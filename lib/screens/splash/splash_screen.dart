import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../auth/login_screen.dart';
import 'widgets/splash_background_painter.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2100),
    )..forward();

    _navTimer = Timer(const Duration(milliseconds: 2400), _goToLogin);
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _progressController.dispose();
    super.dispose();
  }

  void _goToLogin() {
    if (!mounted) return;
    _navTimer?.cancel();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const LoginScreen(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F5E25), Color(0xFF15732E), Color(0xFF0A3D18)],
          ),
        ),
        child: Stack(
          children: [
            // Decorative IoT Grid & Ambient Circles
            Positioned.fill(
              child: CustomPaint(painter: SplashBackgroundPainter()),
            ),

            // Main Splash Content
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top Spacer
                    const SizedBox(height: 16),

                    // Center Brand Hero
                    Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.32),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.22),
                                    blurRadius: 24,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.eco_rounded,
                                color: Colors.white,
                                size: 52,
                              ),
                            ),
                            Positioned(
                              top: -6,
                              right: -6,
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.wifi_rounded,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'SemaiKu',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'SMART IOT SEED GERMINATION',
                          style: TextStyle(
                            color: Color(0xFFD1FAE5),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Progress Bar
                        SizedBox(
                          width: 230,
                          child: AnimatedBuilder(
                            animation: _progressController,
                            builder: (_, _) => ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: _progressController.value,
                                minHeight: 6,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.22,
                                ),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFFD9F99D),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Memuat sistem & memeriksa modul...',
                          style: TextStyle(
                            color: Color(0xFFD1FAE5),
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ),

                    // Bottom Partner Section: PENS & PT Petrokimia Gresik (Frosted Glass Pill)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Subtle Kolaborasi Header with Accent Lines
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 24,
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(
                                'KOLABORASI & DUKUNGAN',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.4,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                            ),
                            Container(
                              width: 24,
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Frosted Glass Pill (Glassmorphism, Semi-Transparent)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // PENS
                                  Image.asset(
                                    'assets/images/logo_pens.png',
                                    height: 24,
                                    width: 24,
                                    fit: BoxFit.contain,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'PENS',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  // Center Dot Separator
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Container(
                                      width: 4,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.45,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                  // Petrokimia
                                  Image.asset(
                                    'assets/images/logo_petrokimia.png',
                                    height: 24,
                                    fit: BoxFit.contain,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Petrokimia',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Subtitle Institution Names
                        Text(
                          'Politeknik Elektronika Negeri Surabaya × PT Petrokimia Gresik',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.72),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
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
}
