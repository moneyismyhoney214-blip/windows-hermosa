import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models.dart';
import '../../services/language_service.dart';

/// Visual card representing one table in the waiter's grid.
///
/// Simplified look: uniform rounded-rectangle cards with a thin colored
/// border — green for free, red for occupied/locked, amber for paid.
/// Table name sits at the top-start, guests count at the bottom-end.
class WaiterTableCard extends StatelessWidget {
  final TableItem table;
  final String? ownerWaiterId;
  final String? ownerWaiterName;
  final String currentWaiterId;
  final int? guestCount;
  final VoidCallback onTap;
  final bool isTakingOrder;
  final bool paymentPending;
  final VoidCallback? onMigrate;
  final VoidCallback? onEditOrder;
  final VoidCallback? onReleaseTable;
  /// Cancel a pay-later booking: PATCHes status=8 on the backend and
  /// flips the table back to free. Only offered when the table has an
  /// active paymentPending booking owned by the current waiter.
  final VoidCallback? onCancelBooking;
  /// When non-null, the table was assigned to this waitlist party but
  /// they haven't arrived yet. We overlay a small orange "holding"
  /// pill so the host doesn't accidentally give the table to someone
  /// else who walks in.
  final String? holdingForName;

  const WaiterTableCard({
    super.key,
    required this.table,
    required this.currentWaiterId,
    required this.onTap,
    this.ownerWaiterId,
    this.ownerWaiterName,
    this.guestCount,
    this.isTakingOrder = false,
    this.paymentPending = false,
    this.onMigrate,
    this.onEditOrder,
    this.onReleaseTable,
    this.onCancelBooking,
    this.holdingForName,
  });

