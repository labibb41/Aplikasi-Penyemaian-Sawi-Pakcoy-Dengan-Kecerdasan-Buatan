/// Normalisasi URL server AI.
///
/// - Input berformat IP/hostname biasa (mis. `192.168.100.9`) →
///   dikembalikan sebagai `http://192.168.100.9:8000`.
/// - Input yang sudah mengandung skema `http://` atau `https://` (mis. URL
///   Cloudflare Tunnel `https://xxx.trycloudflare.com`) → digunakan langsung
///   tanpa menambahkan port `:8000`, trailing slash dihapus.
String normalizeServerUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return 'http://192.168.100.9:8000';

  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    // Hapus trailing slash
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  // Input tanpa skema → tambah http:// dan :8000
  return 'http://$trimmed:8000';
}

/// Kebalikan normalizeServerUrl: tampilkan hanya bagian "kotor" di UI.
/// Untuk URL Cloudflare (https://...), kembalikan URL lengkapnya.
/// Untuk IP lokal, kembalikan hanya IP-nya tanpa http:// dan port.
String displayServerInput(String baseUrl) {
  if (baseUrl.startsWith('https://')) return baseUrl;
  // Hapus 'http://' di depan dan ':8000' di belakang jika ada
  String s = baseUrl;
  if (s.startsWith('http://')) s = s.substring(7);
  if (s.endsWith(':8000')) s = s.substring(0, s.length - 5);
  return s;
}
