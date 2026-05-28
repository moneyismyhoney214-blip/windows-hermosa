# CLAUDE.md — hermosa_pos

Guidance for Claude Code when working in this repository.

## What this app is

A Flutter cashier / POS app shipped as **hermosa_pos** (`pubspec.yaml`
version 1.0.5+26). Targets Android (Sunmi devices in production), iOS
(iPad in App Store), and Windows desktop. Talks to the Hermosa
backend at `portal.hermosaapp.com` and integrates the **NearPay** card
terminal SDK (`vendor/flutter_terminal_sdk`).

Two business modules co-exist behind one binary:
- **salons** — appointment-based services, sessions, deposits.
- **restaurants** — table service, waiter mesh, kitchen tickets.

Which module is active is controlled by `ApiConstants.branchModule`
(set from the login response).

## Top-level layout

```
lib/
  main.dart                     boot, runZonedGuarded, error wiring
  locator.dart                  GetIt registrations (single DI graph)
  services/
    api/                        every backend call (BaseClient + per-resource services)
    security/                   cert pinning, secure token store
    observability/              crash_reporter (file-backed by default)
    offline/                    connectivity_service, sync_service, sqflite migrations
  controllers/                  cart, payment_logic, order_totals_calculator (testable, no UI)
  dialogs/                      per-action modals (booking, refund, deposit, …)
  screens/                      top-level routes (main, reports, tables, …)
  customer_display/             secondary screen + NearPay integration
  waiter_module/                LAN-mesh-connected waiter app (in-scope for edits)
  models.dart / models.g.dart   shared DTOs (json_serializable)
  widgets/                      reusable widgets, settings tabs, panels
integration_test/               2 files — performance + 1 happy-path stub
test/                           controllers, security, logger (real assertions)
android/ ios/ linux/ macos/     platform projects (Android + iOS active; others scaffolding)
codemagic.yaml                  CI/CD for Windows + iOS (App Store / TestFlight upload)
```

## Hard constraints (DO NOT VIOLATE)

1. **Never modify printing / receipt code** without explicit user
   permission. Anything under `lib/services/receipt_builder_service.dart`,
   `lib/services/invoice_html_pdf_service.dart`, `lib/widgets/print_listener.dart`,
   or the `*_print_dispatcher.dart` files. Receipts are revenue-critical
   and have been a recurring source of breakage.
2. **Default scope is the salon module** plus `lib/waiter_module/**`
   and the cashier tables-section waiter plumbing. Other restaurant
   code is off-limits unless the user explicitly approves the change.
3. **ReceiptBuilderService is the single source of truth** for cashier
   and waiter receipts. Don't fork logic into a mixin or dispatcher —
   add it once in `receipt_builder_service.dart` and consume it from
   both paths.
4. **Employees-income chip is salon-only** — the Reports screen must
   gate `employeesIncome` behind `branchModule == 'salons'`.

## How to run locally

```bash
flutter pub get
flutter run                                # primary cashier display
flutter run -t lib/customer_display/customer_display_main.dart  # secondary
```

For hardened builds (recommended for production):

```bash
flutter build apk --release \
  --dart-define=CERT_PINNING_ENFORCE=true \
  --dart-define=MESH_AUTH_PEPPER=<32-byte-hex> \
  --dart-define=API_BASE_URL=https://portal.hermosaapp.com
```

Without `MESH_AUTH_PEPPER`, the waiter mesh falls back to a known dev
pepper that's safe for local dev but **not** for production fleets.

## Tests

```bash
flutter test                               # unit + widget tests
flutter test integration_test/             # device-bound tests (needs emulator)
flutter analyze                            # lint (info-level only — CI passes)
```

CI (`codemagic.yaml`) runs `flutter analyze` then `flutter test` before
every iOS + Windows build. **A failing test blocks the upload to
TestFlight / Windows release.** Don't disable these steps to "unblock"
a release — fix the test.

## Observability

- All errors flow through `Log.e(tag, msg, error:, stackTrace:)` →
  `CrashReporter.instance.report(...)`. Default reporter is
  `FileCrashReporter` which appends JSON-line crash events to
  `<app-docs>/crash_reports/crashes.log` with size-based rotation.
- `Log.sanitize()` redacts JWTs, bearer tokens, PANs, and emails. Use
  it before logging any payload you didn't construct yourself.
- For multi-sink reporting (local file + remote), wrap reporters in
  `CompositeCrashReporter`. An HTTP uploader is included
  (`HttpCrashReporter`) if you want crash telemetry without a vendor
  SDK.

### Activating Sentry

`sentry_flutter` is already a dependency and
`lib/services/observability/sentry_crash_reporter.dart` is wired into
`main.dart`. **The adapter only activates when a DSN is provided at
build time** — default builds keep the existing FileCrashReporter
behaviour, so adding the dep didn't change the runtime.

To enable Sentry for a release build:

```bash
flutter build apk --release \
  --dart-define=SENTRY_DSN=https://<key>@sentry.io/<project> \
  --dart-define=SENTRY_RELEASE=$CI_BUILD_NUMBER \
  --dart-define=SENTRY_ENVIRONMENT=production
```

When `SENTRY_DSN` is non-empty, `SentryCrashReporter.bootstrap`
installs a `CompositeCrashReporter([FileCrashReporter, SentryCrashReporter])`
so crash events fan out to BOTH the local rolling log AND Sentry.

For the `SentryFlutter.init` zone-based capture (catches uncaught
Dart errors before they reach our `runZonedGuarded`), wrap `runApp`
in `SentryFlutter.init(... appRunner: () => runApp(...))`. The adapter
already swapped the global reporter before `runApp` runs, so synchronous
`Log.e` calls also reach Sentry.

Codemagic should set the DSN via a secure env var → dart-define mapping
in the iOS / Windows / Android workflow `vars:` block.

## Security

- Auth tokens live in `flutter_secure_storage` via `SecureTokenStore`
  (legacy SharedPreferences entries are migrated on first read).
- Network: HTTPS-only to the public internet (Android
  `network_security_config.xml`). Plain ws:// is allowed ONLY to
  RFC1918 ranges for the waiter mesh.
- TLS pinning is wired through `PinningHttpClient` on every API call.
  Default builds run in **detect-only** mode (mismatch is logged but
  request is allowed). Builds compiled with
  `--dart-define=CERT_PINNING_ENFORCE=true` fail closed.
- Mesh-auth pepper is `--dart-define`-injected at build time.

## Versioning + releases

- `pubspec.yaml` version is the marketing version (`1.0.5`); build
  number is set by Codemagic's `$PROJECT_BUILD_NUMBER` for iOS.
- Don't amend published commits or force-push `main`.
- iOS release flow: push to `main` → Codemagic ios-workflow → IPA →
  TestFlight (5-30 min processing). Promotion to App Store is manual
  via App Store Connect.

## Style

- Lint config in `analysis_options.yaml` is pragmatic, not strict.
  Real issues (`avoid_print`, `use_build_context_synchronously`,
  `unawaited_futures`) are warnings; stylistic preferences are info.
- No TODOs in committed code — track work in the issue tracker.
- New code MUST go through `BaseClient` for HTTP calls. Don't add
  raw `http.get/post` calls in screens or dialogs (the one existing
  exception in `legal_page_screen.dart` is grandfathered).
