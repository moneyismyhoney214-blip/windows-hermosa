// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../main_screen.dart';

extension MainScreenDevices on _MainScreenState {
  bool _isDisplayDeviceType(String type) {
    final normalized = type.trim().toLowerCase();
    return normalized == 'kds' ||
        normalized == 'kitchen_screen' ||
        normalized == 'order_viewer' ||
        normalized == 'cds' ||
        normalized == 'customer_display';
  }

  bool _isPhysicalPrinter(DeviceConfig device) {
    final normalized = device.type.trim().toLowerCase();
    if (device.id.startsWith('kitchen:')) return false;
    if (_isDisplayDeviceType(normalized)) return false;
    return normalized == 'printer';
  }

  bool _isUsablePrinter(DeviceConfig device) {
    if (!_isPhysicalPrinter(device)) return false;
    if (device.connectionType == PrinterConnectionType.bluetooth) {
      return device.bluetoothAddress?.trim().isNotEmpty == true;
    }
    return device.ip.trim().isNotEmpty;
  }

  DisplayMode _displayModeForDevice(DeviceConfig device) {
    final normalized = device.type.trim().toLowerCase();
    if (device.id.startsWith('kitchen:')) {
      final isExplicitCds =
          normalized == 'cds' || normalized == 'customer_display';
      return isExplicitCds ? DisplayMode.cds : DisplayMode.kds;
    }
    if (normalized == 'cds' ||
        normalized == 'customer_display' ||
        normalized == 'order_viewer') {
      return DisplayMode.cds;
    }
    return DisplayMode.kds;
  }

  bool _deviceMatchesDisplayEndpoint(
    DeviceConfig device, {
    String? ip,
    int? port,
  }) =>
      matchesDisplayEndpoint(device, ip: ip, port: port);

  DeviceConfig? _connectedDisplayDevice(DisplayAppService displayService) {
    final connectedIp = displayService.connectedIp?.trim();
    if (connectedIp == null || connectedIp.isEmpty) return null;

    return findConfiguredDisplayDevice(
      _devices,
      isDisplayDevice: (device) => _isDisplayDeviceType(device.type),
      ip: connectedIp,
      port: displayService.connectedPort,
    );
  }

  DeviceConfig? _pickPreferredDeviceForCdsAutoConnect() {
    final displayService = getIt<DisplayAppService>();
    return pickPreferredCdsDisplayDevice(
      _devices,
      modeForDevice: _displayModeForDevice,
      preferredIp: displayService.connectedIp,
      preferredPort: displayService.connectedPort,
    );
  }

  Future<bool> _ensureCdsAutoConnected() async {
    if (!_isCdsEnabled) return false;

    final displayService = getIt<DisplayAppService>();
    DeviceConfig? connectedDisplayDevice() =>
        _connectedDisplayDevice(displayService);

    bool canReuseCurrentConnection() =>
        canReuseCurrentConnectionForCdsAutoConnect(
          currentMode: displayService.currentMode,
          connectedDevice: connectedDisplayDevice(),
          modeForDevice: _displayModeForDevice,
        );

    Future<bool> connectPreferredCdsDevice() async {
      final targetDevice = _pickPreferredDeviceForCdsAutoConnect();
      if (targetDevice == null) return false;

      final parsedPort = int.tryParse(targetDevice.port) ?? 8080;
      final sameEndpoint = displayService.isConnected &&
          _deviceMatchesDisplayEndpoint(
            targetDevice,
            ip: displayService.connectedIp,
            port: displayService.connectedPort,
          );

      try {
        if (sameEndpoint) {
          if (!canReuseCurrentConnection()) {
            debugPrint(
              '⚠️ Refusing to auto-switch the current ${displayService.currentMode} session to CDS.',
            );
            return false;
          }
          if (displayService.currentMode != DisplayMode.cds) {
            displayService.setMode(DisplayMode.cds);
          }
          return true;
        }

        if (displayService.isConnected ||
            displayService.isConnecting ||
            displayService.isReconnecting) {
          displayService.disconnect(clearEndpoint: false);
        }

        await displayService.connectWithMode(
          targetDevice.ip,
          port: parsedPort,
          mode: DisplayMode.cds,
        );
        return displayService.isConnected &&
            displayService.currentMode == DisplayMode.cds;
      } catch (e) {
        debugPrint('⚠️ Failed to auto-connect CDS device: $e');
        return false;
      }
    }

    bool shouldReconnectToDedicatedCdsDevice() => requiresDedicatedCdsReconnect(
          connectedDisplayDevice(),
          modeForDevice: _displayModeForDevice,
        );

    if (displayService.isConnected) {
      if (displayService.currentMode == DisplayMode.cds) {
        return true;
      }
      if (shouldReconnectToDedicatedCdsDevice()) {
        return connectPreferredCdsDevice();
      }
      if (!canReuseCurrentConnection()) {
        debugPrint(
          '⚠️ Current display connection is not reusable for CDS auto-connect; aborting automatic mode switch.',
        );
        return false;
      }
      displayService.setMode(DisplayMode.cds);
      return true;
    }

    if (displayService.isConnecting || displayService.isReconnecting) {
      final connected = await displayService.waitUntilConnected();
      if (!connected) return false;
      if (displayService.currentMode == DisplayMode.cds) {
        return true;
      }
      if (shouldReconnectToDedicatedCdsDevice()) {
        return connectPreferredCdsDevice();
      }
      if (!canReuseCurrentConnection()) {
        debugPrint(
          '⚠️ Connected display session resolved to KDS; refusing automatic CDS switch after reconnect.',
        );
        return false;
      }
      displayService.setMode(DisplayMode.cds);
      return true;
    }

    return connectPreferredCdsDevice();
  }

