import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/auth_config.dart';
import '../models/user_model.dart';
import 'auth_api_client.dart';
import 'email_otp_service.dart';
import 'token_store.dart';

class AuthResult {
  final bool success;
  final String? message;
  final UserModel? user;

  const AuthResult({
    required this.success,
    this.message,
    this.user,
  });
}

/// Accounts for the app.
///
/// * Remote mode (AUTH_API_URL set): real accounts on auth-service; OTP codes are sent by the server, the
///   refresh token is kept in secure storage and access tokens only in memory.
/// * Local mode (no AUTH_API_URL): the original offline demo accounts stored on the device.
class AuthService extends ChangeNotifier {
  AuthService({AuthApiClient? api, TokenStore? tokenStore})
      : _api = api ?? (AuthConfig.isRemote ? AuthApiClient() : null),
        _tokens = tokenStore ?? ((api != null || AuthConfig.isRemote) ? SecureTokenStore() : MemoryTokenStore());

  final AuthApiClient? _api;
  final TokenStore _tokens;
  String? _accessToken;
  DateTime? _accessExpiry;
  String? _refreshToken;
  DateTime? _otpRequestedAt;
  int _otpCooldown = 60;
  static const String _prefRemoteUser = 'adhikar_remote_user_cache';

  /// True when accounts live on the server (auth-service).
  bool get isRemote => _api != null;

  /// Local demo mode can tell whether an email is registered; the server deliberately cannot (no enumeration).
  bool get canCheckAccounts => !isRemote;

  static const String _prefCurrentUser = 'adhikar_current_user_session';
  static const String _prefIsLoggedIn = 'adhikar_is_logged_in_state';
  static const String _prefAccountsDb = 'adhikar_accounts_database';

  UserModel? _currentUser;
  bool _isInitialized = false;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isInitialized => _isInitialized;

  String get userName => _currentUser?.name ?? 'Citizen';
  String get userPhoneOrEmail => _currentUser?.phoneOrEmail ?? '';
  String get userState => _currentUser?.state ?? 'All India';

  static String _newSalt() {
    final r = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  static String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  /// Writes a salted hash into the account record and removes any plaintext.
  static void _setPassword(Map<String, dynamic> account, String password) {
    final salt = _newSalt();
    account['salt'] = salt;
    account['passwordHash'] = _hash(password, salt);
    account.remove('password');
  }

  Future<void> init() async {
    if (isRemote) return _remoteInit();
    final prefs = await SharedPreferences.getInstance();

    // Check if accounts DB exists, otherwise initialize with default verified citizen
    final accountsJson = prefs.getString(_prefAccountsDb);
    if (accountsJson == null || accountsJson.isEmpty) {
      final defaultAccounts = {
        'citizen@adhikar.gov.in': {
          'user': {
            'id': 'citizen_verified_1',
            'name': 'Rajesh Sharma',
            'phoneOrEmail': 'citizen@adhikar.gov.in',
            'state': 'Uttar Pradesh',
            'socialCategory': 'OBC',
            'occupation': 'Farmer',
            'createdAt': DateTime(2024, 1, 15).toIso8601String(),
            'isVerified': true,
          },
          'password': 'password123',
        },
        '9876543210': {
          'user': {
            'id': 'citizen_verified_2',
            'name': 'Priya Patel',
            'phoneOrEmail': '9876543210',
            'state': 'Gujarat',
            'socialCategory': 'General',
            'occupation': 'Student',
            'createdAt': DateTime(2024, 3, 20).toIso8601String(),
            'isVerified': true,
          },
          'password': 'password123',
        },
      };
      for (final acc in defaultAccounts.values) {
        final account = acc as Map<String, dynamic>;
        _setPassword(account, account['password'] as String);
      }
      await prefs.setString(_prefAccountsDb, jsonEncode(defaultAccounts));
    }

    // Restore active session if logged in
    final isLoggedIn = prefs.getBool(_prefIsLoggedIn) ?? false;
    final savedUserJson = prefs.getString(_prefCurrentUser);

    if (isLoggedIn && savedUserJson != null && savedUserJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(savedUserJson) as Map<String, dynamic>;
        _currentUser = UserModel.fromJson(decoded);
      } catch (e) {
        debugPrint('Failed to decode user session: $e');
        _currentUser = null;
      }
    }

    _isInitialized = true;
    notifyListeners();
  }

