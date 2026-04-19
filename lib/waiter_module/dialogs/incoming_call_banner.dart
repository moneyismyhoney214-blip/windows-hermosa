import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/app_themes.dart';
import '../../services/language_service.dart';
import '../models/waiter_message.dart';

/// Shows a material banner when another waiter calls this device.
/// The sound + vibration are handled by [WaiterNotificationService]; this
/// widget is purely visual.
void showIncomingCallBanner(BuildContext context, WaiterMessage msg) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.clearMaterialBanners();

  final text = msg.tableNumber != null && msg.tableNumber!.isNotEmpty
      ? translationService.t(
          'waiter_call_with_table',
          args: {
            'name': msg.fromWaiterName,
            'table': msg.tableNumber,
          },
        )
      : translationService.t(
          'waiter_call_from',
          args: {'name': msg.fromWaiterName},
        );

  final banner = MaterialBanner(
    backgroundColor: context.appPrimary,
    content: Row(
      children: [
        const Icon(LucideIcons.bellRing, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            msg.text.isEmpty ? text : '$text — ${msg.text}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        onPressed: () => messenger.hideCurrentMaterialBanner(),
        child: Text(translationService.t('waiter_dismiss')),
      ),
    ],
  );

  messenger.showMaterialBanner(banner);
  Future.delayed(const Duration(seconds: 8), () {
    try {
      messenger.hideCurrentMaterialBanner();
    } catch (_) {}
  });
}
