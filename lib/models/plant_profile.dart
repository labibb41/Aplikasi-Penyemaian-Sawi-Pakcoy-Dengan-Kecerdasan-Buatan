class PlantProfile {
  final int id;
  final String name;
  final double suhuMin;
  final double suhuMax;
  final int durasiSiram;
  final bool autoAktif;
  final List<String> jamSiram;
  final int masaGelap;
  final int masaTerang;
  final DateTime tglMulai;
  final int hariKe;
  final String faseAwal;
  final String jamMulai;
  final String jamSelesai;
  final String jamMulaiH1;
  final String jumlahLampu;

  PlantProfile({
    required this.id,
    required this.name,
    required this.suhuMin,
    required this.suhuMax,
    required this.durasiSiram,
    required this.autoAktif,
    required this.jamSiram,
    required this.masaGelap,
    required this.masaTerang,
    required this.tglMulai,
    this.hariKe = 1,
    required this.faseAwal,
    required this.jamMulai,
    required this.jamSelesai,
    required this.jamMulaiH1,
    required this.jumlahLampu,
  });

  int get totalHari => masaGelap + masaTerang;
  DateTime get tglSelesai => tglMulai.add(Duration(days: totalHari));
}
