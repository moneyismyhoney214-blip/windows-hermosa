import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/waiter_module/models/waiter_table_event.dart';
import 'package:hermosa_pos/waiter_module/services/waiter_table_registry.dart';

/// Lifecycle / reconcile tests for [WaiterTableRegistry].
///
/// The registry drives the tables-grid card colour: when its row disappears
/// for a table, the card flips back to green. The hard-won invariant these
/// tests pin down is that **a waiter's own draft (cart has items, no backend
/// booking yet) must survive a [reconcileWithBackend] pass** — otherwise a
/// pull-to-refresh while the waiter is mid-order silently wipes their
/// claim and re-opens the table to anyone.
void main() {
  TableLifecycleEvent evt(
    TableLifecycleKind kind, {
    String tableId = 't1',
    String tableNumber = '1',
    String waiterId = 'w-self',
    String waiterName = 'Self',
    int? itemCount,
    double? total,
    String? orderId,
    List<TableItemSnapshot>? items,
  }) =>
      TableLifecycleEvent(
        kind: kind,
        tableId: tableId,
        tableNumber: tableNumber,
        waiterId: waiterId,
        waiterName: waiterName,
        itemCount: itemCount,
        total: total,
        orderId: orderId,
        items: items,
      );

  group('apply() — tap-and-add lifecycle', () {
    test('takingOrder → updated keeps the waiter as owner', () {
      // Models the exact "tap green table → add first item" flow that was
      // dropping the owner before the selfDraft guard was added.
      final r = WaiterTableRegistry();

      r.apply(evt(TableLifecycleKind.takingOrder));
      expect(r.ownerIdFor('t1'), 'w-self');
      expect(r.takingOrderFor('t1'), isTrue);

      r.apply(evt(
        TableLifecycleKind.updated,
        itemCount: 2,
        total: 10.0,
        items: [
          TableItemSnapshot(name: 'Latte', quantity: 1, unitPrice: 5),
          TableItemSnapshot(name: 'Croissant', quantity: 1, unitPrice: 5),
        ],
      ));

      // Owner preserved, takingOrder cleared, itemCount mirrored.
      expect(r.ownerIdFor('t1'), 'w-self');
      expect(r.takingOrderFor('t1'), isFalse);
      expect(r.itemCountFor('t1'), 2);
      expect(r.bookingIdFor('t1'), isNull, reason: 'no backend booking yet');
    });

    test('released drops the row entirely', () {
      final r = WaiterTableRegistry();
      r.apply(evt(TableLifecycleKind.takingOrder));
      r.apply(evt(TableLifecycleKind.released));
      expect(r.lookup('t1'), isNull);
    });
  });

  group('reconcileWithBackend() — eviction policy', () {
    test('self-owned draft with items is PRESERVED when backend says available', () {
      // The regression: a waiter mid-compose pops back to the tables grid;
      // _load() calls getTables() which (correctly) reports the table as
      // available because no booking exists yet. The reconcile must not
      // wipe the waiter's own draft — the cart still holds items locally.
      final r = WaiterTableRegistry();
      r.apply(evt(TableLifecycleKind.takingOrder));
      r.apply(evt(
        TableLifecycleKind.updated,
        itemCount: 1,
        items: [TableItemSnapshot(name: 'Tea', quantity: 1, unitPrice: 3)],
      ));

      r.reconcileWithBackend(const ['t1'], selfId: 'w-self');

      expect(r.ownerIdFor('t1'), 'w-self',
          reason: 'self-owned draft must survive reconcile');
      expect(r.itemCountFor('t1'), 1);
    });

    test('peer-owned draft with items is EVICTED when backend says available', () {
      // Mirror of the above for a peer's row on this device. The cart is
      // on the peer's device; if the backend doesn't see a booking, this
      // device should let the row go and refresh on next broadcast.
      final r = WaiterTableRegistry();
      r.apply(evt(
        TableLifecycleKind.updated,
        waiterId: 'w-peer',
        waiterName: 'Peer',
        itemCount: 1,
        items: [TableItemSnapshot(name: 'Tea', quantity: 1, unitPrice: 3)],
      ));

      r.reconcileWithBackend(const ['t1'], selfId: 'w-self');

      expect(r.lookup('t1'), isNull,
          reason: 'peer drafts without a backend booking are evicted');
    });

    test('self-owned committed booking survives reconcile (selfCommitted)', () {
      // Booking is on the backend but the table-list call lagged behind —
      // don't evict our own pay-later row just because getTables() hasn't
      // caught up to the booking write.
      final r = WaiterTableRegistry();
      r.apply(evt(
        TableLifecycleKind.paymentPending,
        orderId: 'b-123',
        itemCount: 3,
        total: 30.0,
      ));

      r.reconcileWithBackend(const ['t1'], selfId: 'w-self');

      expect(r.ownerIdFor('t1'), 'w-self');
      expect(r.paymentPendingFor('t1'), isTrue);
      expect(r.bookingIdFor('t1'), 'b-123');
    });

    test('peer-owned paid row is evicted when evictCommitted: true', () {
      final r = WaiterTableRegistry();
      r.apply(evt(
        TableLifecycleKind.paid,
        waiterId: 'w-peer',
        waiterName: 'Peer',
        orderId: 'b-999',
      ));

      r.reconcileWithBackend(
        const ['t1'],
        selfId: 'w-self',
      );

      expect(r.lookup('t1'), isNull);
    });

    test('committed rows are preserved when evictCommitted: false (cashier path)', () {
      // The cashier passes evictCommitted: false so a momentarily-stale
      // getTables read can't drop a pay-later booking it just saw broadcast.
      final r = WaiterTableRegistry();
      r.apply(evt(
        TableLifecycleKind.paymentPending,
        waiterId: 'w-peer',
        waiterName: 'Peer',
        orderId: 'b-77',
      ));

      r.reconcileWithBackend(
        const ['t1'],
        selfId: 'cashier',
        evictCommitted: false,
      );

      expect(r.ownerIdFor('t1'), 'w-peer');
      expect(r.paymentPendingFor('t1'), isTrue);
    });

    test('takingOrder is preserved while the order screen is open', () {
      final r = WaiterTableRegistry();
      r.apply(evt(TableLifecycleKind.takingOrder));

      r.reconcileWithBackend(
        const ['t1'],
        selfId: 'w-self',
        activeOrderingTableId: 't1',
      );

      expect(r.ownerIdFor('t1'), 'w-self');
      expect(r.takingOrderFor('t1'), isTrue);
    });

    test('rows for tables NOT in availableTableIds are never touched', () {
      // Reconcile only acts on the IDs the backend is currently reporting
      // as available — an unrelated occupied table must not be evicted.
      final r = WaiterTableRegistry();
      r.apply(evt(TableLifecycleKind.takingOrder, tableId: 't2'));

      r.reconcileWithBackend(const ['t1'], selfId: 'w-self');

      expect(r.ownerIdFor('t2'), 'w-self');
    });

    test('an empty registry is a no-op (no listener storm)', () {
      final r = WaiterTableRegistry();
      var fired = 0;
      r.addListener(() => fired++);

      r.reconcileWithBackend(const ['t1', 't2'], selfId: 'w-self');

      expect(fired, 0);
    });
  });

  group('clearForWaiter() / dropTakingOrderForWaiter()', () {
    test('clearForWaiter removes only rows belonging to that waiter', () {
      final r = WaiterTableRegistry();
      r.apply(evt(TableLifecycleKind.takingOrder, tableId: 't1', waiterId: 'a'));
      r.apply(evt(TableLifecycleKind.takingOrder, tableId: 't2', waiterId: 'b'));

      r.clearForWaiter('a');

      expect(r.lookup('t1'), isNull);
      expect(r.ownerIdFor('t2'), 'b');
    });

    test('dropTakingOrderForWaiter spares their committed rows', () {
      // A waiter who walked away mid-compose should lose the transient pill
      // but keep their pay-later / paid rows so the cashier can still close
      // them out.
      final r = WaiterTableRegistry();
      r.apply(evt(TableLifecycleKind.takingOrder, tableId: 't1', waiterId: 'a'));
      r.apply(evt(
        TableLifecycleKind.paymentPending,
        tableId: 't2',
        waiterId: 'a',
        orderId: 'b-1',
      ));

      r.dropTakingOrderForWaiter('a');

      expect(r.lookup('t1'), isNull);
      expect(r.paymentPendingFor('t2'), isTrue);
      expect(r.bookingIdFor('t2'), 'b-1');
    });
  });
}
