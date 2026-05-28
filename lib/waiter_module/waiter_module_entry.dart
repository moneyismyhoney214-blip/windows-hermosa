import 'dart:async';

import 'package:flutter/material.dart';

import '../locator.dart';
import '../services/api/api_constants.dart';
import '../services/api/auth_service.dart';
import '../services/language_service.dart';
import '../services/logger_service.dart';
import '../services/waitlist_mesh_bridge.dart';
import '../services/waitlist_service.dart';
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
  bool _bootstrapping = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Guard overlapping runs (initState + retry button).
    if (_bootstrapping) return;
    _bootstrapping = true;
    try {
      await _bootstrapInner();
    } finally {
      _bootstrapping = false;
    }
  }

  Future<void> _bootstrapInner() async {
    await _session.initialize(branchId: ApiConstants.branchId.toString());
    // Hydrate cached printer/KDS snapshots BEFORE mesh comes up — avoids race with cashier's push-on-HELLO.
    await _configStore.initialize();
    await _outbox.initialize();
    // Refresh profile (waiter path skips main_screen) so flags like NearPay propagate without re-login.
    try {
      await _authService.getProfile();
    } catch (e) {
      debugPrint('⚠️ Waiter profile refresh failed (using cached): $e');
    }
    // Auto sign-in from profile name; re-signs even when already signed in to overwrite stale/test names.
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
        // No name resolvable; fallback splash will render.
        debugPrint('⚠️ Waiter auto sign-in: no name resolved from profile');
      }
    } catch (e) {
      debugPrint('⚠️ Waiter auto sign-in failed: $e');
    }
    // NearPay bootstrap mirrors cashier (setNearPayEnabled + JWT pre-warm + ensureReady), non-blocking.
    unawaited(_billing.hydrateNearPayConfig());
    if (_session.isSignedIn) {
      // Realign WS endpoint to cashier's last-pushed KDS (no-op if unchanged).
      await _configStore.reapplyKdsEndpointToLiveService();
      try {
        await _controller.start();
      } catch (e) {
        Log.d('WaiterModuleEntry', 'resume previous shift failed (non-fatal): $e');
      }
      // Wire waitlist service to the mesh controller.
      unawaited(waitlistService.initialize());
      waitlistMeshBridge.attach(_controller);
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
      // Some backends flatten the map — grab the first non-empty value.
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
    // Fallback when profile didn't yield a usable name.
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                translationService.t('waiter_load_failed_retry'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _ready = false);
                  _bootstrap();
                },
                icon: const Icon(Icons.refresh),
                label: Text(translationService.t('waiter_retry')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
