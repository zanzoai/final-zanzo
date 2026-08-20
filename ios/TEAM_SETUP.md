# iOS Signing / Team Setup

This app's Xcode project uses **automatic signing**, so building for a real iPhone requires
`DEVELOPMENT_TEAM` to point at **your own** Apple Developer team — not whoever committed last.
If you see errors like `No Account for Team "XXXXXXXXXX"` or
`No profiles for 'com.yosrith.zanzouk' were found`, you haven't set your team yet.

> ✅ **Your team ID is never committed.** It lives in `ios/Flutter/Signing.xcconfig`, which is
> **gitignored**. The Xcode project (`project.pbxproj`) no longer hardcodes any team, so nobody's
> personal team leaks into git and nobody else's team breaks your build. Each developer just
> creates their own `Signing.xcconfig` once (step 2 below).

---

## 1. Find your Team ID

Add your Apple ID in **Xcode → Settings → Accounts** first (a free personal Apple ID works;
it produces a personal team whose provisioning profiles expire after ~7 days).

Then get your Team ID (the 10-char alphanumeric, shown as the certificate's `OU`):

```bash
security find-certificate -a -c "Apple Development" -p \
  | openssl x509 -noout -subject 2>/dev/null
# subject= .../CN=Apple Development: you@example.com (…)/OU=<YOUR_TEAM_ID>/O=Your Name/C=US
#                                                        ^^^^^^^^^^^^^^  <-- this is it
```

If nothing prints, you have no signing certificate yet — open the project in Xcode once
(`open ios/Runner.xcworkspace`), pick your team under **Runner → Signing & Capabilities**,
and let Xcode create the certificate, then re-run the command.

## 2. Set your Team ID (one-time, local)

Copy the committed template to the gitignored file and drop in your Team ID:

```bash
# from the project root (final-zanzo/)
cp ios/Flutter/Signing.xcconfig.example ios/Flutter/Signing.xcconfig
# then edit ios/Flutter/Signing.xcconfig and set:  DEVELOPMENT_TEAM = <YOUR_TEAM_ID>
```

That's it — `Signing.xcconfig` is included by `Debug.xcconfig` / `Release.xcconfig` /
`Profile.xcconfig` and gitignored, so your team applies to every build config and never gets
committed. The `project.pbxproj` intentionally has **no** `DEVELOPMENT_TEAM` anymore.

> If you set the Team via Xcode's **Signing & Capabilities** UI instead, Xcode will write
> `DEVELOPMENT_TEAM` back into `project.pbxproj` — don't commit that hunk; the xcconfig is the
> source of truth.

## 3. Bundle identifier

The committed bundle id is `com.yosrith.zanzouk`. With automatic signing, Xcode registers the
App ID under **your** team the first time you build, so you can usually keep it — and keeping it
means `GoogleService-Info.plist` (Firebase) still matches.

If your build fails to register the App ID (rare — happens when that exact id is already an
explicit App ID owned by another team), change `PRODUCT_BUNDLE_IDENTIFIER` in the project to
something unique (e.g. `com.<you>.zanzo`). Note: doing so breaks the Firebase config match, so
you'd also need a matching `GoogleService-Info.plist` for the new id, or expect Firebase to warn.

## 4. Build & install on a device

```bash
# from the project root (final-zanzo/)
flutter devices                                   # find your iPhone's UDID (wired or wireless)
flutter build ios --release                       # compiles + signs automatically
flutter install -d <DEVICE_UDID>                  # installs to the device
# verify:
xcrun devicectl device info apps --device <DEVICE_UDID> | grep zanzouk
```

First launch on the device: **Settings → General → VPN & Device Management → trust your
developer certificate**, then tap the app icon.

---

## Known iOS dependency pin (do not "fix" without reading this)

`pubspec.yaml` pins `google_mlkit_text_recognition: 0.13.1` **on purpose**. Version `0.14.0+`
pulls GoogleMLKit 7.0 (GoogleDataTransport ~10.0), which conflicts with
`firebase_messaging 14.7.10` → Firebase iOS SDK 10.x (GoogleDataTransport ~9.3). They cannot
coexist. Keeping the OCR plugin at 0.13.1 (GoogleMLKit 5.x) resolves it; the Dart OCR API is
identical. If you ever bump the ML Kit plugin, you must also upgrade the Firebase plugins to a
version on Firebase iOS SDK 11.x.

Related: the iOS deployment target is **15.5** (GoogleMLKit 5.x minimum) — set in `Podfile`
(`platform` + `post_install` override) and `project.pbxproj`. Don't lower it.
