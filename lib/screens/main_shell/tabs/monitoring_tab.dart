import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/control_mode.dart';
import '../../../models/plant_profile.dart';
import '../widgets/actuator_card.dart';
import '../widgets/sensor_card.dart';
import '../widgets/sub_lamp_tile.dart';

class MonitoringTab extends StatelessWidget {
  final PlantProfile? activePlant;
  final ControlMode mode;
  final double suhu;
  final double lembabUdara;
  final double lembabTanah;
  final double lux;
  final String lastUpdateTs;
  final bool kipasOn;
  final bool sprayerOn;
  final bool lamp1On;
  final bool lamp2On;
  final VoidCallback onRefreshSensor;
  final ValueChanged<ControlMode> onModeChanged;
  final VoidCallback onSelectPlant;
  final VoidCallback onDeactivatePlant;
  final ValueChanged<bool> onKipasChanged;
  final ValueChanged<bool> onSprayerChanged;
  final ValueChanged<bool> onMasterLampChanged;
  final VoidCallback onToggleLamp1;
  final VoidCallback onToggleLamp2;

  const MonitoringTab({
    super.key,
    required this.activePlant,
    required this.mode,
    required this.suhu,
    required this.lembabUdara,
    required this.lembabTanah,
    required this.lux,
    required this.lastUpdateTs,
    required this.kipasOn,
    required this.sprayerOn,
    required this.lamp1On,
    required this.lamp2On,
    required this.onRefreshSensor,
    required this.onModeChanged,
    required this.onSelectPlant,
    required this.onDeactivatePlant,
    required this.onKipasChanged,
    required this.onSprayerChanged,
    required this.onMasterLampChanged,
    required this.onToggleLamp1,
    required this.onToggleLamp2,
  });

