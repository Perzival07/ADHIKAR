import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';
import '../core/models/citizen_profile.dart';
import '../core/models/administrative_regions.dart';
import '../core/models/scheme_model.dart';
import '../core/services/settings_service.dart';
import '../core/services/tts_service.dart';
import '../data/schemes_corpus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'results/scheme_detail_screen.dart';

class SchemesDirectoryScreen extends StatefulWidget {
  final SettingsService settings;

  const SchemesDirectoryScreen({super.key, required this.settings});

  @override
  State<SchemesDirectoryScreen> createState() => _SchemesDirectoryScreenState();
}

class _SchemesDirectoryScreenState extends State<SchemesDirectoryScreen> {
  final TtsService _tts = TtsService();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _selectedStateFilter = 'All';
  String _selectedOccupation = 'All';
  String _selectedEducation = 'All';
  String _selectedIncome = 'All';
  String _selectedGender = 'All';
  String _selectedAppStatus = 'Active & Open Only'; // Default to active schemes to prevent expired results
  int? _selectedAge; // Specific age e.g. 21
  bool _includeCentralWithState = true;

  @override
  void initState() {
    super.initState();
    // If user has a selected state in settings that isn't 'All India', initialize to that
    if (widget.settings.selectedState != 'All India') {
      _selectedStateFilter = widget.settings.selectedState;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tts.dispose();
    super.dispose();
  }

  int get _activeFilterCount {
    int count = 0;
    if (_selectedStateFilter != 'All') count++;
    if (_selectedCategory != 'All') count++;
    if (_selectedOccupation != 'All') count++;
    if (_selectedEducation != 'All') count++;
    if (_selectedIncome != 'All') count++;
    if (_selectedGender != 'All') count++;
    if (_selectedAge != null) count++;
    if (_selectedAppStatus != 'Active & Open Only') count++;
    return count;
  }

  void _resetFilters() {
    setState(() {
      _selectedCategory = 'All';
      _selectedOccupation = 'All';
      _selectedEducation = 'All';
      _selectedIncome = 'All';
      _selectedGender = 'All';
      _selectedAppStatus = 'Active & Open Only';
      _selectedAge = null;
      _selectedStateFilter = 'All';
      _includeCentralWithState = true;
    });
  }

  void _showFilterModal(BuildContext context, List<String> categories) {
    final isHi = widget.settings.isHindi;

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
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.filter_list_rounded, color: AppTheme.primaryNavy),
                        const SizedBox(width: 8),
                        Text(
                          isHi ? 'योजना फ़िल्टर' : 'Filter Schemes',
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
                            isHi ? 'रीसेट करें' : 'Reset All',
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

                  // Filter options body
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Region Selector
                          _buildFilterSectionTitle(Icons.location_on_rounded, isHi ? 'राज्य / केंद्र शासित प्रदेश' : 'State / UT Jurisdiction'),
                          const SizedBox(height: 8),
                          _buildRegionDropdown(modalCtx, setModalState),
                          if (_selectedStateFilter != 'All' && _selectedStateFilter != 'Central Only') ...[
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                isHi ? 'केंद्र सरकार की योजनाएं भी शामिल करें' : 'Include Central Schemes with $_selectedStateFilter',
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                isHi ? 'राष्ट्रीय स्तर पर उपलब्ध सभी लाभ भी दिखेंगे' : 'Displays nationwide schemes alongside state schemes',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              ),
                              value: _includeCentralWithState,
                              activeThumbColor: AppTheme.accentSaffron,
                              onChanged: (val) {
                                setModalState(() => _includeCentralWithState = val);
                                setState(() => _includeCentralWithState = val);
                              },
                            ),
                          ],
                          const SizedBox(height: 18),

