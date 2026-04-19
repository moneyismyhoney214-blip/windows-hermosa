library invoice_details_dialog;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models.dart';
import '../models/receipt_data.dart';
import '../services/api/api_constants.dart';
import '../services/api/branch_service.dart';
import '../services/api/device_service.dart';
import '../services/api/order_service.dart';
import '../services/invoice_html_pdf_service.dart';
import '../services/print_audit_service.dart';
import '../services/printer_role_registry.dart';
import '../services/printer_service.dart';
import '../services/zatca_printer_service.dart';
import '../services/printer_language_settings_service.dart';
import '../services/language_service.dart';
import '../locator.dart';
import '../widgets/invoice_print_widget.dart';
import '../services/app_themes.dart';

part 'invoice_details_dialog_parts/invoice_details_dialog.actions.dart';
part 'invoice_details_dialog_parts/invoice_details_dialog.data_loading.dart';
part 'invoice_details_dialog_parts/invoice_details_dialog.state_helpers.dart';
part 'invoice_details_dialog_parts/invoice_details_dialog.refund_helpers.dart';
part 'invoice_details_dialog_parts/invoice_details_dialog.single_item_refund.dart';
part 'invoice_details_dialog_parts/invoice_details_dialog.build_widgets.dart';
part 'invoice_details_dialog_parts/invoice_details_dialog.utils.dart';

class InvoiceDetailsDialog extends StatefulWidget {
  final String invoiceId;
  final bool autoOpenRefund;
  final bool autoOpenSingleItemRefund;

  /// Callback to print receipt using the same logic as normal payment flow.
  final Future<void> Function({
    required OrderReceiptData receiptData,
    String? invoiceId,
  })? onPrintReceipt;

  const InvoiceDetailsDialog({
    super.key,
    required this.invoiceId,
    this.autoOpenRefund = false,
    this.autoOpenSingleItemRefund = false,
    this.onPrintReceipt,
  });

  @override
  State<InvoiceDetailsDialog> createState() => _InvoiceDetailsDialogState();
}

class _InvoiceDetailsDialogState extends State<InvoiceDetailsDialog> {
  final OrderService _orderService = getIt<OrderService>();
  final PrintAuditService _printAuditService = getIt<PrintAuditService>();
  bool _isLoading = true;
  bool _isSendingWhatsApp = false;
  bool _isProcessingRefund = false;
  bool _isPrintingInvoice = false;
  bool _didAutoOpenRefund = false;
  bool _didAutoOpenSingleItemRefund = false;
  Map<String, dynamic>? _invoiceDetails;
  String? _error;

  @override

  void initState() {
    super.initState();
    _loadInvoiceDetails();
  }


