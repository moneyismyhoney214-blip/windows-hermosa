import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../locator.dart';
import '../../models.dart';
import '../../services/api/table_service.dart';
import '../../services/app_themes.dart';
import '../../services/language_service.dart';
import '../models/waiter_table_event.dart';
import '../services/waiter_billing_service.dart';
import '../services/waiter_cart_store.dart';
import '../services/waiter_controller.dart';
import '../services/waiter_table_registry.dart';
import '../theme/waiter_design.dart';
import '../widgets/skeleton_grid.dart';
import '../widgets/waiter_table_card.dart';
import 'waiter_order_screen.dart';

/// Grid view of every table in the branch, with ownership and status
/// overlaid from the live [WaiterTableRegistry].
class WaiterTablesScreen extends StatefulWidget {
  final WaiterController controller;

  const WaiterTablesScreen({super.key, required this.controller});

  @override
  State<WaiterTablesScreen> createState() => _WaiterTablesScreenState();
}

class _WaiterTablesScreenState extends State<WaiterTablesScreen> {
  final TableService _tableService = getIt<TableService>();
  final WaiterTableRegistry _registry = getIt<WaiterTableRegistry>();

  List<TableItem> _tables = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _registry.addListener(_onRegistry);
    // Registry application now lives in WaiterController (for both
    // incoming and self-broadcast paths) so every device stays in
    // sync. We only need to listen for the ChangeNotifier signal
    // above to trigger a rebuild; no need to apply here.
  }

  @override
  void dispose() {
    _registry.removeListener(_onRegistry);
    super.dispose();
  }

  void _onRegistry() {
    if (!mounted) return;
    // Registry notifications can fire mid-build — e.g. opening the order
    // screen broadcasts a "taking order" lifecycle event during its
    // initState, which reaches WaiterTableRegistry.apply() and notifies
    // us while this screen is still in the same frame's build pass.
    // Defer the rebuild to the next frame so setState doesn't land
    // inside someone else's build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// Keep every table visible — including ones the current waiter has
  /// already submitted (pay-later, paid-still-seated). The card's
  /// status pill + inline CTAs ("Edit Order", "تحرير الطاولة") signal
  /// what's still actionable. Hiding owned pay-later tables would
  /// strand the Edit Order button on a card the waiter can't reach.
  List<TableItem> _visibleTables() => _tables;

  void _releaseTable(TableItem table) {
    final me = widget.controller.session.self;
    if (me == null) return;
    widget.controller.broadcastTableEvent(TableLifecycleEvent(
      kind: TableLifecycleKind.released,
      tableId: table.id,
      tableNumber: table.number,
      waiterId: me.id,
      waiterName: me.name,
    ));
    // Local cart flush so re-entering a freshly-released table doesn't
    // resurface stale items from the previous party.
    try {
      getIt<WaiterCartStore>().clearTable(table.id);
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم تحرير الطاولة ${table.number}'),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tables = await _tableService.getTables();
      if (!mounted) return;
      setState(() {
        _tables = tables
            .where((t) => t.isActive)
            .toList()
          ..sort((a, b) {
            final aNum = int.tryParse(a.number) ?? 0;
            final bNum = int.tryParse(b.number) ?? 0;
            return aNum.compareTo(bNum);
          });
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _openTable(TableItem table) {
    final me = widget.controller.session.self;
    if (me == null) return;

    final ownerId = _registry.ownerIdFor(table.id);
    if (ownerId != null && ownerId != me.id) {
      _showBorrowDialog(table, ownerId);
      return;
    }

    // Backend-locked path: the cashier (or another device outside the
    // waiter mesh) opened this table so the server marks it occupied/
    // printed even though our in-memory registry has no owner. Tapping
    // through would let the waiter start a second party on a seated
    // table. Same rule the cashier's screen enforces via
    // _checkTableStatus → "الطاولة محجوزة / غير متاحة".
    if (ownerId == null && table.status != TableStatus.available) {
      _showBackendLockedDialog(table);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WaiterOrderScreen(
          table: table,
          controller: widget.controller,
        ),
      ),
    );
  }

  Future<void> _migrateTable(TableItem source) async {
    final me = widget.controller.session.self;
    if (me == null) return;

    // The waiter can only migrate a table they own — the card-level guard
    // enforces this, but we re-check here so a stale onMigrate callback
    // firing after ownership change doesn't slip through.
    final ownerId = _registry.ownerIdFor(source.id);
    if (ownerId != me.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا تملك هذه الطاولة — لا يمكن نقلها.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Destinations: tables not owned by any waiter AND backend-status is
    // available. Skip self + inactive tables.
    final destinations = _tables.where((t) {
      if (t.id == source.id) return false;
      if (!t.isActive) return false;
      if (_registry.ownerIdFor(t.id) != null) return false;
      return t.status == TableStatus.available;
    }).toList();

    if (destinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد طاولة فاضية للنقل إليها.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final picked = await showDialog<TableItem>(
      context: context,
      builder: (_) => _WaiterMigrateDestinationDialog(
        source: source,
        destinations: destinations,
      ),
    );
    if (picked == null) return;
    if (!mounted) return;

    // Re-validate right before broadcasting — between open and pick a
    // peer may have claimed the destination.
    final stillFree = _registry.ownerIdFor(picked.id) == null;
    if (!stillFree) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'الطاولة ${picked.number} لم تعد متاحة — النقل ملغي.',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Persist the move on the backend first — without this, the booking
    // stays pinned to the old table server-side and the next getTables()
    // refresh reverts the view. Mirrors the cashier's edit-order path of
    // PATCHing the booking via updateBookingItems with the new table_id
    // and table_name in type_extra.
    final existingBookingId = _registry.bookingIdFor(source.id);
    final cart = getIt<WaiterCartStore>();
    final carriedItems = cart.allItemsFor(source.id);
    final carriedGuests = _registry.guestCountFor(source.id);
    var backendMoved = false;
    if (existingBookingId != null) {
      try {
        await getIt<WaiterBillingService>().updateBookingItems(
          bookingId: existingBookingId,
          table: picked,
          items: carriedItems,
          guests: carriedGuests,
        );
        backendMoved = true;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر نقل الحجز على الخادم: $e'),
            backgroundColor: const Color(0xFFDC2626),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    try {
      widget.controller.migrateTable(
        oldTableId: source.id,
        oldTableNumber: source.number,
        newTableId: picked.id,
        newTableNumber: picked.number,
      );
    } on StateError catch (e) {
      // Mesh-side guard rejected the migrate after the backend had
      // already accepted the move. Roll the booking back to the source
      // table so the two layers don't diverge — otherwise a refresh
      // would show the booking under `picked` while the waiter mesh
      // still treats `source` as the owner.
      if (backendMoved && existingBookingId != null) {
        try {
          await getIt<WaiterBillingService>().updateBookingItems(
            bookingId: existingBookingId,
            table: source,
            items: carriedItems,
            guests: carriedGuests,
          );
        } catch (rollbackError) {
          debugPrint(
              '⚠️ Migrate rollback failed — booking is on ${picked.number} '
              'server-side but mesh rejected the shuffle: $rollbackError');
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر نقل الطاولة: $e')),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم نقل الطاولة ${source.number} إلى ${picked.number}',
        ),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showBackendLockedDialog(TableItem table) {
    final isReserved = table.status == TableStatus.occupied;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.appSurface,
        title: Row(
          children: [
            Icon(LucideIcons.lock, color: context.appDanger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isReserved
                    ? translationService.t('table_occupied')
                    : translationService.t('table_unavailable'),
                style: TextStyle(color: context.appText),
              ),
            ),
          ],
        ),
        content: Text(
          translationService.t(
            'waiter_table_backend_locked_body',
            args: {'table': table.number},
          ),
          style: TextStyle(color: context.appText),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.appPrimary),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(translationService.t('waiter_close')),
          ),
        ],
      ),
    );
  }

  void _showBorrowDialog(TableItem table, String ownerId) {
    // Waiter-to-waiter calls are disabled — only the cashier rings the
    // bell. We still show an info dialog so the tapping waiter knows
    // the table is taken instead of letting them silently overwrite.
    final owner = widget.controller.roster.byId(ownerId);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.appSurface,
        title: Text(translationService.t('waiter_table_owned_title')),
        content: Text(
          translationService.t(
            'waiter_table_owned_body',
            args: {
              'table': table.number,
              'name': owner?.name ?? '—',
            },
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.appPrimary),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(translationService.t('waiter_close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SkeletonTablesGrid();
    }
    if (_error != null) {
      return _ErrorView(onRetry: _load, error: _error!);
    }
    if (_tables.isEmpty) {
      return _EmptyView(onRefresh: _load);
    }
    return RefreshIndicator(
      color: context.appPrimary,
      onRefresh: _load,
      child: LayoutBuilder(builder: (_, constraints) {
        // Pick card size based on viewport:
        //   phone (<420)  → 1 column, shorter card so the content fits
        //   tablet / split → 2+ columns of ~220dp
        //   expanded → 240dp cards, slightly wider aspect
        final w = constraints.maxWidth;
        final double maxExtent;
        final double aspect;
        if (w < 420) {
          maxExtent = w;
          aspect = 1.6;
        } else if (w < 900) {
          maxExtent = 220;
          aspect = 1.35;
        } else {
          maxExtent = 240;
          aspect = 1.3;
        }
        return GridView.builder(
          padding: const EdgeInsets.all(WaiterSpacing.md),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxExtent,
            mainAxisSpacing: WaiterSpacing.sm + 2,
            crossAxisSpacing: WaiterSpacing.sm + 2,
            childAspectRatio: aspect,
          ),
          // Owner-hide rule: a waiter who has already submitted a
          // "Pay Later" order shouldn't still see that table in their
          // active grid — their work is done. Peers still see it as
          // "Order Taken" (locked). Derived here so the grid
          // re-renders whenever ownership/payment state changes.
          itemCount: _visibleTables().length,
          itemBuilder: (_, i) {
            final t = _visibleTables()[i];
            final ownerId = _registry.ownerIdFor(t.id);
            final ownerName = _registry.ownerNameFor(t.id) ??
                (ownerId != null
                    ? widget.controller.roster.byId(ownerId)?.name
                    : null);
            // Mirror the registry's ownership onto the TableItem's status
            // so the card colors match even before the backend reflects
            // it — but when no mesh owner is set, preserve whatever the
            // backend already reports (occupied / printed / available).
            // Forcing everything to "available" here is what made the
            // waiter see a table as free while the cashier's screen had
            // it locked as "غير متاحة" (e.g. order created cashier-side).
            final overlaid = t
              ..status =
                  ownerId != null ? TableStatus.occupied : t.status
              ..waiterName = ownerName ?? t.waiterName;
            final isMine = ownerId != null &&
                ownerId == widget.controller.session.self!.id;
            final paymentPending = _registry.paymentPendingFor(t.id);
            return WaiterTableCard(
              // Stable per-table key lets Flutter reuse the underlying
              // Element + State when the grid re-sorts (e.g. a peer
              // HELLO shuffles ownership); without this the list can
              // rebuild cards from scratch and flicker scroll state.
              key: ValueKey('waiter_table_${t.id}'),
              table: overlaid,
              currentWaiterId: widget.controller.session.self!.id,
              ownerWaiterId: ownerId,
              ownerWaiterName: ownerName,
              guestCount: _registry.guestCountFor(t.id),
              isTakingOrder: _registry.takingOrderFor(t.id),
              paymentPending: paymentPending,
              // Only expose "نقل إلى طاولة أخرى" on tables this waiter
              // actually owns and that aren't already paid/closed —
              // migrating a paid bill is a backend-hostile no-op.
              onMigrate: (isMine && !t.isPaid) ? () => _migrateTable(t) : null,
              // Edit Order surfaces only on tables this waiter owns AND
              // that have an active pay-later booking. Tapping reopens
              // the order screen so the waiter can add/modify items —
              // same semantics as the cashier's "تعديل الطلب" button.
              onEditOrder: (isMine && paymentPending)
                  ? () => _openTable(t)
                  : null,
              // Release Table: any table owned by me that's occupied
              // (including paid-but-still-seated). Lets the waiter
              // manually mark it "available" when guests leave.
              onReleaseTable: isMine ? () => _releaseTable(t) : null,
              onTap: () => _openTable(t),
            );
          },
        );
      }),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final Object error;
  const _ErrorView({required this.onRetry, required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.alertCircle,
              size: 42, color: context.appDanger),
          const SizedBox(height: 8),
          Text(translationService.t('waiter_tables_load_failed'),
              style: TextStyle(color: context.appText)),
          const SizedBox(height: 4),
          Text('$error',
              style: TextStyle(color: context.appTextMuted, fontSize: 12)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.rotateCcw),
            label: Text(translationService.t('waiter_retry')),
          ),
        ],
      ),
    );
  }
}

/// Grid picker shown to the waiter so they can choose which empty table
/// to relocate the current party to.
class _WaiterMigrateDestinationDialog extends StatelessWidget {
  final TableItem source;
  final List<TableItem> destinations;

  const _WaiterMigrateDestinationDialog({
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
              'نقل الطاولة ${source.number} إلى...',
              style: TextStyle(color: context.appText, fontSize: 17),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        height: 320,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 120,
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
                        color: context.appSuccess, size: 26),
                    const SizedBox(height: 6),
                    Text(
                      t.number,
                      style: TextStyle(
                        color: context.appText,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${t.seats} أشخاص',
                      style: TextStyle(
                        color: context.appTextMuted,
                        fontSize: 10,
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
          child: Text(translationService.t('waiter_cancel')),
        ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyView({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.armchair,
              size: 42, color: context.appTextMuted),
          const SizedBox(height: 8),
          Text(translationService.t('waiter_tables_empty'),
              style: TextStyle(color: context.appText)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(LucideIcons.rotateCcw),
            label: Text(translationService.t('waiter_retry')),
          ),
        ],
      ),
    );
  }
}
