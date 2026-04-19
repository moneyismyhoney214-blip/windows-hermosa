import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/app_themes.dart';
import '../../services/language_service.dart';
import '../models/waiter.dart';

/// A small pill that shows a waiter's availability status.
class WaiterStatusChip extends StatelessWidget {
  final WaiterStatus status;
  final double? fontSize;
  final EdgeInsetsGeometry padding;

  const WaiterStatusChip({
    super.key,
    required this.status,
    this.fontSize,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _meta(context, status);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: (fontSize ?? 12) + 2, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize ?? 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  (String, Color, IconData) _meta(BuildContext context, WaiterStatus status) {
    switch (status) {
      case WaiterStatus.free:
        return (
          translationService.t('waiter_status_free'),
          context.appSuccess,
          LucideIcons.checkCircle,
        );
      case WaiterStatus.busy:
        return (
          translationService.t('waiter_status_busy'),
          context.appPrimary,
          LucideIcons.clock,
        );
      case WaiterStatus.onBreak:
        return (
          translationService.t('waiter_status_break'),
          context.appTextMuted,
          LucideIcons.coffee,
        );
      case WaiterStatus.offline:
        return (
          translationService.t('waiter_status_offline'),
          context.appDanger,
          LucideIcons.wifiOff,
        );
    }
  }
}
