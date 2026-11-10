import 'package:flutter/material.dart';
import '../core/localization/app_translations.dart';
import '../core/services/settings_service.dart';
import '../core/services/auth_service.dart';
import '../core/services/latest_updates_service.dart';
import '../core/theme/app_theme.dart';
import '../widgets/blinking_badge.dart';
import 'home_screen.dart';
import 'schemes_directory_screen.dart';
import 'internships/internships_screen.dart';
import 'latest/latest_updates_screen.dart';
import 'profile/profile_screen.dart';
import 'settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  final SettingsService settings;
  final AuthService auth;
  final int initialIndex;

  const MainNavigationScreen({
    super.key,
    required this.settings,
    required this.auth,
    this.initialIndex = 0,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    // Automatically refresh latest schemes and internships every time the app opens
    LatestUpdatesService.instance.fetchUpdates();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.settings.currentLanguage;

    final pages = [
      HomeScreen(
        settings: widget.settings,
        auth: widget.auth,
        onNavigateToTab: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
      SchemesDirectoryScreen(settings: widget.settings),
      InternshipsScreen(settings: widget.settings),
      LatestUpdatesScreen(settings: widget.settings),
      ProfileScreen(settings: widget.settings, auth: widget.auth),
      SettingsScreen(settings: widget.settings, auth: widget.auth),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryNavy.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: AppTheme.accentSaffron,
          unselectedItemColor: AppTheme.textMuted,
          iconSize: 22,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 9.5),
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.home_outlined),
              activeIcon: const Icon(Icons.home_rounded),
              label: AppStrings.get('nav_home', lang),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.account_balance_outlined),
              activeIcon: const Icon(Icons.account_balance_rounded),
              label: AppStrings.get('nav_schemes', lang),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.school_outlined),
              activeIcon: const Icon(Icons.school_rounded),
              label: AppStrings.get('nav_internships', lang),
            ),
            BottomNavigationBarItem(
              icon: const ContinuousBlinkingNavIcon(
                icon: Icons.bolt_outlined,
                color: AppTheme.textMuted,
              ),
              activeIcon: const ContinuousBlinkingNavIcon(
                icon: Icons.bolt_rounded,
                color: AppTheme.accentSaffron,
                isActive: true,
              ),
              label: AppStrings.get('nav_latest', lang),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.person_outline_rounded),
              activeIcon: const Icon(Icons.person_rounded),
              label: AppStrings.get('nav_profile', lang),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_outlined),
              activeIcon: const Icon(Icons.settings_rounded),
              label: AppStrings.get('nav_settings', lang),
            ),
          ],
        ),
      ),
    );
  }
}
