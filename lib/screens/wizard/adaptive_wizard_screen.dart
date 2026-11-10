import 'package:flutter/material.dart';
import '../../core/services/recommendation_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/app_translations.dart';
import '../../core/models/citizen_profile.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/scheme_engine.dart';
import '../../core/models/administrative_regions.dart';
import '../results/schemes_result_screen.dart';

class AdaptiveWizardScreen extends StatefulWidget {
  final SettingsService settings;
  final AuthService? auth;

  /// Pre-fills the answers (used by "Update my answers" on the results screen).
  final CitizenProfile? initialProfile;

  /// Injectable for tests; the results screen builds a default one when null.
  final RecommendationRepository? repository;

  const AdaptiveWizardScreen({super.key, required this.settings, this.auth, this.initialProfile, this.repository});

  @override
  State<AdaptiveWizardScreen> createState() => _AdaptiveWizardScreenState();
}

class _AdaptiveWizardScreenState extends State<AdaptiveWizardScreen> {
  int _currentStep = 0;
  late final CitizenProfile _profile =
      widget.initialProfile != null ? CitizenProfile.copyOf(widget.initialProfile!) : CitizenProfile.empty();

  late final List<String> _states;

  @override
  void initState() {
    super.initState();
    _states = IndianRegions.allRegionNames;
    if (widget.auth?.currentUser != null) {
      final user = widget.auth!.currentUser!;
      if (_states.contains(user.state)) {
        _profile.state = user.state;
      }
      if (user.occupation.isNotEmpty) {
        _profile.occupation = user.occupation;
      }
      if (user.socialCategory.isNotEmpty) {
        _profile.socialCategory = user.socialCategory;
      }
    } else if (widget.settings.selectedState != 'All India' && _states.contains(widget.settings.selectedState)) {
      _profile.state = widget.settings.selectedState;
    }
  }

  final List<String> _occupations = [
    'Citizen',
    'Farmer',
    'Student',
    'Salaried',
    'Self-Employed',
    'Artisan / Craftsman',
    'Street Vendor',
    'Daily Wage / Laborer',
    'Homemaker',
    'Senior Citizen',
    'Unemployed',
  ];

  final List<String> _artisanTrades = [
    'Carpenter (बढ़ई)',
    'Blacksmith (लोहार)',
    'Potter (कुम्हार)',
    'Mason (राजमिस्त्री)',
    'Sculptor / Stone Carver (मूर्तिकार)',
    'Cobbler / Shoemaker (चर्मकार)',
    'Barber (नाई)',
    'Tailor (दर्जी)',
    'Weaver (बुनकर)',
    'Basket / Mat Maker (टोकरी निर्माता)',
    'Locksmith (ताला बनाने वाले)',
    'Boat Builder (नाव निर्माता)',
    'Armourer / Hammer & Tool Maker (हथौड़ा/औजार निर्माता)',
  ];