  Future<AuthResult> signIn({
    required String phoneOrEmail,
    required String password,
  }) async {
    if (isRemote) return _remote(() => _api!.login(phoneOrEmail.trim(), password));
    final normalizedIdentifier = phoneOrEmail.trim().toLowerCase();
    final cleanPassword = password.trim();

    if (normalizedIdentifier.isEmpty || cleanPassword.isEmpty) {
      return const AuthResult(
        success: false,
        message: 'Please provide both phone/email and password.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final accountsJson = prefs.getString(_prefAccountsDb) ?? '{}';
    final Map<String, dynamic> accounts = jsonDecode(accountsJson) as Map<String, dynamic>;

    // Look for matching account
    Map<String, dynamic>? matchedAccount;
    for (var key in accounts.keys) {
      if (key.toLowerCase() == normalizedIdentifier) {
        matchedAccount = accounts[key] as Map<String, dynamic>?;
        break;
      }
    }

    if (matchedAccount == null) {
      return const AuthResult(
        success: false,
        message: 'No account found with this phone number or email.',
      );
    }

    final storedHash = matchedAccount['passwordHash'] as String?;
    final bool passwordOk;
    if (storedHash != null) {
      passwordOk = _hash(cleanPassword, matchedAccount['salt'] as String? ?? '') == storedHash;
    } else {
      // Legacy plaintext record: verify, then upgrade it to a salted hash.
      passwordOk = (matchedAccount['password'] as String? ?? '') == cleanPassword;
      if (passwordOk) {
        _setPassword(matchedAccount, cleanPassword);
        await prefs.setString(_prefAccountsDb, jsonEncode(accounts));
      }
    }
    if (!passwordOk) {
      return const AuthResult(
        success: false,
        message: 'Incorrect password. Please verify your credentials.',
      );
    }

    final userData = matchedAccount['user'] as Map<String, dynamic>;
    final user = UserModel.fromJson(userData);

    _currentUser = user;
    await prefs.setBool(_prefIsLoggedIn, true);
    await prefs.setString(_prefCurrentUser, jsonEncode(user.toJson()));

    notifyListeners();
    return AuthResult(success: true, user: user);
  }

  Future<AuthResult> signUp({
    required String name,
    required String phoneOrEmail,
    required String password,
    required String state,
    String socialCategory = 'General',
    String occupation = 'Citizen',
  }) async {
    if (isRemote) {
      return const AuthResult(success: false, message: 'Create an account with the emailed code (requestOtp + completeOtp).');
    }
    final normalizedIdentifier = phoneOrEmail.trim().toLowerCase();
    final cleanPassword = password.trim();
    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      return const AuthResult(success: false, message: 'Please enter your full name.');
    }
    if (normalizedIdentifier.isEmpty) {
      return const AuthResult(success: false, message: 'Please enter a valid phone number or email.');
    }
    if (cleanPassword.length < 6) {
      return const AuthResult(success: false, message: 'Password must be at least 6 characters.');
    }

    final prefs = await SharedPreferences.getInstance();
    final accountsJson = prefs.getString(_prefAccountsDb) ?? '{}';
    final Map<String, dynamic> accounts = jsonDecode(accountsJson) as Map<String, dynamic>;

    // Check if account already exists
    for (var key in accounts.keys) {
      if (key.toLowerCase() == normalizedIdentifier) {
        return const AuthResult(
          success: false,
          message: 'An account with this phone or email already exists. Please Sign In.',
        );
      }
    }

    final newUser = UserModel(
      id: 'citizen_${DateTime.now().millisecondsSinceEpoch}',
      name: cleanName,
      phoneOrEmail: phoneOrEmail.trim(),
      state: state.isNotEmpty ? state : 'Uttar Pradesh',
      socialCategory: socialCategory,
      occupation: occupation,
      createdAt: DateTime.now(),
      isVerified: true,
    );

    final newAccount = <String, dynamic>{'user': newUser.toJson()};
    _setPassword(newAccount, cleanPassword);
    accounts[normalizedIdentifier] = newAccount;

    await prefs.setString(_prefAccountsDb, jsonEncode(accounts));
    await prefs.setBool(_prefIsLoggedIn, true);
    await prefs.setString(_prefCurrentUser, jsonEncode(newUser.toJson()));

    _currentUser = newUser;
    notifyListeners();

    return AuthResult(success: true, user: newUser);
  }

  Future<bool> accountExists(String phoneOrEmail) async {
    final normalized = phoneOrEmail.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    final accountsJson = prefs.getString(_prefAccountsDb) ?? '{}';
    try {
      final Map<String, dynamic> accounts = jsonDecode(accountsJson) as Map<String, dynamic>;
      for (var key in accounts.keys) {
        if (key.toLowerCase() == normalized) return true;
      }
    } catch (_) {}
    return false;
  }

  Future<AuthResult> signInWithVerifiedEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const AuthResult(
        success: false,
        message: 'Please provide a valid email.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final accountsJson = prefs.getString(_prefAccountsDb) ?? '{}';
    Map<String, dynamic> accounts = {};
    try {
      accounts = jsonDecode(accountsJson) as Map<String, dynamic>;
    } catch (_) {}

    Map<String, dynamic>? matchedAccount;
    for (var key in accounts.keys) {
      if (key.toLowerCase() == normalized) {
        matchedAccount = accounts[key] as Map<String, dynamic>?;
        break;
      }
    }

    if (matchedAccount == null) {
      return const AuthResult(
        success: false,
        message: 'No registered account found with this email. Please create an account.',
      );
    }

    final userData = matchedAccount['user'] as Map<String, dynamic>;
    final user = UserModel.fromJson(userData);

    _currentUser = user;
    await prefs.setBool(_prefIsLoggedIn, true);
    await prefs.setString(_prefCurrentUser, jsonEncode(user.toJson()));

    notifyListeners();
    return AuthResult(success: true, user: user);
  }

  Future<void> signOut() async {
    if (isRemote) return _remoteSignOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefCurrentUser);
    await prefs.setBool(_prefIsLoggedIn, false);

    _currentUser = null;
    notifyListeners();
  }

