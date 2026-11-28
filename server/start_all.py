"""
SemaiKu - start_all.py
======================
Launcher terpadu:
  1. Menjalankan FastAPI / Uvicorn di port 8000.
  2. Menjalankan Cloudflare Tunnel (cloudflared) dan menangkap URL publik-nya.
  3. Mempublish URL tersebut ke MQTT EMQX Cloud (topik semaiku/config/server_url,
     retain=True, qos=1) agar aplikasi Flutter menerimanya secara otomatis.

Jalankan dengan:
    python start_all.py

Tekan Ctrl+C untuk berhenti dengan bersih.
"""

import os
import re
import subprocess
import sys
import threading
import time

# ── Pastikan paho-mqtt terinstal ────────────────────────────────────────────
try:
    import paho.mqtt.client as mqtt
except ImportError:
    print("[!] paho-mqtt belum terinstal. Menginstal secara otomatis...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "paho-mqtt"])
    import paho.mqtt.client as mqtt

# ─────────────────────────────────────────────────────────────────────────────
#  KONFIGURASI  — Ambil identik dari mqtt_service.dart
# ─────────────────────────────────────────────────────────────────────────────
MQTT_HOST = "z101725a.ala.asia-southeast1.emqxsl.com"
MQTT_PORT = 8883          # TLS/SSL
MQTT_USER = "Semaiku"
MQTT_PASS = "semaiku123"
MQTT_TOPIC_SERVER_URL = "semaiku/config/server_url"

CLOUDFLARED_EXE = r"D:\cloudflared\cloudflared.exe"
UVICORN_CMD = [sys.executable, "-m", "uvicorn", "api_server:app",
               "--host", "0.0.0.0", "--port", "8000"]

# Regex untuk URL trycloudflare
_CF_URL_RE = re.compile(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com')

# ─────────────────────────────────────────────────────────────────────────────
#  GLOBAL STATE
# ─────────────────────────────────────────────────────────────────────────────
_procs: list[subprocess.Popen] = []
_tunnel_url: str | None = None
_url_found_event = threading.Event()


# ─────────────────────────────────────────────────────────────────────────────
#  MQTT PUBLISH
# ─────────────────────────────────────────────────────────────────────────────
def _publish_url_to_mqtt(url: str) -> None:
    """Hubungkan ke EMQX Cloud dan publish URL tunnel sekali pakai (retain=True)."""
    print(f"\n📡 [MQTT] Menghubungkan ke {MQTT_HOST}:{MQTT_PORT} ...")

    client = mqtt.Client(client_id="semaiku_server_launcher", protocol=mqtt.MQTTv311)
    client.tls_set()  # gunakan TLS default (port 8883)
    client.username_pw_set(MQTT_USER, MQTT_PASS)

    connected = threading.Event()
    published = threading.Event()

    def on_connect(c, userdata, flags, rc):
        if rc == 0:
            print("📡 [MQTT] Terhubung ke EMQX Cloud!")
            connected.set()
        else:
            print(f"📡 [MQTT] Gagal terhubung, kode: {rc}")

    def on_publish(c, userdata, mid):
        print(f"✅ [MQTT] URL berhasil dipublish ke topik '{MQTT_TOPIC_SERVER_URL}'")
        print(f"         URL Cloudflare: {url}")
        print("         Aplikasi Flutter akan menerima URL ini secara otomatis.\n")
        published.set()

    client.on_connect = on_connect
    client.on_publish = on_publish

    try:
        client.connect(MQTT_HOST, MQTT_PORT, keepalive=30)
        client.loop_start()

        if not connected.wait(timeout=10):
            print("⚠️  [MQTT] Timeout saat menghubungkan ke broker.")
            client.loop_stop()
            return

        client.publish(
            topic=MQTT_TOPIC_SERVER_URL,
            payload=url,
            qos=1,
            retain=True,
        )

        published.wait(timeout=10)
        time.sleep(0.5)   # beri waktu broker memproses

    except Exception as exc:
        print(f"⚠️  [MQTT] Error: {exc}")
    finally:
        client.loop_stop()
        client.disconnect()


# ─────────────────────────────────────────────────────────────────────────────
#  BACA OUTPUT CLOUDFLARED
# ─────────────────────────────────────────────────────────────────────────────
def _stream_cloudflared(proc: subprocess.Popen) -> None:
    """Baca stdout+stderr cloudflared secara realtime, tangkap URL tunnel."""
    global _tunnel_url

    def _read_stream(stream):
        global _tunnel_url
        for raw_line in stream:
            try:
                line = raw_line.decode("utf-8", errors="replace").rstrip()
            except Exception:
                continue

            print(f"[cloudflared] {line}")

            if _tunnel_url is None:
                match = _CF_URL_RE.search(line)
                if match:
                    _tunnel_url = match.group(0)
                    print(f"\n🌐 URL Cloudflare Tunnel terdeteksi: {_tunnel_url}")
                    _url_found_event.set()
                    # Publish ke MQTT di thread terpisah agar tidak memblokir pembacaan log
                    threading.Thread(
                        target=_publish_url_to_mqtt,
                        args=(_tunnel_url,),
                        daemon=True,
                    ).start()

    t_out = threading.Thread(target=_read_stream, args=(proc.stdout,), daemon=True)
    t_err = threading.Thread(target=_read_stream, args=(proc.stderr,), daemon=True)
    t_out.start()
    t_err.start()


# ─────────────────────────────────────────────────────────────────────────────
#  SHUTDOWN BERSIH
# ─────────────────────────────────────────────────────────────────────────────
def _shutdown() -> None:
    print("\n\n🛑 Menghentikan semua proses...")
    for proc in _procs:
        try:
            proc.terminate()
        except Exception:
            pass
    for proc in _procs:
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
    print("👋 Semua proses berhasil dihentikan.")


# ─────────────────────────────────────────────────────────────────────────────
#  ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    print("=" * 65)
    print("  🌿 SemaiKu AI Server Launcher (FastAPI + Cloudflare Tunnel)")
    print("=" * 65)

    # 1. Jalankan Uvicorn / FastAPI
    print("\n▶ Menjalankan FastAPI (Uvicorn) di http://0.0.0.0:8000 ...")
    uvicorn_proc = subprocess.Popen(
        UVICORN_CMD,
        cwd=script_dir,
        stdout=None,   # tampil langsung di terminal
        stderr=None,
    )
    _procs.append(uvicorn_proc)
    time.sleep(2)   # beri waktu server mulai

    # 2. Jalankan Cloudflare Tunnel
    if not os.path.isfile(CLOUDFLARED_EXE):
        print(f"\n⚠️  cloudflared.exe tidak ditemukan di: {CLOUDFLARED_EXE}")
        print("   Download dari https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/")
        print("   Lalu letakkan di D:\\cloudflared\\cloudflared.exe\n")
    else:
        print(f"\n▶ Menjalankan Cloudflare Tunnel (cloudflared) ...")
        cf_proc = subprocess.Popen(
            [CLOUDFLARED_EXE, "tunnel", "--url", "http://127.0.0.1:8000"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=script_dir,
        )
        _procs.append(cf_proc)
        _stream_cloudflared(cf_proc)

        print("⏳ Menunggu URL Cloudflare Tunnel...")
        _url_found_event.wait(timeout=60)

        if _tunnel_url is None:
            print("⚠️  URL Cloudflare tidak terdeteksi dalam 60 detik. Periksa log cloudflared di atas.")

    print("\n" + "-" * 65)
    print("  Server berjalan. Tekan Ctrl+C untuk berhenti.")
    print("-" * 65 + "\n")

    try:
        # Tunggu sampai Ctrl+C
        while True:
            time.sleep(1)
            # Restart otomatis jika uvicorn mati
            if uvicorn_proc.poll() is not None:
                print("⚠️  Uvicorn berhenti. Restart...")
                uvicorn_proc = subprocess.Popen(UVICORN_CMD, cwd=script_dir)
                _procs[0] = uvicorn_proc
    except KeyboardInterrupt:
        _shutdown()


if __name__ == "__main__":
    main()
