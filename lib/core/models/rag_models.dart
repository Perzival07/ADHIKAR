// Typed models for the recommendation-service API (backend/contracts/openapi/recommendation-service.yaml).

class RagCitation {
  final String chunkId;
  final String quote;
  final String section;
  final String url;

  const RagCitation({required this.chunkId, this.quote = '', this.section = '', this.url = ''});

  factory RagCitation.fromJson(Map<String, dynamic> j) => RagCitation(
        chunkId: j['chunk_id'] as String,
        quote: (j['quote'] as String?) ?? '',
        section: (j['section'] as String?) ?? '',
        url: (j['url'] as String?) ?? '',
      );
}

class RagRecommendation {
  final String schemeId;
  final String name;
  final int rank;
  final double confidence;
  final String reason;
  final String reasonLanguage;
  final List<RagCitation> citations;
  final List<String> missingInfo;

  /// "eligible" or "unknown" (rules could not decide; the user may need to provide more information).
  final String eligibilityStatus;

  const RagRecommendation({
    required this.schemeId,
    this.name = '',
    required this.rank,
    required this.confidence,
    required this.reason,
    this.reasonLanguage = 'en',
    this.citations = const [],
    this.missingInfo = const [],
    this.eligibilityStatus = 'eligible',
  });

  factory RagRecommendation.fromJson(Map<String, dynamic> j) => RagRecommendation(
        schemeId: j['scheme_id'] as String,
        name: (j['name'] as String?) ?? '',
        rank: (j['rank'] as num).toInt(),
        confidence: (j['confidence'] as num).toDouble(),
        reason: (j['reason'] as String?) ?? '',
        reasonLanguage: (j['reason_language'] as String?) ?? 'en',
        citations: ((j['citations'] as List?) ?? const [])
            .map((c) => RagCitation.fromJson(c as Map<String, dynamic>))
            .toList(),
        missingInfo: ((j['missing_info'] as List?) ?? const []).map((e) => e.toString()).toList(),
        eligibilityStatus: (j['eligibility_status'] as String?) ?? 'eligible',
      );
}

class RagResponse {
  final List<RagRecommendation> recommendations;
  final List<RagRecommendation> more;

  /// "rag" (LLM-assisted) or "rules_only" (server fell back to rules).
  final String mode;
  final String traceId;
  final String? fallbackReason;

  const RagResponse({
    required this.recommendations,
    this.more = const [],
    required this.mode,
    this.traceId = '',
    this.fallbackReason,
  });

  bool get isAi => mode == 'rag';

  factory RagResponse.fromJson(Map<String, dynamic> j) {
    List<RagRecommendation> list(String k) =>
        ((j[k] as List?) ?? const []).map((e) => RagRecommendation.fromJson(e as Map<String, dynamic>)).toList();
    return RagResponse(
      recommendations: list('recommendations'),
      more: list('more'),
      mode: (j['mode'] as String?) ?? 'rules_only',
      traceId: (j['trace_id'] as String?) ?? '',
      fallbackReason: j['fallback_reason'] as String?,
    );
  }
}
