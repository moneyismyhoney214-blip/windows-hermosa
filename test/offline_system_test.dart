import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';
import 'package:hermosa_pos/services/offline/sync_service.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';

/// Initialize sqflite FFI for desktop/test environment.
void setupTestDb() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

void main() {
  setupTestDb();

  late OfflineDatabaseService offlineDb;

  setUp(() async {
    ApiConstants.branchId = 87;
    ApiConstants.sellerId = 1;
    offlineDb = OfflineDatabaseService();
    await offlineDb.initialize();
  });

  tearDown(() async {
    // Clear all data between tests
    final db = await offlineDb.database;
    for (final table in [
      'categories',
      'products',
      'customers',
      'restaurant_tables',
      'orders',
      'invoices',
      'payment_methods',
      'branch_settings',
      'promo_codes',
      'sync_queue',
      'reports_cache',
      'countries',
      'cities',
    ]) {
      await db.delete(table);
    }
  });

  // ═══════════════════════════════════════════════════════════════════
  //  DATABASE INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════

  group('OfflineDatabaseService - Initialization', () {
    test('database initializes successfully', () async {
      expect(offlineDb.isReady, isTrue);
    });

    test('all tables exist', () async {
      final db = await offlineDb.database;
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
      );
      final tableNames = tables.map((t) => t['name'] as String).toSet();

      expect(tableNames, contains('categories'));
      expect(tableNames, contains('products'));
      expect(tableNames, contains('customers'));
      expect(tableNames, contains('restaurant_tables'));
      expect(tableNames, contains('orders'));
      expect(tableNames, contains('invoices'));
      expect(tableNames, contains('payment_methods'));
      expect(tableNames, contains('branch_settings'));
      expect(tableNames, contains('promo_codes'));
      expect(tableNames, contains('sync_queue'));
      expect(tableNames, contains('reports_cache'));
      expect(tableNames, contains('countries'));
      expect(tableNames, contains('cities'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  CATEGORIES
  // ═══════════════════════════════════════════════════════════════════

  group('OfflineDatabaseService - Categories', () {
    test('saves and retrieves categories', () async {
      final categories = [
        {
          'id': 5,
          'name': {'ar': 'قهوة', 'en': 'Coffee'},
          'type': 'meals',
          'parent_id': null,
        },
        {
          'id': 10,
          'name': {'ar': 'عصائر', 'en': 'Juices'},
          'type': 'meals',
          'parent_id': null,
        },
      ];

      await offlineDb.saveCategories(categories, 87);

      final retrieved = await offlineDb.getCategories(87);
      expect(retrieved.length, 2);
      expect(retrieved[0]['id'], 5);
      expect(retrieved[1]['id'], 10);
    });

    test('returns empty for different branch', () async {
      await offlineDb.saveCategories([
        {'id': 1, 'name': 'Test', 'type': 'meals'},
      ], 87);

      final retrieved = await offlineDb.getCategories(999);
      expect(retrieved.length, 0);
    });

    test('replaces on duplicate id', () async {
      await offlineDb.saveCategories([
        {'id': 1, 'name': 'Old Name'},
      ], 87);

      await offlineDb.saveCategories([
        {'id': 1, 'name': 'New Name'},
      ], 87);

      final retrieved = await offlineDb.getCategories(87);
      expect(retrieved.length, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  PRODUCTS
  // ═══════════════════════════════════════════════════════════════════

  group('OfflineDatabaseService - Products', () {
    test('saves and retrieves products', () async {
      final products = [
        {
          'id': 100,
          'name': 'V60 Cold',
          'price': 15.0,
          'category_id': '5',
          'is_active': true,
          'image': 'https://example.com/v60.jpg',
          'extras': [
            {'id': '1', 'name': 'Extra Shot', 'price': 4.0}
          ],
        },
        {
          'id': 101,
          'name': 'Latte',
          'price': 18.0,
          'category_id': '5',
          'is_active': true,
        },
      ];

      await offlineDb.saveProducts(products, 87);

      final retrieved = await offlineDb.getProducts(87);
      expect(retrieved.length, 2);
    });

    test('filters by category', () async {
      await offlineDb.saveProducts([
        {'id': 1, 'name': 'Coffee', 'price': 10, 'category_id': '5'},
        {'id': 2, 'name': 'Juice', 'price': 12, 'category_id': '10'},
      ], 87);

      final coffees = await offlineDb.getProducts(87, categoryId: '5');
      expect(coffees.length, 1);

      final all = await offlineDb.getProducts(87);
      expect(all.length, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  CUSTOMERS
  // ═══════════════════════════════════════════════════════════════════

  group('OfflineDatabaseService - Customers', () {
    test('saves and retrieves customers', () async {
      final customers = [
        {
          'id': 1,
          'name': 'Ahmed',
          'phone': '0501234567',
          'email': 'ahmed@test.com',
        },
        {
          'id': 2,
          'name': 'Mohammed',
          'phone': '0559876543',
        },
      ];

      await offlineDb.saveCustomers(customers, 1);

      final retrieved = await offlineDb.getCustomers(1);
      expect(retrieved.length, 2);
    });

    test('searches customers by name/phone', () async {
      await offlineDb.saveCustomers([
        {'id': 1, 'name': 'Ahmed Ali', 'phone': '0501234567'},
        {'id': 2, 'name': 'Mohammed Saeed', 'phone': '0559876543'},
      ], 1);

      final byName = await offlineDb.getCustomers(1, search: 'Ahmed');
      expect(byName.length, 1);

      final byPhone = await offlineDb.getCustomers(1, search: '055');
      expect(byPhone.length, 1);
    });

    test('creates local customer with local_id', () async {
      final localId = await offlineDb.saveLocalCustomer({
        'name': 'New Customer',
        'phone': '0512345678',
      }, 1);

      expect(localId, startsWith('local_'));

      final customers = await offlineDb.getCustomers(1);
      expect(customers.length, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  TABLES
  // ═══════════════════════════════════════════════════════════════════

  group('OfflineDatabaseService - Tables', () {
    test('saves and retrieves restaurant tables', () async {
      final tables = [
        {
          'id': 1,
          'name': 'Table 1',
          'floor_id': 'f1',
          'seats': 4,
          'status': 'available',
          'is_active': true,
        },
        {
          'id': 2,
          'name': 'Table 2',
          'floor_id': 'f1',
          'seats': 6,
          'status': 'occupied',
          'is_active': true,
        },
      ];

      await offlineDb.saveTables(tables, 87);

      final retrieved = await offlineDb.getTables(87);
      expect(retrieved.length, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  ORDERS (Offline CRUD)
  // ═══════════════════════════════════════════════════════════════════

  group('OfflineDatabaseService - Orders', () {
    test('creates local order and retrieves it', () async {
      final orderData = {
        'customer_id': 1,
        'type': 'restaurant_pickup',
        'total': 45.0,
        'subtotal': 40.0,
        'tax': 5.0,
        'items': [
          {'meal_id': 100, 'quantity': 2, 'price': 15.0},
          {'meal_id': 101, 'quantity': 1, 'price': 10.0},
        ],
        'pays': [
          {'pay_method': 'cash', 'amount': 45.0},
        ],
      };

      final localId = await offlineDb.saveLocalOrder(orderData, 87);

      expect(localId, startsWith('local_'));

      final orders = await offlineDb.getOrders(87);
      expect(orders.length, 1);
      expect(orders[0]['_is_local'], true);
      expect(orders[0]['_is_synced'], false);
    });

    test('saves server orders', () async {
      final serverOrders = [
        {
          'id': 5001,
          'booking_number': 'B-5001',
          'customer_id': 1,
          'status': 'completed',
          'total': 100.0,
          'booking_meals': [
            {'meal_id': 100, 'quantity': 3},
          ],
        },
        {
          'id': 5002,
          'booking_number': 'B-5002',
          'customer_id': 2,
          'status': 'pending',
          'total': 50.0,
        },
      ];

      await offlineDb.saveServerOrders(serverOrders, 87);

      final orders = await offlineDb.getOrders(87);
      expect(orders.length, 2);
      expect(orders[0]['_is_synced'], true);
    });

    test('unsynced orders list works', () async {
      // Create one local (unsynced) and one server (synced) order
      await offlineDb.saveLocalOrder({
        'customer_id': 1,
        'total': 30.0,
        'items': [],
      }, 87);

      await offlineDb.saveServerOrders([
        {'id': 999, 'total': 50.0},
      ], 87);

      final unsynced = await offlineDb.getUnsyncedOrders();
      expect(unsynced.length, 1);
      expect(unsynced[0]['is_local'], 1);
      expect(unsynced[0]['is_synced'], 0);
    });

    test('marks order as synced', () async {
      final localId = await offlineDb.saveLocalOrder({
        'customer_id': 1,
        'total': 30.0,
        'items': [],
      }, 87);

      await offlineDb.markOrderSynced(localId, '12345');

      final unsynced = await offlineDb.getUnsyncedOrders();
      expect(unsynced.length, 0);

      final allOrders = await offlineDb.getOrders(87);
      expect(allOrders.length, 1);
      expect(allOrders[0]['_is_synced'], true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  INVOICES (Offline CRUD)
  // ═══════════════════════════════════════════════════════════════════

  group('OfflineDatabaseService - Invoices', () {
    test('creates local invoice and retrieves it', () async {
      final invoiceData = {
        'customer_id': 1,
        'type': 'services',
        'total': 100.0,
        'subtotal': 87.0,
        'tax': 13.0,
        'card': [
          {'meal_id': 100, 'quantity': 2, 'price': 15.0},
        ],
        'pays': [
          {'pay_method': 'cash', 'amount': 100.0},
        ],
      };

      final localId = await offlineDb.saveLocalInvoice(invoiceData, 87);

      expect(localId, startsWith('local_inv_'));

      final invoices = await offlineDb.getInvoices(87);
      expect(invoices.length, 1);
      expect(invoices[0]['_is_local'], true);
      expect(invoices[0]['_is_synced'], false);
    });

    test('saves server invoices', () async {
      await offlineDb.saveServerInvoices([
        {
          'id': 3001,
          'invoice_number': 'INV-3001',
          'customer_id': 1,
          'total': 200.0,
          'status': 'completed',
        },
      ], 87);

      final invoices = await offlineDb.getInvoices(87);
      expect(invoices.length, 1);
      expect(invoices[0]['_is_synced'], true);
    });

    test('marks invoice as synced', () async {
      final localId = await offlineDb.saveLocalInvoice({
        'customer_id': 1,
        'total': 50.0,
        'card': [],
      }, 87);

      await offlineDb.markInvoiceSynced(localId, '9999');

      final unsynced = await offlineDb.getUnsyncedInvoices();
      expect(unsynced.length, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  SYNC QUEUE
  // ═══════════════════════════════════════════════════════════════════

  group('OfflineDatabaseService - Sync Queue', () {
    test('adds items to sync queue', () async {
      final id = await offlineDb.addToSyncQueue(
        operation: 'CREATE_BOOKING',
        endpoint: '/seller/branches/87/bookings',
        method: 'POST',
        payload: {'customer_id': 1, 'total': 50.0},
        localRefTable: 'orders',
        localRefId: 'local_123',
      );

      expect(id, greaterThan(0));

      final pending = await offlineDb.getPendingSyncItems();
      expect(pending.length, 1);
      expect(pending[0]['operation'], 'CREATE_BOOKING');
      expect(pending[0]['status'], 'pending');
    });

    test('pending count is correct', () async {
      await offlineDb.addToSyncQueue(
        operation: 'CREATE_BOOKING',
        endpoint: '/test1',
        method: 'POST',
      );
      await offlineDb.addToSyncQueue(
        operation: 'CREATE_INVOICE',
        endpoint: '/test2',
        method: 'POST',
      );

      final count = await offlineDb.getPendingSyncCount();
      expect(count, 2);
    });

    test('updates sync item status', () async {
      final id = await offlineDb.addToSyncQueue(
        operation: 'CREATE_BOOKING',
        endpoint: '/test',
        method: 'POST',
      );

      await offlineDb.updateSyncItemStatus(id, 'syncing');

      final pending = await offlineDb.getPendingSyncItems();
      // 'syncing' is not 'pending' or 'failed', so it won't appear
      expect(pending.length, 0);
    });

    test('removes sync item after success', () async {
      final id = await offlineDb.addToSyncQueue(
        operation: 'CREATE_BOOKING',
        endpoint: '/test',
        method: 'POST',
      );

      await offlineDb.removeSyncItem(id);

      final count = await offlineDb.getPendingSyncCount();
      expect(count, 0);
    });

    test('failed items with retries still appear in pending', () async {
      final id = await offlineDb.addToSyncQueue(
        operation: 'CREATE_BOOKING',
        endpoint: '/test',
        method: 'POST',
      );

      // Fail it (retries < max_retries)
      await offlineDb.updateSyncItemStatus(id, 'failed',
          errorMessage: 'Network error');

      final pending = await offlineDb.getPendingSyncItems();
      expect(pending.length, 1);
      expect(pending[0]['status'], 'failed');
      expect(pending[0]['retries'], 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  PAYMENT METHODS
  // ═══════════════════════════════════════════════════════════════════

  group('OfflineDatabaseService - Payment Methods', () {
    test('saves and retrieves payment methods', () async {
      await offlineDb.savePaymentMethods([
        {'id': 'cash', 'name': 'Cash', 'is_active': true},
        {'id': 'mada', 'name': 'Mada', 'is_active': true},
        {'id': 'visa', 'name': 'Visa', 'is_active': false},
      ], 87);

      final methods = await offlineDb.getPaymentMethods(87);
      expect(methods.length, 3);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  BRANCH SETTINGS
  // ═══════════════════════════════════════════════════════════════════

  group('OfflineDatabaseService - Branch Settings', () {
    test('saves and retrieves branch settings', () async {
      final settings = {
        'name': {'ar': 'فرع الرياض', 'en': 'Riyadh Branch'},
        'logo': 'https://example.com/logo.png',
        'currency': 'ر.س',
        'tax_percentage': 15.0,
        'pay_methods': {
          'cash': true,
          'mada': true,
          'visa': false,
        },
      };

      await offlineDb.saveBranchSettings(87, settings);

      final retrieved = await offlineDb.getBranchSettings(87);
      expect(retrieved, isNotNull);
      expect(retrieved!['currency'], 'ر.س');
      expect(retrieved['tax_percentage'], 15.0);
    });

    test('returns null for non-existent branch', () async {
      final retrieved = await offlineDb.getBranchSettings(999);
      expect(retrieved, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  PROMO CODES
  // ═══════════════════════════════════════════════════════════════════

  group('OfflineDatabaseService - Promo Codes', () {
    test('saves and retrieves promo codes', () async {
      await offlineDb.savePromoCodes([
        {
          'id': '1',
          'code': 'SAVE10',
          'discount': 10.0,
          'discount_type': 'percentage',
          'is_active': true,
        },
        {
          'id': '2',
          'code': 'FLAT50',
          'discount': 50.0,
          'discount_type': 'amount',
          'is_active': true,
        },
      ], 87);

      final codes = await offlineDb.getPromoCodes(87);
      expect(codes.length, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  REPORTS CACHE
  // ═══════════════════════════════════════════════════════════════════

  group('OfflineDatabaseService - Reports Cache', () {
    test('caches and retrieves report', () async {
      final reportData = {
        'data': [
          {'total_sales': 5000, 'total_tax': 750},
        ],
        'summary': {'grand_total': 5000},
      };

      await offlineDb.cacheReport(
          'sales_2024-01-01_2024-01-31', reportData, 87);

      final cached = await offlineDb.getCachedReport(
          'sales_2024-01-01_2024-01-31', 87);
      expect(cached, isNotNull);
      expect(cached!['summary']['grand_total'], 5000);
    });

    test('returns null for non-existent report', () async {
      final cached =
          await offlineDb.getCachedReport('non_existent', 87);
      expect(cached, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  COUNTRIES & CITIES
  // ═══════════════════════════════════════════════════════════════════

  group('OfflineDatabaseService - Countries & Cities', () {
    test('saves and retrieves countries', () async {
      await offlineDb.saveCountries([
        {
          'id': 1,
          'name': {'ar': 'السعودية', 'en': 'Saudi Arabia'},
          'currency': 'SAR',
          'tax_percentage': 15.0,
        },
      ]);

      final countries = await offlineDb.getCountries();
      expect(countries.length, 1);
    });

    test('saves and retrieves cities', () async {
      await offlineDb.saveCities([
        {
          'id': 1,
          'name': {'ar': 'الرياض', 'en': 'Riyadh'},
        },
        {
          'id': 2,
          'name': {'ar': 'جدة', 'en': 'Jeddah'},
        },
      ], 1);

      final cities = await offlineDb.getCities(1);
      expect(cities.length, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  CONNECTIVITY SERVICE
  // ═══════════════════════════════════════════════════════════════════

  group('ConnectivityService', () {
    test('singleton returns same instance', () {
      final a = ConnectivityService();
      final b = ConnectivityService();
      expect(identical(a, b), isTrue);
    });

    test('defaults to online', () {
      final service = ConnectivityService();
      // Before initialization, isOnline defaults to true
      expect(service.isOnline, isTrue);
      expect(service.isOffline, isFalse);
    });

    test('registers callbacks', () {
      final service = ConnectivityService();
      var onlineCalled = false;
      var offlineCalled = false;

      service.onOnline(() => onlineCalled = true);
      service.onOffline(() => offlineCalled = true);

      // Callbacks are registered but not called yet
      expect(onlineCalled, isFalse);
      expect(offlineCalled, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  SYNC SERVICE
  // ═══════════════════════════════════════════════════════════════════

  group('SyncService', () {
    test('singleton returns same instance', () {
      final a = SyncService();
      final b = SyncService();
      expect(identical(a, b), isTrue);
    });

    test('reports not syncing initially', () {
      final service = SyncService();
      expect(service.isSyncing, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  FULL OFFLINE WORKFLOW
  // ═══════════════════════════════════════════════════════════════════

  group('Full Offline Workflow', () {
    test('complete order -> invoice -> sync queue workflow', () async {
      // 1. Save products (simulating previous online session cache)
      await offlineDb.saveProducts([
        {'id': 100, 'name': 'V60', 'price': 15.0, 'category_id': '5'},
        {'id': 101, 'name': 'Latte', 'price': 18.0, 'category_id': '5'},
      ], 87);

      // 2. Save categories
      await offlineDb.saveCategories([
        {'id': 5, 'name': 'Coffee'},
      ], 87);

      // 3. Save customers
      await offlineDb.saveCustomers([
        {'id': 1, 'name': 'Walk-in Customer'},
      ], 1);

      // 4. Verify all data is available offline
      final products = await offlineDb.getProducts(87);
      expect(products.length, 2);
      final categories = await offlineDb.getCategories(87);
      expect(categories.length, 1);
      final customers = await offlineDb.getCustomers(1);
      expect(customers.length, 1);

      // 5. Create an order offline
      final orderLocalId = await offlineDb.saveLocalOrder({
        'customer_id': 1,
        'type': 'restaurant_pickup',
        'total': 33.0,
        'card': [
          {'meal_id': 100, 'quantity': 1, 'price': 15.0},
          {'meal_id': 101, 'quantity': 1, 'price': 18.0},
        ],
      }, 87);

      // 6. Add order to sync queue
      await offlineDb.addToSyncQueue(
        operation: 'CREATE_BOOKING',
        endpoint: '/seller/branches/87/bookings',
        method: 'POST',
        payload: {'customer_id': 1, 'total': 33.0},
        localRefTable: 'orders',
        localRefId: orderLocalId,
      );

      // 7. Create an invoice offline
      final invoiceLocalId = await offlineDb.saveLocalInvoice({
        'customer_id': 1,
        'total': 33.0,
        'card': [
          {'meal_id': 100, 'quantity': 1, 'price': 15.0},
          {'meal_id': 101, 'quantity': 1, 'price': 18.0},
        ],
        'pays': [
          {'pay_method': 'cash', 'amount': 33.0},
        ],
      }, 87);

      // 8. Add invoice to sync queue
      await offlineDb.addToSyncQueue(
        operation: 'CREATE_INVOICE',
        endpoint: '/seller/branches/87/invoices',
        method: 'POST',
        payload: {'customer_id': 1, 'total': 33.0},
        localRefTable: 'invoices',
        localRefId: invoiceLocalId,
      );

      // 9. Verify sync queue has 2 items
      final pendingCount = await offlineDb.getPendingSyncCount();
      expect(pendingCount, 2);

      // 10. Verify unsynced orders
      final unsyncedOrders = await offlineDb.getUnsyncedOrders();
      expect(unsyncedOrders.length, 1);

      // 11. Verify unsynced invoices
      final unsyncedInvoices = await offlineDb.getUnsyncedInvoices();
      expect(unsyncedInvoices.length, 1);

      // 12. Simulate sync: mark order as synced
      await offlineDb.markOrderSynced(orderLocalId, '5001');
      final syncedOrders = await offlineDb.getUnsyncedOrders();
      expect(syncedOrders.length, 0);

      // 13. Simulate sync: mark invoice as synced
      await offlineDb.markInvoiceSynced(invoiceLocalId, '3001');
      final syncedInvoices = await offlineDb.getUnsyncedInvoices();
      expect(syncedInvoices.length, 0);

      // 14. Remove sync queue items
      final pending = await offlineDb.getPendingSyncItems();
      for (final item in pending) {
        await offlineDb.removeSyncItem(item['id'] as int);
      }

      final finalCount = await offlineDb.getPendingSyncCount();
      expect(finalCount, 0);

      // 15. All orders (local + synced) still accessible
      final allOrders = await offlineDb.getOrders(87);
      expect(allOrders.length, 1);
      expect(allOrders[0]['_is_synced'], true);
    });

    test('mixed server + local orders appear together', () async {
      // Server orders from previous online session
      await offlineDb.saveServerOrders([
        {'id': 5001, 'total': 100.0, 'status': 'completed'},
        {'id': 5002, 'total': 200.0, 'status': 'completed'},
      ], 87);

      // Local order created offline
      await offlineDb.saveLocalOrder({
        'customer_id': 1,
        'total': 50.0,
        'items': [],
      }, 87);

      final allOrders = await offlineDb.getOrders(87);
      expect(allOrders.length, 3);

      // Check we have both synced and unsynced
      final synced = allOrders.where((o) => o['_is_synced'] == true).length;
      final local = allOrders.where((o) => o['_is_local'] == true).length;
      expect(synced, 2);
      expect(local, 1);
    });
  });
}
