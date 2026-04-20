import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models.dart';
import '../../services/app_themes.dart';
import '../../services/language_service.dart';
import '../theme/waiter_design.dart';

/// Visual card representing one table in the waiter's grid.
///
/// Status encoding is deliberately opinionated:
///   * **free** — neutral surface, green status pill — the table is
///     available; this card is the most common CTA.
///   * **mine** — accent border filled, primary tint — "this is yours,
///     tap to keep serving it".
///   * **other waiter** — dimmed surface + muted icons — avoid
///     inviting a tap that'll only show a "owned by X" dialog.
///   * **paid / printed** — success tint with a receipt icon — the
///     order is closing out.
class WaiterTableCard extends StatelessWidget {
  final TableItem table;
  final String? ownerWaiterId;
  final String? ownerWaiterName;
  final String currentWaiterId;
  final int? guestCount;
  final VoidCallback onTap;

  const WaiterTableCard({
    super.key,
    required this.table,
    required this.currentWaiterId,
    required this.onTap,
    this.ownerWaiterId,
    this.ownerWaiterName,
    this.guestCount,
  });

  @override
  Widget build(BuildContext context) {
    final state = _resolveState();
    final palette = _paletteFor(context, state);
    final isInteractive =
        state != _CardState.otherWaiter; // muted tap still allowed, but no fill

    return Semantics(
      label: _semanticsLabel(),
      button: true,
      child: Material(
        color: palette.background,
        borderRadius: BorderRadius.circular(WaiterRadius.md + 2),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(WaiterRadius.md + 2),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WaiterRadius.md + 2),
              border: Border.all(
                color: palette.border,
                width: state == _CardState.mine ? 2 : 1.2,
              ),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(
              WaiterSpacing.md,
              WaiterSpacing.md,
              WaiterSpacing.md,
              WaiterSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, palette, state),
                const SizedBox(height: WaiterSpacing.sm),
                _meta(context, palette),
                const Spacer(),
                _footer(context, palette, state, isInteractive),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // State resolution
  // ---------------------------------------------------------------------------

  _CardState _resolveState() {
    if (table.isPaid) return _CardState.paid;
    if (table.status == TableStatus.printed) return _CardState.paymentPending;
    final hasOwner =
        ownerWaiterId != null && ownerWaiterId!.trim().isNotEmpty;
    if (!hasOwner && table.status == TableStatus.available) {
      return _CardState.free;
    }
    if (ownerWaiterId == currentWaiterId) return _CardState.mine;
    return _CardState.otherWaiter;
  }

  // ---------------------------------------------------------------------------
  // Building blocks
  // ---------------------------------------------------------------------------

  Widget _header(
    BuildContext context,
    _Palette palette,
    _CardState state,
  ) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(WaiterRadius.sm),
          ),
          alignment: Alignment.center,
          child: Icon(LucideIcons.armchair,
              size: WaiterSizes.iconMedium, color: palette.accent),
        ),
        const SizedBox(width: WaiterSpacing.sm),
        Expanded(
          child: Text(
            '${translationService.t('waiter_table')} ${table.number}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.title,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _statusBadge(palette, state),
      ],
    );
  }

  Widget _meta(BuildContext context, _Palette palette) {
    final occupiedMinutes = table.occupiedMinutes;
    final showGuests = guestCount != null && guestCount! > 0;
    return Row(
      children: [
        Icon(LucideIcons.users,
            size: WaiterSizes.iconSmall, color: palette.meta),
        const SizedBox(width: WaiterSpacing.xs),
        Text(
          showGuests ? '$guestCount' : '—',
          style: TextStyle(color: palette.meta, fontSize: 12),
        ),
        if (occupiedMinutes > 0) ...[
          const SizedBox(width: WaiterSpacing.md),
          Icon(LucideIcons.timer,
              size: WaiterSizes.iconSmall, color: palette.meta),
          const SizedBox(width: WaiterSpacing.xs),
          Text(
            '$occupiedMinutes ${translationService.t('min')}',
            style: TextStyle(color: palette.meta, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _footer(
    BuildContext context,
    _Palette palette,
    _CardState state,
    bool isInteractive,
  ) {
    if (state == _CardState.free) {
      return Row(
        children: [
          Icon(LucideIcons.circleDot,
              size: WaiterSizes.iconSmall, color: palette.accent),
          const SizedBox(width: WaiterSpacing.xs + 2),
          Text(
            translationService.t('waiter_table_free'),
            style: TextStyle(
              color: palette.accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }
    if (ownerWaiterName == null || ownerWaiterName!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        Icon(LucideIcons.user,
            size: WaiterSizes.iconSmall, color: palette.meta),
        const SizedBox(width: WaiterSpacing.xs + 2),
        Expanded(
          child: Text(
            ownerWaiterName!,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.meta,
              fontSize: 12,
              fontWeight:
                  state == _CardState.mine ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(_Palette palette, _CardState state) {
    final label = switch (state) {
      _CardState.free => translationService.t('waiter_status_open'),
      _CardState.mine => translationService.t('waiter_status_occupied'),
      _CardState.otherWaiter =>
        translationService.t('waiter_status_occupied'),
      _CardState.paid => translationService.t('waiter_status_paid'),
      _CardState.paymentPending =>
        translationService.t('waiter_status_paid'),
    };
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: WaiterSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(WaiterRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.accent,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  _Palette _paletteFor(BuildContext context, _CardState state) {
    switch (state) {
      case _CardState.free:
        return _Palette(
          accent: context.appSuccess,
          background: context.appCardBg,
          border: context.appSuccess.withValues(alpha: 0.35),
          title: context.appText,
          meta: context.appTextMuted,
        );
      case _CardState.mine:
        return _Palette(
          accent: context.appPrimary,
          background: context.appPrimary.withValues(alpha: 0.07),
          border: context.appPrimary,
          title: context.appText,
          meta: context.appText,
        );
      case _CardState.otherWaiter:
        return _Palette(
          accent: Colors.blueAccent,
          background: context.appSurface,
          border: context.appBorder,
          title: context.appTextMuted,
          meta: context.appTextMuted,
        );
      case _CardState.paid:
      case _CardState.paymentPending:
        return _Palette(
          accent: const Color(0xFFF59E0B),
          background: context.appCardBg,
          border: const Color(0xFFF59E0B).withValues(alpha: 0.4),
          title: context.appText,
          meta: context.appTextMuted,
        );
    }
  }

  String _semanticsLabel() {
    final baseline =
        '${translationService.t('waiter_table')} ${table.number}';
    final owner = (ownerWaiterName?.isNotEmpty ?? false)
        ? ' — ${ownerWaiterName!}'
        : '';
    return baseline + owner;
  }
}

enum _CardState { free, mine, otherWaiter, paid, paymentPending }

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
