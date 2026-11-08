// lib/core/config/app_config.dart
//
// Build-time configuration. Every value can be set when building, e.g.
//
//   flutter run   --dart-define-from-file=config/prod.json
//   flutter build appbundle --release --dart-define-from-file=config/prod.json
//
// No keys live in source: they come from a git-ignored config file, e.g.
//
//   flutter run --dart-define-from-file=config/test.json
//
// The app refuses to start if a required key is missing. See config/README.md.

class AppConfig {
  AppConfig._();

  /// Backend base URL, including the /api/v1 prefix.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api-test.zanzo.ai/api/v1',
  );

  /// Stripe publishable key (pk_test_… or pk_live_…). Publishable keys are
  /// meant to ship inside client apps; secret keys never are.
  static const String stripePublishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
  );

  /// Supabase project (public anon key): realtime updates and legacy chat images.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Google Maps Platform key for Places autocomplete. Restrict it to this
  /// app's bundle ids and the Places API in Google Cloud.
  static const String googleMapsKey = String.fromEnvironment('GOOGLE_MAPS_KEY');

  /// Names of required keys that were not provided at build time.
  static List<String> get missingKeys => [
    if (stripePublishableKey.isEmpty) 'STRIPE_PUBLISHABLE_KEY',
    if (supabaseUrl.isEmpty) 'SUPABASE_URL',
    if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
    if (googleMapsKey.isEmpty) 'GOOGLE_MAPS_KEY',
  ];

  /// True when built against Stripe test mode.
  static bool get isStripeTestMode =>
      stripePublishableKey.startsWith('pk_test_');
}
