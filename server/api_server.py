import os
import sys
import io
import base64
import warnings
warnings.filterwarnings("ignore")
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'

import cv2
import numpy as np
import socket
import threading
from PIL import Image
from collections import Counter
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import tensorflow as tf
from ultralytics import YOLO

# ─────────────────────────────────────────────────────────────
#  UDP AUTO-DISCOVERY BEACON (DETEKSI OTOMATIS OLEH HP)
# ─────────────────────────────────────────────────────────────
def start_discovery_beacon(http_port: int = 8000, udp_port: int = 8888):
    """Mendengarkan broadcast dari HP dan menjawab dengan alamat/port server."""
    def listener():
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(('', udp_port))
            print(f"📡 UDP Auto-Discovery aktif di port {udp_port} (HP akan otomatis menemukan laptop)")
            while True:
                try:
                    data, addr = sock.recvfrom(1024)
                    msg = data.decode('utf-8', errors='ignore').strip()
                    if 'SEMAIKU_DISCOVER' in msg:
                        reply = f"SEMAIKU_OFFER:{http_port}".encode('utf-8')
                        sock.sendto(reply, addr)
                except Exception:
                    pass
        except Exception as e:
            print(f"⚠️ Warning UDP Discovery: {e}")

    t = threading.Thread(target=listener, daemon=True)
    t.start()

start_discovery_beacon(http_port=8000, udp_port=8888)

# ─────────────────────────────────────────────────────────────
#  INISIALISASI & KONFIGURASI PATH MODEL
# ─────────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

YOLO_WEIGHTS = os.path.join(BASE_DIR, "exp_pakcoy_yolo26_seg_v4", "weights", "best.pt")

MOBILENET_CANDIDATES = [
    os.path.join(BASE_DIR, "mobilenetv2_pakcoy_opt.h5"),
    os.path.join(BASE_DIR, "mobilenetv2_pakcoy_murni.h5"),
    os.path.join(BASE_DIR, "mobilenetv2_pakcoy_augmented.h5"),
]

MOB_WEIGHTS = None
for cand in MOBILENET_CANDIDATES:
    if os.path.exists(cand):
        MOB_WEIGHTS = cand
        break

print("⏳ Memuat model YOLO...")
yolo_model = YOLO(YOLO_WEIGHTS)
print("✅ YOLO Model Loaded!")

print(f"⏳ Memuat MobileNetV2: {os.path.basename(MOB_WEIGHTS)}...")
mob_model = tf.keras.models.load_model(MOB_WEIGHTS)
print("✅ MobileNetV2 Model Loaded!")

# Konfigurasi
IMG_SIZE = (224, 224)
CLASS_NAMES = ["etiolasi_berat", "etiolasi_ringan", "normal"]

THRESH_NORMAL = 0.30
THRESH_ETIOLASI_RINGAN = 0.70
THRESH_ETIOLASI_BERAT = 0.65

CLASS_COLORS_RGB = {
    "normal": (46, 204, 113),       # Hijau segar
    "etiolasi_ringan": (243, 156, 18),# Oranye
    "etiolasi_berat": (231, 76, 60),  # Merah
}

CLASS_DISPLAY = {
    "normal": "Normal",
    "etiolasi_ringan": "Et. Ringan",
    "etiolasi_berat": "Et. Berat",
}

