import 'package:flutter/material.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/app_translations.dart';

import '../../core/models/administrative_regions.dart';
import '../../core/services/auth_service.dart';
import 'profile/profile_screen.dart';
import 'auth/sign_in_screen.dart';

class SettingsScreen extends StatelessWidget {
  final SettingsService settings;
  final AuthService? auth;

  const SettingsScreen({
    super.key,
    required this.settings,
    this.auth,
  });

  static List<String> get statesList => IndianRegions.allRegionNames;

  @override
  Widget build(BuildContext context) {
    final lang = settings.currentLanguage;
    final isHi = settings.isHindi;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              AppStrings.get('btn_settings', lang),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (auth != null) ...[
              _buildUserProfileCard(context, lang, isHi),
              const SizedBox(height: 16),
            ],
            // Language Selection Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.accentSaffron.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.translate_rounded, color: AppTheme.accentSaffron),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isHi ? 'भाषा चुनें (Select Regional Language)' : 'App Language',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                isHi
                                    ? 'संविधान की 8वीं अनुसूची की सभी 22 भाषाएं + अंग्रेज़ी (23 भाषाएं)'
                                    : 'All 22 Scheduled Indian Languages + English (23 Languages)',
                                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: AppTheme.borderSubtle),
                    const SizedBox(height: 12),

