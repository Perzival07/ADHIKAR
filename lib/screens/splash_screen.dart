import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/services/settings_service.dart';
import '../core/services/auth_service.dart';
import 'main_navigation_screen.dart';
import 'auth/sign_in_screen.dart';

class SplashScreen extends StatefulWidget {
  final SettingsService settings;
  final AuthService auth;

  const SplashScreen({super.key, required this.settings, required this.auth});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _pulseController;

  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _taglineSlideAnimation;
  late Animation<double> _taglineFadeAnimation;
  late Animation<double> _pulseAnimation;

  Timer? _navTimer;

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _taglineSlideAnimation = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _taglineFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
      ),
    );

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _mainController.forward();

    // Smooth transition after animation plays
    _navTimer = Timer(
      const Duration(milliseconds: 2700),
      _navigateToNextScreen,
    );
  }

  void _navigateToNextScreen() {
    if (!mounted) return;

    final isAuthenticated = widget.auth.isAuthenticated;
    final targetScreen = isAuthenticated
        ? MainNavigationScreen(settings: widget.settings, auth: widget.auth)
        : SignInScreen(settings: widget.settings, auth: widget.auth);

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (routeContext, animation, secondaryAnimation) =>
            targetScreen,
        transitionsBuilder:
            (routeContext, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeInOut,
                ),
                child: child,
              );
            },
      ),
    );
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _mainController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Elegant Civic Indian Gradient Backdrop
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFFFFFFF),
                  Color(0xFFF8FAFC),
                  Color(0xFFF1F5F9),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          // Glowing background halos
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accentSaffron.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.forestGreen.withValues(alpha: 0.07),
              ),
            ),
          ),

          // Central Animated Content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Spacer(),

                          // Animated Logo with glowing pulse
                          AnimatedBuilder(
                            animation: Listenable.merge([
                              _mainController,
                              _pulseController,
                            ]),
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _scaleAnimation.value,
                                child: Opacity(
                                  opacity: _fadeAnimation.value,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Pulsing aura
                                      Transform.scale(
                                        scale: _pulseAnimation.value,
                                        child: Container(
                                          width: 220,
                                          height: 220,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: RadialGradient(
                                              colors: [
                                                AppTheme.accentSaffron
                                                    .withValues(alpha: 0.12),
                                                AppTheme.primaryNavy.withValues(
                                                  alpha: 0.04,
                                                ),
                                                Colors.transparent,
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),

                                      // Exact Uploaded Logo Image
                                      Container(
                                        width: 190,
                                        height: 190,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            32,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppTheme.primaryNavy
                                                  .withValues(alpha: 0.12),
                                              blurRadius: 28,
                                              offset: const Offset(0, 10),
                                              spreadRadius: 2,
                                            ),
                                            BoxShadow(
                                              color: AppTheme.accentSaffron
                                                  .withValues(alpha: 0.10),
                                              blurRadius: 20,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            32,
                                          ),
                                          child: Image.asset(
                                            'assets/images/logo.png',
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 28),

                          // Animated Tagline & Badges
                          AnimatedBuilder(
                            animation: _mainController,
                            builder: (context, child) {
                              return Transform.translate(
                                offset: Offset(0, _taglineSlideAnimation.value),
                                child: Opacity(
                                  opacity: _taglineFadeAnimation.value,
                                  child: Column(
                                    children: [
                                      // Brand Name in Royal Navy
                                      const Text(
                                        'Haqdaar',
                                        style: TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.5,
                                          color: AppTheme.primaryNavy,
                                        ),
                                      ),
                                      const SizedBox(height: 6),

                                      // Tagline
                                      const Text(
                                        'Right Schemes. Real Support.',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.royalNavy,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),

                                      // Subtitle
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 24,
                                            height: 2,
                                            color: AppTheme.accentSaffron,
                                          ),
                                          const Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            child: Text(
                                              'For Every Indian',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.textMuted,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            width: 24,
                                            height: 2,
                                            color: AppTheme.forestGreen,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                          const Spacer(),

                          // Sleek Loading Indicator with national badge
                          Column(
                            children: [
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.8,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppTheme.accentSaffron,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Empowering Indian Citizens',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textMuted.withValues(
                                    alpha: 0.8,
                                  ),
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
