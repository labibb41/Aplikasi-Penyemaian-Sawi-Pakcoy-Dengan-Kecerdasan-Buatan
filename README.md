# SemaiKu 🌱

**SemaiKu** adalah aplikasi IoT cerdas berbasis **Flutter (Material 3)** yang dirancang untuk memantau, mengontrol, dan mendeteksi etiolasi pada proses penyemaian bibit tanaman secara otomatis dan real-time.

---

## 📁 Struktur Arsitektur Proyek

Berikut adalah susunan modul dan struktur file yang telah dirapikan:

```text
lib/
├── core/
│   ├── constants/
│   │   └── app_colors.dart            # Palet warna Material 3 & tema utama
│   └── utils/
│       ├── date_formatter.dart        # Format ISO tanggal & format jam (HH:mm:ss)
│       └── snackbar_utils.dart        # Helper notifikasi SnackBar seragam
├── models/
│   ├── control_mode.dart              # Enum ControlMode (auto, manual)
│   ├── vision_source.dart             # Enum VisionSource (webcam, hp)
│   └── plant_profile.dart             # Model data profil tanaman & kalkulasi hari
├── screens/
│   ├── splash/
│   │   ├── splash_screen.dart         # Layar pembuka / splash screen animasi & partner
│   │   └── widgets/
│   │       └── splash_background_painter.dart # CustomPainter background splash
│   ├── auth/
│   │   └── login_screen.dart          # Layar login & validasi form autentikasi
│   └── main_shell/
│       ├── main_shell_screen.dart     # Shell utama (AppBar MQTT, BottomNav, state coordinator)
│       ├── tabs/
│       │   ├── monitoring_tab.dart    # Tab 1: Kondisi 4 sensor & kontrol sakelar aktuator
│       │   ├── tanaman_tab.dart       # Tab 2: Daftar & manajemen profil tanaman
│       │   └── etiolasi_tab.dart      # Tab 3: Analisis webcam / kamera HP & tray visualizer
│       ├── dialogs/
│       │   └── plant_form_dialog.dart # Dialog form tambah / edit profil tanaman
│       └── widgets/
│           ├── sensor_card.dart       # Kartu sensor (DHT22 Suhu/Lembab, Soil, Lux)
│           ├── actuator_card.dart     # Kartu switch aktuator (Kipas, Sprayer)
│           ├── sub_lamp_tile.dart     # Tile tes satuan lampu (Utama & Booster)
│           ├── spec_pill.dart         # Badge ringkasan spesifikasi profil tanaman
│           ├── field_label.dart       # Label field form input
│           ├── time_picker_box.dart   # Input pemilih jam
│           ├── vision_stat_box.dart   # Statistik hasil scan etiolasi
│           └── tray_painters.dart     # CustomPainter TopViewTray & SideViewStem
└── main.dart                          # Titik masuk utama aplikasi (MaterialApp & ThemeData)
```

---

## 🚀 Fitur Utama

1. **Monitoring IoT Real-time:**
   - Pemantauan suhu udara (°C), kelembaban udara (%), kelembaban tanah (%), dan intensitas cahaya (*lux*).
   - Mode kontrol ganda: **AUTO** (mengikuti kebutuhan profil tanaman) dan **MANUAL** (kontrol sakelar langsung).
   - Pengendalian aktuator: Kipas pendingin, Sprayer penyiraman, dan Grow Light (Lampu Utama & Booster).

2. **Manajemen Profil Tanaman:**
   - Pendaftaran bibit baru (misal: Cabe, Pakcoy, Selada).
   - Konfigurasi batas suhu min/max, jadwal & durasi siram, siklus masa gelap/terang, dan mode lampu.

3. **Deteksi Etiolasi (Vision AI):**
   - Pemindaian kondisi bibit melalui **Webcam Alat** (*Top View & Side View*) maupun foto dari **Kamera HP / Galeri**.
   - Identifikasi bibit etiolasi vs bibit normal beserta rekomendasi otomatis penyalaan lampu booster.

---

## 🛠️ Cara Menjalankan Aplikasi

Pastikan dependensi sudah terpasang:
```bash
flutter pub get
```

### 1. Jalankan di HP Android (Fisik)
Pastikan **USB Debugging** dan **Instal via USB** di HP sudah aktif:
```bash
flutter run
```

### 2. Jalankan di Google Chrome (Web)
```bash
flutter run -d chrome
```

### 3. Jalankan Pengujian (Unit Test)
```bash
flutter test
```