  @override
  Widget build(BuildContext context) {
    final state = _resolveState();
    final palette = _paletteFor(state);
    final subtitle = _subtitle(state);

    return Semantics(
      label: _semanticsLabel(),
      button: true,
      child: Material(
        color: palette.background,
        borderRadius: BorderRadius.circular(10),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.border, width: 1.4),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        table.number,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.title,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      const Spacer(),
                      Align(
                        alignment: AlignmentDirectional.bottomEnd,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.user,
                                size: 12, color: palette.meta),
                            const SizedBox(width: 2),
                            Text(
                              '${(guestCount != null && guestCount! > 0) ? guestCount : table.seats}',
                              style: TextStyle(
                                color: palette.meta,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (state == _CardState.paid ||
                    state == _CardState.paymentPending)
                  const PositionedDirectional(
                    bottom: 4,
                    start: 6,
                    child: Icon(
                      LucideIcons.dollarSign,
                      size: 12,
                      color: Color(0xFFB45309),
                    ),
                  ),
                if (onMigrate != null ||
                    onReleaseTable != null ||
                    onEditOrder != null ||
                    onCancelBooking != null)
                  PositionedDirectional(
                    top: -2,
                    end: -2,
                    child: _buildActionsMenu(context, palette),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _CardState _resolveState() {
    if (table.isPaid) return _CardState.paid;
    if (paymentPending || table.status == TableStatus.printed) {
      return _CardState.paymentPending;
    }
    final hasOwner =
        ownerWaiterId != null && ownerWaiterId!.trim().isNotEmpty;
    if (!hasOwner && table.status == TableStatus.available) {
      // Holding-for-waitlist always wins over the plain "free" state —
      // otherwise the host sees a green card that looks like a fresh
      // table to hand to the next walk-in.
      if (holdingForName != null && holdingForName!.trim().isNotEmpty) {
        return _CardState.waitlistHold;
      }
      return _CardState.free;
    }
    if (isTakingOrder && hasOwner) return _CardState.takingOrder;
    if (ownerWaiterId == currentWaiterId) return _CardState.mine;
    return _CardState.otherWaiter;
  }

  String? _subtitle(_CardState state) {
    if (state == _CardState.waitlistHold) {
      return translationService.t(
        'waitlist_table_pill_waiting_for',
        args: {'name': holdingForName!},
      );
    }
    if (state == _CardState.takingOrder) return 'جاري اخذ الطلب';
    if (state == _CardState.paymentPending) return 'تم أخذ الطلب';
    if (state == _CardState.mine &&
        ownerWaiterName != null &&
        ownerWaiterName!.trim().isNotEmpty) {
      return ownerWaiterName;
    }
    return null;
  }

  Widget _buildActionsMenu(BuildContext context, _Palette palette) {
    return SizedBox(
      width: 24,
      height: 24,
      child: PopupMenuButton<String>(
        tooltip: 'خيارات',
        padding: EdgeInsets.zero,
        icon: Icon(
          LucideIcons.moreVertical,
          size: 14,
          color: palette.meta,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        onSelected: (value) {
          if (value == 'edit' && onEditOrder != null) onEditOrder!();
          if (value == 'migrate' && onMigrate != null) onMigrate!();
          if (value == 'release' && onReleaseTable != null) onReleaseTable!();
          if (value == 'cancel' && onCancelBooking != null) onCancelBooking!();
        },
        itemBuilder: (_) => [
          if (onEditOrder != null)
            const PopupMenuItem<String>(
              value: 'edit',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.pencil,
                      size: 16, color: Color(0xFFF59E0B)),
                  SizedBox(width: 8),
                  Text(
                    'تعديل الطلب',
                    style: TextStyle(
                      color: Color(0xFFB45309),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          if (onMigrate != null)
            const PopupMenuItem<String>(
              value: 'migrate',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.moveRight,
                      size: 16, color: Color(0xFF2563EB)),
                  SizedBox(width: 8),
                  Text(
                    'نقل إلى طاولة أخرى',
                    style: TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          if (onCancelBooking != null)
            const PopupMenuItem<String>(
              value: 'cancel',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.xCircle,
                      size: 16, color: Color(0xFFDC2626)),
                  SizedBox(width: 8),
                  Text(
                    'إلغاء الحجز',
                    style: TextStyle(
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          if (onReleaseTable != null)
            const PopupMenuItem<String>(
              value: 'release',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.logOut,
                      size: 16, color: Color(0xFFDC2626)),
                  SizedBox(width: 8),
                  Text(
                    'تحرير الطاولة',
                    style: TextStyle(
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  _Palette _paletteFor(_CardState state) {
    switch (state) {
      case _CardState.free:
        return const _Palette(
          accent: Color(0xFF16A34A),
          background: Color(0xFFDCFCE7),
          border: Color(0xFF16A34A),
          title: Color(0xFF0F172A),
          meta: Color(0xFF16A34A),
        );
      case _CardState.waitlistHold:
        // Warm amber — same visual language as the assign banner so
        // the host links the card to the pending notification.
        return const _Palette(
          accent: Color(0xFFB45309),
          background: Color(0xFFFEF3C7),
          border: Color(0xFFF59E0B),
          title: Color(0xFF0F172A),
          meta: Color(0xFFB45309),
        );
      case _CardState.mine:
      case _CardState.takingOrder:
      case _CardState.otherWaiter:
        return const _Palette(
          accent: Color(0xFFDC2626),
          background: Color(0xFFFFFFFF),
          border: Color(0xFFDC2626),
          title: Color(0xFF0F172A),
          meta: Color(0xFFDC2626),
        );
      case _CardState.paid:
      case _CardState.paymentPending:
        return const _Palette(
          accent: Color(0xFFB45309),
          background: Color(0xFFFEF3C7),
          border: Color(0xFFF59E0B),
          title: Color(0xFF0F172A),
          meta: Color(0xFFB45309),
        );
    }
  }

  String _semanticsLabel() => table.number;
}

enum _CardState {
  free,
  mine,
  takingOrder,
  otherWaiter,
  paid,
  paymentPending,
  waitlistHold,
}

class _Palette {
  final Color accent;
  final Color background;
  final Color border;
  final Color title;
  final Color meta;

  const _Palette({
    required this.accent,
    required this.background,
    required this.border,
    required this.title,
    required this.meta,
  });
}
