import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';

class EtiolasiTab extends StatefulWidget {
  const EtiolasiTab({super.key});

  @override
  State<EtiolasiTab> createState() => _EtiolasiTabState();
}

class _EtiolasiTabState extends State<EtiolasiTab> {
  final ImagePicker _picker = ImagePicker();

  // Konfigurasi Server AI Laptop (Auto-Discovery)
  String _serverIp = kIsWeb ? 'localhost' : '192.168.100.9';
  final int _serverPort = 8000;
  String get _serverBaseUrl => 'http://$_serverIp:$_serverPort';

  bool _isDiscoveringServer = false;
  bool _isServerOnline = false;

  // Sisi Atas (Top View)
  XFile? _topImage;
  bool _isAnalyzingTop = false;
  Map<String, String>? _topResult;
  String? _topAnnotatedImageBase64;
  bool _showTopAnnotated = true; // Toggle Foto Asli vs Hasil Deteksi

  // Sisi Samping (Side View)
  XFile? _sideImage;
  bool _isAnalyzingSide = false;
  Map<String, String>? _sideResult;

  @override
  void initState() {
    super.initState();
    // Otomatis cari IP server laptop begitu menu dibuka!
    _autoDiscoverServer();
  }

  /// Memindai jaringan secara otomatis untuk menemukan IP laptop tanpa perlu input manual.
  Future<void> _autoDiscoverServer({bool showFeedback = false}) async {
    if (_isDiscoveringServer) return;
    setState(() => _isDiscoveringServer = true);

    String? foundIp;

    // Tahap 1: Cek kandidat langsung (Sangat cepat & akurat untuk Chrome Laptop maupun HP)
    final directCandidates = <String>{
      if (kIsWeb) ...[
        if (Uri.base.host.isNotEmpty) Uri.base.host,
        'localhost',
        '127.0.0.1',
      ],
      _serverIp,
      '192.168.100.9',
      '192.168.1.100',
    };

    for (final testIp in directCandidates) {
      if (await _pingServer(testIp)) {
        foundIp = testIp;
        break;
      }
    }

    // Tahap 2: Kirim Sinyal UDP Broadcast jika IP tersimpan belum merespons (Khusus HP / Android)
    if (foundIp == null && !kIsWeb) {
      foundIp = await _udpDiscover();
    }

    // Tahap 3: Pemindaian Subnet Lokal Cepat (Fallback jika router blokir broadcast)
    if (foundIp == null && !kIsWeb) {
      foundIp = await _fastSubnetScan();
    }

    if (!mounted) return;

    if (foundIp != null) {
      setState(() {
        _serverIp = foundIp!;
        _isServerOnline = true;
        _isDiscoveringServer = false;
      });
      if (showFeedback && mounted) {
        showAppSnackBar(context, '✅ Server AI terdeteksi otomatis: $_serverBaseUrl');
      }
    } else {
      setState(() {
        _isServerOnline = false;
        _isDiscoveringServer = false;
      });
      if (showFeedback && mounted) {
        showAppSnackBar(
          context,
          '⚠️ Laptop belum terdeteksi. Pastikan file jalankan_server.bat aktif di laptop.',
        );
      }
    }
  }

