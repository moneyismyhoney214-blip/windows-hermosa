import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../locator.dart';
import '../../models.dart';
import '../../models/receipt_data.dart';
import '../../services/api/auth_service.dart';
import '../../services/api/device_service.dart';
import '../../services/api/order_service.dart';
import '../../services/print_orchestrator_service.dart';
import '../../services/printer_role_registry.dart';
import '../../services/printer_language_settings_service.dart';
import '../../services/printer_service.dart';
import 'waiter_device_prefs.dart';

/// Waiter-facing mirror of the cashier's print triggers. Kept thin —
/// the underlying [PrintOrchestratorService] / [PrinterService] do the
/// real work, we just feed them data shaped like what the cashier sends.
///
/// Two jobs:
///   * [printKitchenTicket] — fires after a pay-later booking so the
///     kitchen gets a physical ticket in addition to the KDS push.
///   * [printCashierReceipt] — fires after a pay-now invoice so the
///     customer gets the cashier-role thermal receipt (honors the
///     second-copy toggle, same as the cashier).
///
/// Both respect the device-level toggles in [WaiterDevicePrefKeys] so a
/// waiter who disables "printing kitchen invoices" or turns on
/// "allow print with KDS" sees identical gating to the cashier.
class WaiterPrintDispatcher {
  WaiterPrintDispatcher({
    PrintOrchestratorService? orchestrator,
    PrinterService? printerService,
    DeviceService? deviceService,
    PrinterRoleRegistry? roleRegistry,
    OrderService? orderService,
    AuthService? authService,
  })  : _orchestrator = orchestrator ?? getIt<PrintOrchestratorService>(),
        _printerService = printerService ?? getIt<PrinterService>(),
        _deviceService = deviceService ?? getIt<DeviceService>(),
        _roleRegistry = roleRegistry ?? getIt<PrinterRoleRegistry>(),
        _orderService = orderService ?? getIt<OrderService>(),
        _authService = authService ?? getIt<AuthService>();

  final PrintOrchestratorService _orchestrator;
  final PrinterService _printerService;
  final DeviceService _deviceService;
  final PrinterRoleRegistry _roleRegistry;
  final OrderService _orderService;
  final AuthService _authService;

  // ---------------------------------------------------------------------------
  // Preferences
  // ---------------------------------------------------------------------------

