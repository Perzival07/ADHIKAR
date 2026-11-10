import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/app_translations.dart';
import '../../core/models/citizen_profile.dart';
import '../../core/models/scheme_model.dart';
import '../../core/config/rag_config.dart';
import '../../core/models/rag_models.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/recommendation_api_client.dart';
import '../../core/services/recommendation_repository.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/tts_service.dart';
import '../wizard/adaptive_wizard_screen.dart';
import 'scheme_detail_screen.dart';

class SchemesResultScreen extends StatefulWidget {
  final CitizenProfile profile;
  final List<SchemeModel> eligibleSchemes;
  final SettingsService settings;

  /// Injectable for tests. Default: AI backend when RAG_API_URL is set, otherwise rules only.
  final RecommendationRepository? repository;

  /// When signed in to a real account, requests carry the user's access token.
  final AuthService? auth;

  const SchemesResultScreen({
    super.key,
    required this.profile,
    required this.eligibleSchemes,
    required this.settings,
    this.repository,
    this.auth,
  });

  @override
  State<SchemesResultScreen> createState() => _SchemesResultScreenState();
}

class _SchemesResultScreenState extends State<SchemesResultScreen> {
  final TtsService _tts = TtsService();
  String _selectedCategory = 'All';

  // Rule-based results are shown instantly; AI results replace them if/when the backend answers.
  late List<SchemeModel> _schemes = List.of(widget.eligibleSchemes);
  RecommendationResult? _result;
  bool _loadingAi = false;

  RecommendationRepository get _repo =>
      widget.repository ??
      (_defaultRepo ??= RecommendationRepository(
          api: RagConfig.isConfigured ? RecommendationApiClient(accessToken: widget.auth?.accessToken) : null));
  RecommendationRepository? _defaultRepo;

