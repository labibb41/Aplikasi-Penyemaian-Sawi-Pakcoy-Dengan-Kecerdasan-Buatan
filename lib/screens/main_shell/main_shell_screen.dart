import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/control_mode.dart';
import '../../models/plant_profile.dart';
import '../auth/login_screen.dart';
import 'dialogs/plant_form_dialog.dart';
import 'tabs/etiolasi_tab.dart';
import 'tabs/monitoring_tab.dart';
import 'tabs/tanaman_tab.dart';

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

  // Plant Profiles State
  int? _activePlantId = 1;
  final List<PlantProfile> _plants = [
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
      tglMulai: DateTime(2026, 11, 10),
      hariKe: 11,
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
      tglMulai: DateTime(2026, 11, 16),
      hariKe: 5,
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
      tglMulai: DateTime(2026, 11, 18),
      hariKe: 3,
      faseAwal: 'Mulai dari masa terang',
      jamMulai: '05:30',
      jamSelesai: '17:30',
      jamMulaiH1: '15:00',
      jumlahLampu: '2 Lampu (Utama + Booster)',
    ),
  ];

  PlantProfile? get _activePlant {
    if (_activePlantId == null) return null;
    for (final p in _plants) {
      if (p.id == _activePlantId) return p;
    }
    return null;
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
            onPressed: () {
              Navigator.of(ctx).pop();
              if (isExitApp) {
                SystemNavigator.pop();
              } else {
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
    final rng = Random();
    setState(() {
      _suhu = double.parse((22 + rng.nextDouble() * 12).toStringAsFixed(1));
      _lembabUdara = double.parse(
        (60 + rng.nextDouble() * 28).toStringAsFixed(1),
      );
      _lembabTanah = (18 + rng.nextInt(62)).toDouble();
      _lux = rng.nextDouble() > 0.25
          ? (800 + rng.nextInt(1100)).toDouble()
          : rng.nextInt(45).toDouble();
      _lastUpdateTs = formatNowHms();

      if (_mode == ControlMode.auto) {
        final p = _activePlant;
        _kipasOn = p != null && _suhu > p.suhuMax;
      }
    });
    _showSnack('Data sensor MQTT diperbarui');
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
    _showSnack(
      newMode == ControlMode.auto
          ? 'Mode kontrol diubah ke AUTO'
          : 'Mode Manual aktif: silakan tes aktuator di bawah',
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
    final p = _activePlant;
    if (p != null) {
      _showSnack('Tanaman "${p.name}" diaktifkan');
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
    _showSnack(
      existing != null
          ? 'Profil "${result.name}" diperbarui'
          : 'Profil "${result.name}" ditambahkan',
    );
  }

  void _onKipasChanged(bool val) {
    if (_mode == ControlMode.auto) {
      _showSnack('Ubah ke mode MANUAL untuk mengontrol kipas');
      return;
    }
    setState(() => _kipasOn = val);
    _showSnack('Kipas Pendingin diubah menjadi ${val ? "ON" : "OFF"}');
  }

  void _onSprayerChanged(bool val) {
    if (_mode == ControlMode.auto) {
      _showSnack('Ubah ke mode MANUAL untuk mengontrol sprayer');
      return;
    }
    setState(() => _sprayerOn = val);
    _showSnack('Sprayer diubah menjadi ${val ? "ON" : "OFF"}');
  }

  void _onMasterLampChanged(bool val) {
    if (_mode == ControlMode.auto) return;
    setState(() {
      _lamp1On = val;
      if (!val) _lamp2On = false;
    });
    _showSnack('Lampu Grow Light diubah menjadi ${val ? "ON" : "OFF"}');
  }

  void _onToggleLamp1() {
    if (_mode == ControlMode.auto) {
      _showSnack('Tes satuan lampu hanya aktif di Mode MANUAL');
      return;
    }
    setState(() => _lamp1On = !_lamp1On);
    _showSnack('Lampu 1 diubah menjadi ${_lamp1On ? "ON" : "OFF"}');
  }

  void _onToggleLamp2() {
    if (_mode == ControlMode.auto) {
      _showSnack('Tes satuan lampu hanya aktif di Mode MANUAL');
      return;
    }
    setState(() => _lamp2On = !_lamp2On);
    _showSnack('Lampu 2 diubah menjadi ${_lamp2On ? "ON" : "OFF"}');
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.18),
                ),
              ),
              child: const Row(
                children: [
                  CircleAvatar(radius: 3.5, backgroundColor: AppColors.primary),
                  SizedBox(width: 5),
                  Text(
                    'MQTT: Online',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
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
