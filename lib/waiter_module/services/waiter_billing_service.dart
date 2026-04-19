import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../customer_display/nearpay/nearpay_bootstrap.dart';
import '../../customer_display/nearpay/nearpay_service.dart';
import '../../locator.dart';
import '../../models.dart';
import '../../services/api/api_constants.dart';
import '../../services/api/auth_service.dart';
import '../../services/api/branch_service.dart';
import '../../services/api/order_service.dart';
import '../../services/api/base_client.dart';
import '../../services/invoice_html_pdf_service.dart';
import '../models/waiter_table_event.dart';

/// Result of a completed bill flow.
///
/// `bookingId`/`invoiceId` can be non-null even on failure: e.g. the
/// backend accepted the booking but the NearPay SDK declined the card.
/// Callers use those to retry *without* duplicating the booking on the
/// backend (which would leave a ghost row with no invoice).
class WaiterBillResult {
  final bool success;
  final String? bookingId;
  final String? invoiceId;
  final String? invoiceNumber;
  final String? errorMessage;
  final String? paymentMethod;
  final String? transactionId;
  final String? receiptPdfPath;

  const WaiterBillResult.success({
    required this.bookingId,
    this.invoiceId,
    this.invoiceNumber,
    this.paymentMethod,
    this.transactionId,
    this.receiptPdfPath,
  })  : success = true,
        errorMessage = null;

  const WaiterBillResult.failure(
    this.errorMessage, {
    this.bookingId,
    this.invoiceId,
    this.invoiceNumber,
  })  : success = false,
        paymentMethod = null,
        transactionId = null,
        receiptPdfPath = null;
}

/// Orchestrates the waiter-side billing:
///   * Reads enabled payment methods from the user profile.
///   * Builds the booking payload from a waiter's cart items.
///   * Calls [OrderService.createBooking] to persist the order.
///   * Runs NearPay for card payments (when the branch has it enabled).
///
/// Designed to be called from a single place in the order screen so the
/// screen stays thin.
class WaiterBillingService {
  final OrderService _orderService;
  final AuthService _authService;
  final BranchService _branchService;
  final NearPayService _nearPay;
  final InvoiceHtmlPdfService _invoicePdf;

  /// Cached copy of the branch-enabled pay methods, refreshed when the
  /// waiter opens the order screen.
  Map<String, bool>? _payMethodsCache;

  /// Branch VAT rate (0.0–1.0). Loaded from BranchService so the waiter's
  /// invoice total matches what the cashier would produce for the same cart.
  double _taxRate = 0.0;
  bool _hasTax = false;

  double get taxRate => _taxRate;
  bool get hasTax => _hasTax;

  /// Compute tax-inclusive total the same way the cashier does:
  /// `subtotal * (1 + rate)` then round to 2 decimal places. Matches
  /// what the backend returns in the `(total)` validation hint.
  double applyTax(double subtotal) {
    if (!_hasTax || _taxRate <= 0 || subtotal <= 0) return _round2(subtotal);
    return _round2(subtotal * (1 + _taxRate));
  }

  double taxAmount(double subtotal) =>
      _hasTax && _taxRate > 0 && subtotal > 0
          ? _round2(subtotal * _taxRate)
          : 0.0;

  double _round2(double v) => double.parse(v.toStringAsFixed(2));

  WaiterBillingService({
    OrderService? orderService,
    AuthService? authService,
    BranchService? branchService,
    NearPayService? nearPay,
    InvoiceHtmlPdfService? invoicePdf,
  })  : _orderService = orderService ?? getIt<OrderService>(),
        _authService = authService ?? getIt<AuthService>(),
        _branchService = branchService ?? getIt<BranchService>(),
        _nearPay = nearPay ?? getIt<NearPayService>(),
        _invoicePdf = invoicePdf ?? getIt<InvoiceHtmlPdfService>();

