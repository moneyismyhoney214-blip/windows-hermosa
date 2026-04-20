import 'package:flutter/services.dart';

/// Design tokens shared across the waiter module. A tiny set by design —
/// the goal is "pick one of these" instead of eyeballing numbers per
/// screen. Add sparingly; every token here becomes a commitment.
class WaiterSpacing {
  WaiterSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class WaiterRadius {
  WaiterRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;
}

class WaiterSizes {
  WaiterSizes._();

  /// Material's minimum tap target. Touch anything smaller than this in
  /// a busy restaurant and you *will* mis-tap. Treat as a hard floor.
  static const double minTapTarget = 44;
  static const double tapTargetLg = 56;

  /// "Primary" action button — Send to kitchen, Start shift, Accept claim.
  static const double primaryButtonHeight = 52;

  static const double iconSmall = 16;
  static const double iconMedium = 20;
  static const double iconLarge = 24;
}

/// Haptic vocabulary used across the waiter module. Kept light because
/// over-vibration is worse than none — haptics should confirm, not nag.
class WaiterHaptics {
  WaiterHaptics._();

  /// A selection / tab switch — the quietest feedback.
  static Future<void> tick() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Affirmative action landed (send-to-kitchen queued, message sent).
  static Future<void> confirm() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// A durable change — claim accepted, bill paid, shift ended.
  static Future<void> success() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Something went wrong or a destructive action fired.
  static Future<void> warn() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }
}