  Future<bool> _readBool(String key, {required bool fallback}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  // ---------------------------------------------------------------------------
  // Printer discovery
  // ---------------------------------------------------------------------------

  Future<List<DeviceConfig>> _loadPrinters() async {
    try {
      final devices = await _deviceService.getDevices();
      return devices.where(_isUsablePrinter).toList(growable: false);
    } catch (_) {
      try {
        final cached = await _deviceService.getCachedDevices();
        return cached.where(_isUsablePrinter).toList(growable: false);
      } catch (_) {
        return const <DeviceConfig>[];
      }
    }
  }

  bool _isUsablePrinter(DeviceConfig d) {
    final type = d.type.trim().toLowerCase();
    if (type != 'printer') return false;
    // Both Bluetooth (name-only) and TCP (ip/port) printers are usable.
    final hasBt = d.name.trim().isNotEmpty;
    final hasTcp = d.ip.trim().isNotEmpty;
    return hasBt || hasTcp;
  }

  Future<List<DeviceConfig>> _kitchenRolePrinters(
      List<DeviceConfig> printers) async {
    await _roleRegistry.initialize();
    return printers.where((p) {
      final role = _roleRegistry.resolveRole(p);
      return role == PrinterRole.kitchen ||
          role == PrinterRole.kds ||
          role == PrinterRole.bar;
    }).toList(growable: false);
  }

  Future<List<DeviceConfig>> _cashierRolePrinters(
      List<DeviceConfig> printers) async {
    await _roleRegistry.initialize();
    final matches = printers
        .where(
            (p) => _roleRegistry.resolveRole(p) == PrinterRole.cashierReceipt)
        .toList(growable: false);
    if (matches.isNotEmpty) return matches;
    // Fall back to any non-kitchen printer — same rule as the cashier's
    // _resolvePrintersForRole(PrinterRole.cashierReceipt) fallback.
    return printers.where((p) {
      final role = _roleRegistry.resolveRole(p);
      return role != PrinterRole.kitchen &&
          role != PrinterRole.kds &&
          role != PrinterRole.bar;
    }).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Kitchen print (pay-later)
  // ---------------------------------------------------------------------------

  /// Enqueues a kitchen ticket for a booking the waiter just submitted.
  /// Returns `true` if a job was queued, `false` if gated out (toggle off
  /// or no printers). Non-fatal — callers should fire-and-forget.
  Future<bool> printKitchenTicket({
    required String bookingId,
    required String orderNumber,
    required List<CartItem> items,
    required String tableNumber,
    required String waiterName,
    String? invoiceNumber,
    /// `true` when the KDS broadcast already delivered the order. Used
    /// with the allowPrintWithKds toggle to decide whether to print too.
    bool kdsAlreadyDispatched = false,
  }) async {
    if (items.isEmpty) return false;

    final allowWithKds = await _readBool(
      WaiterDevicePrefKeys.allowPrintWithKds,
      fallback: false,
    );
    final kdsEnabled = await _readBool(
      WaiterDevicePrefKeys.kdsEnabled,
      fallback: true,
    );
    final printKitchen = await _readBool(
      WaiterDevicePrefKeys.printKitchenInvoices,
      fallback: true,
    );
    if (!printKitchen) return false;

    // Mirror main_screen.payment:2943 — when KDS delivered the order and
    // allowPrintWithKds is off, skip the paper kitchen ticket. Pay-later
    // callers should pass kdsAlreadyDispatched=true; see _payLater.
    if (kdsAlreadyDispatched && kdsEnabled && !allowWithKds) {
      return false;
    }

    final printers = await _loadPrinters();
    if (printers.isEmpty) return false;
    final kitchenPrinters = await _kitchenRolePrinters(printers);
    if (kitchenPrinters.isEmpty) return false;

    final wireItems = items.map(_toWireItem).toList(growable: false);
    final langSettings = printerLanguageSettings;

    try {
      await _orchestrator.enqueueKitchenPrint(
        printers: kitchenPrinters,
        orderNumber: orderNumber,
        orderType: 'restaurant_internal',
        items: wireItems,
        invoiceNumber: invoiceNumber,
        tableNumber: tableNumber,
        cashierName: waiterName,
        isRtl: true,
        primaryLang: langSettings.primary,
        secondaryLang: langSettings.secondary,
        allowSecondary:
            langSettings.primary != langSettings.secondary,
      );
      return true;
    } catch (e) {
      // Orchestrator already retries internally; swallow so a down
      // printer doesn't fail the whole pay-later flow.
      return false;
    }
  }

  Map<String, dynamic> _toWireItem(CartItem item) {
    final extras = item.selectedExtras
        .map((e) => {
              'id': e.id,
              'name': e.name,
              'price': e.price,
            })
        .toList(growable: false);
    final qtyInt = item.quantity == item.quantity.toInt()
        ? item.quantity.toInt()
        : item.quantity;
    return <String, dynamic>{
      'name': item.product.name,
      'nameAr': item.product.name,
      'quantity': qtyInt,
      'price': item.product.price,
      'unit_price': item.product.price,
      'total_price': item.totalPrice,
      'notes': item.notes,
      if (extras.isNotEmpty) 'addons': extras,
      if (extras.isNotEmpty) 'extras': extras,
      'category_id': item.product.categoryId,
    };
  }

  // ---------------------------------------------------------------------------
  // Cashier receipt (pay-now)
  // ---------------------------------------------------------------------------

  /// Prints the cashier-role thermal receipt for a just-created invoice.
  /// Reads the invoice back from the backend so the printed copy matches
  /// what the server persisted (invoice number, totals, payments). Falls
  /// back to locally-known values if the fetch fails.
  ///
  /// Returns `true` if at least one physical print landed.
  Future<bool> printCashierReceipt({
    required String invoiceId,
    String? invoiceNumber,
    String? dailyOrderNumber,
    required List<CartItem> items,
    required double totalInclVat,
    required double vatRate,
    required String tableNumber,
    required String waiterName,
    required List<Map<String, dynamic>> pays,
  }) async {
    final autoPrint = await _readBool(
      WaiterDevicePrefKeys.autoPrintCashier,
      fallback: true,
    );
    if (!autoPrint) return false;

    final printers = await _loadPrinters();
    if (printers.isEmpty) return false;
    final cashierPrinters = await _cashierRolePrinters(printers);
    if (cashierPrinters.isEmpty) return false;

    final secondCopy = await _readBool(
      WaiterDevicePrefKeys.autoPrintCustomerSecondCopy,
      fallback: false,
    );
    final totalCopies = secondCopy ? 2 : 1;

    // Try to fetch the canonical invoice payload; fall back to locally-
    // known values if the fetch fails so we still print *something*.
    Map<String, dynamic>? invoicePayload;
    try {
      invoicePayload = await _orderService.getInvoice(invoiceId);
    } catch (_) {
      invoicePayload = null;
    }

    final receiptData = _buildReceiptData(
      invoicePayload: invoicePayload,
      fallbackInvoiceNumber: invoiceNumber ?? invoiceId,
      dailyOrderNumber: dailyOrderNumber,
      items: items,
      totalInclVat: totalInclVat,
      vatRate: vatRate,
      tableNumber: tableNumber,
      waiterName: waiterName,
      pays: pays,
    );

    var anyPrinted = false;
    for (var copy = 0; copy < totalCopies; copy++) {
      for (final printer in cashierPrinters) {
        try {
          await _printerService
              .printReceipt(
                printer,
                receiptData,
                jobType: copy == 0 ? 'cashier' : 'cashier_copy_${copy + 1}',
              )
              .timeout(const Duration(seconds: 12));
          anyPrinted = true;
        } catch (_) {
          // Swallow — a broken printer shouldn't fail the pay-now flow.
        }
      }
      if (copy + 1 < totalCopies) {
        // Thermal printers sometimes merge back-to-back jobs; gap
        // between copies lets the cutter reset. Same 400ms the cashier
        // uses in _autoPrintReceiptCopies.
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    return anyPrinted;
  }

  OrderReceiptData _buildReceiptData({
    required Map<String, dynamic>? invoicePayload,
    required String fallbackInvoiceNumber,
    String? dailyOrderNumber,
    required List<CartItem> items,
    required double totalInclVat,
    required double vatRate,
    required String tableNumber,
    required String waiterName,
    required List<Map<String, dynamic>> pays,
  }) {
    final invoice = _asMap(invoicePayload?['invoice']) ?? invoicePayload;
    final branch = _asMap(invoicePayload?['branch']) ?? _asMap(invoice?['branch']);
    final seller = _asMap(invoicePayload?['seller']) ??
        _asMap(branch?['seller']) ??
        _asMap(invoice?['seller']);
    final user = _authService.getUser();
    final userBranch = _asMap(user?['branch']);
    final userSeller =
        _asMap(user?['seller']) ?? _asMap(userBranch?['seller']);

    String? pick(List<dynamic> values) {
      for (final v in values) {
        final t = v?.toString().trim();
        if (t != null && t.isNotEmpty && t.toLowerCase() != 'null') return t;
      }
      return null;
    }

    final invoiceNumber = pick([
          invoice?['invoice_number'],
          invoice?['number'],
          invoicePayload?['invoice_number'],
        ]) ??
        fallbackInvoiceNumber;

    final issueDateTime = pick([
          invoice?['created_at'],
          invoice?['date'],
          invoicePayload?['created_at'],
        ]) ??
        DateTime.now().toIso8601String();

    final sellerNameAr = pick([
          seller?['name_ar'],
          seller?['ar_name'],
          seller?['name'],
          userSeller?['name_ar'],
          userSeller?['ar_name'],
          userSeller?['name'],
        ]) ??
        '';
    final sellerNameEn = pick([
          seller?['name_en'],
          seller?['en_name'],
          userSeller?['name_en'],
          userSeller?['en_name'],
        ]) ??
        sellerNameAr;

    final vatNumber = pick([
          seller?['tax_number'],
          seller?['vat_number'],
          branch?['tax_number'],
          userSeller?['tax_number'],
          userSeller?['vat_number'],
          userBranch?['tax_number'],
        ]) ??
        '';

    final branchName = pick([
          branch?['name'],
          userBranch?['name'],
        ]) ??
        '';

    final branchAddress = pick([
          branch?['address'],
          userBranch?['address'],
        ]);
    final branchMobile = pick([
          branch?['mobile'],
          branch?['phone'],
          userBranch?['mobile'],
          userBranch?['phone'],
        ]);
    final sellerLogo = pick([
      seller?['logo'],
      userSeller?['logo'],
    ]);

    double parseNum(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    final total = parseNum(invoice?['total']) > 0
        ? parseNum(invoice?['total'])
        : totalInclVat;
    final vat = parseNum(invoice?['vat_amount']) > 0
        ? parseNum(invoice?['vat_amount'])
        : (vatRate > 0 ? total - (total / (1 + vatRate)) : 0.0);
    final subtotal = parseNum(invoice?['subtotal']) > 0
        ? parseNum(invoice?['subtotal'])
        : (total - vat);

    final receiptItems = items.map((it) {
      final addons = it.selectedExtras
          .map((e) => ReceiptAddon(
                nameAr: e.name,
                nameEn: e.name,
                price: e.price,
              ))
          .toList(growable: false);
      return ReceiptItem(
        nameAr: it.product.name,
        nameEn: it.product.name,
        quantity: it.quantity,
        unitPrice: it.product.price,
        total: it.totalPrice,
        addons: addons.isEmpty ? null : addons,
      );
    }).toList(growable: false);

    final receiptPayments = pays.map((p) {
      final method = (p['pay_method'] ?? p['method'] ?? p['name'])
              ?.toString()
              .trim()
              .toLowerCase() ??
          'cash';
      final label = _payLabel(method);
      return ReceiptPayment(
        methodLabel: label,
        amount: parseNum(p['amount'] ?? p['value']),
      );
    }).toList(growable: false);
    final paymentMethod = receiptPayments.isNotEmpty
        ? receiptPayments.first.methodLabel
        : 'نقدي';

    final qr = pick([
          invoice?['zatca_qr'],
          invoice?['qr_code'],
          invoicePayload?['zatca_qr'],
          invoicePayload?['qr_code'],
        ]) ??
        '';

    return OrderReceiptData(
      invoiceNumber: invoiceNumber,
      issueDateTime: issueDateTime,
      sellerNameAr: sellerNameAr,
      sellerNameEn: sellerNameEn,
      vatNumber: vatNumber,
      branchName: branchName,
      items: receiptItems,
      totalExclVat: subtotal,
      vatAmount: vat,
      totalInclVat: total,
      paymentMethod: paymentMethod,
      payments: receiptPayments,
      qrCodeBase64: qr,
      sellerLogo: sellerLogo,
      branchAddress: branchAddress,
      branchMobile: branchMobile,
      cashierName: waiterName,
      orderType: 'restaurant_internal',
      // Prefer the backend daily_order_number for the human-facing ref,
      // fall back to a daily number pulled off the invoice payload, then
      // finally to the invoice number. Mirrors the cashier's
      // normalizeDisplayOrderRef resolution order.
      orderNumber: (dailyOrderNumber != null && dailyOrderNumber.isNotEmpty)
          ? dailyOrderNumber
          : (pick([
                invoice?['daily_order_number'],
                invoice?['order_number'],
                invoicePayload?['daily_order_number'],
                invoicePayload?['order_number'],
              ]) ??
              invoiceNumber),
      tableNumber: tableNumber.trim().isEmpty ? null : tableNumber,
    );
  }

  Map<String, dynamic>? _asMap(Object? v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return null;
  }

  String _payLabel(String method) {
    switch (method) {
      case 'cash':
      case 'نقدي':
      case 'كاش':
        return 'نقدي';
      case 'card':
      case 'mada':
      case 'visa':
      case 'بطاقة':
      case 'مدى':
        return 'بطاقة';
      case 'stc':
      case 'stc_pay':
        return 'STC Pay';
      case 'pay_later':
      case 'later':
      case 'دفع لاحق':
        return 'دفع لاحق';
      default:
        return method;
    }
  }
}