  // ---------------------------------------------------------------------------
  // Profile helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _userOptions() {
    final user = _authService.getUser();
    final opts = user?['options'];
    if (opts is Map) {
      return opts.map((k, v) => MapEntry(k.toString(), v));
    }
    return const {};
  }

  /// Whether the current branch/profile has NearPay card payments on.
  bool get isNearPayEnabled => _userOptions()['nearpay'] == true;

  /// Hydrate the pay-method cache + tax settings from the same sources the
  /// cashier uses. Safe to call repeatedly — subsequent calls just refresh
  /// the in-memory copy.
  Future<Map<String, bool>> refreshPayMethods({bool force = false}) async {
    try {
      final cached = await _branchService.getCachedPayMethods();
      if (cached != null && !force) {
        _payMethodsCache = Map<String, bool>.from(cached);
      }
      final fresh =
          await _branchService.getEnabledPayMethods(forceRefresh: force);
      _payMethodsCache = Map<String, bool>.from(fresh);
    } catch (e) {
      debugPrint('⚠️ Waiter pay-methods refresh failed: $e');
    }
    await _refreshTaxConfig();
    return enabledPaymentMethods();
  }

  Future<void> _refreshTaxConfig() async {
    double? rate;
    bool? hasTax;

    // Primary source: BranchService.getBranchSettings() — same as cashier.
    try {
      final settings = await _branchService.getBranchSettings();
      rate = _findTaxRateInPayload(settings);
      hasTax = _findHasTaxInPayload(settings);
      debugPrint('🧾 [Waiter] tax from settings: rate=$rate hasTax=$hasTax');
    } catch (e) {
      debugPrint('⚠️ getBranchSettings failed: $e');
    }

    // Fallback: look up the current branch inside the raw branches list
    // (same fallback the cashier uses in _loadTaxConfiguration).
    if (rate == null || hasTax == null) {
      try {
        final branches = await _authService.getBranchesRaw();
        Map<String, dynamic>? current;
        for (final b in branches) {
          final bid = int.tryParse(b['id']?.toString() ?? '') ??
              int.tryParse(b['branch_id']?.toString() ?? '') ??
              0;
          if (bid == ApiConstants.branchId) {
            current = b;
            break;
          }
        }
        current ??= branches.isNotEmpty ? branches.first : null;
        if (current != null) {
          rate ??= _findTaxRateInPayload(current);
          hasTax ??= _findHasTaxInPayload(current);
          debugPrint(
              '🧾 [Waiter] tax from branches fallback: rate=$rate hasTax=$hasTax');
        }
      } catch (e) {
        debugPrint('⚠️ getBranchesRaw fallback failed: $e');
      }
    }

    // If we couldn't discover tax config anywhere, default to 15% VAT
    // (Saudi POS norm for this app). The cashier's branch settings often
    // expose the same value but under keys we don't know — without this
    // default the backend rejects our invoice (expected tax-inclusive
    // total ≠ pre-tax total we sent) and leaves a cancelled draft behind.
    if (rate == null) {
      rate = 0.15;
      debugPrint('🧾 [Waiter] tax rate defaulted to 15%');
    }
    hasTax ??= rate > 0;

    _taxRate = rate.clamp(0.0, 1.0);
    _hasTax = hasTax && _taxRate > 0;
    debugPrint(
        '🧾 [Waiter] effective tax: rate=$_taxRate hasTax=$_hasTax');
  }

  /// Deep-scan for a `tax_rate`-like field (mirrors the cashier's lookup).
  double? _findTaxRateInPayload(dynamic payload) {
    const keys = ['tax_rate', 'taxRate', 'tax_percentage', 'vat_rate'];
    double? parse(dynamic v) {
      if (v == null) return null;
      if (v is num) {
        final n = v.toDouble();
        if (n < 0) return null;
        return n > 1.0 ? (n / 100).clamp(0.0, 1.0) : n.clamp(0.0, 1.0);
      }
      if (v is String) {
        final cleaned = v.replaceAll('%', '').trim();
        final n = double.tryParse(cleaned);
        if (n == null || n < 0) return null;
        return n > 1.0 ? (n / 100).clamp(0.0, 1.0) : n.clamp(0.0, 1.0);
      }
      return null;
    }

    final queue = <dynamic>[payload];
    var guard = 0;
    while (queue.isNotEmpty && guard < 250) {
      guard++;
      final node = queue.removeLast();
      if (node is Map) {
        for (final k in keys) {
          final parsed = parse(node[k]);
          if (parsed != null) return parsed;
        }
        final nested = node['taxObject'] ?? node['tax_object'];
        if (nested is Map) queue.add(nested);
        for (final v in node.values) {
          if (v is Map || v is List) queue.add(v);
        }
      } else if (node is List) {
        for (final v in node) {
          if (v is Map || v is List) queue.add(v);
        }
      }
    }
    return null;
  }

  bool? _findHasTaxInPayload(dynamic payload) {
    const keys = ['has_tax', 'hasTax', 'tax_enabled', 'enable_tax'];
    bool? parse(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v > 0;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == 'true' || s == '1' || s == 'yes') return true;
        if (s == 'false' || s == '0' || s == 'no') return false;
      }
      return null;
    }

    final queue = <dynamic>[payload];
    var guard = 0;
    while (queue.isNotEmpty && guard < 250) {
      guard++;
      final node = queue.removeLast();
      if (node is Map) {
        for (final k in keys) {
          final parsed = parse(node[k]);
          if (parsed != null) return parsed;
        }
        for (final v in node.values) {
          if (v is Map || v is List) queue.add(v);
        }
      } else if (node is List) {
        for (final v in node) {
          if (v is Map || v is List) queue.add(v);
        }
      }
    }
    return null;
  }

  /// Payment methods the waiter's dialog should show — identical to the
  /// cashier's behavior: the source of truth is the branch settings
  /// (`BranchService.getEnabledPayMethods`). Card methods stay visible
  /// only when NearPay is also enabled on the profile. Pay-later is
  /// always on so the waiter can close the table and leave the invoice
  /// for the cashier to collect later.
  Map<String, bool> enabledPaymentMethods() {
    final fromBranch = _payMethodsCache ?? const <String, bool>{};
    final card = isNearPayEnabled;
    // Start from the full set the cashier tender dialog knows about.
    final methods = <String, bool>{
      'cash': fromBranch['cash'] ?? true,
      'card': (fromBranch['card'] ?? false) && card,
      'mada': (fromBranch['mada'] ?? false) && card,
      'visa': (fromBranch['visa'] ?? false) && card,
      'benefit': (fromBranch['benefit'] ?? false) && card,
      'stc': fromBranch['stc'] ?? false,
      'bank_transfer': fromBranch['bank_transfer'] ?? false,
      'wallet': fromBranch['wallet'] ?? false,
      'cheque': fromBranch['cheque'] ?? false,
      'petty_cash': fromBranch['petty_cash'] ?? false,
      'pay_later': true,
      'tabby': fromBranch['tabby'] ?? false,
      'tamara': fromBranch['tamara'] ?? false,
      'keeta': fromBranch['keeta'] ?? false,
      'my_fatoorah': fromBranch['my_fatoorah'] ?? false,
      'jahez': fromBranch['jahez'] ?? false,
      'talabat': fromBranch['talabat'] ?? false,
      'hunger_station': fromBranch['hunger_station'] ?? false,
    };
    return methods;
  }

  // ---------------------------------------------------------------------------
  // Booking payload
  // ---------------------------------------------------------------------------

  Map<String, dynamic> buildBookingPayload({
    required TableItem table,
    required List<CartItem> items,
    required int guests,
    required String waiterName,
    String? note,
  }) =>
      _buildBookingPayloadRaw(
        table: table,
        // Matches the cashier's invoiceItems shape line-for-line: meal_id
        // is cast to int, quantity is rounded+clamped, modified_unit_price
        // is explicitly null, discount is a percent.
        lines: items.map((it) {
          final mealIdInt = int.tryParse(it.product.id);
          return <String, dynamic>{
            'item_name': it.product.name,
            'meal_id': mealIdInt ?? it.product.id,
            'price': it.product.price,
            'unitPrice': it.product.price,
            'modified_unit_price': null,
            'quantity': it.quantity.round().clamp(1, 9999),
            'addons': it.selectedExtras
                .map((e) => int.tryParse(e.id) ?? e.id)
                .toList(),
            if (it.notes.isNotEmpty) 'note': it.notes,
            if (it.discount > 0) 'discount': it.discount,
            if (it.discount > 0) 'discount_type': '%',
          };
        }).toList(growable: false),
        guests: guests,
        waiterName: waiterName,
        note: note,
      );

  /// Build payload from a lightweight [TableItemSnapshot] list — used when
  /// the cashier creates the invoice on behalf of the waiter and only has
  /// the broadcast snapshot, not the original cart items.
  Map<String, dynamic> buildBookingPayloadFromSnapshot({
    required TableItem table,
    required List<TableItemSnapshot> items,
    required int guests,
    required String waiterName,
    String? note,
  }) =>
      _buildBookingPayloadRaw(
        table: table,
        lines: items
            .map((it) => <String, dynamic>{
                  'item_name': it.name,
                  if (it.mealId != null) 'meal_id': it.mealId,
                  'price': it.unitPrice,
                  'unitPrice': it.unitPrice,
                  'quantity': it.quantity,
                  'note': it.note ?? '',
                })
            .toList(growable: false),
        guests: guests,
        waiterName: waiterName,
        note: note,
      );

  Map<String, dynamic> _buildBookingPayloadRaw({
    required TableItem table,
    required List<Map<String, dynamic>> lines,
    required int guests,
    required String waiterName,
    String? note,
  }) {
    final now = DateTime.now();
    final dateStr =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    // Backend vocabulary: dine-in tables use `restaurant_internal` (aliases:
    // `restaurant_table`, `table`). `dine_in` is *not* accepted by this API.
    const orderType = 'restaurant_internal';
    final tableName = table.number.trim().isNotEmpty
        ? table.number.trim()
        : table.id;
    return {
      'type': orderType,
      'date': dateStr,
      'table_id': table.id,
      'type_extra': {
        'table_name': tableName,
        'guest_count': guests,
        'waiter': waiterName,
      },
      if (note != null && note.isNotEmpty) 'note': note,
      'card': lines,
      'meals': lines,
    };
  }

  // ---------------------------------------------------------------------------
  // Public flow
  // ---------------------------------------------------------------------------

  /// Create the booking, run NearPay if the selected pay contains a card
  /// method, and return a summary. Cash / pay-later flows skip NearPay.
  ///
  /// Pass [existingBookingId] when retrying a failed attempt — the
  /// service will skip the booking creation and reuse the given id, so
  /// a declined card followed by a cash retry doesn't leave two bookings
  /// (a ghost + a real one) on the backend.
  Future<WaiterBillResult> processBill({
    required TableItem table,
    required List<CartItem> items,
    required int guests,
    required String waiterName,
    required List<Map<String, dynamic>> pays,
    String? existingBookingId,
    void Function(String status)? onStatus,
  }) async {
    final total = items.fold<double>(0, (s, i) => s + i.totalPrice);
    return _processBillWithPayload(
      table: table,
      payload: buildBookingPayload(
        table: table,
        items: items,
        guests: guests,
        waiterName: waiterName,
      ),
      total: total,
      pays: pays,
      existingBookingId: existingBookingId,
      onStatus: onStatus,
    );
  }

  /// Variant used by the cashier — works off a [TableItemSnapshot] list
  /// (the same data it sees in the Details dialog) instead of [CartItem].
  Future<WaiterBillResult> processBillFromSnapshot({
    required TableItem table,
    required List<TableItemSnapshot> items,
    required int guests,
    required String waiterName,
    required List<Map<String, dynamic>> pays,
    String? existingBookingId,
    void Function(String status)? onStatus,
  }) async {
    final total = items.fold<double>(0, (s, i) => s + i.lineTotal);
    return _processBillWithPayload(
      table: table,
      payload: buildBookingPayloadFromSnapshot(
        table: table,
        items: items,
        guests: guests,
        waiterName: waiterName,
      ),
      total: total,
      pays: pays,
      existingBookingId: existingBookingId,
      onStatus: onStatus,
    );
  }

  Future<WaiterBillResult> _processBillWithPayload({
    required TableItem table,
    required Map<String, dynamic> payload,
    required double total,
    required List<Map<String, dynamic>> pays,
    String? existingBookingId,
    void Function(String status)? onStatus,
  }) async {
    String? bookingId = existingBookingId;
    String? orderId;
    String? invoiceId;
    String? invoiceNumber;
    try {
      final primaryMethod = _pickPrimaryMethod(pays);
      final payLater = primaryMethod == 'pay_later';

      // ─── 1. createBooking (skipped when retrying) ────────────────────
      if (bookingId == null) {
        onStatus?.call('creating_booking');
        final bookingResp = await _orderService.createBooking(
          payload,
          paymentType: payLater ? 'later' : 'payment',
        );
        final bookingData = _unwrapBookingData(bookingResp);
        bookingId = _stringify(bookingData['id'] ??
            bookingData['booking_id'] ??
            bookingResp['id']);
        orderId = _stringify(bookingData['order_id'] ??
            bookingData['order']?['id']);
        invoiceId = _stringify(
            bookingData['invoice_id'] ?? bookingData['invoice']?['id']);
        invoiceNumber = _stringify(bookingData['invoice_number'] ??
            bookingData['invoice']?['invoice_number']);
      } else {
        debugPrint(
            '♻️ Bill retry reusing booking $existingBookingId — skipping createBooking');
      }

      // ─── 2. NearPay (card payments) ───────────────────────────────────
      String? transactionId;
      final needsCard = _containsCardMethod(pays);
      if (needsCard) {
        if (!isNearPayEnabled) {
          return WaiterBillResult.failure(
            'NearPay is not enabled for this branch',
            bookingId: bookingId,
            invoiceId: invoiceId,
            invoiceNumber: invoiceNumber,
          );
        }
        onStatus?.call('preparing_nearpay');
        final initialized = await NearPayBootstrap.ensureInitialized();
        if (!initialized) {
          return WaiterBillResult.failure(
            'NearPay SDK could not be initialized',
            bookingId: bookingId,
            invoiceId: invoiceId,
            invoiceNumber: invoiceNumber,
          );
        }
        final referenceId = (bookingId ?? const Uuid().v4()).toString();
        final sessionId = const Uuid().v4();
        onStatus?.call('charging_card');
        final cardAmount = _cardAmountOf(pays, fallbackTotal: total);
        final result = await _nearPay.executePurchaseWithSession(
          amount: cardAmount,
          sessionId: sessionId,
          referenceId: referenceId,
          onStatusUpdate: (s) => onStatus?.call(s),
        );
        if (!result.success) {
          return WaiterBillResult.failure(
            result.errorMessage ?? 'Card payment failed',
            bookingId: bookingId,
            invoiceId: invoiceId,
            invoiceNumber: invoiceNumber,
          );
        }
        transactionId = result.transactionId;
      }

      // ─── 3. createInvoice (mirrors cashier's invoiceDataBase) ────────
      final dateStr = _todayIso();
      final normalizedPays =
          buildUpdatePaysPayload(pays, total, payLater: payLater);
      final lineItems = (payload['meals'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];

      if (invoiceId == null && !payLater) {
        onStatus?.call('creating_invoice');
        Map<String, dynamic> buildInvoiceData(
            List<Map<String, dynamic>> paysToUse) {
          return <String, dynamic>{
            'branch_id': ApiConstants.branchId,
            if (orderId != null) 'order_id': orderId,
            if (bookingId != null) 'booking_id': bookingId,
            'cash_back': 0,
            'date': dateStr,
            'pays': paysToUse,
            'items': lineItems,
            'card': lineItems,
            'meals': lineItems,
          };
        }

        Future<Map<String, dynamic>?> attempt(
            List<Map<String, dynamic>> paysToUse) async {
          try {
            return await _orderService.createInvoice(buildInvoiceData(paysToUse));
          } on ApiException catch (e) {
            // Backend authoritative total: "...يساوي إجمالي الفاتورة (16)."
            final expected = _extractExpectedTotal(e.message);
            if ((e.statusCode ?? 0) == 422 && expected != null && expected > 0) {
              debugPrint(
                  '♻️ Retrying createInvoice with backend total=$expected');
              final retryPays = buildUpdatePaysPayload(pays, expected);
              try {
                return await _orderService.createInvoice(
                    buildInvoiceData(retryPays));
              } on ApiException catch (retryError) {
                debugPrint(
                    '⚠️ createInvoice retry still failed: ${retryError.message}');
                rethrow;
              }
            }
            rethrow;
          }
        }

        try {
          final invResp = await attempt(normalizedPays);
          if (invResp != null) {
            final invData = _unwrapBookingData(invResp);
            invoiceId = _stringify(invData['id'] ??
                invData['invoice_id'] ??
                invData['invoice']?['id']);
            invoiceNumber = _stringify(invData['invoice_number'] ??
                invData['invoice']?['invoice_number'] ??
                invoiceNumber);
          }
        } catch (e) {
          debugPrint('⚠️ createInvoice failed — continuing with booking only: $e');
        }
      }

      // ─── 3b. updateInvoiceDate (aligns invoice date with booking date) ─
      if (invoiceId != null && !payLater) {
        try {
          await _orderService.updateInvoiceDate(
            invoiceId: invoiceId,
            date: dateStr,
          );
        } catch (e) {
          debugPrint('⚠️ updateInvoiceDate failed (non-fatal): $e');
        }
      }

      // ─── 4. updateInvoicePays (multi-tender reconciliation) ──────────
      if (invoiceId != null && !payLater) {
        onStatus?.call('updating_pays');
        try {
          await _orderService.updateInvoicePays(
            invoiceId,
            pays: normalizedPays,
            date: dateStr,
          );
        } on ApiException catch (e) {
          final expected = _extractExpectedTotal(e.message);
          if ((e.statusCode ?? 0) == 422 && expected != null && expected > 0) {
            try {
              await _orderService.updateInvoicePays(
                invoiceId,
                pays: buildUpdatePaysPayload(pays, expected),
                date: dateStr,
              );
            } catch (retryError) {
              debugPrint('⚠️ updateInvoicePays retry failed: $retryError');
            }
          } else {
            debugPrint('⚠️ updateInvoicePays failed (non-fatal): $e');
          }
        } catch (e) {
          debugPrint('⚠️ updateInvoicePays failed (non-fatal): $e');
        }
      }

      // ─── 5. Receipt PDF (best-effort) ────────────────────────────────
      String? receiptPath;
      if (invoiceId != null) {
        try {
          onStatus?.call('printing_receipt');
          receiptPath = await _invoicePdf.generatePdfFromInvoice(invoiceId);
        } catch (e) {
          debugPrint('⚠️ Receipt PDF generation failed: $e');
        }
      }

      onStatus?.call('done');
      return WaiterBillResult.success(
        bookingId: bookingId,
        invoiceId: invoiceId,
        invoiceNumber: invoiceNumber,
        paymentMethod: primaryMethod,
        transactionId: transactionId,
        receiptPdfPath: receiptPath,
      );
    } catch (e, st) {
      debugPrint('⚠️ Waiter bill flow failed: $e');
      debugPrintStack(stackTrace: st);
      return WaiterBillResult.failure(e.toString());
    }
  }

  /// Parse the backend's authoritative invoice total out of the
  /// validation-failure message, e.g.
  /// `... يساوي إجمالي الفاتورة (16).` → `16.0`.
  double? _extractExpectedTotal(String message) {
    final m = RegExp(r'\(([\d.]+)\)').firstMatch(message);
    final raw = m?.group(1);
    if (raw == null || raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  String _todayIso() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// Normalize a cashier-style pays list into the shape `updateInvoicePays`
  /// expects. Mirrors the cashier's `_buildUpdatePaysPayload` rounding +
  /// fallback-to-cash behavior so the backend validates identically.
  List<Map<String, dynamic>> buildUpdatePaysPayload(
    List<Map<String, dynamic>> pays,
    double invoiceTotal, {
    bool payLater = false,
  }) {
    double round2(double v) => double.parse(v.toStringAsFixed(2));
    num toBackendAmount(double v) {
      final r = round2(v);
      final i = r.roundToDouble();
      if ((r - i).abs() < 0.000001) return i.toInt();
      return r;
    }

    if (payLater) {
      return [
        {
          'name': 'دفع لاحق',
          'pay_method': 'pay_later',
          'amount': toBackendAmount(invoiceTotal),
          'index': 0,
        },
      ];
    }

    final out = <Map<String, dynamic>>[];
    var sum = 0.0;
    var idx = 0;
    for (final p in pays) {
      final method = _normalizePayMethod(p['pay_method']?.toString() ?? '');
      final amount = (p['amount'] as num?)?.toDouble() ??
          double.tryParse(p['amount']?.toString() ?? '') ??
          0.0;
      if (amount <= 0) continue;
      final r = round2(amount);
      out.add({
        'name': p['name']?.toString().trim().isNotEmpty == true
            ? p['name']
            : (method == 'card' ? 'البطاقة' : 'دفع نقدي'),
        'pay_method': method,
        'amount': toBackendAmount(r),
        'index': idx++,
      });
      sum += r;
    }
    if (out.isEmpty) {
      return [
        {
          'name': 'دفع نقدي',
          'pay_method': 'cash',
          'amount': toBackendAmount(invoiceTotal),
          'index': 0,
        }
      ];
    }
    // Close rounding gap on the last row so pays sum == invoiceTotal.
    final diff = round2(invoiceTotal - sum);
    if (diff.abs() >= 0.01) {
      final last = out.last;
      final adjusted = round2(((last['amount'] as num).toDouble()) + diff);
      out[out.length - 1] = {
        ...last,
        'amount': toBackendAmount(adjusted),
      };
    }
    return out;
  }

  String _normalizePayMethod(String raw) {
    final m = raw.trim().toLowerCase();
    const cardAliases = {'mada', 'visa', 'benefit', 'card'};
    if (cardAliases.contains(m)) return 'card';
    if (m == 'pay_later') return 'pay_later';
    return m.isEmpty ? 'cash' : m;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  String _pickPrimaryMethod(List<Map<String, dynamic>> pays) {
    if (pays.isEmpty) return 'cash';
    // The method with the largest amount is treated as primary — matches
    // what the cashier flow does when deciding NearPay.
    pays.sort((a, b) {
      final av = (a['amount'] as num?)?.toDouble() ?? 0;
      final bv = (b['amount'] as num?)?.toDouble() ?? 0;
      return bv.compareTo(av);
    });
    return pays.first['pay_method']?.toString() ?? 'cash';
  }

  bool _containsCardMethod(List<Map<String, dynamic>> pays) {
    const cardLike = {'card', 'mada', 'visa', 'benefit'};
    return pays.any((p) => cardLike.contains(p['pay_method']));
  }

  double _cardAmountOf(List<Map<String, dynamic>> pays,
      {required double fallbackTotal}) {
    const cardLike = {'card', 'mada', 'visa', 'benefit'};
    final sum = pays
        .where((p) => cardLike.contains(p['pay_method']))
        .fold<double>(0, (s, p) => s + ((p['amount'] as num?)?.toDouble() ?? 0));
    return sum > 0 ? sum : fallbackTotal;
  }

  Map<String, dynamic> _unwrapBookingData(Map<String, dynamic> resp) {
    final data = resp['data'];
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    return resp;
  }

  String? _stringify(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  // Expose to callers that want to reference global constants from this
  // service without pulling ApiConstants themselves.
  String get currency => ApiConstants.currency;
}