  Future<UserModel?> updateProfile({
    required String name,
    required String state,
    String? occupation,
    String? socialCategory,
  }) async {
    if (isRemote) {
      return _remoteUpdateProfile(name: name, state: state, occupation: occupation, socialCategory: socialCategory);
    }
    if (_currentUser == null) return null;

    final updated = _currentUser!.copyWith(
      name: name.trim().isNotEmpty ? name.trim() : _currentUser!.name,
      state: state.isNotEmpty ? state : _currentUser!.state,
      occupation: occupation ?? _currentUser!.occupation,
      socialCategory: socialCategory ?? _currentUser!.socialCategory,
    );

    _currentUser = updated;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCurrentUser, jsonEncode(updated.toJson()));

    // Update in accounts DB as well
    final accountsJson = prefs.getString(_prefAccountsDb) ?? '{}';
    final Map<String, dynamic> accounts = jsonDecode(accountsJson) as Map<String, dynamic>;
    final key = _currentUser!.phoneOrEmail.trim().toLowerCase();

    if (accounts.containsKey(key)) {
      final existing = accounts[key] as Map<String, dynamic>;
      existing['user'] = updated.toJson();
      accounts[key] = existing;
      await prefs.setString(_prefAccountsDb, jsonEncode(accounts));
    }

