import 'package:flutter/foundation.dart';
import 'base_client.dart';
import 'api_constants.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';

/// Invoice Service for Hermosa POS
///
/// Handles all invoice-related API operations including:
/// - Get invoices list
/// - Get invoice details
/// - Create new invoice
/// - Update invoice
/// - Delete invoice
/// - Link with Display App ecosystem
class InvoiceService {
  final BaseClient _client = BaseClient();
  final OfflineDatabaseService _offlineDb = OfflineDatabaseService();
  final ConnectivityService _connectivity = ConnectivityService();

  /// Get list of invoices
  ///
  /// [dateFrom] Start date (YYYY-MM-DD)
  /// [dateTo] End date (YYYY-MM-DD)
  /// [status] Invoice status filter
  /// [search] Search query
  /// [invoiceType] Type of invoice
  /// [page] Page number (default: 1)
  /// [perPage] Items per page (default: 20)
  Future<Map<String, dynamic>> getInvoices({
    String? dateFrom,
    String? dateTo,
    String? status,
    String? search,
    String? invoiceType,
    int page = 1,
    int perPage = 20,
  }) async {
    // OFFLINE MODE: Return from local database
    if (_connectivity.isOffline) {
      return _getInvoicesOffline();
    }

    try {
      // Build query parameters
      final queryParams = <String, String>{
        'page': page.toString(),
        'per_page': perPage.toString(),
      };

      if (dateFrom != null && dateFrom.isNotEmpty) {
        queryParams['date_from'] = dateFrom;
      }
      if (dateTo != null && dateTo.isNotEmpty) {
        queryParams['date_to'] = dateTo;
      }
      if (status != null && status.isNotEmpty) {
        queryParams['status'] = status;
      }
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      if (invoiceType != null && invoiceType.isNotEmpty) {
        queryParams['invoice_type'] = invoiceType;
      }

      final queryString = queryParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final endpoint = '${ApiConstants.invoicesEndpoint}?$queryString';

      debugPrint('📊 Fetching invoices: $endpoint');

      final response = await _client.get(endpoint);
      if (response is! Map<String, dynamic>) {
        throw Exception('Invalid invoices response format');
      }

      // Save to SQLite for offline use
      if (response['data'] is List && page == 1) {
        await _offlineDb.saveServerInvoices(
          (response['data'] as List).cast<Map<String, dynamic>>(),
          ApiConstants.branchId,
        );
      }

      debugPrint(
          '✅ Fetched ${(response['data'] as List?)?.length ?? 0} invoices');
      return {
        'success': true,
        'data': response['data'] ?? [],
        'meta': response['meta'] ?? {},
      };
    } catch (e) {
      debugPrint('Error fetching invoices, trying offline: $e');
      return _getInvoicesOffline();
    }
  }

  /// Get invoices from local database
  Future<Map<String, dynamic>> _getInvoicesOffline() async {
    try {
      final localInvoices =
          await _offlineDb.getInvoices(ApiConstants.branchId);
      return {
        'success': true,
        'data': localInvoices,
        '_offline': true,
      };
    } catch (e) {
      return {
        'success': true,
        'data': [],
        '_offline': true,
      };
    }
  }

