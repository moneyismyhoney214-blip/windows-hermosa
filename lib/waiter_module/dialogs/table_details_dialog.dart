import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../dialogs/payment_tender_dialog.dart';
import '../../locator.dart';
import '../../models.dart';
import '../../services/api/api_constants.dart';
import '../../services/app_themes.dart';
import '../../services/language_service.dart';
import '../models/waiter_table_event.dart';
import '../services/waiter_billing_service.dart';
import '../services/waiter_controller.dart';
import '../services/waiter_table_registry.dart';

/// Cashier-facing dialog that shows a live view of what the waiter has
/// ordered for a given table: guest count, waiter, per-item list, totals
/// and payment status.
///
/// The cashier can also **create the invoice** and run the payment flow
/// from here (when the waiter hasn't done it from their side yet) —
/// reuses the same [WaiterBillingService] the waiter uses so the result
/// is identical on the backend.
class TableDetailsDialog extends StatefulWidget {
  final TableItem table;
  final WaiterTableSnapshot snapshot;

  const TableDetailsDialog({
    super.key,
    required this.table,
    required this.snapshot,
  });

  @override
  State<TableDetailsDialog> createState() => _TableDetailsDialogState();
}

class _TableDetailsDialogState extends State<TableDetailsDialog> {
  final WaiterBillingService _billing = getIt<WaiterBillingService>();
  final WaiterController _controller = getIt<WaiterController>();
  final WaiterTableRegistry _registry = getIt<WaiterTableRegistry>();

  bool _working = false;

  /// Booking id that an earlier attempt left behind on the backend (e.g.
  /// booking succeeded but card was declined). Re-used when the cashier
  /// tries again so we don't accumulate ghost bookings.
  String? _pendingBookingId;

  @override
  void initState() {
    super.initState();
    // Rebuild when the waiter adds/edits items or the payment status
    // flips — otherwise the cashier stares at a frozen snapshot.
    _registry.addListener(_onRegistry);
  }

  @override
  void dispose() {
    _registry.removeListener(_onRegistry);
    super.dispose();
  }

  void _onRegistry() {
    if (mounted) setState(() {});
  }

  String get tableNumber => widget.table.number;

  /// Always prefer the live registry entry; fall back to the snapshot
  /// captured when the dialog opened in case the waiter went offline
  /// and the registry cleared mid-view.
  WaiterTableSnapshot get snapshot =>
      _registry.lookup(widget.table.id) ?? widget.snapshot;