  String _aiLanguage = '';
  int _aiRequestId = 0; // ignore answers that arrive after a newer request was started

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettingsChanged);
    if (widget.settings.aiRecommendationsEnabled) {
      _loadAi();
    }
  }

  /// The AI reasons are written in the language that was current when they were requested, so a language
  /// change (or toggling AI on/off) must refresh them instead of leaving stale text on screen.
  void _onSettingsChanged() {
    if (!mounted) return;
    final enabled = widget.settings.aiRecommendationsEnabled;
    if (!enabled) {
      _aiRequestId++; // drop any in-flight answer
      if (_result != null || _loadingAi) {
        setState(() {
          _result = null;
          _loadingAi = false;
          _schemes = List.of(widget.eligibleSchemes);
        });
      }
    } else if (widget.settings.currentLanguage != _aiLanguage || _result == null && !_loadingAi) {
      _loadAi();
    }
  }

  Future<void> _loadAi() async {
    final requestId = ++_aiRequestId;
    final language = widget.settings.currentLanguage;
    _aiLanguage = language;
    setState(() => _loadingAi = true);
    final result = await _repo.recommend(
      widget.profile,
      language: language,
      aiEnabled: true,
    );
    if (!mounted || requestId != _aiRequestId) return;
    setState(() {
      _loadingAi = false;
      _result = result;
      if (result.isAi) {
        _schemes = result.schemes;
        if (_selectedCategory != 'All' && !_schemes.any((s) => s.category == _selectedCategory)) {
          _selectedCategory = 'All';
        }
      }
    });
  }

  bool get _isAi => _result?.isAi ?? false;

  Future<void> _launchPortalUrl(String urlString) async {
    if (urlString.trim().isEmpty) return;
    var cleanUrl = urlString.trim();
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
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.settings.currentLanguage;
    final isHi = widget.settings.isHindi;

    final categories = ['All', ..._schemes.map((s) => s.category).toSet()];
    final displayedSchemes = _selectedCategory == 'All'
        ? _schemes
        : _schemes.where((s) => s.category == _selectedCategory).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('results_title', lang)),
        actions: [
          IconButton(
            icon: Icon(
              _tts.isPlaying ? Icons.volume_off : Icons.volume_up,
              color: Colors.white,
            ),
            tooltip: isHi ? 'आवाज बंद/चालू करें' : 'Toggle Voice',
            onPressed: () {
              if (_tts.isPlaying) {
                _tts.stop();
              } else if (displayedSchemes.isNotEmpty) {
                final text = isHi
                    ? 'आपके लिए ${displayedSchemes.length} योजनाएं खोजी गई हैं। पहली योजना है ${displayedSchemes.first.nameHi}।'
                    : 'Found ${displayedSchemes.length} schemes for you. First scheme is ${displayedSchemes.first.name}.';
                _tts.speak(text, langCode: lang, isHindi: isHi);
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Verified Header Banner
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryNavy, Color(0xFF1E3A5F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.accentSaffron,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isHi
                              ? '${_schemes.length} योजनाएं पात्र'
                              : '${_schemes.length} Schemes Matched',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: _buildModeBadge(isHi)),
                      const Spacer(),
                      const Icon(Icons.verified_rounded, color: Colors.white70, size: 20),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isHi
                        ? '${widget.profile.state} एवं केंद्र सरकार में आपकी पात्रता'
                        : 'Entitlements in ${widget.profile.state} & Central Govt',
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isHi
                        ? 'आयु: ${widget.profile.age} वर्ष | पेशा: ${widget.profile.occupation} | श्रेणी: ${widget.profile.socialCategory} | राशन: ${widget.profile.rationCard}'
                        : 'Age: ${widget.profile.age} | ${widget.profile.occupation} | ${widget.profile.socialCategory} | ${widget.profile.rationCard}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Strategic Grounded Advice Card
            _buildStrategicAdviceCard(isHi, lang),
            const SizedBox(height: 16),

            // Category Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: categories.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                        cat == 'All' ? AppStrings.get('filter_all', lang) : cat,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : AppTheme.textDark,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryNavy,
                      backgroundColor: Colors.white,
                      checkmarkColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isSelected ? AppTheme.primaryNavy : AppTheme.borderSubtle,
                        ),
                      ),
                      onSelected: (val) {
                        setState(() {
                          _selectedCategory = cat;
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),

            // Scheme Cards List
            if (displayedSchemes.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Text(
                    isHi ? 'इस श्रेणी में कोई योजना नहीं मिली।' : 'No schemes found in this category.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              )
            else
              ...displayedSchemes.map((scheme) => _buildSchemeCard(scheme, isHi, lang)),

            const SizedBox(height: 16),

            // Anti-Hallucination & Provenance Warning Note
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, color: Colors.grey.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppStrings.get('anti_hallucination_note', lang),
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, height: 1.4),
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

  Widget _buildStrategicAdviceCard(bool isHi, String lang) {
    if (_schemes.isEmpty) return const SizedBox.shrink();

    final topScheme = _schemes.first;
    final topName = isHi ? topScheme.nameHi : topScheme.name;
    final adviceText = isHi
        ? 'रणनीतिक सुझाव: आपकी प्रोफ़ाइल के अनुसार सबसे पहले "$topName" पर ध्यान दें। आवश्यक दस्तावेज जैसे आधार और बैंक खाता सक्रिय रखें और निकटतम सीएससी केंद्र या आधिकारिक पोर्टल से आवेदन शुरू करें।'
        : 'Priority Action: Start with "$topName". Ensure your Aadhaar is seeded with your bank account for DBT and verify documents at your local CSC or online portal.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tips_and_updates_rounded, color: AppTheme.accentSaffron, size: 20),
              const SizedBox(width: 8),
              Text(
                isHi ? 'अधिकार रणनीतिक मार्गदर्शन' : 'ADHIKAR Priority Advisor',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  color: Color(0xFFC05621),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.volume_up, size: 20, color: Color(0xFFC05621)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _tts.speak(adviceText, langCode: lang, isHindi: isHi),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            adviceText,
            style: const TextStyle(fontSize: 13, height: 1.45, color: Color(0xFF2D3748)),
          ),
        ],
      ),
    );
  }

  Widget _buildSchemeCard(SchemeModel scheme, bool isHi, String lang) {
    final title = isHi ? scheme.nameHi : scheme.name;
    final benefit = isHi ? scheme.benefitHi : scheme.benefit;
    final extra = _result?.extras[scheme.id];
    final reason = extra?.reason ??
        (isHi
            ? (scheme.generatedReasonHi ?? scheme.defaultPlainReasonHi)
            : (scheme.generatedReason ?? scheme.defaultPlainReason));

    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.borderSubtle),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SchemeDetailScreen(
                scheme: scheme,
                profile: widget.profile,
                settings: widget.settings,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Category Tag & Central/State Tag
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      scheme.category,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentSaffron,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.isCentral
                          ? AppTheme.primaryNavy.withValues(alpha: 0.08)
                          : Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      scheme.isCentral
                          ? (isHi ? 'केंद्रीय योजना' : 'Central')
                          : (isHi ? '${scheme.stateScope} राज्य' : scheme.stateScope),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: scheme.isCentral ? AppTheme.primaryNavy : Colors.purple.shade800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.volume_up, size: 20, color: AppTheme.primaryNavy),
                    tooltip: isHi ? 'सुनें' : 'Listen',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      final speechText = '$title. $benefit. $reason';
                      _tts.speak(speechText, langCode: lang, isHindi: isHi);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),

              // Benefit Highlight Callout
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.mintLight.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFABF5D1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.currency_rupee_rounded, size: 18, color: AppTheme.forestGreen),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        benefit,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.forestGreen,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Why You Qualify Snippet
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline, size: 16, color: AppTheme.forestGreen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reason,
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155), height: 1.4),
                    ),
                  ),
                ],
              ),
              if (extra != null) ..._buildAiDetails(scheme, extra, isHi),
              const SizedBox(height: 14),

              // Bottom Metadata: Documents Count & Action
              Row(
                children: [
                  const Icon(Icons.file_copy_outlined, size: 15, color: AppTheme.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    '${scheme.documents.length} ${isHi ? "दस्तावेज आवश्यक" : "Documents Needed"}',
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  if (scheme.officialPortalUrl.isNotEmpty) ...[
                    InkWell(
                      onTap: () => _launchPortalUrl(scheme.officialPortalUrl),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.18)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.language_rounded, size: 12, color: AppTheme.primaryNavy),
                            const SizedBox(width: 4),
                            Text(
                              isHi ? 'पोर्टल' : 'Portal',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryNavy),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Row(
                    children: [
                      Text(
                        isHi ? 'विवरण देखें' : 'View Details',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentSaffron,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded, size: 16, color: AppTheme.accentSaffron),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeBadge(bool isHi) {
    if (_loadingAi) {
      return Container(
        key: const Key('mode_badge_loading'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.6, color: Colors.white)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                isHi ? 'AI से सुधार रहे हैं…' : 'Improving with AI…',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 10.5),
              ),
            ),
          ],
        ),
      );
    }
    final ai = _isAi;
    return Container(
      key: const Key('mode_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ai ? const Color(0xFF2B6CB0) : Colors.white24,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ai ? Icons.auto_awesome : Icons.rule_rounded, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              ai ? (isHi ? 'AI-सहायता प्राप्त' : 'AI-assisted') : (isHi ? 'नियम-आधारित' : 'Rule-based'),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAiDetails(SchemeModel scheme, AiExtras extra, bool isHi) {
    final widgets = <Widget>[];
    if (extra.citations.isNotEmpty) {
      widgets
        ..add(const SizedBox(height: 10))
        ..add(Wrap(
          key: Key('sources_${scheme.id}'),
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(isHi ? 'स्रोत:' : 'Sources:', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            for (final c in extra.citations)
              ActionChip(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                avatar: const Icon(Icons.menu_book_outlined, size: 13),
                label: Text(c.section.isNotEmpty ? c.section : (isHi ? 'आधिकारिक दस्तावेज़' : 'Official document'),
                    style: const TextStyle(fontSize: 11)),
                onPressed: () => _openSource(c, scheme),
              ),
          ],
        ));
    }
    if (extra.missingInfo.isNotEmpty || extra.needsMoreInfo) {
      widgets
        ..add(const SizedBox(height: 10))
        ..add(Container(
          key: Key('missing_${scheme.id}'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7E6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFFD591)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 15, color: Color(0xFFB45309)),
                  const SizedBox(width: 6),
                  Text(isHi ? 'पुष्टि के लिए जानकारी चाहिए' : 'To confirm, we need',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFB45309))),
                ],
              ),
              const SizedBox(height: 4),
              for (final m in extra.missingInfo) Text('• $m', style: const TextStyle(fontSize: 11.5, height: 1.35)),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _editAnswers,
                  child: Text(isHi ? 'मेरे उत्तर बदलें' : 'Update my answers'),
                ),
              ),
            ],
          ),
        ));
    }
    return widgets;
  }

  void _openSource(RagCitation c, SchemeModel scheme) {
    final url = c.url.isNotEmpty ? c.url : scheme.officialPortalUrl;
    if (url.isNotEmpty) {
      _launchPortalUrl(url);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SchemeDetailScreen(scheme: scheme, profile: widget.profile, settings: widget.settings),
        ),
      );
    }
  }

  void _editAnswers() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AdaptiveWizardScreen(
          settings: widget.settings,
          initialProfile: widget.profile,
          repository: widget.repository,
        ),
      ),
    );
  }
}
