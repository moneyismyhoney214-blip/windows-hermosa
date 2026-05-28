part of '../table_management_screen.dart';

// Helper widgets + painters extracted from table_management_screen.dart (library-private).

class _RestaurantTableSection {
  final String key;
  final String title;
  final List<TableItem> tables;
  _RestaurantTableSection({
    required this.key,
    required this.title,
    required this.tables,
  });
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.1)
      ..strokeWidth = 1;

    const gridSize = 50.0;

    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


class _NormalTableCard extends StatelessWidget {
  final TableItem table;
  final bool isDeactivated;
  final VoidCallback? onTap;
  final bool compact;
  final double? width;
  final double? height;

  /// Most recent pickup state for this table. When non-null we overlay a
  /// status strip / cancel button; when null and the table is available
  /// we expose the "استلام" action so the cashier can broadcast.
  final TablePickupRequest? activePickup;
  final VoidCallback? onRequestPickup;
  final VoidCallback? onCancelPickup;
  final VoidCallback? onMigrate;
  /// Cashier force-release: clears the waiter's hold on an occupied
  /// table so it becomes available again. Manual only — the cashier
  /// decides when to fire this (no auto-timeout).
  final VoidCallback? onReleaseTable;
  /// Order-management actions for a table that has an active backend
  /// booking (pay-later / paid). All four are null when there's nothing
  /// to manage (free table, or no booking id known yet).
  final VoidCallback? onOrderDetails;
  final VoidCallback? onEditOrder;
  final VoidCallback? onRefundOrder;
  final VoidCallback? onCancelBooking;
  /// Waiter has opened the table and is composing the first order but has
  /// not yet sent it to the kitchen. Shown to the cashier as
  /// "جاري اخذ الطلب" instead of the generic occupied label.
  final bool isTakingOrder;

  /// Number of guests the waiter set for this table (distinct from the
  /// table's capacity `seats`). Null when no active party.
  final int? guestCount;

  /// When non-null the table was handed to this waitlist party but
  /// they haven't arrived yet. Overrides the normal free-state color
  /// so the host doesn't accidentally double-book.
  final String? holdingForName;

  const _NormalTableCard({
    super.key,
    required this.table,
    required this.isDeactivated,
    this.onTap,
    this.compact = false,
    this.width,
    this.height,
    this.activePickup,
    this.onRequestPickup,
    this.onCancelPickup,
    this.onMigrate,
    this.onReleaseTable,
    this.onOrderDetails,
    this.onEditOrder,
    this.onRefundOrder,
    this.onCancelBooking,
    this.isTakingOrder = false,
    this.guestCount,
    this.holdingForName,
  });

  bool get _isHoldingForWaitlist {
    if (isDeactivated) return false;
    if (table.status != TableStatus.available) return false;
    return holdingForName != null && holdingForName!.trim().isNotEmpty;
  }

