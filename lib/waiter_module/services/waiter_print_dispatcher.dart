import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../../dialogs/edit_order_dialog.dart' show OrderChange;
import '../../locator.dart';
import '../../models.dart';
import '../../models/receipt_data.dart';
import '../../services/api/auth_service.dart';
import '../../services/api/branch_service.dart';
import '../../services/api/device_service.dart';
import '../../services/api/order_service.dart';
import '../../services/print_orchestrator_service.dart';
import '../../services/printer_role_registry.dart';
import '../../services/printer_language_settings_service.dart';
import '../../services/printer_service.dart';
import '../../services/receipt_builder_service.dart';
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

  Future<bool> _printKitchenTicketInternal({
    required String bookingId,
    required String orderNumber,
    required List<CartItem> items,
    required String tableNumber,
    required String waiterName,
    String? invoiceNumber,
    required bool kdsAlreadyDispatched,
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
        // Follow the user's actual printer-language toggle:
        //   - primaryLang is always the chosen primary
        //   - secondary is passed ONLY when `allowSecondary` is on AND
        //     the two languages differ (passing the same code twice
        //     produces a duplicate column on the thermal template).
        // The earlier `primary != secondary` shortcut bypassed the
        // user's "bilingual off" setting, so a waiter who had
        // `allowSecondary=false` still got both languages on the
        // kitchen ticket — the bug the user hit.
        isRtl: langSettings.primary == 'ar' || langSettings.primary == 'ur',
        primaryLang: langSettings.primary,
        secondaryLang: (langSettings.allowSecondary &&
                langSettings.secondary != langSettings.primary)
            ? langSettings.secondary
            : null,
        allowSecondary: langSettings.allowSecondary &&
            langSettings.secondary != langSettings.primary,
      );
      return true;
    } catch (e) {
      // Orchestrator already retries internally; swallow so a down
      // printer doesn't fail the whole pay-later flow.
      return false;
    }
  }

  Map<String, dynamic> _toWireItem(CartItem item) {
    // Mirror the cashier's kitchen-item shape (see
    // main_screen.kitchen_print.dart lines ~970 — the `items.add({...})`
    // section that feeds `enqueueKitchenPrint`). The template relies on
    // `nameAr` / `nameEn` / `localizedNames` to render bilingual
    // kitchen tickets correctly. Without localizedNames the template
    // would fall back to `name` alone — which is whatever language the
    // Product was loaded in, NOT the primary/secondary the user chose.
    final product = item.product;
    final nameAr =
        product.nameAr.isNotEmpty ? product.nameAr : product.name;
    final nameEn =
        product.nameEn.isNotEmpty ? product.nameEn : product.name;

    // Extras shape must also carry translations so addons render
    // bilingual — the cashier builds this via
    // `{'name': ar, 'translations': {'option': {ar, en, ...}}}`.
    final extras = item.selectedExtras.map((e) {
      final entry = <String, dynamic>{
        'id': e.id,
        'name': e.name,
        'price': e.price,
      };
      if (e.optionTranslations.isNotEmpty ||
          e.attributeTranslations.isNotEmpty) {
        entry['translations'] = <String, Map<String, String>>{
          if (e.optionTranslations.isNotEmpty)
            'option': e.optionTranslations,
          if (e.attributeTranslations.isNotEmpty)
            'attribute': e.attributeTranslations,
        };
      }
      return entry;
    }).toList(growable: false);

    final qtyInt = item.quantity == item.quantity.toInt()
        ? item.quantity.toInt()
        : item.quantity;
    return <String, dynamic>{
      'name': nameAr.isNotEmpty ? nameAr : nameEn,
      'nameAr': nameAr,
      'nameEn': nameEn,
      if (product.localizedNames.isNotEmpty)
        'localizedNames': product.localizedNames,
      'quantity': qtyInt,
      'price': item.product.price,
      'unit_price': item.product.price,
      'total_price': item.totalPrice,
      if (item.notes.isNotEmpty) 'notes': item.notes,
      if (extras.isNotEmpty) 'addons': extras,
      if (extras.isNotEmpty) 'extras': extras,
      if (product.categoryId != null) 'category_id': product.categoryId,
    };
  }

  // ---------------------------------------------------------------------------
  // Kitchen change ticket (edit-order diff + full cancel)
  // ---------------------------------------------------------------------------

  /// Prints a kitchen DIFF ticket for an edited order. Mirrors
  /// main_screen.devices._printOrderChangeTicket byte-for-byte so the
  /// kitchen sees the same badges regardless of which device ran the
  /// edit. `isFullCancel` flips the header from "تعديل طلب" to
  /// "إلغاء طلب" and adds the red warning banner.
  ///
  /// The caller is typically the waiter's Edit Order flow: the
  /// `EditOrderDialog` computes the diff via `_detectChanges()` and
  /// hands us the list through its `onPrintChanges` callback.
  Future<void> printKitchenChangeTicket({
    required List<OrderChange> changes,
    required String orderNumber,
    bool isFullCancel = false,
  }) async {
    try {
      await _printKitchenChangeTicketInternal(
        changes: changes,
        orderNumber: orderNumber,
        isFullCancel: isFullCancel,
      );
    } catch (e) {
      // Never let a printer/registry failure propagate — callers use
      // `unawaited` and an unobserved exception would crash the isolate.
      debugPrint('⚠️ Waiter change ticket aborted: $e');
    }
  }

  Future<void> _printKitchenChangeTicketInternal({
    required List<OrderChange> changes,
    required String orderNumber,
    required bool isFullCancel,
  }) async {
    if (changes.isEmpty) return;

    // Respect the same toggle the fresh-order kitchen print respects —
    // if the device-level "اطبع فواتير المطبخ" is off we skip the diff
    // ticket too. Cashier side honours this implicitly via the full
    // kitchen-print pipeline; we do it explicitly here because the
    // change ticket bypasses `_triggerKitchenPrint`.
    final printKitchen = await _readBool(
      WaiterDevicePrefKeys.printKitchenInvoices,
      fallback: true,
    );
    if (!printKitchen) return;

    // Resolve printer language — primary + optional secondary — exactly
    // like the cashier. Empty secondary means "no bilingual badge",
    // which the kitchen-view renderer handles by skipping the second
    // line.
    final String invoiceLang = printerLanguageSettings.primary;
    final String invoiceLangSecondary =
        printerLanguageSettings.allowSecondary &&
                printerLanguageSettings.secondary != invoiceLang
            ? printerLanguageSettings.secondary
            : '';

    String pickLabel(
      String code, {
      required String ar,
      required String en,
      String? es,
      String? tr,
      String? hi,
      String? ur,
    }) {
      switch (code) {
        case 'es':
          return es ?? en;
        case 'tr':
          return tr ?? en;
        case 'hi':
          return hi ?? en;
        case 'ur':
          return ur ?? en;
        case 'en':
          return en;
        case 'ar':
          return ar;
        default:
          return ar;
      }
    }

    String tl(
      String ar,
      String en, {
      String? es,
      String? tr,
      String? hi,
      String? ur,
    }) =>
        pickLabel(invoiceLang,
            ar: ar, en: en, es: es, tr: tr, hi: hi, ur: ur);

    String tlSec(
      String ar,
      String en, {
      String? es,
      String? tr,
      String? hi,
      String? ur,
    }) {
      if (invoiceLangSecondary.isEmpty) return '';
      return pickLabel(invoiceLangSecondary,
          ar: ar, en: en, es: es, tr: tr, hi: hi, ur: ur);
    }

    String resolveName(OrderChange change) {
      final loc = change.localizedNames;
      if (loc != null &&
          loc.containsKey(invoiceLang) &&
          loc[invoiceLang]!.isNotEmpty) {
        return loc[invoiceLang]!;
      }
      if (loc != null && loc.containsKey('en') && loc['en']!.isNotEmpty) {
        return loc['en']!;
      }
      return change.name;
    }

    List<Map<String, dynamic>> extrasFor(OrderChange change) {
      if (change.extras.isEmpty) return const [];
      return change.extras.map((e) {
        final entry = <String, dynamic>{'name': e.name};
        if (e.optionTranslations.isNotEmpty ||
            e.attributeTranslations.isNotEmpty) {
          entry['translations'] = <String, Map<String, String>>{
            if (e.optionTranslations.isNotEmpty)
              'option': e.optionTranslations,
            if (e.attributeTranslations.isNotEmpty)
              'attribute': e.attributeTranslations,
          };
        }
        return entry;
      }).toList(growable: false);
    }

    final changeItems = <Map<String, dynamic>>[];
    for (final change in changes) {
      final resolvedName = resolveName(change);
      final extras = extrasFor(change);
      switch (change.type) {
        case 'add':
          changeItems.add({
            'name': '+ $resolvedName',
            'nameAr': resolvedName,
            'quantity': change.quantity,
            'tag': 'Add',
            'tagAr': tl('إضافة', 'Add',
                es: 'Agregar', tr: 'Ekle', hi: 'जोड़ें', ur: 'شامل کریں'),
            'tagPrimary': tl('إضافة', 'Add',
                es: 'Agregar', tr: 'Ekle', hi: 'जोड़ें', ur: 'شامل کریں'),
            'tagSecondary': tlSec('إضافة', 'Add',
                es: 'Agregar', tr: 'Ekle', hi: 'जोड़ें', ur: 'شامل کریں'),
            'tagColor': 'green',
            if (change.localizedNames != null)
              'localizedNames': change.localizedNames,
            if (extras.isNotEmpty) 'extras': extras,
          });
          break;
        case 'cancel':
          changeItems.add({
            'name': resolvedName,
            'nameAr': resolvedName,
            'quantity': change.quantity,
            'tag': 'Cancelled',
            'tagAr': tl('ملغي', 'Cancelled',
                es: 'Cancelado', tr: 'İptal', hi: 'रद्द', ur: 'منسوخ'),
            'tagPrimary': tl('ملغي', 'Cancelled',
                es: 'Cancelado', tr: 'İptal', hi: 'रद्द', ur: 'منسوخ'),
            'tagSecondary': tlSec('ملغي', 'Cancelled',
                es: 'Cancelado', tr: 'İptal', hi: 'रद्द', ur: 'منسوخ'),
            'cancelled': true,
            'tagColor': 'black',
            if (change.localizedNames != null)
              'localizedNames': change.localizedNames,
            if (extras.isNotEmpty) 'extras': extras,
          });
          break;
        case 'partial_cancel':
          changeItems.add({
            'name': resolvedName,
            'nameAr': resolvedName,
            'quantity': change.quantity,
            'tag': 'Partial Cancel',
            'tagAr': tl('إلغاء جزئي', 'Partial Cancel',
                es: 'Cancelación parcial',
                tr: 'Kısmi İptal',
                hi: 'आंशिक रद्द',
                ur: 'جزوی منسوخی'),
            'tagPrimary': tl('إلغاء جزئي', 'Partial Cancel',
                es: 'Cancelación parcial',
                tr: 'Kısmi İptal',
                hi: 'आंशिक रद्द',
                ur: 'جزوی منسوخی'),
            'tagSecondary': tlSec('إلغاء جزئي', 'Partial Cancel',
                es: 'Cancelación parcial',
                tr: 'Kısmi İptal',
                hi: 'आंशिक रद्द',
                ur: 'جزوی منسوخی'),
            'tagColor': 'black',
            'oldQuantity': change.oldQuantity,
            'cancelledQuantity': change.cancelledQuantity,
            if (change.localizedNames != null)
              'localizedNames': change.localizedNames,
            if (extras.isNotEmpty) 'extras': extras,
          });
          break;
        case 'qty_change':
          changeItems.add({
            'name': resolvedName,
            'nameAr': resolvedName,
            'quantity': change.quantity,
            'tag': 'Qty Change',
            'tagPrimary': tl('تعديل كمية', 'Qty Change',
                es: 'Cambio de cantidad',
                tr: 'Miktar Değişikliği',
                hi: 'मात्रा बदलें',
                ur: 'مقدار تبدیلی'),
            'tagSecondary': tlSec('تعديل كمية', 'Qty Change',
                es: 'Cambio de cantidad',
                tr: 'Miktar Değişikliği',
                hi: 'मात्रा बदलें',
                ur: 'مقدار تبدیلی'),
            'tagAr': tl('تعديل كمية', 'Qty Change',
                es: 'Cambio de cantidad',
                tr: 'Miktar Değişikliği',
                hi: 'मात्रा बदलें',
                ur: 'مقدار تبدیلی'),
            'tagColor': 'orange',
            'oldQuantity': change.oldQuantity,
            if (change.localizedNames != null)
              'localizedNames': change.localizedNames,
            if (extras.isNotEmpty) 'extras': extras,
          });
          break;
        case 'replace_old':
          changeItems.add({
            'name': resolvedName,
            'nameAr': resolvedName,
            'quantity': change.quantity,
            'tag': 'Cancelled',
            'tagAr': tl('ملغي', 'Cancelled',
                es: 'Cancelado', tr: 'İptal', hi: 'रद्द', ur: 'منسوخ'),
            'tagPrimary': tl('ملغي', 'Cancelled',
                es: 'Cancelado', tr: 'İptal', hi: 'रद्द', ur: 'منسوخ'),
            'tagSecondary': tlSec('ملغي', 'Cancelled',
                es: 'Cancelado', tr: 'İptal', hi: 'रद्द', ur: 'منسوخ'),
            'cancelled': true,
            'tagColor': 'black',
            if (change.localizedNames != null)
              'localizedNames': change.localizedNames,
            if (extras.isNotEmpty) 'extras': extras,
          });
          break;
        case 'replace_new':
          changeItems.add({
            'name': resolvedName,
            'nameAr': resolvedName,
            'quantity': change.quantity,
            'tag': 'New',
            'tagAr': tl('جديد', 'New',
                es: 'Nuevo', tr: 'Yeni', hi: 'نया', ur: 'نیا'),
            'tagPrimary': tl('جديد', 'New',
                es: 'Nuevo', tr: 'Yeni', hi: 'نया', ur: 'نیا'),
            'tagSecondary': tlSec('جديد', 'New',
                es: 'Nuevo', tr: 'Yeni', hi: 'نया', ur: 'نیا'),
            'tagColor': 'green',
            if (change.localizedNames != null)
              'localizedNames': change.localizedNames,
            if (extras.isNotEmpty) 'extras': extras,
          });
          break;
      }
    }

    final printers = await _loadPrinters();
    if (printers.isEmpty) return;
    final kitchenPrinters = await _kitchenRolePrinters(printers);
    if (kitchenPrinters.isEmpty) {
      debugPrint('ℹ️ No kitchen printers for waiter change ticket');
      return;
    }

    final hasAnyCancel = changeItems.any((item) =>
        item['cancelled'] == true || item['cancelledQuantity'] != null);
    final orderTypeLabel = isFullCancel
        ? tl('إلغاء طلب', 'Order Cancelled',
            es: 'Pedido Cancelado',
            tr: 'Sipariş İptal',
            hi: 'ऑर्डर रद्द',
            ur: 'آرڈر منسوخ')
        : tl('تعديل طلب', 'Order Change',
            es: 'Cambio de Pedido',
            tr: 'Sipariş Değişikliği',
            hi: 'ऑर्डर बदलें',
            ur: 'آرڈر تبدیلی');
    final String? noteLabel = isFullCancel
        ? tl('⛔ الطلب ملغي بالكامل', '⛔ Entire order cancelled',
            es: '⛔ Pedido cancelado',
            tr: '⛔ Sipariş tamamen iptal',
            hi: '⛔ पूरा ऑर्डर रद्द',
            ur: '⛔ پورا آرڈر منسوخ')
        : (hasAnyCancel
            ? tl('⚠️ إلغاء جزئي', '⚠️ Partial cancellation',
                es: '⚠️ Cancelación parcial',
                tr: '⚠️ Kısmi iptal',
                hi: '⚠️ आंशिक रद्दीकरण',
                ur: '⚠️ جزوی منسوخی')
            : null);

    try {
      await _orchestrator.enqueueKitchenPrint(
        printers: kitchenPrinters,
        orderNumber: orderNumber,
        orderType: orderTypeLabel,
        items: changeItems,
        note: noteLabel,
        // RTL follows the primary lang, not a fixed "always Arabic" —
        // an English-primary waiter shouldn't get reversed item rows.
        isRtl: invoiceLang == 'ar' || invoiceLang == 'ur',
        primaryLang: invoiceLang,
        secondaryLang:
            invoiceLangSecondary.isEmpty ? null : invoiceLangSecondary,
        allowSecondary: invoiceLangSecondary.isNotEmpty,
      );
      debugPrint('✅ Waiter change ticket dispatched for #$orderNumber');
    } catch (e) {
      debugPrint('⚠️ Waiter change ticket failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Table migration kitchen ticket
  // ---------------------------------------------------------------------------

  /// Prints the "نقل طاولة" kitchen ticket when a booking is moved
  /// between tables. Byte-for-byte match with the cashier's
  /// `_printMigrationTicket` (lib/screens/table_management_screen.dart)
  /// so the kitchen sees the same FROM/TO layout regardless of which
  /// device initiated the migrate.
  Future<void> printMigrationTicket({
    required String sourceTableNumber,
    required String destinationTableNumber,
    required String waiterName,
  }) async {
    try {
      await _printMigrationTicketInternal(
        sourceTableNumber: sourceTableNumber,
        destinationTableNumber: destinationTableNumber,
        waiterName: waiterName,
      );
    } catch (e) {
      debugPrint('⚠️ printMigrationTicket aborted: $e');
    }
  }

  Future<void> _printMigrationTicketInternal({
    required String sourceTableNumber,
    required String destinationTableNumber,
    required String waiterName,
  }) async {
    final printKitchen = await _readBool(
      WaiterDevicePrefKeys.printKitchenInvoices,
      fallback: true,
    );
    if (!printKitchen) return;

    final printers = await _loadPrinters();
    if (printers.isEmpty) return;
    final kitchenPrinters = await _kitchenRolePrinters(printers);
    if (kitchenPrinters.isEmpty) return;

    final migrationItems = <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'من: طاولة $sourceTableNumber',
        'nameAr': 'من: طاولة $sourceTableNumber',
        'quantity': 1,
        'tag': 'FROM',
        'tagAr': 'من',
        'tagPrimary': 'من',
        'tagSecondary': 'FROM',
        'tagColor': 'black',
      },
      <String, dynamic>{
        'name': 'إلى: طاولة $destinationTableNumber',
        'nameAr': 'إلى: طاولة $destinationTableNumber',
        'quantity': 1,
        'tag': 'TO',
        'tagAr': 'إلى',
        'tagPrimary': 'إلى',
        'tagSecondary': 'TO',
        'tagColor': 'green',
      },
    ];
    final noteBuffer = StringBuffer()
      ..writeln(
        '⚠️ الطلب الذي كان على الطاولة $sourceTableNumber منقول إلى الطاولة $destinationTableNumber',
      );
    if (waiterName.isNotEmpty) {
      noteBuffer.writeln('بواسطة النادل: $waiterName');
    }

    final migrationId =
        'MIG-$sourceTableNumber-$destinationTableNumber-${DateTime.now().millisecondsSinceEpoch}';
    try {
      await _orchestrator.enqueueKitchenPrint(
        printers: kitchenPrinters,
        orderNumber: migrationId,
        orderType: 'نقل طاولة',
        items: migrationItems,
        note: noteBuffer.toString().trim(),
        tableNumber: destinationTableNumber,
        cashierName: waiterName.isEmpty ? null : waiterName,
        isRtl: true,
        primaryLang: 'ar',
      );
    } catch (e) {
      debugPrint('⚠️ Waiter migration ticket failed: $e');
    }
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
    try {
      return await _printCashierReceiptInternal(
        invoiceId: invoiceId,
        invoiceNumber: invoiceNumber,
        dailyOrderNumber: dailyOrderNumber,
        items: items,
        totalInclVat: totalInclVat,
        vatRate: vatRate,
        tableNumber: tableNumber,
        waiterName: waiterName,
        pays: pays,
      );
    } catch (e) {
      debugPrint('⚠️ printCashierReceipt aborted: $e');
      return false;
    }
  }

  Future<bool> _printCashierReceiptInternal({
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
    //
    // The backend wraps everything under `data` — `{status, message,
    // data: {invoice, branch, qr_image, ...}, ...}` — so the real
    // payload the receipt builder needs is `response['data']`, not the
    // full envelope. The cashier unwraps this at
    // main_screen.payment:2573 before calling `_buildOrderReceiptData`;
    // we have to do the same or every top-level picker below misses
    // (branch=null, invoice=null, qr_image=null → no logo, no tax
    // number, no QR on the printed receipt).
    Map<String, dynamic>? invoicePayload;
    try {
      final raw = await _orderService.getInvoice(invoiceId);
      final unwrapped = _asMap(raw['data']);
      invoicePayload = unwrapped ?? raw;
    } catch (e) {
      debugPrint('⚠️ waiter getInvoice($invoiceId) failed: $e');
      invoicePayload = null;
    }

    // Ensure the BranchService branch/seller/logo cache is populated —
    // this is the SAME cache the cashier prewarms at session start.
    // Without it (and if `getInvoice` returned a payload that doesn't
    // nest branch.seller), the printed header loses the logo, tax
    // number, and commercial register. Awaited with a short timeout
    // so a slow /seller/branches call can't block the print job.
    if (_branchService.cachedBranchReceiptInfo == null) {
      try {
        await _branchService
            .fetchAndCacheBranchReceiptInfo()
            .timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('⚠️ waiter branch receipt cache warm-up failed: $e');
      }
    }

    final receiptData = _buildReceiptData(
      invoicePayload: invoicePayload,
      // Only fall back to the invoice_number passed by the caller;
      // NEVER fall back to the invoice_id (= booking id). The receipt
      // template renders `invoiceNumber` in the "رقم الفاتورة: IN-xxx"
      // header, so substituting a booking id like "63" there made the
      // printed invoice look like an order id. Empty is better than
      // wrong — the downstream renderer handles a missing invoice
      // number gracefully by omitting the line.
      fallbackInvoiceNumber: invoiceNumber ?? '',
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

  // ---------------------------------------------------------------------------
  // Receipt data adapter — delegates to ReceiptBuilderService
  // ---------------------------------------------------------------------------
  //
  // The waiter reuses the exact same receipt-building logic the cashier
  // runs (lib/services/receipt_builder_service.dart). This adapter only
  // does two waiter-specific things:
  //   1. Convert the in-memory CartItem list into the Map<String, dynamic>
  //      shape the service was originally written for (name/nameAr/nameEn/
  //      localizedNames/quantity/unitPrice/total/extras-with-translations).
  //   2. Pass in the offline fallback sources the waiter has access to —
  //      the auth-profile (for tax/logo on first-print before getInvoice)
  //      and BranchService.cachedBranchReceiptInfo (uploaded logo URL).
  //
  // No receipt field is resolved here; every picker lives in the service.
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
    // CartItem → Map adapter. The service expects the cashier-style
    // order-item shape (see main_screen.payment._buildOrderReceiptData).
    final orderItems = items.map((it) {
      final nameAr = it.product.nameAr.isNotEmpty
          ? it.product.nameAr
          : it.product.name;
      final nameEn = it.product.nameEn.isNotEmpty
          ? it.product.nameEn
          : it.product.name;
      final extras = it.selectedExtras.map((e) {
        final entry = <String, dynamic>{
          'id': e.id,
          'name': e.name,
          'price': e.price,
        };
        if (e.optionTranslations.isNotEmpty ||
            e.attributeTranslations.isNotEmpty) {
          entry['translations'] = <String, Map<String, String>>{
            if (e.optionTranslations.isNotEmpty)
              'option': e.optionTranslations,
            if (e.attributeTranslations.isNotEmpty)
              'attribute': e.attributeTranslations,
          };
        }
        return entry;
      }).toList(growable: false);
      return <String, dynamic>{
        'name': nameAr.isNotEmpty ? nameAr : nameEn,
        'nameAr': nameAr,
        'nameEn': nameEn,
        if (it.product.localizedNames.isNotEmpty)
          'localizedNames': it.product.localizedNames,
        'quantity': it.quantity,
        'unitPrice': it.product.price,
        'total': it.totalPrice,
        // Per-item note (e.g. "بدون ثوم"). Cashier passes this through
        // at main_screen.payment.dart:1043 — omitting it dropped the
        // waiter's printed receipt below the cashier's whenever the
        // order had any item-level instructions.
        if (it.notes.trim().isNotEmpty) 'notes': it.notes.trim(),
        if (extras.isNotEmpty) 'extras': extras,
        if (it.product.categoryId != null)
          'category_id': it.product.categoryId,
      };
    }).toList(growable: false);

    // Unwrap the API envelope (backend wraps everything under
    // `data`) to match what the cashier passes to the service —
    // the cashier does the same unwrap at main_screen.payment:2573.
    final effectivePayload = invoicePayload == null
        ? null
        : (_asMap(invoicePayload['data']) ?? invoicePayload);

    return ReceiptBuilderService.build(
      orderId: fallbackInvoiceNumber,
      invoiceNumber: fallbackInvoiceNumber.isEmpty ? null : fallbackInvoiceNumber,
      orderItems: orderItems,
      orderTotal: totalInclVat,
      // Dine-in is the only waiter context; the service will prefer
      // whatever the invoice payload tells it over this seed value.
      orderType: 'restaurant_internal',
      // pay-now only — pay-later never reaches printCashierReceipt.
      type: 'payment',
      pays: pays,
      invoicePayload: effectivePayload,
      tableNumber: tableNumber,
      dailyOrderNumber: dailyOrderNumber,
      isTaxEnabled: vatRate > 0,
      taxRate: vatRate,
      userNameFallback: waiterName.isEmpty ? null : waiterName,
      // Waiter-specific fallbacks:
      authUser: _authService.getUser(),
      branchReceiptCache: _branchService.cachedBranchReceiptInfo,
    );
  }

  Map<String, dynamic>? _asMap(Object? v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return null;
  }
}
