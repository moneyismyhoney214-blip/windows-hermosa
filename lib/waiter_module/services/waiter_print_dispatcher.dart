import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../../dialogs/edit_order_dialog.dart' show OrderChange;
import '../../locator.dart';
import '../../models.dart';
import '../../models/receipt_data.dart';
import '../../services/api/api_constants.dart';
import '../../services/api/auth_service.dart';
import '../../services/api/branch_service.dart';
import '../../services/api/device_service.dart';
import '../../services/api/order_service.dart';
import '../../services/print_orchestrator_service.dart';
import '../../services/printer_language_settings_service.dart';
import '../../services/printer_role_registry.dart';
import '../../services/printer_service.dart';
import '../../services/receipt_builder_service.dart';
import 'waiter_device_prefs.dart';

part 'waiter_print_dispatcher_parts/waiter_print_dispatcher.kitchen.dart';
part 'waiter_print_dispatcher_parts/waiter_print_dispatcher.receipt.dart';

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
    BranchService? branchService,
  })  : _orchestrator = orchestrator ?? getIt<PrintOrchestratorService>(),
        _printerService = printerService ?? getIt<PrinterService>(),
        _deviceService = deviceService ?? getIt<DeviceService>(),
        _roleRegistry = roleRegistry ?? getIt<PrinterRoleRegistry>(),
        _orderService = orderService ?? getIt<OrderService>(),
        _authService = authService ?? getIt<AuthService>(),
        _branchService = branchService ?? getIt<BranchService>();

  final PrintOrchestratorService _orchestrator;
  final PrinterService _printerService;
  final DeviceService _deviceService;
  final PrinterRoleRegistry _roleRegistry;
  final OrderService _orderService;
  final AuthService _authService;
  final BranchService _branchService;

  /// Session-scoped cache of seller/branch fields the receipt builder
  /// pulls out of the canonical `getInvoice` response. The cashier owns
  /// an equivalent cache on its main-screen state; without one, every
  /// waiter print starts cold and, if the current invoice payload
  /// happens to nest seller info inconsistently, the printed header
  /// loses logo/tax/CR fields and the receipt comes out shorter than
  /// the cashier's. Pre-warmed by the first successful build and
  /// reused on every subsequent call.
  final ReceiptBuilderCache _receiptCache = ReceiptBuilderCache();

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

  /// Byte-for-byte match with `PrintOrchestratorService._isUsablePrinter`
  /// so the advisory cull we do here never diverges from the filter
  /// the orchestrator runs internally. Three rules:
  ///   1. type must be "printer" (not "kds", "cds", etc.)
  ///   2. skip `kitchen:*` pseudo-device IDs (those are KDS streams,
  ///      not physical printers)
  ///   3. Bluetooth needs a non-empty bluetoothAddress; TCP needs a
  ///      non-empty ip. Having a `name` isn't enough — it's always set.
  bool _isUsablePrinter(DeviceConfig d) {
    final type = d.type.trim().toLowerCase();
    if (type != 'printer') return false;
    if (d.id.startsWith('kitchen:')) return false;
    if (d.connectionType == PrinterConnectionType.bluetooth) {
      return (d.bluetoothAddress?.trim().isNotEmpty ?? false);
    }
    return d.ip.trim().isNotEmpty;
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
    try {
      return await _printKitchenTicketInternal(
        bookingId: bookingId,
        orderNumber: orderNumber,
        items: items,
        tableNumber: tableNumber,
        waiterName: waiterName,
        invoiceNumber: invoiceNumber,
        kdsAlreadyDispatched: kdsAlreadyDispatched,
      );
    } catch (e) {
      debugPrint('⚠️ printKitchenTicket aborted: $e');
      return false;
    }
  }

}
