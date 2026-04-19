import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/app_themes.dart';
import '../../services/language_service.dart';
import '../services/waiter_controller.dart';

/// Broadcast-call dialog: the cashier (or a waiter) rings the bell and
/// every waiter on the LAN sees the request in their Notifications tab.
/// The first one to tap "استلام" claims it, the others see who claimed.
class CallWaiterDialog extends StatefulWidget {
  final WaiterController controller;
  final String? tableId;
  final String? tableNumber;

  const CallWaiterDialog({
    super.key,
    required this.controller,
    this.tableId,
    this.tableNumber,
  });

  @override
  State<CallWaiterDialog> createState() => _CallWaiterDialogState();
}

class _CallWaiterDialogState extends State<CallWaiterDialog> {
  final _messageCtrl = TextEditingController();

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  void _broadcast() {
    widget.controller.sendMessage(
      text: _messageCtrl.text.trim(),
      tableId: widget.tableId,
      tableNumber: widget.tableNumber,
      isCall: true,
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.tableNumber != null
        ? translationService.t(
            'waiter_call_for_table',
            args: {'table': widget.tableNumber!},
          )
        : translationService.t('waiter_call_broadcast_title');

    final peerCount = widget.controller.roster.all
        .where((w) => !w.isViewer)
        .length;

    return AlertDialog(
      backgroundColor: context.appSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(LucideIcons.bellRing, color: context.appPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: context.appText, fontSize: 17),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.appSurfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.users,
                      size: 16, color: context.appTextMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      translationService.t(
                        'waiter_call_broadcast_hint',
                        args: {'count': peerCount},
                      ),
                      style:
                          TextStyle(color: context.appTextMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _messageCtrl,
              minLines: 1,
              maxLines: 3,
              style: TextStyle(color: context.appText),
              decoration: InputDecoration(
                hintText: translationService.t('waiter_message_optional'),
                filled: true,
                fillColor: context.appSurfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.appBorder),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(translationService.t('waiter_cancel')),
        ),
        FilledButton.icon(
          onPressed: _broadcast,
          style: FilledButton.styleFrom(
            backgroundColor: context.appPrimary,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(LucideIcons.bellRing),
          label: Text(translationService.t('waiter_ring')),
        ),
      ],
    );
  }
}
