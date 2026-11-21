import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/plant_profile.dart';
import '../widgets/spec_pill.dart';

class TanamanTab extends StatelessWidget {
  final List<PlantProfile> plants;
  final int? activePlantId;
  final ValueChanged<int> onActivatePlant;
  final VoidCallback onDeactivatePlant;
  final ValueChanged<PlantProfile> onEditPlant;
  final ValueChanged<int> onDeletePlant;

  const TanamanTab({
    super.key,
    required this.plants,
    required this.activePlantId,
    required this.onActivatePlant,
    required this.onDeactivatePlant,
    required this.onEditPlant,
    required this.onDeletePlant,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 92),
      children: [
        const Text(
          'Daftar Profil Tanaman',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          '${plants.length} profil tersimpan untuk mode Auto',
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        if (plants.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.outlineLight),
            ),
            child: const Column(
              children: [
                Text(
                  'Belum ada profil tanaman',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  'Tekan tombol Tambah Tanaman untuk mendaftarkan profil baru.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          )
        else
          ...plants.map((p) {
            final isActive = p.id == activePlantId;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isActive ? AppColors.primary : AppColors.outlineLight,
                  width: isActive ? 1.6 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.primary
                              : AppColors.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.eco_rounded,
                          color: isActive ? Colors.white : AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                if (isActive) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryContainer,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      'AKTIF',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${p.totalHari} Hari (${p.masaGelap} Gelap + ${p.masaTerang} Terang) • s/d ${formatIsoDate(p.tglSelesai)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit tanaman',
                        onPressed: () => onEditPlant(p),
                        icon: const Icon(Icons.edit_outlined, size: 19),
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        tooltip: 'Hapus tanaman',
                        onPressed: () => onDeletePlant(p.id),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 19,
                          color: Color(0xFFDC2626),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 4.1,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      SpecPill(
                        'Suhu',
                        '${p.suhuMin.toInt()}–${p.suhuMax.toInt()}°C',
                      ),
                      SpecPill(
                        'Siram',
                        '${p.jamSiram.join(", ")} (${p.durasiSiram}s)',
                      ),
                      SpecPill('Lampu', '${p.jamMulai}–${p.jamSelesai}'),
                      SpecPill('H-1 Buka', p.jamMulaiH1, highlightAmber: true),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 38,
                    child: isActive
                        ? OutlinedButton(
                            onPressed: onDeactivatePlant,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: const BorderSide(color: AppColors.outline),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                              ),
                            ),
                            child: const Text(
                              'Nonaktifkan Profil',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : FilledButton(
                            onPressed: () => onActivatePlant(p.id),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                              ),
                            ),
                            child: const Text(
                              'Aktifkan Tanaman',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
