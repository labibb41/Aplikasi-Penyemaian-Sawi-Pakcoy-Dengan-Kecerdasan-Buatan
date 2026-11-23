import os
import base64
import warnings
warnings.filterwarnings("ignore")
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'

import cv2
import numpy as np
import socket
import threading
from PIL import Image
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
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
YOLO_SAMPING_WEIGHTS = os.path.join(BASE_DIR, "exp_pakcoy_samping_yolo26_seg_v1", "weights", "best.pt")

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

print("⏳ Memuat model YOLO Pandangan Atas...")
yolo_model = YOLO(YOLO_WEIGHTS)
print("✅ YOLO Atas Model Loaded!")

yolo_samping_model = None
if os.path.exists(YOLO_SAMPING_WEIGHTS):
    print("⏳ Memuat model YOLO Pandangan Samping...")
    yolo_samping_model = YOLO(YOLO_SAMPING_WEIGHTS)
    print("✅ YOLO Samping Model Loaded!")
else:
    print(f"⚠️ Model Samping tidak ditemukan di: {YOLO_SAMPING_WEIGHTS}")

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

def classify_crop_physiological(crop_bgr: np.ndarray,
                                 p_berat: float, p_ringan: float, p_normal: float,
                                 bbox: tuple = None, kotak_box: tuple = None) -> tuple[str, float]:
    """
    Klasifikasi Fisiologis Tanaman Pakcoy:
    - Hijau dominan (>=35%) + tidak rebah/menjulang -> NORMAL (override model bias)
    - Batang rebah menyamping -> ETIOLASI BERAT
    - Menjulang tinggi -> ETIOLASI (ringan/berat)
    - Batang pucat/putih tanpa klorofil -> ETIOLASI
    - Hijau cukup + model p_normal >= 0.20 -> NORMAL
    """
    # 1. Analisis Ukuran & Proporsi (Menjulang / Merebah)
    is_menjulang = False
    is_merebah = False
    if bbox is not None:
        bw = max(1, bbox[2] - bbox[0])
        bh = max(1, bbox[3] - bbox[1])
        aspect = max(bw, bh) / max(1, min(bw, bh))

        if kotak_box is not None:
            kw = max(1, kotak_box[2] - kotak_box[0])
            kh = max(1, kotak_box[3] - kotak_box[1])
            if bw >= 1.05 * kw:
                is_merebah = True
            elif bh >= 1.05 * kh:
                is_menjulang = True

        if aspect >= 1.50 and bh >= 50:
            is_menjulang = True
        elif aspect >= 1.50 and bw >= 45:
            is_merebah = True

    # 2. Analisis Warna (Batang Hijau vs Putih Pucat Kutilang)
    green_ratio = 0.0
    has_green = False
    is_pale = False
    if crop_bgr is not None and crop_bgr.size > 0:
        hsv_c = cv2.cvtColor(crop_bgr, cv2.COLOR_BGR2HSV)
        green_mask = cv2.inRange(hsv_c, (25, 45, 45), (85, 255, 255))
        green_ratio = float(np.mean(green_mask > 0))
        has_green = green_ratio >= 0.10
        is_pale = float(np.mean(cv2.inRange(hsv_c, (0, 0, 165), (180, 45, 255)) > 0)) >= 0.08

    # 3. KEPUTUSAN KELAS FISIOLOGIS
    # A. HIJAU DOMINAN (>= 35%) + TIDAK REBAH/MENJULANG -> PASTI NORMAL
    if green_ratio >= 0.35 and not is_merebah and not is_menjulang:
        return "normal", max(p_normal, 0.80)

    # B. JIKA SUDAH MEREBAH -> ETIOLASI BERAT
    elif is_merebah:
        return "etiolasi_berat", max(p_berat, 0.75)

    # C. JIKA MENJULANG TINGGI -> ETIOLASI RINGAN / BERAT
    elif is_menjulang:
        if p_berat >= 0.50:
            return "etiolasi_berat", p_berat
        else:
            return "etiolasi_ringan", max(p_ringan, 0.70)

    # D. JIKA BATANG PUTIH PUCAT -> ETIOLASI
    elif is_pale and green_ratio < 0.30:
        lbl = "etiolasi_berat" if p_berat >= p_ringan else "etiolasi_ringan"
        return lbl, max(p_berat, p_ringan)

    # E. HIJAU CUKUP + MODEL SETUJU NORMAL -> NORMAL
    elif has_green and p_normal >= 0.20:
        return "normal", max(p_normal, 0.75)

    # F. MODEL SANGAT YAKIN ETIOLASI DAN TIDAK TERLALU HIJAU -> ETIOLASI
    elif p_berat >= 0.80 and green_ratio < 0.40:
        return "etiolasi_berat", p_berat
    elif p_ringan >= 0.80 and green_ratio < 0.40:
        return "etiolasi_ringan", p_ringan

    # G. DEFAULT ARGMAX
    else:
        max_idx = int(np.argmax([p_berat, p_ringan, p_normal]))
        return CLASS_NAMES[max_idx], float([p_berat, p_ringan, p_normal][max_idx])

