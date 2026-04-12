import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// Core SQLite database service for offline-first POS operations.
///
/// Manages local storage for products, categories, orders, invoices,
/// customers, tables, and a sync queue for pending server operations.
class OfflineDatabaseService {
  static final OfflineDatabaseService _instance =
      OfflineDatabaseService._internal();
  factory OfflineDatabaseService() => _instance;
  OfflineDatabaseService._internal();

  Database? _db;
  static const int _dbVersion = 2;
  static const String _dbName = 'hermosa_offline.db';

  /// Whether the database is ready.
  bool get isReady => _db != null;

  /// Get database instance, initializing if needed.
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    debugPrint('Offline DB path: $path');
    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> initialize() async {
    _db = await _initDatabase();
    debugPrint('OfflineDatabaseService initialized');
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // ── Categories ──
    batch.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        name_ar TEXT,
        name_en TEXT,
        type TEXT,
        parent_id TEXT,
        image_url TEXT,
        branch_id INTEGER,
        raw_json TEXT,
        updated_at TEXT
      )
    ''');

    // ── Products / Meals ──
    batch.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        name_ar TEXT,
        name_en TEXT,
        price REAL NOT NULL DEFAULT 0,
        category_id TEXT,
        category_name TEXT,
        is_active INTEGER DEFAULT 1,
        image TEXT,
        extras_json TEXT,
        branch_id INTEGER,
        raw_json TEXT,
        updated_at TEXT
      )
    ''');

    // ── Customers ──
    batch.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id TEXT PRIMARY KEY,
        name TEXT,
        phone TEXT,
        email TEXT,
        tax_number TEXT,
        address TEXT,
        seller_id INTEGER,
        raw_json TEXT,
        is_local INTEGER DEFAULT 0,
        local_id TEXT,
        updated_at TEXT
      )
    ''');

    // ── Restaurant Tables ──
    batch.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_tables (
        id TEXT PRIMARY KEY,
        name TEXT,
        floor_id TEXT,
        seats INTEGER DEFAULT 4,
        status TEXT DEFAULT 'available',
        is_active INTEGER DEFAULT 1,
        branch_id INTEGER,
        raw_json TEXT,
        updated_at TEXT
      )
    ''');

    // ── Orders / Bookings ──
    batch.execute('''
      CREATE TABLE IF NOT EXISTS orders (
        id TEXT PRIMARY KEY,
        server_id TEXT,
        order_number TEXT,
        customer_id TEXT,
        table_id TEXT,
        status TEXT DEFAULT 'pending',
        type TEXT,
        payment_type TEXT DEFAULT 'payment',
        subtotal REAL DEFAULT 0,
        tax REAL DEFAULT 0,
        total REAL DEFAULT 0,
        discount REAL DEFAULT 0,
        notes TEXT,
        items_json TEXT,
        pays_json TEXT,
        raw_json TEXT,
        branch_id INTEGER,
        is_local INTEGER DEFAULT 0,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── Invoices ──
    batch.execute('''
      CREATE TABLE IF NOT EXISTS invoices (
        id TEXT PRIMARY KEY,
        server_id TEXT,
        invoice_number TEXT,
        customer_id TEXT,
        order_id TEXT,
        status TEXT DEFAULT 'pending',
        type TEXT DEFAULT 'services',
        subtotal REAL DEFAULT 0,
        tax REAL DEFAULT 0,
        total REAL DEFAULT 0,
        items_json TEXT,
        pays_json TEXT,
        type_extra_json TEXT,
        raw_json TEXT,
        branch_id INTEGER,
        is_local INTEGER DEFAULT 0,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── Payment Methods ──
    batch.execute('''
      CREATE TABLE IF NOT EXISTS payment_methods (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        name_ar TEXT,
        is_active INTEGER DEFAULT 1,
        branch_id INTEGER,
        raw_json TEXT,
        updated_at TEXT
      )
    ''');

    // ── Branch Settings ──
    batch.execute('''
      CREATE TABLE IF NOT EXISTS branch_settings (
        branch_id INTEGER PRIMARY KEY,
        settings_json TEXT,
        logo_url TEXT,
        name TEXT,
        currency TEXT,
        tax_percentage REAL,
        updated_at TEXT
      )
    ''');

    // ── Promo Codes ──
    batch.execute('''
      CREATE TABLE IF NOT EXISTS promo_codes (
        id TEXT PRIMARY KEY,
        code TEXT,
        discount REAL,
        discount_type TEXT,
        max_discount REAL,
        min_pay REAL,
        duration_from TEXT,
        duration_to TEXT,
        max_use INTEGER,
        is_active INTEGER DEFAULT 1,
        branch_id INTEGER,
        raw_json TEXT,
        updated_at TEXT
      )
    ''');

    // ── Sync Queue ──
    batch.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation TEXT NOT NULL,
        endpoint TEXT NOT NULL,
        method TEXT NOT NULL DEFAULT 'POST',
        payload TEXT,
        local_ref_table TEXT,
        local_ref_id TEXT,
        status TEXT DEFAULT 'pending',
        retries INTEGER DEFAULT 0,
        max_retries INTEGER DEFAULT 5,
        error_message TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ── Countries & Cities (for customer forms) ──
    batch.execute('''
      CREATE TABLE IF NOT EXISTS countries (
        id INTEGER PRIMARY KEY,
        name TEXT,
        name_ar TEXT,
        name_en TEXT,
        currency TEXT,
        tax_percentage REAL,
        area_code TEXT,
        iso TEXT,
        raw_json TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS cities (
        id INTEGER PRIMARY KEY,
        country_id INTEGER,
        name TEXT,
        name_ar TEXT,
        name_en TEXT,
        raw_json TEXT
      )
    ''');

    // ── Reports Cache ──
    batch.execute('''
      CREATE TABLE IF NOT EXISTS reports_cache (
        cache_key TEXT PRIMARY KEY,
        data_json TEXT,
        branch_id INTEGER,
        updated_at TEXT
      )
    ''');

    // ── User / Auth Cache ──
    batch.execute('''
      CREATE TABLE IF NOT EXISTS auth_cache (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TEXT
      )
    ''');

    // Indexes for performance
    batch.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id)');
    batch.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_branch ON products(branch_id)');
    batch.execute(
        'CREATE INDEX IF NOT EXISTS idx_orders_branch ON orders(branch_id)');
    batch.execute(
        'CREATE INDEX IF NOT EXISTS idx_orders_synced ON orders(is_synced)');
    batch.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoices_branch ON invoices(branch_id)');
    batch.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoices_synced ON invoices(is_synced)');
    batch.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status)');
    batch.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_seller ON customers(seller_id)');

    await batch.commit(noResult: true);
    debugPrint('Offline database tables created');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE orders ADD COLUMN payment_type TEXT DEFAULT \'payment\'');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CATEGORIES
  // ═══════════════════════════════════════════════════════════════════

  Future<void> saveCategories(
      List<Map<String, dynamic>> categories, int branchId) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();
    for (final cat in categories) {
      final id = (cat['id'] ?? cat['category_id'] ?? cat['value'])?.toString();
      if (id == null || id.isEmpty) continue;
      batch.insert(
        'categories',
        {
          'id': id,
          'name': _extractName(cat),
          'name_ar': _extractNameLang(cat, 'ar'),
          'name_en': _extractNameLang(cat, 'en'),
          'type': cat['type']?.toString(),
          'parent_id': cat['parent_id']?.toString(),
          'image_url': (cat['icon'] ?? cat['image'] ?? cat['image_url'])
              ?.toString(),
          'branch_id': branchId,
          'raw_json': jsonEncode(cat),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCategories(int branchId) async {
    final db = await database;
    final rows = await db.query(
      'categories',
      where: 'branch_id = ?',
      whereArgs: [branchId],
    );
    return rows.map((row) {
      if (row['raw_json'] != null) {
        try {
          return jsonDecode(row['raw_json'] as String) as Map<String, dynamic>;
        } catch (_) {}
      }
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  PRODUCTS
  // ═══════════════════════════════════════════════════════════════════

  Future<void> saveProducts(
      List<Map<String, dynamic>> products, int branchId,
      {String? categoryId}) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();
    for (final prod in products) {
      final id = prod['id']?.toString();
      if (id == null || id.isEmpty) continue;
      batch.insert(
        'products',
        {
          'id': id,
          'name': _extractName(prod),
          'name_ar': _extractNameLang(prod, 'ar'),
          'name_en': _extractNameLang(prod, 'en'),
          'price': _toDouble(prod['price'] ?? prod['unit_price']),
          'category_id':
              (prod['category_id'] ?? prod['cat_id'])?.toString() ?? categoryId,
          'category_name': _extractName(
              prod['category_data'] ?? prod['category'] ?? prod),
          'is_active': (prod['is_active'] == true || prod['is_active'] == 1)
              ? 1
              : 0,
          'image': prod['image']?.toString(),
          'extras_json': jsonEncode(prod['extras'] ??
              prod['add_ons'] ??
              prod['addons'] ??
              prod['options'] ??
              []),
          'branch_id': branchId,
          'raw_json': jsonEncode(prod),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getProducts(int branchId,
      {String? categoryId}) async {
    final db = await database;
    String where = 'branch_id = ?';
    List<dynamic> whereArgs = [branchId];
    if (categoryId != null && categoryId != 'all') {
      where += ' AND category_id = ?';
      whereArgs.add(categoryId);
    }
    final rows = await db.query('products', where: where, whereArgs: whereArgs);
    return rows.map((row) {
      if (row['raw_json'] != null) {
        try {
          return jsonDecode(row['raw_json'] as String) as Map<String, dynamic>;
        } catch (_) {}
      }
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CUSTOMERS
  // ═══════════════════════════════════════════════════════════════════

  Future<void> saveCustomers(
      List<Map<String, dynamic>> customers, int sellerId) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();
    for (final cust in customers) {
      final id = cust['id']?.toString();
      if (id == null || id.isEmpty) continue;
      batch.insert(
        'customers',
        {
          'id': id,
          'name': _extractName(cust),
          'phone': (cust['phone'] ?? cust['mobile'])?.toString(),
          'email': cust['email']?.toString(),
          'tax_number': cust['tax_number']?.toString(),
          'address': cust['address']?.toString(),
          'seller_id': sellerId,
          'raw_json': jsonEncode(cust),
          'is_local': 0,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCustomers(int sellerId,
      {String? search}) async {
    final db = await database;
    String where = 'seller_id = ?';
    List<dynamic> whereArgs = [sellerId];
    if (search != null && search.isNotEmpty) {
      where += ' AND (name LIKE ? OR phone LIKE ? OR email LIKE ?)';
      final pattern = '%$search%';
      whereArgs.addAll([pattern, pattern, pattern]);
    }
    final rows =
        await db.query('customers', where: where, whereArgs: whereArgs);
    return rows.map((row) {
      if (row['raw_json'] != null) {
        try {
          return jsonDecode(row['raw_json'] as String) as Map<String, dynamic>;
        } catch (_) {}
      }
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  Future<String> saveLocalCustomer(Map<String, dynamic> customer, int sellerId) async {
    final db = await database;
    final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'customers',
      {
        'id': localId,
        'name': _extractName(customer),
        'phone': (customer['phone'] ?? customer['mobile'])?.toString(),
        'email': customer['email']?.toString(),
        'tax_number': customer['tax_number']?.toString(),
        'address': customer['address']?.toString(),
        'seller_id': sellerId,
        'raw_json': jsonEncode({...customer, 'id': localId}),
        'is_local': 1,
        'local_id': localId,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return localId;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  TABLES
  // ═══════════════════════════════════════════════════════════════════

  Future<void> saveTables(
      List<Map<String, dynamic>> tables, int branchId) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();
    for (final table in tables) {
      final id = (table['id'] ?? table['table_id'])?.toString();
      if (id == null || id.isEmpty) continue;
      batch.insert(
        'restaurant_tables',
        {
          'id': id,
          'name': (table['name'] ?? table['number'])?.toString(),
          'floor_id': table['floor_id']?.toString() ?? 'f1',
          'seats': _toInt(table['seats'] ?? table['chairs'] ?? 4),
          'status': table['status']?.toString() ?? 'available',
          'is_active':
              (table['is_active'] == true || table['is_active'] == 1) ? 1 : 0,
          'branch_id': branchId,
          'raw_json': jsonEncode(table),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getTables(int branchId) async {
    final db = await database;
    final rows = await db.query(
      'restaurant_tables',
      where: 'branch_id = ?',
      whereArgs: [branchId],
    );
    return rows.map((row) {
      if (row['raw_json'] != null) {
        try {
          return jsonDecode(row['raw_json'] as String) as Map<String, dynamic>;
        } catch (_) {}
      }
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ORDERS
  // ═══════════════════════════════════════════════════════════════════

  Future<String> saveLocalOrder(Map<String, dynamic> orderData, int branchId,
      {String paymentType = 'payment'}) async {
    final db = await database;
    final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'orders',
      {
        'id': localId,
        'server_id': null,
        'order_number': localId,
        'customer_id': orderData['customer_id']?.toString(),
        'table_id': orderData['table_id']?.toString(),
        'status': 'pending',
        'type': orderData['type']?.toString() ?? 'dine_in',
        'payment_type': paymentType,
        'subtotal': _toDouble(orderData['subtotal']),
        'tax': _toDouble(orderData['tax']),
        'total': _toDouble(orderData['total']),
        'discount': _toDouble(orderData['discount']),
        'notes': orderData['notes']?.toString(),
        'items_json': jsonEncode(orderData['items'] ?? orderData['card'] ?? []),
        'pays_json': jsonEncode(orderData['pays'] ?? []),
        'raw_json': jsonEncode(orderData),
        'branch_id': branchId,
        'is_local': 1,
        'is_synced': 0,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return localId;
  }

  Future<void> saveServerOrder(
      Map<String, dynamic> orderData, int branchId) async {
    final db = await database;
    final id = orderData['id']?.toString();
    if (id == null || id.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'orders',
      {
        'id': id,
        'server_id': id,
        'order_number':
            (orderData['order_number'] ?? orderData['booking_number'] ?? id)
                .toString(),
        'customer_id': orderData['customer_id']?.toString(),
        'table_id': (orderData['table_id'] ?? orderData['restaurant_table_id'])
            ?.toString(),
        'status': orderData['status']?.toString() ?? 'pending',
        'type': orderData['type']?.toString(),
        'subtotal': _toDouble(orderData['subtotal']),
        'tax': _toDouble(orderData['tax']),
        'total': _toDouble(orderData['total']),
        'discount': _toDouble(orderData['discount']),
        'notes': orderData['notes']?.toString(),
        'items_json': jsonEncode(orderData['booking_meals'] ??
            orderData['items'] ??
            orderData['card'] ??
            []),
        'pays_json': jsonEncode(orderData['pays'] ?? []),
        'raw_json': jsonEncode(orderData),
        'branch_id': branchId,
        'is_local': 0,
        'is_synced': 1,
        'created_at': orderData['created_at']?.toString() ?? now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveServerOrders(
      List<Map<String, dynamic>> orders, int branchId) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();
    for (final orderData in orders) {
      final id = orderData['id']?.toString();
      if (id == null || id.isEmpty) continue;
      batch.insert(
        'orders',
        {
          'id': id,
          'server_id': id,
          'order_number':
              (orderData['order_number'] ?? orderData['booking_number'] ?? id)
                  .toString(),
          'customer_id': orderData['customer_id']?.toString(),
          'table_id':
              (orderData['table_id'] ?? orderData['restaurant_table_id'])
                  ?.toString(),
          'status': orderData['status']?.toString() ?? 'pending',
          'type': orderData['type']?.toString(),
          'subtotal': _toDouble(orderData['subtotal']),
          'tax': _toDouble(orderData['tax']),
          'total': _toDouble(orderData['total']),
          'discount': _toDouble(orderData['discount']),
          'notes': orderData['notes']?.toString(),
          'items_json': jsonEncode(orderData['booking_meals'] ??
              orderData['items'] ??
              orderData['card'] ??
              []),
          'pays_json': jsonEncode(orderData['pays'] ?? []),
          'raw_json': jsonEncode(orderData),
          'branch_id': branchId,
          'is_local': 0,
          'is_synced': 1,
          'created_at': orderData['created_at']?.toString() ?? now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getOrders(int branchId) async {
    final db = await database;
    final rows = await db.query(
      'orders',
      where: 'branch_id = ?',
      whereArgs: [branchId],
      orderBy: 'created_at DESC',
    );
    return rows.map((row) {
      if (row['raw_json'] != null) {
        try {
          final parsed =
              jsonDecode(row['raw_json'] as String) as Map<String, dynamic>;
          // Inject local metadata
          parsed['_is_local'] = row['is_local'] == 1;
          parsed['_is_synced'] = row['is_synced'] == 1;
          parsed['_local_id'] = row['id'];
          return parsed;
        } catch (_) {}
      }
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getUnsyncedOrders() async {
    final db = await database;
    return await db.query(
      'orders',
      where: 'is_synced = 0 AND is_local = 1',
      orderBy: 'created_at ASC',
    );
  }

  /// Get the server ID for a local order ID (after sync).
  Future<String?> getOrderServerId(String localId) async {
    final db = await database;
    final rows = await db.query(
      'orders',
      columns: ['server_id'],
      where: 'id = ? AND server_id IS NOT NULL',
      whereArgs: [localId],
    );
    if (rows.isNotEmpty) return rows.first['server_id'] as String?;
    return null;
  }

  Future<void> markOrderSynced(String localId, String serverId) async {
    final db = await database;
    await db.update(
      'orders',
      {
        'server_id': serverId,
        'is_synced': 1,
        'is_local': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  INVOICES
  // ═══════════════════════════════════════════════════════════════════

  Future<String> saveLocalInvoice(
      Map<String, dynamic> invoiceData, int branchId) async {
    final db = await database;
    final localId = 'local_inv_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'invoices',
      {
        'id': localId,
        'server_id': null,
        'invoice_number': localId,
        'customer_id': invoiceData['customer_id']?.toString(),
        'order_id': invoiceData['order_id']?.toString(),
        'status': 'pending',
        'type': invoiceData['type']?.toString() ?? 'services',
        'subtotal': _toDouble(invoiceData['subtotal']),
        'tax': _toDouble(invoiceData['tax']),
        'total': _toDouble(invoiceData['total']),
        'items_json':
            jsonEncode(invoiceData['card'] ?? invoiceData['items'] ?? []),
        'pays_json': jsonEncode(invoiceData['pays'] ?? []),
        'type_extra_json': jsonEncode(invoiceData['type_extra'] ?? {}),
        'raw_json': jsonEncode(invoiceData),
        'branch_id': branchId,
        'is_local': 1,
        'is_synced': 0,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return localId;
  }

  Future<void> saveServerInvoice(
      Map<String, dynamic> invoiceData, int branchId) async {
    final db = await database;
    final id = invoiceData['id']?.toString();
    if (id == null || id.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'invoices',
      {
        'id': id,
        'server_id': id,
        'invoice_number':
            (invoiceData['invoice_number'] ?? id).toString(),
        'customer_id': invoiceData['customer_id']?.toString(),
        'order_id': invoiceData['booking_id']?.toString(),
        'status': invoiceData['status']?.toString() ?? 'completed',
        'type': invoiceData['type']?.toString() ?? 'services',
        'subtotal': _toDouble(invoiceData['subtotal']),
        'tax': _toDouble(invoiceData['tax']),
        'total': _toDouble(invoiceData['total']),
        'items_json': jsonEncode(
            invoiceData['card'] ?? invoiceData['items'] ?? []),
        'pays_json': jsonEncode(invoiceData['pays'] ?? []),
        'type_extra_json': jsonEncode(invoiceData['type_extra'] ?? {}),
        'raw_json': jsonEncode(invoiceData),
        'branch_id': branchId,
        'is_local': 0,
        'is_synced': 1,
        'created_at': invoiceData['created_at']?.toString() ?? now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveServerInvoices(
      List<Map<String, dynamic>> invoices, int branchId) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();
    for (final inv in invoices) {
      final id = inv['id']?.toString();
      if (id == null || id.isEmpty) continue;
      batch.insert(
        'invoices',
        {
          'id': id,
          'server_id': id,
          'invoice_number': (inv['invoice_number'] ?? id).toString(),
          'customer_id': inv['customer_id']?.toString(),
          'order_id': inv['booking_id']?.toString(),
          'status': inv['status']?.toString() ?? 'completed',
          'type': inv['type']?.toString() ?? 'services',
          'subtotal': _toDouble(inv['subtotal']),
          'tax': _toDouble(inv['tax']),
          'total': _toDouble(inv['total']),
          'items_json':
              jsonEncode(inv['card'] ?? inv['items'] ?? []),
          'pays_json': jsonEncode(inv['pays'] ?? []),
          'type_extra_json': jsonEncode(inv['type_extra'] ?? {}),
          'raw_json': jsonEncode(inv),
          'branch_id': branchId,
          'is_local': 0,
          'is_synced': 1,
          'created_at': inv['created_at']?.toString() ?? now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getInvoices(int branchId) async {
    final db = await database;
    final rows = await db.query(
      'invoices',
      where: 'branch_id = ?',
      whereArgs: [branchId],
      orderBy: 'created_at DESC',
    );
    return rows.map((row) {
      if (row['raw_json'] != null) {
        try {
          final parsed =
              jsonDecode(row['raw_json'] as String) as Map<String, dynamic>;
          parsed['_is_local'] = row['is_local'] == 1;
          parsed['_is_synced'] = row['is_synced'] == 1;
          parsed['_local_id'] = row['id'];
          return parsed;
        } catch (_) {}
      }
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getUnsyncedInvoices() async {
    final db = await database;
    return await db.query(
      'invoices',
      where: 'is_synced = 0 AND is_local = 1',
      orderBy: 'created_at ASC',
    );
  }

  Future<void> markInvoiceSynced(String localId, String serverId) async {
    final db = await database;
    await db.update(
      'invoices',
      {
        'server_id': serverId,
        'is_synced': 1,
        'is_local': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  PAYMENT METHODS
  // ═══════════════════════════════════════════════════════════════════

  Future<void> savePaymentMethods(
      List<Map<String, dynamic>> methods, int branchId) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();
    for (final method in methods) {
      final id = method['id']?.toString() ??
          method['name']?.toString() ??
          method['value']?.toString();
      if (id == null || id.isEmpty) continue;
      batch.insert(
        'payment_methods',
        {
          'id': id,
          'name': _extractName(method),
          'name_ar': _extractNameLang(method, 'ar'),
          'is_active':
              (method['is_active'] == true || method['is_active'] == 1) ? 1 : 0,
          'branch_id': branchId,
          'raw_json': jsonEncode(method),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getPaymentMethods(int branchId) async {
    final db = await database;
    final rows = await db.query(
      'payment_methods',
      where: 'branch_id = ?',
      whereArgs: [branchId],
    );
    return rows.map((row) {
      if (row['raw_json'] != null) {
        try {
          return jsonDecode(row['raw_json'] as String) as Map<String, dynamic>;
        } catch (_) {}
      }
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BRANCH SETTINGS
  // ═══════════════════════════════════════════════════════════════════

  Future<void> saveBranchSettings(
      int branchId, Map<String, dynamic> settings) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'branch_settings',
      {
        'branch_id': branchId,
        'settings_json': jsonEncode(settings),
        'logo_url': settings['logo']?.toString() ??
            settings['logo_url']?.toString(),
        'name': _extractName(settings),
        'currency': settings['currency']?.toString(),
        'tax_percentage': _toDouble(settings['tax_percentage'] ??
            settings['taxPercentage']),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getBranchSettings(int branchId) async {
    final db = await database;
    final rows = await db.query(
      'branch_settings',
      where: 'branch_id = ?',
      whereArgs: [branchId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    if (row['settings_json'] != null) {
      try {
        return jsonDecode(row['settings_json'] as String)
            as Map<String, dynamic>;
      } catch (_) {}
    }
    return Map<String, dynamic>.from(row);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  PROMO CODES
  // ═══════════════════════════════════════════════════════════════════

  Future<void> savePromoCodes(
      List<Map<String, dynamic>> codes, int branchId) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();
    for (final code in codes) {
      final id = code['id']?.toString();
      if (id == null || id.isEmpty) continue;
      batch.insert(
        'promo_codes',
        {
          'id': id,
          'code': (code['code'] ?? code['promocode'])?.toString(),
          'discount': _toDouble(code['discount']),
          'discount_type': code['discount_type']?.toString(),
          'max_discount': _toDouble(code['max_discount']),
          'min_pay': _toDouble(code['min_pay']),
          'duration_from': code['duration_from']?.toString(),
          'duration_to': code['duration_to']?.toString(),
          'max_use': _toInt(code['max_use']),
          'is_active':
              (code['is_active'] == true || code['is_active'] == 1) ? 1 : 0,
          'branch_id': branchId,
          'raw_json': jsonEncode(code),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getPromoCodes(int branchId) async {
    final db = await database;
    final rows = await db.query(
      'promo_codes',
      where: 'branch_id = ? AND is_active = 1',
      whereArgs: [branchId],
    );
    return rows.map((row) {
      if (row['raw_json'] != null) {
        try {
          return jsonDecode(row['raw_json'] as String) as Map<String, dynamic>;
        } catch (_) {}
      }
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SYNC QUEUE
  // ═══════════════════════════════════════════════════════════════════

  Future<int> addToSyncQueue({
    required String operation,
    required String endpoint,
    required String method,
    Map<String, dynamic>? payload,
    String? localRefTable,
    String? localRefId,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return await db.insert('sync_queue', {
      'operation': operation,
      'endpoint': endpoint,
      'method': method,
      'payload': payload != null ? jsonEncode(payload) : null,
      'local_ref_table': localRefTable,
      'local_ref_id': localRefId,
      'status': 'pending',
      'retries': 0,
      'max_retries': 5,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingSyncItems() async {
    final db = await database;
    return await db.query(
      'sync_queue',
      where: 'status = ? OR (status = ? AND retries < max_retries)',
      whereArgs: ['pending', 'failed'],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> updateSyncItemStatus(
      int id, String status, {String? errorMessage}) async {
    final db = await database;
    final updates = <String, dynamic>{
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (status == 'failed') {
      await db.rawUpdate(
        'UPDATE sync_queue SET status = ?, retries = retries + 1, error_message = ?, updated_at = ? WHERE id = ?',
        [status, errorMessage, DateTime.now().toIso8601String(), id],
      );
    } else {
      await db.update('sync_queue', updates, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> removeSyncItem(int id) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getPendingSyncCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sync_queue WHERE status IN (?, ?)',
      ['pending', 'failed'],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  REPORTS CACHE
  // ═══════════════════════════════════════════════════════════════════

  Future<void> cacheReport(
      String key, Map<String, dynamic> data, int branchId) async {
    final db = await database;
    await db.insert(
      'reports_cache',
      {
        'cache_key': '${branchId}_$key',
        'data_json': jsonEncode(data),
        'branch_id': branchId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getCachedReport(
      String key, int branchId) async {
    final db = await database;
    final rows = await db.query(
      'reports_cache',
      where: 'cache_key = ?',
      whereArgs: ['${branchId}_$key'],
    );
    if (rows.isEmpty) return null;
    try {
      return jsonDecode(rows.first['data_json'] as String)
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  COUNTRIES & CITIES
  // ═══════════════════════════════════════════════════════════════════

  Future<void> saveCountries(List<Map<String, dynamic>> countries) async {
    final db = await database;
    final batch = db.batch();
    for (final c in countries) {
      final id = _toInt(c['id']);
      if (id == null) continue;
      batch.insert(
        'countries',
        {
          'id': id,
          'name': _extractName(c),
          'name_ar': _extractNameLang(c, 'ar'),
          'name_en': _extractNameLang(c, 'en'),
          'currency': c['currency']?.toString(),
          'tax_percentage': _toDouble(c['tax_percentage']),
          'area_code': c['area_code']?.toString(),
          'iso': c['iso']?.toString(),
          'raw_json': jsonEncode(c),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCountries() async {
    final db = await database;
    final rows = await db.query('countries');
    return rows.map((row) {
      if (row['raw_json'] != null) {
        try {
          return jsonDecode(row['raw_json'] as String) as Map<String, dynamic>;
        } catch (_) {}
      }
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  Future<void> saveCities(
      List<Map<String, dynamic>> cities, int countryId) async {
    final db = await database;
    final batch = db.batch();
    for (final c in cities) {
      final id = _toInt(c['id']);
      if (id == null) continue;
      batch.insert(
        'cities',
        {
          'id': id,
          'country_id': countryId,
          'name': _extractName(c),
          'name_ar': _extractNameLang(c, 'ar'),
          'name_en': _extractNameLang(c, 'en'),
          'raw_json': jsonEncode(c),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCities(int countryId) async {
    final db = await database;
    final rows = await db.query('cities',
        where: 'country_id = ?', whereArgs: [countryId]);
    return rows.map((row) {
      if (row['raw_json'] != null) {
        try {
          return jsonDecode(row['raw_json'] as String) as Map<String, dynamic>;
        } catch (_) {}
      }
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════════════

  String _extractName(dynamic data) {
    if (data == null) return '';
    if (data is String) return data;
    if (data is Map) {
      // Try localized name
      final nameDisplay = data['name_display'];
      if (nameDisplay is Map) {
        return nameDisplay['ar']?.toString() ??
            nameDisplay['en']?.toString() ??
            '';
      }
      if (nameDisplay is String && nameDisplay.isNotEmpty) return nameDisplay;

      final name = data['name'];
      if (name is Map) {
        return name['ar']?.toString() ?? name['en']?.toString() ?? '';
      }
      if (name is String && name.isNotEmpty) return name;

      return data['label']?.toString() ??
          data['title']?.toString() ??
          data['name_ar']?.toString() ??
          data['name_en']?.toString() ??
          '';
    }
    return data.toString();
  }

  String? _extractNameLang(dynamic data, String lang) {
    if (data is! Map) return null;
    final name = data['name'];
    if (name is Map) return name[lang]?.toString();
    return data['name_$lang']?.toString();
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  /// Close the database
  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
