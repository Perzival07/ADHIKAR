import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/models/citizen_profile.dart';
import '../../core/models/scheme_model.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/tts_service.dart';

class SchemeDetailScreen extends StatefulWidget {
  final SchemeModel scheme;
  final CitizenProfile profile;
  final SettingsService settings;

  const SchemeDetailScreen({
    super.key,
    required this.scheme,
    required this.profile,
    required this.settings,
  });

  @override
  State<SchemeDetailScreen> createState() => _SchemeDetailScreenState();
}

class _SchemeDetailScreenState extends State<SchemeDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TtsService _tts = TtsService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _tts.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String? urlString) async {
    if (urlString == null || urlString.trim().isEmpty) return;
    var cleanUrl = urlString.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }
    final uri = Uri.parse(cleanUrl);

    // 1. Try system browser directly
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (launched) return;
    } catch (e) {
      debugPrint('LaunchMode.externalApplication failed: $e');
    }

    // 2. Try platform default handler
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (launched) return;
    } catch (e) {
      debugPrint('LaunchMode.platformDefault failed: $e');
    }

    // 3. Try in-app custom tab / browser view
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (launched) return;
    } catch (e) {
      debugPrint('LaunchMode.inAppBrowserView failed: $e');
    }

    // 4. Try in-app webview
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.inAppWebView);
      if (launched) return;
    } catch (e) {
      debugPrint('LaunchMode.inAppWebView failed: $e');
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open portal: $cleanUrl'),
        backgroundColor: Colors.red.shade700,
        action: SnackBarAction(
          label: 'Copy Link',
          textColor: Colors.white,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: cleanUrl));
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.settings.currentLanguage;
    final isHi = widget.settings.isHindi;
    final scheme = widget.scheme;

    final title = isHi ? scheme.nameHi : scheme.name;
    final benefit = isHi ? scheme.benefitHi : scheme.benefit;

    final isFarmingScheme = scheme.category.toLowerCase().contains('agriculture') ||
        scheme.category.toLowerCase().contains('farmer') ||
        scheme.name.toLowerCase().contains('kisan') ||
        scheme.name.toLowerCase().contains('farmer') ||
        scheme.id.contains('kisan') ||
        scheme.defaultPlainReason.toLowerCase().contains('farming');

    String reason;
    bool isEligibleForScheme = true;

    if (widget.profile.isSalaried && isFarmingScheme) {
      isEligibleForScheme = false;
      reason = isHi
          ? 'पात्रता शर्त: यह योजना कृषि भूमि धारक सक्रिय किसानों के लिए निर्धारित है। वेतनभोगी (Salaried) नागरिक इस योजना हेतु पात्र नहीं हैं।'
          : 'Eligibility Criterion: This scheme is strictly designated for landholding practicing farmers. Salaried employees are not eligible for agricultural income support.';
    } else if (!widget.profile.isFarmer && isFarmingScheme) {
      isEligibleForScheme = false;
      reason = isHi
          ? 'पात्रता शर्त: यह योजना पंजीकृत भूमिधारक किसानों के लिए है। अन्य व्यवसायों के नागरिक इसके पात्र नहीं हैं।'
          : 'Eligibility Criterion: This scheme is designated for verified farmers holding cultivable agricultural land. Non-farming professions do not qualify.';
    } else {
      reason = isHi
          ? (scheme.generatedReasonHi ?? scheme.defaultPlainReasonHi)
          : (scheme.generatedReason ?? scheme.defaultPlainReason);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isHi ? 'योजना विवरण' : 'Scheme Details'),
        actions: [
          IconButton(
            icon: Icon(_tts.isPlaying ? Icons.volume_off : Icons.volume_up, color: Colors.white),
            tooltip: isHi ? 'सुनें' : 'Listen',
            onPressed: () {
              if (_tts.isPlaying) {
                _tts.stop();
              } else {
                final text = '$title. $benefit. $reason';
                _tts.speak(text, langCode: lang, isHindi: isHi);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Scheme Header Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        scheme.category,
                        style: const TextStyle(
                          color: AppTheme.accentSaffron,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.isCentral
                            ? AppTheme.primaryNavy.withValues(alpha: 0.08)
                            : Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        scheme.isCentral
                            ? (isHi ? 'केंद्रीय सरकार' : 'Central Govt')
                            : (isHi ? '${scheme.stateScope} राज्य' : '${scheme.stateScope} State'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: scheme.isCentral ? AppTheme.primaryNavy : Colors.purple.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        scheme.department,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryNavy,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.mintLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFABF5D1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.currency_rupee_rounded, size: 16, color: AppTheme.forestGreen),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          benefit,
                          style: const TextStyle(
                            color: AppTheme.forestGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _buildBadgeTag(Icons.verified_rounded, scheme.officialSource, Colors.green.shade800, Colors.green.shade50),
                    _buildBadgeTag(Icons.calendar_today_rounded, scheme.deadline, Colors.blue.shade800, Colors.blue.shade50),
                    if (scheme.educationLevel != 'All')
                      _buildBadgeTag(Icons.school_rounded, scheme.educationLevel, Colors.teal.shade800, Colors.teal.shade50),
                    if (scheme.incomeCeiling != 'No Limit')
                      _buildBadgeTag(Icons.payments_outlined, scheme.incomeCeiling, Colors.orange.shade900, Colors.orange.shade50),
                  ],
                ),
              ],
            ),
          ),

          // Tabs
          TabBar(
            controller: _tabController,
            labelColor: AppTheme.primaryNavy,
            indicatorColor: AppTheme.accentSaffron,
            indicatorWeight: 3,
            tabs: [
              Tab(text: isHi ? 'पात्रता कारण' : 'Eligibility'),
              Tab(text: isHi ? 'दस्तावेज चेकलिस्ट' : 'Documents'),
              Tab(text: isHi ? 'आवेदन मार्ग' : 'Application Route'),
            ],
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildEligibilityTab(reason, isHi, lang, isEligibleForScheme),
                _buildDocumentsTab(isHi),
                _buildRouteTab(isHi),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              offset: const Offset(0, -3),
              blurRadius: 10,
            ),
          ],
          border: const Border(top: BorderSide(color: AppTheme.borderSubtle)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                  onPressed: () => _launchUrl(scheme.officialPortalUrl),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(
                    isHi ? 'आधिकारिक पोर्टल खोलें (Open Portal)' : 'Open Official Portal',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // TAB 1: ELIGIBILITY & GROUNDED GUIDELINES
  Widget _buildEligibilityTab(String reason, bool isHi, String lang, bool isEligible) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Plain Reason Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isEligible
                  ? Colors.blue.shade50.withValues(alpha: 0.7)
                  : Colors.orange.shade50.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isEligible ? Colors.blue.shade200 : Colors.orange.shade300,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isEligible ? Icons.verified_outlined : Icons.info_outline_rounded,
                      color: isEligible ? Colors.blue : Colors.orange.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isEligible
                            ? (isHi ? 'आप इस योजना के लिए क्यों पात्र हैं:' : 'Why you qualify for this scheme:')
                            : (isHi ? 'पात्रता आवश्यकता एवं शर्तें:' : 'Eligibility Criteria & Requirements:'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: isEligible ? AppTheme.primaryNavy : Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  reason,
                  style: const TextStyle(fontSize: 13.5, height: 1.45, color: AppTheme.textDark),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Timeline & Department Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildDetailRow(
                    Icons.account_balance_outlined,
                    isHi ? 'प्रशासनिक विभाग' : 'Department',
                    widget.scheme.department,
                  ),
                  const Divider(height: 20, color: AppTheme.borderSubtle),
                  _buildDetailRow(
                    Icons.timer_outlined,
                    isHi ? 'अनुमानित समय' : 'Disbursement Timeline',
                    widget.scheme.timeline,
                  ),
                  const Divider(height: 20, color: AppTheme.borderSubtle),
                  _buildDetailRow(
                    Icons.source_outlined,
                    isHi ? 'आधिकारिक स्रोत' : 'Source Circular',
                    widget.scheme.provenance,
                  ),
                  const Divider(height: 20, color: AppTheme.borderSubtle),
                  _buildDetailRow(
                    Icons.update_rounded,
                    isHi ? 'अंतिम सत्यापन' : 'Last Verified',
                    widget.scheme.lastVerifiedDate,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Grounded Guidelines & FAQs Box
          _buildOfficialGuidanceCard(isHi, lang),
          const SizedBox(height: 16),

          // Verification Caveat Callout
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isHi ? 'महत्वपूर्ण शर्त / अपवाद:' : 'Important Exclusion / Verification Notice:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: Colors.amber.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.scheme.verificationCaveat,
                        style: TextStyle(fontSize: 12, height: 1.4, color: Colors.brown.shade900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 2: DOCUMENTS CHECKLIST
  Widget _buildDocumentsTab(bool isHi) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final docs = widget.scheme.documents;
        int checkedCount = 0;
        for (var d in docs) {
          if (widget.settings.isDocumentChecked(widget.scheme.id, d.id)) {
            checkedCount++;
          }
        }

        return Column(
          children: [
            // Progress Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isHi
                              ? 'तैयार दस्तावेज: $checkedCount/${docs.length}'
                              : 'Assembled: $checkedCount of ${docs.length} documents',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: docs.isEmpty ? 0 : checkedCount / docs.length,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.forestGreen),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.borderSubtle),

            // Checklist Items
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final isChecked = widget.settings.isDocumentChecked(widget.scheme.id, doc.id);
                  final name = isHi ? doc.nameHi : doc.name;
                  final tip = isHi ? doc.tipHi : doc.tip;

                  return Card(
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isChecked ? AppTheme.forestGreen : AppTheme.borderSubtle,
                        width: isChecked ? 1.5 : 1,
                      ),
                    ),
                    child: CheckboxListTile(
                      value: isChecked,
                      activeColor: AppTheme.forestGreen,
                      onChanged: (val) {
                        widget.settings.toggleDocumentCheck(widget.scheme.id, doc.id);
                      },
                      title: Text(
                        name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          decoration: isChecked ? TextDecoration.lineThrough : null,
                          color: isChecked ? AppTheme.textMuted : AppTheme.textDark,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            '${isHi ? "जारीकर्ता: " : "Authority: "}${doc.issuingAuthority}',
                            style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                          ),
                          if (tip.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              '💡 $tip',
                              style: const TextStyle(fontSize: 11.5, color: AppTheme.accentSaffron),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // TAB 3: APPLICATION ROUTE & BDO
  Widget _buildRouteTab(bool isHi) {
    final routes = widget.scheme.routes;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isHi ? 'आवेदन कैसे और कहां करें:' : 'Application Pathways:',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.primaryNavy),
          ),
          const SizedBox(height: 12),
          ...routes.map((route) {
            final title = isHi ? route.titleHi : route.title;
            final instructions = isHi ? route.instructionsHi : route.instructions;
            final portalUrl = route.url ?? widget.scheme.officialPortalUrl;

            return Card(
              elevation: 1.5,
              margin: const EdgeInsets.only(bottom: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppTheme.borderSubtle),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.1),
                          child: Icon(_getRouteIcon(route.type), size: 18, color: AppTheme.primaryNavy),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      instructions,
                      style: const TextStyle(fontSize: 13, height: 1.45, color: Color(0xFF334155)),
                    ),
                    if (portalUrl.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentSaffron,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _launchUrl(portalUrl),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: Text(
                          isHi ? 'आधिकारिक पोर्टल खोलें' : 'Open Portal ($portalUrl)',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  IconData _getRouteIcon(RouteType type) {
    switch (type) {
      case RouteType.online:
        return Icons.language_rounded;
      case RouteType.csc:
        return Icons.storefront_rounded;
      case RouteType.panchayat:
        return Icons.domain_rounded;
      case RouteType.blockOffice:
        return Icons.account_balance_rounded;
      case RouteType.bankBranch:
        return Icons.account_balance_wallet_rounded;
    }
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryNavy),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark),
          ),
        ),
      ],
    );
  }

  Widget _buildOfficialGuidanceCard(bool isHi, String lang) {
    final scheme = widget.scheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.menu_book_rounded, color: AppTheme.primaryNavy, size: 20),
              const SizedBox(width: 8),
              Text(
                isHi ? 'सरकारी दिशानिर्देश एवं परामर्श' : 'Official Scheme Guidelines',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isHi
                ? '• आवेदन से पूर्व सुनिश्चित करें कि आपका आधार बैंक खाते से डीबीटी (DBT) हेतु मैप किया हुआ है।\n• किसी भी बिचौलिए को कोई शुल्क न दें। सरकारी पोर्टल एवं जन सेवा केंद्र पर तय सरकारी शुल्क ही मान्य है।\n• योजना संबंधी किसी भी शंका के निवारण हेतु अपने विकास खंड अधिकारी (BDO) या तहसीलदार कार्यालय से संपर्क करें।'
                : '• Ensure your Aadhaar is linked with your savings bank account for direct benefit transfer (DBT).\n• Avoid middlemen. Always apply via the official government portal or authorized CSC.\n• In case of discrepancies in land or income records, verify directly at your local Block Office or Tehsil.',
            style: const TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _launchUrl(scheme.officialPortalUrl),
            icon: const Icon(Icons.link_rounded, size: 16),
            label: Text(
              isHi ? 'आधिकारिक पोर्टल लिंक' : 'Official Website: ${scheme.officialPortalUrl}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeTag(IconData icon, String text, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: textColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: textColor),
          ),
        ],
      ),
    );
  }
}
