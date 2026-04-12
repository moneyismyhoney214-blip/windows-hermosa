import 'package:flutter/material.dart';
import '../locator.dart';
import '../services/cashier_sound_service.dart';

class ButtonSoundOverlay extends StatelessWidget {
  final Widget child;
  const ButtonSoundOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (!getIt.isRegistered<CashierSoundService>()) return;
        try {
          getIt<CashierSoundService>().playButtonSound();
        } catch (_) {
          // Keep UI safe even if DI state is transient during hot reload/restart.
        }
      },
      child: child,
    );
  }
}
