/// Build-time product capabilities.
///
/// Diabetes support is intentionally opt-in. Enable it with
/// `--dart-define=DIABETES_ENABLED=true` for a diabetes-focused build.
abstract final class AppFeatures {
  static const bool diabetesEnabled = bool.fromEnvironment(
    'DIABETES_ENABLED',
    defaultValue: false,
  );
}