                    // Grid of Languages
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: SettingsService.supportedLanguages.map((langItem) {
                        final code = langItem['code']!;
                        final native = langItem['native']!;
                        final englishName = langItem['name']!;
                        final isSelected = lang == code;

                        return InkWell(
                          onTap: () {
                            settings.setLanguage(code);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: (MediaQuery.of(context).size.width - 72) / 2,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? AppTheme.primaryNavy : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? AppTheme.primaryNavy : AppTheme.borderSubtle,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        native,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isSelected ? Colors.white : AppTheme.textDark,
                                        ),
                                      ),
                                      Text(
                                        englishName,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isSelected ? Colors.white70 : AppTheme.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle_rounded, color: AppTheme.accentSaffron, size: 18),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // State Preference Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.location_city_rounded, color: Colors.blue.shade800),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isHi ? 'राज्य प्राथमिकता (Preferred State)' : 'Default State Filter',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                isHi ? 'राज्य-विशिष्ट योजनाओं को प्राथमिकता देने हेतु' : 'Customizes state-specific scheme discovery',
                                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: statesList.contains(settings.selectedState) ? settings.selectedState : 'All India',
                      decoration: InputDecoration(
                        labelText: isHi ? 'चयनित राज्य' : 'Selected State',
                        prefixIcon: const Icon(Icons.map_outlined, color: AppTheme.primaryNavy),
                      ),
                      items: statesList.map((st) {
                        return DropdownMenuItem<String>(
                          value: st,
                          child: Text(
                            st,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          settings.setSelectedState(val);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // AI recommendations (beta) toggle
            ListenableBuilder(
              listenable: settings,
              builder: (context, _) => Card(
                child: SwitchListTile(
                  key: const Key('ai_toggle'),
                  secondary: const Icon(Icons.auto_awesome, color: AppTheme.primaryNavy),
                  title: Text(
                    isHi ? 'AI सुझाव (बीटा)' : 'AI recommendations (beta)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  subtitle: Text(
                    !settings.aiRecommendationsAvailable
                        ? (isHi
                            ? 'इस ऐप में AI सर्वर सेट नहीं है, इसलिए केवल नियम-आधारित परिणाम दिखते हैं।'
                            : 'No AI server is configured in this build, so only rule-based results are shown.')
                        : (isHi
                            ? 'चालू होने पर आपके उत्तर (आयु, राज्य, पेशा, आय वर्ग, श्रेणी) AI सर्वर को भेजे जाते हैं ताकि सरल भाषा में कारण और स्रोत मिल सकें। आपका नाम, फोन या ईमेल कभी नहीं भेजा जाता। पात्रता हमेशा आपके फोन के नियम तय करते हैं।'
                            : 'When on, your answers (age, state, occupation, income band, category) are sent to the AI server to write plain-language reasons with sources. Your name, phone or email are never sent. Eligibility is always decided by the rules on your phone.'),
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                  value: settings.aiRecommendationsEnabled,
                  onChanged: settings.aiRecommendationsAvailable ? (v) => settings.setAiRecommendationsEnabled(v) : null,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Privacy & Architecture Assurance Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.shield_outlined, color: AppTheme.forestGreen),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isHi ? 'गोपनीयता और डेटा सुरक्षा' : 'Data Privacy & Architecture',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildFeatureBullet(
                      icon: Icons.offline_bolt_outlined,
                      title: isHi ? '100% ऑफ़लाइन नियम प्रणाली' : '100% Offline Rule Engine',
                      desc: isHi
                          ? 'सभी पात्रता शर्तें और गणनाएं आपके फोन पर स्थानीय रूप से चलती हैं।'
                          : 'All scheme eligibility determinations run on-device. The optional AI beta (off unless a server is configured) only adds explanations.',
                    ),
                    const SizedBox(height: 10),
                    _buildFeatureBullet(
                      icon: Icons.no_accounts_outlined,
                      title: isHi ? 'शून्य डेटा भंडारण (Zero Data Retention)' : 'Zero Personal Data Retention',
                      desc: isHi
                          ? 'कोई भी व्यक्तिगत पहचानकर्ता (आधार, नाम) किसी बाहरी सर्वर पर संग्रहीत नहीं किया जाता।'
                          : 'No personally identifiable information is ever stored or transmitted.',
                    ),
                    const SizedBox(height: 10),
                    _buildFeatureBullet(
                      icon: Icons.verified_outlined,
                      title: isHi ? 'सरकारी परिपत्रों पर आधारित' : 'Zero Hallucinations',
                      desc: isHi
                          ? 'प्रत्येक पात्रता सीमा myScheme और आधिकारिक राजपत्र अधिसूचनाओं से जांची गई है।'
                          : 'Direct provenance stamped against ministry gazette circulars with verified dates.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (auth != null && auth!.isAuthenticated) ...[
              _buildSignOutCard(context, lang, isHi),
              const SizedBox(height: 16),
            ],

            // App Version Footer
            Center(
              child: Column(
                children: [
                  Text(
                    '${AppStrings.get("app_name", lang)} v1.0.0 (Production Build)',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Government Social Welfare & AICTE Internship Navigator',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureBullet({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppTheme.forestGreen),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserProfileCard(BuildContext context, String lang, bool isHi) {
    final user = auth?.currentUser;
    final isAuthenticated = auth?.isAuthenticated ?? false;

    if (!isAuthenticated || user == null) {
      return Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.borderSubtle),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.1),
                child: const Icon(Icons.person_outline, color: AppTheme.primaryNavy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isHi ? 'नागरिक खाता' : 'Citizen Account',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      isHi ? 'लॉगिन करें या नया खाता बनाएं' : 'Sign in to access your profile',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SignInScreen(
                        settings: settings,
                        auth: auth!,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(AppStrings.get('sign_in', lang)),
              ),
            ],
          ),
        ),
      );
    }

    final initials = user.name.isNotEmpty
        ? user.name.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join()
        : 'U';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppTheme.borderSubtle),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileScreen(
                settings: settings,
                auth: auth!,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
                child: Text(
                  initials.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.verified, color: AppTheme.forestGreen, size: 16),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.phoneOrEmail,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.royalNavy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        user.state,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryNavy,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                        settings: settings,
                        auth: auth!,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.person, size: 16),
                label: Text(
                  isHi ? 'प्रोफ़ाइल' : 'Profile',
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignOutCard(BuildContext context, String lang, bool isHi) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.red.shade200),
      ),
      color: Colors.red.shade50.withValues(alpha: 0.5),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.logout_rounded, color: Colors.red.shade800),
        ),
        title: Text(
          AppStrings.get('sign_out', lang),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: Colors.red.shade800,
          ),
        ),
        subtitle: Text(
          isHi
              ? 'इस डिवाइस से सुरक्षित रूप से लॉग आउट करें'
              : 'Safely end your session on this device',
          style: TextStyle(fontSize: 12, color: Colors.red.shade700),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: Colors.red.shade700),
        onTap: () => _confirmSignOut(context, lang, isHi),
      ),
    );
  }

  void _confirmSignOut(BuildContext context, String lang, bool isHi) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.red.shade700),
            const SizedBox(width: 8),
            Text(AppStrings.get('sign_out', lang)),
          ],
        ),
        content: Text(
          isHi
              ? 'क्या आप वाकई हक़दार ऐप से साइन आउट करना चाहते हैं? आपकी सहेजी गई जानकारी सुरक्षित रहेगी।'
              : 'Are you sure you want to sign out of Haqdaar? Your preferences and saved eligibility will remain safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.get('cancel', lang)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await auth?.signOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => SignInScreen(
                    settings: settings,
                    auth: auth!,
                  ),
                ),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(AppStrings.get('sign_out', lang)),
          ),
        ],
      ),
    );
  }
}

