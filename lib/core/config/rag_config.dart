/// Build-time configuration of the optional AI (RAG) backend.
///
///   flutter run -d chrome --dart-define=RAG_API_URL=http://localhost:8000
///   flutter run --dart-define=RAG_API_URL=http://10.0.2.2:8000     (Android emulator -> host machine)
///
/// No host is hard-coded. Without RAG_API_URL the app is purely rule-based and offline.
class RagConfig {
  static const String apiUrl = String.fromEnvironment('RAG_API_URL');

  static bool get isConfigured => apiUrl.trim().isNotEmpty;
}
