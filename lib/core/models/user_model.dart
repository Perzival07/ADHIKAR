class UserModel {
  final String id;
  final String name;
  final String phoneOrEmail;
  final String state;
  final String socialCategory;
  final String occupation;
  final DateTime createdAt;
  final bool isVerified;

  const UserModel({
    required this.id,
    required this.name,
    required this.phoneOrEmail,
    required this.state,
    this.socialCategory = 'General',
    this.occupation = 'Citizen',
    required this.createdAt,
    this.isVerified = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phoneOrEmail': phoneOrEmail,
      'state': state,
      'socialCategory': socialCategory,
      'occupation': occupation,
      'createdAt': createdAt.toIso8601String(),
      'isVerified': isVerified,
    };
  }

  /// From auth-service's `UserOut` (backend/contracts/openapi/auth-service.yaml).
  factory UserModel.fromServer(Map<String, dynamic> j) => UserModel(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Citizen',
        phoneOrEmail: (j['email'] as String?) ?? (j['phone'] as String?) ?? '',
        state: (j['state'] as String?) ?? 'All India',
        socialCategory: (j['socialCategory'] as String?) ?? 'General',
        occupation: (j['occupation'] as String?) ?? 'Citizen',
        createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? '') ?? DateTime.now(),
        isVerified: (j['isVerified'] as bool?) ?? true,
      );

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String? ?? 'user_1',
      name: json['name'] as String? ?? 'Citizen',
      phoneOrEmail: json['phoneOrEmail'] as String? ?? '',
      state: json['state'] as String? ?? 'Uttar Pradesh',
      socialCategory: json['socialCategory'] as String? ?? 'General',
      occupation: json['occupation'] as String? ?? 'Citizen',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      isVerified: json['isVerified'] as bool? ?? true,
    );
  }

  UserModel copyWith({
    String? name,
    String? phoneOrEmail,
    String? state,
    String? socialCategory,
    String? occupation,
    bool? isVerified,
  }) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      phoneOrEmail: phoneOrEmail ?? this.phoneOrEmail,
      state: state ?? this.state,
      socialCategory: socialCategory ?? this.socialCategory,
      occupation: occupation ?? this.occupation,
      createdAt: createdAt,
      isVerified: isVerified ?? this.isVerified,
    );
  }
}
