import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// Manages the bundled server-schema SQLite database for offline POS.
///
/// On first launch, copies assets/database/database.sqlite to the app data
/// directory. The sync API then populates it with real data (employees,
/// customers, etc.). Offline sales are stored in a [pending_pos_sales] table
/// and uploaded via POST /sync/pos when connectivity returns.
class OfflinePosDatabase {
  static final OfflinePosDatabase _instance = OfflinePosDatabase._internal();
  factory OfflinePosDatabase() => _instance;
  OfflinePosDatabase._internal();

  Database? _db;
  static const String _dbName = 'hermosa_pos_offline.db';
  static const String _assetPath = 'assets/database/database.sqlite';

  bool get isReady => _db != null;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  /// Initialize: copy bundled DB from assets if needed, open it, add custom tables.
  Future<void> initialize() async {
    _db = await _initDatabase();
    debugPrint('OfflinePosDatabase initialized');
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    // Copy from assets if the file doesn't exist yet
    if (!await File(path).exists()) {
      debugPrint('Copying bundled database from assets...');
      try {
        // Ensure directory exists
        await Directory(dbPath).create(recursive: true);
        // Copy from assets
        final data = await rootBundle.load(_assetPath);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        await File(path).writeAsBytes(bytes, flush: true);
        debugPrint('Bundled database copied to: $path');
      } catch (e) {
        debugPrint('Failed to copy bundled database: $e');
        // If copy fails, create a fresh DB - the sync will populate it
      }
    }

    final db = await openDatabase(
      path,
      onOpen: (db) async {
        // Enable WAL mode for better concurrent read/write
        await db.execute('PRAGMA journal_mode=WAL');
        // Create our custom overlay tables
        await _createOverlayTables(db);
      },
    );

    return db;
  }

