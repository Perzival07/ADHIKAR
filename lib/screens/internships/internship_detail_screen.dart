import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models/internship_model.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/tts_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/app_translations.dart';

class InternshipDetailScreen extends StatefulWidget {
  final InternshipModel internship;
  final SettingsService settings;

  const InternshipDetailScreen({
    super.key,
    required this.internship,
    required this.settings,
  });

  @override
  State<InternshipDetailScreen> createState() => _InternshipDetailScreenState();
}

class _InternshipDetailScreenState extends State<InternshipDetailScreen> {
  final TtsService _ttsService = TtsService();

  @override
  void dispose() {
    _ttsService.stop();
    _ttsService.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String url) async {
    if (url.trim().isEmpty) return;
    var cleanUrl = url.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }
    final uri = Uri.parse(cleanUrl);

    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    try {
      if (await launchUrl(uri, mode: LaunchMode.platformDefault)) return;
    } catch (_) {}
    try {
      if (await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) return;
    } catch (_) {}
    try {
      if (await launchUrl(uri, mode: LaunchMode.inAppWebView)) return;
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open portal: $cleanUrl'),
        backgroundColor: Colors.red.shade700,
        action: SnackBarAction(
          label: 'Copy Link',
          textColor: Colors.white,
          onPressed: () => Clipboard.setData(ClipboardData(text: cleanUrl)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.settings.currentLanguage;
    final isHi = widget.settings.isHindi;
    final item = widget.internship;
    final title = isHi && item.titleHi.isNotEmpty ? item.titleHi : item.title;
    final about = isHi && item.aboutHi.isNotEmpty ? item.aboutHi : item.about;
    final eligibility = isHi && item.eligibilityHi.isNotEmpty ? item.eligibilityHi : item.eligibility;

    final speechSummary = '$title. Organization: ${item.organization}. Stipend: ${item.stipend}. Duration: ${item.duration}. Eligibility: $eligibility';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isHi ? 'इंटर्नशिप विवरण' : 'Internship Details',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          ListenableBuilder(
            listenable: _ttsService,
            builder: (context, _) {
              final isSpeaking = _ttsService.isPlaying;
              return IconButton(
                icon: Icon(
                  isSpeaking ? Icons.volume_up_rounded : Icons.volume_up_outlined,
                  color: isSpeaking ? AppTheme.accentSaffron : Colors.white,
                ),
                tooltip: isSpeaking
                    ? AppStrings.get('stop_audio', lang)
                    : AppStrings.get('listen_audio', lang),
                onPressed: () {
                  if (isSpeaking) {
                    _ttsService.stop();
                  } else {
                    _ttsService.speak(speechSummary, langCode: lang, isHindi: isHi);
                  }
                },
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Portal, Company Type, Work Mode, & Category Pills
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    item.portalSource,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryNavy,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.purple.shade200),
                  ),
                  child: Text(
                    item.companyType,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple.shade800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.workMode == 'Remote' ? Icons.wifi_rounded : (item.workMode == 'Hybrid' ? Icons.swap_horiz_rounded : Icons.location_city_rounded),
                        size: 13,
                        color: Colors.blue.shade800,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.workMode,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: item.isExpired ? Colors.grey.shade100 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: item.isExpired ? Colors.grey.shade300 : Colors.green.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.isExpired ? Icons.cancel_outlined : Icons.verified_rounded,
                        size: 13,
                        color: item.isExpired ? Colors.grey : Colors.green.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: item.isExpired ? Colors.grey.shade700 : Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Title
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                height: 1.3,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 6),

            // Organization
            Row(
              children: [
                const Icon(Icons.business_outlined, size: 16, color: AppTheme.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.organization,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Highlight Box: Stipend, Duration, Location, Openings
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryNavy,
                    AppTheme.primaryNavy.withValues(alpha: 0.85),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.currency_rupee_rounded,
                          label: AppStrings.get('stipend', lang),
                          value: item.stipend,
                          isHighlight: true,
                        ),
                      ),
                      Container(width: 1, height: 40, color: Colors.white24),
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.access_time_rounded,
                          label: AppStrings.get('duration', lang),
                          value: item.duration,
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.location_on_outlined,
                          label: isHi ? 'स्थान' : 'Location',
                          value: item.location,
                        ),
                      ),
                      Container(width: 1, height: 40, color: Colors.white24),
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.group_outlined,
                          label: isHi ? 'कुल रिक्तियां' : 'Openings',
                          value: item.openings,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // About Section
            _buildSectionHeader(Icons.description_outlined, isHi ? 'इंटर्नशिप परिचय' : 'About the Program'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Text(
                about,
                style: const TextStyle(fontSize: 13.5, height: 1.5, color: Color(0xFF334155)),
              ),
            ),
            const SizedBox(height: 20),

            // Eligibility Section
            _buildSectionHeader(Icons.school_outlined, AppStrings.get('eligibility', lang)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.shade50.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.amber.shade900, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      eligibility,
                      style: TextStyle(fontSize: 13.5, height: 1.45, color: Colors.brown.shade900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Perks & Benefits
            _buildSectionHeader(Icons.stars_rounded, isHi ? 'लाभ एवं प्रमाणन' : 'Perks & Certification'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                children: item.perks.map((perk) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.verified_rounded, size: 18, color: AppTheme.forestGreen),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            perk,
                            style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.textDark),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            // Required Documents
            _buildSectionHeader(Icons.folder_shared_outlined, isHi ? 'आवश्यक दस्तावेज' : 'Required Documents'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                children: item.documents.map((doc) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_box_outlined, size: 18, color: AppTheme.primaryNavy),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            doc,
                            style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.textDark),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            // Application Deadline Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_month_outlined, color: Colors.blue.shade800, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    isHi ? 'अंतिम तिथि: ' : 'Deadline: ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue.shade900),
                  ),
                  Text(
                    item.deadline,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue.shade800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Official Portal Link Card
            InkWell(
              onTap: () => _launchUrl(item.officialUrl),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.language_rounded, color: AppTheme.primaryNavy, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isHi ? 'आधिकारिक पोर्टल लिंक (Official Portal)' : 'Official Careers & Application Portal',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.officialUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryNavy,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.open_in_new_rounded, color: AppTheme.primaryNavy, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentSaffron,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _launchUrl(item.officialUrl),
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
            label: Text(
              isHi ? 'पोर्टल खोलें / आवेदन करें' : 'Open Portal / Apply Online',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryNavy),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryNavy,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    bool isHighlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: isHighlight ? AppTheme.accentSaffron : Colors.white70),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: isHighlight ? const Color(0xFFFFB74D) : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