    notifyListeners();
    return _currentUser;
  }

  // ---------------------------------------------------------------------------------------------- OTP (both modes)

  /// Seconds until another code may be requested.
  int get resendSecondsLeft {
    if (!isRemote) return EmailOtpService.instance.resendSecondsLeft;
    final at = _otpRequestedAt;
    if (at == null) return 0;
    final left = _otpCooldown - DateTime.now().difference(at).inSeconds;
    return left > 0 ? left : 0;
  }

  /// Sends a 6-digit code. purpose: 'signup' or 'login'.
  Future<OtpResult> requestOtp({required String email, required String purpose, String? name}) async {
    final e = email.trim().toLowerCase();
    if (!isRemote) return EmailOtpService.instance.sendOtp(recipientEmail: e, recipientName: name);
    try {
      _otpCooldown = await _api!.requestOtp(e, purpose);
      _otpRequestedAt = DateTime.now();
      return const OtpResult(success: true, message: 'If this address can receive a code, we have sent one. Check your inbox.');
    } on AuthApiException catch (err) {
      return OtpResult(success: false, message: err.message);
    }
  }

  /// Verifies the code and completes sign-up or sign-in in one step.
  Future<AuthResult> completeOtp({
    required String email,
    required String code,
    required String purpose,
    String? name,
    String? password,
    String state = 'All India',
    String socialCategory = 'General',
    String occupation = 'Citizen',
  }) async {
    final e = email.trim().toLowerCase();
    if (!isRemote) {
      final v = EmailOtpService.instance.verifyOtp(enteredOtp: code);
      if (!v.success) return AuthResult(success: false, message: v.message);
      if (purpose == 'signup') {
        return signUp(
            name: name ?? 'Citizen', phoneOrEmail: e, password: password ?? '', state: state,
            socialCategory: socialCategory, occupation: occupation);
      }
      return signInWithVerifiedEmail(e);
    }
    if (purpose == 'signup') {
      return _remote(() => _api!.signup(
          email: e, code: code.trim(), password: password ?? '', name: (name ?? '').trim().isEmpty ? 'Citizen' : name!.trim(),
          state: state, socialCategory: socialCategory, occupation: occupation));
    }
    return _remote(() => _api!.loginWithOtp(e, code.trim()));
  }

  // ---------------------------------------------------------------------------------------------- tokens

  /// A valid access token for API calls (refreshed when close to expiry), or null when signed out / offline mode.
  Future<String?> accessToken() async {
    if (!isRemote || _refreshToken == null) return null;
    final exp = _accessExpiry;
    if (_accessToken != null && exp != null && exp.isAfter(DateTime.now().add(const Duration(seconds: 60)))) {
      return _accessToken;
    }
    return await _refreshSession() ? _accessToken : null;
  }

  Future<bool> _refreshSession() async {
    final rt = _refreshToken;
    if (rt == null) return false;
    try {
      await _applySession(await _api!.refresh(rt));
      return true;
    } on AuthApiException catch (e) {
      if (e.isUnauthorized) await _clearRemote(); // revoked / expired / reused: must sign in again
      return false;
    }
  }

  Future<void> _applySession(Map<String, dynamic> pair) async {
    _accessToken = pair['access_token'] as String;
    _accessExpiry = DateTime.now().add(Duration(seconds: (pair['expires_in'] as num?)?.toInt() ?? 900));
    _refreshToken = pair['refresh_token'] as String;
    await _tokens.writeRefreshToken(_refreshToken!);
    _currentUser = UserModel.fromServer(pair['user'] as Map<String, dynamic>);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefRemoteUser, jsonEncode(_currentUser!.toJson()));
    notifyListeners();
  }

  Future<AuthResult> _remote(Future<Map<String, dynamic>> Function() call) async {
    try {
      await _applySession(await call());
      return AuthResult(success: true, user: _currentUser);
    } on AuthApiException catch (e) {
      return AuthResult(success: false, message: e.message);
    }
  }

  Future<void> _remoteInit() async {
    _refreshToken = await _tokens.readRefreshToken();
    if (_refreshToken != null) {
      // show the cached profile immediately (works offline), then renew the session
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_prefRemoteUser);
      if (cached != null) {
        try {
          _currentUser = UserModel.fromJson(jsonDecode(cached) as Map<String, dynamic>);
        } catch (_) {
          _currentUser = null;
        }
      }
      await _refreshSession();
    }
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _clearRemote() async {
    _accessToken = null;
    _accessExpiry = null;
    _refreshToken = null;
    _currentUser = null;
    await _tokens.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefRemoteUser);
    notifyListeners();
  }

  Future<void> _remoteSignOut() async {
    final rt = _refreshToken;
    if (rt != null) {
      try {
        await _api!.logout(rt); // revoke server-side; ignore network failures
      } on AuthApiException catch (_) {}
    }
    await _clearRemote();
  }

  Future<UserModel?> _remoteUpdateProfile({required String name, required String state, String? occupation, String? socialCategory}) async {
    final token = await accessToken();
    if (token == null) return _currentUser;
    final changes = <String, dynamic>{'state': state};
    if (name.trim().isNotEmpty) changes['name'] = name.trim();
    if (occupation != null) changes['occupation'] = occupation;
    if (socialCategory != null) changes['socialCategory'] = socialCategory;
    try {
      _currentUser = UserModel.fromServer(await _api!.updateMe(token, changes));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefRemoteUser, jsonEncode(_currentUser!.toJson()));
      notifyListeners();
    } on AuthApiException catch (_) {}
    return _currentUser;
  }

  /// Permanently deletes the account (server-side in remote mode) and signs out.
  Future<AuthResult> deleteAccount() async {
    if (isRemote) {
      final token = await accessToken();
      if (token == null) return const AuthResult(success: false, message: 'Please sign in again.');
      try {
        await _api!.deleteMe(token);
      } on AuthApiException catch (e) {
        return AuthResult(success: false, message: e.message);
      }
      await _clearRemote();
      return const AuthResult(success: true);
    }
    final user = _currentUser;
    if (user == null) return const AuthResult(success: false, message: 'Not signed in.');
    final prefs = await SharedPreferences.getInstance();
    final accounts = jsonDecode(prefs.getString(_prefAccountsDb) ?? '{}') as Map<String, dynamic>;
    accounts.remove(user.phoneOrEmail.trim().toLowerCase());
    await prefs.setString(_prefAccountsDb, jsonEncode(accounts));
    await signOut();
    return const AuthResult(success: true);
  }
}
