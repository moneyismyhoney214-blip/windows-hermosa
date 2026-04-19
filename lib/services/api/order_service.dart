library order_service;

import 'dart:convert';
import 'dart:io';

import 'base_client.dart';
import 'api_constants.dart';
import 'package:hermosa_pos/models/booking_invoice.dart';
import 'package:hermosa_pos/services/cache_service.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:hermosa_pos/services/offline/offline_pos_database.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';
import 'package:hermosa_pos/locator.dart';
import 'package:uuid/uuid.dart';

part 'order_service_parts/order_service.utilities.dart';
part 'order_service_parts/order_service.refund_logic.dart';
part 'order_service_parts/order_service.invoice_helpers.dart';
part 'order_service_parts/order_service.booking_helpers.dart';
part 'order_service_parts/order_service.booking_apis.dart';
part 'order_service_parts/order_service.invoice_apis.dart';
part 'order_service_parts/order_service.misc_apis.dart';
part 'order_service_parts/order_service.offline.dart';

// Cache key relocated to library-level so extensions can reference it.
const String _bookingCreateMetadataDisabledCacheKey =
    'booking_create_metadata_disabled';

class OrderService {
  final BaseClient _client = BaseClient();
  final CacheService _cache = getIt<CacheService>();
  final OfflineDatabaseService _offlineDb = OfflineDatabaseService();
  final OfflinePosDatabase _posDb = OfflinePosDatabase();
  final ConnectivityService _connectivity = ConnectivityService();
  final Uuid _uuid = const Uuid();
  final Map<String, Map<String, dynamic>> _lastOrderApiResponses = {};
  bool _skipBookingCreateMetadataEndpoint = false;

  Map<String, Map<String, dynamic>> get lastOrderApiResponses =>
      Map.unmodifiable(_lastOrderApiResponses);


  // ─────────────────────────────────────────────────────────
  // PRINT-RELATED METHODS (preserved verbatim, do not modify)
  // ─────────────────────────────────────────────────────────
  /// Update print count for booking
  Future<void> updateBookingPrintCount(String orderId) async {
    await _client.post(ApiConstants.bookingPrintCountEndpoint(orderId), {});
  }

  /// Generate kitchen receipt from backend by booking.
  /// Source of truth contract (Postman):
  /// POST /seller/kitchen-receipts/generate-by-booking
  /// body: { "booking_id": <id>, "kitchen_id": <id> }
  Future<Map<String, dynamic>> generateKitchenReceiptByBooking({
    required String bookingId,
    required int kitchenId,
  }) async {
    final normalizedBookingId = _normalizeBookingIdOrThrow(bookingId);
    final safeKitchenId = kitchenId <= 0 ? 1 : kitchenId;

    final response = await _client.post(
      ApiConstants.kitchenReceiptGenerateByBookingEndpoint,
      {
        'booking_id': int.tryParse(normalizedBookingId) ?? normalizedBookingId,
        'kitchen_id': safeKitchenId,
      },
    );
    return _rememberResponse('generate_kitchen_receipt', response);
  }

  // ─────────────────────────────────────────────────────────
  // PDF METHODS (preserved verbatim)
  // ─────────────────────────────────────────────────────────

