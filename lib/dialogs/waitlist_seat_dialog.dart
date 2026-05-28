import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/waitlist_entry.dart';
import '../services/app_themes.dart';
import '../services/language_service.dart';

/// What the host chose in [WaitlistSeatDialog].
enum WaitlistSeatChoice {
  /// Seat the party — mark them seated, bind the customer to the table and
  /// open the table for ordering.
  seat,

  /// Drop the hold — the party goes back to plain "waiting" and the table
  /// is freed again.
  cancelHold,
}

/// Shown when someone taps a table that is currently *held* for a
/// waitlisted party (status `notified`). The table is locked until the
/// host explicitly seats the party — there is no "just start ordering"
/// path while the hold is live, by design.
class WaitlistSeatDialog extends StatelessWidget {
  final WaitlistEntry entry;
  final String tableNumber;

  const WaitlistSeatDialog({
    super.key,
    required this.entry,
    required this.tableNumber,
  });

  static Future<WaitlistSeatChoice?> show(
    BuildContext context, {
    required WaitlistEntry entry,
    required String tableNumber,
  }) {
    return showDialog<WaitlistSeatChoice>(
      context: context,
      builder: (_) => WaitlistSeatDialog(entry: entry, tableNumber: tableNumber),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: context.appSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Directionality(
        textDirection:
            translationService.isRTL ? TextDirection.rtl : TextDirection.ltr,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      translationService.t(
                        'waitlist_seat_body',
                        args: {'table': tableNumber, 'name': entry.customerName},
                      ),
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: context.appText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _infoChips(context),
                  ],
                ),
              ),
              _footer(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF59E0B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.lock, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              translationService.t('waitlist_seat_title'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(LucideIcons.x, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _infoChips(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appSurfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        children: [
          _chip(
            context,
            icon: LucideIcons.user,
            label: translationService.t('waitlist_field_name'),
            value: entry.customerName,
          ),
          Container(
            width: 1,
            height: 30,
            color: context.appBorder,
            margin: const EdgeInsets.symmetric(horizontal: 10),
          ),
          _chip(
            context,
            icon: LucideIcons.users,
            label: translationService.t('waitlist_field_party_size'),
            value: '${entry.partySize}',
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: context.appTextMuted),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: context.appTextMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: context.appText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.appBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(WaitlistSeatChoice.cancelHold),
              icon: const Icon(LucideIcons.userX, size: 16),
              label: Text(translationService.t('waitlist_seat_cancel_hold')),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(WaitlistSeatChoice.seat),
              icon: const Icon(LucideIcons.checkCircle2, size: 16),
              label: Text(translationService.t('waitlist_seat_confirm')),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
