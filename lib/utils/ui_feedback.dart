import 'package:flutter/material.dart';

/// Reusable user-facing feedback helpers.
///
/// Replaces hundreds of ad-hoc `ScaffoldMessenger.of(context).showSnackBar(...)`
/// and `showDialog(...)` call sites scattered across screens and dialogs.
/// Centralizing them gives us:
///   1. Consistent visual style (colors, icons, durations) across the app,
///   2. A single place to localize / switch to a richer toast lib later,
///   3. Built-in `mounted` checks so async callers can't paint into a
///      torn-down widget tree (a real `use_build_context_synchronously`
///      bug-source in the existing code).
///
/// Usage:
/// ```dart
/// UiFeedback.error(context, 'فشل الحفظ');
/// UiFeedback.success(context, 'تم الحفظ');
/// final ok = await UiFeedback.confirm(context,
///     title: 'حذف الموعد؟', message: 'لا يمكن التراجع.');
/// ```
class UiFeedback {
  UiFeedback._();

  /// Default duration applied to every snackbar unless caller overrides.
  static const Duration _defaultDuration = Duration(seconds: 3);

  /// Show a red error snackbar. Safe to call from `async` paths — guarded
  /// internally so it no-ops if the context is no longer mounted.
  static void error(
    BuildContext context,
    String message, {
    Duration? duration,
    SnackBarAction? action,
  }) {
    _show(
      context,
      message,
      backgroundColor: Colors.red.shade600,
      icon: Icons.error_outline,
      duration: duration,
      action: action,
    );
  }

  /// Show a green success snackbar.
  static void success(
    BuildContext context,
    String message, {
    Duration? duration,
    SnackBarAction? action,
  }) {
    _show(
      context,
      message,
      backgroundColor: Colors.green.shade600,
      icon: Icons.check_circle_outline,
      duration: duration,
      action: action,
    );
  }

  /// Show an amber warning snackbar.
  static void warning(
    BuildContext context,
    String message, {
    Duration? duration,
    SnackBarAction? action,
  }) {
    _show(
      context,
      message,
      backgroundColor: Colors.orange.shade700,
      icon: Icons.warning_amber_outlined,
      duration: duration,
      action: action,
    );
  }

  /// Neutral informational snackbar — uses the theme's surface color.
  static void info(
    BuildContext context,
    String message, {
    Duration? duration,
    SnackBarAction? action,
  }) {
    _show(
      context,
      message,
      backgroundColor: Theme.of(context).colorScheme.inverseSurface,
      icon: Icons.info_outline,
      duration: duration,
      action: action,
    );
  }

  /// Show a yes/no confirmation dialog. Returns `true` if the user
  /// confirms, `false` (or `null`-coerced) if they cancel or dismiss by
  /// tapping outside.
  ///
  /// The dialog is intentionally minimal — call-sites that need a custom
  /// layout should still use `showDialog` directly. This helper exists for
  /// the common "are you sure?" prompt that previously had 30+ copy-pasted
  /// implementations.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          TextButton(
            style: destructive
                ? TextButton.styleFrom(foregroundColor: Colors.red.shade700)
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Dismiss the currently-visible snackbar, if any. Useful when a
  /// long-running operation completes and the caller wants to clear an
  /// earlier "saving…" toast before showing the success/failure.
  static void dismiss(BuildContext context) {
    if (!_isStillMounted(context)) return;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  }

  // ─────────────────────────── internals ────────────────────────────────

  static void _show(
    BuildContext context,
    String message, {
    required Color backgroundColor,
    required IconData icon,
    Duration? duration,
    SnackBarAction? action,
  }) {
    if (!_isStillMounted(context)) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: backgroundColor,
          duration: duration ?? _defaultDuration,
          action: action,
          content: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
  }

  /// Best-effort `mounted` check for a context whose owner is unknown.
  /// `BuildContext.mounted` is the canonical signal but isn't exposed on
  /// raw `BuildContext` in older Flutter SDKs, so we fall back to a
  /// `findRenderObject` probe.
  static bool _isStillMounted(BuildContext context) {
    try {
      // Flutter 3.7+ exposes `mounted` directly on BuildContext.
      return context.mounted;
    } catch (_) {
      try {
        return context.findRenderObject() != null;
      } catch (_) {
        return false;
      }
    }
  }
}