  /// Create tables that don't exist in the bundled schema but are needed
  /// for offline POS operations.
  Future<void> _createOverlayTables(Database db) async {
    final batch = db.batch();

    // ── Pending POS Sales (queued for /sync/pos upload) ──
    batch.execute('''
      CREATE TABLE IF NOT EXISTS pending_pos_sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        location_id INTEGER,
        contact_id INTEGER,
        transaction_date TEXT,
        products_json TEXT NOT NULL,
        payment_json TEXT NOT NULL,
        discount_type TEXT DEFAULT 'percentage',
        discount_amount REAL DEFAULT 0,
        tax_rate_id INTEGER,
        tax_calculation_amount REAL DEFAULT 0,
        shipping_charges REAL DEFAULT 0,
        final_total REAL NOT NULL,
        sale_note TEXT,
        staff_note TEXT,
        status TEXT DEFAULT 'final',
        is_suspend INTEGER DEFAULT 0,
        is_credit_sale INTEGER DEFAULT 0,
        change_return REAL DEFAULT 0,
        raw_payload_json TEXT,
        sync_status TEXT DEFAULT 'pending',
        sync_error TEXT,
        sync_retries INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── Sync Cursors (track incremental sync position per resource) ──
    batch.execute('''
      CREATE TABLE IF NOT EXISTS sync_cursors (
        resource TEXT PRIMARY KEY,
        cursor_value TEXT,
        last_synced_at TEXT,
        total_synced INTEGER DEFAULT 0
      )
    ''');

    // ── Sync Manifest Cache ──
    batch.execute('''
      CREATE TABLE IF NOT EXISTS sync_manifest (
        id INTEGER PRIMARY KEY DEFAULT 1,
        manifest_json TEXT,
        fetched_at TEXT
      )
    ''');

    // Indexes
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_pending_sales_status ON pending_pos_sales(sync_status)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_pending_sales_uuid ON pending_pos_sales(uuid)',
    );

    await batch.commit(noResult: true);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SYNC CURSORS
  // ═══════════════════════════════════════════════════════════════════

  /// Get the sync cursor for a resource (e.g. "employees", "customers").
  Future<String?> getSyncCursor(String resource) async {
    final db = await database;
    final rows = await db.query(
      'sync_cursors',
      columns: ['cursor_value'],
      where: 'resource = ?',
      whereArgs: [resource],
    );
    if (rows.isEmpty) return null;
    return rows.first['cursor_value'] as String?;
  }

  /// Update the sync cursor after a successful sync page.
  Future<void> updateSyncCursor(String resource, String cursor,
      {int addCount = 0}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final existing = await db.query(
      'sync_cursors',
      where: 'resource = ?',
      whereArgs: [resource],
    );
    if (existing.isEmpty) {
      await db.insert('sync_cursors', {
        'resource': resource,
        'cursor_value': cursor,
        'last_synced_at': now,
        'total_synced': addCount,
      });
    } else {
      final prev = existing.first['total_synced'] as int? ?? 0;
      await db.update(
        'sync_cursors',
        {
          'cursor_value': cursor,
          'last_synced_at': now,
          'total_synced': prev + addCount,
        },
        where: 'resource = ?',
        whereArgs: [resource],
      );
    }
  }

  /// Reset cursor for a resource (force full re-sync).
  Future<void> resetSyncCursor(String resource) async {
    final db = await database;
    await db.delete('sync_cursors',
        where: 'resource = ?', whereArgs: [resource]);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SYNC MANIFEST
  // ═══════════════════════════════════════════════════════════════════

  Future<void> saveManifest(Map<String, dynamic> manifest) async {
    final db = await database;
    await db.insert(
      'sync_manifest',
      {
        'id': 1,
        'manifest_json': jsonEncode(manifest),
        'fetched_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getManifest() async {
    final db = await database;
    final rows = await db.query('sync_manifest', where: 'id = 1');
    if (rows.isEmpty) return null;
    try {
      return jsonDecode(rows.first['manifest_json'] as String)
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  RESOURCE UPSERT (employees, customers from sync API)
  // ═══════════════════════════════════════════════════════════════════

  /// Upsert rows into any table. Each row must have an 'id' key.
  /// Used by the sync API to write downloaded resources.
  Future<int> upsertRows(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return 0;
    final db = await database;

    // Get the table's column names so we only insert valid columns
    final tableInfo = await db.rawQuery('PRAGMA table_info($table)');
    final validColumns =
        tableInfo.map((c) => c['name'] as String).toSet();

    final batch = db.batch();
    int count = 0;
    for (final row in rows) {
      // Filter to only valid columns
      final filtered = <String, dynamic>{};
      for (final entry in row.entries) {
        if (validColumns.contains(entry.key)) {
          // Handle JSON fields - if the value is a Map or List, encode it
          final value = entry.value;
          if (value is Map || value is List) {
            filtered[entry.key] = jsonEncode(value);
          } else {
            filtered[entry.key] = value;
          }
        }
      }
      if (filtered.isEmpty) continue;
      batch.insert(table, filtered,
          conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
    }
    await batch.commit(noResult: true);
    return count;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  READ HELPERS (for offline fallback)
  // ═══════════════════════════════════════════════════════════════════

  /// Get employees for a seller from the local database.
  Future<List<Map<String, dynamic>>> getEmployees(int sellerId) async {
    final db = await database;
    final rows = await db.query(
      'employees',
      where: 'seller_id = ? AND is_active = 1 AND deleted_at IS NULL',
      whereArgs: [sellerId],
    );
    return _decodeJsonFields(rows);
  }

  /// Get customers for a seller from the local database.
  Future<List<Map<String, dynamic>>> getCustomers(int sellerId,
      {String? search}) async {
    final db = await database;
    String where = 'seller_id = ? AND is_active = 1 AND deleted_at IS NULL';
    List<dynamic> whereArgs = [sellerId];
    if (search != null && search.isNotEmpty) {
      where += ' AND (name LIKE ? OR mobile LIKE ? OR email LIKE ?)';
      final pattern = '%$search%';
      whereArgs.addAll([pattern, pattern, pattern]);
    }
    final rows = await db.query('customers', where: where, whereArgs: whereArgs);
    return _decodeJsonFields(rows);
  }

  /// Get meals for a branch from the local database.
  Future<List<Map<String, dynamic>>> getMeals(int branchId,
      {int? categoryId}) async {
    final db = await database;
    String where = 'branch_id = ? AND is_active = 1';
    List<dynamic> whereArgs = [branchId];
    if (categoryId != null) {
      where += ' AND category_id = ?';
      whereArgs.add(categoryId);
    }
    final rows = await db.query('meals', where: where, whereArgs: whereArgs);
    return _decodeJsonFields(rows);
  }

  /// Get services for a branch from the local database.
  Future<List<Map<String, dynamic>>> getServices(int branchId,
      {int? categoryId}) async {
    final db = await database;
    String where = 'branch_id = ? AND is_active = 1';
    List<dynamic> whereArgs = [branchId];
    if (categoryId != null) {
      where += ' AND category_id = ?';
      whereArgs.add(categoryId);
    }
    final rows = await db.query('services', where: where, whereArgs: whereArgs);
    return _decodeJsonFields(rows);
  }

  /// Get products for a branch from the local database.
  Future<List<Map<String, dynamic>>> getProducts(int branchId,
      {int? categoryId}) async {
    final db = await database;
    String where = 'branch_id = ? AND is_active = 1';
    List<dynamic> whereArgs = [branchId];
    if (categoryId != null) {
      where += ' AND category_id = ?';
      whereArgs.add(categoryId);
    }
    final rows = await db.query('products', where: where, whereArgs: whereArgs);
    return _decodeJsonFields(rows);
  }

  /// Get categories for a branch from the local database.
  Future<List<Map<String, dynamic>>> getCategories(int branchId,
      {int? type}) async {
    final db = await database;
    String where = 'branch_id = ? AND is_active = 1';
    List<dynamic> whereArgs = [branchId];
    if (type != null) {
      where += ' AND type = ?';
      whereArgs.add(type);
    }
    final rows =
        await db.query('categories', where: where, whereArgs: whereArgs);
    return _decodeJsonFields(rows);
  }

  /// Get branch info from the local database.
  Future<Map<String, dynamic>?> getBranch(int branchId) async {
    final db = await database;
    final rows = await db.query(
      'branches',
      where: 'id = ?',
      whereArgs: [branchId],
    );
    if (rows.isEmpty) return null;
    final decoded = _decodeJsonFields(rows);
    return decoded.first;
  }

  /// Get settings for a user.
  Future<Map<String, String>> getSettings(int userId) async {
    final db = await database;
    final rows = await db.query(
      'settings',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final result = <String, String>{};
    for (final row in rows) {
      final key = row['key'] as String?;
      final value = row['value'] as String?;
      if (key != null) result[key] = value ?? '';
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  PENDING POS SALES
  // ═══════════════════════════════════════════════════════════════════

  /// Save a POS sale for offline sync. Returns the UUID.
  Future<String> savePendingSale({
    required String uuid,
    required int locationId,
    int? contactId,
    required List<Map<String, dynamic>> products,
    required List<Map<String, dynamic>> payments,
    required double finalTotal,
    String discountType = 'percentage',
    double discountAmount = 0,
    int? taxRateId,
    double taxCalculationAmount = 0,
    double shippingCharges = 0,
    String? saleNote,
    String? staffNote,
    String status = 'final',
    int isSuspend = 0,
    int isCreditSale = 0,
    double changeReturn = 0,
    Map<String, dynamic>? rawPayload,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'pending_pos_sales',
      {
        'uuid': uuid,
        'location_id': locationId,
        'contact_id': contactId,
        'transaction_date': now,
        'products_json': jsonEncode(products),
        'payment_json': jsonEncode(payments),
        'discount_type': discountType,
        'discount_amount': discountAmount,
        'tax_rate_id': taxRateId,
        'tax_calculation_amount': taxCalculationAmount,
        'shipping_charges': shippingCharges,
        'final_total': finalTotal,
        'sale_note': saleNote,
        'staff_note': staffNote,
        'status': status,
        'is_suspend': isSuspend,
        'is_credit_sale': isCreditSale,
        'change_return': changeReturn,
        'raw_payload_json': rawPayload != null ? jsonEncode(rawPayload) : null,
        'sync_status': 'pending',
        'sync_retries': 0,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return uuid;
  }

  /// Get all pending (unsynced) POS sales.
  Future<List<Map<String, dynamic>>> getPendingSales() async {
    final db = await database;
    return await db.query(
      'pending_pos_sales',
      where: "sync_status IN ('pending', 'failed') AND sync_retries < 5",
      orderBy: 'created_at ASC',
    );
  }

  /// Get count of pending sales.
  Future<int> getPendingSalesCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM pending_pos_sales WHERE sync_status IN ('pending', 'failed')",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Mark a sale as synced.
  Future<void> markSaleSynced(String uuid) async {
    final db = await database;
    await db.update(
      'pending_pos_sales',
      {
        'sync_status': 'synced',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  /// Mark a sale as failed.
  Future<void> markSaleFailed(String uuid, String error) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE pending_pos_sales SET sync_status = ?, sync_error = ?, sync_retries = sync_retries + 1, updated_at = ? WHERE uuid = ?',
      ['failed', error, DateTime.now().toIso8601String(), uuid],
    );
  }

  /// Build the POST /sync/pos payload from a pending sale row.
  Map<String, dynamic> buildSyncPosPayload(Map<String, dynamic> saleRow) {
    final productsJson = saleRow['products_json'] as String? ?? '[]';
    final paymentJson = saleRow['payment_json'] as String? ?? '[]';
    final rawPayloadJson = saleRow['raw_payload_json'] as String?;

    // If we have the raw payload, use it directly
    if (rawPayloadJson != null && rawPayloadJson.isNotEmpty) {
      try {
        return jsonDecode(rawPayloadJson) as Map<String, dynamic>;
      } catch (_) {}
    }

    // Build from structured fields
    final products = jsonDecode(productsJson);
    final payments = jsonDecode(paymentJson);

    // Convert products list to indexed map as expected by /sync/pos
    final productsMap = <String, dynamic>{};
    if (products is List) {
      for (var i = 0; i < products.length; i++) {
        productsMap['${i + 1}'] = products[i];
      }
    } else if (products is Map) {
      productsMap.addAll(products.cast<String, dynamic>());
    }

    return {
      'location_id': saleRow['location_id'],
      'contact_id': saleRow['contact_id'] ?? 1,
      'sub_type': '',
      'search_product': '',
      'pay_term_number': '',
      'pay_term_type': '',
      'price_group': 0,
      'sell_price_tax': 'includes',
      'products': productsMap,
      'discount_type': saleRow['discount_type'] ?? 'percentage',
      'discount_amount': saleRow['discount_amount'] ?? 0,
      'rp_redeemed': 0,
      'rp_redeemed_amount': 0,
      'tax_rate_id': saleRow['tax_rate_id'],
      'tax_calculation_amount': saleRow['tax_calculation_amount'] ?? 0,
      'shipping_details': '',
      'shipping_address': '',
      'shipping_status': '',
      'delivered_to': '',
      'delivery_person': '',
      'shipping_charges': saleRow['shipping_charges'] ?? 0,
      'advance_balance': 0,
      'payment': payments is List ? payments : [payments],
      'sale_note': saleRow['sale_note'] ?? '',
      'staff_note': saleRow['staff_note'] ?? '',
      'change_return': saleRow['change_return'] ?? 0,
      'additional_notes': '',
      'is_suspend': saleRow['is_suspend'] ?? 0,
      'is_credit_sale': saleRow['is_credit_sale'] ?? 0,
      'final_total': saleRow['final_total'],
      'status': saleRow['status'] ?? 'final',
    };
  }

  // ═══════════════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════════════

  /// Decode JSON string fields (name, description, etc.) in rows.
  /// The bundled database stores some fields as JSON strings (e.g. name is
  /// {"ar":"...", "en":"..."}).
  List<Map<String, dynamic>> _decodeJsonFields(
      List<Map<String, dynamic>> rows) {
    return rows.map((row) {
      final decoded = Map<String, dynamic>.from(row);
      for (final key in ['name', 'description', 'fullname', 'district',
          'policy', 'options', 'type_extra', 'favorite_langs',
          'tap_file_ids', 'tap_brand_names', 'tap_channel_services',
          'zatca_fields', 'zatca_settings']) {
        final value = decoded[key];
        if (value is String && value.startsWith('{')) {
          try {
            decoded[key] = jsonDecode(value);
          } catch (_) {}
        }
      }
      return decoded;
    }).toList();
  }

  /// Check if the database has data for a given table.
  Future<bool> hasData(String table) async {
    final db = await database;
    try {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $table LIMIT 1',
      );
      return (Sqflite.firstIntValue(result) ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  /// Close the database.
  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