  @override
  Widget build(BuildContext context) {
    final isLocked = mode == ControlMode.auto;
    final lampuOn = lamp1On || lamp2On;
    final activeLampCount = (lamp1On ? 1 : 0) + (lamp2On ? 1 : 0);

    // Status helpers
    String suhuBadge;
    Color suhuBg;
    Color suhuFg;
    if (activePlant == null) {
      suhuBadge = 'Menunggu profil';
      suhuBg = const Color(0xFFF1F5F9);
      suhuFg = const Color(0xFF475569);
    } else if (suhu > activePlant!.suhuMax) {
      suhuBadge = 'Terlalu Panas > ${activePlant!.suhuMax.toInt()}°C';
      suhuBg = const Color(0xFFFEF2F2);
      suhuFg = const Color(0xFFDC2626);
    } else if (suhu < activePlant!.suhuMin) {
      suhuBadge = 'Dingin < ${activePlant!.suhuMin.toInt()}°C';
      suhuBg = const Color(0xFFF0F9FF);
      suhuFg = const Color(0xFF0369A1);
    } else {
      suhuBadge = 'Optimal';
      suhuBg = AppColors.primaryContainer;
      suhuFg = AppColors.primary;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        // 1. Compact Status Strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outlineLight),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Update: $lastUpdateTs',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: const Text(
                  'RTC: Sinkron',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF047857),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. Unified Box: 4 Kondisi Sensor
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.outlineLight),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'KONDISI SENSOR',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  InkWell(
                    onTap: onRefreshSensor,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            size: 14,
                            color: AppColors.primary,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Simulasi Sensor',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.08,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  SensorCard(
                    icon: Icons.thermostat_rounded,
                    iconBg: const Color(0xFFFFEDD5),
                    iconColor: const Color(0xFFEA580C),
                    sensorTag: 'DHT22',
                    title: 'Suhu Udara',
                    value: suhu.toStringAsFixed(1),
                    unit: '°C',
                    badgeText: suhuBadge,
                    badgeBg: suhuBg,
                    badgeFg: suhuFg,
                    progress: (suhu / 45).clamp(0.05, 1.0),
                    barColor: const Color(0xFFF97316),
                  ),
                  SensorCard(
                    icon: Icons.water_drop_rounded,
                    iconBg: const Color(0xFFCCFBF1),
                    iconColor: const Color(0xFF0D9488),
                    sensorTag: 'DHT22',
                    title: 'Kelembaban Udara',
                    value: lembabUdara.toStringAsFixed(1),
                    unit: '%',
                    badgeText: lembabUdara < 55 ? 'Agak Kering' : 'Optimal',
                    badgeBg: lembabUdara < 55
                        ? const Color(0xFFFFFBEB)
                        : const Color(0xFFF0FDFA),
                    badgeFg: lembabUdara < 55
                        ? const Color(0xFFB45309)
                        : const Color(0xFF0F766E),
                    progress: (lembabUdara / 100).clamp(0.05, 1.0),
                    barColor: const Color(0xFF14B8A6),
                  ),
                  SensorCard(
                    icon: Icons.grass_rounded,
                    iconBg: const Color(0xFFD1FAE5),
                    iconColor: AppColors.primary,
                    sensorTag: 'Soil',
                    title: 'Kelembaban Tanah',
                    value: lembabTanah.round().toString(),
                    unit: '%',
                    badgeText: lembabTanah < 30
                        ? 'Kering'
                        : (lembabTanah > 75 ? 'Basah' : 'Cukup Lembab'),
                    badgeBg: lembabTanah < 30
                        ? const Color(0xFFFEF2F2)
                        : AppColors.primaryContainer,
                    badgeFg: lembabTanah < 30
                        ? const Color(0xFFDC2626)
                        : AppColors.primary,
                    progress: (lembabTanah / 100).clamp(0.05, 1.0),
                    barColor: AppColors.primary,
                  ),
                  SensorCard(
                    icon: Icons.wb_sunny_rounded,
                    iconBg: const Color(0xFFFEF3C7),
                    iconColor: const Color(0xFFD97706),
                    sensorTag: 'Lux Meter',
                    title: 'Intensitas Cahaya',
                    value: lux.round().toString(),
                    unit: 'lx',
                    badgeText: lux < 100 ? 'Gelap / Malam' : 'Fase Terang',
                    badgeBg: lux < 100
                        ? const Color(0xFFF1F5F9)
                        : const Color(0xFFFFFBEB),
                    badgeFg: lux < 100
                        ? const Color(0xFF475569)
                        : const Color(0xFFB45309),
                    progress: (lux / 2000).clamp(0.04, 1.0),
                    barColor: const Color(0xFFF59E0B),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. Mode Kontrol Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.outlineLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Mode Kontrol',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: mode == ControlMode.auto
                          ? AppColors.primaryContainer
                          : const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      mode == ControlMode.auto ? 'Otomatis' : 'Kontrol Manual',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: mode == ControlMode.auto
                            ? AppColors.onPrimaryContainer
                            : const Color(0xFF6B21A8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<ControlMode>(
                segments: const [
                  ButtonSegment(
                    value: ControlMode.auto,
                    label: Text(
                      'AUTO',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  ButtonSegment(
                    value: ControlMode.manual,
                    label: Text(
                      'MANUAL',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (set) => onModeChanged(set.first),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return mode == ControlMode.auto
                          ? AppColors.primaryContainer
                          : const Color(0xFFF3E8FF);
                    }
                    return Colors.white;
                  }),
                ),
              ),
              const SizedBox(height: 10),

              // Dynamic Banner inside Mode Kontrol
              if (mode == ControlMode.manual)
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF5FF),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFFE9D5FF)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.touch_app_rounded,
                        color: Color(0xFF7E22CE),
                        size: 20,
                      ),
                      SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mode Manual Aktif',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF581C87),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Gunakan sakelar di bawah untuk mengetes aktuator (Kipas, Sprayer, dan Lampu) yang berjalan secara langsung.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6B21A8),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else if (activePlant != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.eco_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TANAMAN AKTIF',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                            Text(
                              '${activePlant!.name} • Hari ke-${activePlant!.hariKe}/${activePlant!.totalHari} • H-1: ${activePlant!.jamMulaiH1}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Nonaktifkan tanaman',
                        onPressed: onDeactivatePlant,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                      FilledButton(
                        onPressed: onSelectPlant,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 32),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                        child: const Text(
                          'Atur',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFFD97706),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Belum ada tanaman aktif',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF78350F),
                              ),
                            ),
                            Text(
                              'Pilih atau aktifkan profil tanaman agar mode AUTO dapat berjalan.',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: onSelectPlant,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD97706),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 32),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                        child: const Text(
                          'Pilih',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 4. Kontrol Perangkat (Actuators)
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            'KONTROL PERANGKAT',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppColors.textSecondary,
            ),
          ),
        ),

        // Kipas
        ActuatorCard(
          icon: Icons.wind_power_rounded,
          title: 'Kipas Pendingin',
          subtitle: activePlant != null
              ? 'Set suhu: ${activePlant!.suhuMin.toInt()}–${activePlant!.suhuMax.toInt()}°C'
              : 'Belum ada set suhu (pilih tanaman)',
          isOn: kipasOn,
          isLocked: isLocked,
          activeColor: AppColors.primary,
          activeBg: AppColors.primaryContainer,
          onChanged: onKipasChanged,
        ),
        const SizedBox(height: 10),

        // Sprayer
        ActuatorCard(
          icon: Icons.water_drop_outlined,
          title: 'Sprayer Penyiraman',
          subtitle: activePlant != null
              ? 'Jadwal: ${activePlant!.jamSiram.join(", ")} • ${activePlant!.durasiSiram} dtk'
              : 'Belum ada jadwal penyiraman',
          isOn: sprayerOn,
          isLocked: isLocked,
          activeColor: const Color(0xFF0284C7),
          activeBg: const Color(0xFFE0F2FE),
          onChanged: onSprayerChanged,
        ),
        const SizedBox(height: 10),

        // Lampu Grow Light + Tes Satuan
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.outlineLight),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: lampuOn
                          ? const Color(0xFFFFFBEB)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.lightbulb_outline_rounded,
                      color: lampuOn
                          ? const Color(0xFFD97706)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Grow Light (Semua)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: activeLampCount > 0
                                    ? const Color(0xFFFEF3C7)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                activeLampCount > 0
                                    ? '$activeLampCount AKTIF'
                                    : 'OFF',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: activeLampCount > 0
                                      ? const Color(0xFFB45309)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          activePlant != null
                              ? 'Jadwal: ${activePlant!.jamMulai}–${activePlant!.jamSelesai} • H-1: ${activePlant!.jamMulaiH1}'
                              : 'Belum ada jadwal penyinaran',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: lampuOn,
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.primary,
                    onChanged: isLocked ? null : onMasterLampChanged,
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: AppColors.outlineLight),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tes Satuan Lampu',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    isLocked
                        ? 'Aktif di Mode Manual'
                        : 'Ketuk untuk tes satuan',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SubLampTile(
                      title: 'Lampu 1',
                      subtitle: 'Utama',
                      isOn: lamp1On,
                      isLocked: isLocked,
                      onTap: onToggleLamp1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SubLampTile(
                      title: 'Lampu 2',
                      subtitle: 'Booster',
                      isOn: lamp2On,
                      isLocked: isLocked,
                      onTap: onToggleLamp2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
