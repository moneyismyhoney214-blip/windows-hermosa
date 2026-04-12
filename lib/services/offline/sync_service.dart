import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hermosa_pos/services/api/base_client.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';
import 'package:hermosa_pos/services/api/order_service.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';
import 'package:hermosa_pos/locator.dart';

/// Background sync engine that processes pending local operations
/// and pushes them to the server when connectivity is available.
///
/// Handles:
/// - Order sync (local orders -> server bookings)
/// - Invoice sync (local invoices -> server invoices)
/// - Customer sync (local customers -> server customers)
/// - Generic sync queue items
class SyncService extends ChangeNotifier {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final OfflineDatabaseService _offlineDb = OfflineDatabaseService();
  final ConnectivityService _connectivity = ConnectivityService();
  final BaseClient _client = BaseClient();

  bool _isSyncing = false;
  bool _isInitialized = false;
  int _pendingCount = 0;
  String? _lastSyncError;
  DateTime? _lastSyncTime;

  /// Whether a sync is currently in progress.
  bool get isSyncing => _isSyncing;

  /// Number of items pending sync.
  int get pendingCount => _pendingCount;

  /// Last sync error message, if any.
  String? get lastSyncError => _lastSyncError;

  /// Last successful sync time.
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Initialize sync service and register connectivity callbacks.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // When device comes back online, trigger sync
    _connectivity.onOnline(() {
      debugPrint('SyncService: Device came online - starting sync');
      syncAll();
    });

    // Update pending count
    await _refreshPendingCount();

