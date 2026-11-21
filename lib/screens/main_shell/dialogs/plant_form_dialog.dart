import 'dart:math';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/plant_profile.dart';
import '../widgets/field_label.dart';
import '../widgets/time_picker_box.dart';

class PlantFormDialog extends StatefulWidget {
  final PlantProfile? existing;

  const PlantFormDialog({super.key, this.existing});

  @override
  State<PlantFormDialog> createState() => _PlantFormDialogState();
}

class _PlantFormDialogState extends State<PlantFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _namaCtrl;
  late TextEditingController _suhuMinCtrl;
  late TextEditingController _suhuMaxCtrl;
  late TextEditingController _durasiCtrl;
  late TextEditingController _gelapCtrl;
  late TextEditingController _terangCtrl;

  late bool _autoAktif;
  late List<String> _jamSiram;
  late DateTime _tglMulai;
  late String _faseAwal;
  late String _jamMulai;
  late String _jamSelesai;
  late String _jamMulaiH1;
  late String _jumlahLampu;

  static const _faseOptions = [
    'Mulai dari masa gelap',
    'Mulai dari masa terang',
  ];

  static const _lampuOptions = [
    '1 Lampu Saja (Lampu Utama - GPIO 17)',
    '2 Lampu (Utama + Booster)',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _namaCtrl = TextEditingController(text: e?.name ?? '');
    _suhuMinCtrl = TextEditingController(
      text: (e?.suhuMin.toInt() ?? 20).toString(),
    );
    _suhuMaxCtrl = TextEditingController(
      text: (e?.suhuMax.toInt() ?? 30).toString(),
    );
    _durasiCtrl = TextEditingController(
      text: (e?.durasiSiram ?? 10).toString(),
    );
    _gelapCtrl = TextEditingController(text: (e?.masaGelap ?? 2).toString());
    _terangCtrl = TextEditingController(text: (e?.masaTerang ?? 12).toString());

    _autoAktif = e?.autoAktif ?? true;
    _jamSiram = e != null ? List<String>.from(e.jamSiram) : ['08:00', '15:00'];
    _tglMulai = e?.tglMulai ?? DateTime(2026, 11, 20);
    _faseAwal = e?.faseAwal ?? _faseOptions.first;
    _jamMulai = e?.jamMulai ?? '05:30';
    _jamSelesai = e?.jamSelesai ?? '18:00';
    _jamMulaiH1 = e?.jamMulaiH1 ?? '15:00';
    _jumlahLampu = e?.jumlahLampu ?? _lampuOptions.first;
  }

  @override
  void dispose() {
    _namaCtrl.dispose();
    _suhuMinCtrl.dispose();
    _suhuMaxCtrl.dispose();
    _durasiCtrl.dispose();
    _gelapCtrl.dispose();
    _terangCtrl.dispose();
    super.dispose();
  }

  int get _gelapVal => max(0, int.tryParse(_gelapCtrl.text) ?? 0);
  int get _terangVal => max(0, int.tryParse(_terangCtrl.text) ?? 0);
  int get _totalHari => _gelapVal + _terangVal;
  DateTime get _tglSelesai => _tglMulai.add(Duration(days: _totalHari));

  Future<void> _pickTime(String current, ValueChanged<String> onPicked) async {
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 8,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    onPicked(formatted);
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _tglMulai,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _tglMulai = picked);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final profile = PlantProfile(
      id: widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch,
      name: _namaCtrl.text.trim(),
      suhuMin: double.tryParse(_suhuMinCtrl.text) ?? 20,
      suhuMax: double.tryParse(_suhuMaxCtrl.text) ?? 30,
      durasiSiram: int.tryParse(_durasiCtrl.text) ?? 10,
      autoAktif: _autoAktif,
      jamSiram: _jamSiram,
      masaGelap: _gelapVal,
      masaTerang: max(1, _terangVal),
      tglMulai: _tglMulai,
      hariKe: widget.existing?.hariKe ?? 1,
      faseAwal: _faseAwal,
      jamMulai: _jamMulai,
      jamSelesai: _jamSelesai,
      jamMulaiH1: _jamMulaiH1,
      jumlahLampu: _jumlahLampu,
    );
    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
          maxWidth: 460,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Solid Dark Green Header (#15732E)
            Container(
              color: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  const Icon(
                    Icons.eco_rounded,
                    color: Color(0xFFD1FAE5),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isEdit ? 'Edit Tanaman' : 'Tambah Tanaman',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // Single Unified Pure-White Scrollable Form Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Nama Tanaman
                      const FieldLabel('Nama Tanaman'),
                      TextFormField(
                        controller: _namaCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Masukkan nama tanaman (mis. Tomat Cherry)',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nama tanaman wajib diisi'
                            : null,
                      ),
                      const SizedBox(height: 12),

                      // 2. Suhu Min & Max
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const FieldLabel('Suhu Min (Â°C)'),
                                TextFormField(
                                  controller: _suhuMinCtrl,
                                  keyboardType: TextInputType.number,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const FieldLabel('Suhu Max (Â°C)'),
                                TextFormField(
                                  controller: _suhuMaxCtrl,
                                  keyboardType: TextInputType.number,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 3. Durasi Penyiraman & Mode Otomatis Aktif
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const FieldLabel('Durasi Penyiraman (detik)'),
                                TextFormField(
                                  controller: _durasiCtrl,
                                  keyboardType: TextInputType.number,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _autoAktif = !_autoAktif),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                height: 44,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFD5DDD7),
                                    width: 1.4,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: Checkbox(
                                        value: _autoAktif,
                                        activeColor: AppColors.primary,
                                        onChanged: (v) => setState(
                                          () => _autoAktif = v ?? true,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Expanded(
                                      child: Text(
                                        'Mode Otomatis Aktif',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 4. Jam Penyiraman (Chips + Tambah)
                      const FieldLabel('Jam Penyiraman'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ..._jamSiram.map(
                            (t) => InputChip(
                              label: Text(
                                t,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                              backgroundColor: const Color(0xFFECFDF5),
                              side: const BorderSide(color: Color(0xFF6EE7B7)),
                              onDeleted: _jamSiram.length > 1
                                  ? () => setState(() => _jamSiram.remove(t))
                                  : null,
                            ),
                          ),
                          ActionChip(
                            label: const Text(
                              '+ Tambah',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: AppColors.outline),
                            onPressed: () => _pickTime('12:00', (picked) {
                              if (!_jamSiram.contains(picked)) {
                                setState(() {
                                  _jamSiram.add(picked);
                                  _jamSiram.sort();
                                });
                              }
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 5. Divider: SIKLUS PENYINARAN
                      const Row(
                        children: [
                          Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.wb_sunny_outlined,
                                  size: 14,
                                  color: Color(0xFFD97706),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'SIKLUS PENYINARAN',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                    color: Color(0xFFD97706),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 6. Masa Gelap & Masa Terang
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const FieldLabel('Masa Gelap (hari)'),
                                TextFormField(
                                  controller: _gelapCtrl,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() {}),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const FieldLabel('Masa Terang (hari)'),
                                TextFormField(
                                  controller: _terangCtrl,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() {}),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 7. Tanggal Mulai & Tanggal Selesai otomatis
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const FieldLabel('Tanggal Mulai'),
                                InkWell(
                                  onTap: _pickStartDate,
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      suffixIcon: Icon(
                                        Icons.calendar_today_rounded,
                                        size: 16,
                                      ),
                                    ),
                                    child: Text(
                                      formatIsoDate(_tglMulai),
                                      style: const TextStyle(fontSize: 12.5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const FieldLabel('Tanggal Selesai'),
                                InputDecorator(
                                  decoration: const InputDecoration(
                                    fillColor: Color(0xFFF8FAFC),
                                  ),
                                  child: Text(
                                    formatIsoDate(_tglSelesai),
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 8. Fase Awal & Total Siklus Tanam
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const FieldLabel('Fase Awal Saat Mulai'),
                                DropdownButtonFormField<String>(
                                  initialValue: _faseAwal,
                                  isExpanded: true,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textPrimary,
                                  ),
                                  items: _faseOptions
                                      .map(
                                        (f) => DropdownMenuItem(
                                          value: f,
                                          child: Text(
                                            f,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) { setState(() => _faseAwal = v); }
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const FieldLabel('Total Siklus Tanam'),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFFDE68A),
                                    ),
                                  ),
                                  child: Text(
                                    '$_totalHari Hari ($_gelapVal Gelap + $_terangVal Terang)',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF78350F),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 9. Jam Penyinaran Lampu (Mulai Pagi, Selesai Malam, Waktu H-1)
                      const FieldLabel('Jam Penyinaran Lampu'),
                      Row(
                        children: [
                          Expanded(
                            child: TimePickerBox(
                              label: 'MULAI PAGI',
                              value: _jamMulai,
                              bg: const Color(0xFFECFDF5),
                              border: const Color(0xFFA7F3D0),
                              fg: const Color(0xFF065F46),
                              onTap: () => _pickTime(
                                _jamMulai,
                                (v) => setState(() => _jamMulai = v),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TimePickerBox(
                              label: 'SELESAI MALAM',
                              value: _jamSelesai,
                              bg: const Color(0xFFFFF1F2),
                              border: const Color(0xFFFECDD3),
                              fg: const Color(0xFF9F1239),
                              onTap: () => _pickTime(
                                _jamSelesai,
                                (v) => setState(() => _jamSelesai = v),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TimePickerBox(
                        label: 'WAKTU H-1 / BUKA SEMAI',
                        value: _jamMulaiH1,
                        bg: const Color(0xFFFFFBEB),
                        border: const Color(0xFFFDE68A),
                        fg: const Color(0xFF92400E),
                        onTap: () => _pickTime(
                          _jamMulaiH1,
                          (v) => setState(() => _jamMulaiH1 = v),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Jam awal buka semai / mulai masa terang pada H-1',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 10. Jumlah Lampu Masa Terang
                      const FieldLabel('Jumlah Lampu Masa Terang'),
                      DropdownButtonFormField<String>(
                        initialValue: _jumlahLampu,
                        isExpanded: true,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        items: _lampuOptions
                            .map(
                              (o) => DropdownMenuItem(
                                value: o,
                                child: Text(o, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _jumlahLampu = v);
                        },
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Jika memilih 1 lampu, Lampu 2 (booster) tetap mati dan hanya menyala otomatis bila etiolasi terdeteksi kamera.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Sticky Bottom Footer: Batal & Simpan Tanaman
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF334155),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Batal',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text(
                        'Simpan Tanaman',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// REUSABLE WIDGETS & CUSTOM PAINTERS
// ============================================================================