  /// Get invoice details by ID
  Future<Map<String, dynamic>> getInvoiceDetails(String invoiceId) async {
    try {
      final endpoint = ApiConstants.invoiceDetailsEndpoint(invoiceId);

      debugPrint('📄 Fetching invoice details: $invoiceId');

      final response = await _client.get(endpoint);
      if (response is! Map<String, dynamic>) {
        throw Exception('Invalid invoice details response format');
      }

      debugPrint('✅ Fetched invoice details');
      return {
        'success': true,
        'data': response['data'] ?? response,
      };
    } catch (e) {
      debugPrint('❌ Error fetching invoice details: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Create new invoice
  ///
  /// [customerId] Customer ID
  /// [items] List of items (card)
  /// [type] Invoice type (e.g., 'services')
  /// [typeExtra] Additional type info (table, car, etc.)
  /// [pays] List of payment methods
  Future<Map<String, dynamic>> createInvoice({
    required int customerId,
    required List<Map<String, dynamic>> items,
    String type = 'services',
    Map<String, dynamic>? typeExtra,
    List<Map<String, dynamic>>? pays,
  }) async {
    try {
      final body = {
        'customer_id': customerId,
        'branch_id': ApiConstants.branchId,
        'date': DateTime.now().toIso8601String().substring(0, 10),
        'card': items,
        'pays': pays ??
            [
              {
                'name': 'Cash',
                'pay_method': 'cash',
                'amount': items.fold<double>(
                    0,
                    (sum, item) =>
                        sum +
                        ((item['price'] as num?)?.toDouble() ?? 0) *
                            ((item['quantity'] as num?)?.toInt() ?? 1)),
                'index': 0
              }
            ],
        'type': type,
        'type_extra': typeExtra ??
            {
              'car_number': null,
              'table_name': null,
              'latitude': null,
              'longitude': null,
            },
      };

      debugPrint('📝 Creating invoice for customer: $customerId');
      debugPrint('📝 Items: ${items.length}');

      final response = await _client.post(
        ApiConstants.invoicesEndpoint,
        body,
      );
      if (response is! Map<String, dynamic>) {
        throw Exception('Invalid create invoice response format');
      }

      debugPrint('✅ Invoice created successfully');
      return {
        'success': true,
        'data': response['data'] ?? response,
        'invoice_id': response['data']?['id'],
      };
    } catch (e) {
      debugPrint('❌ Error creating invoice: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Update existing invoice
  Future<Map<String, dynamic>> updateInvoice(
    String invoiceId, {
    required Map<String, dynamic> data,
  }) async {
    try {
      final endpoint = ApiConstants.invoiceDetailsEndpoint(invoiceId);

      debugPrint('📝 Updating invoice: $invoiceId');

      final response = await _client.put(
        endpoint,
        data,
      );
      if (response is! Map<String, dynamic>) {
        throw Exception('Invalid update invoice response format');
      }

      debugPrint('✅ Invoice updated successfully');
      return {
        'success': true,
        'data': response['data'] ?? response,
      };
    } catch (e) {
      debugPrint('❌ Error updating invoice: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Delete invoice
  Future<Map<String, dynamic>> deleteInvoice(String invoiceId) async {
    try {
      final endpoint = ApiConstants.invoiceDetailsEndpoint(invoiceId);

      debugPrint('🗑️ Deleting invoice: $invoiceId');

      await _client.delete(endpoint);
      debugPrint('✅ Invoice deleted successfully');
      return {
        'success': true,
      };
    } catch (e) {
      debugPrint('❌ Error deleting invoice: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Calculate invoice (get totals before creating)
  Future<Map<String, dynamic>> calculateInvoice({
    required List<Map<String, dynamic>> items,
    num discount = 0,
    int? promocodeId,
  }) async {
    try {
      final body = {
        'items': items,
        'discount': discount,
        'promocode_id': promocodeId,
      };

      debugPrint('🧮 Calculating invoice totals');

      dynamic response;
      try {
        response = await _client.post(
          ApiConstants.calculateInvoiceEndpoint,
          body,
        );
      } on ApiException catch (e) {
        // Some accounts still expect "card" instead of "items".
        if (!e.message.contains('السلة')) rethrow;
        response = await _client.post(
          ApiConstants.calculateInvoiceEndpoint,
          {
            'card': items,
            'discount': discount,
            'promocode_id': promocodeId,
          },
        );
      }
      if (response is! Map<String, dynamic>) {
        throw Exception('Invalid calculate invoice response format');
      }

      final data = response['data'] ?? response;
      debugPrint('✅ Invoice calculated');
      return {
        'success': true,
        'data': data,
        'subtotal': data['subtotal'],
        'tax': data['tax'],
        'total': data['total'],
      };
    } catch (e) {
      debugPrint('❌ Error calculating invoice: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Complete invoice and payment workflow with Display App ecosystem
  ///
  /// This integrates with the Display App ecosystem:
  /// 1. Creates invoice in backend
  /// 2. Sends order to Display App (KDS)
  /// 3. Updates Display App CDS with cart
  /// 4. Processes payment
  Future<Map<String, dynamic>> completeInvoiceWorkflow({
    required int customerId,
    required List<Map<String, dynamic>> items,
    String type = 'services',
    Map<String, dynamic>? typeExtra,
    Function(Map<String, dynamic>)? onInvoiceCreated,
    Function(Map<String, dynamic>)? onPaymentSuccess,
  }) async {
    try {
      // Step 1: Calculate invoice first
      final calculation = await calculateInvoice(items: items);
      if (!calculation['success']) {
        return calculation;
      }

      final totals = calculation['data'];

      // Step 2: Create invoice
      final invoiceResult = await createInvoice(
        customerId: customerId,
        items: items,
        type: type,
        typeExtra: typeExtra,
      );

      if (!invoiceResult['success']) {
        return invoiceResult;
      }

      // Notify callback
      if (onInvoiceCreated != null) {
        onInvoiceCreated(invoiceResult['data']);
      }

      // Step 3: Return complete data for Display App integration
      return {
        'success': true,
        'invoice': invoiceResult['data'],
        'totals': totals,
        'display_data': {
          'items': items,
          'subtotal': totals['subtotal'],
          'tax': totals['tax'],
          'total': totals['total'],
          'orderNumber': invoiceResult['data']?['id']?.toString() ?? '',
          'invoice_id': invoiceResult['invoice_id'],
        },
      };
    } catch (e) {
      debugPrint('❌ Error in complete workflow: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}

/// Invoice Model
class Invoice {
  final int? id;
  final String? invoiceNumber;
  final int? customerId;
  final List<InvoiceItem>? items;
  final double? subtotal;
  final double? tax;
  final double? total;
  final String? status;
  final String? type;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Invoice({
    this.id,
    this.invoiceNumber,
    this.customerId,
    this.items,
    this.subtotal,
    this.tax,
    this.total,
    this.status,
    this.type,
    this.createdAt,
    this.updatedAt,
  });

  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      id: json['id'],
      invoiceNumber: json['invoice_number']?.toString(),
      customerId: json['customer_id'],
      items: json['card'] != null
          ? (json['card'] as List)
              .map((item) => InvoiceItem.fromJson(item))
              .toList()
          : null,
      subtotal: json['subtotal']?.toDouble(),
      tax: json['tax']?.toDouble(),
      total: json['total']?.toDouble(),
      status: json['status'],
      type: json['type'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'invoice_number': invoiceNumber,
      'customer_id': customerId,
      'card': items?.map((item) => item.toJson()).toList(),
      'subtotal': subtotal,
      'tax': tax,
      'total': total,
      'status': status,
      'type': type,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

/// Invoice Item Model
class InvoiceItem {
  final String? itemName;
  final int? mealId;
  final double? price;
  final double? unitPrice;
  final double? modifiedUnitPrice;
  final int? quantity;
  final List<Map<String, dynamic>>? extras;

  InvoiceItem({
    this.itemName,
    this.mealId,
    this.price,
    this.unitPrice,
    this.modifiedUnitPrice,
    this.quantity,
    this.extras,
  });

  factory InvoiceItem.fromJson(Map<String, dynamic> json) {
    return InvoiceItem(
      itemName: json['item_name'] ?? json['name'],
      mealId: json['meal_id'],
      price: json['price']?.toDouble(),
      unitPrice: json['unitPrice']?.toDouble(),
      modifiedUnitPrice: json['modified_unit_price']?.toDouble(),
      quantity: json['quantity'],
      extras: json['extras'] != null
          ? List<Map<String, dynamic>>.from(json['extras'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'item_name': itemName,
      'meal_id': mealId,
      'price': price,
      'unitPrice': unitPrice,
      'modified_unit_price': modifiedUnitPrice,
      'quantity': quantity,
      'extras': extras,
    };
  }
}
