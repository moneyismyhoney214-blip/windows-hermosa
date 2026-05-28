# Hermosa POS

Cross-platform cashier / point-of-sale app for the Hermosa platform.
Flutter-based, ships on Android (Sunmi terminals), iOS (iPad), and
Windows desktop. Integrates the NearPay card-terminal SDK and prints
to network / Bluetooth / Sunmi built-in thermal printers.

## Quick start

```bash
flutter pub get
flutter run
```

Login uses your Hermosa seller credentials. Module is selected by the
branch you log into (`salons` vs `restaurants`).

## Building for release

### Android

```bash
flutter build apk --release
```

Signing config is in `android/app/build.gradle.kts`. Credentials come
from `key.properties` (local) or Codemagic env vars (CI). The build
falls back to debug signing with a loud warning if no keystore is
configured — never ship that fallback.

### iOS (TestFlight via Codemagic)

Push to `main`. The ios-workflow in `codemagic.yaml` will:

1. Run `flutter analyze` and `flutter test` — fails the build on any test failure.
2. Fetch (or create) the App Store distribution cert via the
   `IOS_DIST_PRIVATE_KEY` secure env var.
3. Build `flutter build ipa --release` with auto-incremented build
   number from `$PROJECT_BUILD_NUMBER`.
4. Upload to App Store Connect → TestFlight.

Required Codemagic secrets:
- `IOS_DIST_PRIVATE_KEY` — PEM-format private key for the Distribution cert.
- `APP_STORE_APPLE_ID` — numeric Apple ID of the app.
- `DEVELOPER_CERT_PEM` (optional) — NearPay developer cert.
- `MESH_AUTH_PEPPER` (recommended) — 32+ random hex chars; injected
  as `--dart-define` so the waiter mesh HMAC isn't a known constant.

### Windows

```bash
flutter build windows --release
```

Codemagic windows-workflow packages the output as `hermosa-windows.zip`.

## Hardened builds

For production fleets, compile with the security hardening flags
turned on:

```bash
flutter build apk --release \
  --dart-define=CERT_PINNING_ENFORCE=true \
  --dart-define=MESH_AUTH_PEPPER=<random-32-byte-hex> \
  --dart-define=API_BASE_URL=https://portal.hermosaapp.com
```

| Flag | Default | Purpose |
| --- | --- | --- |
| `CERT_PINNING_ENFORCE` | `false` | Fail closed on TLS pin mismatch. Default is detect-only so a stale pin can't brick the fleet. |
| `MESH_AUTH_PEPPER` | dev-only constant | HMAC pepper for the waiter LAN mesh. Use a unique value per release. |
| `API_BASE_URL` | `https://portal.hermosaapp.com` | Override for staging / sandbox. |
| `AUTH_BASE_URL` | inherits `API_BASE_URL` | Auth host (forgot-password etc.) |

## Tests

```bash
flutter test                       # unit + widget tests
flutter test integration_test/     # device-bound (emulator required)
flutter analyze                    # lint (info-level only)
```

The CI gate (`codemagic.yaml`) blocks any build with failing tests
or analyzer errors. Don't merge to `main` with red tests.

## Architecture (one-paragraph version)

`main.dart` boots inside `runZonedGuarded`, wires `FlutterError.onError`
+ `PlatformDispatcher.onError` → `Log.e` → `CrashReporter`. `setupLocator`
(`lib/locator.dart`) registers ~50 services in GetIt. All HTTP goes
through `BaseClient` which uses a TLS-pinning `IOClient` wrapper.
Receipts (cashier + waiter) flow through one `ReceiptBuilderService`.
Offline writes queue into `OfflineDatabaseService.sync_queue` and are
drained by `SyncService` on reconnect. Errors are persisted to
`<docs>/crash_reports/crashes.log` by `FileCrashReporter`.

## Repository layout

See `CLAUDE.md` for the directory map and contributing constraints
(scope rules, do-not-touch areas, conventions).

## Support

Email: `support@hermosaapp.com`
