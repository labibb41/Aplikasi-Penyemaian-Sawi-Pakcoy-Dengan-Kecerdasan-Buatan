import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_colors.dart';
import '../main_shell/main_shell_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController(text: 'admin@semaiku.id');
  final _passCtrl = TextEditingController(text: 'semaiku2026');
  bool _obscurePassword = true;
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_email');
    if (savedEmail != null && savedEmail.isNotEmpty) {
      if (mounted) {
        setState(() => _emailCtrl.text = savedEmail);
      }
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    // Show M3 Loading Overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.primary),
                SizedBox(height: 18),
                Text(
                  'Menyiapkan SemaiKu',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 1100));
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('saved_email', _emailCtrl.text.trim());
    } else {
      await prefs.setBool('is_logged_in', false);
      await prefs.remove('saved_email');
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // Close loading dialog
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShellScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.18),
                    ),
                  ),
                  child: const Icon(
                    Icons.eco_rounded,
                    color: AppColors.primary,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Selamat Datang',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Masuk Untuk Akses Dan Kontrol Inkubator Penyemaian',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.outlineLight),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Email / Username',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _emailCtrl,
                          decoration: const InputDecoration(
                            hintText: 'nama@email.com',
                            prefixIcon: Icon(
                              Icons.alternate_email_rounded,
                              size: 19,
                            ),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Wajib diisi'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Kata Sandi',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: 'Masukkan kata sandi',
                            prefixIcon: const Icon(
                              Icons.lock_outline_rounded,
                              size: 19,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 19,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Wajib diisi' : null,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    activeColor: AppColors.primary,
                                    onChanged: (val) => setState(
                                      () => _rememberMe = val ?? true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Ingat saya',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: _handleLogin,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: const StadiumBorder(),
                            ),
                            icon: const Text(
                              'Masuk',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            label: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Partner Section: PENS & PT Petrokimia Gresik
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 24,
                      height: 1,
                      color: AppColors.outline.withValues(alpha: 0.5),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'KOLABORASI & DUKUNGAN',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: AppColors.textSecondary.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    Container(
                      width: 24,
                      height: 1,
                      color: AppColors.outline.withValues(alpha: 0.5),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Partner Logo Pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.outlineLight),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // PENS Logo
                      Image.asset(
                        'assets/images/logo_pens.png',
                        height: 22,
                        width: 22,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'PENS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: 0.4,
                        ),
                      ),
                      // Dot separator
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: AppColors.outline,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      // Petrokimia Logo
                      Image.asset(
                        'assets/images/logo_petrokimia.png',
                        height: 22,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'PT Petrokimia Gresik',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                Text(
                  'Politeknik Elektronika Negeri Surabaya × PT Petrokimia Gresik',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary.withValues(alpha: 0.8),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Penyemaian Bibit Tanaman Berbasis IoT',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SCREEN 3: MAIN APP SHELL (SCAFFOLD + NAVIGATION BAR)
// ============================================================================
