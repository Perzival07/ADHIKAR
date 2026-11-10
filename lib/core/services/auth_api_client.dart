import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/auth_config.dart';

class AuthApiException implements Exception {
  final int statusCode;
  final String message;
  final int? retryAfter;
  const AuthApiException(this.statusCode, this.message, {this.retryAfter});

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'AuthApiException($statusCode, $message)';
}

/// HTTP client for backend/services/auth-service (contract: backend/contracts/openapi/auth-service.yaml).
class AuthApiClient {
  final String baseUrl;
  final Duration timeout;
  final http.Client _http;

  AuthApiClient({String? baseUrl, http.Client? client, this.timeout = const Duration(seconds: 20)})
      : baseUrl = (baseUrl ?? AuthConfig.apiUrl).trim().replaceAll(RegExp(r'/+$'), ''),
        _http = client ?? http.Client();

  Future<Map<String, dynamic>?> _send(String method, String path, {Object? body, String? bearer}) async {
    final headers = <String, String>{'content-type': 'application/json'};
    if (bearer != null) headers['authorization'] = 'Bearer $bearer';
    final uri = Uri.parse('$baseUrl$path');
    final http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } on TimeoutException {
      throw const AuthApiException(0, 'The server took too long to respond. Please try again.');
    } catch (_) {
      throw const AuthApiException(0, 'Could not reach the server. Check your internet connection.');
    }
    if (res.statusCode == 204) return null;
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) data = decoded;
    } on FormatException {
      data = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data ?? <String, dynamic>{};
    final detail = data?['detail'];
    final message = detail is String ? detail : 'Request failed (${res.statusCode}).';
    throw AuthApiException(res.statusCode, message, retryAfter: int.tryParse(res.headers['retry-after'] ?? ''));
  }

  /// Returns seconds until another code may be requested.
  Future<int> requestOtp(String email, String purpose) async {
    final d = await _send('POST', '/v1/auth/otp/request', body: {'email': email, 'purpose': purpose});
    return (d?['resend_after'] as num?)?.toInt() ?? 60;
  }

  Future<Map<String, dynamic>> signup({
    required String email,
    required String code,
    required String password,
    required String name,
    required String state,
    required String socialCategory,
    required String occupation,
  }) async =>
      (await _send('POST', '/v1/auth/signup', body: {
        'email': email,
        'code': code,
        'password': password,
        'name': name,
        'state': state,
        'socialCategory': socialCategory,
        'occupation': occupation,
      }))!;

  Future<Map<String, dynamic>> login(String identifier, String password) async =>
      (await _send('POST', '/v1/auth/login', body: {'identifier': identifier, 'password': password}))!;

  Future<Map<String, dynamic>> loginWithOtp(String email, String code) async =>
      (await _send('POST', '/v1/auth/login/otp', body: {'email': email, 'code': code}))!;

  Future<Map<String, dynamic>> refresh(String refreshToken) async =>
      (await _send('POST', '/v1/auth/token/refresh', body: {'refresh_token': refreshToken}))!;

  Future<void> logout(String refreshToken) => _send('POST', '/v1/auth/logout', body: {'refresh_token': refreshToken});

  Future<Map<String, dynamic>> me(String accessToken) async => (await _send('GET', '/v1/users/me', bearer: accessToken))!;

  Future<Map<String, dynamic>> updateMe(String accessToken, Map<String, dynamic> changes) async =>
      (await _send('PATCH', '/v1/users/me', body: changes, bearer: accessToken))!;

  Future<void> deleteMe(String accessToken) => _send('DELETE', '/v1/users/me', bearer: accessToken);
}
