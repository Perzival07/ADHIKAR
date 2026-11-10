class InternshipModel {
  final String id;
  final String title;
  final String titleHi;
  final String organization;
  final String portalSource; // 'AICTE Internship Portal', 'TULIP', 'NATS', 'PM Internship', 'ISRO Portal', etc.
  final String category; // 'IT & AI', 'Urban Governance', 'Core Engineering', 'Space & Defense', 'Public Policy', 'Green Energy', 'Management'
  final String stipend;
  final String duration;
  final String location;
  final String openings;
  final String eligibility;
  final String eligibilityHi;
  final List<String> perks;
  final List<String> documents;
  final String officialUrl;
  final String deadline;
  final String about;
  final String aboutHi;

  // Additional facets requested
  final String workMode; // 'Remote', 'Hybrid', 'On-site'
  final String companyType; // 'Central Govt', 'PSU', 'Research Lab', 'Private Tech', 'State Govt', 'Startup'
  final String status; // 'Verified Open', 'Actively Recruiting', 'Rolling Cycle'
  final bool isExpired;
  final String? postedDate; // e.g. '2026-10-15'
  final bool isRecentLaunch;

  DateTime? get parsedPostedDate =>
      postedDate != null ? DateTime.tryParse(postedDate!) : null;

  /// Whether the internship was posted or announced in the last 1 month (31 days)
  bool isPostedInLastMonth({DateTime? referenceDate}) {
    final now = referenceDate ?? DateTime.now();
    final dt = parsedPostedDate;
    if (dt != null) {
      final diff = now.difference(dt);
      return diff.inDays >= 0 && diff.inDays <= 31;
    }
    return isRecentLaunch;
  }

  const InternshipModel({
    required this.id,
    required this.title,
    required this.titleHi,
    required this.organization,
    required this.portalSource,
    required this.category,
    required this.stipend,
    required this.duration,
    required this.location,
    required this.openings,
    required this.eligibility,
    required this.eligibilityHi,
    required this.perks,
    required this.documents,
    required this.officialUrl,
    required this.deadline,
    required this.about,
    required this.aboutHi,
    this.workMode = 'Remote',
    this.companyType = 'Central Govt',
    this.status = 'Verified Open',
    this.isExpired = false,
    this.postedDate,
    this.isRecentLaunch = false,
  });
}
