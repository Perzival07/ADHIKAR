import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/app_translations.dart';
import '../../core/models/administrative_regions.dart';
import '../../core/models/citizen_profile.dart';
import '../../core/models/scheme_model.dart';
import '../../core/models/internship_model.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/latest_updates_service.dart';
import '../../widgets/blinking_badge.dart';
import '../results/scheme_detail_screen.dart';
import '../internships/internship_detail_screen.dart';

class LatestUpdatesScreen extends StatefulWidget {
  final SettingsService settings;

  const LatestUpdatesScreen({
    super.key,
    required this.settings,
  });

  @override
  State<LatestUpdatesScreen> createState() => _LatestUpdatesScreenState();
}

class _LatestUpdatesScreenState extends State<LatestUpdatesScreen> {
  final LatestUpdatesService _latestService = LatestUpdatesService.instance;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Automatically refresh on open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _latestService.fetchUpdates();
    });
  }

  Future<void> _handleManualRefresh() async {
    await _latestService.manualRefresh();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Fetched latest schemes and internships launched in the last 1 month.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.forestGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;

    final uri = Uri.parse(cleanUrl.startsWith('http') ? cleanUrl : 'https://$cleanUrl');

    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      if (await launchUrl(uri, mode: LaunchMode.platformDefault)) return;
      if (await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) return;
      if (await launchUrl(uri, mode: LaunchMode.inAppWebView)) return;
    } catch (e) {
      debugPrint('Launch URL failed: $e');
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open portal: $cleanUrl'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade800,
      ),
    );
  }

  String _formatDateBadge(String? dateStr) {
    if (dateStr == null) return 'Announced recently';
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return dateStr;

    final diff = DateTime.now().difference(dt);
    if (diff.inDays <= 0) return 'Announced today';
    if (diff.inDays == 1) return 'Announced yesterday';
    return '${diff.inDays} days ago (${_monthName(dt.month)} ${dt.day}, ${dt.year})';
  }

  String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    if (month >= 1 && month <= 12) return months[month - 1];
    return '';
  }

  String _formatLastUpdated(DateTime? time) {
    if (time == null) return 'Checking updates...';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.settings.currentLanguage;

    return Scaffold(
      backgroundColor: AppTheme.bgSurface,
      appBar: AppBar(
        title: Row(
          children: [
            ContinuousBlinkingWidget(
              minOpacity: 0.35,
              maxOpacity: 1.0,
              duration: const Duration(milliseconds: 650),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.accentSaffron,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accentSaffron.withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.get('nav_latest', lang),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                  Text(
                    'Announced in Last 1 Month',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ListenableBuilder(
            listenable: _latestService,
            builder: (context, _) {
              return IconButton(
                icon: _latestService.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh for Latest Schemes & Internships',
                onPressed: _latestService.isLoading ? null : _handleManualRefresh,
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _latestService,
        builder: (context, _) {
          final schemes = _latestService.filteredSchemes.where((s) {
            if (_searchQuery.isEmpty) return true;
            final q = _searchQuery.toLowerCase();
            return s.name.toLowerCase().contains(q) ||
                s.nameHi.toLowerCase().contains(q) ||
                s.category.toLowerCase().contains(q) ||
                s.stateScope.toLowerCase().contains(q);
          }).toList();

          final internships = _latestService.filteredInternships.where((i) {
            if (_searchQuery.isEmpty) return true;
            final q = _searchQuery.toLowerCase();
            return i.title.toLowerCase().contains(q) ||
                i.titleHi.toLowerCase().contains(q) ||
                i.organization.toLowerCase().contains(q) ||
                i.category.toLowerCase().contains(q);
          }).toList();

          final totalVisible = schemes.length + internships.length;
          final isCompletelyEmpty = totalVisible == 0;

          return RefreshIndicator(
            color: AppTheme.accentSaffron,
            onRefresh: _latestService.manualRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                // 1. Radar Sync Banner Card
                _buildSyncHeader(lang),

                const SizedBox(height: 14),

                // 2. Search & Category Filters
                _buildSearchAndFilters(),

                const SizedBox(height: 16),

                // 3. Loading bar or Empty State or Content Cards
                if (_latestService.isLoading && totalVisible == 0) ...[
                  _buildLoadingState(),
                ] else if (isCompletelyEmpty) ...[
                  _buildEmptyState(),
                ] else ...[
                  // Schemes Section (if any)
                  if (schemes.isNotEmpty && _latestService.selectedCategory != 'Internships') ...[
                    _buildSectionHeader(
                      title: 'Newly Launched Welfare Schemes (${schemes.length})',
                      icon: Icons.account_balance_rounded,
                      color: AppTheme.primaryNavy,
                    ),
                    const SizedBox(height: 10),
                    ...schemes.map((s) => _buildSchemeCard(s, lang)),
                    const SizedBox(height: 16),
                  ],

                  // Internships Section (if any)
                  if (internships.isNotEmpty && _latestService.selectedCategory != 'Schemes') ...[
                    _buildSectionHeader(
                      title: 'Recently Announced Internships (${internships.length})',
                      icon: Icons.school_rounded,
                      color: AppTheme.forestGreen,
                    ),
                    const SizedBox(height: 10),
                    ...internships.map((i) => _buildInternshipCard(i, lang)),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSyncHeader(String lang) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryNavy, Color(0xFF1E3E62)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.12),
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
              ContinuousBlinkingWidget(
                minOpacity: 0.4,
                maxOpacity: 1.0,
                duration: const Duration(milliseconds: 650),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.forestGreen,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.forestGreen.withValues(alpha: 0.7),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Live Portal Radar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.sync_rounded, color: Colors.white70, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Synced ${_formatLastUpdated(_latestService.lastRefreshedAt)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.get('latest_title', lang),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.get('latest_subtitle', lang),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    final categories = ['All', 'Schemes', 'Internships'];
    final allStates = IndianRegions.allRegionNames;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search Input
        TextField(
          onChanged: (val) => setState(() => _searchQuery = val.trim()),
          decoration: InputDecoration(
            hintText: 'Search new schemes or internships...',
            prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primaryNavy, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () => setState(() => _searchQuery = ''),
                  )
                : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppTheme.borderSubtle),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppTheme.borderSubtle),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Category ChoiceChips Carousel
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: categories.map((cat) {
              final isSelected = _latestService.selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(
                    cat == 'All' ? 'All (Last 30 Days)' : 'New $cat',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? Colors.white : AppTheme.textDark,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppTheme.primaryNavy,
                  backgroundColor: Colors.white,
                  showCheckmark: false,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected ? AppTheme.primaryNavy : AppTheme.borderSubtle,
                    ),
                  ),
                  onSelected: (selected) {
                    if (selected) _latestService.setCategoryFilter(cat);
                  },
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 8),

        // State / Region Selection Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderSubtle),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 16, color: AppTheme.accentSaffron),
              const SizedBox(width: 8),
              const Text(
                'Filter Region:',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _latestService.selectedState,
                    isExpanded: true,
                    isDense: true,
                    icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primaryNavy),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryNavy,
                    ),
                    items: allStates.map((st) {
                      return DropdownMenuItem(
                        value: st,
                        child: Text(st, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) _latestService.setStateFilter(val);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildSchemeCard(SchemeModel scheme, String lang) {
    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppTheme.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Badge Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.accentSaffron.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.accentSaffron.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.new_releases_rounded, size: 13, color: AppTheme.accentSaffron),
                      const SizedBox(width: 4),
                      Text(
                        _formatDateBadge(scheme.announcedDate),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentSaffron,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    scheme.isCentral ? 'Central Govt' : scheme.stateScope,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryNavy,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Scheme Name
            Text(
              scheme.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryNavy,
                height: 1.25,
              ),
            ),
            if (scheme.nameHi.isNotEmpty && lang == 'hi') ...[
              const SizedBox(height: 2),
              Text(
                scheme.nameHi,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                ),
              ),
            ],

            const SizedBox(height: 8),

            // Benefit Highlight Chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.mintLight.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.forestGreen.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.stars_rounded, color: AppTheme.forestGreen, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      scheme.benefit,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.forestGreen,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Ministry / Source
            Row(
              children: [
                const Icon(Icons.corporate_fare_rounded, size: 14, color: AppTheme.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    scheme.ministry,
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SchemeDetailScreen(
                            scheme: scheme,
                            profile: CitizenProfile.empty(),
                            settings: widget.settings,
                          ),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      side: const BorderSide(color: AppTheme.primaryNavy),
                    ),
                    child: const Text(
                      'View Details',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: AppTheme.primaryNavy,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _launchUrl(scheme.officialPortalUrl),
                    icon: const Icon(Icons.open_in_new_rounded, size: 14, color: Colors.white),
                    label: const Text(
                      'Open Portal',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentSaffron,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInternshipCard(InternshipModel internship, String lang) {
    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppTheme.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Badge Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.forestGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.forestGreen.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt_rounded, size: 13, color: AppTheme.forestGreen),
                      const SizedBox(width: 4),
                      Text(
                        _formatDateBadge(internship.postedDate),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.forestGreen,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    internship.companyType,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Title
            Text(
              internship.title,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryNavy,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              internship.organization,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
              ),
            ),

            const SizedBox(height: 10),

            // Facets row (Stipend, Mode, Duration)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildFacetChip(Icons.currency_rupee_rounded, internship.stipend, Colors.green.shade800, Colors.green.shade50),
                _buildFacetChip(Icons.laptop_chromebook_rounded, internship.workMode, AppTheme.primaryNavy, Colors.grey.shade100),
                _buildFacetChip(Icons.schedule_rounded, internship.duration, Colors.orange.shade900, Colors.orange.shade50),
              ],
            ),

            const SizedBox(height: 14),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InternshipDetailScreen(
                            internship: internship,
                            settings: widget.settings,
                          ),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      side: const BorderSide(color: AppTheme.primaryNavy),
                    ),
                    child: const Text(
                      'View Details',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: AppTheme.primaryNavy,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _launchUrl(internship.officialUrl),
                    icon: const Icon(Icons.arrow_outward_rounded, size: 14, color: Colors.white),
                    label: const Text(
                      'Apply on Portal',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.forestGreen,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFacetChip(IconData icon, String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: const [
            CircularProgressIndicator(strokeWidth: 3, color: AppTheme.accentSaffron),
            SizedBox(height: 16),
            Text(
              'Fetching latest announcements from official portals...',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.borderSubtle),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.inbox_outlined, size: 32, color: Colors.orange.shade800),
              ),
              const SizedBox(height: 18),
              // Exact required text
              const Text(
                'No new schemes or internships are available.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primaryNavy,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'No newly gazetted schemes or verified internship drives were announced in the last 1 month for your selected category or state.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _handleManualRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                label: const Text(
                  'Refresh Updates',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
