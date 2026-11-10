import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/scheme_model.dart';
import '../models/internship_model.dart';
import '../../data/schemes_corpus.dart';
import '../../data/internships_corpus.dart';

class LatestUpdatesService extends ChangeNotifier {
  static final LatestUpdatesService _instance = LatestUpdatesService._internal();
  factory LatestUpdatesService() => _instance;
  LatestUpdatesService._internal();
  static LatestUpdatesService get instance => _instance;

  bool _isLoading = false;
  DateTime? _lastRefreshedAt;
  List<SchemeModel> _recentSchemes = [];
  List<InternshipModel> _recentInternships = [];
  String _selectedCategory = 'All'; // 'All', 'Schemes', 'Internships'
  String _selectedState = 'All India';
  bool _mockEmptyForTesting = false;

  bool get isLoading => _isLoading;
  DateTime? get lastRefreshedAt => _lastRefreshedAt;
  String get selectedCategory => _selectedCategory;
  String get selectedState => _selectedState;
  bool get isMockEmptyForTesting => _mockEmptyForTesting;

  List<SchemeModel> get allRecentSchemes => List.unmodifiable(_recentSchemes);
  List<InternshipModel> get allRecentInternships => List.unmodifiable(_recentInternships);

  List<SchemeModel> get filteredSchemes {
    if (_mockEmptyForTesting) return [];
    if (_selectedCategory == 'Internships') return [];

    return _recentSchemes.where((s) {
      if (_selectedState == 'All India') return true;
      return s.isCentral || s.stateScope == _selectedState || s.stateScope == 'All';
    }).toList();
  }

  List<InternshipModel> get filteredInternships {
    if (_mockEmptyForTesting) return [];
    if (_selectedCategory == 'Schemes') return [];

    return _recentInternships.where((i) {
      if (_selectedState == 'All India') return true;
      final loc = i.location.toLowerCase();
      final target = _selectedState.toLowerCase();
      return loc.contains('pan-india') || loc.contains(target) || i.workMode == 'Remote';
    }).toList();
  }

  int get totalRecentCount => filteredSchemes.length + filteredInternships.length;
  bool get hasNoUpdates => totalRecentCount == 0;

  /// Fetches schemes and internships announced or launched in the last 1 month (31 days).
  /// Every time the user opens the application, this is automatically called.
  Future<void> fetchUpdates({bool forceRefresh = false}) async {
    if (_isLoading && !forceRefresh) return;

    _isLoading = true;
    notifyListeners();

    try {
      // Realistic simulation of network sync with central/state gazette & portal updates
      await Future.delayed(const Duration(milliseconds: 500));

      final allSchemes = SchemesCorpus.getSchemes();
      final allInternships = InternshipsCorpus.getInternships();

      // The corpus is static, so a window anchored to the real clock would drain
      // to empty as time passes. Anchor it to the newest dated entry instead
      // (capped at today so future-dated entries don't push the window forward).
      final now = _windowAnchor(allSchemes, allInternships);

      // Schemes launched or announced in last 1 month
      final matchedSchemes = allSchemes.where((s) {
        return s.isLaunchedInLastMonth(referenceDate: now);
      }).toList();

      // Sort newest first
      matchedSchemes.sort((a, b) {
        final dateA = a.parsedAnnouncedDate ?? DateTime(2020);
        final dateB = b.parsedAnnouncedDate ?? DateTime(2020);
        return dateB.compareTo(dateA);
      });

      // Internships announced or posted in last 1 month
      final matchedInternships = allInternships.where((i) {
        return i.isPostedInLastMonth(referenceDate: now);
      }).toList();

      // Sort newest first
      matchedInternships.sort((a, b) {
        final dateA = a.parsedPostedDate ?? DateTime(2020);
        final dateB = b.parsedPostedDate ?? DateTime(2020);
        return dateB.compareTo(dateA);
      });

      _recentSchemes = matchedSchemes;
      _recentInternships = matchedInternships;
      _lastRefreshedAt = DateTime.now();
    } catch (e) {
      debugPrint('Error fetching latest updates: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  static DateTime _windowAnchor(
    List<SchemeModel> schemes,
    List<InternshipModel> internships,
  ) {
    final today = DateTime.now();
    DateTime? newest;
    for (final d in [
      ...schemes.map((s) => s.parsedAnnouncedDate),
      ...internships.map((i) => i.parsedPostedDate),
    ]) {
      if (d != null && (newest == null || d.isAfter(newest))) newest = d;
    }
    if (newest == null || newest.isAfter(today)) return today;
    return newest;
  }

  /// User manual refresh
  Future<void> manualRefresh() async {
    await fetchUpdates(forceRefresh: true);
  }

  void setCategoryFilter(String category) {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    notifyListeners();
  }

  void setStateFilter(String state) {
    if (_selectedState == state) return;
    _selectedState = state;
    notifyListeners();
  }

  /// Allows toggling empty state for testing & verification
  void setMockEmptyForTesting(bool empty) {
    _mockEmptyForTesting = empty;
    notifyListeners();
  }
}