def predict_single_crop(crop_bgr: np.ndarray, bbox: tuple = None, kotak_box: tuple = None) -> tuple[str, float]:
    """Prediksi satu potongan bibit dengan MobileNetV2 + Fisiologi Tanaman."""
    x = preprocess_crop(crop_bgr)
    preds = mob_model.predict(x, verbose=0)[0]
    p_berat, p_ringan, p_normal = float(preds[0]), float(preds[1]), float(preds[2])
    return classify_crop_physiological(crop_bgr, p_berat, p_ringan, p_normal, bbox=bbox, kotak_box=kotak_box)

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
        "model_yolo_top": "exp_pakcoy_yolo26_seg_v4",
        "model_yolo_side": "exp_pakcoy_samping_yolo26_seg_v1" if yolo_samping_model else None,
        "model_mobilenet": os.path.basename(MOB_WEIGHTS) if MOB_WEIGHTS else None,
        "mode": "flexible_framing (Full Tray, Partial, or Close-Up)",
        "supports": ["top_view", "side_view"]
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
        yolo_results = yolo_model(img_bgr, conf=0.15, iou=0.45, verbose=False)[0]
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

        # Saring box bibit kanopi daun (hilangkan duplikasi tumpang tindih)
        if bibit_dets:
            bibit_dets = select_best_leaf_boxes(img_bgr, bibit_dets)

        # ── 2. ANALISIS KOTAK TRAY & BIJI TERDETEKSI ──
        vis_bgr = img_bgr.copy()
        COLOR_KOTAK_ISI   = (255, 180, 0)    # Cyan / Biru Muda untuk slot terisi (sesuai referensi)
        COLOR_KOTAK_EMPTY = (120, 120, 120)  # Abu-abu untuk slot kosong
        COLOR_EMPTY_TXT   = (180, 180, 180)  # Abu-abu terang untuk teks EMPTY

        is_tray = len(kotak_dets) >= 2
        valid_bibit = []
        is_fallback_closeup = False

        if is_tray:
            # Urutkan slot kisi tray dari atas ke bawah, kiri ke kanan
            kotak_dets = sorted(kotak_dets, key=lambda b: (b[1] // 40, b[0]))
            tray_slots = []
            used_bibit = set()

            for s_idx, k_box in enumerate(kotak_dets):
                kx1, ky1, kx2, ky2 = k_box[:4]
                found_bibit = None

                for b_idx, b_box in enumerate(bibit_dets):
                    if b_idx in used_bibit:
                        continue
                    bx1, by1, bx2, by2 = b_box[:4]
                    bcx, bcy = (bx1 + bx2) / 2, (by1 + by2) / 2

                    if kx1 <= bcx <= kx2 and ky1 <= bcy <= ky2:
                        found_bibit = b_box
                        used_bibit.add(b_idx)
                        break

                slot_info = {
                    "slot_idx": s_idx + 1,
                    "kotak_box": (kx1, ky1, kx2, ky2),
                    "has_bibit": found_bibit is not None,
                    "bibit_box": found_bibit
                }
                tray_slots.append(slot_info)

                if found_bibit is not None:
                    valid_bibit.append(found_bibit)
                    # Gambar kotak kisi tray terisi (Cyan)
                    cv2.rectangle(vis_bgr, (kx1, ky1), (kx2, ky2), COLOR_KOTAK_ISI, 1)
                    cv2.putText(vis_bgr, f"#{s_idx + 1}", (kx1 + 2, ky1 + 10),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.28, COLOR_KOTAK_ISI, 1, cv2.LINE_AA)
                else:
                    # Gambar kotak kisi tray kosong (Abu-abu + Label EMPTY)
                    cv2.rectangle(vis_bgr, (kx1, ky1), (kx2, ky2), COLOR_KOTAK_EMPTY, 1)
                    cv2.putText(vis_bgr, f"#{s_idx + 1}", (kx1 + 2, ky1 + 10),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.28, COLOR_KOTAK_EMPTY, 1, cv2.LINE_AA)
                    cx, cy = (kx1 + kx2) // 2, (ky1 + ky2) // 2
                    cv2.putText(vis_bgr, "EMPTY", (cx - 16, cy + 4),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.30, COLOR_EMPTY_TXT, 1, cv2.LINE_AA)

            # Tambahkan juga bibit di luar slot kisi tray jika ada
            for b_idx, b_box in enumerate(bibit_dets):
                if b_idx not in used_bibit:
                    valid_bibit.append(b_box)

            total_kotak = len(kotak_dets)
            biji_terdeteksi = len(valid_bibit)
            kotak_kosong = max(0, total_kotak - len(used_bibit))
            daya_kecambah = round((len(used_bibit) / total_kotak * 100), 1) if total_kotak > 0 else 100.0
        else:
            # Fallback fleksibel jika memotret 1 bibit dekat (close-up) atau tanpa kisi tray
            if not bibit_dets:
                is_fallback_closeup = True
                margin_x = int(w * 0.08)
                margin_y = int(h * 0.08)
                bibit_dets = [(margin_x, margin_y, w - margin_x, h - margin_y, 0.95, 0)]

            valid_bibit = bibit_dets
            total_kotak = len(valid_bibit)
            biji_terdeteksi = len(valid_bibit)
            kotak_kosong = 0
            daya_kecambah = 100.0

        # ── 3. KLASIFIKASI DENGAN MOBILENETV2 (BATCH INFERENCE CEPAT) ──
        results = []
        counts = {"normal": 0, "etiolasi_ringan": 0, "etiolasi_berat": 0}

        batch_inputs = []
        crops_bgr = []
        clean_valid_bibit = []

        for b in valid_bibit:
            x1, y1, x2, y2, yconf, _ = b
            crop = img_bgr[y1:y2, x1:x2]
            if crop.size == 0 or crop.shape[0] < 4 or crop.shape[1] < 4:
                continue
            crop_rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
            crop_pil = Image.fromarray(crop_rgb).resize(IMG_SIZE)
            arr = np.array(crop_pil, dtype=np.float32) / 255.0
            batch_inputs.append(arr)
            clean_valid_bibit.append(b)
            crops_bgr.append(crop)

        if batch_inputs:
            X_tensor = tf.convert_to_tensor(np.stack(batch_inputs, axis=0), dtype=tf.float32)
            all_preds = mob_model(X_tensor, training=False).numpy()

            for i, (b, crop, preds) in enumerate(zip(clean_valid_bibit, crops_bgr, all_preds), 1):
                x1, y1, x2, y2, yconf, _ = b
                p_berat, p_ringan, p_normal = float(preds[0]), float(preds[1]), float(preds[2])

                # Cari kotak slot tray tempat bibit ini berada (jika ada)
                matched_kotak = None
                for k_box in kotak_dets:
                    kx1, ky1, kx2, ky2 = k_box[:4]
                    bcx, bcy = (x1 + x2) / 2, (y1 + y2) / 2
                    if kx1 <= bcx <= kx2 and ky1 <= bcy <= ky2:
                        matched_kotak = (kx1, ky1, kx2, ky2)
                        break

                label, conf = classify_crop_physiological(
                    crop, p_berat, p_ringan, p_normal,
                    bbox=(x1, y1, x2, y2), kotak_box=matched_kotak
                )

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
            rekomendasi = f"Ditemukan {berat_cnt} bibit kutilang (etiolasi berat) dari {biji_terdeteksi} bibit tumbuh. Segera aktifkan Booster Lampu (Lampu 2) dan dekatkan jarak pencahayaan ke bibit."
        elif ringan_cnt > 0:
            status_overall = "Etiolasi Ringan Terdeteksi"
            rekomendasi = f"Ditemukan {ringan_cnt} bibit mulai kekurangan cahaya. Disarankan menambah durasi masa terang Grow Light sebanyak 1-2 jam."
        else:
            status_overall = "Kondisi Sangat Baik (Normal)"
            rekomendasi = f"Semua {biji_terdeteksi} bibit tumbuh optimal dan sehat ({pct_normal}% normal). Pertahankan siklus terang/gelap serta suhu inkubator saat ini."

        # Encode gambar hasil ke Base64 JPEG
        _, enc_jpg = cv2.imencode(".jpg", vis_bgr, [cv2.IMWRITE_JPEG_QUALITY, 85])
        annotated_b64 = "data:image/jpeg;base64," + base64.b64encode(enc_jpg.tobytes()).decode("ascii")

        return {
            "success": True,
            "framing_type": "Close-Up / Parsial" if is_fallback_closeup or (not is_tray and total <= 3) else "Multi-Bibit / Tray",
            "total_kotak": total_kotak,
            "biji_terdeteksi": biji_terdeteksi,
            "kotak_kosong": kotak_kosong,
            "daya_kecambah": daya_kecambah,
            "total_tanaman": biji_terdeteksi,
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

@app.post("/api/predict/side")
@app.post("/api/predict/samping")
async def predict_side_view(file: UploadFile = File(...), tray_width_cm: float = 66.0):
    """
    Endpoint deteksi & pengukuran tinggi etiolasi bibit pakcoy dari Sisi Samping.
    - YOLO26n-Seg untuk deteksi batang tanaman & batas bawah tray
    - Pengukuran tinggi dalam centimeter (cm) secara presisi
    - Analisis warna pangkal batang (ruang warna HSV)
    """
    if yolo_samping_model is None:
        raise HTTPException(status_code=503, detail="Model sisi samping belum tersedia di server")

    try:
        contents = await file.read()
        nparr = np.frombuffer(contents, np.uint8)
        img_bgr = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if img_bgr is None:
            raise HTTPException(status_code=400, detail="Format gambar tidak valid")

        h_img, w_img = img_bgr.shape[:2]

        # Inferensi YOLO Samping
        results_yolo = yolo_samping_model(img_bgr, conf=0.25, imgsz=640, verbose=False)[0]
        boxes = results_yolo.boxes
        masks = results_yolo.masks

        tanaman_list = []
        tray_box = None

        if boxes is not None and len(boxes) > 0:
            for i, box in enumerate(boxes):
                cls_id = int(box.cls[0])
                cls_name = yolo_samping_model.names.get(cls_id, "")
                conf = float(box.conf[0])
                xyxy = box.xyxy[0].cpu().numpy()
                mask_poly = masks.xy[i] if masks is not None else None

                if "tray" in cls_name.lower():
                    tray_box = xyxy
                elif "batang" in cls_name.lower():
                    tanaman_list.append({
                        "box": xyxy,
                        "conf": conf,
                        "poly": mask_poly
                    })

        if tray_box is not None:
            tx1, ty1, tx2, ty2 = tray_box
            tray_w_px = max(1.0, tx2 - tx1)
            scale_cm_per_px = tray_width_cm / tray_w_px
            baseline_y = ty1
        else:
            scale_cm_per_px = 0.05
            baseline_y = max([t["box"][3] for t in tanaman_list]) if tanaman_list else h_img - 20

        vis_bgr = img_bgr.copy()

        # Gambar 1 Garis Acuan Tunggal Tray Bawah (Garis Baseline 0 cm)
        if tray_box is not None:
            by = int(baseline_y)
            x_start = int(tray_box[0])
            x_end = int(tray_box[2])
            # Garis horizontal batas tray (Merah)
            cv2.line(vis_bgr, (x_start, by), (x_end, by), (0, 0, 255), 2, cv2.LINE_AA)
            # Label teks di bawah garis agar tidak menabrak kotak tanaman
            cv2.putText(vis_bgr, "--- BATAS TRAY (0 cm) ---", (x_start + 6, min(h_img - 6, by + 16)),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.42, (0, 0, 255), 1, cv2.LINE_AA)

        tanaman_list = sorted(tanaman_list, key=lambda t: t["box"][0])
        results_detail = []
        counts = {"normal": 0, "etiolasi_ringan": 0, "etiolasi_berat": 0}
        all_heights = []

        for idx, t in enumerate(tanaman_list, 1):
            x1, y1, x2, y2 = map(int, t["box"])
            poly = t["poly"]

            pucuk_y = int(np.min(poly[:, 1])) if poly is not None and len(poly) > 0 else y1
            pangkal_y = int(baseline_y) if baseline_y > pucuk_y else y2

            tinggi_px = max(1, pangkal_y - pucuk_y)
            tinggi_cm = round(float(tinggi_px * scale_cm_per_px), 2)
            all_heights.append(tinggi_cm)

            # Analisis Warna Batang (40% bawah)
            stem_y_start = int(pucuk_y + 0.60 * tinggi_px)
            stem_y_end = min(h_img, pangkal_y)
            stem_crop = img_bgr[stem_y_start:stem_y_end, max(0, x1):min(w_img, x2)]

            is_pale = False
            color_desc = "Hijau"
            if stem_crop.size > 0:
                hsv = cv2.cvtColor(stem_crop, cv2.COLOR_BGR2HSV)
                pale_mask = cv2.inRange(hsv, (0, 0, 150), (180, 55, 255))
                green_mask = cv2.inRange(hsv, (25, 40, 40), (85, 255, 255))
                pale_ratio = float(np.mean(pale_mask > 0))
                green_ratio = float(np.mean(green_mask > 0))

                if pale_ratio >= 0.25 and green_ratio < 0.20:
                    is_pale = True
                    color_desc = f"Pucat ({pale_ratio:.0%})"
                else:
                    color_desc = f"Hijau ({green_ratio:.0%})"

            if tinggi_cm <= 10.0:
                status = "Normal"
                color_bgr = (0, 220, 0)
                counts["normal"] += 1
            elif is_pale:
                status = "Etiolasi Berat"
                color_bgr = (0, 0, 230)
                counts["etiolasi_berat"] += 1
            else:
                status = "Etiolasi Ringan"
                color_bgr = (0, 165, 255)
                counts["etiolasi_ringan"] += 1

            # Gambar Kotak Bounding Box
            cv2.rectangle(vis_bgr, (x1, y1), (x2, y2), color_bgr, 2)

            # Garis ukur tinggi
            cx = int((x1 + x2) / 2)
            cv2.line(vis_bgr, (cx, pangkal_y), (cx, pucuk_y), (255, 255, 255), 1, cv2.LINE_AA)
            cv2.circle(vis_bgr, (cx, pucuk_y), 3, (0, 255, 255), -1)

            # Badge Label di atas kotak
            label_txt = f"{status} {tinggi_cm:.1f}cm"
            (tw, th), _ = cv2.getTextSize(label_txt, cv2.FONT_HERSHEY_SIMPLEX, 0.45, 1)
            badge_top = max(0, y1 - th - 6)
            cv2.rectangle(vis_bgr, (x1, badge_top), (x1 + tw + 6, y1), color_bgr, -1)
            text_color = (0, 0, 0) if status == "Etiolasi Ringan" else (255, 255, 255)
            cv2.putText(vis_bgr, label_txt, (x1 + 3, y1 - 3), cv2.FONT_HERSHEY_SIMPLEX, 0.45, text_color, 1, cv2.LINE_AA)

            results_detail.append({
                "id": idx,
                "status": status,
                "tinggi_cm": tinggi_cm,
                "tinggi_px": tinggi_px,
                "warna_batang": color_desc,
                "bbox": [x1, y1, x2, y2]
            })

        total_tanaman = len(results_detail)
        avg_height = round(float(np.mean(all_heights)), 1) if all_heights else 0.0
        normal_cnt = counts["normal"]
        ringan_cnt = counts["etiolasi_ringan"]
        berat_cnt = counts["etiolasi_berat"]

        pct_normal = round((normal_cnt / total_tanaman * 100), 1) if total_tanaman > 0 else 0.0
        pct_etiolasi = round(100.0 - pct_normal, 1)

        if berat_cnt > 0:
            status_overall = "Etiolasi Berat Terdeteksi (Kutilang)"
            rekomendasi = f"Ditemukan {berat_cnt} batang meninggi pucat (>10 cm). Batang rapuh, segera turunkan intensitas jarak lampu dan berikan sirkulasi udara."
        elif ringan_cnt > 0:
            status_overall = "Etiolasi Ringan Terdeteksi"
            rekomendasi = f"Ditemukan {ringan_cnt} batang mulai meninggi (>10 cm) namun masih hijau. Tambahkan durasi penyinaran 1-2 jam."
        else:
            status_overall = "Batang Kokoh (Normal)"
            rekomendasi = f"Semua {total_tanaman} batang tanaman tumbuh proporsional (<=10 cm, rata-rata {avg_height} cm). Kondisi pencahayaan saat ini sangat tepat."

        _, enc_jpg = cv2.imencode(".jpg", vis_bgr, [cv2.IMWRITE_JPEG_QUALITY, 85])
        annotated_b64 = "data:image/jpeg;base64," + base64.b64encode(enc_jpg.tobytes()).decode("ascii")

        return {
            "success": True,
            "total_tanaman": total_tanaman,
            "biji_terdeteksi": total_tanaman,
            "tinggi_rata_rata": avg_height,
            "normal": normal_cnt,
            "etiolasi_ringan": ringan_cnt,
            "etiolasi_berat": berat_cnt,
            "persentase_normal": pct_normal,
            "persentase_etiolasi": pct_etiolasi,
            "status_keseluruhan": status_overall,
            "rekomendasi": rekomendasi,
            "annotated_image": annotated_b64,
            "detail_tanaman": results_detail
        }

    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    print("\n🌿 Menjalankan SemaiKu AI Server pada port 8000...")
    uvicorn.run("api_server:app", host="0.0.0.0", port=8000, reload=True)
