/// Compile-time environment configuration.
///
/// Values are injected at build time via `--dart-define`:
/// ```bash
/// flutter run --dart-define=SENTRY_DSN=https://...
/// flutter run --dart-define=USE_MOCK=true
/// ```
class EnvConfig {
  EnvConfig._();

  /// Sentry DSN for crash reporting. Empty string = not configured.
  static const String sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: '',
  );

  /// Whether Sentry is configured (DSN was provided at build time).
  static bool get isSentryConfigured => sentryDsn.isNotEmpty;

  /// Whether to use mock datasources (development mode).
  static const bool useMockDatasources = bool.fromEnvironment(
    'USE_MOCK',
    defaultValue: false,
  );
}
