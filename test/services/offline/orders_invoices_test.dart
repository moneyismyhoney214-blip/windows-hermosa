@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Coverage for the local orders + invoices CRUD in
/// [OfflineDatabaseService]. The sync_service drain assumes these
/// invariants:
///   * `saveLocalOrder` inserts a row with is_synced=0, is_local=1
///   * `markOrderSynced` flips it to synced and stamps a server_id
///   * `getUnsyncedOrders` returns only locally-created rows that
///     haven't been confirmed by the server
///   * `saveServerOrder` upserts a server row as already-synced
///   * same for invoices
///
/// A regression here causes either silent revenue loss (rows missed
/// by the drain) or duplicate sends (rows drained more than once),
/// so these tests are load-bearing.
void main() {
  late OfflineDatabaseService service;

  late Directory tmpDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('hermosa_orders_inv_');
    OfflineDatabaseService.debugOverrideDbPath = '${tmpDir.path}/db.sqlite';

    final s = OfflineDatabaseService();
    await s.close();
    service = s;
    await service.database;
  });

  tearDown(() async {
    await service.close();
    OfflineDatabaseService.debugOverrideDbPath = null;
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  group('orders', () {
    test('saveLocalOrder inserts is_local=1, is_synced=0', () async {
      final id = await service.saveLocalOrder({
        'subtotal': 100,
        'tax': 15,
        'total': 115,
        'items': [{'meal_id': 1, 'qty': 2}],
        'pays': [{'pay_method': 'cash', 'amount': 115}],
        'type': 'dine_in',
      }, 42);

      expect(id, startsWith('local_'));

      final unsynced = await service.getUnsyncedOrders();
      expect(unsynced, hasLength(1));
      expect(unsynced.single['id'], id);
      expect(unsynced.single['is_local'], 1);
      expect(unsynced.single['is_synced'], 0);
      expect(unsynced.single['server_id'], isNull);
      expect(unsynced.single['total'], 115.0);
    });

    test('markOrderSynced flips is_synced=1 and stamps server_id', () async {
      final localId = await service.saveLocalOrder({'total': 50}, 1);
      await service.markOrderSynced(localId, 'srv-9876');

      final unsynced = await service.getUnsyncedOrders();
      expect(unsynced, isEmpty,
          reason: 'a synced row must not reappear in the drain set');

      final serverId = await service.getOrderServerId(localId);
      expect(serverId, 'srv-9876');
    });

    test('saveServerOrder upserts as already-synced, not drainable', () async {
      await service.saveServerOrder(
        {'id': 'srv-1', 'order_number': 'INV-100', 'total': 99},
        7,
      );
      expect(await service.getUnsyncedOrders(), isEmpty,
          reason: 'server-origin rows are pre-synced');

      final all = await service.getOrders(7);
      expect(all, hasLength(1));
      // raw_json is preserved + the convenience flags are injected.
      expect(all.first['_is_local'], isFalse);
      expect(all.first['_is_synced'], isTrue);
    });

    test('getUnsyncedOrders excludes server-origin rows', () async {
      await service.saveLocalOrder({'total': 10}, 1);
      await service.saveServerOrder(
        {'id': 'srv-x', 'order_number': 'N', 'total': 20},
        1,
      );
      // Drain set should contain only the local row.
      final unsynced = await service.getUnsyncedOrders();
      expect(unsynced, hasLength(1));
      expect((unsynced.single['id'] as String).startsWith('local_'), isTrue);
    });

    test('getOrders preserves chronological-desc order', () async {
      await service.saveServerOrder(
        {'id': 'a', 'created_at': '2026-01-01T00:00:00Z', 'total': 1},
        1,
      );
      await service.saveServerOrder(
        {'id': 'b', 'created_at': '2026-05-01T00:00:00Z', 'total': 2},
        1,
      );
      final orders = await service.getOrders(1);
      expect(orders.map((r) => r['id']).toList(), ['b', 'a']);
    });
  });

  group('invoices', () {
    test('saveLocalInvoice is drainable; markInvoiceSynced removes it',
        () async {
      final localId = await service.saveLocalInvoice({
        'total': 500,
        'type': 'services',
        'pays': [{'pay_method': 'card', 'amount': 500}],
      }, 7);
      expect(localId, startsWith('local_inv_'));

      final unsynced = await service.getUnsyncedInvoices();
      expect(unsynced, hasLength(1));
      expect(unsynced.single['id'], localId);

      await service.markInvoiceSynced(localId, 'srv-inv-1');
      expect(await service.getUnsyncedInvoices(), isEmpty);
    });

    test('saveServerInvoice + saveServerInvoices upsert + dedupe', () async {
      await service.saveServerInvoice(
        {'id': 'inv-1', 'total': 10, 'created_at': '2026-01-01T00:00:00Z'},
        1,
      );
      await service.saveServerInvoices(
        [
          {'id': 'inv-1', 'total': 25}, // upsert overwrites
          {'id': 'inv-2', 'total': 99},
        ],
        1,
      );

      final all = await service.getInvoices(1);
      expect(all, hasLength(2));
      final byId = {for (final r in all) r['id'] as String: r};
      expect((byId['inv-1']!['total'] as num).toDouble(), 25.0,
          reason: 'second saveServer* should replace the first');
    });
  });
}
