enum RegionType { state, unionTerritory }

class AdministrativeRegion {
  final String name;
  final String code;
  final RegionType type;
  final String regionalLanguage;

  const AdministrativeRegion({
    required this.name,
    required this.code,
    required this.type,
    required this.regionalLanguage,
  });

  bool get isState => type == RegionType.state;
  bool get isUnionTerritory => type == RegionType.unionTerritory;
}

class IndianRegions {
  // All 28 States of India
  static const List<AdministrativeRegion> states = [
    AdministrativeRegion(name: 'Andhra Pradesh', code: 'AP', type: RegionType.state, regionalLanguage: 'Telugu'),
    AdministrativeRegion(name: 'Arunachal Pradesh', code: 'AR', type: RegionType.state, regionalLanguage: 'English'),
    AdministrativeRegion(name: 'Assam', code: 'AS', type: RegionType.state, regionalLanguage: 'Assamese'),
    AdministrativeRegion(name: 'Bihar', code: 'BR', type: RegionType.state, regionalLanguage: 'Hindi'),
    AdministrativeRegion(name: 'Chhattisgarh', code: 'CG', type: RegionType.state, regionalLanguage: 'Hindi'),
    AdministrativeRegion(name: 'Goa', code: 'GA', type: RegionType.state, regionalLanguage: 'Konkani'),
    AdministrativeRegion(name: 'Gujarat', code: 'GJ', type: RegionType.state, regionalLanguage: 'Gujarati'),
    AdministrativeRegion(name: 'Haryana', code: 'HR', type: RegionType.state, regionalLanguage: 'Hindi'),
    AdministrativeRegion(name: 'Himachal Pradesh', code: 'HP', type: RegionType.state, regionalLanguage: 'Hindi'),
    AdministrativeRegion(name: 'Jharkhand', code: 'JH', type: RegionType.state, regionalLanguage: 'Hindi'),
    AdministrativeRegion(name: 'Karnataka', code: 'KA', type: RegionType.state, regionalLanguage: 'Kannada'),
    AdministrativeRegion(name: 'Kerala', code: 'KL', type: RegionType.state, regionalLanguage: 'Malayalam'),
    AdministrativeRegion(name: 'Madhya Pradesh', code: 'MP', type: RegionType.state, regionalLanguage: 'Hindi'),
    AdministrativeRegion(name: 'Maharashtra', code: 'MH', type: RegionType.state, regionalLanguage: 'Marathi'),
    AdministrativeRegion(name: 'Manipur', code: 'MN', type: RegionType.state, regionalLanguage: 'Manipuri'),
    AdministrativeRegion(name: 'Meghalaya', code: 'ML', type: RegionType.state, regionalLanguage: 'English'),
    AdministrativeRegion(name: 'Mizoram', code: 'MZ', type: RegionType.state, regionalLanguage: 'Mizo'),
    AdministrativeRegion(name: 'Nagaland', code: 'NL', type: RegionType.state, regionalLanguage: 'English'),
    AdministrativeRegion(name: 'Odisha', code: 'OR', type: RegionType.state, regionalLanguage: 'Odia'),
    AdministrativeRegion(name: 'Punjab', code: 'PB', type: RegionType.state, regionalLanguage: 'Punjabi'),
    AdministrativeRegion(name: 'Rajasthan', code: 'RJ', type: RegionType.state, regionalLanguage: 'Hindi'),
    AdministrativeRegion(name: 'Sikkim', code: 'SK', type: RegionType.state, regionalLanguage: 'Nepali'),
    AdministrativeRegion(name: 'Tamil Nadu', code: 'TN', type: RegionType.state, regionalLanguage: 'Tamil'),
    AdministrativeRegion(name: 'Telangana', code: 'TS', type: RegionType.state, regionalLanguage: 'Telugu'),
    AdministrativeRegion(name: 'Tripura', code: 'TR', type: RegionType.state, regionalLanguage: 'Bengali'),
    AdministrativeRegion(name: 'Uttar Pradesh', code: 'UP', type: RegionType.state, regionalLanguage: 'Hindi'),
    AdministrativeRegion(name: 'Uttarakhand', code: 'UK', type: RegionType.state, regionalLanguage: 'Hindi'),
    AdministrativeRegion(name: 'West Bengal', code: 'WB', type: RegionType.state, regionalLanguage: 'Bengali'),
  ];

  // All 8 Union Territories of India
  static const List<AdministrativeRegion> unionTerritories = [
    AdministrativeRegion(name: 'Andaman and Nicobar Islands', code: 'AN', type: RegionType.unionTerritory, regionalLanguage: 'Hindi / English'),
    AdministrativeRegion(name: 'Chandigarh', code: 'CH', type: RegionType.unionTerritory, regionalLanguage: 'Punjabi / Hindi'),
    AdministrativeRegion(name: 'Dadra and Nagar Haveli and Daman and Diu', code: 'DH', type: RegionType.unionTerritory, regionalLanguage: 'Gujarati / Hindi'),
    AdministrativeRegion(name: 'Delhi (NCT)', code: 'DL', type: RegionType.unionTerritory, regionalLanguage: 'Hindi'),
    AdministrativeRegion(name: 'Jammu and Kashmir', code: 'JK', type: RegionType.unionTerritory, regionalLanguage: 'Kashmiri / Dogri / Urdu'),
    AdministrativeRegion(name: 'Ladakh', code: 'LA', type: RegionType.unionTerritory, regionalLanguage: 'Ladakhi / Hindi'),
    AdministrativeRegion(name: 'Lakshadweep', code: 'LD', type: RegionType.unionTerritory, regionalLanguage: 'Malayalam'),
    AdministrativeRegion(name: 'Puducherry', code: 'PY', type: RegionType.unionTerritory, regionalLanguage: 'Tamil / French'),
  ];

  // Complete List: All 36 Administrative Entities
  static List<AdministrativeRegion> get allRegions => [...states, ...unionTerritories];

  static List<String> get stateNames => states.map((s) => s.name).toList();
  static List<String> get utNames => unionTerritories.map((ut) => ut.name).toList();

  // String list for pickers: 'All India', followed by 28 states, followed by 8 UTs
  static List<String> get allRegionNames => [
    'All India',
    ...states.map((s) => s.name),
    ...unionTerritories.map((ut) => ut.name),
  ];

  static bool isUnionTerritory(String regionName) {
    return unionTerritories.any((ut) => ut.name == regionName || ut.name.toLowerCase() == regionName.toLowerCase());
  }
}
