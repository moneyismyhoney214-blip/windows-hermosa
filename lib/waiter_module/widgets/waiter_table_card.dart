import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models.dart';
import '../../services/app_themes.dart';
import '../../services/language_service.dart';

/// Visual card representing one table in the waiter's grid.
///
/// Colors:
///   * green — available (no one seated)
///   * orange — occupied (this waiter owns it)
///   * blue — occupied by another waiter
///   * gray — inactive / disabled
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
    final isMine = ownerWaiterId == currentWaiterId;
    final isOccupied = table.status != TableStatus.available;

    final accent = !isOccupied
        ? context.appSuccess
        : (isMine ? context.appPrimary : Colors.blueAccent);

    return Material(
      color: context.appCardBg,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.5),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.armchair, color: accent, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${translationService.t('waiter_table')} ${table.number}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appText,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _statusBadge(context, accent, isOccupied),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(LucideIcons.users, size: 14, color: context.appTextMuted),
                  const SizedBox(width: 4),
                  Text(
                    // Waiter-set guest count is the source of truth —
                    // backend `seats` is capacity, not "how many are seated".
                    guestCount != null && guestCount! > 0 ? '$guestCount' : '—',
                    style: TextStyle(color: context.appTextMuted, fontSize: 12),
                  ),
                  if (table.occupiedMinutes > 0) ...[
                    const SizedBox(width: 10),
                    Icon(LucideIcons.timer,
                        size: 14, color: context.appTextMuted),
                    const SizedBox(width: 4),
                    Text(
                      '${table.occupiedMinutes} ${translationService.t('min')}',
                      style: TextStyle(
                          color: context.appTextMuted, fontSize: 12),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              if (ownerWaiterName != null && ownerWaiterName!.isNotEmpty)
                Row(
                  children: [
                    Icon(LucideIcons.user,
                        size: 14, color: context.appTextMuted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        ownerWaiterName!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.appTextMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  translationService.t('waiter_table_free'),
                  style: TextStyle(
                    color: context.appSuccess,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(BuildContext context, Color accent, bool isOccupied) {
    final label = !isOccupied
        ? translationService.t('waiter_status_open')
        : (table.isPaid
            ? translationService.t('waiter_status_paid')
            : translationService.t('waiter_status_occupied'));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