  String _toAbsolutePdfUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final needsSlash = !trimmed.startsWith('/');
    return '${ApiConstants.baseUrl}${needsSlash ? '/' : ''}$trimmed';
  }

  bool _looksLikePdfPath(String value) {
    final lower = value.toLowerCase();
    if (lower.endsWith('.pdf')) return true;
    return lower.contains('/pdf');
  }

  String? _extractPdfUrlFromDynamic(dynamic node, {int depth = 0}) {
    if (node == null || depth > 6) return null;

    if (node is String) {
      final value = node.trim();
      if (value.isEmpty || !_looksLikePdfPath(value)) return null;
      return _toAbsolutePdfUrl(value);
    }

    if (node is List) {
      for (final item in node) {
        final extracted = _extractPdfUrlFromDynamic(item, depth: depth + 1);
        if (extracted != null && extracted.isNotEmpty) return extracted;
      }
      return null;
    }

    if (node is Map) {
      final map = node.map((k, v) => MapEntry(k.toString(), v));
      const preferredKeys = [
        'pdf_url',
        'receipt',
        'receipt_url',
        'invoice_pdf',
        'pdf',
        'pdfPath',
        'pdf_path',
        'file',
        'url',
      ];

      for (final key in preferredKeys) {
        final candidate = map[key];
        final extracted = _extractPdfUrlFromDynamic(
          candidate,
          depth: depth + 1,
        );
        if (extracted != null && extracted.isNotEmpty) return extracted;
      }

      for (final entry in map.entries) {
        final extracted = _extractPdfUrlFromDynamic(
          entry.value,
          depth: depth + 1,
        );
        if (extracted != null && extracted.isNotEmpty) return extracted;
      }
    }

    return null;
  }

  bool _isMissingClientPdfBug(ApiException error) {
    final message = error.message.toLowerCase();
    return message.contains('undefined array key') &&
        message.contains('client');
  }

  Future<String?> _resolvePdfUrlFromInvoiceDetails(String invoiceId) async {
    Future<Map<String, dynamic>> loadDetails() => getInvoice(invoiceId);
    Future<Map<String, dynamic>> loadHelper() => getInvoiceHelper(invoiceId);
    final loaders = <Future<Map<String, dynamic>> Function()>[
      loadDetails,
      loadHelper,
    ];

    for (final loader in loaders) {
      try {
        final response = await loader();
        final extracted = _extractPdfUrlFromDynamic(response);
        if (extracted != null && extracted.isNotEmpty) {
          return extracted;
        }
      } on ApiException catch (e) {
        final isNotFound = (e.statusCode ?? 0) == 404 ||
            e.message.toLowerCase().contains('route_not_found');
        if (!isNotFound) {
          // Continue trying alternative sources when available.
          continue;
        }
      } catch (_) {
        // Continue trying alternative sources when available.
      }
    }

    return null;
  }

  /// Get invoice PDF metadata / response
  Future<Map<String, dynamic>> getInvoicePdf(String invoiceId) async {
    final endpoint = ApiConstants.invoicePdfEndpoint(invoiceId);
    final endpointUrl = '${ApiConstants.baseUrl}$endpoint';
    try {
      final response = await _client.get(endpoint);
      final normalized = _rememberResponse('get_invoice_pdf', response);
      final extractedPdfUrl = _extractPdfUrlFromDynamic(normalized);

      if (extractedPdfUrl != null && extractedPdfUrl.isNotEmpty) {
        normalized['pdf_url'] = extractedPdfUrl;
      } else {
        // Backward-compatible fallback for environments that still return
        // a direct PDF response without metadata.
        normalized['pdf_url'] = endpointUrl;
      }

      normalized['pdf_endpoint'] = endpointUrl;
      return normalized;
    } on ApiException catch (e) {
      if (_isMissingClientPdfBug(e)) {
        final fallbackPdfUrl =
            await _resolvePdfUrlFromInvoiceDetails(invoiceId);
        if (fallbackPdfUrl != null && fallbackPdfUrl.isNotEmpty) {
          return _rememberResponse('get_invoice_pdf', {
            'status': 200,
            'message': 'resolved_from_invoice_details',
            'pdf_url': fallbackPdfUrl,
            'pdf_endpoint': endpointUrl,
            'fallback': true,
          });
        }
      }
      rethrow;
    }
  }

  /// Get invoice PDF endpoint that also triggers WhatsApp flow on backend.
  Future<Map<String, dynamic>> getInvoicePdfWithWhatsApp(
      String invoiceId) async {
    final endpoint = ApiConstants.invoicePdfWithWhatsAppEndpoint(invoiceId);
    final endpointUrl = '${ApiConstants.baseUrl}$endpoint';
    final response = await _client.get(endpoint);
    final normalized = _rememberResponse('get_invoice_pdf_whatsapp', response);
    final extractedPdfUrl = _extractPdfUrlFromDynamic(normalized);
    if (extractedPdfUrl != null && extractedPdfUrl.isNotEmpty) {
      normalized['pdf_url'] = extractedPdfUrl;
    } else {
      normalized['pdf_url'] = endpointUrl;
    }
    normalized['pdf_endpoint'] = endpointUrl;
    return normalized;
  }
}