# ─────────────────────────────────────────────────────────────
#  FASTAPI APPLICATION
# ─────────────────────────────────────────────────────────────
app = FastAPI(
    title="SemaiKu AI Vision Service",
    description="Layanan Deteksi & Monitoring Etiolasi Bibit Pakcoy",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def preprocess_crop(crop_bgr: np.ndarray) -> np.ndarray:
    crop_rgb = cv2.cvtColor(crop_bgr, cv2.COLOR_BGR2RGB)
    crop_pil = Image.fromarray(crop_rgb).resize(IMG_SIZE)
    arr = np.array(crop_pil, dtype=np.float32) / 255.0
    return np.expand_dims(arr, axis=0)

def predict_single_crop(crop_bgr: np.ndarray) -> tuple[str, float]:
    """Prediksi satu potongan bibit dengan MobileNetV2 + HSV Green Check."""
    x = preprocess_crop(crop_bgr)
    preds = mob_model.predict(x, verbose=0)[0]
    p_berat, p_ringan, p_normal = float(preds[0]), float(preds[1]), float(preds[2])

    hsv = cv2.cvtColor(crop_bgr, cv2.COLOR_BGR2HSV)
    mask = cv2.inRange(hsv, (25, 35, 35), (85, 255, 255))
    has_good_leaf = np.mean(mask > 0) >= 0.08

    if p_berat >= THRESH_ETIOLASI_BERAT and p_berat > p_normal and not has_good_leaf:
        return "etiolasi_berat", p_berat
    elif p_ringan >= THRESH_ETIOLASI_RINGAN and p_ringan > p_normal and not has_good_leaf:
        return "etiolasi_ringan", p_ringan
    else:
        conf = max(p_normal, 0.88) if has_good_leaf else p_normal
        return "normal", conf

def select_best_leaf_boxes(orig_bgr, bibit_boxes):
    """Filter kanopi daun agar tidak tumpang tindih."""
    if not bibit_boxes:
        return []
    scored_boxes = []
    for b in bibit_boxes:
        x1, y1, x2, y2, yconf, ycls = b
        crop = orig_bgr[y1:y2, x1:x2]
        if crop.size == 0:
            continue
        hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
        mask = cv2.inRange(hsv, (25, 35, 35), (85, 255, 255))
        green_ratio = np.mean(mask > 0)
        w_b = max(1, x2 - x1)
        h_b = max(1, y2 - y1)
        aspect = min(w_b, h_b) / max(w_b, h_b)
        score = green_ratio * 1.5 + aspect * 0.5
        scored_boxes.append((b, score))

    scored_boxes.sort(key=lambda x: x[1], reverse=True)
    kept = []
    for box_a, _ in scored_boxes:
        ax1, ay1, ax2, ay2, _, _ = box_a
        area_a = (ax2 - ax1) * (ay2 - ay1)
        overlap = False
        for box_b in kept:
            bx1, by1, bx2, by2, _, _ = box_b
            area_b = (bx2 - bx1) * (by2 - by1)
            ix1, iy1 = max(ax1, bx1), max(ay1, by1)
            ix2, iy2 = min(ax2, bx2), min(ay2, by2)
            iw, ih = max(0, ix2 - ix1), max(0, iy2 - iy1)
            inter = iw * ih
            iou = inter / float(area_a + area_b - inter + 1e-6)
            if iou > 0.30:
                overlap = True
                break
        if not overlap:
            kept.append(box_a)
    return kept

@app.get("/")
@app.get("/api/health")
def health_check():
    return {
        "status": "online",
        "app": "SemaiKu AI Server",
        "model_yolo": "exp_pakcoy_yolo26_seg_v4",
        "model_mobilenet": os.path.basename(MOB_WEIGHTS) if MOB_WEIGHTS else None,
        "mode": "flexible_framing (Full Tray, Partial, or Close-Up)"
    }

@app.post("/api/predict/top")
async def predict_top_view(file: UploadFile = File(...)):
    """
    Endpoint fleksibel untuk mendeteksi etiolasi bibit pakcoy dari Sisi Atas.
    Bisa memproses:
      - 1 Tray Penuh
      - Sebagian Tray (Cluster 2-10 bibit)
      - Close-Up 1 bibit tunggal
    """
    try:
        contents = await file.read()
        nparr = np.frombuffer(contents, np.uint8)
        img_bgr = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if img_bgr is None:
            raise HTTPException(status_code=400, detail="Format gambar tidak valid")

        h, w = img_bgr.shape[:2]

        # ── 1. INFERENSI YOLO ──
        yolo_results = yolo_model(img_bgr, conf=0.20, iou=0.45, verbose=False)[0]
        boxes = yolo_results.boxes

        detections = []
        if boxes is not None and len(boxes) > 0:
            for box in boxes:
                x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
                x1, y1 = max(0, x1), max(0, y1)
                x2, y2 = min(w, x2), min(h, y2)
                yconf = float(box.conf[0])
                ycls = int(box.cls[0]) if box.cls is not None else 0
                detections.append((x1, y1, x2, y2, yconf, ycls))

        bibit_dets = [d for d in detections if d[5] == 0]
        kotak_dets = [d for d in detections if d[5] == 1]

        # Jika ada deteksi tapi tidak ada label 0 terpisah
        if detections and not bibit_dets:
            bibit_dets = detections

        # Saring box bibit kanopi daun
        if bibit_dets:
            bibit_dets = select_best_leaf_boxes(img_bgr, bibit_dets)

        # ── 2. FALLBACK FLEKSIBEL (JIKA FOTO CLOSE-UP / HANYA 1 BIBIT) ──
        # Jika pengguna memotret 1 bibit dari dekat dan YOLO tidak memicu kotak tray
        is_fallback_closeup = False
        if not bibit_dets:
            is_fallback_closeup = True
            # Anggap gambar fokus pada bibit (area 80% tengah atau full image)
            margin_x = int(w * 0.08)
            margin_y = int(h * 0.08)
            fx1, fy1 = margin_x, margin_y
            fx2, fy2 = w - margin_x, h - margin_y
            bibit_dets = [(fx1, fy1, fx2, fy2, 0.95, 0)]

        # ── 3. KLASIFIKASI DENGAN MOBILENETV2 (BATCH INFERENCE CEPAT) ──
        results = []
        counts = {"normal": 0, "etiolasi_ringan": 0, "etiolasi_berat": 0}
        vis_bgr = img_bgr.copy()

        # Gambar slot kisi tray jika ada (warna cyan)
        for idx, (kx1, ky1, kx2, ky2, _, _) in enumerate(kotak_dets):
            cv2.rectangle(vis_bgr, (kx1, ky1), (kx2, ky2), (255, 180, 0), 1)

        valid_bibit = []
        batch_inputs = []
        crops_bgr = []

        for b in bibit_dets:
            x1, y1, x2, y2, yconf, _ = b
            crop = img_bgr[y1:y2, x1:x2]
            if crop.size == 0:
                continue
            crop_rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
            crop_pil = Image.fromarray(crop_rgb).resize(IMG_SIZE)
            arr = np.array(crop_pil, dtype=np.float32) / 255.0
            batch_inputs.append(arr)
            valid_bibit.append(b)
            crops_bgr.append(crop)

        if batch_inputs:
            X_tensor = tf.convert_to_tensor(np.stack(batch_inputs, axis=0), dtype=tf.float32)
            all_preds = mob_model(X_tensor, training=False).numpy()

            for i, (b, crop, preds) in enumerate(zip(valid_bibit, crops_bgr, all_preds), 1):
                x1, y1, x2, y2, yconf, _ = b
                p_berat, p_ringan, p_normal = float(preds[0]), float(preds[1]), float(preds[2])

                hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
                mask = cv2.inRange(hsv, (25, 35, 35), (85, 255, 255))
                has_good_leaf = np.mean(mask > 0) >= 0.08

                if p_berat >= THRESH_ETIOLASI_BERAT and p_berat > p_normal and not has_good_leaf:
                    label, conf = "etiolasi_berat", p_berat
                elif p_ringan >= THRESH_ETIOLASI_RINGAN and p_ringan > p_normal and not has_good_leaf:
                    label, conf = "etiolasi_ringan", p_ringan
                else:
                    label, conf = "normal", max(p_normal, 0.88) if has_good_leaf else p_normal

                counts[label] += 1
                disp_label = CLASS_DISPLAY.get(label, label)
                color_rgb = CLASS_COLORS_RGB.get(label, (46, 204, 113))
                color_bgr = (color_rgb[2], color_rgb[1], color_rgb[0])

                # Gambar bounding box bibit
                cv2.rectangle(vis_bgr, (x1, y1), (x2, y2), color_bgr, 2)

                # Badge teks label di atas kotak
                txt = f"{disp_label} {conf:.0%}"
                (tw, th), _ = cv2.getTextSize(txt, cv2.FONT_HERSHEY_SIMPLEX, 0.45, 1)
                badge_top = max(0, y1 - th - 6)
                cv2.rectangle(vis_bgr, (x1, badge_top), (x1 + tw + 6, y1), color_bgr, -1)
                text_color = (0, 0, 0) if label == "etiolasi_ringan" else (255, 255, 255)
                cv2.putText(vis_bgr, txt, (x1 + 3, y1 - 4),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.45, text_color, 1, cv2.LINE_AA)

                results.append({
                    "id": i,
                    "label": label,
                    "display_label": disp_label,
                    "confidence": round(conf, 4),
                    "bbox": [x1, y1, x2, y2]
                })

        total = len(results)
        normal_cnt = counts["normal"]
        ringan_cnt = counts["etiolasi_ringan"]
        berat_cnt = counts["etiolasi_berat"]

        pct_normal = round((normal_cnt / total * 100), 1) if total > 0 else 0.0

        # Ringkasan status keseluruhan & Rekomendasi Pintar SemaiKu
        if berat_cnt > 0:
            status_overall = "Etiolasi Berat Terdeteksi"
            rekomendasi = f"Ditemukan {berat_cnt} bibit kutilang (etiolasi berat). Segera aktifkan Booster Lampu (Lampu 2) dan dekatkan jarak pencahayaan ke bibit."
        elif ringan_cnt > 0:
            status_overall = "Etiolasi Ringan Terdeteksi"
            rekomendasi = f"Ditemukan {ringan_cnt} bibit mulai kekurangan cahaya. Disarankan menambah durasi masa terang Grow Light sebanyak 1-2 jam."
        else:
            status_overall = "Kondisi Sangat Baik (Normal)"
            rekomendasi = "Semua bibit tumbuh optimal dan sehat. Pertahankan siklus terang/gelap serta suhu inkubator saat ini."

        # Encode gambar hasil ke Base64 JPEG
        _, enc_jpg = cv2.imencode(".jpg", vis_bgr, [cv2.IMWRITE_JPEG_QUALITY, 85])
        annotated_b64 = "data:image/jpeg;base64," + base64.b64encode(enc_jpg.tobytes()).decode("ascii")

        return {
            "success": True,
            "framing_type": "Close-Up / Parsial" if is_fallback_closeup or total <= 3 else "Multi-Bibit / Tray",
            "total_tanaman": total,
            "normal": normal_cnt,
            "etiolasi_ringan": ringan_cnt,
            "etiolasi_berat": berat_cnt,
            "persentase_normal": pct_normal,
            "status_keseluruhan": status_overall,
            "rekomendasi": rekomendasi,
            "annotated_image": annotated_b64,
            "detail_tanaman": results
        }

    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    print("\n🌿 Menjalankan SemaiKu AI Server pada port 8000...")
    uvicorn.run("api_server:app", host="0.0.0.0", port=8000, reload=True)
