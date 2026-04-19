import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/app_themes.dart';

/// The restaurant-bell icon used to request another waiter. Simple dedicated
/// widget so the icon and tap-target are consistent across every screen.
class WaiterCallBellButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String? tooltip;
  final double size;
  final bool highlighted;

  const WaiterCallBellButton({
    super.key,
    required this.onPressed,
    this.tooltip,
    this.size = 44,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? context.appPrimary : context.appText;
    final bg = highlighted
        ? context.appPrimary.withValues(alpha: 0.14)
        : context.appSurfaceAlt;
    return Tooltip(
      message: tooltip ?? 'Call waiter',
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(LucideIcons.bellRing, color: color, size: size * 0.5),
          ),
        ),
      ),
    );
  }
}
