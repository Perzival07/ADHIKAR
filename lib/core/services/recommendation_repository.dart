import '../models/citizen_profile.dart';
import '../models/rag_models.dart';
import '../models/scheme_model.dart';
import '../../data/schemes_corpus.dart';
import 'recommendation_api_client.dart';
import 'scheme_engine.dart';

enum RecommendationMode { aiAssisted, ruleBased }

/// AI-written details for one scheme (only present for AI-assisted results).
class AiExtras {
  final String reason;
  final String reasonLanguage;
  final List<RagCitation> citations;
  final List<String> missingInfo;
  final bool needsMoreInfo; // server says eligibility is "unknown"
  final double confidence;

  const AiExtras({
    required this.reason,
    required this.reasonLanguage,
    this.citations = const [],
    this.missingInfo = const [],
    this.needsMoreInfo = false,
    this.confidence = 0,
  });
}

class RecommendationResult {
  final List<SchemeModel> schemes;
  final RecommendationMode mode;
  final Map<String, AiExtras> extras;

  /// Why the result is rule-based although AI was requested (null when AI was not requested).
  final String? fallbackReason;

  const RecommendationResult({
    required this.schemes,
    required this.mode,
    this.extras = const {},
    this.fallbackReason,
  });

  bool get isAi => mode == RecommendationMode.aiAssisted;
}

/// Tries the AI (RAG) backend and always falls back to the on-device [SchemeEngine].
///
/// Rules still decide eligibility; the backend only adds ranking, explanations and sources.
/// A scheme id the server returns that does not exist in the local corpus is ignored.
class RecommendationRepository {
  final RecommendationApiClient? api;
  final List<SchemeModel> Function() _corpus;
  final List<SchemeModel> Function(CitizenProfile) _local;

  RecommendationRepository({
    this.api,
    List<SchemeModel> Function()? corpus,
    List<SchemeModel> Function(CitizenProfile)? localEngine,
  })  : _corpus = corpus ?? SchemesCorpus.getSchemes,
        _local = localEngine ?? SchemeEngine.evaluate;

  /// Instant, offline, rule-based result.
  RecommendationResult local(CitizenProfile profile, {String? fallbackReason}) => RecommendationResult(
        schemes: _local(profile),
        mode: RecommendationMode.ruleBased,
        fallbackReason: fallbackReason,
      );

  Future<RecommendationResult> recommend(CitizenProfile profile, {required String language, required bool aiEnabled}) async {
    final localResult = local(profile);
    final client = api;
    if (!aiEnabled || client == null || !client.isConfigured) return localResult;

    final RagResponse resp;
    try {
      resp = await client.recommend(profile, language: language);
    } on RecommendationApiException catch (e) {
      return local(profile, fallbackReason: e.message);
    }
    if (!resp.isAi) return local(profile, fallbackReason: resp.fallbackReason ?? 'rules_only');

    final byId = {for (final s in _corpus()) s.id: s};
    final ordered = <SchemeModel>[];
    final extras = <String, AiExtras>{};
    final seen = <String>{};

    for (final r in resp.recommendations) {
      final scheme = byId[r.schemeId]; // unknown ids (hallucinations) are ignored
      if (scheme == null || !seen.add(r.schemeId) || r.reason.trim().isEmpty) continue;
      ordered.add(scheme);
      extras[r.schemeId] = AiExtras(
        reason: r.reason.trim(),
        reasonLanguage: r.reasonLanguage,
        citations: r.citations,
        missingInfo: r.missingInfo,
        needsMoreInfo: r.eligibilityStatus == 'unknown',
        confidence: r.confidence,
      );
    }
    if (ordered.isEmpty) return local(profile, fallbackReason: 'no_valid_ai_items');

    // Never lose a scheme the on-device rules found: append what the AI list did not mention.
    for (final s in localResult.schemes) {
      if (seen.add(s.id)) ordered.add(s);
    }
    return RecommendationResult(schemes: ordered, mode: RecommendationMode.aiAssisted, extras: extras);
  }
}
