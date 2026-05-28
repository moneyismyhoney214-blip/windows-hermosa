// Kitchen-ticket internals — split from waiter_print_dispatcher.dart for size.
part of '../waiter_print_dispatcher.dart';

extension WaiterPrintDispatcherKitchen on WaiterPrintDispatcher {
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
}
