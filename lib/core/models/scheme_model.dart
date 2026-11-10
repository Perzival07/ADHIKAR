enum RouteType { online, csc, panchayat, blockOffice, bankBranch }

class DocumentItem {
  final String id;
  final String name;
  final String nameHi;
  final String issuingAuthority;
  final String tip;
  final String tipHi;
  final bool isRequired;

  DocumentItem({
    required this.id,
    required this.name,
    required this.nameHi,
    required this.issuingAuthority,
    required this.tip,
    required this.tipHi,
    this.isRequired = true,
  });
}

class ApplicationRoute {
  final RouteType type;
  final String title;
  final String titleHi;
  final String instructions;
  final String instructionsHi;
  final String? url;

  ApplicationRoute({
    required this.type,
    required this.title,
    required this.titleHi,
    required this.instructions,
    required this.instructionsHi,
    this.url,
  });
}

class SchemeModel {
  final String id;
  final String name;
  final String nameHi;
  final String ministry;
  final String category;
  final String summary;
  final String summaryHi;
  final String benefit;
  final String benefitHi;
  final String defaultPlainReason;
  final String defaultPlainReasonHi;
  final List<DocumentItem> documents;
  final List<ApplicationRoute> routes;
  final String department;
  final String timeline;
  final String provenance;
  final String lastVerifiedDate;
  final String officialPortalUrl;
  final String verificationCaveat;
  final bool isCentral;
  final String stateScope; // 'All' or specific state / UT name

  // Expanded filters & metadata
  final String educationLevel; // 'All', 'School', '10th / 12th', 'Graduate / Degree', 'Diploma / ITI'
  final String incomeCeiling; // 'No Limit', '< 1 Lakh', '< 2.5 Lakh', '< 5 Lakh'
  final String genderEligibility; // 'All', 'Female', 'Male'
  final String applicationStatus; // 'Open / Ongoing', 'Annual Cycle', 'Rolling', 'Expired / Superseded'
  final String deadline; // 'Ongoing', 'Annual Academic Cycle', etc.
  final bool isVerified;
  final bool isExpired;
  final int? minAge;
  final int? maxAge;
  final String officialSource; // 'myScheme.gov.in', 'india.gov.in', State Department Portal
  final String? announcedDate; // e.g. '2026-10-08'
  final bool isRecentLaunch;

  // Runtime fields
  double matchConfidence; // 0.0 to 1.0
  String? generatedReason;
  String? generatedReasonHi;

  bool isAgeEligible(int age) {
    if (minAge != null && age < minAge!) return false;
    if (maxAge != null && age > maxAge!) return false;
    return true;
  }

  DateTime? get parsedAnnouncedDate =>
      announcedDate != null ? DateTime.tryParse(announcedDate!) : null;

  /// Whether the scheme was launched or announced in the last 1 month (31 days)
  bool isLaunchedInLastMonth({DateTime? referenceDate}) {
    final now = referenceDate ?? DateTime.now();
    final dt = parsedAnnouncedDate;
    if (dt != null) {
      final diff = now.difference(dt);
      return diff.inDays >= 0 && diff.inDays <= 31;
    }
    return isRecentLaunch;
  }

  SchemeModel({
    required this.id,
    required this.name,
    required this.nameHi,
    required this.ministry,
    required this.category,
    required this.summary,
    required this.summaryHi,
    required this.benefit,
    required this.benefitHi,
    required this.defaultPlainReason,
    required this.defaultPlainReasonHi,
    required this.documents,
    required this.routes,
    required this.department,
    required this.timeline,
    required this.provenance,
    required this.lastVerifiedDate,
    required this.officialPortalUrl,
    required this.verificationCaveat,
    this.isCentral = true,
    this.stateScope = 'All',
    this.educationLevel = 'All',
    this.incomeCeiling = 'No Limit',
    this.genderEligibility = 'All',
    this.applicationStatus = 'Open / Ongoing',
    this.deadline = 'Ongoing',
    this.isVerified = true,
    this.isExpired = false,
    this.minAge,
    this.maxAge,
    this.officialSource = 'myScheme.gov.in',
    this.announcedDate,
    this.isRecentLaunch = false,
    this.matchConfidence = 1.0,
    this.generatedReason,
    this.generatedReasonHi,
  });
}
