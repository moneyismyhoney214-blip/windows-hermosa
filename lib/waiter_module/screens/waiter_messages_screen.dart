import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/app_themes.dart';
import '../../services/language_service.dart';
import '../models/waiter_message.dart';
import '../services/waiter_controller.dart';

/// Flat feed of broadcast notifications. Each row is either:
///   * a *pending* broadcast (someone asked for help at a table,
///     nobody has accepted yet) — shows "استلام" / Accept button, or
///   * an *accepted* broadcast — shows "تم الاستلام بواسطة X" and the
///     accept button disappears for everyone.
///
/// Old-style 1-to-1 messages (when someone pages a specific waiter by
/// name) still render here — they just have no accept button.
class WaiterMessagesScreen extends StatefulWidget {
  final WaiterController controller;
  const WaiterMessagesScreen({super.key, required this.controller});

  @override
  State<WaiterMessagesScreen> createState() => _WaiterMessagesScreenState();
}

class _WaiterMessagesScreenState extends State<WaiterMessagesScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.messages.addListener(_onStoreChanged);
    // Opening the tab counts as "read" — clears the unread badge.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.messages.markAllRead();
    });
  }

  @override
  void dispose() {
    widget.controller.messages.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.controller.messages.all.reversed.toList();
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.bellOff, size: 42, color: context.appTextMuted),
            const SizedBox(height: 8),
            Text(
              translationService.t('waiter_notifications_empty'),
              style: TextStyle(color: context.appTextMuted),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) =>
          _NotificationTile(message: items[i], controller: widget.controller),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final WaiterMessage message;
  final WaiterController controller;

  const _NotificationTile({required this.message, required this.controller});

  @override
  Widget build(BuildContext context) {
    final me = controller.session.self;
    final mine = me != null && message.fromWaiterId == me.id;
    final accepted = message.isAccepted;
    final acceptedByMe =
        accepted && message.acceptedByWaiterId == me?.id;
    final canAccept = !mine && !accepted && message.isBroadcast && !(me?.isViewer ?? false);

    final accent = accepted ? context.appSuccess : context.appPrimary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                message.isCall ? LucideIcons.bellRing : LucideIcons.messageCircle,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mine
                      ? translationService.t('waiter_notification_from_me')
                      : message.fromWaiterName,
                  style: TextStyle(
                    color: context.appText,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                DateFormat('HH:mm').format(message.sentAt),
                style: TextStyle(color: context.appTextMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (message.tableNumber != null && message.tableNumber!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(LucideIcons.armchair,
                      size: 13, color: context.appTextMuted),
                  const SizedBox(width: 4),
                  Text(
                    '${translationService.t('waiter_table')} ${message.tableNumber}',
                    style: TextStyle(
                      color: context.appText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          if (message.text.isNotEmpty)
            Text(
              message.text,
              style: TextStyle(color: context.appText, fontSize: 13),
            ),
          const SizedBox(height: 8),
          _footer(context,
              accepted: accepted,
              acceptedByMe: acceptedByMe,
              canAccept: canAccept,
              accent: accent),
        ],
      ),
    );
  }

  Widget _footer(
    BuildContext context, {
    required bool accepted,
    required bool acceptedByMe,
    required bool canAccept,
    required Color accent,
  }) {
    if (accepted) {
      final label = acceptedByMe
          ? translationService.t('waiter_notification_accepted_by_me')
          : translationService.t(
              'waiter_notification_accepted_by',
              args: {'name': message.acceptedByWaiterName ?? '—'},
            );
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.checkCircle, size: 14, color: accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    if (canAccept) {
      return SizedBox(
        width: double.infinity,
        height: 38,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
          ),
          onPressed: () => controller.acceptCall(message.id),
          icon: const Icon(LucideIcons.check, size: 16),
          label: Text(
            translationService.t('waiter_notification_accept'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    // Notification targeted at me (not broadcast) — nothing to accept,
    // just show a quiet label so the user knows the state.
    return Text(
      message.isBroadcast
          ? translationService.t('waiter_notification_pending')
          : translationService.t('waiter_notification_direct'),
      style: TextStyle(
        color: context.appTextMuted,
        fontSize: 11,
      ),
    );
  }
}
