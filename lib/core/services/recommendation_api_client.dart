import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/rag_config.dart';
import '../models/citizen_profile.dart';
import '../models/rag_models.dart';

class RecommendationApiException implements Exception {
  final String message;
  final int? statusCode;
  const RecommendationApiException(this.message, {this.statusCode});

  @override
  String toString() => 'RecommendationApiException($message${statusCode != null ? ', HTTP $statusCode' : ''})';
}

/// Talks to backend/services/recommendation-service.
///
/// Privacy: the request body is exactly [CitizenProfile.toJson] (state, age, occupation, income band ...).
/// Name, phone and email are never part of the profile and are never sent.
class RecommendationApiClient {
  final String baseUrl;
  final Duration timeout;
  final http.Client _http;

  /// Returns the signed-in user's access token (or null when anonymous). Sent as a Bearer token so the
  /// backend can apply per-account limits; anonymous use still works when the server allows it.
  final Future<String?> Function()? accessToken;

  RecommendationApiClient({String? baseUrl, http.Client? client, this.timeout = const Duration(seconds: 25), this.accessToken})
      : baseUrl = (baseUrl ?? RagConfig.apiUrl).trim().replaceAll(RegExp(r'/+$'), ''),
        _http = client ?? http.Client();

  bool get isConfigured => baseUrl.isNotEmpty;

  static String newRequestId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<RagResponse> recommend(CitizenProfile profile, {String language = 'en', int topN = 8}) async {
    if (!isConfigured) throw const RecommendationApiException('RAG_API_URL is not configured');
    final body = jsonEncode({
      'profile': profile.toJson(),
      'language': language,
      'top_n': topN,
      'include_citations': true,
    });
    final headers = {'content-type': 'application/json', 'X-Request-ID': newRequestId()};
    try {
      final token = accessToken == null ? null : await accessToken!();
      if (token != null) headers['authorization'] = 'Bearer $token';
      final res = await _http
          .post(Uri.parse('$baseUrl/v1/recommendations'), headers: headers, body: body)
          .timeout(timeout);
      if (res.statusCode != 200) {
        throw RecommendationApiException('unexpected response', statusCode: res.statusCode);
      }
      return RagResponse.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
    } on RecommendationApiException {
      rethrow;
    } on TimeoutException {
      throw const RecommendationApiException('request timed out');
    } on FormatException catch (e) {
      throw RecommendationApiException('malformed response: ${e.message}');
    } on TypeError catch (e) {
      throw RecommendationApiException('unexpected response shape: $e');
    } catch (e) {
      // network errors (SocketException, ClientException, CORS failures on web ...)
      throw RecommendationApiException('network error: ${e.runtimeType}');
    }
  }

  void close() => _http.close();
}
