import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models/internship_model.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/app_translations.dart';
import '../../data/internships_corpus.dart';
import 'internship_detail_screen.dart';

class InternshipsScreen extends StatefulWidget {
  final SettingsService settings;

  const InternshipsScreen({super.key, required this.settings});

  @override
  State<InternshipsScreen> createState() => _InternshipsScreenState();
}

class _InternshipsScreenState extends State<InternshipsScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedQuickTag = 'All';
  String _selectedCompanyType = 'All';
  String _selectedWorkMode = 'All';
  String _selectedCategory = 'All';
  String _selectedLocation = 'All';
  String _selectedStipend = 'All';
  bool _onlyOpenPositions = true;

  late List<InternshipModel> _allInternships;

  final List<String> _quickTags = [
    'All',
    'Govt & PSU',
    'Tech Giants',
    'Research & Defense',
    'Remote',
    'Paid (> ₹15k)',
  ];

  @override
  void initState() {
    super.initState();
    _allInternships = InternshipsCorpus.getInternships();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int get _activeFilterCount {
    int count = 0;
    if (_selectedCompanyType != 'All') count++;
    if (_selectedWorkMode != 'All') count++;
    if (_selectedCategory != 'All') count++;
    if (_selectedLocation != 'All') count++;
    if (_selectedStipend != 'All') count++;
    if (!_onlyOpenPositions) count++;
    return count;
  }

  Future<void> _launchPortalUrl(String url) async {
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

  void _resetFilters() {
    setState(() {
      _selectedQuickTag = 'All';
      _selectedCompanyType = 'All';
      _selectedWorkMode = 'All';
      _selectedCategory = 'All';
      _selectedLocation = 'All';
      _selectedStipend = 'All';
      _onlyOpenPositions = true;
    });
  }

  void _showFilterModal(BuildContext context) {
    final isHi = widget.settings.isHindi;

    final allCategories = ['All', ..._allInternships.map((i) => i.category).toSet()];
    final allLocations = ['All', 'Pan-India', 'Bengaluru', 'New Delhi', 'Hyderabad', 'Pune', 'Mumbai', 'Remote'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Modal Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.tune_rounded, color: AppTheme.primaryNavy),
                        const SizedBox(width: 8),
                        Text(
                          isHi ? 'इंटर्नशिप फ़िल्टर' : 'Filter Opportunities',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.primaryNavy),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              _resetFilters();
                            });
                            setState(() {});
                          },
                          child: Text(
                            isHi ? 'रीसेट' : 'Reset All',
                            style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),

                  // Modal Options Body
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Employer / Organization Type
                          _buildFilterSectionTitle(Icons.business_rounded, isHi ? 'नियोक्ता प्रकार (Organization Type)' : 'Employer / Organization Type'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ['All', 'Central Govt', 'PSU', 'Research Lab', 'Private Tech', 'State Govt', 'Startup'].map((type) {
                              final isSelected = _selectedCompanyType == type;
                              return ChoiceChip(
                                label: Text(type == 'All' ? (isHi ? 'सभी संगठन' : 'All Types') : type),
                                selected: isSelected,
                                selectedColor: AppTheme.primaryNavy,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : AppTheme.textDark,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 12,
                                ),
                                onSelected: (sel) {
                                  setModalState(() => _selectedCompanyType = type);
                                  setState(() => _selectedCompanyType = type);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),

                          // Work Mode (Remote / Hybrid / On-site)
                          _buildFilterSectionTitle(Icons.work_outline_rounded, isHi ? 'कार्य मोड (Work Mode)' : 'Work Mode'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ['All', 'Remote', 'Hybrid', 'On-site'].map((mode) {
                              final isSelected = _selectedWorkMode == mode;
                              return ChoiceChip(
                                label: Text(mode == 'All' ? (isHi ? 'सभी मोड' : 'All Modes') : mode),
                                selected: isSelected,
                                selectedColor: AppTheme.primaryNavy,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : AppTheme.textDark,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 12,
                                ),
                                onSelected: (sel) {
                                  setModalState(() => _selectedWorkMode = mode);
                                  setState(() => _selectedWorkMode = mode);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),

                          // Domain / Category
                          _buildFilterSectionTitle(Icons.category_rounded, isHi ? 'क्षेत्र / डोमेन (Domain)' : 'Domain / Sector'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: allCategories.map((cat) {
                              final isSelected = _selectedCategory == cat;
                              return ChoiceChip(
                                label: Text(cat == 'All' ? (isHi ? 'सभी क्षेत्र' : 'All Domains') : cat),
                                selected: isSelected,
                                selectedColor: AppTheme.primaryNavy,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : AppTheme.textDark,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 12,
                                ),
                                onSelected: (sel) {
                                  setModalState(() => _selectedCategory = cat);
                                  setState(() => _selectedCategory = cat);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),

                          // Location
                          _buildFilterSectionTitle(Icons.location_on_rounded, isHi ? 'स्थान (Location)' : 'Location'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: allLocations.map((loc) {
                              final isSelected = _selectedLocation == loc;
                              return ChoiceChip(
                                label: Text(loc == 'All' ? (isHi ? 'सभी स्थान' : 'All Locations') : loc),
                                selected: isSelected,
                                selectedColor: AppTheme.primaryNavy,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : AppTheme.textDark,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 12,
                                ),
                                onSelected: (sel) {
                                  setModalState(() => _selectedLocation = loc);
                                  setState(() => _selectedLocation = loc);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),

                          // Stipend Filter
                          _buildFilterSectionTitle(Icons.currency_rupee_rounded, isHi ? 'वजीफा (Stipend)' : 'Stipend Range'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ['All', 'Paid Only', '₹15,000+', '₹25,000+'].map((stip) {
                              final isSelected = _selectedStipend == stip;
                              return ChoiceChip(
                                label: Text(stip == 'All' ? (isHi ? 'सभी' : 'Any Stipend') : stip),
                                selected: isSelected,
                                selectedColor: AppTheme.primaryNavy,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : AppTheme.textDark,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 12,
                                ),
                                onSelected: (sel) {
                                  setModalState(() => _selectedStipend = stip);
                                  setState(() => _selectedStipend = stip);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),

                          // Only Verified Open Toggle
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              isHi ? 'केवल सक्रिय खुली रिक्तियां दिखाएं' : 'Show Verified Open Opportunities Only',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              isHi ? 'समाप्त या बंद हो चुके पदों को छुपाएं' : 'Hides closed or expired listings',
                              style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                            ),
                            value: _onlyOpenPositions,
                            activeThumbColor: AppTheme.accentSaffron,
                            onChanged: (val) {
                              setModalState(() => _onlyOpenPositions = val);
                              setState(() => _onlyOpenPositions = val);
                            },
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),

                  // Modal Apply Button
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
                      color: Colors.white,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryNavy,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          isHi ? 'फ़िल्टर लागू करें' : 'Apply Filters',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterSectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.accentSaffron),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryNavy),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.settings.currentLanguage;
    final isHi = widget.settings.isHindi;

    final filtered = _allInternships.where((item) {
      // Open / Expired status
      if (_onlyOpenPositions && item.isExpired) {
        return false;
      }

      // Quick Tag match
      if (_selectedQuickTag == 'Govt & PSU') {
        if (item.companyType != 'Central Govt' && item.companyType != 'PSU') return false;
      } else if (_selectedQuickTag == 'Tech Giants') {
        if (item.companyType != 'Private Tech') return false;
      } else if (_selectedQuickTag == 'Research & Defense') {
        if (item.companyType != 'Research Lab' && !item.category.contains('Defense')) return false;
      } else if (_selectedQuickTag == 'Remote') {
        if (item.workMode != 'Remote') return false;
      } else if (_selectedQuickTag == 'Paid (> ₹15k)') {
        if (item.stipend.contains('₹0') || item.stipend.contains('Unpaid') || (!item.stipend.contains('₹15,000') && !item.stipend.contains('₹25,000') && !item.stipend.contains('₹30,000') && !item.stipend.contains('₹40,000') && !item.stipend.contains('₹50,000') && !item.stipend.contains('₹1,00,000'))) {
          return false;
        }
      }

      // Company Type
      if (_selectedCompanyType != 'All' && item.companyType != _selectedCompanyType) {
        return false;
      }

      // Work Mode
      if (_selectedWorkMode != 'All' && item.workMode != _selectedWorkMode) {
        return false;
      }

      // Category
      if (_selectedCategory != 'All' && item.category != _selectedCategory) {
        return false;
      }

      // Location
      if (_selectedLocation != 'All') {
        if (_selectedLocation == 'Remote' && item.workMode != 'Remote') return false;
        if (_selectedLocation != 'Remote' && !item.location.toLowerCase().contains(_selectedLocation.toLowerCase())) return false;
      }

      // Stipend
      if (_selectedStipend == 'Paid Only') {
        if (item.stipend.contains('₹0') || item.stipend.toLowerCase().contains('unpaid')) return false;
      } else if (_selectedStipend == '₹15,000+') {
        final hasHighStipend = item.stipend.contains('₹15,000') || item.stipend.contains('₹25,000') || item.stipend.contains('₹30,000') || item.stipend.contains('₹40,000') || item.stipend.contains('₹50,000') || item.stipend.contains('₹1,00,000');
        if (!hasHighStipend) return false;
      } else if (_selectedStipend == '₹25,000+') {
        final hasVeryHighStipend = item.stipend.contains('₹25,000') || item.stipend.contains('₹30,000') || item.stipend.contains('₹40,000') || item.stipend.contains('₹50,000') || item.stipend.contains('₹1,00,000');
        if (!hasVeryHighStipend) return false;
      }

      // Search Query
      final query = _searchQuery.toLowerCase().trim();
      if (query.isNotEmpty) {
        final matchesQuery = item.title.toLowerCase().contains(query) ||
            item.titleHi.toLowerCase().contains(query) ||
            item.organization.toLowerCase().contains(query) ||
            item.portalSource.toLowerCase().contains(query) ||
            item.category.toLowerCase().contains(query) ||
            item.location.toLowerCase().contains(query) ||
            item.companyType.toLowerCase().contains(query);
        if (!matchesQuery) return false;
      }

      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppStrings.get('internships_title', lang),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.filter_list_rounded, color: Colors.white),
                if (_activeFilterCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppTheme.accentSaffron,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$_activeFilterCount',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: isHi ? 'फ़िल्टर' : 'Filter',
            onPressed: () => _showFilterModal(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Header / Search Bar Section
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: isHi ? 'AICTE, TULIP, ISRO, TCS, कंपनी या विषय खोजें...' : 'Search AICTE, ISRO, TCS, Google, domain...',
                    prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primaryNavy),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ],
            ),
          ),

          // Horizontal Quick Tags
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: _quickTags.map((tag) {
                  final isSelected = _selectedQuickTag == tag;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                        tag == 'All' ? AppStrings.get('filter_all', lang) : tag,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? Colors.white : AppTheme.textDark,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryNavy,
                      backgroundColor: Colors.grey.shade100,
                      checkmarkColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected ? AppTheme.primaryNavy : AppTheme.borderSubtle,
                        ),
                      ),
                      onSelected: (val) {
                        setState(() {
                          _selectedQuickTag = tag;
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          const Divider(height: 1, color: AppTheme.borderSubtle),

          // Internships Count & Filter Badge Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppTheme.bgSurface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isHi
                      ? '${filtered.length} सत्यापित अवसर उपलब्ध'
                      : 'Showing ${filtered.length} verified opportunities',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
                ),
                if (_activeFilterCount > 0 || _selectedQuickTag != 'All')
                  GestureDetector(
                    onTap: _resetFilters,
                    child: Text(
                      isHi ? 'फ़िल्टर हटाएं' : 'Clear filters',
                      style: const TextStyle(fontSize: 11.5, color: Colors.redAccent, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),

          // Internships List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded, size: 54, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            isHi ? 'कोई अवसर नहीं मिला' : 'No opportunities match your filter',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isHi ? 'कृपया अन्य श्रेणी, संगठन या खोज शब्द आज़माएं' : 'Try resetting filters or searching for different keywords',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryNavy,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _resetFilters,
                            icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                            label: Text(
                              isHi ? 'फ़िल्टर रीसेट करें' : 'Reset Filters',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _buildInternshipCard(context, item, lang, isHi);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInternshipCard(
    BuildContext context,
    InternshipModel item,
    String lang,
    bool isHi,
  ) {
    final title = isHi && item.titleHi.isNotEmpty ? item.titleHi : item.title;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1.5,
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
              builder: (_) => InternshipDetailScreen(
                internship: item,
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
              // Top Pills Row: Company Type + Work Mode + Status + Portal
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.companyType,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.workMode == 'Remote'
                              ? Icons.wifi_rounded
                              : (item.workMode == 'Hybrid' ? Icons.swap_horiz_rounded : Icons.location_city_rounded),
                          size: 11,
                          color: Colors.blue.shade800,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          item.workMode,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Verified Status Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: item.isExpired ? Colors.grey.shade100 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: item.isExpired ? Colors.grey.shade300 : Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.isExpired ? Icons.cancel_outlined : Icons.verified_rounded,
                          size: 11,
                          color: item.isExpired ? Colors.grey : Colors.green.shade700,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          item.status,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: item.isExpired ? Colors.grey.shade700 : Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
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
              const SizedBox(height: 4),

              // Organization & Portal
              Row(
                children: [
                  const Icon(Icons.business_outlined, size: 14, color: AppTheme.textMuted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${item.organization} • ${item.portalSource}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Metrics Chips Row: Stipend, Duration, Location
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _buildMetricPill(
                    icon: Icons.currency_rupee_rounded,
                    label: item.stipend,
                    textColor: AppTheme.forestGreen,
                    bgColor: AppTheme.mintLight,
                    isBold: true,
                  ),
                  _buildMetricPill(
                    icon: Icons.access_time_rounded,
                    label: item.duration,
                    textColor: Colors.blue.shade800,
                    bgColor: Colors.blue.shade50,
                  ),
                  _buildMetricPill(
                    icon: Icons.location_on_outlined,
                    label: item.location,
                    textColor: Colors.grey.shade800,
                    bgColor: Colors.grey.shade100,
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Eligibility Line
              Text(
                '${isHi ? "पात्रता: " : "Eligibility: "}${isHi && item.eligibilityHi.isNotEmpty ? item.eligibilityHi : item.eligibility}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 10),

              // Footer: Deadline + Open Portal + Details
              Row(
                children: [
                  Icon(Icons.calendar_month_outlined, size: 13, color: Colors.blue.shade800),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${isHi ? "अंतिम तिथि: " : "Deadline: "}${item.deadline}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (item.officialUrl.isNotEmpty) ...[
                    InkWell(
                      onTap: () => _launchPortalUrl(item.officialUrl),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.language_rounded, size: 12, color: AppTheme.primaryNavy),
                            const SizedBox(width: 4),
                            Text(
                              isHi ? 'पोर्टल खोलें' : 'Open Portal',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryNavy,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isHi ? 'विवरण' : 'Details',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentSaffron,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: AppTheme.accentSaffron),
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

  Widget _buildMetricPill({
    required IconData icon,
    required String label,
    required Color textColor,
    required Color bgColor,
    bool isBold = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
