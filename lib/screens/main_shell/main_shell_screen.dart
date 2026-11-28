import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/mqtt/mqtt_service.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/control_mode.dart';
import '../../models/plant_profile.dart';
import '../../core/services/notification_service.dart';
import '../auth/login_screen.dart';
import 'dialogs/plant_form_dialog.dart';
import 'tabs/etiolasi_tab.dart';
import 'tabs/monitoring_tab.dart';
import 'tabs/tanaman_tab.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _selectedIndex = 0;

  // Sensor & Control State
  ControlMode _mode = ControlMode.auto;
  double _suhu = 32.8;
  double _lembabUdara = 81.8;
  double _lembabTanah = 42;
  double _lux = 1250;
  String _lastUpdateTs = formatNowHms();

  bool _kipasOn = true;
  bool _sprayerOn = false;
  bool _lamp1On = true;
  bool _lamp2On = false;
  bool? _lastNotifiedKipas;
  bool? _lastNotifiedSprayer;
  bool? _lastNotifiedLamp1;
  bool? _lastNotifiedLamp2;


Future<void> _savePlants() async {
  final prefs = await SharedPreferences.getInstance();
  final encoded = jsonEncode(_plants.map((p) => {
    'id': p.id,
    'name': p.name,
    'suhuMin': p.suhuMin,
    'suhuMax': p.suhuMax,
    'durasiSiram': p.durasiSiram,
    'autoAktif': p.autoAktif,
    'jamSiram': p.jamSiram,
    'masaGelap': p.masaGelap,
    'masaTerang': p.masaTerang,
    'tglMulai': p.tglMulai.toIso8601String(),
    'faseAwal': p.faseAwal,
    'jamMulai': p.jamMulai,
    'jamSelesai': p.jamSelesai,
    'jamMulaiH1': p.jamMulaiH1,
    'jumlahLampu': p.jumlahLampu,
  }).toList());
  await prefs.setString('saved_plants', encoded);
  if (_activePlantId != null) {
    await prefs.setInt('active_plant_id', _activePlantId!);
  } else {
    await prefs.remove('active_plant_id');
  }
}

Future<void> _loadSavedPlants() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('saved_plants');
  final savedActiveId = prefs.getInt('active_plant_id');
  if (raw == null) return;

  final List decoded = jsonDecode(raw);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  setState(() {
    _plants.clear();
    for (final item in decoded) {
      final start = DateTime.parse(item['tglMulai']);
      final startDay = DateTime(start.year, start.month, start.day);
      final hariKe = (today.difference(startDay).inDays + 1).clamp(1, 999);
      _plants.add(PlantProfile(
        id: item['id'],
        name: item['name'],
        suhuMin: (item['suhuMin'] as num).toDouble(),
        suhuMax: (item['suhuMax'] as num).toDouble(),
        durasiSiram: item['durasiSiram'],
        autoAktif: item['autoAktif'],
        jamSiram: List<String>.from(item['jamSiram']),
        masaGelap: item['masaGelap'],
        masaTerang: item['masaTerang'],
        tglMulai: start,
        hariKe: hariKe,
        faseAwal: item['faseAwal'],
        jamMulai: item['jamMulai'],
        jamSelesai: item['jamSelesai'],
        jamMulaiH1: item['jamMulaiH1'],
        jumlahLampu: item['jumlahLampu'],
      ));
    }
    _activePlantId = savedActiveId;
  });
} 

  // MQTT State
  MqttConnectionStatus _mqttStatus = MqttConnectionStatus.disconnected;
  StreamSubscription<MqttConnectionStatus>? _mqttStatusSub;
  StreamSubscription<IncubatorTelemetry>? _telemetrySub;

  // Plant Profiles State
  int? _activePlantId = 1;
  late final List<PlantProfile> _plants = _buildDefaultPlants();

  static List<PlantProfile> _buildDefaultPlants() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      PlantProfile(
        id: 1,
        name: 'Cabe',
        suhuMin: 25,
        suhuMax: 30,
        durasiSiram: 5,
        autoAktif: true,
        jamSiram: ['07:00', '15:00'],
        masaGelap: 4,
        masaTerang: 26,
        tglMulai: today,
        hariKe: 1,
        faseAwal: 'Mulai dari masa gelap',
        jamMulai: '05:30',
        jamSelesai: '18:00',
        jamMulaiH1: '15:00',
        jumlahLampu: '1 Lampu Saja (Lampu Utama - GPIO 17)',
      ),
      PlantProfile(
        id: 2,
        name: 'Pakcoy',
        suhuMin: 20,
        suhuMax: 28,
        durasiSiram: 10,
        autoAktif: true,
        jamSiram: ['08:00', '15:00'],
        masaGelap: 2,
        masaTerang: 12,
        tglMulai: today,
        hariKe: 1,
        faseAwal: 'Mulai dari masa gelap',
        jamMulai: '05:30',
        jamSelesai: '18:00',
        jamMulaiH1: '14:30',
        jumlahLampu: '1 Lampu Saja (Lampu Utama - GPIO 17)',
      ),
      PlantProfile(
        id: 3,
        name: 'Selada',
        suhuMin: 18,
        suhuMax: 25,
        durasiSiram: 8,
        autoAktif: true,
        jamSiram: ['08:00', '15:00'],
        masaGelap: 2,
        masaTerang: 14,
        tglMulai: today,
        hariKe: 1,
        faseAwal: 'Mulai dari masa terang',
        jamMulai: '05:30',
        jamSelesai: '17:30',
        jamMulaiH1: '15:00',
        jumlahLampu: '2 Lampu (Utama + Booster)',
      ),
    ];
  }

  PlantProfile? get _activePlant {
    if (_activePlantId == null) return null;
    for (final p in _plants) {
      if (p.id == _activePlantId) return p;
    }
    return null;
  }

 @override
