class ApiConfig {
  ApiConfig._();

  /// Base URL for the API.
  ///
  /// Override per build without editing code, e.g.:
  /// `flutter run --dart-define=API_BASE_URL=https://api.Rivalink.et/api`
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://unpossessively-pseudonational-shawnta.ngrok-free.dev/api',
  );

  static const Duration httpTimeout = Duration(seconds: 30);
}
