# Dokumentasi Arsitektur SemaiKu

Dokumen ini menjelaskan struktur arsitektur, pembagian tanggung jawab modul (*Separation of Concerns*), serta alur data aplikasi **SemaiKu**.

## 1. Pembagian Layer

### Core (`lib/core/`)
- **`constants/app_colors.dart`**: Menyediakan warna-warna standar desain sistem Material 3 (hijau agro `#15732E`, aksen kontainer, kartu, garis tepi, dsb).
- **`utils/date_formatter.dart`**: Fungsi utilitas untuk memformat tanggal kalender ISO (`yyyy-MM-dd`) dan jam waktu nyata (`HH:mm:ss`).
- **`utils/snackbar_utils.dart`**: Helper terpadu `showAppSnackBar()` agar seluruh tampilan notifikasi mengambang (*floating*) konsisten di semua layar.

### Models (`lib/models/`)
- **`control_mode.dart`**: Enum `ControlMode { auto, manual }`.
- **`vision_source.dart`**: Enum `VisionSource { webcam, hp }`.
- **`plant_profile.dart`**: Entitas data profil tanaman lengkap dengan kalkulasi masa tumbuh (`totalHari`, `tglSelesai`).

### Screens (`lib/screens/`)
- **`splash/`**: Mengelola animasi loading dan pengenalan brand beserta logo mitra (PENS & PT Petrokimia Gresik).
- **`auth/`**: Validasi login pengguna (username/password) dengan popup dialog loading material 3.
- **`main_shell/`**: Shell navigasi utama aplikasi:
  - **`tabs/monitoring_tab.dart`**: Visualisasi 4 sensor dan sakelar uji aktuator.
  - **`tabs/tanaman_tab.dart`**: Tampilan daftar tanaman, kartu spesifikasi, dan tombol aksi aktifkan/edit/hapus.
  - **`tabs/etiolasi_tab.dart`**: Visualisasi AI nampan bibit dan batang.
  - **`dialogs/plant_form_dialog.dart`**: Formulir modal interaktif untuk konfigurasi jadwal siram dan masa terang/gelap.
  - **`widgets/`**: Widget komponen independen yang dapat digunakan kembali (*reusable*).