  @override
  Widget build(BuildContext context) {
    final items = snapshot.items;
    return Dialog(
      backgroundColor: context.appSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.appPrimary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(LucideIcons.receipt,
                        color: context.appPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${translationService.t('waiter_table')} $tableNumber',
                          style: TextStyle(
                            color: context.appText,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${translationService.t('waiter_served_by')}: ${snapshot.waiterName}',
                          style: TextStyle(
                            color: context.appTextMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _paymentPill(context),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _meta(context, LucideIcons.users,
                      '${snapshot.guestCount ?? '—'} ${translationService.t('waiter_guests_short')}'),
                  _meta(context, LucideIcons.utensils,
                      '${snapshot.itemCount ?? items.length} ${translationService.t('waiter_items_short')}'),
                ],
              ),
              const Divider(height: 24),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      translationService.t('waiter_no_items_yet'),
                      style: TextStyle(color: context.appTextMuted),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: context.appDivider),
                    itemBuilder: (_, i) {
                      final it = items[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${it.quantity.toStringAsFixed(it.quantity == it.quantity.toInt() ? 0 : 1)}×',
                              style: TextStyle(
                                color: context.appTextMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    it.name,
                                    style: TextStyle(color: context.appText),
                                  ),
                                  if (it.note != null && it.note!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        it.note!,
                                        style: TextStyle(
                                          color: context.appPrimary,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              it.lineTotal.toStringAsFixed(2),
                              style: TextStyle(
                                color: context.appText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const Divider(height: 24),
              Row(
                children: [
                  Text(
                    translationService.t('waiter_total'),
                    style: TextStyle(
                      color: context.appText,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(snapshot.total ?? 0).toStringAsFixed(2)} ${ApiConstants.currency}',
                    style: TextStyle(
                      color: context.appPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: _working
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.appText,
                          side: BorderSide(color: context.appBorder),
                        ),
                        child: Text(translationService.t('waiter_close')),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 44,
                      child: FilledButton.icon(
                        onPressed: (_working ||
                                items.isEmpty ||
                                snapshot.paid)
                            ? null
                            : _createInvoice,
                        style: FilledButton.styleFrom(
                          backgroundColor: context.appPrimary,
                          foregroundColor: Colors.white,
                        ),
                        icon: _working
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(LucideIcons.receipt),
                        label: Text(
                          snapshot.paid
                              ? translationService.t('waiter_status_paid')
                              : translationService.t('waiter_create_invoice'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createInvoice() async {
    if (snapshot.items.isEmpty) return;
    // Pull the latest enabled pay methods + tax config from branch
    // settings — mirrors the cashier's behavior on opening the tender dialog.
    await _billing.refreshPayMethods();
    if (!mounted) return;
    final subtotal = snapshot.total ?? _computedTotal();
    // Send tax-inclusive total so pays match invoice total on first try.
    final total = _billing.applyTax(subtotal);
    final pays = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => PaymentTenderDialog(
        total: total,
        enabledMethods: _billing.enabledPaymentMethods(),
        onConfirm: () {},
        onConfirmWithPays: (p) => Navigator.of(context).pop(p),
      ),
    );
    if (pays == null || pays.isEmpty) return;

    setState(() => _working = true);
    final result = await _billing.processBillFromSnapshot(
      table: widget.table,
      items: snapshot.items,
      guests: snapshot.guestCount ?? 1,
      waiterName: snapshot.waiterName,
      pays: pays,
      existingBookingId: _pendingBookingId,
    );
    if (!mounted) return;
    setState(() => _working = false);
    // Remember a partial booking so the next retry doesn't dup it; clear
    // when the flow completes successfully.
    _pendingBookingId = result.success ? null : result.bookingId;

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.appDanger,
          content: Text(
            '${translationService.t('waiter_bill_failed')}: ${result.errorMessage ?? ''}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }

    // Broadcast lifecycle so the waiter's card also updates to "paid".
    final payLater = result.paymentMethod == 'pay_later';
    final me = _controller.session.self;
    if (me != null) {
      _controller.broadcastTableEvent(TableLifecycleEvent(
        kind: payLater
            ? TableLifecycleKind.paymentPending
            : TableLifecycleKind.paid,
        tableId: widget.table.id,
        tableNumber: widget.table.number,
        waiterId: snapshot.waiterId,
        waiterName: snapshot.waiterName,
        guestCount: snapshot.guestCount,
        total: snapshot.total ?? _computedTotal(),
        itemCount: snapshot.itemCount,
        items: snapshot.items,
        orderId: result.bookingId,
      ));
      // After a fully paid invoice we also release the table so the
      // registry entry goes back to "free" — otherwise the row sits at
      // `paid=true` forever and blocks the next customer. Pay-later keeps
      // the table open because money hasn't been collected yet.
      if (!payLater) {
        _controller.broadcastTableEvent(TableLifecycleEvent(
          kind: TableLifecycleKind.released,
          tableId: widget.table.id,
          tableNumber: widget.table.number,
          waiterId: snapshot.waiterId,
          waiterName: snapshot.waiterName,
        ));
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: context.appSuccess,
        content: Text(
          payLater
              ? translationService.t('waiter_bill_pending')
              : translationService.t('waiter_bill_done'),
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  double _computedTotal() =>
      snapshot.items.fold<double>(0, (s, it) => s + it.lineTotal);

  Widget _meta(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.appTextMuted),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: context.appTextMuted, fontSize: 12)),
      ],
    );
  }

  Widget _paymentPill(BuildContext context) {
    final (label, color) = snapshot.paid
        ? (translationService.t('waiter_status_paid'), context.appSuccess)
        : snapshot.paymentPending
            ? (translationService.t('waiter_pay_pending'), context.appPrimary)
            : (translationService.t('waiter_open_bill'), context.appTextMuted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
