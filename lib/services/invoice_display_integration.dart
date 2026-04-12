import 'package:flutter/foundation.dart';
import '../services/api/invoice_service.dart';
import '../services/display_app_service.dart';

/// Invoice Display Integration
///
/// Connects Invoice API with Display App Ecosystem
/// When an invoice is created, it automatically:
/// 1. Updates Display App CDS with cart
/// 2. Sends order to KDS after payment
class InvoiceDisplayIntegration {
  final InvoiceService _invoiceService = InvoiceService();
  final DisplayAppService _displayService;

  InvoiceDisplayIntegration(this._displayService);

  double _toDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  /// Create invoice and update Display App
  Future<Map<String, dynamic>> createInvoiceWithDisplay({
    required int customerId,
    required List<Map<String, dynamic>> items,
    String type = 'services',
    Map<String, dynamic>? typeExtra,
    String? tableNumber,
  }) async {
    try {
      // Step 1: Calculate invoice
      final calculation = await _invoiceService.calculateInvoice(items: items);
      if (!calculation['success']) {
        return calculation;
      }

      final totals = calculation['data'];
      final subtotal = _toDouble(totals['subtotal']);
      final tax = _toDouble(totals['tax']);
      final total = _toDouble(totals['total']);

      // Step 2: Update Display App (CDS)
      if (_displayService.isConnected) {
        final orderNumber = 'INV-${DateTime.now().millisecondsSinceEpoch}';

        _displayService.updateCartDisplay(
          items: items,
          subtotal: subtotal,
          tax: tax,
          total: total,
          orderNumber: orderNumber,
          orderType: type == 'services' ? 'dine_in' : type,
          note: tableNumber != null ? 'Table: $tableNumber' : null,
        );

        debugPrint('✅ CDS updated with invoice cart');

        // Step 3: Setup callbacks for automatic KDS
        _displayService.setCallbacks(
          onPaymentSuccess: (transactionData) async {
            debugPrint('✅ Payment received, creating invoice...');

            // Create invoice after successful payment
            final invoiceResult = await _invoiceService.createInvoice(
              customerId: customerId,
              items: items,
              type: type,
              typeExtra: typeExtra,
            );

            if (invoiceResult['success']) {
              debugPrint('✅ Invoice created: ${invoiceResult['invoice_id']}');
            } else {
              debugPrint(
                  '❌ Failed to create invoice: ${invoiceResult['error']}');
            }
          },
        );

        // Step 4: Start payment on Display
        _displayService.startPayment(
          amount: total,
          orderNumber: orderNumber,
          customerReference: tableNumber,
        );

        debugPrint('🔔 Payment started on Display App');
      }

      return {
        'success': true,
        'totals': totals,
        'message': 'Display updated and payment initiated',
      };
    } catch (e) {
      debugPrint('❌ Error in invoice-display integration: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Direct invoice to KDS (skip payment - for pay later)
  Future<Map<String, dynamic>> sendInvoiceToKitchen({
    required int customerId,
    required List<Map<String, dynamic>> items,
    String type = 'services',
    Map<String, dynamic>? typeExtra,
    String? note,
  }) async {
    try {
      // Step 1: Create invoice immediately
      final invoiceResult = await _invoiceService.createInvoice(
        customerId: customerId,
        items: items,
        type: type,
        typeExtra: typeExtra,
      );

      if (!invoiceResult['success']) {
        return invoiceResult;
      }

      final invoice = invoiceResult['data'];
      final invoiceId = invoiceResult['invoice_id'];

      // Step 2: Calculate totals
      final calculation = await _invoiceService.calculateInvoice(items: items);
      final totals = calculation['data'];

      // Step 3: Send directly to KDS
      if (_displayService.isConnected) {
        _displayService.sendOrderToKitchen(
          orderId: invoiceId?.toString() ?? 'ORD-$invoiceId',
          orderNumber: invoiceId?.toString() ?? '#$invoiceId',
          orderType: type == 'services' ? 'dine_in' : type,
          items: items,
          note: note ?? 'Pay later',
          total: _toDouble(totals['total']),
        );

        debugPrint('✅ Invoice sent directly to KDS');
      }

      return {
        'success': true,
        'invoice': invoice,
        'invoice_id': invoiceId,
      };
    } catch (e) {
      debugPrint('❌ Error sending invoice to KDS: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get invoices and sync status
  Future<Map<String, dynamic>> getInvoicesForDisplay({
    String? dateFrom,
    String? dateTo,
    int page = 1,
  }) async {
    final result = await _invoiceService.getInvoices(
      dateFrom: dateFrom,
      dateTo: dateTo,
      page: page,
    );

    if (result['success']) {
      // Process invoices for display
      final invoices = result['data'] as List<dynamic>;
      final processedInvoices = invoices.map((inv) {
        return {
          'id': inv['id'],
          'number': inv['invoice_number'] ?? inv['id'].toString(),
          'total': inv['total'],
          'status': inv['status'],
          'created_at': inv['created_at'],
          'items_count': inv['card']?.length ?? 0,
        };
      }).toList();

      return {
        'success': true,
        'invoices': processedInvoices,
        'meta': result['meta'],
      };
    }

    return result;
  }
}

/// Helper class to convert cart items to invoice format
class InvoiceItemConverter {
  /// Convert cart items to invoice card format
  static List<Map<String, dynamic>> convertCartToInvoiceItems(
    List<Map<String, dynamic>> cartItems,
  ) {
    return cartItems.map((item) {
      return {
        'item_name': item['name'] ?? item['productName'] ?? 'Unknown',
        'meal_id': item['mealId'] ?? item['productId'] ?? item['id'],
        'price': item['price'] ?? item['unitPrice'] ?? 0.0,
        'unitPrice': item['unitPrice'] ?? item['price'] ?? 0.0,
        'modified_unit_price': item['modifiedPrice'],
        'quantity': item['quantity'] ?? 1,
        'extras': item['extras'] ?? item['selectedExtras'] ?? [],
      };
    }).toList();
  }

  /// Calculate invoice totals from items
  static Map<String, double> calculateTotals(
    List<Map<String, dynamic>> items, {
    double taxRate = 0.15, // 15% VAT
  }) {
    double subtotal = 0.0;

    for (final item in items) {
      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
      final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
      subtotal += price * quantity;
    }

    final tax = subtotal * taxRate;
    final total = subtotal + tax;

    return {
      'subtotal': subtotal,
      'tax': tax,
      'total': total,
    };
  }
}
