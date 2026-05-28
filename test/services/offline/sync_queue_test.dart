@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Tests for the offline sync queue inside [OfflineDatabaseService].
///
/// The audit flagged the sync queue's enqueue / retry / max-retry / dedup
/// path as zero-coverage despite being how every offline write reaches
/// the backend. A bug here loses real revenue.
///
/// We use `sqflite_common_ffi` (already a runtime dep for the desktop
/// build) to get a real SQLite engine in the test process. The
/// singleton is closed between tests so each one starts on a fresh
/// database file.
void main() {
  late OfflineDatabaseService service;

  late Directory tmpDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Every test gets a fresh DB in a unique temp dir so concurrent
    // test files don't step on each other's bytes (which produced
    // "attempt to write a readonly database" errors before we added
    // the per-test path override).
    tmpDir = await Directory.systemTemp.createTemp('hermosa_sync_queue_');
    OfflineDatabaseService.debugOverrideDbPath = '${tmpDir.path}/db.sqlite';

    final s = OfflineDatabaseService();
    await s.close();
    service = s;
    await service.database; // lazy init
  });

  tearDown(() async {
    await service.close();
    OfflineDatabaseService.debugOverrideDbPath = null;
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  group('addToSyncQueue', () {
    test('persists a pending row with retries=0 and the JSON payload', () async {
      final id = await service.addToSyncQueue(
        operation: 'create_invoice',
        endpoint: '/seller/branches/1/invoices',
        method: 'POST',
        payload: {'total': 12.34},
        localRefTable: 'invoices',
        localRefId: 'local-xyz',
      );
      expect(id, greaterThan(0));

      final pending = await service.getPendingSyncItems();
      expect(pending, hasLength(1));
      final row = pending.single;
      expect(row['operation'], 'create_invoice');
      expect(row['method'], 'POST');
      expect(row['status'], 'pending');
      expect(row['retries'], 0);
      expect(row['max_retries'], 5);
      expect(row['local_ref_id'], 'local-xyz');
      expect(row['payload'], contains('12.34'));
    });

    test('null payload is stored as NULL not as the string "null"', () async {
      await service.addToSyncQueue(
        operation: 'logout',
        endpoint: '/logout',
        method: 'POST',
      );
      final pending = await service.getPendingSyncItems();
      expect(pending.single['payload'], isNull);
    });
  });

  group('getPendingSyncItems ordering', () {
    test('returns rows oldest-first so FIFO drain is preserved', () async {
      // Insert with explicit small delays so the created_at timestamps
      // actually differ — sqflite stores them as ISO8601 strings.
      await service.addToSyncQueue(
          operation: 'op1', endpoint: '/a', method: 'POST');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await service.addToSyncQueue(
          operation: 'op2', endpoint: '/b', method: 'POST');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await service.addToSyncQueue(
          operation: 'op3', endpoint: '/c', method: 'POST');

      final pending = await service.getPendingSyncItems();
      expect(pending.map((r) => r['operation']).toList(),
          ['op1', 'op2', 'op3']);
    });
  });

  group('updateSyncItemStatus — retry semantics', () {
    test('failed marks status=failed and bumps retries by exactly 1',
        () async {
      final id = await service.addToSyncQueue(
          operation: 'op', endpoint: '/x', method: 'POST');

      await service.updateSyncItemStatus(id, 'failed',
          errorMessage: 'connection refused');

      final pending = await service.getPendingSyncItems();
      expect(pending.single['retries'], 1);
      expect(pending.single['status'], 'failed');
      expect(pending.single['error_message'], 'connection refused');
    });

    test('failed rows stay drainable until retries reach max_retries (5)',
        () async {
      final id = await service.addToSyncQueue(
          operation: 'op', endpoint: '/x', method: 'POST');

      // Eligibility predicate is `retries < max_retries` (5). So
      // failures 1..4 leave the row eligible (retries=1..4 < 5), and
      // failure 5 takes it out (retries=5, not strictly less).
      for (var i = 0; i < 4; i++) {
        await service.updateSyncItemStatus(id, 'failed',
            errorMessage: 'try $i');
        final pending = await service.getPendingSyncItems();
        expect(pending, hasLength(1),
            reason: 'after ${i + 1} fail(s) retries < 5, still eligible');
      }

      // 5th failure raises retries to 5; the strict-less predicate now
      // excludes the row from the drain set.
      await service.updateSyncItemStatus(id, 'failed',
          errorMessage: 'exhausted');
      final exhausted = await service.getPendingSyncItems();
      expect(exhausted, isEmpty,
          reason: 'retries >= max_retries must drop the row from drain set');
    });

    test('successful sync (status=synced) is removed from getPendingSyncItems',
        () async {
      final id = await service.addToSyncQueue(
          operation: 'op', endpoint: '/x', method: 'POST');
      await service.updateSyncItemStatus(id, 'synced');
      expect(await service.getPendingSyncItems(), isEmpty);
    });
  });

  group('removeSyncItem', () {
    test('drops the row entirely', () async {
      final id = await service.addToSyncQueue(
          operation: 'op', endpoint: '/x', method: 'POST');
      await service.removeSyncItem(id);
      expect(await service.getPendingSyncItems(), isEmpty);
    });
  });

  group('getPendingSyncCount', () {
    test('counts pending AND failed-but-retriable rows', () async {
      final id1 = await service.addToSyncQueue(
          operation: 'op1', endpoint: '/a', method: 'POST');
      await service.addToSyncQueue(
          operation: 'op2', endpoint: '/b', method: 'POST');
      await service.updateSyncItemStatus(id1, 'failed', errorMessage: 'x');

      // Status of id1 is now 'failed'; both rows still count toward
      // the queue depth that the badge / sync indicator displays.
      expect(await service.getPendingSyncCount(), 2);
    });

    test('does not count rows already marked synced', () async {
      final id = await service.addToSyncQueue(
          operation: 'op', endpoint: '/x', method: 'POST');
      await service.updateSyncItemStatus(id, 'synced');
      expect(await service.getPendingSyncCount(), 0);
    });
  });
}
