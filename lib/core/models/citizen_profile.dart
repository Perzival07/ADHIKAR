class CitizenProfile {
  String state;
  String district;
  int age;
  String gender; // 'Male', 'Female', 'Other'
  String maritalStatus; // 'Single', 'Married', 'Widow', 'Divorced'
  String occupation; // 'Farmer', 'Artisan / Craftsman', 'Street Vendor', 'Daily Wage / Laborer', 'Self-Employed', 'Salaried', 'Student', 'Unemployed', 'Homemaker'
  double landHoldingAcres; // 0 for landless/non-farmer
  String artisanTrade; // Carpentry, Pottery, Blacksmith, Weaving, Masonry, etc.
  String studentLevel; // 'None', 'School (1-10)', 'Post-Matric (11-12/ITI)', 'Higher Ed'
  String socialCategory; // 'General', 'OBC', 'SC', 'ST', 'EWS'
  String rationCard; // 'Antyodaya (AAY)', 'BPL', 'Priority (PHH)', 'APL', 'None'
  String annualIncomeRange; // '< 1 Lakh', '1 - 2.5 Lakh', '2.5 - 5 Lakh', '> 5 Lakh'
  String disabilityStatus; // 'None', '< 40%', '40%+ (Divyangjan)'
  bool hasGirlChildUnder10;

  CitizenProfile({
    this.state = 'Uttar Pradesh',
    this.district = '',
    this.age = 35,
    this.gender = 'Male',
    this.maritalStatus = 'Married',
    this.occupation = 'Citizen',
    this.landHoldingAcres = 0.0,
    this.artisanTrade = '',
    this.studentLevel = 'None',
    this.socialCategory = 'General',
    this.rationCard = 'None',
    this.annualIncomeRange = '1 - 2.5 Lakh',
    this.disabilityStatus = 'None',
    this.hasGirlChildUnder10 = false,
  });

  bool get isFarmer => occupation == 'Farmer';
  bool get isSalaried => occupation == 'Salaried';
  bool get isArtisan => occupation == 'Artisan / Craftsman';
  bool get isStreetVendor => occupation == 'Street Vendor';
  bool get isStudent => occupation == 'Student' || studentLevel != 'None';
  bool get isSenior => age >= 60;
  bool get isWidow => gender == 'Female' && maritalStatus == 'Widow';
  bool get isLowIncome =>
      annualIncomeRange == '< 1 Lakh' || annualIncomeRange == '1 - 2.5 Lakh';
  bool get hasBplOrAay =>
      rationCard == 'Antyodaya (AAY)' ||
      rationCard == 'BPL' ||
      rationCard == 'Priority (PHH)';
  bool get isDivyangjan => disabilityStatus == '40%+ (Divyangjan)';

  Map<String, dynamic> toJson() {
    return {
      'state': state,
      'district': district,
      'age': age,
      'gender': gender,
      'maritalStatus': maritalStatus,
      'occupation': occupation,
      'landHoldingAcres': landHoldingAcres,
      'artisanTrade': artisanTrade,
      'studentLevel': studentLevel,
      'socialCategory': socialCategory,
      'rationCard': rationCard,
      'annualIncomeRange': annualIncomeRange,
      'disabilityStatus': disabilityStatus,
      'hasGirlChildUnder10': hasGirlChildUnder10,
    };
  }

  factory CitizenProfile.empty() => CitizenProfile();

  /// Independent copy (the wizard mutates its profile in place).
  factory CitizenProfile.copyOf(CitizenProfile o) => CitizenProfile(
        state: o.state,
        district: o.district,
        age: o.age,
        gender: o.gender,
        maritalStatus: o.maritalStatus,
        occupation: o.occupation,
        landHoldingAcres: o.landHoldingAcres,
        artisanTrade: o.artisanTrade,
        studentLevel: o.studentLevel,
        socialCategory: o.socialCategory,
        rationCard: o.rationCard,
        annualIncomeRange: o.annualIncomeRange,
        disabilityStatus: o.disabilityStatus,
        hasGirlChildUnder10: o.hasGirlChildUnder10,
      );
}