    debugPrint(
        'SyncService initialized (pending: $_pendingCount)');
  }

  Future<void> _refreshPendingCount() async {
    try {
      final orders = await _offlineDb.getUnsyncedOrders();
      final invoices = await _offlineDb.getUnsyncedInvoices();
      final queueItems = await _offlineDb.getPendingSyncItems();
      _pendingCount = orders.length + invoices.length + queueItems.length;
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing pending count: $e');
    }
  }

  /// Sync all pending operations to the server.
  Future<SyncResult> syncAll() async {
    if (_isSyncing) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }
    if (_connectivity.isOffline) {
      return SyncResult(success: false, message: 'No internet connection');
    }

    _isSyncing = true;
    _lastSyncError = null;
    notifyListeners();

    int synced = 0;
    int failed = 0;
    final errors = <String>[];

    try {
      // 1. Sync local orders
      final orderResult = await _syncOrders();
      synced += orderResult.synced;
      failed += orderResult.failed;
      if (orderResult.errors.isNotEmpty) errors.addAll(orderResult.errors);

      // 2. Sync local invoices
      final invoiceResult = await _syncInvoices();
      synced += invoiceResult.synced;
      failed += invoiceResult.failed;
      if (invoiceResult.errors.isNotEmpty) errors.addAll(invoiceResult.errors);

      // 3. Sync local customers
      final customerResult = await _syncCustomers();
      synced += customerResult.synced;
      failed += customerResult.failed;
      if (customerResult.errors.isNotEmpty) {
        errors.addAll(customerResult.errors);
      }

      // 4. Process generic sync queue
      final queueResult = await _processSyncQueue();
      synced += queueResult.synced;
      failed += queueResult.failed;
      if (queueResult.errors.isNotEmpty) errors.addAll(queueResult.errors);

      _lastSyncTime = DateTime.now();
      if (errors.isNotEmpty) {
        _lastSyncError = errors.first;
      }

      debugPrint(
          'Sync complete: $synced synced, $failed failed');
    } catch (e) {
      _lastSyncError = e.toString();
      debugPrint('Sync error: $e');
    } finally {
      _isSyncing = false;
      await _refreshPendingCount();
      notifyListeners();
    }

    return SyncResult(
      success: failed == 0,
      synced: synced,
      failed: failed,
      errors: errors,
      message: failed == 0
          ? 'Synced $synced items successfully'
          : 'Synced $synced, failed $failed',
    );
  }

  /// Sync local orders to server, then create their invoices.
  Future<_BatchResult> _syncOrders() async {
    int synced = 0;
    int failed = 0;
    final errors = <String>[];

    try {
      final unsyncedOrders = await _offlineDb.getUnsyncedOrders();
      if (unsyncedOrders.isEmpty) return _BatchResult(0, 0, []);

      debugPrint('Syncing ${unsyncedOrders.length} local orders...');

      for (final order in unsyncedOrders) {
        try {
          final localId = order['id'] as String;
          final rawJson = order['raw_json'] as String?;
          if (rawJson == null) continue;

          final payload = jsonDecode(rawJson) as Map<String, dynamic>;

          // Remove local-only fields
          payload.remove('_is_local');
          payload.remove('_is_synced');
          payload.remove('_local_id');

          // Create booking on server
          final response = await _client.post(
            ApiConstants.bookingsEndpoint,
            payload,
          );

          if (response is Map) {
            final data = response['data'];
            final serverId = (data is Map ? data['id'] : response['id'])
                ?.toString();
            if (serverId != null && serverId.isNotEmpty) {
              await _offlineDb.markOrderSynced(localId, serverId);
              synced++;
              debugPrint('Order synced: $localId -> $serverId');

              // Only auto-create invoice for pay-now orders, NOT deferred (pay later)
              final paymentType = order['payment_type']?.toString() ?? 'payment';
              if (paymentType != 'later') {
                await _autoCreateInvoiceForBooking(
                  localId, int.tryParse(serverId) ?? 0, order);
              } else {
                debugPrint('Skipping invoice for deferred payment order: $localId');
              }
            } else {
              failed++;
              errors.add('Order $localId: no server ID in response');
            }
          } else {
            failed++;
            errors.add('Order $localId: unexpected response format');
          }
        } catch (e) {
          failed++;
          final localId = order['id']?.toString() ?? 'unknown';
          errors.add('Order $localId: $e');
          debugPrint('Failed to sync order: $e');
        }
      }
    } catch (e) {
      debugPrint('Error syncing orders batch: $e');
      errors.add('Orders batch error: $e');
    }

    return _BatchResult(synced, failed, errors);
  }

  /// After syncing a booking, create its invoice.
  /// Fetches booking details from server to get items (required by backend).
  Future<void> _autoCreateInvoiceForBooking(
      String localOrderId, int serverBookingId,
      Map<String, dynamic> orderRow) async {
    try {
      // Find the matching local invoice for this order
      final db = await _offlineDb.database;
      final localInvoices = await db.query(
        'invoices',
        where: 'is_local = 1 AND is_synced = 0',
        orderBy: 'created_at ASC',
      );

      for (final inv in localInvoices) {
        final rawJson = inv['raw_json'] as String?;
        if (rawJson == null) continue;
        final invPayload = jsonDecode(rawJson) as Map<String, dynamic>;

        // Match by booking_id
        final invBookingId = invPayload['booking_id']?.toString() ?? '';
        if (invBookingId != localOrderId) continue;

        // Step 1: Get items from the LOCAL order (not API - API may return 0 items initially)
        List<Map<String, dynamic>> bookingItems = [];
        try {
          final orderRawJson = orderRow['raw_json'] as String?;
          if (orderRawJson != null) {
            final orderPayload =
                jsonDecode(orderRawJson) as Map<String, dynamic>;
            // Try all possible item keys
            final items = orderPayload['card'] ??
                orderPayload['meals'] ??
                orderPayload['items'] ??
                orderPayload['sales_meals'] ??
                [];
            if (items is List) {
              for (final item in items) {
                if (item is! Map) continue;
                final m = item.map((k, v) => MapEntry(k.toString(), v));
                bookingItems.add({
                  'item_name': m['item_name'] ??
                      m['meal_name'] ??
                      m['name'] ??
                      '',
                  'meal_id': m['meal_id'] ?? m['id'],
                  'price': m['price'] ?? m['unitPrice'] ?? m['unit_price'],
                  'unitPrice':
                      m['unitPrice'] ?? m['unit_price'] ?? m['price'],
                  'quantity': m['quantity'] ?? 1,
                  if (m['addons'] is List && (m['addons'] as List).isNotEmpty)
                    'addons': m['addons'],
                });
              }
            }
          }
          debugPrint(
              'Got ${bookingItems.length} items from local order for booking $serverBookingId');
        } catch (e) {
          debugPrint('Could not read local order items: $e');
        }

        // Step 2: Build invoice payload with items and use OrderService
        final invoicePayload = <String, dynamic>{
          if (invPayload['customer_id'] != null)
            'customer_id': invPayload['customer_id'],
          'branch_id': invPayload['branch_id'] ?? ApiConstants.branchId,
          'booking_id': serverBookingId,
          'date': invPayload['date'] ??
              DateTime.now().toIso8601String().substring(0, 10),
          if (invPayload['cash_back'] != null)
            'cash_back': invPayload['cash_back'],
          if (invPayload['pays'] != null) 'pays': invPayload['pays'],
          if (bookingItems.isNotEmpty) 'card': bookingItems,
        };

        debugPrint(
            'Auto-creating invoice for booking $serverBookingId (${bookingItems.length} items)');

        try {
          // Use OrderService.createInvoice which handles normalization & retries
          final orderService = getIt<OrderService>();
          final response = await orderService.createInvoice(invoicePayload);

          final data = response['data'];
          final invoiceServerId =
              (data is Map ? data['id'] : response['id'])?.toString();
          if (invoiceServerId != null &&
              invoiceServerId.isNotEmpty &&
              !invoiceServerId.startsWith('local_')) {
            await _offlineDb.markInvoiceSynced(
                inv['id'] as String, invoiceServerId);
            // Also remove related sync queue items
            final queueItems = await db.query('sync_queue',
                where: 'local_ref_table = ? AND local_ref_id = ?',
                whereArgs: ['invoices', inv['id']]);
            for (final qi in queueItems) {
              await _offlineDb.removeSyncItem(qi['id'] as int);
            }
            debugPrint(
                'Invoice auto-synced: ${inv['id']} -> $invoiceServerId');
          }
        } catch (e) {
          debugPrint('Auto-create invoice failed: $e');
        }
        break; // Only one invoice per booking
      }
    } catch (e) {
      debugPrint('Error in _autoCreateInvoiceForBooking: $e');
    }
  }

  /// Sync local invoices to server.
  /// Most invoices are auto-created in _syncOrders via _autoCreateInvoiceForBooking.
  /// This handles any remaining orphan invoices.
  Future<_BatchResult> _syncInvoices() async {
    int synced = 0;
    int failed = 0;
    final errors = <String>[];

    try {
      // Re-fetch to get only truly unsynced (auto-create may have synced some)
      final unsyncedInvoices = await _offlineDb.getUnsyncedInvoices();
      if (unsyncedInvoices.isEmpty) return _BatchResult(0, 0, []);

      debugPrint(
          'Syncing ${unsyncedInvoices.length} local invoices...');

      for (final invoice in unsyncedInvoices) {
        try {
          final localId = invoice['id'] as String;
          final rawJson = invoice['raw_json'] as String?;
          if (rawJson == null) continue;

          final payload = jsonDecode(rawJson) as Map<String, dynamic>;
          payload.remove('_is_local');
          payload.remove('_is_synced');
          payload.remove('_local_id');

          // Replace local booking_id / order_id with real server IDs
          await _resolveLocalIdsInPayload(payload);

          // Enrich payload with items from the synced booking
          final enrichedPayload = await _enrichInvoiceWithBookingItems(payload);

          final response = await _client.post(
            ApiConstants.invoicesEndpoint,
            enrichedPayload,
          );

          if (response is Map) {
            final data = response['data'];
            final serverId = (data is Map ? data['id'] : response['id'])
                ?.toString();
            if (serverId != null && serverId.isNotEmpty) {
              await _offlineDb.markInvoiceSynced(localId, serverId);
              synced++;
              debugPrint(
                  'Invoice synced: $localId -> $serverId');
            } else {
              failed++;
              errors.add('Invoice $localId: no server ID');
            }
          } else {
            failed++;
            errors.add('Invoice $localId: unexpected response');
          }
        } catch (e) {
          failed++;
          final localId = invoice['id']?.toString() ?? 'unknown';
          errors.add('Invoice $localId: $e');
          debugPrint('Failed to sync invoice: $e');
        }
      }
    } catch (e) {
      debugPrint('Error syncing invoices batch: $e');
      errors.add('Invoices batch error: $e');
    }

    return _BatchResult(synced, failed, errors);
  }

  /// Sync local customers to server.
  Future<_BatchResult> _syncCustomers() async {
    int synced = 0;
    int failed = 0;
    final errors = <String>[];

    try {
      final db = await _offlineDb.database;
      final localCustomers = await db.query(
        'customers',
        where: 'is_local = 1',
      );
      if (localCustomers.isEmpty) return _BatchResult(0, 0, []);

      debugPrint(
          'Syncing ${localCustomers.length} local customers...');

      for (final customer in localCustomers) {
        try {
          final localId = customer['id'] as String;
          final rawJson = customer['raw_json'] as String?;
          if (rawJson == null) continue;

          final payload = jsonDecode(rawJson) as Map<String, dynamic>;
          payload.remove('id'); // Let server assign ID

          final sellerId = customer['seller_id'] as int? ?? ApiConstants.sellerId;
          final endpoint = ApiConstants.customersEndpoint(sellerId);

          final fields = <String, String>{};
          if (payload['name'] != null) fields['name'] = payload['name'].toString();
          if (payload['phone'] != null) {
            fields['phone'] = payload['phone'].toString();
          }
          if (payload['email'] != null) {
            fields['email'] = payload['email'].toString();
          }
          if (payload['tax_number'] != null) {
            fields['tax_number'] = payload['tax_number'].toString();
          }

          final response = await _client.postMultipart(endpoint, fields);

          if (response is Map) {
            final data = response['data'];
            final serverId =
                (data is Map ? data['id'] : response['id'])?.toString();
            if (serverId != null && serverId.isNotEmpty) {
              // Update local record with server ID
              await db.update(
                'customers',
                {
                  'is_local': 0,
                  'updated_at': DateTime.now().toIso8601String(),
                },
                where: 'id = ?',
                whereArgs: [localId],
              );
              synced++;
              debugPrint(
                  'Customer synced: $localId -> $serverId');
            }
          }
        } catch (e) {
          failed++;
          errors.add('Customer sync error: $e');
          debugPrint('Failed to sync customer: $e');
        }
      }
    } catch (e) {
      debugPrint('Error syncing customers: $e');
      errors.add('Customers batch error: $e');
    }

    return _BatchResult(synced, failed, errors);
  }

  /// Process the generic sync queue.
  Future<_BatchResult> _processSyncQueue() async {
    int synced = 0;
    int failed = 0;
    final errors = <String>[];

    try {
      final pendingItems = await _offlineDb.getPendingSyncItems();
      if (pendingItems.isEmpty) return _BatchResult(0, 0, []);

      debugPrint(
          'Processing ${pendingItems.length} sync queue items...');

      for (final item in pendingItems) {
        final id = item['id'] as int;
        final method = (item['method'] as String?)?.toUpperCase() ?? 'POST';
        final endpoint = item['endpoint'] as String;
        final payloadStr = item['payload'] as String?;
        final operation = item['operation'] as String? ?? '';
        final localRefTable = item['local_ref_table'] as String?;
        final localRefId = item['local_ref_id'] as String?;

        // Skip items already handled by _syncOrders / _syncInvoices / _autoCreate
        if (localRefTable == 'orders' && localRefId != null) {
          final serverId = await _offlineDb.getOrderServerId(localRefId);
          if (serverId != null) {
            await _offlineDb.removeSyncItem(id);
            synced++;
            continue;
          }
        }
        if (localRefTable == 'invoices' && localRefId != null) {
          final db = await _offlineDb.database;
          final rows = await db.query('invoices',
              columns: ['is_synced'],
              where: 'id = ? AND is_synced = 1',
              whereArgs: [localRefId]);
          if (rows.isNotEmpty) {
            await _offlineDb.removeSyncItem(id);
            synced++;
            continue;
          }
        }

        try {
          await _offlineDb.updateSyncItemStatus(id, 'syncing');

          dynamic payload;
          if (payloadStr != null && payloadStr.isNotEmpty) {
            payload = jsonDecode(payloadStr);
          }

          // Resolve local IDs for invoice operations
          final operation = item['operation'] as String? ?? '';
          if (payload is Map<String, dynamic> &&
              operation.contains('INVOICE')) {
            await _resolveLocalIdsInPayload(payload);
            payload = await _enrichInvoiceWithBookingItems(payload);
          }

          dynamic response;
          switch (method) {
            case 'POST':
              response = await _client.post(endpoint, payload ?? {});
              break;
            case 'PUT':
              response = await _client.put(endpoint, payload ?? {});
              break;
            case 'PATCH':
              response = await _client.patch(endpoint, payload ?? {});
              break;
            case 'DELETE':
              response = await _client.delete(endpoint);
              break;
            default:
              throw Exception('Unsupported method: $method');
          }

          // Update local reference if provided
          final localRefTable = item['local_ref_table'] as String?;
          final localRefId = item['local_ref_id'] as String?;
          if (localRefTable != null &&
              localRefId != null &&
              response is Map) {
            final serverId = (response['data'] is Map
                    ? response['data']['id']
                    : response['id'])
                ?.toString();
            if (serverId != null) {
              if (localRefTable == 'orders') {
                await _offlineDb.markOrderSynced(localRefId, serverId);
              } else if (localRefTable == 'invoices') {
                await _offlineDb.markInvoiceSynced(localRefId, serverId);
              }
            }
          }

          await _offlineDb.removeSyncItem(id);
          synced++;
        } catch (e) {
          await _offlineDb.updateSyncItemStatus(id, 'failed',
              errorMessage: e.toString());
          failed++;
          errors.add('Queue item $id: $e');
          debugPrint('Sync queue item $id failed: $e');
        }
      }
    } catch (e) {
      debugPrint('Error processing sync queue: $e');
      errors.add('Queue processing error: $e');
    }

    return _BatchResult(synced, failed, errors);
  }

  /// Fetch booking details from server and enrich the invoice payload with items.
  Future<Map<String, dynamic>> _enrichInvoiceWithBookingItems(
      Map<String, dynamic> payload) async {
    final bookingId = payload['booking_id'];
    if (bookingId == null || bookingId.toString().startsWith('local_')) {
      return _buildCleanInvoicePayload(payload);
    }

    try {
      // Fetch booking details from server
      final endpoint =
          '${ApiConstants.bookingsEndpoint}/$bookingId';
      final response = await _client.get(endpoint);

      if (response is Map) {
        final data = response['data'];
        if (data is Map) {
          final bookingData =
              data.map((k, v) => MapEntry(k.toString(), v));

          // Extract items from booking
          final bookingMeals = bookingData['booking_meals'] ??
              bookingData['items'] ??
              bookingData['card'] ??
              [];

          if (bookingMeals is List && bookingMeals.isNotEmpty) {
            // Build card items from booking meals
            final card = <Map<String, dynamic>>[];
            for (final meal in bookingMeals) {
              if (meal is! Map) continue;
              final m = meal.map((k, v) => MapEntry(k.toString(), v));
              card.add({
                'item_name': m['meal_name'] ?? m['item_name'] ?? m['name'],
                'meal_id': m['meal_id'] ?? m['id'],
                'booking_meal_id': m['id'],
                'price': m['price'] ?? m['unit_price'],
                'unitPrice': m['unit_price'] ?? m['price'],
                'quantity': m['quantity'] ?? 1,
                if (m['addons'] != null) 'addons': m['addons'],
              });
            }

            final enriched = Map<String, dynamic>.from(payload);
            enriched['card'] = card;
            enriched['items'] = card;
            // Remove any empty items lists
            enriched.remove('meals');
            enriched.remove('sales_meals');
            debugPrint(
                'Enriched invoice with ${card.length} items from booking $bookingId');
            return _buildCleanInvoicePayload(enriched);
          }
        }
      }
    } catch (e) {
      debugPrint('Could not fetch booking items for invoice: $e');
    }

    return _buildCleanInvoicePayload(payload);
  }

  /// Build a clean invoice payload matching the format the backend expects.
  /// The backend resolves items from the booking - we just need the reference.
  Map<String, dynamic> _buildCleanInvoicePayload(
      Map<String, dynamic> raw) {
    final clean = <String, dynamic>{};

    // Required fields
    if (raw['customer_id'] != null) {
      clean['customer_id'] = raw['customer_id'];
    }
    clean['branch_id'] = raw['branch_id'] ?? ApiConstants.branchId;
    if (raw['booking_id'] != null) {
      clean['booking_id'] = raw['booking_id'];
    }
    if (raw['order_id'] != null) {
      clean['order_id'] = raw['order_id'];
    }
    clean['date'] =
        raw['date'] ?? DateTime.now().toIso8601String().substring(0, 10);
    if (raw['cash_back'] != null) {
      clean['cash_back'] = raw['cash_back'];
    }

    // Pays
    if (raw['pays'] is List && (raw['pays'] as List).isNotEmpty) {
      clean['pays'] = raw['pays'];
    }

    // Items - include if available (some endpoints need them)
    for (final key in ['card', 'items', 'meals', 'sales_meals']) {
      if (raw[key] is List && (raw[key] as List).isNotEmpty) {
        clean[key] = raw[key];
        break; // Only include one items key
      }
    }

    // Optional fields
    if (raw['type'] != null) clean['type'] = raw['type'];
    if (raw['type_extra'] != null) clean['type_extra'] = raw['type_extra'];
    if (raw['promocode_id'] != null) {
      clean['promocode_id'] = raw['promocode_id'];
    }
    if (raw['promocodeValue'] != null) {
      clean['promocodeValue'] = raw['promocodeValue'];
    }

    return clean;
  }

  /// Replace any local_* IDs in invoice payload with real server IDs.
  Future<void> _resolveLocalIdsInPayload(Map<String, dynamic> payload) async {
    for (final key in ['booking_id', 'order_id']) {
      final value = payload[key]?.toString() ?? '';
      if (value.startsWith('local_')) {
        final serverId = await _offlineDb.getOrderServerId(value);
        if (serverId != null && serverId.isNotEmpty) {
          payload[key] = int.tryParse(serverId) ?? serverId;
          debugPrint('Resolved $key: $value -> $serverId');
        } else {
          // Order not synced yet - remove the field so server doesn't reject it
          payload.remove(key);
          debugPrint('Removed unresolved $key: $value');
        }
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}

/// Result of a sync operation.
class SyncResult {
  final bool success;
  final int synced;
  final int failed;
  final List<String> errors;
  final String? message;

  SyncResult({
    required this.success,
    this.synced = 0,
    this.failed = 0,
    this.errors = const [],
    this.message,
  });
}

class _BatchResult {
  final int synced;
  final int failed;
  final List<String> errors;
  _BatchResult(this.synced, this.failed, this.errors);
}
