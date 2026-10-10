# Build configuration

The app reads its environment at build time (`lib/core/config/app_config.dart`).
No keys are stored in source: every run and build must pass a config file, and the
app stops at launch with a clear error if a required key is missing.

All `config/*.json` files are git-ignored except the `*.example.json` templates.

## Local development

1. `cp config/test.example.json config/test.json` and fill in the test keys
   (ask the team for the values).
2. Run with it:

   ```bash
   flutter run --dart-define-from-file=config/test.json
   ```

| Key | What |
|---|---|
| `API_BASE_URL` | Backend URL including `/api/v1` (defaults to the test API) |
| `STRIPE_PUBLISHABLE_KEY` | `pk_test_…` or `pk_live_…` |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Supabase project for realtime updates and legacy chat images |
| `GOOGLE_MAPS_KEY` | Places autocomplete key |

## Production build

1. `cp config/prod.example.json config/prod.json` and fill it in.
2. Build with it:

   ```bash
   flutter build appbundle --release --dart-define-from-file=config/prod.json
   flutter build ipa --release --dart-define-from-file=config/prod.json
   ```

Only publishable/public keys belong here — they are compiled into the app and
can be read by anyone who has it. Never put a Stripe secret key, service-role
key or database password in these files.
