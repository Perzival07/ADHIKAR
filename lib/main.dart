import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/services/settings_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/latest_updates_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsService = SettingsService();
  await settingsService.init();

  final authService = AuthService();
  await authService.init();

  // Every time the user opens the app, automatically fetch latest updates
  LatestUpdatesService.instance.fetchUpdates().ignore();

  runApp(AdhikarApp(
    settings: settingsService,
    auth: authService,
  ));
}

class AdhikarApp extends StatelessWidget {
  final SettingsService settings;
  final AuthService auth;

  const AdhikarApp({
    super.key,
    required this.settings,
    required this.auth,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([settings, auth]),
      builder: (context, _) {
        return MaterialApp(
          title: 'ADHIKAR - Welfare & Internships Navigator',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: Locale(settings.currentLanguage),
          builder: (context, child) {
            return Directionality(
              textDirection: settings.isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: SplashScreen(
            settings: settings,
            auth: auth,
          ),
        );
      },
    );
  }
}