  Future<void> _openInvoicePreview({
    required BuildContext hostContext,
    required OrderReceiptData receiptData,
    String? invoiceId,
    String? orderType,
  }) async {
    if (!hostContext.mounted) return;

    final availablePrinters =
        _devices.where(_isUsablePrinter).toList(growable: false);
    final cashierPrinters = await _resolvePrintersForRole(
      role: PrinterRole.cashierReceipt,
      printers: availablePrinters,
    );
    final previewPrinters =
        cashierPrinters.isNotEmpty ? cashierPrinters : availablePrinters;
    final selectedPrinter = previewPrinters.cast<DeviceConfig?>().firstWhere(
          (d) => d != null && _isPhysicalPrinter(d),
          orElse: () => null,
        );

    // If we have an invoiceId, use InvoiceHtmlPdfService to generate the real
    // HTML invoice (same template used for printing via flutter_html_to_pdf_plus)
    // and display it in PdfPreviewScreen for a faithful preview.
    if (invoiceId != null && invoiceId.trim().isNotEmpty) {
      try {
        final invoiceHtmlPdfService = getIt<InvoiceHtmlPdfService>();
        final htmlContent = await invoiceHtmlPdfService.generateHtmlString(
          invoiceId,
          paperWidthMm: selectedPrinter?.paperWidthMm,
        );

        if (!hostContext.mounted) return;

        final titleLabel = _buildInvoicePreviewTitle(
          receiptData: receiptData,
          invoiceId: invoiceId,
        );
        await Navigator.push(
          hostContext,
          MaterialPageRoute(
            builder: (_) => PdfPreviewScreen(
              receiptData: receiptData,
              printer: selectedPrinter,
              htmlContent: htmlContent,
              title: titleLabel,
              carNumber: receiptData.carNumber.isNotEmpty
                  ? receiptData.carNumber
                  : null,
              orderType: orderType,
              // Auto-print already ran at payment time; preview is for viewing
              // only — user can reprint manually via the print button.
              promptPrinterSelectionOnOpen: false,
            ),
          ),
        );
        return;
      } catch (e) {
        debugPrint('⚠️ Failed to generate HTML invoice preview: $e');
        // Fall through to PdfPreviewScreen as fallback.
      }
    }

    // Fallback: use PdfPreviewScreen when no invoiceId or HTML generation failed.
    if (!hostContext.mounted) return;

    final titleLabel = _buildInvoicePreviewTitle(
      receiptData: receiptData,
      invoiceId: invoiceId,
    );
    await Navigator.push(
      hostContext,
      MaterialPageRoute(
        builder: (context) => PdfPreviewScreen(
          receiptData: receiptData,
          printer: selectedPrinter,
          carNumber:
              receiptData.carNumber.isNotEmpty ? receiptData.carNumber : null,
          title: titleLabel,
          orderType: orderType,
          promptPrinterSelectionOnOpen: false,
        ),
      ),
    );
  }