  _TablePalette _paletteFor() {
    if (isDeactivated) {
      return const _TablePalette(
        background: Color(0xFFF1F5F9),
        border: Color(0xFFCBD5E1),
        accent: Color(0xFF64748B),
      );
    }
    if (_isHoldingForWaitlist) {
      // Warm amber matches the waiter card + assign banner ("reserved").
      return const _TablePalette(
        background: Color(0xFFFEF3C7),
        border: Color(0xFFF59E0B),
        accent: Color(0xFFB45309),
      );
    }
    switch (table.status) {
      case TableStatus.available:
        return const _TablePalette(
          background: Color(0xFFDCFCE7),
          border: Color(0xFF16A34A),
          accent: Color(0xFF16A34A),
        );
      case TableStatus.occupied:
        return const _TablePalette(
          background: Color(0xFFFFFFFF),
          border: Color(0xFFDC2626),
          accent: Color(0xFFDC2626),
        );
      case TableStatus.printed:
        return const _TablePalette(
          background: Color(0xFFFEF3C7),
          border: Color(0xFFF59E0B),
          accent: Color(0xFFB45309),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor();
    final subtitle = _subtitleLabel();

    return SizedBox(
      width: width ?? 140,
      height: height ?? 140,
      child: RepaintBoundary(
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: isDeactivated || !_hasAnyAction()
              ? const <Type, GestureRecognizerFactory>{}
              : <Type, GestureRecognizerFactory>{
                  LongPressGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          LongPressGestureRecognizer>(
                    () => LongPressGestureRecognizer(
                      duration: const Duration(milliseconds: 500),
                    ),
                    (instance) {
                      instance.onLongPressStart = (details) =>
                          _openActionsMenu(context, details.globalPosition);
                    },
                  ),
                },
          child: Material(
          color: palette.background,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: isDeactivated ? null : onTap,
            borderRadius: BorderRadius.circular(10),
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
                            color: isDeactivated
                                ? palette.accent
                                : const Color(0xFF0F172A),
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
                                  size: 12, color: palette.accent),
                              const SizedBox(width: 2),
                              Text(
                                '${(guestCount != null && guestCount! > 0) ? guestCount : table.seats}',
                                style: TextStyle(
                                  color: palette.accent,
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
                  if (table.isPaid && !isDeactivated)
                    const PositionedDirectional(
                      bottom: 4,
                      start: 6,
                      child: Icon(
                        LucideIcons.dollarSign,
                        size: 12,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  // Lock glyph: "tap to seat" (held for waitlisted party).
                  if (_isHoldingForWaitlist)
                    const PositionedDirectional(
                      bottom: 4,
                      start: 6,
                      child: Icon(
                        LucideIcons.lock,
                        size: 12,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  // 3-dots menu replaced by 2s long-press (see RawGestureDetector above).
                  if (!isDeactivated && _showPickupHint())
                    PositionedDirectional(
                      bottom: 4,
                      start: table.isPaid ? 20 : 6,
                      child: _buildPickupHint(),
                    ),
                  if (isDeactivated)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.ban,
                                  color: Colors.white, size: 22),
                              const SizedBox(height: 4),
                              Text(
                                translationService.t('disabled'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  String? _subtitleLabel() {
    if (isDeactivated) return null;
    // Holding-for-waitlist overrides every free-state signal (table is reserved).
    if (_isHoldingForWaitlist) {
      return translationService.t(
        'waitlist_table_pill_waiting_for',
        args: {'name': holdingForName},
      );
    }
    if (table.status == TableStatus.occupied && isTakingOrder) {
      return translationService.t('taking_order');
    }
    if (table.status == TableStatus.printed) {
      return translationService.t('printed');
    }
    if (table.status == TableStatus.occupied) {
      final pickup = activePickup;
      if (pickup != null && pickup.isClaimed) {
        return pickup.claimedByWaiterName;
      }
      final name = table.waiterName?.trim() ?? '';
      if (name.isNotEmpty) return name;
      return translationService.t('occupied');
    }
    final pickup = activePickup;
    if (pickup != null && pickup.isPending) {
      return translationService.t('waiting_for_waiter_dots');
    }
    if (pickup != null && pickup.isClaimed) {
      return translationService.t(
        'waiter_claimed_n',
        args: {'name': pickup.claimedByWaiterName ?? ''},
      );
    }
    return null;
  }

  bool _showPickupHint() {
    final pickup = activePickup;
    if (pickup != null && pickup.isPending) return true;
    return false;
  }

  Widget _buildPickupHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFF58220).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF58220)),
        ),
      ),
    );
  }

  bool _hasAnyAction() {
    final canPickup = activePickup == null &&
        table.status == TableStatus.available &&
        onRequestPickup != null;
    final canCancelPickup = activePickup != null &&
        activePickup!.isPending &&
        onCancelPickup != null;
    return canPickup ||
        canCancelPickup ||
        onMigrate != null ||
        onReleaseTable != null ||
        onOrderDetails != null ||
        onEditOrder != null ||
        onRefundOrder != null ||
        onCancelBooking != null;
  }

  // Opens the actions menu at the touch position (long-press anchor).
  Future<void> _openActionsMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlay.size.width - globalPosition.dx,
      overlay.size.height - globalPosition.dy,
    );
    final value = await showMenu<String>(
      context: context,
      position: position,
      items: [
        if (activePickup == null && onRequestPickup != null)
          PopupMenuItem<String>(
            value: 'pickup',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.handMetal,
                    size: 16, color: Color(0xFFF58220)),
                const SizedBox(width: 8),
                Text(
                  translationService.t('waiter_pickup_take'),
                  style: const TextStyle(
                    color: Color(0xFFF58220),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        if (activePickup != null &&
            activePickup!.isPending &&
            onCancelPickup != null)
          PopupMenuItem<String>(
            value: 'cancel_pickup',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.x, size: 16, color: Color(0xFFDC2626)),
                const SizedBox(width: 8),
                Text(
                  translationService.t('cancel_pickup'),
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        if (onOrderDetails != null)
          PopupMenuItem<String>(
            value: 'order_details',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.fileText, size: 16, color: Color(0xFF2563EB)),
                const SizedBox(width: 8),
                Text(translationService.t('waiter_action_order_details'),
                    style: const TextStyle(
                        color: Color(0xFF2563EB), fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        if (onEditOrder != null)
          PopupMenuItem<String>(
            value: 'edit_order',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.edit3, size: 16, color: Color(0xFF0F766E)),
                const SizedBox(width: 8),
                Text(translationService.t('waiter_action_edit_order'),
                    style: const TextStyle(
                        color: Color(0xFF0F766E), fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        if (onRefundOrder != null)
          PopupMenuItem<String>(
            value: 'refund_order',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.undo2, size: 16, color: Color(0xFFEF4444)),
                const SizedBox(width: 8),
                Text(translationService.t('waiter_action_refund'),
                    style: const TextStyle(
                        color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        if (onCancelBooking != null)
          PopupMenuItem<String>(
            value: 'cancel_booking',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.xCircle, size: 16, color: Color(0xFFDC2626)),
                const SizedBox(width: 8),
                Text(translationService.t('cancel_booking_title'),
                    style: const TextStyle(
                        color: Color(0xFFDC2626), fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        if (onMigrate != null)
          PopupMenuItem<String>(
            value: 'migrate',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.moveRight,
                    size: 16, color: Color(0xFF2563EB)),
                const SizedBox(width: 8),
                Text(
                  translationService.t('move_to_another_table'),
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        if (onReleaseTable != null)
          PopupMenuItem<String>(
            value: 'release',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.logOut, size: 16, color: Color(0xFFDC2626)),
                const SizedBox(width: 8),
                Text(
                  translationService.t('release_table_btn'),
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (value == 'pickup' && onRequestPickup != null) onRequestPickup!();
    if (value == 'cancel_pickup' && onCancelPickup != null) onCancelPickup!();
    if (value == 'order_details' && onOrderDetails != null) onOrderDetails!();
    if (value == 'edit_order' && onEditOrder != null) onEditOrder!();
    if (value == 'refund_order' && onRefundOrder != null) onRefundOrder!();
    if (value == 'cancel_booking' && onCancelBooking != null) {
      onCancelBooking!();
    }
    if (value == 'migrate' && onMigrate != null) onMigrate!();
    if (value == 'release' && onReleaseTable != null) onReleaseTable!();
  }
}

class _TablePalette {
  final Color background;
  final Color border;
  final Color accent;

  const _TablePalette({
    required this.background,
    required this.border,
    required this.accent,
  });
}

class _HeaderActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const btnColor = Color(0xFFF58220);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 8,
        ),
        child: Row(
          children: [
            Icon(icon, color: btnColor, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: btnColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

/// Compact icon-only waitlist button for the compact header layout.
class _WaitlistHeaderIconButton extends StatelessWidget {
  final int count;
  final VoidCallback onPressed;

  const _WaitlistHeaderIconButton({
    required this.count,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: translationService.t('waitlist_tooltip'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        backgroundColor: const Color(0xFFDC2626),
        child: const Icon(LucideIcons.clock),
      ),
      color: const Color(0xFFF58220),
    );
  }
}

/// Full-width waitlist action button matching [_HeaderActionBtn] styling.
class _WaitlistHeaderActionBtn extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _WaitlistHeaderActionBtn({
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const btnColor = Color(0xFFF58220);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              backgroundColor: const Color(0xFFDC2626),
              child: const Icon(LucideIcons.clock, color: btnColor, size: 18),
            ),
            const SizedBox(width: 8),
            Text(
              translationService.t('waitlist_title'),
              style: const TextStyle(
                color: btnColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _MigrateDestinationDialog extends StatelessWidget {
  final TableItem source;
  final List<TableItem> destinations;

  const _MigrateDestinationDialog({
    required this.source,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...destinations]
      ..sort((a, b) {
        final an = int.tryParse(a.number) ?? 0;
        final bn = int.tryParse(b.number) ?? 0;
        return an.compareTo(bn);
      });
    return AlertDialog(
      backgroundColor: context.appSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(LucideIcons.moveRight, color: Color(0xFF2563EB)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              translationService.t(
                'move_table_n_to_dots',
                args: {'number': source.number},
              ),
              style: TextStyle(color: context.appText, fontSize: 17),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        height: 360,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.1,
          ),
          itemCount: sorted.length,
          itemBuilder: (_, i) {
            final t = sorted[i];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).pop(t),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.appBorder),
                  color: context.appSurfaceAlt,
                ),
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.armchair,
                        color: context.appSuccess, size: 28),
                    const SizedBox(height: 8),
                    Text(
                      t.number,
                      style: TextStyle(
                        color: context.appText,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      translationService.t(
                        'people_count',
                        args: {'count': t.seats},
                      ),
                      style: TextStyle(
                        color: context.appTextMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(translationService.t('cancel')),
        ),
      ],
    );
  }
}
