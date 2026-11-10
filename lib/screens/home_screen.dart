import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../core/localization/app_translations.dart';
import '../core/services/settings_service.dart';
import '../core/services/auth_service.dart';
import '../widgets/blinking_badge.dart';
import 'wizard/adaptive_wizard_screen.dart';
import 'schemes_directory_screen.dart';
import 'internships/internships_screen.dart';
import 'profile/profile_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  final SettingsService settings;
  final AuthService? auth;
  final void Function(int index)? onNavigateToTab;

  const HomeScreen({
    super.key,
    required this.settings,
    this.auth,
    this.onNavigateToTab,
  });

  void _showLanguagePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final filtered = SettingsService.supportedLanguages.where((l) {
              final q = query.toLowerCase().trim();
              if (q.isEmpty) return true;
              return l['name']!.toLowerCase().contains(q) ||
                  l['native']!.toLowerCase().contains(q) ||
                  l['code']!.toLowerCase().contains(q);
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.translate_rounded, color: AppTheme.accentSaffron),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Choose Language (23 Languages)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search language (हिंदी, বাংলা, தமிழ்...)',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (val) {
                          setModalState(() => query = val);
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollController,
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) => const Divider(height: 1, color: AppTheme.borderSubtle),
                          itemBuilder: (context, i) {
                            final l = filtered[i];
                            final isSelected = settings.currentLanguage == l['code'];
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              title: Text(
                                l['native']!,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 15,
                                  color: isSelected ? AppTheme.accentSaffron : AppTheme.textDark,
                                ),
                              ),
                              subtitle: Text(
                                l['name']!,
                                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle_rounded, color: AppTheme.accentSaffron)
                                  : null,
                              onTap: () {
                                settings.setLanguage(l['code']!);
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showStatePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final allList = SettingsScreen.statesList;
            final filtered = allList.where((st) {
              final q = query.toLowerCase().trim();
              if (q.isEmpty) return true;
              return st.toLowerCase().contains(q);
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded, color: AppTheme.accentSaffron),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Select State / Union Territory',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search State or UT...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (val) {
                          setModalState(() => query = val);
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollController,
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) => const Divider(height: 1, color: AppTheme.borderSubtle),
                          itemBuilder: (context, i) {
                            final st = filtered[i];
                            final isSelected = settings.selectedState == st;
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              title: Text(
                                st,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 14.5,
                                  color: isSelected ? AppTheme.accentSaffron : AppTheme.textDark,
                                ),
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle_rounded, color: AppTheme.accentSaffron)
                                  : null,
                              onTap: () {
                                settings.setSelectedState(st);
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = settings.currentLanguage;
    final isHi = settings.isHindi;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              AppStrings.get('app_name', lang),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.3),
            ),
          ],
        ),
        actions: [
          // Regional Language Pill
          TextButton.icon(
            onPressed: () => _showLanguagePicker(context),
            icon: const Icon(Icons.translate, color: Colors.white, size: 15),
            label: Text(
              SettingsService.supportedLanguages.firstWhere(
                (l) => l['code'] == lang,
                orElse: () => {'native': 'Language'},
              )['native']!,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
          ),
          // User Profile Avatar Button
          InkWell(
            onTap: () {
              if (onNavigateToTab != null) {
                onNavigateToTab!(4);
              } else if (auth != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ProfileScreen(settings: settings, auth: auth!)),
                );
              }
            },
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.only(right: 12, left: 4),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: AppTheme.accentSaffron,
                child: Text(
                  (auth?.userName.isNotEmpty == true) ? auth!.userName[0].toUpperCase() : 'C',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // State Selector Interactive Pill Banner
            InkWell(
              onTap: () => _showStatePicker(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderSubtle),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded, color: AppTheme.accentSaffron, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          text: isHi ? 'चयनित राज्य: ' : 'Region: ',
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                          children: [
                            TextSpan(
                              text: settings.selectedState,
                              style: const TextStyle(
                                color: AppTheme.primaryNavy,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.primaryNavy),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Hero Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    colors: [
                      AppTheme.primaryNavy,
                      Color(0xFF1E3E62),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.all(22.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.accentSaffron,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isHi ? 'प्रमाणित कल्याणकारी नेविगेटर' : 'Verified Welfare Navigator',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.verified_user_rounded, color: Colors.white70, size: 20),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (auth?.userName != null) ...[
                      Text(
                        isHi ? 'नमस्ते, ${auth!.userName}!' : 'Namaste, ${auth!.userName}!',
                        style: const TextStyle(
                          color: Color(0xFFFFB74D),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      AppStrings.get('tagline', lang),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      AppStrings.get('subheading', lang),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentSaffron,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 3,
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdaptiveWizardScreen(settings: settings, auth: auth),
                          ),
                        );
                      },
                      icon: const Icon(Icons.explore_rounded, size: 20),
                      label: Text(
                        AppStrings.get('btn_find_schemes', lang),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Statistics Highlights Bar
            Row(
              children: [
                _buildStatItem(Icons.policy_outlined, AppStrings.get('stat_schemes', lang)),
                const SizedBox(width: 8),
                _buildStatItem(Icons.school_outlined, AppStrings.get('stat_internships', lang)),
                const SizedBox(width: 8),
                _buildStatItem(Icons.location_city_outlined, AppStrings.get('stat_states', lang)),
              ],
            ),
            const SizedBox(height: 20),

            // 2x2 Feature Navigation Grid
            Row(
              children: [
                // Feature 1: Browse Schemes
                Expanded(
                  child: _buildActionTile(
                    icon: Icons.account_balance_rounded,
                    iconBg: AppTheme.lightGreen,
                    iconColor: AppTheme.forestGreen,
                    title: AppStrings.get('btn_browse_all', lang),
                    subtitle: isHi ? 'केंद्र व राज्य योजनाएं' : 'Central & State schemes',
                    onTap: () {
                      if (onNavigateToTab != null) {
                        onNavigateToTab!(1);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => SchemesDirectoryScreen(settings: settings)),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Feature 2: Internships
                Expanded(
                  child: _buildActionTile(
                    icon: Icons.school_rounded,
                    iconBg: const Color(0xFFFFF3E0),
                    iconColor: AppTheme.accentSaffron,
                    title: AppStrings.get('btn_internships', lang),
                    subtitle: isHi ? 'AICTE, TULIP, NATS' : 'AICTE, TULIP, NATS',
                    onTap: () {
                      if (onNavigateToTab != null) {
                        onNavigateToTab!(2);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => InternshipsScreen(settings: settings)),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Feature 3: Regional Languages
                Expanded(
                  child: _buildActionTile(
                    icon: Icons.translate_rounded,
                    iconBg: Colors.purple.shade50,
                    iconColor: Colors.purple.shade700,
                    title: isHi ? '11 भारतीय भाषाएं' : '11 Regional Languages',
                    subtitle: isHi ? 'मराठी, गुजराती, बांग्ला...' : 'Marathi, Gujarati, Bengali...',
                    onTap: () => _showLanguagePicker(context),
                  ),
                ),
                const SizedBox(width: 12),
                // Feature 4: Settings
                Expanded(
                  child: _buildActionTile(
                    icon: Icons.tune_rounded,
                    iconBg: Colors.blue.shade50,
                    iconColor: Colors.blue.shade700,
                    title: AppStrings.get('btn_settings', lang),
                    subtitle: isHi ? 'प्राथमिकताएं एवं राज्य' : 'Preferences & State',
                    onTap: () {
                      if (onNavigateToTab != null) {
                        onNavigateToTab!(5);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => SettingsScreen(settings: settings)),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Feature 5: What's New (Announced in Last 1 Month) Callout Banner
            InkWell(
              onTap: () {
                if (onNavigateToTab != null) {
                  onNavigateToTab!(3);
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryNavy.withValues(alpha: 0.95),
                      const Color(0xFF1E3E62),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    ContinuousBlinkingWidget(
                      minOpacity: 0.35,
                      maxOpacity: 1.0,
                      enableScale: true,
                      duration: const Duration(milliseconds: 650),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.accentSaffron,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accentSaffron.withValues(alpha: 0.6),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                isHi ? 'नवीनतम घोषणाएं (30 दिन)' : "What's New (Last 30 Days)",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                              ContinuousBlinkingWidget(
                                minOpacity: 0.4,
                                maxOpacity: 1.0,
                                duration: const Duration(milliseconds: 650),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentSaffron,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.accentSaffron.withValues(alpha: 0.8),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: const Text(
                                    'NEW',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isHi
                                ? 'पिछले 1 महीने में शुरू की गई नई योजनाएं और इंटर्नशिप देखें।'
                                : 'Explore schemes & internships launched in the past month.',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Why ADHIKAR Exists Mission Callout
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded, color: Colors.blue.shade800, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.get('why_adhikar_title', lang),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: Colors.blue.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppStrings.get('why_adhikar_desc', lang),
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade900, height: 1.4),
                        ),
                      ],
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

  Widget _buildActionTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.textDark),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String text) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: AppTheme.primaryNavy),
            const SizedBox(height: 4),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.textDark),
            ),
          ],
        ),
      ),
    );
  }
}