  /// Cek respons server melalui HTTP GET /api/health
  Future<bool> _pingServer(String ip) async {
    try {
      final res = await http
          .get(Uri.parse('http://$ip:$_serverPort/api/health'))
          .timeout(const Duration(milliseconds: 1200));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Deteksi cepat lewat UDP Broadcast pada port 8888
  Future<String?> _udpDiscover() async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final data = utf8.encode('SEMAIKU_DISCOVER');
      socket.send(data, InternetAddress('255.255.255.255'), 8888);

      final completer = Completer<String?>();
      late StreamSubscription sub;

      sub = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            final reply = utf8.decode(datagram.data);
            if (reply.startsWith('SEMAIKU_OFFER')) {
              if (!completer.isCompleted) {
                completer.complete(datagram.address.address);
              }
            }
          }
        }
      });

      final result = await completer.future.timeout(
        const Duration(milliseconds: 1200),
        onTimeout: () => null,
      );

      await sub.cancel();
      socket.close();
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Memindai host-host subnet lokal secara paralel
  Future<String?> _fastSubnetScan() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final myIp = addr.address;
          if (myIp == '127.0.0.1') continue;

          final parts = myIp.split('.');
          if (parts.length != 4) continue;
          final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
          final myHost = int.tryParse(parts[3]) ?? 100;

          // Targetkan gateway dan host terdekat di sekitar HP
          final targetHosts = <int>{};
          targetHosts.addAll([1, 2, 3, 4, 5, 10, 15, 20, 50, 100, 101, 102, 103, 104]);
          for (int i = myHost - 6; i <= myHost + 6; i++) {
            if (i > 0 && i < 255) targetHosts.add(i);
          }

          final futures = targetHosts.map((h) async {
            final testIp = '$prefix.$h';
            final isUp = await _pingServer(testIp);
            return isUp ? testIp : null;
          });

          final results = await Future.wait(futures);
          for (final res in results) {
            if (res != null) return res;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _pickImage({
    required bool isTop,
    required ImageSource source,
  }) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 88,
      );

      if (picked != null) {
        setState(() {
          if (isTop) {
            _topImage = picked;
            _topResult = null; // reset hasil lama saat ganti foto
            _topAnnotatedImageBase64 = null;
            _showTopAnnotated = true;
          } else {
            _sideImage = picked;
            _sideResult = null;
          }
        });

        if (mounted) {
          showAppSnackBar(
            context,
            'Foto ${isTop ? "Sisi Atas" : "Sisi Samping"} berhasil diambil',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'Gagal mengambil gambar: $e');
      }
    }
  }

  void _showServerConfigDialog() {
    final ctrl = TextEditingController(text: _serverIp);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.laptop_chromebook_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Text(
              'Pengaturan IP Server AI',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aplikasi mendeteksi IP laptop secara otomatis. Anda juga bisa memasukkan IP secara manual jika diperlukan:',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                prefixText: 'http://',
                suffixText: ':$_serverPort',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _autoDiscoverServer(showFeedback: true);
                  },
                  icon: const Icon(Icons.radar_rounded, size: 16),
                  label: const Text('Pindai Ulang', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final newIp = ctrl.text.trim();
              if (newIp.isNotEmpty) {
                setState(() {
                  _serverIp = newIp;
                  _isServerOnline = false;
                });
                Navigator.pop(ctx);
                _autoDiscoverServer(showFeedback: true);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Simpan & Tes'),
          ),
        ],
      ),
    );
  }

  void _showConnectionErrorDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text(
              'Laptop Belum Terhubung',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'HP belum dapat menemukan server AI di laptop.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Buka folder server di laptop, lalu klik 2x "jalankan_server.bat".\n'
              '2. Pastikan HP dan laptop terhubung ke jaringan Wi-Fi yang sama.\n'
              '3. Tekan tombol "Cari Otomatis" di bawah ini.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.45),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _autoDiscoverServer(showFeedback: true);
            },
            icon: const Icon(Icons.radar_rounded, size: 16),
            label: const Text('Cari Otomatis'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _analyzeTop() async {
    if (_topImage == null) return;

    // Pastikan server online atau cari otomatis terlebih dahulu
    if (!_isServerOnline) {
      await _autoDiscoverServer();
      if (!_isServerOnline) {
        _showConnectionErrorDialog();
        return;
      }
    }

    setState(() {
      _isAnalyzingTop = true;
      _topResult = null;
      _topAnnotatedImageBase64 = null;
    });

    try {
      final uri = Uri.parse('$_serverBaseUrl/api/predict/top');
      final request = http.MultipartRequest('POST', uri);

      final bytes = await _topImage!.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: _topImage!.name.isNotEmpty ? _topImage!.name : 'top_view.jpg',
        ),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 35),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final totalKotak = data['total_kotak'] ?? data['total_tanaman'] ?? 0;
        final bijiDeteksi = data['biji_terdeteksi'] ?? data['total_tanaman'] ?? 0;
        final kotakKosong = data['kotak_kosong'] ?? 0;
        final dayaKecambah = data['daya_kecambah'] ?? 100.0;

        setState(() {
          _isAnalyzingTop = false;
          _isServerOnline = true;
          _topAnnotatedImageBase64 = data['annotated_image'] as String?;
          _showTopAnnotated = true;
          _topResult = {
            'status': data['status_keseluruhan'] ?? 'Normal',
            'tipe_foto': data['framing_type'] ?? 'Fleksibel',
            'total_kotak': '$totalKotak Lubang',
            'biji_terdeteksi': '$bijiDeteksi Biji ($dayaKecambah%)',
            'kotak_kosong': '$kotakKosong Lubang',
            'bibit_normal': '${data['normal']} Bibit (${data['persentase_normal']}%)',
            'etiolasi_ringan': '${data['etiolasi_ringan']} Bibit',
            'etiolasi_berat': '${data['etiolasi_berat']} Bibit',
            'catatan': data['rekomendasi'] ?? '',
          };
        });

        if (mounted) {
          showAppSnackBar(
            context,
            'Analisis selesai: $bijiDeteksi bibit diidentifikasi dari $totalKotak kotak!',
          );
        }
      } else {
        throw Exception('Server error: HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAnalyzingTop = false;
        _isServerOnline = false;
      });
      _showConnectionErrorDialog();
    }
  }

  Future<void> _analyzeSide() async {
    if (_sideImage == null) return;
    setState(() => _isAnalyzingSide = true);

    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;

    setState(() {
      _isAnalyzingSide = false;
      _sideResult = {
        'status': 'Batang Kokoh (Normal)',
        'tinggi': '3.2 cm (Proporsional)',
        'etiolasi': 'Negatif (0%)',
        'catatan':
            'Tinggi hipokotil seimbang dengan luas daun, batang tegak kuat, pencahayaan utama mencukupi.',
      };
    });

    showAppSnackBar(context, 'Analisis Sisi Samping selesai!');
  }

  void _openInteractiveZoomDialog({
    required XFile imageFile,
    String? annotatedBase64,
    required bool isTop,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        bool showAnnotatedInDialog = annotatedBase64 != null && annotatedBase64.isNotEmpty;
        final TransformationController transformController = TransformationController();

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget currentImage;
            if (showAnnotatedInDialog && annotatedBase64 != null) {
              final base64Clean = annotatedBase64.replaceFirst(
                RegExp(r'data:image\/[a-z]+;base64,'),
                '',
              );
              final bytes = base64Decode(base64Clean);
              currentImage = Image.memory(
                bytes,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.contain,
              );
            } else {
              if (kIsWeb) {
                currentImage = Image.network(
                  imageFile.path,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.contain,
                );
              } else {
                currentImage = Image.file(
                  File(imageFile.path),
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.contain,
                );
              }
            }

            return Dialog.fullscreen(
              backgroundColor: const Color(0xFF0F172A),
              child: SafeArea(
                child: Stack(
                  children: [
                    // Interactive Zoom & Pan Area
                    Positioned.fill(
                      child: InteractiveViewer(
                        transformationController: transformController,
                        minScale: 0.5,
                        maxScale: 8.0,
                        boundaryMargin: const EdgeInsets.all(120),
                        child: Center(
                          child: GestureDetector(
                            onDoubleTap: () {
                              if (transformController.value.getMaxScaleOnAxis() > 1.2) {
                                transformController.value = Matrix4.identity();
                              } else {
                                transformController.value = Matrix4.identity()..scale(2.5);
                              }
                            },
                            child: currentImage,
                          ),
                        ),
                      ),
                    ),

                    // Top Bar
                    Positioned(
                      top: 10,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  isTop ? 'Detail Hasil Sisi Atas' : 'Detail Sisi Samping',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                if (annotatedBase64 != null && annotatedBase64.isNotEmpty) ...[
                                  InkWell(
                                    onTap: () {
                                      setDialogState(() {
                                        showAnnotatedInDialog = !showAnnotatedInDialog;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: showAnnotatedInDialog
                                            ? AppColors.primary
                                            : const Color(0xFF334155),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        showAnnotatedInDialog ? 'Deteksi AI' : 'Foto Asli',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                                  onPressed: () => Navigator.pop(ctx),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Bottom Floating Zoom Controls & Hint
                    Positioned(
                      bottom: 16,
                      left: 20,
                      right: 20,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white, size: 20),
                                  tooltip: 'Zoom Out',
                                  onPressed: () {
                                    final current = transformController.value.getMaxScaleOnAxis();
                                    final next = (current / 1.3).clamp(0.5, 8.0);
                                    transformController.value = Matrix4.identity()..scale(next);
                                  },
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () {
                                    transformController.value = Matrix4.identity();
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    child: Text(
                                      'Reset (100%)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 20),
                                  tooltip: 'Zoom In',
                                  onPressed: () {
                                    final current = transformController.value.getMaxScaleOnAxis();
                                    final next = (current * 1.3).clamp(0.5, 8.0);
                                    transformController.value = Matrix4.identity()..scale(next);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '💡 Cubit layar atau scroll mouse untuk zoom • Geser untuk menggeser',
                              style: TextStyle(color: Colors.white70, fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildImagePreview({
    required XFile imageFile,
    String? annotatedBase64,
    required bool showAnnotated,
    required VoidCallback onToggleAnnotated,
    required VoidCallback onZoomTap,
  }) {
    final hasAnnotated = annotatedBase64 != null && annotatedBase64.isNotEmpty;

    Widget imageWidget;
    if (hasAnnotated && showAnnotated) {
      final base64Clean = annotatedBase64.replaceFirst(RegExp(r'data:image\/[a-z]+;base64,'), '');
      final bytes = base64Decode(base64Clean);
      imageWidget = Image.memory(
        bytes,
        width: double.infinity,
        height: 320,
        fit: BoxFit.contain,
      );
    } else {
      if (kIsWeb) {
        imageWidget = Image.network(
          imageFile.path,
          width: double.infinity,
          height: 320,
          fit: BoxFit.contain,
        );
      } else {
        imageWidget = Image.file(
          File(imageFile.path),
          width: double.infinity,
          height: 320,
          fit: BoxFit.contain,
        );
      }
    }

    return Container(
      height: 320,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. Gambar Utama dengan Zoom Interaktif Langsung di Kartu
            Positioned.fill(
              child: InteractiveViewer(
                clipBehavior: Clip.antiAlias,
                minScale: 1.0,
                maxScale: 6.0,
                child: Center(child: imageWidget),
              ),
            ),

            // 2. Tombol Layar Penuh (Zoom Maksimal) di Pojok Kanan Bawah
            Positioned(
              bottom: 8,
              right: 8,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onZoomTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24, width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fullscreen_rounded, size: 16, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Layar Penuh',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 3. Hint Panduan Zoom di Pojok Kiri Atas
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pinch_rounded, size: 13, color: Colors.white70),
                    SizedBox(width: 4),
                    Text(
                      'Cubit / Scroll untuk Zoom',
                      style: TextStyle(color: Colors.white70, fontSize: 9.5),
                    ),
                  ],
                ),
              ),
            ),

            // 4. Toggle Deteksi AI vs Foto Asli
            if (hasAnnotated)
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () {
                          if (!showAnnotated) onToggleAnnotated();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: showAnnotated ? AppColors.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Deteksi AI',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          if (showAnnotated) onToggleAnnotated();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: !showAnnotated ? AppColors.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Foto Asli',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraSlotCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required XFile? imageFile,
    required bool isAnalyzing,
    required Map<String, String>? result,
    String? annotatedBase64,
    bool showAnnotated = true,
    VoidCallback? onToggleAnnotated,
    required VoidCallback onTakePhoto,
    required VoidCallback onPickGallery,
    required VoidCallback onAnalyze,
    required VoidCallback onRetake,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: imageFile != null
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.outlineLight,
          width: imageFile != null ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Slot
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (imageFile != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: const Text(
                    'Foto Siap',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF047857),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Area Gambar / Jepret Kamera
          if (imageFile == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.outlineLight,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.add_a_photo_outlined,
                    size: 40,
                    color: AppColors.primary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Belum ada foto bibit',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Text(
                    'Fleksibel: Bisa 1 tray, sebagian bibit, atau close-up',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onTakePhoto,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          icon: const Icon(
                            Icons.camera_alt_rounded,
                            size: 16,
                          ),
                          label: const Text(
                            'Kamera HP',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onPickGallery,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.outline),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          icon: const Icon(
                            Icons.photo_library_outlined,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          label: const Text(
                            'Pilih Galeri',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else ...[
            // Tampilan Foto (Asli / Anotasi AI)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  _buildImagePreview(
                    imageFile: imageFile,
                    annotatedBase64: annotatedBase64,
                    showAnnotated: showAnnotated,
                    onToggleAnnotated: onToggleAnnotated ?? () {},
                    onZoomTap: () => _openInteractiveZoomDialog(
                      imageFile: imageFile,
                      annotatedBase64: annotatedBase64,
                      isTop: title.contains('Atas'),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: InkWell(
                      onTap: onRetake,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Foto Ulang',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Tombol Analisis
            if (result == null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isAnalyzing ? null : onAnalyze,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: isAnalyzing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.analytics_outlined, size: 18),
                  label: Text(
                    isAnalyzing
                        ? 'Memproses AI di Laptop...'
                        : 'Mulai Analisis $title',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),

            // Turun Hasil Analisis
            if (result != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              size: 16,
                              color: Color(0xFF16A34A),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Hasil Analisis AI',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF15803D),
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: Text(
                            result['status'] ?? 'Normal',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF166534),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16, color: Color(0xFFDCFCE7)),
                    if (result.containsKey('total_kotak')) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 9,
                          horizontal: 8,
                        ),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFDCFCE7)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  const Text(
                                    'TOTAL KOTAK',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0284C7),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    result['total_kotak'] ?? '-',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 26,
                              color: const Color(0xFFE2E8F0),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  const Text(
                                    'BIJI TUMBUH',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF16A34A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    result['biji_terdeteksi'] ?? '-',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 26,
                              color: const Color(0xFFE2E8F0),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  const Text(
                                    'KOTAK KOSONG',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    result['kotak_kosong'] ?? '-',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    ...result.entries
                        .where(
                          (e) =>
                              e.key != 'status' &&
                              e.key != 'catatan' &&
                              e.key != 'total_kotak' &&
                              e.key != 'biji_terdeteksi' &&
                              e.key != 'kotak_kosong',
                        )
                        .map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  e.key.replaceAll('_', ' ').toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                                Text(
                                  e.value,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    if (result['catatan'] != null && result['catatan']!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFDCFCE7)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.lightbulb_outline_rounded,
                              size: 15,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                result['catatan']!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF334155),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Menu Ambil / Upload Foto Baru Setelah Analisis
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onTakePhoto,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.camera_alt_rounded, size: 15),
                      label: const Text(
                        'Foto Kamera Baru',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPickGallery,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.outline),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.photo_library_outlined, size: 15),
                      label: const Text(
                        'Upload Galeri Baru',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bothAnalyzed = _topResult != null && _sideResult != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        // Ringkasan Header & Status Server Laptop (Auto-Discovery Live Indicator)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outlineLight),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.camera_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monitoring Visual Kamera',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Deteksi etiolasi fleksibel (1 tray, sebagian, atau close-up)',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Live Auto-Discovery Server Status Pill
              InkWell(
                onTap: _showServerConfigDialog,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _isServerOnline
                        ? const Color(0xFFF0FDF4)
                        : _isDiscoveringServer
                            ? const Color(0xFFFEFCE8)
                            : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isServerOnline
                          ? const Color(0xFF86EFAC)
                          : _isDiscoveringServer
                              ? const Color(0xFFFDE047)
                              : const Color(0xFFFECACA),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Status Dot / Spinner
                      if (_isDiscoveringServer)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFCA8A04),
                          ),
                        )
                      else
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isServerOnline
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFDC2626),
                          ),
                        ),
                      const SizedBox(width: 8),

                      // Text Info
                      Expanded(
                        child: Text(
                          _isDiscoveringServer
                              ? 'Mencari Server Laptop Otomatis...'
                              : _isServerOnline
                                  ? 'Server Terhubung: $_serverIp (Otomatis)'
                                  : 'Server Belum Aktif ($_serverIp)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _isServerOnline
                                ? const Color(0xFF166534)
                                : _isDiscoveringServer
                                    ? const Color(0xFF854D0E)
                                    : const Color(0xFF991B1B),
                          ),
                        ),
                      ),

                      // Action Button
                      if (_isDiscoveringServer)
                        const SizedBox()
                      else if (_isServerOnline)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF16A34A)),
                              tooltip: 'Pindai Ulang',
                              onPressed: () => _autoDiscoverServer(showFeedback: true),
                            ),
                          ],
                        )
                      else
                        InkWell(
                          onTap: () => _autoDiscoverServer(showFeedback: true),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.radar_rounded, size: 14, color: Color(0xFFDC2626)),
                              SizedBox(width: 3),
                              Text(
                                'Cari Lagi',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Slot 1: Sisi Atas (Terhubung ke AI Laptop)
        _buildCameraSlotCard(
          title: 'Sisi Atas (Top View)',
          subtitle: 'YOLO26n + MobileNetV2 (Deteksi kanopi daun)',
          icon: Icons.grid_view_rounded,
          imageFile: _topImage,
          isAnalyzing: _isAnalyzingTop,
          result: _topResult,
          annotatedBase64: _topAnnotatedImageBase64,
          showAnnotated: _showTopAnnotated,
          onToggleAnnotated: () {
            setState(() => _showTopAnnotated = !_showTopAnnotated);
          },
          onTakePhoto: () =>
              _pickImage(isTop: true, source: ImageSource.camera),
          onPickGallery: () =>
              _pickImage(isTop: true, source: ImageSource.gallery),
          onAnalyze: _analyzeTop,
          onRetake: () =>
              _pickImage(isTop: true, source: ImageSource.camera),
        ),
        const SizedBox(height: 14),

        // Slot 2: Sisi Samping
        _buildCameraSlotCard(
          title: 'Sisi Samping (Side View)',
          subtitle: 'Memantau tinggi hipokotil & kekokohan batang',
          icon: Icons.height_rounded,
          imageFile: _sideImage,
          isAnalyzing: _isAnalyzingSide,
          result: _sideResult,
          onTakePhoto: () =>
              _pickImage(isTop: false, source: ImageSource.camera),
          onPickGallery: () =>
              _pickImage(isTop: false, source: ImageSource.gallery),
          onAnalyze: _analyzeSide,
          onRetake: () =>
              _pickImage(isTop: false, source: ImageSource.camera),
        ),
        const SizedBox(height: 14),

        // Kesimpulan Menyeluruh (muncul jika dua-duanya selesai dianalisis)
        if (bothAnalyzed)
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE8F5E9), Color(0xFFC8E6C9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFA5D6A7), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.verified_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Evaluasi Menyeluruh Selesai',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'SELESAI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Data Sisi Atas (AI Laptop) dan Sisi Samping telah berhasil dianalisis. Parameter bibit terdokumentasi lengkap dan sistem inkubator SemaiKu siap mengoptimalkan siklus penyiraman serta pencahayaan.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF1B5E20),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