void initState() {
  super.initState();
  _initMqtt();
  _loadSavedPlants();
  NotificationService.instance.init();
}

  void _initMqtt() {
    final mqtt = MqttService.instance;
    _mqttStatus = mqtt.currentStatus;

    _mqttStatusSub = mqtt.statusStream.listen((status) {
      if (!mounted) return;
      setState(() => _mqttStatus = status);
      if (status == MqttConnectionStatus.connected) {
        _showSnack(
          'Terhubung ke EMQX Cloud',
          icon: Icons.cloud_done_rounded,
          iconColor: const Color(0xFF4ADE80),
        );
      } else if (status == MqttConnectionStatus.error) {
        _showSnack(
          'Gagal terhubung ke MQTT Broker. Ketuk badge untuk coba lagi.',
          icon: Icons.cloud_off_rounded,
          iconColor: const Color(0xFFF87171),
        );
      }
    });

    _telemetrySub = mqtt.telemetryStream.listen((telemetry) {
  if (!mounted) return;

  setState(() {
    if (telemetry.temperature != null) _suhu = telemetry.temperature!;
    if (telemetry.humidity != null) _lembabUdara = telemetry.humidity!;
    if (telemetry.soilMoisture != null) _lembabTanah = telemetry.soilMoisture!;
    if (telemetry.lux != null) _lux = telemetry.lux!;
    if (telemetry.fanRelay != null) _kipasOn = telemetry.fanRelay!;
    if (telemetry.sprayerRelay != null) _sprayerOn = telemetry.sprayerRelay!;
    if (telemetry.lamp1Relay != null) _lamp1On = telemetry.lamp1Relay!;
    if (telemetry.lamp2Relay != null) _lamp2On = telemetry.lamp2Relay!;
    if (telemetry.mode != null) {
      _mode = telemetry.mode!.toLowerCase() == 'auto'
          ? ControlMode.auto
          : ControlMode.manual;
    }
    // ... (biarkan kode sinkronisasi tanaman Anda di sini) ...
    _lastUpdateTs = formatNowHms();
  });

      // Kirim notifikasi hanya jika status aktuator benar-benar berubah setelah data awal diterima
      final isAuto = _mode == ControlMode.auto;
      final prefix = isAuto ? 'Otomatis' : 'Manual';
      final nowStr = _lastUpdateTs;

      if (telemetry.fanRelay != null) {
        final on = telemetry.fanRelay!;
        if (_lastNotifiedKipas != null && on != _lastNotifiedKipas) {
          NotificationService.instance.show(
            id: 1,
            title: isAuto
                ? 'Fuzzy Logic: Kipas ${on ? "Menyala" : "Mati"}'
                : 'Manual: Kipas ${on ? "Menyala" : "Mati"}',
            body: on
                ? '[$nowStr] Kipas aktif mendinginkan inkubator. Suhu: ${_suhu.toStringAsFixed(1)}°C.'
                : '[$nowStr] Kipas dimatikan. Suhu saat ini: ${_suhu.toStringAsFixed(1)}°C.',
          );
        }
        _lastNotifiedKipas = on;
      }

      if (telemetry.sprayerRelay != null) {
        final on = telemetry.sprayerRelay!;
        if (_lastNotifiedSprayer != null && on != _lastNotifiedSprayer) {
          NotificationService.instance.show(
            id: 2,
            title: '$prefix: Sprayer ${on ? "Menyala" : "Mati"}',
            body: on
                ? '[$nowStr] Penyiraman sedang berlangsung. Kelembaban tanah: ${_lembabTanah.toInt()}%. ($nowStr)'
                : '[$nowStr] Penyiraman selesai dan sprayer dimatikan.',
          );
        }
        _lastNotifiedSprayer = on;
      }

      if (telemetry.lamp1Relay != null) {
        final on = telemetry.lamp1Relay!;
        if (_lastNotifiedLamp1 != null && on != _lastNotifiedLamp1) {
          NotificationService.instance.show(
            id: 3,
            title: '$prefix: Lampu 1 ${on ? "Menyala" : "Mati"}',
            body: on
                ? '[$nowStr] Lampu utama grow light dinyalakan.'
                : '[$nowStr] Lampu utama grow light dimatikan.',
          );
        }
        _lastNotifiedLamp1 = on;
      }

      if (telemetry.lamp2Relay != null) {
        final on = telemetry.lamp2Relay!;
        if (_lastNotifiedLamp2 != null && on != _lastNotifiedLamp2) {
          NotificationService.instance.show(
            id: 4,
            title: '$prefix: Lampu 2 ${on ? "Menyala" : "Mati"}',
            body: on
                ? '[$nowStr] Lampu booster (Lampu 2) dinyalakan.'
                : '[$nowStr] Lampu booster (Lampu 2) dimatikan.',
          );
        }
        _lastNotifiedLamp2 = on;
      }
});

    mqtt.connect();
  }

  @override
  void dispose() {
    _mqttStatusSub?.cancel();
    _telemetrySub?.cancel();
    super.dispose();
  }

  DateTime? _lastBackPressTime;

  void _showSnack(
    String message, {
    IconData icon = Icons.check_circle_rounded,
    Color iconColor = const Color(0xFF4ADE80),
  }) {
    showAppSnackBar(context, message, icon: icon, iconColor: iconColor);
  }

  void _handleBackNavigation() {
    if (_selectedIndex != 0) {
      // Jika di tab Tanaman (1) atau Monitoring (2), kembali ke Tab Kontrol (0)
      setState(() => _selectedIndex = 0);
      return;
    }

    // Jika sudah berada di Tab Kontrol (0):
    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      _showSnack(
        'Tekan tombol kembali sekali lagi untuk keluar',
        icon: Icons.exit_to_app_rounded,
        iconColor: const Color(0xFFFBBF24),
      );
    } else {
      _showExitOrLogoutDialog(isExitApp: true);
    }
  }

  void _showExitOrLogoutDialog({required bool isExitApp}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 22),
        actionsPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFDC2626),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isExitApp ? 'Keluar Aplikasi' : 'Konfirmasi Keluar',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          isExitApp
              ? 'Apakah Anda yakin ingin menutup dan keluar dari aplikasi SemaiKu?'
              : 'Apakah Anda yakin ingin keluar dari SemaiKu?',
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text(
              'Batal',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              if (isExitApp) {
                SystemNavigator.pop();
              } else {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('is_logged_in', false);
                if (!mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            ),
            child: Text(
              isExitApp ? 'Keluar Aplikasi' : 'Keluar Akun',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // SENSOR & CONTROL ACTIONS
  // --------------------------------------------------------------------------
  void _simulateSensorRefresh() {
    if (_mqttStatus == MqttConnectionStatus.connected) {
      _showSnack(
        'Sinkronisasi aktif: data streaming live dari ESP32 via EMQX Cloud',
        icon: Icons.cloud_sync_rounded,
        iconColor: const Color(0xFF60A5FA),
      );
    } else {
      MqttService.instance.connect();
      _showSnack(
        'Menghubungkan kembali ke EMQX Cloud...',
        icon: Icons.sync_rounded,
        iconColor: const Color(0xFFFBBF24),
      );
    }
  }

  void _setMode(ControlMode newMode) {
    setState(() {
      _mode = newMode;
      if (_mode == ControlMode.auto) {
        final p = _activePlant;
        if (p == null) {
          _kipasOn = false;
          _sprayerOn = false;
          _lamp1On = false;
          _lamp2On = false;
        } else {
          _kipasOn = _suhu > p.suhuMax;
        }
      }
    });

    final modeStr = newMode == ControlMode.auto ? 'auto' : 'manual';
    final sent = MqttService.instance.setMode(modeStr);

    _showSnack(
      newMode == ControlMode.auto
          ? 'Mode kontrol diubah ke AUTO${sent ? " (MQTT terkirim)" : ""}'
          : 'Mode Manual aktif: silakan tes aktuator di bawah',
      icon: newMode == ControlMode.auto ? Icons.auto_mode_rounded : Icons.tune_rounded,
      iconColor: newMode == ControlMode.auto ? const Color(0xFF4ADE80) : const Color(0xFF60A5FA),
    );
  }

  void _deactivatePlant() {
    setState(() {
      _activePlantId = null;
      if (_mode == ControlMode.auto) {
        _kipasOn = false;
        _sprayerOn = false;
        _lamp1On = false;
        _lamp2On = false;
      }
    });
    _savePlants();
    _showSnack('Tanaman dinonaktifkan. Pilih tanaman untuk mode AUTO.');
  }

  void _activatePlant(int id) {
    setState(() {
      _activePlantId = id;
      final p = _activePlant;
      if (p != null && _mode == ControlMode.auto) {
        _kipasOn = _suhu > p.suhuMax;
        _lamp1On = true;
        _lamp2On = p.jumlahLampu.startsWith('2');
      }
    });
    _savePlants();
    final p = _activePlant;
    if (p != null) {
      final lampsCount = p.jumlahLampu.startsWith('2') ? 2 : 1;
      final sent = MqttService.instance.syncPlantProfile(
        name: p.name,
        suhuMax: p.suhuMax,
        jamMulai: p.jamMulai,
        jamSelesai: p.jamSelesai,
        jamMulaiH1: p.jamMulaiH1,
        masaGelap: p.masaGelap,
        masaTerang: p.masaTerang,
        tglMulai: p.tglMulai,
        faseAwal: p.faseAwal,
        autoLampsCount: lampsCount,
        jamSiram: p.jamSiram,
        durasiSiram: p.durasiSiram,
      );
      _showSnack(
        'Tanaman "${p.name}" diaktifkan & disinkronkan ke ESP32${sent ? " (MQTT terkirim)" : ""}',
        icon: Icons.eco_rounded,
        iconColor: const Color(0xFF4ADE80),
      );
    }
  }

  void _deletePlant(int id) {
    final target = _plants.firstWhere((e) => e.id == id);
    setState(() {
      _plants.removeWhere((e) => e.id == id);
      if (_activePlantId == id) {
        _activePlantId = null;
      }
    });
    _savePlants();
    _showSnack('Profil "${target.name}" dihapus');
  }

  Future<void> _openPlantForm([PlantProfile? existing]) async {
    final result = await showDialog<PlantProfile>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PlantFormDialog(existing: existing),
    );
    if (result == null) return;

    setState(() {
      if (existing != null) {
        final idx = _plants.indexWhere((p) => p.id == existing.id);
        if (idx != -1) _plants[idx] = result;
      } else {
        _plants.insert(0, result);
      }
    });
    _savePlants();

    if (existing != null && _activePlantId == result.id) {
      final lampsCount = result.jumlahLampu.startsWith('2') ? 2 : 1;
      MqttService.instance.syncPlantProfile(
        name: result.name,
        suhuMax: result.suhuMax,
        jamMulai: result.jamMulai,
        jamSelesai: result.jamSelesai,
        jamMulaiH1: result.jamMulaiH1,
        masaGelap: result.masaGelap,
        masaTerang: result.masaTerang,
        tglMulai: result.tglMulai,
        faseAwal: result.faseAwal,
        autoLampsCount: lampsCount,
        jamSiram: result.jamSiram,
        durasiSiram: result.durasiSiram,
      );
    }

    _showSnack(
      existing != null
          ? 'Profil "${result.name}" diperbarui & disinkronkan'
          : 'Profil "${result.name}" ditambahkan',
    );
  }

  void _onKipasChanged(bool val) {
    if (_mode == ControlMode.auto) {
      _showSnack('Ubah ke mode MANUAL untuk mengontrol kipas');
      return;
    }
    setState(() => _kipasOn = val);
    final sent = MqttService.instance.setRelay('fan', val);
    _showSnack(
      'Kipas Pendingin diubah menjadi ${val ? "ON" : "OFF"}${sent ? " (MQTT terkirim)" : ""}',
      icon: Icons.air_rounded,
      iconColor: val ? const Color(0xFF4ADE80) : const Color(0xFF94A3B8),
    );
  }

  void _onSprayerChanged(bool val) {
    if (_mode == ControlMode.auto) {
      _showSnack('Ubah ke mode MANUAL untuk mengontrol sprayer');
      return;
    }
    setState(() => _sprayerOn = val);
    final dur = _activePlant?.durasiSiram ?? 20;
    final sent = MqttService.instance.setRelay('sprayer', val, duration: dur);
    _showSnack(
      'Sprayer diubah menjadi ${val ? "ON" : "OFF"}${sent ? " (durasi ${dur}d)" : ""}',
      icon: Icons.water_drop_rounded,
      iconColor: val ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
    );
  }

  void _onMasterLampChanged(bool val) {
    if (_mode == ControlMode.auto) return;
    setState(() {
      _lamp1On = val;
      if (!val) _lamp2On = false;
    });
    final sent = MqttService.instance.setRelay('lamp', val);
    _showSnack(
      'Lampu Grow Light diubah menjadi ${val ? "ON" : "OFF"}${sent ? " (MQTT terkirim)" : ""}',
      icon: Icons.lightbulb_rounded,
      iconColor: val ? const Color(0xFFFBBF24) : const Color(0xFF94A3B8),
    );
  }

  void _onToggleLamp1() {
    if (_mode == ControlMode.auto) {
      _showSnack('Tes satuan lampu hanya aktif di Mode MANUAL');
      return;
    }
    final newVal = !_lamp1On;
    setState(() => _lamp1On = newVal);
    final sent = MqttService.instance.setRelay('lamp1', newVal);
    _showSnack(
      'Lampu 1 diubah menjadi ${newVal ? "ON" : "OFF"}${sent ? " (MQTT terkirim)" : ""}',
      icon: Icons.lightbulb_outline_rounded,
      iconColor: newVal ? const Color(0xFFFBBF24) : const Color(0xFF94A3B8),
    );
  }

  void _onToggleLamp2() {
    if (_mode == ControlMode.auto) {
      _showSnack('Tes satuan lampu hanya aktif di Mode MANUAL');
      return;
    }
    final newVal = !_lamp2On;
    setState(() => _lamp2On = newVal);
    final sent = MqttService.instance.setRelay('lamp2', newVal);
    _showSnack(
      'Lampu 2 diubah menjadi ${newVal ? "ON" : "OFF"}${sent ? " (MQTT terkirim)" : ""}',
      icon: Icons.lightbulb_outline_rounded,
      iconColor: newVal ? const Color(0xFFFBBF24) : const Color(0xFF94A3B8),
    );
  }

  void _showMqttDetailsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.cloud_sync_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Status EMQX Cloud',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMqttInfoTile('Broker Host', MqttService.brokerHost),
            const SizedBox(height: 8),
            _buildMqttInfoTile('Port', '8883 (Mobile SSL) / 8084 (Web WSS)'),
            const SizedBox(height: 8),
            _buildMqttInfoTile('Koneksi', _mqttStatus == MqttConnectionStatus.connected
                ? 'Terhubung (Online)'
                : _mqttStatus == MqttConnectionStatus.connecting
                    ? 'Sedang Menghubungkan...'
                    : 'Terputus (Offline)'),
            const SizedBox(height: 8),
            _buildMqttInfoTile('Pembaruan Terakhir', _lastUpdateTs),
            const SizedBox(height: 8),
            _buildMqttInfoTile('Topic Telemetri', MqttService.topicTelemetry),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Tutup'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              MqttService.instance.connect();
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Hubungkan Ulang'),
          ),
        ],
      ),
    );
  }

  Widget _buildMqttInfoTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const subtitles = [
      'Kontrol & Kondisi IoT',
      'Konfigurasi Tanaman',
      'Monitoring Kamera Bibit',
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: AppColors.outlineLight),
          ),
          titleSpacing: 16,
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.18),
                  ),
                ),
                child: const Icon(
                  Icons.eco_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SemaiKu',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitles[_selectedIndex],
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            Builder(
              builder: (context) {
                Color badgeBg;
                Color badgeBorder;
                Color badgeDot;
                Color badgeFg;
                String badgeText;

                switch (_mqttStatus) {
                  case MqttConnectionStatus.connected:
                    badgeBg = AppColors.primaryContainer;
                    badgeBorder = AppColors.primary.withValues(alpha: 0.18);
                    badgeDot = AppColors.primary;
                    badgeFg = AppColors.onPrimaryContainer;
                    badgeText = 'MQTT: Online';
                    break;
                  case MqttConnectionStatus.connecting:
                    badgeBg = const Color(0xFFFEF3C7);
                    badgeBorder =
                        const Color(0xFFF59E0B).withValues(alpha: 0.3);
                    badgeDot = const Color(0xFFF59E0B);
                    badgeFg = const Color(0xFF92400E);
                    badgeText = 'MQTT: Hubung...';
                    break;
                  case MqttConnectionStatus.disconnected:
                  case MqttConnectionStatus.error:
                    badgeBg = const Color(0xFFF1F5F9);
                    badgeBorder =
                        const Color(0xFF94A3B8).withValues(alpha: 0.3);
                    badgeDot = const Color(0xFF94A3B8);
                    badgeFg = const Color(0xFF475569);
                    badgeText = 'MQTT: Offline';
                    break;
                }

                return InkWell(
                  onTap: _showMqttDetailsDialog,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: badgeBorder),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(radius: 3.5, backgroundColor: badgeDot),
                        const SizedBox(width: 5),
                        Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: badgeFg,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Keluar',
              icon: const Icon(Icons.logout_rounded, size: 20),
              onPressed: () => _showExitOrLogoutDialog(isExitApp: false),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            MonitoringTab(
              activePlant: _activePlant,
              mode: _mode,
              suhu: _suhu,
              lembabUdara: _lembabUdara,
              lembabTanah: _lembabTanah,
              lux: _lux,
              lastUpdateTs: _lastUpdateTs,
              kipasOn: _kipasOn,
              sprayerOn: _sprayerOn,
              lamp1On: _lamp1On,
              lamp2On: _lamp2On,
              onRefreshSensor: _simulateSensorRefresh,
              onModeChanged: _setMode,
              onSelectPlant: () => setState(() => _selectedIndex = 1),
              onDeactivatePlant: _deactivatePlant,
              onKipasChanged: _onKipasChanged,
              onSprayerChanged: _onSprayerChanged,
              onMasterLampChanged: _onMasterLampChanged,
              onToggleLamp1: _onToggleLamp1,
              onToggleLamp2: _onToggleLamp2,
            ),
            TanamanTab(
              plants: _plants,
              activePlantId: _activePlantId,
              onActivatePlant: _activatePlant,
              onDeactivatePlant: _deactivatePlant,
              onEditPlant: _openPlantForm,
              onDeletePlant: _deletePlant,
            ),
            const EtiolasiTab(),
          ],
        ),
        floatingActionButton: _selectedIndex == 1
            ? FloatingActionButton.extended(
                onPressed: () => _openPlantForm(),
                elevation: 3,
                highlightElevation: 6,
                backgroundColor: const Color(0xFFE8F5E9),
                foregroundColor: const Color(0xFF0C3B20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFF81C784), width: 1.4),
                ),
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                label: const Text(
                  'Tambah Tanaman',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Color(0xFF0C3B20),
                    letterSpacing: 0.2,
                  ),
                ),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          backgroundColor: Colors.white,
          indicatorColor: AppColors.primaryContainer,
          onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(
                Icons.dashboard_rounded,
                color: AppColors.onPrimaryContainer,
              ),
              label: 'Kontrol',
            ),
            NavigationDestination(
              icon: Icon(Icons.eco_outlined),
              selectedIcon: Icon(
                Icons.eco_rounded,
                color: AppColors.onPrimaryContainer,
              ),
              label: 'Tanaman',
            ),
            NavigationDestination(
              icon: Icon(Icons.camera_alt_outlined),
              selectedIcon: Icon(
                Icons.camera_alt_rounded,
                color: AppColors.onPrimaryContainer,
              ),
              label: 'Monitoring',
            ),
          ],
        ),
      ),
    );
  }
}
