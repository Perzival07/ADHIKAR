// Build-time configuration of the accounts backend (auth-service).
//
//   flutter run --dart-define=AUTH_API_URL=http://localhost:8006 --dart-define=RAG_API_URL=http://localhost:8000
//
// Without AUTH_API_URL the app keeps its offline demo accounts stored on the device.
class AuthConfig {
  static const String apiUrl = String.fromEnvironment('AUTH_API_URL');

  static bool get isRemote => apiUrl.trim().isNotEmpty;
}