  @override
  Widget build(BuildContext context) {
    final lang = widget.settings.currentLanguage;
    final isHi = widget.settings.isHindi;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('wizard_title', lang)),
        actions: [
          TextButton(
            onPressed: () => widget.settings.toggleLanguage(),
            child: Text(
              isHi ? 'English' : 'हिंदी',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // Adaptive Step Progress Indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${isHi ? "चरण" : "Step"} ${_currentStep + 1} / 5',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryNavy),
                    ),
                    Text(
                      _getStepTitle(_currentStep, isHi),
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_currentStep + 1) / 5,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentSaffron),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content of Current Step
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildStepBody(isHi),
            ),
          ),

          // Bottom Navigation Buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                if (_currentStep > 0)
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _currentStep--);
                    },
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: Text(AppStrings.get('btn_back', lang)),
                  ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () {
                    if (_currentStep < 4) {
                      setState(() => _currentStep++);
                    } else {
                      _finishAndEvaluate();
                    }
                  },
                  icon: Icon(_currentStep == 4 ? Icons.check_circle : Icons.arrow_forward, size: 18),
                  label: Text(
                    _currentStep == 4
                        ? AppStrings.get('btn_discover', lang)
                        : AppStrings.get('btn_next', lang),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getStepTitle(int step, bool isHi) {
    switch (step) {
      case 0: return isHi ? 'राज्य व स्थान' : 'Location';
      case 1: return isHi ? 'व्यक्तिगत विवरण' : 'Demographics';
      case 2: return isHi ? 'आजीविका व काम' : 'Livelihood';
      case 3: return isHi ? 'पारिवारिक आय' : 'Economics';
      case 4: return isHi ? 'वर्ग एवं स्थिति' : 'Inclusion';
      default: return '';
    }
  }

  Widget _buildStepBody(bool isHi) {
    switch (_currentStep) {
      case 0: return _buildStep1Location(isHi);
      case 1: return _buildStep2Demographics(isHi);
      case 2: return _buildStep3Livelihood(isHi);
      case 3: return _buildStep4Economics(isHi);
      case 4: return _buildStep5Category(isHi);
      default: return const SizedBox.shrink();
    }
  }

  // STEP 1: Location & Geography
  Widget _buildStep1Location(bool isHi) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: isHi ? 'आप किस राज्य / केंद्र शासित प्रदेश में रहते हैं?' : 'Which State/UT do you reside in?',
          subtitle: isHi ? 'योजनाएं राज्य के अनुसार बदलती हैं' : 'Schemes are routed by State jurisdiction',
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _states.contains(_profile.state) ? _profile.state : _states.first,
          decoration: InputDecoration(
            labelText: isHi ? 'राज्य चुनें' : 'Select State / UT',
            prefixIcon: const Icon(Icons.location_on_outlined, color: AppTheme.primaryNavy),
          ),
          items: _states
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(
                      s,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ))
              .toList(),
          onChanged: (val) {
            if (val != null) setState(() => _profile.state = val);
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: _profile.district,
          decoration: InputDecoration(
            labelText: isHi ? 'ज़िला (वैकल्पिक)' : 'District (Optional)',
            hintText: isHi ? 'उदा. वाराणसी, पटना, जयपुर' : 'e.g. Varanasi, Patna, Jaipur',
            prefixIcon: const Icon(Icons.map_outlined, color: AppTheme.primaryNavy),
          ),
          onChanged: (val) => _profile.district = val,
        ),
      ],
    );
  }

  // STEP 2: Demographics (Age, Gender, Marital Status)
  Widget _buildStep2Demographics(bool isHi) {
    final allowWidow = SchemeEngine.shouldAskWidowStatus(_profile.gender, _profile.age);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: isHi ? 'आपकी आयु और लिंग क्या है?' : 'What is your Age and Gender?',
          subtitle: isHi ? 'पेंशन और छात्रवृत्तियां उम्र पर निर्भर करती हैं' : 'Age determines pensions and youth programmes',
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isHi ? 'आयु: ${_profile.age} वर्ष' : 'Age: ${_profile.age} years',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (_profile.age >= 60)
              Chip(
                backgroundColor: AppTheme.lightGreen,
                label: Text(
                  isHi ? 'वरिष्ठ नागरिक (60+)' : 'Senior Citizen (60+)',
                  style: const TextStyle(color: AppTheme.forestGreen, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        Slider(
          value: _profile.age.toDouble(),
          min: 14,
          max: 90,
          divisions: 76,
          activeColor: AppTheme.accentSaffron,
          onChanged: (val) => setState(() => _profile.age = val.toInt()),
        ),
        const SizedBox(height: 16),
        Text(
          isHi ? 'लिंग (Gender):' : 'Gender:',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Row(
          children: ['Male', 'Female', 'Other'].map((g) {
            final isSelected = _profile.gender == g;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: ChoiceChip(
                  label: Center(
                    child: Text(
                      g == 'Male' ? (isHi ? 'पुरुष' : 'Male') : (g == 'Female' ? (isHi ? 'महिला' : 'Female') : (isHi ? 'अन्य' : 'Other')),
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppTheme.primaryNavy,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _profile.gender = g);
                  },
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        Text(
          isHi ? 'वैवाहिक स्थिति:' : 'Marital Status:',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: ['Married', 'Single', if (allowWidow) 'Widow', 'Divorced'].map((m) {
            final isSelected = _profile.maritalStatus == m;
            return ChoiceChip(
              label: Text(
                m == 'Married' ? (isHi ? 'विवाहित' : 'Married') :
                m == 'Single' ? (isHi ? 'अविवाहित' : 'Single') :
                m == 'Widow' ? (isHi ? 'विधवा' : 'Widow') : (isHi ? 'तलाकशुदा' : 'Divorced'),
              ),
              selected: isSelected,
              selectedColor: AppTheme.primaryNavy,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
              onSelected: (val) {
                if (val) setState(() => _profile.maritalStatus = m);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // STEP 3: Livelihood & Occupation (Adaptive branching for Farmer, Artisan, Student)
  Widget _buildStep3Livelihood(bool isHi) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: isHi ? 'आपका मुख्य पेशा / व्यवसाय क्या है?' : 'What is your primary livelihood / occupation?',
          subtitle: isHi ? 'योजनाएं पेशे के आधार पर लक्षित होती हैं' : 'Schemes are targeted by occupational category',
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _occupations.contains(_profile.occupation) ? _profile.occupation : _occupations.first,
          decoration: InputDecoration(
            labelText: isHi ? 'पेशा चुनें' : 'Select Occupation',
            prefixIcon: const Icon(Icons.work_outline, color: AppTheme.primaryNavy),
          ),
          items: _occupations.map((occ) {
            String label = occ;
            if (isHi) {
              const hiMap = {
                'Citizen': 'नागरिक / सामान्य (Citizen)',
                'Farmer': 'किसान (Farmer)',
                'Student': 'छात्र (Student)',
                'Salaried': 'वेतनभोगी (Salaried)',
                'Self-Employed': 'स्वरोजगार (Self-Employed)',
                'Artisan / Craftsman': 'कारीगर / शिल्पकार (Vishwakarma)',
                'Street Vendor': 'रेहड़ी-पटरी / फेरीवाले (Street Vendor)',
                'Daily Wage / Laborer': 'दैनिक मजदूर (Daily Wage / Laborer)',
                'Homemaker': 'गृहिणी (Homemaker)',
                'Senior Citizen': 'वरिष्ठ नागरिक (Senior Citizen)',
                'Unemployed': 'बेरोजगार (Unemployed)',
              };
              label = hiMap[occ] ?? occ;
            }
            return DropdownMenuItem(
              value: occ,
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _profile.occupation = val);
          },
        ),

        // ADAPTIVE SUB-QUESTION: Farmer -> Land Holding
        if (SchemeEngine.shouldAskLandHolding(_profile.occupation)) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.grass, color: AppTheme.forestGreen, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      isHi ? 'कृषि योग्य भूमि (एकड़ में):' : 'Cultivable Agricultural Land (in Acres):',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${_profile.landHoldingAcres.toStringAsFixed(1)} ${isHi ? "एकड़" : "Acres"} '
                  '(${_profile.landHoldingAcres <= 2.5 ? (isHi ? "सीमांत किसान" : "Marginal Farmer") : (_profile.landHoldingAcres <= 5.0 ? (isHi ? "लघु किसान" : "Small Farmer") : (isHi ? "बड़ा किसान" : "Large Farmer"))})',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.forestGreen, fontSize: 15),
                ),
                Slider(
                  value: _profile.landHoldingAcres,
                  min: 0.0,
                  max: 10.0,
                  divisions: 20,
                  activeColor: AppTheme.forestGreen,
                  onChanged: (val) => setState(() => _profile.landHoldingAcres = val),
                ),
                Text(
                  isHi
                      ? 'नोट: 2 हेक्टेयर (लगभग 5 एकड़) तक के किसान पीएम-किसान में प्राथमिकता पाते हैं।'
                      : 'Notice: Land records (Khatauni/RoR) must be registered in your name.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],

        // ADAPTIVE SUB-QUESTION: Artisan -> Traditional Trade
        if (SchemeEngine.shouldAskArtisanTrade(_profile.occupation)) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.handyman_outlined, color: AppTheme.amberWarning, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      isHi ? 'विश्वकर्मा पारंपरिक शिल्प चुनें:' : 'Select PM Vishwakarma Trade:',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _artisanTrades.contains(_profile.artisanTrade) ? _profile.artisanTrade : _artisanTrades.first,
                  decoration: InputDecoration(
                    labelText: isHi ? 'कारीगरी का प्रकार' : 'Trade Category',
                  ),
                  items: _artisanTrades
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              t,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _profile.artisanTrade = val);
                  },
                ),
              ],
            ),
          ),
        ],

        // ADAPTIVE SUB-QUESTION: Student -> Education Level
        if (SchemeEngine.shouldAskStudentLevel(_profile.occupation)) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.school_outlined, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      isHi ? 'वर्तमान शिक्षा का स्तर:' : 'Current Education Level:',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: const ['School (1-10)', 'Post-Matric (11-12/ITI)', 'Higher Ed'].contains(_profile.studentLevel)
                      ? _profile.studentLevel
                      : 'Post-Matric (11-12/ITI)',
                  decoration: InputDecoration(
                    labelText: isHi ? 'कक्षा / स्तर' : 'Study Level',
                  ),
                  items: [
                    DropdownMenuItem(value: 'School (1-10)', child: Text(isHi ? 'कक्षा 1-10 (Pre-Matric)' : 'Class 1-10 (Pre-Matric)', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Post-Matric (11-12/ITI)', child: Text(isHi ? '11वीं, 12वीं, आईटीआई या डिप्लोमा' : 'Class 11-12, ITI or Diploma', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Higher Ed', child: Text(isHi ? 'स्नातक / विश्वविद्यालय (College Degree)' : 'College Degree / University', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _profile.studentLevel = val);
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // STEP 4: Economics (Ration card & Annual Income)
  Widget _buildStep4Economics(bool isHi) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: isHi ? 'पारिवारिक राशन कार्ड और वार्षिक आय' : 'Ration Card & Annual Household Income',
          subtitle: isHi ? 'कल्याणकारी योजनाओं के लिए आय सीमा मुख्य पैमाना है' : 'Economic thresholds gate subsidized welfare',
        ),
        const SizedBox(height: 16),
        Text(
          isHi ? 'राशन कार्ड का प्रकार:' : 'Ration Card Category:',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: const ['Antyodaya (AAY)', 'BPL', 'Priority (PHH)', 'APL', 'None'].contains(_profile.rationCard)
              ? _profile.rationCard
              : 'None',
          decoration: const InputDecoration(prefixIcon: Icon(Icons.credit_card, color: AppTheme.primaryNavy)),
          items: [
            DropdownMenuItem(value: 'Antyodaya (AAY)', child: Text(isHi ? 'अंत्योदय (AAY - सबसे गरीब)' : 'Antyodaya (AAY - Poorest of Poor)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'BPL', child: Text(isHi ? 'बीपीएल (Below Poverty Line)' : 'BPL (Below Poverty Line)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'Priority (PHH)', child: Text(isHi ? 'प्राथमिकता राशन कार्ड (PHH)' : 'Priority Household (PHH)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'APL', child: Text(isHi ? 'एपीएल (Above Poverty Line)' : 'APL (Above Poverty Line)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'None', child: Text(isHi ? 'कोई राशन कार्ड नहीं' : 'No Ration Card', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _profile.rationCard = val);
          },
        ),
        const SizedBox(height: 20),
        Text(
          isHi ? 'वार्षिक पारिवारिक कुल आय:' : 'Annual Total Household Income:',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: const ['< 1 Lakh', '1 - 2.5 Lakh', '2.5 - 5 Lakh', '> 5 Lakh'].contains(_profile.annualIncomeRange)
              ? _profile.annualIncomeRange
              : '1 - 2.5 Lakh',
          decoration: const InputDecoration(prefixIcon: Icon(Icons.currency_rupee, color: AppTheme.primaryNavy)),
          items: [
            DropdownMenuItem(value: '< 1 Lakh', child: Text(isHi ? '₹1 लाख से कम (Under ₹1,00,000)' : 'Under ₹1,00,000 (< 1 Lakh)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: '1 - 2.5 Lakh', child: Text(isHi ? '₹1 लाख से ₹2.5 लाख तक' : '₹1,00,000 - ₹2,50,000', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: '2.5 - 5 Lakh', child: Text(isHi ? '₹2.5 लाख से ₹5 लाख तक' : '₹2,50,000 - ₹5,00,000', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: '> 5 Lakh', child: Text(isHi ? '₹5 लाख से अधिक (> ₹5,00,000)' : 'Above ₹5,00,000 (> 5 Lakh)', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _profile.annualIncomeRange = val);
          },
        ),
      ],
    );
  }

  // STEP 5: Social Category & Special Inclusion
  Widget _buildStep5Category(bool isHi) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: isHi ? 'सामाजिक वर्ग और विशेष स्थिति' : 'Social Category & Vulnerability Status',
          subtitle: isHi ? 'आरक्षण, दिव्यांगता एवं बालिकाओं हेतु विशेष योजनाएं' : 'Affirmative action and targeted welfare',
        ),
        const SizedBox(height: 16),
        Text(
          isHi ? 'सामाजिक वर्ग (Social Category):' : 'Social Category:',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: ['General', 'OBC', 'SC', 'ST', 'EWS'].map((cat) {
            final isSelected = _profile.socialCategory == cat;
            return ChoiceChip(
              label: Text(cat),
              selected: isSelected,
              selectedColor: AppTheme.primaryNavy,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
              onSelected: (val) {
                if (val) setState(() => _profile.socialCategory = cat);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        Text(
          isHi ? 'दिव्यांगता स्थिति (Divyangjan Status):' : 'Disability Status (Divyangjan):',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: const ['None', '< 40%', '40%+ (Divyangjan)'].contains(_profile.disabilityStatus)
              ? _profile.disabilityStatus
              : 'None',
          decoration: const InputDecoration(prefixIcon: Icon(Icons.accessible, color: AppTheme.primaryNavy)),
          items: [
            DropdownMenuItem(value: 'None', child: Text(isHi ? 'कोई दिव्यांगता नहीं' : 'None / Not Applicable', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: '< 40%', child: Text(isHi ? '40% से कम' : 'Mild Disability (< 40%)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: '40%+ (Divyangjan)', child: Text(isHi ? '40% या अधिक (सर्टिफाइड दिव्यांगजन)' : 'Certified Divyangjan (40% or more)', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _profile.disabilityStatus = val);
          },
        ),
        const SizedBox(height: 20),
        CheckboxListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          activeColor: AppTheme.accentSaffron,
          title: Text(
            isHi ? 'क्या परिवार में 10 वर्ष से कम आयु की बेटी है?' : 'Do you have a daughter under 10 years of age?',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            isHi ? 'सुकन्या समृद्धि योजना (8.2% ब्याज दर) हेतु' : 'Qualifies for Sukanya Samriddhi Yojana (8.2% interest)',
            style: const TextStyle(fontSize: 12),
          ),
          value: _profile.hasGirlChildUnder10,
          onChanged: (val) {
            setState(() => _profile.hasGirlChildUnder10 = val ?? false);
          },
        ),
      ],
    );
  }

  Widget _buildSectionHeader({required String title, required String subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppTheme.textDark),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  void _finishAndEvaluate() {
    final schemes = SchemeEngine.evaluate(_profile);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SchemesResultScreen(
          profile: _profile,
          eligibleSchemes: schemes,
          settings: widget.settings,
          repository: widget.repository,
          auth: widget.auth,
        ),
      ),
    );
  }
}
