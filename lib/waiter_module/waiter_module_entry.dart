import 'package:flutter/material.dart';

import '../locator.dart';
import '../services/api/api_constants.dart';
import 'screens/waiter_home_screen.dart';
import 'screens/waiter_login_screen.dart';
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

  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _session.initialize(branchId: ApiConstants.branchId.toString());
    await _outbox.initialize();
    if (_session.isSignedIn) {
      // Resume a previously-started shift automatically.
      try {
        await _controller.start();
      } catch (_) {}
    }
    if (mounted) setState(() => _ready = true);
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
    return WaiterLoginScreen(session: _session, controller: _controller);
  }
}
