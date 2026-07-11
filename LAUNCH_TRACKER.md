# Zanzo — Google Play Launch Tracker

Track Play Store readiness work. Check off items as they are completed.

---

## FRONTEND CODE — PHASE 1

### Android application identity
- [x] Rename `namespace` in `android/app/build.gradle.kts` → `ai.zanzo.app`
- [x] Rename `applicationId` in `android/app/build.gradle.kts` → `ai.zanzo.app`
- [x] Update `package` attribute in `android/app/src/main/AndroidManifest.xml` → `ai.zanzo.app`
- [x] Move `MainActivity.kt` to `android/app/src/main/kotlin/ai/zanzo/app/`
- [x] Update `package` declaration in `MainActivity.kt` → `ai.zanzo.app`
- [ ] Firebase config replacement (Yosrith — manual, see below)

### Release signing configuration
- [x] Create `android/key.properties.template` with placeholder fields
- [x] Confirm `android/key.properties`, `*.jks`, `*.keystore` are git-ignored
- [x] Update `build.gradle.kts` to load release signing from `android/key.properties`
- [x] Release builds never fall back to debug signing
- [x] Missing/incomplete `key.properties` produces a clear Gradle error
- [x] Debug builds are unaffected when `key.properties` is absent
- [ ] Keystore generated and `android/key.properties` created (Yosrith — manual, see below)

### Signed AAB verification
- [ ] Release AAB built successfully with production signing (Yosrith — after keystore setup)
- [ ] AAB uploaded to Play Console (internal or closed testing track)

---

## MANUAL — YOSRITH

### Generate and securely back up upload keystore

Run **once** on your machine. Store the keystore outside the git repository.

```bash
keytool -genkey -v \
  -keystore ~/keys/zanzo-upload.jks \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias zanzo-upload \
  -dname "CN=Zanzo AI Ltd, OU=Mobile, O=Zanzo AI Ltd, L=London, ST=England, C=GB"
```

You will be prompted for a store password and a key password. Use strong, unique passwords.
Save **both passwords** and the `.jks` file path in a password manager immediately.

> **Warning:** Loss of this keystore permanently prevents future Play Store updates.
> Back it up in at least two secure locations.

### Create `android/key.properties` from template

```bash
cp android/key.properties.template android/key.properties
```

Then edit `android/key.properties` and fill in all four fields:

```
storePassword=<store-password>
keyPassword=<key-password>
keyAlias=zanzo-upload
storeFile=/Users/yosrith/keys/zanzo-upload.jks
```

`android/key.properties` is git-ignored and must never be committed.

### Register `ai.zanzo.app` in Firebase project `zanzo-uk-mvp`

1. Open [Firebase Console](https://console.firebase.google.com) → project `zanzo-uk-mvp`
2. Project settings → Your apps → Add app → Android
3. Android package name: `ai.zanzo.app`
4. App nickname: `Zanzo Android`
5. Download the generated `google-services.json`
6. Replace `android/app/google-services.json` with the downloaded file
7. The SHA-1 certificate fingerprint for the upload keystore can be added later (required for Google Sign-In, optional for FCM)

### Download and replace `android/app/google-services.json`

Replace the existing file (which still has `com.example.zanzo`) with the one downloaded above.
Do not commit the old file. Commit only after verifying the app starts and FCM works.

### Verify Google Maps API key restrictions for `ai.zanzo.app`

1. Open [Google Cloud Console](https://console.cloud.google.com) → APIs & Services → Credentials
2. Find the Maps SDK key used in `lib/core/widgets/location_selector.dart`
3. Under "Application restrictions → Android apps", add `ai.zanzo.app` as an allowed package
4. Remove or keep `com.example.zanzo` depending on whether the old ID is still needed for any build

### Physically test Android startup, OTP, FCM and Stripe test payment

After completing the steps above, test the following on a physical Android device:

- [ ] App starts without crash (Firebase init, Stripe init, Supabase init)
- [ ] Phone OTP login completes
- [ ] Home screen loads correctly
- [ ] Push notification received (FCM — requires new `google-services.json`)
- [ ] Customer task request submitted
- [ ] Stripe test payment processed end-to-end (use Stripe test card `4242 4242 4242 4242`)
- [ ] Location picker works (Maps API key active for new package name)

### Build signed release AAB

```bash
flutter build appbundle --release
```

Verify the output at `build/app/outputs/bundle/release/app-release.aab`.
Upload to Play Console → closed testing track.

---

## PHASE 2 ITEMS (before public production)

These are tracked here for visibility but are not part of Phase 1.

- [ ] Switch `api_service.dart` `baseUrl` to the production Railway backend
- [ ] Implement `--dart-define=BASE_URL=...` or `AppConfig` for environment switching
- [ ] Switch Stripe to live keys (`pk_live_...` frontend, `sk_live_...` Railway)
- [ ] Fix `STRIPE_WEBHOOK_SECRET` in Railway to correct `whsec_...` format
- [ ] Set `DEBUG=false` and `ENVIRONMENT=production` in Railway production environment
- [ ] Publish privacy policy to a public URL (e.g. `https://zanzo.ai/privacy`)
- [ ] Update Play Console Data Safety form with public privacy policy URL
- [ ] Set `Supabase.initialize(debug: kDebugMode)` in `main.dart`
- [ ] Remove unconditional `print()` calls in `api_service.dart`
- [ ] Enable `isShrinkResources = true` in `build.gradle.kts`
- [ ] Upgrade `firebase_core` / `firebase_messaging` to 4.x / 16.x
- [ ] Move Stripe publishable key and Google Maps key to `--dart-define`
- [ ] Remove "pilot/testing version" language from `TermsScreen`
- [ ] Define account deletion SLA in Privacy Policy
- [ ] Add Play Store reviewer test credentials to Play Console listing
- [ ] Upgrade `flutter_stripe` to 13.x; evaluate Google Pay integration
- [ ] Prepare Play Store screenshots (minimum 2 per form factor)
- [ ] Verify 16 KB page alignment for native `.so` files
