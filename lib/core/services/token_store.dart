import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the long-lived refresh token lives. Access tokens are short-lived and kept in memory only.
abstract class TokenStore {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String token);
  Future<void> clear();
}

/// iOS Keychain / Android Keystore-backed storage (encrypted at rest).
class SecureTokenStore implements TokenStore {
  static const _key = 'adhikar_refresh_token';
  final FlutterSecureStorage _storage;

  SecureTokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _key);

  @override
  Future<void> writeRefreshToken(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// For tests.
class MemoryTokenStore implements TokenStore {
  String? token;

  @override
  Future<String?> readRefreshToken() async => token;

  @override
  Future<void> writeRefreshToken(String t) async => token = t;

  @override
  Future<void> clear() async => token = null;
}
