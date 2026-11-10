import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/rag_config.dart';

class SettingsService extends ChangeNotifier {
  /// Tests can pretend an AI backend is (not) configured; production uses RAG_API_URL.
  final bool? aiAvailableOverride;

  SettingsService({this.aiAvailableOverride});

  static const String _prefLanguage = 'preferred_language';
  static const String _prefSelectedState = 'preferred_state';
  static const String _prefCheckedDocs = 'checked_documents_prefix_';
  static const String _prefAiEnabled = 'ai_recommendations_enabled';

  late SharedPreferences _prefs;
  bool _isInitialized = false;

  String _currentLanguage = 'en';
  String _selectedState = 'All India';
  bool _aiPreference = true;
  final Set<String> _checkedDocIds = {};

  bool get isInitialized => _isInitialized;
  String get currentLanguage => _currentLanguage;
  String get selectedState => _selectedState;

  /// AI (RAG) recommendations can only be used when a backend URL was provided at build time.
  bool get aiRecommendationsAvailable => aiAvailableOverride ?? RagConfig.isConfigured;

  /// Default ON only when RAG_API_URL is set; the user can switch it off in Settings.
  bool get aiRecommendationsEnabled => aiRecommendationsAvailable && _aiPreference;

  Future<void> setAiRecommendationsEnabled(bool value) async {
    _aiPreference = value;
    if (_isInitialized) await _prefs.setBool(_prefAiEnabled, value);
    notifyListeners();
  }

  // Language convenience getters
  bool get isHindi => _currentLanguage == 'hi';
  bool get isMarathi => _currentLanguage == 'mr';
  bool get isGujarati => _currentLanguage == 'gu';
  bool get isBengali => _currentLanguage == 'bn';
  bool get isTamil => _currentLanguage == 'ta';
  bool get isTelugu => _currentLanguage == 'te';
  bool get isKannada => _currentLanguage == 'kn';
  bool get isMalayalam => _currentLanguage == 'ml';
  bool get isPunjabi => _currentLanguage == 'pa';
  bool get isOdia => _currentLanguage == 'or';
  bool get isUrdu => _currentLanguage == 'ur';
  bool get isAssamese => _currentLanguage == 'as';

  // RTL Directionality getter (Urdu, Kashmiri in Arabic-Persian script, Sindhi)
  bool get isRtl => _currentLanguage == 'ur' || _currentLanguage == 'ks' || _currentLanguage == 'sd';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    _currentLanguage = _prefs.getString(_prefLanguage) ?? 'en';
    _selectedState = _prefs.getString(_prefSelectedState) ?? 'All India';
    _aiPreference = _prefs.getBool(_prefAiEnabled) ?? true; // effective only when a backend is configured

    // Load checked docs
    final keys = _prefs.getKeys().where((k) => k.startsWith(_prefCheckedDocs));
    for (var k in keys) {
      if (_prefs.getBool(k) == true) {
        _checkedDocIds.add(k.replaceFirst(_prefCheckedDocs, ''));
      }
    }

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setLanguage(String langCode) async {
    _currentLanguage = langCode;
    if (_isInitialized) {
      await _prefs.setString(_prefLanguage, langCode);
    }
    notifyListeners();
  }

  void toggleLanguage() {
    if (_currentLanguage == 'hi') {
      setLanguage('en');
    } else {
      setLanguage('hi');
    }
  }

  // Complete List: English + All 22 Constitutionally Scheduled Languages of India
  static const List<Map<String, String>> supportedLanguages = [
    {'code': 'en', 'name': 'English', 'native': 'English', 'script': 'Latin'},
    {'code': 'as', 'name': 'Assamese', 'native': 'অসমীয়া', 'script': 'Bengali-Assamese'},
    {'code': 'bn', 'name': 'Bengali', 'native': 'বাংলা', 'script': 'Bengali'},
    {'code': 'brx', 'name': 'Bodo', 'native': 'बड़ो', 'script': 'Devanagari'},
    {'code': 'doi', 'name': 'Dogri', 'native': 'डोगरी', 'script': 'Devanagari'},
    {'code': 'gu', 'name': 'Gujarati', 'native': 'ગુજરાતી', 'script': 'Gujarati'},
    {'code': 'hi', 'name': 'Hindi', 'native': 'हिन्दी', 'script': 'Devanagari'},
    {'code': 'kn', 'name': 'Kannada', 'native': 'ಕನ್ನಡ', 'script': 'Kannada'},
    {'code': 'ks', 'name': 'Kashmiri', 'native': 'کٲشُر / कॉशुर', 'script': 'Perso-Arabic / Devanagari'},
    {'code': 'kok', 'name': 'Konkani', 'native': 'कोंकणी', 'script': 'Devanagari'},
    {'code': 'mai', 'name': 'Maithili', 'native': 'मैथिली', 'script': 'Devanagari'},
    {'code': 'ml', 'name': 'Malayalam', 'native': 'മലയാളം', 'script': 'Malayalam'},
    {'code': 'mni', 'name': 'Manipuri', 'native': 'মৈতৈলোন্', 'script': 'Meetei Mayek / Bengali'},
    {'code': 'mr', 'name': 'Marathi', 'native': 'मराठी', 'script': 'Devanagari'},
    {'code': 'ne', 'name': 'Nepali', 'native': 'नेपाली', 'script': 'Devanagari'},
    {'code': 'or', 'name': 'Odia', 'native': 'ଓଡ଼ିଆ', 'script': 'Odia'},
    {'code': 'pa', 'name': 'Punjabi', 'native': 'ਪੰਜਾਬੀ', 'script': 'Gurmukhi'},
    {'code': 'sa', 'name': 'Sanskrit', 'native': 'संस्कृतम्', 'script': 'Devanagari'},
    {'code': 'sat', 'name': 'Santali', 'native': 'ᱥᱟᱱᱛᱟᱲᱤ', 'script': 'Ol Chiki / Devanagari'},
    {'code': 'sd', 'name': 'Sindhi', 'native': 'سنڌي / सिन्धी', 'script': 'Perso-Arabic / Devanagari'},
    {'code': 'ta', 'name': 'Tamil', 'native': 'தமிழ்', 'script': 'Tamil'},
    {'code': 'te', 'name': 'Telugu', 'native': 'తెలుగు', 'script': 'Telugu'},
    {'code': 'ur', 'name': 'Urdu', 'native': 'اُردُو', 'script': 'Nastaliq (RTL)'},
  ];

  Future<void> setSelectedState(String stateName) async {
    _selectedState = stateName;
    if (_isInitialized) {
      await _prefs.setString(_prefSelectedState, stateName);
    }
    notifyListeners();
  }

  bool isDocumentChecked(String schemeId, String docId) {
    return _checkedDocIds.contains('${schemeId}_$docId');
  }

  Future<void> toggleDocumentCheck(String schemeId, String docId) async {
    final key = '${schemeId}_$docId';
    if (_checkedDocIds.contains(key)) {
      _checkedDocIds.remove(key);
      if (_isInitialized) {
        await _prefs.setBool('$_prefCheckedDocs$key', false);
      }
    } else {
      _checkedDocIds.add(key);
      if (_isInitialized) {
        await _prefs.setBool('$_prefCheckedDocs$key', true);
      }
    }
    notifyListeners();
  }
}
