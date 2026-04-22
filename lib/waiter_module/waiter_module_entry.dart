import 'dart:async';

import 'package:flutter/material.dart';

import '../locator.dart';
import '../services/api/api_constants.dart';
import '../services/api/auth_service.dart';
import '../services/language_service.dart';
import 'screens/waiter_home_screen.dart';
import 'services/waiter_billing_service.dart';
import 'services/waiter_config_store.dart';
import 'services/waiter_controller.dart';
import 'services/waiter_order_outbox.dart';
import 'services/waiter_session_service.dart';

/// Single entry point for the waiter module.
///
/// Usage:
/// ```dart
/// Navigator.of(context).push(
///   MaterialPageRoute(builder: (_) => const WaiterModuleEntry()),
/// );
/// ```
///
/// Handles session hydration, outbox bootstrapping, and picks between the
/// login screen and the home screen depending on whether the waiter has
/// already signed in on this device.
class WaiterModuleEntry extends StatefulWidget {
  const WaiterModuleEntry({super.key});

  @override
  State<WaiterModuleEntry> createState() => _WaiterModuleEntryState();
}

class _WaiterModuleEntryState extends State<WaiterModuleEntry> {
  final _session = getIt<WaiterSessionService>();
  final _controller = getIt<WaiterController>();
  final _outbox = getIt<WaiterOrderOutbox>();
  final _configStore = getIt<WaiterConfigStore>();
  final _billing = getIt<WaiterBillingService>();
  final _authService = getIt<AuthService>();

  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _session.initialize(branchId: ApiConstants.branchId.toString());
    // Hydrate any printer / KDS snapshots the cashier pushed last session
    // before we bring up the mesh — otherwise the first incoming NEW_ORDER
    // could race with config arriving from the cashier's push-on-HELLO.
    await _configStore.initialize();
    await _outbox.initialize();
    // Refresh the user profile on every waiter app entry: the cashier does
    // this in main_screen.session.dart (_loadUserData), but the waiter path
    // skips that screen. Without this, a cold-start waiter keeps whatever
    // profile was cached at last login — so a freshly-enabled NearPay flag
    // on the backend would never reach the device until re-login. Runs
    // before hydrateNearPayConfig so the latter sees the latest options.
    try {
      await _authService.getProfile();
    } catch (e) {
      debugPrint('⚠️ Waiter profile refresh failed (using cached): $e');
    }
    // Auto-sign-in using the name from the backend profile — there's no
    // reason to ask the waiter to retype it. We call signIn() even when
    // the session already has a stored name so a stale / test name
    // (e.g. an old "ببب" from a dev login) gets replaced with the
    // authoritative profile name on every boot.
    try {
      final resolvedName = _resolveWaiterName();
      debugPrint(
          '👤 Waiter auto sign-in: name="$resolvedName" '
          'wasSignedIn=${_session.isSignedIn} '
          'previous="${_session.self?.name ?? ''}"');
      if (resolvedName.isNotEmpty &&
          resolvedName != _session.self?.name) {
        await _session.signIn(
          name: resolvedName,
          branchId: ApiConstants.branchId.toString(),
        );
      } else if (resolvedName.isEmpty && !_session.isSignedIn) {
        // Nothing to sign in with — leave _ready=true with isSignedIn
        // false so the fallback splash renders.
        debugPrint('⚠️ Waiter auto sign-in: no name resolved from profile');
      }
    } catch (e) {
      debugPrint('⚠️ Waiter auto sign-in failed: $e');
    }
    // Mirror the cashier's login-time NearPay bootstrap so a waiter paying
    // with card on a NearPay-enabled branch gets the same in-app flow the
    // cashier does (setNearPayEnabled + JWT pre-warm + SDK ensureReady).
    // Non-blocking: runs concurrently with the rest of the boot.
    unawaited(_billing.hydrateNearPayConfig());
    if (_session.isSignedIn) {
      // Realign the live DisplayAppService WebSocket to whatever KDS the
      // cashier last pushed. No-op if the endpoint already matches.
      await _configStore.reapplyKdsEndpointToLiveService();
      // Resume a previously-started shift automatically.
      try {
        await _controller.start();
      } catch (_) {}
    }
    if (mounted) setState(() => _ready = true);
  }

  /// Pull the display name for this waiter out of the AuthService
  /// profile. The backend response wraps the name in a language map
  /// (`fullname: {ar: "...", en: "..."}`) so we respect the app's
  /// current language and gracefully degrade through the other keys,
  /// then email/mobile, before giving up on a generic label.
  String _resolveWaiterName() {
    final user = _authService.getUser();
    if (user == null) return '';
    final fullname = user['fullname'];
    if (fullname is Map) {
      final langCode = translationService.currentLanguageCode;
      for (final key in [langCode, 'ar', 'en']) {
        final v = fullname[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      // Some backends flatten to a single string even under the map;
      // grab the first non-empty value we see.
      for (final v in fullname.values) {
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    } else if (fullname is String && fullname.trim().isNotEmpty) {
      return fullname.trim();
    }
    final plainName = user['name'];
    if (plainName is String && plainName.trim().isNotEmpty) {
      return plainName.trim();
    }
    final email = user['email'];
    if (email is String && email.contains('@')) {
      final prefix = email.split('@').first.trim();
      if (prefix.isNotEmpty) return prefix;
    }
    final mobile = user['mobile'];
    if (mobile is String && mobile.trim().isNotEmpty) return mobile.trim();
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_session.isSignedIn) {
      return WaiterHomeScreen(controller: _controller);
    }
    // Fallback: profile didn't yield a usable name (unlikely) — show a
    // minimal retry splash instead of the old "enter your name" form.
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text(
                'تعذّر تحميل بيانات النادل. اضغط لإعادة المحاولة.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _ready = false);
                  _bootstrap();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
