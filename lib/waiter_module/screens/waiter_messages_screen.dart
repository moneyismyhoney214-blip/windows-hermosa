import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'dart:async';

import '../../services/app_themes.dart';
import '../../services/language_service.dart';
import '../models/table_pickup_request.dart';
import '../models/waiter.dart';
import '../models/waiter_message.dart';
import '../services/waiter_controller.dart';
import '../theme/waiter_design.dart';

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
    widget.controller.pickupStore.addListener(_onStoreChanged);
    // Opening the tab counts as "read" — clears the unread badge.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.messages.markAllRead();
    });
  }

  @override
  void dispose() {
    widget.controller.messages.removeListener(_onStoreChanged);
    widget.controller.pickupStore.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final messageItems = widget.controller.messages.all
        .reversed
        .map<_Entry>((m) => _MessageEntry(m))
        .toList();
    final pickupItems = widget.controller.pickupStore.all
        .map<_Entry>((r) => _PickupEntry(r))
        .toList();
    final items = <_Entry>[...pickupItems, ...messageItems]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

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
      itemBuilder: (_, i) {
        final entry = items[i];
        if (entry is _PickupEntry) {
          return _PickupTile(
            request: entry.request,
            controller: widget.controller,
          );
        }
        return _NotificationTile(
          message: (entry as _MessageEntry).message,
          controller: widget.controller,
        );
      },
    );
  }
}

abstract class _Entry {
  DateTime get timestamp;
}

class _MessageEntry implements _Entry {
  final WaiterMessage message;
  _MessageEntry(this.message);
  @override
  DateTime get timestamp => message.sentAt;
}

class _PickupEntry implements _Entry {
  final TablePickupRequest request;
  _PickupEntry(this.request);
  @override
  DateTime get timestamp => request.requestedAt;
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
    // A viewer-prefixed sender id is always the cashier — mark those
    // visually so waiters know the message came from the till, not from
    // another waiter.
    final fromCashier =
        message.fromWaiterId.startsWith(Waiter.viewerIdPrefix);

    final Color accent;
    if (accepted) {
      accent = context.appSuccess;
    } else if (fromCashier) {
      accent = const Color(0xFF2563EB); // cashier blue
    } else {
      accent = context.appPrimary;
    }

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
                fromCashier
                    ? LucideIcons.monitor
                    : (message.isCall
                        ? LucideIcons.bellRing
                        : LucideIcons.messageCircle),
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
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
                    if (fromCashier && !mine) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'الكاشير',
                          style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
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
        height: WaiterSizes.minTapTarget,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            unawaited(WaiterHaptics.confirm());
            controller.acceptCall(message.id);
          },
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

class _PickupTile extends StatelessWidget {
  final TablePickupRequest request;
  final WaiterController controller;

  const _PickupTile({required this.request, required this.controller});

  @override
  Widget build(BuildContext context) {
    final me = controller.session.self;
    final amIViewer = me?.isViewer ?? false;
    final claimedByMe =
        request.isClaimed && request.claimedByWaiterId == me?.id;
    final canAccept = !amIViewer && request.isPending;

    final accent = request.cancelled
        ? context.appTextMuted
        : (request.isClaimed ? context.appSuccess : context.appPrimary);

    final tableLabel = request.tableNumber.isNotEmpty
        ? request.tableNumber
        : request.tableId;

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
              Icon(LucideIcons.handMetal, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'طلب استلام من ${request.cashierName}',
                  style: TextStyle(
                    color: context.appText,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                DateFormat('HH:mm').format(request.requestedAt),
                style: TextStyle(color: context.appTextMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(LucideIcons.armchair,
                  size: 13, color: context.appTextMuted),
              const SizedBox(width: 4),
              Text(
                'طاولة $tableLabel',
                style: TextStyle(
                  color: context.appText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if ((request.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              request.note!,
              style: TextStyle(color: context.appText, fontSize: 13),
            ),
          ],
          const SizedBox(height: 8),
          _footer(
            context,
            accent: accent,
            claimedByMe: claimedByMe,
            canAccept: canAccept,
          ),
        ],
      ),
    );
  }

  Widget _footer(
    BuildContext context, {
    required Color accent,
    required bool claimedByMe,
    required bool canAccept,
  }) {
    if (request.cancelled) {
      return _statusPill(
        context,
        accent: accent,
        icon: LucideIcons.xCircle,
        label: 'تم إلغاء الطلب',
      );
    }
    if (request.isClaimed) {
      final label = claimedByMe
          ? 'استلمت الطاولة'
          : '${request.claimedByWaiterName ?? '—'} استلم الطاولة';
      return _statusPill(
        context,
        accent: accent,
        icon: LucideIcons.checkCircle,
        label: label,
      );
    }
    if (canAccept) {
      return SizedBox(
        width: double.infinity,
        height: WaiterSizes.minTapTarget,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            unawaited(WaiterHaptics.success());
            controller.claimTablePickup(request.requestId);
          },
          icon: const Icon(LucideIcons.check, size: 18),
          label: const Text(
            'استلام',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
      );
    }
    // Cashier viewing its own broadcast — pending, no action.
    return Text(
      'بانتظار رد نادل...',
      style: TextStyle(color: context.appTextMuted, fontSize: 11),
    );
  }

  Widget _statusPill(
    BuildContext context, {
    required Color accent,
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
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
}