  // ═══════════════════════════════════════════════════════════════
  // PRINT METHODS (preserved verbatim — do not modify)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _printCreditNoteForInvoice(String invoiceId, {String? creditNoteNumber}) async {
    debugPrint('🧾 _printCreditNoteForInvoice START invoiceId=$invoiceId');
    try {
      final receiptData = await _buildReceiptDataForCreditNote(invoiceId, creditNoteNumber: creditNoteNumber);
      debugPrint('🧾 Credit note receiptData: ${receiptData != null ? "OK (${receiptData.items.length} items)" : "NULL"}');
      if (receiptData == null) {
        debugPrint('⚠️ Credit note: no receipt data');
        return;
      }

      final devices = await getIt<DeviceService>().getDevices();
      debugPrint('🧾 Credit note: ${devices.length} devices found');
      final printers = devices.where(_isPhysicalPrinter).toList(growable: false);
      if (printers.isEmpty) return;

      final cashierPrinters = await _resolvePrintersForRole(
        role: PrinterRole.cashierReceipt,
        printers: printers,
      );
      if (cashierPrinters.isEmpty) return;

      final printerService = getIt<PrinterService>();
      for (final printer in cashierPrinters) {
        try {
          await printerService.printReceipt(
            printer,
            receiptData,
            jobType: 'credit_note',
            isCreditNote: true,
          );
        } catch (e) {
          debugPrint('Credit note ESC/POS print failed: $e');
        }
      }
    } catch (e) {
      debugPrint('Credit note print failed: $e');
    }
  }

  Future<OrderReceiptData?> _buildReceiptDataForCreditNote(String invoiceId, {String? creditNoteNumber}) async {
    try {
      final invoiceResponse = await _orderService.getInvoice(invoiceId);
      final rawEnvelope = invoiceResponse.map((k, v) => MapEntry(k.toString(), v));
      final envelope = (rawEnvelope['data'] is Map)
          ? (rawEnvelope['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : rawEnvelope;

      final invoice = (envelope['invoice'] is Map)
          ? (envelope['invoice'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : envelope;
      final branch = (envelope['branch'] is Map)
          ? (envelope['branch'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
      final seller = (branch['seller'] is Map)
          ? (branch['seller'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};

      String pick(List<dynamic> candidates) {
        for (final c in candidates) {
          final t = c?.toString().trim();
          if (t != null && t.isNotEmpty && t.toLowerCase() != 'null') return t;
        }
        return '';
      }

      // Resolve printer language (local, device-scoped).
      final String invoicePri = printerLanguageSettings.primary;
      final String invoiceSec = printerLanguageSettings.secondary;

      String _resolveLangName(String langCode, String arName, String enName, Map? translations) {
        if (translations != null) {
          final resolved = translations[langCode]?.toString().trim() ?? '';
          if (resolved.isNotEmpty) return resolved;
        }
        if (langCode == 'ar' && arName.isNotEmpty) return arName;
        if (langCode == 'en' && enName.isNotEmpty) return enName;
        if (enName.isNotEmpty) return enName;
        return arName;
      }

      // Get ONLY refunded items
      List<Map<String, dynamic>> refundedMeals = [];
      try {
        refundedMeals = await _orderService.getRefundedMeals(invoiceId: invoiceId);
      } catch (_) {}

      final List<ReceiptItem> items;
      if (refundedMeals.isNotEmpty) {
        items = refundedMeals.map((m) {
          final rm = m.map((k, v) => MapEntry(k.toString(), v));
          final name = rm['meal_name']?.toString() ?? rm['name']?.toString() ?? rm['item_name']?.toString() ?? '';
          String arName = name;
          String enName = name;
          if (name.contains(' - ')) {
            arName = name.split(' - ').first.trim();
            enName = name.split(' - ').last.trim();
          }
          final mt = rm['meal_name_translations'];
          final primaryName = _resolveLangName(invoicePri, arName, enName, mt is Map ? mt : null);
          final secondaryName = _resolveLangName(invoiceSec, arName, enName, mt is Map ? mt : null);
          final qty = double.tryParse(rm['quantity']?.toString() ?? '1') ?? 1;
          final price = double.tryParse(rm['price']?.toString() ?? rm['total']?.toString() ?? '0') ?? 0;
          return ReceiptItem(nameAr: primaryName, nameEn: secondaryName != primaryName ? secondaryName : '', quantity: qty, unitPrice: price, total: price * qty);
        }).toList();
      } else {
        items = (invoice['items'] as List?)?.map((item) {
          final m = item is Map ? item.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
          final name = m['item_name']?.toString() ?? '';
          String arName = name;
          String enName = name;
          if (name.contains(' - ')) {
            arName = name.split(' - ').first.trim();
            enName = name.split(' - ').last.trim();
          }
          final mt = m['meal_name_translations'];
          final primaryName = _resolveLangName(invoicePri, arName, enName, mt is Map ? mt : null);
          final secondaryName = _resolveLangName(invoiceSec, arName, enName, mt is Map ? mt : null);
          final price = double.tryParse(m['meal_price']?.toString() ?? '') ?? double.tryParse(m['total']?.toString() ?? '') ?? 0;
          return ReceiptItem(nameAr: primaryName, nameEn: secondaryName != primaryName ? secondaryName : '', quantity: double.tryParse(m['quantity']?.toString() ?? '') ?? 1, unitPrice: price, total: price);
        }).toList() ?? [];
      }

      final totalExcl = items.fold(0.0, (sum, item) => sum + item.total);
      // Use the branch's real tax config instead of assuming 15% VAT.
      // Branches with `has_tax=false` return 0 here, keeping credit-note and
      // receipt totals consistent with the cashier settings.
      final branchService = getIt<BranchService>();
      final taxRate =
          branchService.cachedHasTax ? branchService.cachedTaxRate : 0.0;
      final tax = totalExcl * taxRate;
      final grandTotal = totalExcl + tax;

      final sellerName = pick([branch['seller_name']]);
      return OrderReceiptData(
        invoiceNumber: creditNoteNumber ?? pick([invoice['invoice_number']]),
        issueDateTime: DateTime.now().toIso8601String(),
        sellerNameAr: sellerName.contains('|') ? sellerName.split('|').first.trim() : sellerName,
        sellerNameEn: sellerName.contains('|') ? sellerName.split('|').last.trim() : sellerName,
        vatNumber: pick([seller['tax_number'], branch['tax_number']]),
        branchName: pick([branch['seller_name']]),
        items: items,
        totalExclVat: totalExcl,
        vatAmount: tax,
        totalInclVat: grandTotal,
        paymentMethod: pick([invoice['payment_methods']]),
        qrCodeBase64: pick([envelope['qr_image'], invoice['qr_image']]),
        branchAddress: () { final d = (branch['district']?.toString() ?? '').trim(); final a = (branch['address']?.toString() ?? '').trim(); return (d.isNotEmpty && a.isNotEmpty && d != a) ? '$d، $a' : (a.isNotEmpty ? a : d); }(),
        branchMobile: pick([branch['mobile']]),
        commercialRegisterNumber: pick([seller['commercial_register']]),
        issueDate: pick([invoice['date']]),
        issueTime: pick([invoice['time']]),
      );
    } catch (e) {
      debugPrint('⚠️ Failed to build credit note data: $e');
      return null;
    }
  }


  Future<void> _printCreditNoteWithItems(
    String invoiceId,
    List<_RefundCandidate> refundedItems, {
    String? creditNoteNumber,
  }) async {
    debugPrint('🧾 _printCreditNoteWithItems: ${refundedItems.length} items');
    try {
      // Build receipt data from refunded items
      final invoiceResponse = await _orderService.getInvoice(invoiceId);
      final rawEnvelope = invoiceResponse.map((k, v) => MapEntry(k.toString(), v));
      final envelope = (rawEnvelope['data'] is Map)
          ? (rawEnvelope['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : rawEnvelope;
      final invoice = (envelope['invoice'] is Map)
          ? (envelope['invoice'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : envelope;
      final branch = (envelope['branch'] is Map)
          ? (envelope['branch'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
      final seller = (branch['seller'] is Map)
          ? (branch['seller'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};

      String pick(List<dynamic> candidates) {
        for (final c in candidates) {
          final t = c?.toString().trim();
          if (t != null && t.isNotEmpty && t.toLowerCase() != 'null') return t;
        }
        return '';
      }

      // Resolve printer language (local, device-scoped).
      final String invoicePri2 = printerLanguageSettings.primary;
      final String invoiceSec2 = printerLanguageSettings.secondary;

      // Build translations map from invoice meals
      final invoiceMeals2 = (invoice['sales_meals'] ?? invoice['meals'] ?? invoice['items'] ?? invoice['booking_meals']);
      final translationsById2 = <int, Map>{};
      if (invoiceMeals2 is List) {
        for (final m in invoiceMeals2.whereType<Map>()) {
          final mealId = int.tryParse((m['meal_id'] ?? m['id'] ?? m['sales_meal_id'])?.toString() ?? '') ?? 0;
          final mt = m['meal_name_translations'];
          if (mealId > 0 && mt is Map) translationsById2[mealId] = mt;
        }
      }

      String _resolveLangName2(String langCode, String arName, String enName, Map? translations) {
        if (translations != null) {
          final resolved = translations[langCode]?.toString().trim() ?? '';
          if (resolved.isNotEmpty) return resolved;
        }
        if (langCode == 'ar' && arName.isNotEmpty) return arName;
        if (langCode == 'en' && enName.isNotEmpty) return enName;
        if (enName.isNotEmpty) return enName;
        return arName;
      }

      final items = refundedItems.map((c) {
        String arName = c.name;
        String enName = c.name;
        if (c.name.contains(' - ')) {
          arName = c.name.split(' - ').first.trim();
          enName = c.name.split(' - ').last.trim();
        }
        final translations = translationsById2[c.id];
        final primaryName = _resolveLangName2(invoicePri2, arName, enName, translations);
        final secondaryName = _resolveLangName2(invoiceSec2, arName, enName, translations);
        final unitPrice = c.quantity > 0 ? c.total / c.quantity : c.total;
        return ReceiptItem(nameAr: primaryName, nameEn: secondaryName != primaryName ? secondaryName : '', quantity: c.quantity.toDouble(), unitPrice: unitPrice, total: c.total);
      }).toList();

      final totalExcl = items.fold(0.0, (sum, item) => sum + item.total);
      // Use the branch's real tax config instead of assuming 15% VAT.
      // Branches with `has_tax=false` return 0 here, keeping credit-note and
      // receipt totals consistent with the cashier settings.
      final branchService = getIt<BranchService>();
      final taxRate =
          branchService.cachedHasTax ? branchService.cachedTaxRate : 0.0;
      final tax = totalExcl * taxRate;
      final grandTotal = totalExcl + tax;

      final sellerName = pick([branch['seller_name']]);
      final receiptData = OrderReceiptData(
        invoiceNumber: creditNoteNumber ?? pick([invoice['invoice_number']]),
        issueDateTime: DateTime.now().toIso8601String(),
        sellerNameAr: sellerName.contains('|') ? sellerName.split('|').first.trim() : sellerName,
        sellerNameEn: sellerName.contains('|') ? sellerName.split('|').last.trim() : sellerName,
        vatNumber: pick([seller['tax_number'], branch['tax_number']]),
        branchName: pick([branch['seller_name']]),
        items: items,
        totalExclVat: totalExcl,
        vatAmount: tax,
        totalInclVat: grandTotal,
        paymentMethod: pick([invoice['payment_methods']]),
        qrCodeBase64: pick([envelope['qr_image'], invoice['qr_image']]),
        branchAddress: () { final d = (branch['district']?.toString() ?? '').trim(); final a = (branch['address']?.toString() ?? '').trim(); return (d.isNotEmpty && a.isNotEmpty && d != a) ? '$d، $a' : (a.isNotEmpty ? a : d); }(),
        branchMobile: pick([branch['mobile']]),
        commercialRegisterNumber: pick([seller['commercial_register']]),
        issueDate: pick([invoice['date']]),
        issueTime: pick([invoice['time']]),
      );

      // Print using same ESC/POS flow with isCreditNote flag
      final devices = await getIt<DeviceService>().getDevices();
      final printers = devices.where(_isPhysicalPrinter).toList(growable: false);
      if (printers.isEmpty) return;

      final cashierPrinters = await _resolvePrintersForRole(
        role: PrinterRole.cashierReceipt,
        printers: printers,
      );
      final targetPrinters = cashierPrinters.isNotEmpty ? cashierPrinters : printers;

      final printerService = getIt<PrinterService>();
      for (final printer in targetPrinters) {
        try {
          await printerService.printReceipt(printer, receiptData, jobType: 'credit_note', isCreditNote: true);
          _printAuditService.logAttempt(
            printerIp: printer.connectionType == PrinterConnectionType.bluetooth
                ? (printer.bluetoothAddress ?? 'BT')
                : printer.ip,
            jobType: 'credit_note',
            success: true,
          );
        } catch (e) {
          _printAuditService.logAttempt(
            printerIp: printer.connectionType == PrinterConnectionType.bluetooth
                ? (printer.bluetoothAddress ?? 'BT')
                : printer.ip,
            jobType: 'credit_note',
            success: false,
            error: e.toString(),
          );
        }
      }
    } catch (e) {
      debugPrint('Credit note print failed: $e');
    }
  }

  bool _isPhysicalPrinter(DeviceConfig device) {
    final normalized = device.type.trim().toLowerCase();
    if (device.id.startsWith('kitchen:')) return false;
    return normalized == 'printer';
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

    physical.sort((a, b) => a.name.compareTo(b.name));
    return physical;
  }

  Future<bool> _printReceiptToPrinters({
    required List<DeviceConfig> printers,
    required OrderReceiptData receiptData,
    String? invoiceId,
    required String jobType,
  }) async {
    if (printers.isEmpty) return false;

    final results = await Future.wait(printers.map((printer) async {
      return await _printReceiptToPrinter(
        printer: printer,
        receiptData: receiptData,
        jobType: jobType,
      );
    }));

    return results.any((s) => s);
  }

  Future<bool> _printReceiptToPrinter({
    required DeviceConfig printer,
    required OrderReceiptData receiptData,
    required String jobType,
  }) async {
    try {
      final printerService = getIt<PrinterService>();
      await printerService.printReceipt(
        printer,
        receiptData,
        jobType: jobType,
      );

      _printAuditService.logAttempt(
        printerIp: printer.connectionType == PrinterConnectionType.bluetooth
            ? (printer.bluetoothAddress ?? 'BT')
            : printer.ip,
        jobType: jobType,
        success: true,
      );
      return true;
    } catch (e) {
      _printAuditService.logAttempt(
        printerIp: printer.connectionType == PrinterConnectionType.bluetooth
            ? (printer.bluetoothAddress ?? 'BT')
            : printer.ip,
        jobType: jobType,
        success: false,
        error: e.toString(),
      );
      return false;
    }
  }

  void _showPrintSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _printThisInvoice() async {
    if (_invoiceDetails == null || _isPrintingInvoice) return;

    final payload = _asMap(_invoiceDetails!['data']) ?? _invoiceDetails!;
    final data = _asMap(payload['invoice']) ?? payload;
    final receiptData = _mapToOrderReceiptData(payload, data);

    setState(() => _isPrintingInvoice = true);
    try {
      if (widget.onPrintReceipt != null) {
        // Use the same printing logic as normal payment flow
        await widget.onPrintReceipt!(
          receiptData: receiptData,
          invoiceId: widget.invoiceId,
        );
        _showPrintSnackBar('✅ تم إرسال الطباعة بنجاح', Colors.green);
      } else {
        // Fallback to direct printing
        final devices = await getIt<DeviceService>().getDevices();
        final printers =
            devices.where(_isPhysicalPrinter).toList(growable: false);
        if (printers.isEmpty) {
          _showPrintSnackBar('⚠️ يجب ربط طابعة لطباعة الفواتير', Colors.orange);
          return;
        }

        final cashierPrinters = await _resolvePrintersForRole(
          role: PrinterRole.cashierReceipt,
          printers: printers,
        );

        final success = await _printReceiptToPrinters(
          printers: cashierPrinters,
          receiptData: receiptData,
          invoiceId: widget.invoiceId,
          jobType: 'invoice_details_direct',
        );

        if (success) {
          _showPrintSnackBar('✅ تم إرسال الطباعة بنجاح', Colors.green);
        } else {
          _showPrintSnackBar(
            'تعذر الطباعة — تحقق من اتصال الطابعة',
            Colors.orange,
          );
        }
      }
    } catch (e) {
      _showPrintSnackBar('حدث خطأ: $e', Colors.orange);
    } finally {
      if (mounted) setState(() => _isPrintingInvoice = false);
    }
  }


  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00', 'ar');
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 700;
    final insetPadding = EdgeInsets.symmetric(
      horizontal: isCompact ? 12 : 24,
      vertical: isCompact ? 16 : 24,
    );
    final dialogWidth =
        (size.width - insetPadding.horizontal).clamp(280.0, 700.0).toDouble();
    final dialogHeight =
        (size.height - insetPadding.vertical).clamp(460.0, 760.0).toDouble();
    final canRefund = _invoiceDetails != null &&
        (_isInvoicePaidFromDetails() || _hasPartialRefundFromDetails()) &&
        !_isFullyRefundedFromDetails();

    return Dialog(
      insetPadding: insetPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(isCompact ? 14 : 20),
              decoration: const BoxDecoration(
                color: Color(0xFFF58220),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تفاصيل الفاتورة',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (_invoiceDetails != null)
                          Text(
                            'رقم الفاتورة: #${widget.invoiceId}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildErrorView()
                      : _buildInvoiceContent(formatter),
            ),
            Container(
              padding: EdgeInsets.all(isCompact ? 14 : 20),
              decoration: BoxDecoration(
                color: context.appBg,
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: isCompact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (canRefund) ...[
                            OutlinedButton.icon(
                              onPressed: _isProcessingRefund
                                  ? null
                                  : _showRefundOptions,
                              icon: _isProcessingRefund
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(LucideIcons.refreshCw, size: 18),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: const Color(0xFFEF4444),
                                side:
                                    const BorderSide(color: Color(0xFFEF4444)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              label: Text(_isProcessingRefund
                                  ? 'جارٍ الاسترجاع...'
                                  : 'استرجاع'),
                            ),
                            const SizedBox(height: 8),
                          ],
                          OutlinedButton.icon(
                            onPressed:
                                _isPrintingInvoice ? null : _printThisInvoice,
                            icon: _isPrintingInvoice
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(LucideIcons.printer, size: 18),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              foregroundColor: const Color(0xFFF58220),
                              side: const BorderSide(color: Color(0xFFF58220)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            label: Text(_isPrintingInvoice
                                ? 'جارٍ الطباعة...'
                                : 'طباعة الفاتورة'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _isSendingWhatsApp
                                ? null
                                : _sendWhatsAppForInvoice,
                            icon: _isSendingWhatsApp
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(LucideIcons.messageCircle,
                                    size: 18),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              foregroundColor: const Color(0xFF16A34A),
                              side: const BorderSide(color: Color(0xFF16A34A)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            label: Text(_isSendingWhatsApp
                                ? 'جارٍ الإرسال...'
                                : 'إرسال واتساب'),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              backgroundColor: const Color(0xFFF58220),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'إغلاق',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          if (canRefund) ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isProcessingRefund
                                    ? null
                                    : _showRefundOptions,
                                icon: _isProcessingRefund
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(LucideIcons.refreshCw,
                                        size: 18),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                  foregroundColor: const Color(0xFFEF4444),
                                  side: const BorderSide(
                                      color: Color(0xFFEF4444)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                label: Text(_isProcessingRefund
                                    ? 'جارٍ الاسترجاع...'
                                    : 'استرجاع'),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  _isPrintingInvoice ? null : _printThisInvoice,
                              icon: _isPrintingInvoice
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(LucideIcons.printer, size: 18),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                foregroundColor: const Color(0xFFF58220),
                                side:
                                    const BorderSide(color: Color(0xFFF58220)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              label: Text(_isPrintingInvoice
                                  ? 'جارٍ الطباعة...'
                                  : 'طباعة الفاتورة'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isSendingWhatsApp
                                  ? null
                                  : _sendWhatsAppForInvoice,
                              icon: _isSendingWhatsApp
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(LucideIcons.messageCircle,
                                      size: 18),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                foregroundColor: const Color(0xFF16A34A),
                                side:
                                    const BorderSide(color: Color(0xFF16A34A)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              label: Text(_isSendingWhatsApp
                                  ? 'جارٍ الإرسال...'
                                  : 'إرسال واتساب'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                backgroundColor: const Color(0xFFF58220),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'إغلاق',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  }


enum _RefundCandidateType { meal, product, unknown }

class _RefundCandidate {
  final int id;
  final _RefundCandidateType type;
  final String name;
  final double total;
  final int quantity;

  const _RefundCandidate({
    required this.id,
    required this.type,
    required this.name,
    required this.total,
    required this.quantity,
  });
}

class _RefundSelection {
  final List<_RefundCandidate> candidates;
  final String method;

  const _RefundSelection({
    required this.candidates,
    required this.method,
  });
}