                          // Category
                          _buildFilterSectionTitle(Icons.category_rounded, isHi ? 'श्रेणी / क्षेत्र' : 'Category / Sector'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: categories.map((cat) {
                              final isSelected = _selectedCategory == cat;
                              return ChoiceChip(
                                label: Text(cat == 'All' ? (isHi ? 'सभी' : 'All') : cat),
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

                          // Occupation Filter
                          _buildFilterSectionTitle(Icons.work_outline_rounded, isHi ? 'व्यवसाय / पेशा' : 'Occupation / Profession'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              'All',
                              'Salaried',
                              'Farmer',
                              'Student',
                              'Artisan / Craftsman',
                              'Street Vendor',
                              'Daily Wage / Laborer',
                              'Self-Employed',
                              'Homemaker',
                              'Senior Citizen',
                            ].map((occ) {
                              final isSelected = _selectedOccupation == occ;
                              String label = occ;
                              if (occ == 'All') label = isHi ? 'सभी व्यवसाय' : 'All Occupations';
                              if (occ == 'Salaried') label = isHi ? '💼 वेतनभोगी (Salaried)' : '💼 Salaried Employee';
                              if (occ == 'Farmer') label = isHi ? '🌾 किसान (Farmer)' : '🌾 Farmer / Agriculture';
                              if (occ == 'Student') label = isHi ? '🎓 छात्र (Student)' : '🎓 Student';

                              return ChoiceChip(
                                label: Text(label),
                                selected: isSelected,
                                selectedColor: AppTheme.primaryNavy,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : AppTheme.textDark,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 12,
                                ),
                                onSelected: (sel) {
                                  setModalState(() => _selectedOccupation = occ);
                                  setState(() => _selectedOccupation = occ);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),

                          // Education Level
                          _buildFilterSectionTitle(Icons.school_rounded, isHi ? 'शिक्षा स्तर' : 'Education Level'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ['All', 'School', '10th / 12th', 'Graduate / Degree', 'Diploma / ITI'].map((edu) {
                              final isSelected = _selectedEducation == edu;
                              return ChoiceChip(
                                label: Text(edu == 'All' ? (isHi ? 'सभी स्तर' : 'All Levels') : edu),
                                selected: isSelected,
                                selectedColor: AppTheme.primaryNavy,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : AppTheme.textDark,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 12,
                                ),
                                onSelected: (sel) {
                                  setModalState(() => _selectedEducation = edu);
                                  setState(() => _selectedEducation = edu);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),

                          // Income Ceiling
                          _buildFilterSectionTitle(Icons.account_balance_wallet_rounded, isHi ? 'आय सीमा' : 'Income Ceiling'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ['All', '< 1 Lakh', '< 2.5 Lakh', '< 5 Lakh', 'No Limit'].map((inc) {
                              final isSelected = _selectedIncome == inc;
                              return ChoiceChip(
                                label: Text(inc == 'All' ? (isHi ? 'सभी आय' : 'Any Income') : inc),
                                selected: isSelected,
                                selectedColor: AppTheme.primaryNavy,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : AppTheme.textDark,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 12,
                                ),
                                onSelected: (sel) {
                                  setModalState(() => _selectedIncome = inc);
                                  setState(() => _selectedIncome = inc);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),

                          // Gender
                          _buildFilterSectionTitle(Icons.wc_rounded, isHi ? 'लिंग पात्रता' : 'Gender Eligibility'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ['All', 'Female', 'Male'].map((g) {
                              final isSelected = _selectedGender == g;
                              String label = g == 'All' ? (isHi ? 'सभी लिंग' : 'All Genders') : (isHi ? (g == 'Female' ? 'महिला' : 'पुरुष') : g);
                              return ChoiceChip(
                                label: Text(label),
                                selected: isSelected,
                                selectedColor: AppTheme.primaryNavy,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : AppTheme.textDark,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 12,
                                ),
                                onSelected: (sel) {
                                  setModalState(() => _selectedGender = g);
                                  setState(() => _selectedGender = g);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),

                          // Age of Applicant
                          _buildFilterSectionTitle(Icons.cake_rounded, isHi ? 'आवेदक की आयु (Age)' : 'Applicant Age (Years)'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: Text(isHi ? 'सभी आयु (Any Age)' : 'Any Age'),
                                selected: _selectedAge == null,
                                selectedColor: AppTheme.primaryNavy,
                                labelStyle: TextStyle(
                                  color: _selectedAge == null ? Colors.white : AppTheme.textDark,
                                  fontWeight: _selectedAge == null ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 12,
                                ),
                                onSelected: (_) {
                                  setModalState(() => _selectedAge = null);
                                  setState(() => _selectedAge = null);
                                },
                              ),
                              ...[18, 21, 25, 30, 40, 60].map((age) {
                                final isSelected = _selectedAge == age;
                                return ChoiceChip(
                                  label: Text('$age yrs'),
                                  selected: isSelected,
                                  selectedColor: AppTheme.primaryNavy,
                                  labelStyle: TextStyle(
                                    color: isSelected ? Colors.white : AppTheme.textDark,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                  onSelected: (sel) {
                                    setModalState(() => _selectedAge = sel ? age : null);
                                    setState(() => _selectedAge = sel ? age : null);
                                  },
                                );
                              }),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // Application Status
                          _buildFilterSectionTitle(Icons.event_available_rounded, isHi ? 'आवेदन स्थिति व वैधता' : 'Application Status & Validity'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              'Active & Open Only',
                              'All (Including Expired)',
                              'Expired / Superseded Only',
                              'Open / Ongoing',
                              'Annual Cycle',
                            ].map((st) {
                              final isSelected = _selectedAppStatus == st;
                              String label = st;
                              if (st == 'Active & Open Only') {
                                label = isHi ? '🟢 केवल सक्रिय योजनाएं' : '🟢 Active & Open Only';
                              } else if (st == 'All (Including Expired)') {
                                label = isHi ? 'सभी (समाप्त सहित)' : 'All (Including Expired)';
                              } else if (st == 'Expired / Superseded Only') {
                                label = isHi ? '🔴 केवल समाप्त/परिवर्तित' : '🔴 Expired / Superseded Only';
                              }
                              return ChoiceChip(
                                label: Text(label),
                                selected: isSelected,
                                selectedColor: AppTheme.primaryNavy,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : AppTheme.textDark,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 12,
                                ),
                                onSelected: (sel) {
                                  setModalState(() => _selectedAppStatus = st);
                                  setState(() => _selectedAppStatus = st);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Action Bar
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

  Widget _buildRegionDropdown(BuildContext context, StateSetter setModalState) {
    final allStates = IndianRegions.stateNames;
    final allUts = IndianRegions.utNames;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedStateFilter,
          isExpanded: true,
          style: const TextStyle(fontSize: 13, color: AppTheme.textDark, fontWeight: FontWeight.w600),
          items: [
            const DropdownMenuItem(
              value: 'All',
              child: Text('🇮🇳 All India (All Central + State Schemes)'),
            ),
            const DropdownMenuItem(
              value: 'Central Only',
              child: Text('🏛️ Central Schemes Only (Pan-India)'),
            ),
            const DropdownMenuItem(
              enabled: false,
              value: '__states_header__',
              child: Text('─── 28 States ───', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ...allStates.map((st) => DropdownMenuItem(
              value: st,
              child: Text('📍 $st'),
            )),
            const DropdownMenuItem(
              enabled: false,
              value: '__uts_header__',
              child: Text('─── 8 Union Territories ───', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ...allUts.map((ut) => DropdownMenuItem(
              value: ut,
              child: Text('🏛️ $ut (UT)'),
            )),
          ],
          onChanged: (val) {
            if (val != null && !val.startsWith('__')) {
              setModalState(() => _selectedStateFilter = val);
              setState(() => _selectedStateFilter = val);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.settings.currentLanguage;
    final isHi = widget.settings.isHindi;
    final allSchemes = SchemesCorpus.getSchemes();
    final categories = ['All', ...allSchemes.map((s) => s.category).toSet()];

    final filtered = allSchemes.where((s) {
      // Category match
      if (_selectedCategory != 'All' && s.category != _selectedCategory) {
        return false;
      }

      // State / UT match
      if (_selectedStateFilter == 'Central Only') {
        if (!s.isCentral) return false;
      } else if (_selectedStateFilter != 'All') {
        final matchesThisState = s.stateScope.toLowerCase().trim() == _selectedStateFilter.toLowerCase().trim();
        if (_includeCentralWithState) {
          // Display relevant Central schemes along with schemes specific to that state/UT
          if (!matchesThisState && !s.isCentral) return false;
        } else {
          if (!matchesThisState) return false;
        }
      }

      // Education match
      if (_selectedEducation != 'All') {
        if (s.educationLevel != 'All' && s.educationLevel != _selectedEducation) {
          return false;
        }
      }

      // Occupation match
      if (_selectedOccupation != 'All') {
        final isFarmingScheme = s.category.toLowerCase().contains('agriculture') ||
            s.category.toLowerCase().contains('farmer') ||
            s.name.toLowerCase().contains('kisan') ||
            s.name.toLowerCase().contains('farmer') ||
            s.id.contains('kisan') ||
            s.id.contains('farmer') ||
            s.summary.toLowerCase().contains('farmer families') ||
            s.defaultPlainReason.toLowerCase().contains('farming') ||
            s.defaultPlainReason.toLowerCase().contains('farmer');

        if (_selectedOccupation == 'Salaried') {
          // Salaried employees MUST NOT match agricultural, farming schemes or unemployment allowances
          if (isFarmingScheme) return false;
          if (s.category.toLowerCase().contains('unemployment') ||
              s.id.contains('yuva_sathi') ||
              s.id.contains('yuva_nidhi') ||
              s.id.contains('yuva_shakti') ||
              s.id.contains('mgnrega') ||
              s.id == 'pm_vishwakarma' ||
              s.id == 'pm_svanidhi') {
            return false;
          }
        } else if (_selectedOccupation == 'Farmer') {
          if (s.id == 'pm_svanidhi' || s.id == 'pm_vishwakarma') return false;
        } else if (_selectedOccupation == 'Student') {
          if (isFarmingScheme) return false;
        } else if (_selectedOccupation == 'Artisan / Craftsman') {
          if (isFarmingScheme && s.id != 'pm_vishwakarma') return false;
        } else if (_selectedOccupation == 'Street Vendor') {
          if (isFarmingScheme && s.id != 'pm_svanidhi') return false;
        }
      }

      // Income ceiling match
      if (_selectedIncome != 'All') {
        if (s.incomeCeiling != 'No Limit' && s.incomeCeiling != _selectedIncome) {
          return false;
        }
      }

      // Gender match
      if (_selectedGender != 'All') {
        if (s.genderEligibility != 'All' && s.genderEligibility != _selectedGender) {
          return false;
        }
      }

      // Age match
      if (_selectedAge != null) {
        if (!s.isAgeEligible(_selectedAge!)) {
          return false;
        }
      }

      // Application status & Expiration match
      if (_selectedAppStatus == 'Active & Open Only') {
        if (s.isExpired || s.applicationStatus.contains('Expired')) {
          return false;
        }
      } else if (_selectedAppStatus == 'Expired / Superseded Only') {
        if (!s.isExpired && !s.applicationStatus.contains('Expired')) {
          return false;
        }
      } else if (_selectedAppStatus != 'All' && _selectedAppStatus != 'All (Including Expired)') {
        if (s.applicationStatus != _selectedAppStatus) {
          return false;
        }
      }

      // Query match
      final query = _searchQuery.toLowerCase().trim();
      if (query.isNotEmpty) {
        final matchesQuery = s.name.toLowerCase().contains(query) ||
            s.nameHi.contains(query) ||
            s.ministry.toLowerCase().contains(query) ||
            s.stateScope.toLowerCase().contains(query) ||
            s.summary.toLowerCase().contains(query) ||
            s.category.toLowerCase().contains(query);
        if (!matchesQuery) return false;
      }

      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isHi ? 'योजना निर्देशिका' : 'Schemes Directory',
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
            onPressed: () => _showFilterModal(context, categories),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Region Active Status Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: isHi ? 'योजना, राज्य, पात्रता खोजें...' : 'Search schemes, state, category...',
                    prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primaryNavy),
                    suffixIcon: _searchQuery.isNotEmpty
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
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
                const SizedBox(height: 10),

                // Quick Region Selector Row
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on_rounded, size: 14, color: AppTheme.primaryNavy),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _selectedStateFilter == 'All'
                                    ? (isHi ? 'सभी राज्य + केंद्र' : 'All India (Central + States)')
                                    : (_selectedStateFilter == 'Central Only'
                                        ? (isHi ? 'केवल केंद्र सरकार' : 'Central Schemes Only')
                                        : '$_selectedStateFilter ${_includeCentralWithState ? "+ Central" : ""}'),
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primaryNavy),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _showFilterModal(context, categories),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.accentSaffron.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.accentSaffron.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.tune_rounded, size: 14, color: AppTheme.accentSaffron),
                            const SizedBox(width: 4),
                            Text(
                              isHi ? 'फ़िल्टर ($_activeFilterCount)' : 'Filters ($_activeFilterCount)',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.accentSaffron),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (_selectedStateFilter != 'All' ||
                    _selectedOccupation != 'All' ||
                    _selectedGender != 'All' ||
                    _selectedAge != null ||
                    _selectedEducation != 'All' ||
                    _selectedIncome != 'All' ||
                    _selectedAppStatus != 'Active & Open Only') ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (_selectedStateFilter != 'All')
                          _buildActiveFilterPill(
                            icon: Icons.location_on_rounded,
                            label: _selectedStateFilter,
                            onDeleted: () => setState(() => _selectedStateFilter = 'All'),
                          ),
                        if (_selectedOccupation != 'All')
                          _buildActiveFilterPill(
                            icon: Icons.work_outline_rounded,
                            label: _selectedOccupation,
                            onDeleted: () => setState(() => _selectedOccupation = 'All'),
                          ),
                        if (_selectedGender != 'All')
                          _buildActiveFilterPill(
                            icon: Icons.person_rounded,
                            label: _selectedGender,
                            onDeleted: () => setState(() => _selectedGender = 'All'),
                          ),
                        if (_selectedAge != null)
                          _buildActiveFilterPill(
                            icon: Icons.cake_rounded,
                            label: 'Age: $_selectedAge yrs',
                            onDeleted: () => setState(() => _selectedAge = null),
                          ),
                        if (_selectedEducation != 'All')
                          _buildActiveFilterPill(
                            icon: Icons.school_rounded,
                            label: _selectedEducation,
                            onDeleted: () => setState(() => _selectedEducation = 'All'),
                          ),
                        if (_selectedIncome != 'All')
                          _buildActiveFilterPill(
                            icon: Icons.currency_rupee_rounded,
                            label: _selectedIncome,
                            onDeleted: () => setState(() => _selectedIncome = 'All'),
                          ),
                        if (_selectedAppStatus != 'Active & Open Only')
                          _buildActiveFilterPill(
                            icon: Icons.info_outline_rounded,
                            label: _selectedAppStatus,
                            onDeleted: () => setState(() => _selectedAppStatus = 'Active & Open Only'),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Categories Horizontal Carousel
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: categories.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterChip(
                      label: Text(cat == 'All' ? (isHi ? 'सभी श्रेणियां' : 'All Sectors') : cat),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryNavy,
                      backgroundColor: Colors.grey.shade100,
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppTheme.textDark,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isSelected ? AppTheme.primaryNavy : AppTheme.borderSubtle,
                        ),
                      ),
                      onSelected: (val) {
                        setState(() => _selectedCategory = cat);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const Divider(height: 1, color: AppTheme.borderSubtle),

          // Schemes Counter & Status Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppTheme.bgSurface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isHi
                      ? '${filtered.length} आधिकारिक योजनाएं प्रदर्शित'
                      : 'Showing ${filtered.length} official schemes',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
                ),
                if (_activeFilterCount > 0)
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

          // Scheme Cards List
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
                            isHi ? 'कोई योजना नहीं मिली' : 'No schemes match your criteria',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isHi
                                ? 'फ़िल्टर रीसेट करें या राज्य / श्रेणी चयन बदलें'
                                : 'Try resetting filters or switching the state jurisdiction',
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
                      final scheme = filtered[index];
                      return _buildSchemeCard(context, scheme, isHi, lang);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchemeCard(BuildContext context, SchemeModel scheme, bool isHi, String lang) {
    final title = isHi ? scheme.nameHi : scheme.name;
    final summary = isHi ? scheme.summaryHi : scheme.summary;
    final benefit = isHi ? scheme.benefitHi : scheme.benefit;

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
              builder: (_) => SchemeDetailScreen(
                scheme: scheme,
                profile: CitizenProfile(
                  occupation: _selectedOccupation != 'All' ? _selectedOccupation : 'Citizen',
                  landHoldingAcres: _selectedOccupation == 'Farmer' ? 2.0 : 0.0,
                  state: _selectedStateFilter != 'All' && _selectedStateFilter != 'Central Only'
                      ? _selectedStateFilter
                      : widget.settings.selectedState,
                  gender: _selectedGender != 'All' ? _selectedGender : 'Male',
                  age: _selectedAge ?? 35,
                ),
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
              // Badges Row: Category + State/UT + Verified Badge + Audio
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      scheme.category,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentSaffron,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: scheme.isCentral
                          ? AppTheme.primaryNavy.withValues(alpha: 0.08)
                          : Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      scheme.isCentral
                          ? (isHi ? 'केंद्रीय सरकार' : 'Central')
                          : (isHi ? '${scheme.stateScope} राज्य' : scheme.stateScope),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: scheme.isCentral ? AppTheme.primaryNavy : Colors.purple.shade800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Verified source indicator or Expired badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: scheme.isExpired ? Colors.red.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: scheme.isExpired ? Colors.red.shade300 : Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          scheme.isExpired ? Icons.cancel_outlined : Icons.verified_rounded,
                          size: 12,
                          color: scheme.isExpired ? Colors.red.shade700 : Colors.green.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          scheme.isExpired
                              ? (isHi ? 'समाप्त / परिवर्तित' : 'Superseded / Closed')
                              : (isHi ? 'सत्यापित एवं सक्रिय' : 'Active & Verified'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: scheme.isExpired ? Colors.red.shade800 : Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.volume_up, size: 20, color: AppTheme.primaryNavy),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      _tts.speak('$title. $benefit', langCode: lang, isHindi: isHi);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15.5,
                  height: 1.3,
                  color: AppTheme.textDark,
                ),
              ),
              if (scheme.isExpired || scheme.applicationStatus.contains('Expired')) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: Colors.amber.shade900),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isHi
                              ? 'सूचना: यह योजना समाप्त हो चुकी है तथा अन्नपूर्णा भंडार (₹3,000/माह डीबीटी) द्वारा प्रतिस्थापित है।'
                              : 'Notice: This scheme is discontinued / expired and has been superseded by newer state entitlements (e.g. Annapurna Bhandar ₹3,000/mo DBT).',
                          style: TextStyle(fontSize: 11.5, color: const Color(0xFF78350F), fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 6),

              // Summary
              Text(
                summary,
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569), height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),

              // Benefit Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.mintLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFABF5D1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.currency_rupee_rounded, size: 15, color: AppTheme.forestGreen),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        benefit,
                        style: const TextStyle(
                          color: AppTheme.forestGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Metadata Tags (Deadline, Age, Education, Income, Gender)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildMetaTag(Icons.calendar_today_rounded, scheme.deadline, Colors.blue.shade700, Colors.blue.shade50),
                  if (scheme.minAge != null || scheme.maxAge != null)
                    _buildMetaTag(
                      Icons.cake_outlined,
                      scheme.minAge != null && scheme.maxAge != null
                          ? 'Age: ${scheme.minAge}-${scheme.maxAge} yrs'
                          : (scheme.minAge != null ? 'Age: ${scheme.minAge}+ yrs' : 'Age: Up to ${scheme.maxAge} yrs'),
                      Colors.indigo.shade700,
                      Colors.indigo.shade50,
                    ),
                  if (scheme.educationLevel != 'All')
                    _buildMetaTag(Icons.school_rounded, scheme.educationLevel, Colors.teal.shade700, Colors.teal.shade50),
                  if (scheme.incomeCeiling != 'No Limit')
                    _buildMetaTag(Icons.payments_outlined, scheme.incomeCeiling, Colors.orange.shade800, Colors.orange.shade50),
                  if (scheme.genderEligibility != 'All')
                    _buildMetaTag(Icons.person_outline_rounded, scheme.genderEligibility, Colors.purple.shade700, Colors.purple.shade50),
                ],
              ),
              const SizedBox(height: 10),

              // Footer: Ministry / Department + Action
              Row(
                children: [
                  const Icon(Icons.account_balance_outlined, size: 14, color: AppTheme.textMuted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      scheme.ministry,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (scheme.officialPortalUrl.isNotEmpty) ...[
                        InkWell(
                          onTap: () => _launchPortalUrl(scheme.officialPortalUrl),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.15)),
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
                      Text(
                        isHi ? 'विवरण' : 'Details',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.accentSaffron),
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

  Widget _buildMetaTag(IconData icon, String text, Color textColor, Color bgColor) {
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

  Widget _buildActiveFilterPill({
    required IconData icon,
    required String label,
    required VoidCallback onDeleted,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.primaryNavy),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryNavy),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onDeleted,
            child: const Icon(Icons.close_rounded, size: 13, color: AppTheme.primaryNavy),
          ),
        ],
      ),
    );
  }

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
}