  String _buildInvoicePreviewTitle({
    required OrderReceiptData receiptData,
    String? invoiceId,
  }) {
    String label = receiptData.invoiceNumber.trim();
    if (label.isEmpty) {
      label = invoiceId?.trim() ?? '';
    }
    if (label.isNotEmpty && !label.startsWith('#')) {
      label = '#$label';
    }
    return label.isNotEmpty ? 'معاينة الفاتورة $label' : 'معاينة الفاتورة';
  }


  void _showPaymentSuccess({
    required String type,
    required String orderType,
    required String orderId,
    String? invoiceId,
    required OrderReceiptData receiptData,
    bool allowInvoiceActions = true,
    bool autoOpenInvoicePreview = false,
  }) {
    final normalizedOrderId = orderId.trim();
    final orderLabel = normalizedOrderId.isEmpty
        ? '#-'
        : (normalizedOrderId.startsWith('#')
            ? normalizedOrderId
            : '#$normalizedOrderId');

    // مسح السلة أولاً
    _clearCart();

    // عرض صفحة "تم الدفع" الكاملة
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PaymentSuccessView(
        amount: receiptData.totalInclVat,
        orderId: orderLabel,
        type: type,
        showInvoiceButton: allowInvoiceActions,
        onNewOrder: () {
          Navigator.of(dialogContext).pop();
        },
        onPrint: () {
          Navigator.of(dialogContext).pop();
          unawaited(
            _openInvoicePreview(
              hostContext: context,
              receiptData: receiptData,
              invoiceId: invoiceId,
              orderType: orderType,
            ),
          );
        },
        onGoToOrders: type == 'later'
            ? () {
                Navigator.of(dialogContext).pop();
                // Navigate to orders tab
                setState(() => _activeTab = 'orders');
              }
            : null,
      ),
    );
  }

  Future<void> _autoPrintReceiptCopies({
    required OrderReceiptData receiptData,
    String? invoiceId,
  }) async {
    // Collect all usable printers (physical printers with reachable address).
    final List<DeviceConfig> printers =
        _devices.where(_isUsablePrinter).toList(growable: false);
    if (printers.isEmpty) {
      _showMissingPrinterSnackBar();
      return;
    }

    printJobCacheService.cacheReceiptJob(
      receiptData: receiptData,
      invoiceId: invoiceId,
    );

    // One or two copies of the cashier receipt, gated purely by the "نسخة
    // ثانية للعميل" toggle. All other auto-print flags are ignored here — the
    // cashier always gets at least one copy so long as a printer exists.
    final int totalCopies = _autoPrintCustomerSecondCopy ? 2 : 1;
    debugPrint('🧾 _autoPrintReceiptCopies: secondCopy=$_autoPrintCustomerSecondCopy → printing $totalCopies copies');

    // Resolve cashier-role printers (falls back to any non-kitchen printer).
    final cashierPrinters = await _resolvePrintersForRole(
      role: PrinterRole.cashierReceipt,
      printers: printers,
    );
    if (cashierPrinters.isEmpty) {
      debugPrint('⚠️ No cashier-role printer found; cannot print receipt.');
      _showPrintFailureSnackBar();
      return;
    }

    final printerService = getIt<PrinterService>();
    // Per-printer print timeout. An unreachable printer (bad IP, offline)
    // used to hang Future.wait forever and stop the second copy from ever
    // running. 12s is more than enough for a healthy printer to accept
    // bytes + cut.
    const perPrintTimeout = Duration(seconds: 12);

    Future<bool> runOne(DeviceConfig printer, int copy) async {
      try {
        await printerService
            .printReceipt(
              printer,
              receiptData,
              jobType: copy == 0 ? 'cashier' : 'cashier_copy_${copy + 1}',
            )
            .timeout(perPrintTimeout, onTimeout: () {
          debugPrint('⏱️ Print timed out on ${printer.name} (copy ${copy + 1})');
          throw TimeoutException('print timed out', perPrintTimeout);
        });
        return true;
      } catch (e) {
        debugPrint('⚠️ Print failed on ${printer.name} (copy ${copy + 1}): $e');
        return false;
      }
    }

    var anyFailed = false;
    for (var copy = 0; copy < totalCopies; copy++) {
      debugPrint('🧾 Printing copy ${copy + 1}/$totalCopies on ${cashierPrinters.map((p) => p.name).join(", ")}');
      // Fire every printer in parallel but bound each by perPrintTimeout so
      // one dead printer can't stall the whole cycle.
      final results = await Future.wait(
        cashierPrinters.map((printer) => runOne(printer, copy)),
      );
      if (!results.any((s) => s)) anyFailed = true;

      // Thermal printers sometimes merge back-to-back jobs; a short gap
      // between copies gives the printer time to cut and reset.
      if (copy + 1 < totalCopies) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    if (anyFailed) _showPrintFailureSnackBar();
  }

  Future<List<DeviceConfig>> _resolvePrintersForRole({
    required PrinterRole role,
    required List<DeviceConfig> printers,
  }) async {
    final registry = getIt<PrinterRoleRegistry>();
    await registry.initialize();

    final physical = printers.where(_isPhysicalPrinter).toList(growable: false);
    if (physical.isEmpty) return const <DeviceConfig>[];

    final matches = physical
        .where((printer) => registry.resolveRole(printer) == role)
        .toList(growable: false);
    if (matches.isNotEmpty) {
      matches.sort((a, b) => a.name.compareTo(b.name));
      return matches;
    }

    // Only fall back to printers with `general` role — never reuse cashier or kitchen printers
    if (role == PrinterRole.general) {
      return const <DeviceConfig>[];
    }

    // For cashierReceipt role: fall back to non-kitchen printers
    final nonKitchen = physical.where((printer) {
      final resolved = registry.resolveRole(printer);
      return resolved != PrinterRole.kitchen &&
          resolved != PrinterRole.kds &&
          resolved != PrinterRole.bar;
    }).toList(growable: false);
    if (nonKitchen.isNotEmpty) {
      nonKitchen.sort((a, b) => a.name.compareTo(b.name));
      return nonKitchen;
    }

    // No matching printers found — return empty (don't fall back to kitchen printers)
    return const <DeviceConfig>[];
  }

  void _printOrderChangeTicket(List<OrderChange> changes, String orderNumber, {bool isFullCancel = false}) {
    if (changes.isEmpty) return;

    // Resolve printer language (local, device-scoped). The kitchen ticket
    // renders `tagPrimary` as the main line and `tagSecondary` underneath,
    // so we need both values whenever the cashier enabled a secondary
    // language that differs from the primary (e.g. Spanish + English).
    final String invoiceLang = printerLanguageSettings.primary;
    final String invoiceLangSecondary =
        printerLanguageSettings.allowSecondary &&
                printerLanguageSettings.secondary != invoiceLang
            ? printerLanguageSettings.secondary
            : '';

    String _pick(String code, {required String ar, required String en, String? es, String? tr, String? hi, String? ur}) {
      switch (code) {
        case 'es': return es ?? en;
        case 'tr': return tr ?? en;
        case 'hi': return hi ?? en;
        case 'ur': return ur ?? en;
        case 'en': return en;
        case 'ar': return ar;
        default: return ar;
      }
    }

    String _tl(String ar, String en, {String? es, String? tr, String? hi, String? ur}) =>
        _pick(invoiceLang, ar: ar, en: en, es: es, tr: tr, hi: hi, ur: ur);

    // Returns the secondary-language label or an empty string when no
    // distinct secondary is configured — caller threads this into
    // `tagSecondary` so the kitchen view can render a bilingual badge.
    String _tlSec(String ar, String en, {String? es, String? tr, String? hi, String? ur}) {
      if (invoiceLangSecondary.isEmpty) return '';
      return _pick(invoiceLangSecondary, ar: ar, en: en, es: es, tr: tr, hi: hi, ur: ur);
    }

    // Resolve name for invoice language
    String _resolveName(OrderChange change) {
      final loc = change.localizedNames;
      if (loc != null && loc.containsKey(invoiceLang) && loc[invoiceLang]!.isNotEmpty) {
        return loc[invoiceLang]!;
      }
      // Fallback: English → original name
      if (loc != null && loc.containsKey('en') && loc['en']!.isNotEmpty) {
        return loc['en']!;
      }
      return change.name;
    }

    // Flatten an OrderChange's extras into the shape the kitchen view expects:
    // `{name, translations: {option: {ar, en, ...}, attribute: {ar, en, ...}}}`.
    // Including `translations` lets the kitchen ticket print the addon in the
    // cashier's selected invoice language instead of only Arabic.
    List<Map<String, dynamic>> extrasFor(OrderChange change) {
      if (change.extras.isEmpty) return const [];
      return change.extras.map((e) {
        final entry = <String, dynamic>{'name': e.name};
        if (e.optionTranslations.isNotEmpty || e.attributeTranslations.isNotEmpty) {
          entry['translations'] = <String, Map<String, String>>{
            if (e.optionTranslations.isNotEmpty) 'option': e.optionTranslations,
            if (e.attributeTranslations.isNotEmpty)
              'attribute': e.attributeTranslations,
          };
        }
        return entry;
      }).toList(growable: false);
    }

    // Build change items for kitchen ticket
    final changeItems = <Map<String, dynamic>>[];
    for (final change in changes) {
      final resolvedName = _resolveName(change);
      final extras = extrasFor(change);
      switch (change.type) {
        case 'add':
          changeItems.add({
            'name': '+ $resolvedName',
            'nameAr': resolvedName,
            'quantity': change.quantity,
            'tag': 'Add',
            'tagAr': _tl('إضافة', 'Add', es: 'Agregar', tr: 'Ekle', hi: 'जोड़ें', ur: 'شامل کریں'),
            'tagPrimary': _tl('إضافة', 'Add', es: 'Agregar', tr: 'Ekle', hi: 'जोड़ें', ur: 'شامل کریں'),
            'tagSecondary': _tlSec('إضافة', 'Add', es: 'Agregar', tr: 'Ekle', hi: 'जोड़ें', ur: 'شامل کریں'),
            'tagColor': 'green',
            if (change.localizedNames != null) 'localizedNames': change.localizedNames,
            if (extras.isNotEmpty) 'extras': extras,
          });
          break;
        case 'cancel':
          changeItems.add({
            'name': resolvedName,
            'nameAr': resolvedName,
            'quantity': change.quantity,
            'tag': 'Cancelled',
            'tagAr': _tl('ملغي', 'Cancelled', es: 'Cancelado', tr: 'İptal', hi: 'रद्द', ur: 'منسوخ'),
            'tagPrimary': _tl('ملغي', 'Cancelled', es: 'Cancelado', tr: 'İptal', hi: 'रद्द', ur: 'منسوخ'),
            'tagSecondary': _tlSec('ملغي', 'Cancelled', es: 'Cancelado', tr: 'İptal', hi: 'रद्द', ur: 'منسوخ'),
            'cancelled': true,
            'tagColor': 'black',
            if (change.localizedNames != null) 'localizedNames': change.localizedNames,
            if (extras.isNotEmpty) 'extras': extras,
          });
          break;
        case 'partial_cancel':
          changeItems.add({
            'name': resolvedName,
            'nameAr': resolvedName,
            'quantity': change.quantity,
            'tag': 'Partial Cancel',
            'tagAr': _tl('إلغاء جزئي', 'Partial Cancel', es: 'Cancelación parcial', tr: 'Kısmi İptal', hi: 'आंशिक रद्द', ur: 'جزوی منسوخی'),
            'tagPrimary': _tl('إلغاء جزئي', 'Partial Cancel', es: 'Cancelación parcial', tr: 'Kısmi İptal', hi: 'आंशिक रद्द', ur: 'جزوی منسوخی'),
            'tagSecondary': _tlSec('إلغاء جزئي', 'Partial Cancel', es: 'Cancelación parcial', tr: 'Kısmi İptal', hi: 'आंशिक रद्द', ur: 'جزوی منسوخی'),
            'tagColor': 'black',
            'oldQuantity': change.oldQuantity,
            'cancelledQuantity': change.cancelledQuantity,
            if (change.localizedNames != null) 'localizedNames': change.localizedNames,
            if (extras.isNotEmpty) 'extras': extras,
          });
          break;
        case 'qty_change':
          changeItems.add({
            'name': resolvedName,
            'nameAr': resolvedName,
            'quantity': change.quantity,
            'tag': 'Qty Change',
            'tagPrimary': _tl('تعديل كمية', 'Qty Change', es: 'Cambio de cantidad', tr: 'Miktar Değişikliği', hi: 'मात्रा बदलें', ur: 'مقدار تبدیلی'),
            'tagSecondary': _tlSec('تعديل كمية', 'Qty Change', es: 'Cambio de cantidad', tr: 'Miktar Değişikliği', hi: 'मात्रा बदलें', ur: 'مقدار تبدیلی'),
            'tagAr': _tl('تعديل كمية', 'Qty Change', es: 'Cambio de cantidad', tr: 'Miktar Değişikliği', hi: 'मात्रा बदلें', ur: 'مقدار تبدیلی'),
            'tagColor': 'orange',
            'oldQuantity': change.oldQuantity,
            if (change.localizedNames != null) 'localizedNames': change.localizedNames,
            if (extras.isNotEmpty) 'extras': extras,
          });
          break;
        case 'replace_old':
          changeItems.add({
            'name': resolvedName,
            'nameAr': resolvedName,
            'quantity': change.quantity,
            'tag': 'Cancelled',
            'tagAr': _tl('ملغي', 'Cancelled', es: 'Cancelado', tr: 'İptal', hi: 'रद्द', ur: 'منسوخ'),
            'tagPrimary': _tl('ملغي', 'Cancelled', es: 'Cancelado', tr: 'İptal', hi: 'रद्द', ur: 'منسوخ'),
            'tagSecondary': _tlSec('ملغي', 'Cancelled', es: 'Cancelado', tr: 'İptal', hi: 'रद्द', ur: 'منسوخ'),
            'cancelled': true,
            'tagColor': 'black',
            if (change.localizedNames != null) 'localizedNames': change.localizedNames,
            if (extras.isNotEmpty) 'extras': extras,
          });
          break;
        case 'replace_new':
          changeItems.add({
            'name': resolvedName,
            'nameAr': resolvedName,
            'quantity': change.quantity,
            'tag': 'New',
            'tagAr': _tl('جديد', 'New', es: 'Nuevo', tr: 'Yeni', hi: 'نया', ur: 'نیا'),

            'tagPrimary': _tl('جديد', 'New', es: 'Nuevo', tr: 'Yeni', hi: 'نया', ur: 'نیا'),

            'tagSecondary': _tlSec('جديد', 'New', es: 'Nuevo', tr: 'Yeni', hi: 'نया', ur: 'نیا'),
            'tagColor': 'green',
            if (change.localizedNames != null) 'localizedNames': change.localizedNames,
            if (extras.isNotEmpty) 'extras': extras,
          });
          break;
      }
    }

    // Use kitchen print orchestrator to print to kitchen printers
    unawaited(() async {
      try {
        final orchestrator = getIt<PrintOrchestratorService>();
        List<DeviceConfig> kitchenPrinters =
            _devices.where(_isUsablePrinter).toList();

        final registry = getIt<PrinterRoleRegistry>();
        await registry.initialize();
        kitchenPrinters = kitchenPrinters.where((p) {
          final role = registry.resolveRole(p);
          return role == PrinterRole.kitchen ||
              role == PrinterRole.kds ||
              role == PrinterRole.bar;
        }).toList();

        if (kitchenPrinters.isEmpty) {
          debugPrint('ℹ️ No kitchen printers for change ticket');
          return;
        }

        // Decide header/note based on whether the whole order is being cancelled
        // (isFullCancel is set by callers that cancel the entire order) vs a partial edit.
        final hasAnyCancel = changeItems.any(
          (item) => item['cancelled'] == true || item['cancelledQuantity'] != null,
        );
        final orderTypeLabel = isFullCancel
            ? _tl('إلغاء طلب', 'Order Cancelled', es: 'Pedido Cancelado', tr: 'Sipariş İptal', hi: 'ऑर्डर रद्द', ur: 'آرڈر منسوخ')
            : _tl('تعديل طلب', 'Order Change', es: 'Cambio de Pedido', tr: 'Sipariş Değişikliği', hi: 'ऑर्डर बदलें', ur: 'آرڈر تبدیلی');
        final String? noteLabel = isFullCancel
            ? _tl('⛔ الطلب ملغي بالكامل', '⛔ Entire order cancelled', es: '⛔ Pedido cancelado', tr: '⛔ Sipariş tamamen iptal', hi: '⛔ पूरा ऑर्डर रद्द', ur: '⛔ پورا آرڈر منسوخ')
            : (hasAnyCancel
                ? _tl('⚠️ إلغاء جزئي', '⚠️ Partial cancellation', es: '⚠️ Cancelación parcial', tr: '⚠️ Kısmi iptal', hi: '⚠️ आंशिक रद्दीकरण', ur: '⚠️ جزوی منسوخی')
                : null);

        await orchestrator.enqueueKitchenPrint(
          printers: kitchenPrinters,
          orderNumber: orderNumber,
          orderType: orderTypeLabel,
          items: changeItems,
          note: noteLabel,
          isRtl: _useArabicUi,
          primaryLang: invoiceLang,
        );
        debugPrint('✅ Order change ticket dispatched for #$orderNumber');
      } catch (e) {
        debugPrint('⚠️ Failed to print order change ticket: $e');
      }
    }());
  }

  Future<bool> _printReceiptToPrinters({
    required List<DeviceConfig> printers,
    required OrderReceiptData receiptData,
    String? invoiceId,
    required String jobType,
  }) async {
    if (printers.isEmpty) return false;

    final results = await Future.wait(printers.map((printer) async {
      var anySuccess = false;
      final copies = printer.copies <= 0 ? 1 : printer.copies;
      for (var copy = 0; copy < copies; copy++) {
        final success = await _printReceiptToPrinter(
          printer: printer,
          receiptData: receiptData,
          invoiceId: invoiceId,
          jobType: jobType,
        );
        if (success) anySuccess = true;
      }
      return anySuccess;
    }));

    return results.any((s) => s);
  }

  Future<bool> _printReceiptToPrinter({
    required DeviceConfig printer,
    required OrderReceiptData receiptData,
    String? invoiceId,
    required String jobType,
  }) async {
    try {
      final printerService = getIt<PrinterService>();
      await printerService.printReceipt(
        printer,
        receiptData,
        jobType: jobType,
      );
      return true;
    } catch (e) {
      debugPrint('⚠️ Print failed on ${printer.name}: $e');
      return false;
    }
  }

  void _showPrintFailureSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تعذر الطباعة — تحقق من اتصال الطابعة'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showMissingPrinterSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚠️ يجب ربط طابعة لطباعة الفواتير'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _loadCachedDevicesThenRefresh() async {
    // Phase 1: Serve cached/local devices INSTANTLY (no network wait)
    try {
      final deviceService = getIt<DeviceService>();
      final cached = await deviceService.getCachedDevices();
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _devices
            ..clear()
            ..addAll(cached);
        });
      }
    } catch (_) {}

    // Phase 2: Refresh from API in background
    await _loadDevicesFromApi();
  }

  Future<void> _autoConnectPrinters() async {
    final printers = _devices.where(_isUsablePrinter).toList();
    if (printers.isEmpty) return;
    final orchestrator = getIt<PrintOrchestratorService>();
    final printerService = getIt<PrinterService>();
    for (final device in printers) {
      if (!mounted) break;
      try {
        final ok = await printerService.testConnection(device).timeout(
          const Duration(seconds: 3),
          onTimeout: () => false,
        );
        if (!mounted) return;
        setState(() => device.isOnline = ok);
        orchestrator.updatePrinterStatus(device.id, ok);
        debugPrint('🖨️ Auto-connect [${device.name}] ${device.ip}:${device.port} → ${ok ? "ONLINE" : "OFFLINE"}');
      } catch (_) {
        if (!mounted) return;
        setState(() => device.isOnline = false);
      }
    }
  }

  Future<void> _loadDevicesFromApi() async {
    if (!_canCallBranchApis()) return;

    final deviceService = getIt<DeviceService>();
    final devices = await deviceService.getDevices();
    if (!mounted) return;
    setState(() {
      _devices
        ..clear()
        ..addAll(devices);
    });

    // Auto-connect all printers on startup
    unawaited(_autoConnectPrinters());

    final displayService = getIt<DisplayAppService>();
    if (!_isCdsEnabled && !_isKdsEnabled) {
      if (displayService.isConnected) {
        displayService.disconnect();
      }
      return;
    }

    // Never override a live session during background/data refresh.
    if (displayService.isConnected ||
        displayService.isConnecting ||
        displayService.isReconnecting) {
      return;
    }
    final preferredIp = displayService.connectedIp?.trim();
    final displayDevices = devices
        .where((d) => _isDisplayDeviceType(d.type) && d.ip.trim().isNotEmpty)
        .where((d) => _isDisplayModeEnabled(_displayModeForDevice(d)))
        .toList(growable: false);
    final kitchenScreen = displayDevices.cast<DeviceConfig?>().firstWhere(
          (d) =>
              d != null &&
              preferredIp != null &&
              preferredIp.isNotEmpty &&
              d.ip.trim() == preferredIp,
          orElse: () => displayDevices.isNotEmpty ? displayDevices.first : null,
        );
    if (kitchenScreen != null) {
      final parsedPort = int.tryParse(kitchenScreen.port) ?? 8080;
      final targetMode = _displayModeForDevice(kitchenScreen);
      try {
        final sameEndpoint =
            displayService.connectedIp?.trim() == kitchenScreen.ip.trim() &&
                displayService.connectedPort == parsedPort;
        if (displayService.isConnected && sameEndpoint) {
          if (displayService.currentMode != targetMode) {
            displayService.setMode(targetMode);
          }
        } else {
          await displayService.connectWithMode(
            kitchenScreen.ip,
            port: parsedPort,
            mode: targetMode,
          );
        }
      } catch (e) {
        debugPrint('⚠️ Failed to auto-connect display device: $e');
      }
    }
  }

  Future<void> _addDevice(DeviceConfig device) async {
    print('🖥️ [MainScreen] _addDevice called with: ${device.toJson()}');
    final deviceService = getIt<DeviceService>();
    print('🖥️ [MainScreen] Creating device via DeviceService...');
    final created = await deviceService.createDevice(device);
    print('🖥️ [MainScreen] Device created: ${created.toJson()}');
    if (!mounted) {
      print('🖥️ [MainScreen] Not mounted, returning');
      return;
    }
    setState(() => _devices.add(created));
    print('🖥️ [MainScreen] Device added to _devices list');

    if (_isDisplayDeviceType(created.type) && created.ip.isNotEmpty) {
      final displayService = getIt<DisplayAppService>();
      final parsedPort = int.tryParse(created.port) ?? 8080;
      final targetMode = _displayModeForDevice(created);
      if (!_isDisplayModeEnabled(targetMode)) {
        return;
      }
      final sameEndpoint =
          displayService.connectedIp?.trim() == created.ip.trim() &&
              displayService.connectedPort == parsedPort;
      if (displayService.isConnected && sameEndpoint) {
        if (displayService.currentMode != targetMode) {
          displayService.setMode(targetMode);
        }
      } else {
        try {
          await displayService.connectWithMode(
            created.ip,
            port: parsedPort,
            mode: targetMode,
          );
        } catch (e) {
          print(
              '🖥️ [MainScreen] Display connection failed (device saved): $e');
        }
      }
    }
  }

  Future<void> _removeDevice(String id) async {
    final deviceService = getIt<DeviceService>();
    await deviceService.deleteDevice(id);

    // Clean up role, category assignments, kitchen routing, and printer status
    try { getIt<PrinterRoleRegistry>().clearRole(id); } catch (_) {}
    try { getIt<CategoryPrinterRouteRegistry>().clearPrinterAssignments(id); } catch (_) {}
    try { getIt<KitchenPrinterRouteRegistry>().clearPrinterAssignments(id); } catch (_) {}
    try { getIt<PrintOrchestratorService>().updatePrinterStatus(id, false); } catch (_) {}

    if (!mounted) return;
    setState(() => _devices.removeWhere((d) => d.id == id));
  }
}
