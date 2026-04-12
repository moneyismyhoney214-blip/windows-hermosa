import 'package:flutter/material.dart';

import '../locator.dart';
import '../models.dart';
import '../models/receipt_data.dart';
import '../services/api/device_service.dart';
import '../services/invoice_html_pdf_service.dart';
import '../services/printer_role_registry.dart';
import '../widgets/pdf_preview_screen.dart';

class InvoicePreviewHelper {
  static final DeviceService _deviceService = getIt<DeviceService>();
  static final PrinterRoleRegistry _printerRoleRegistry =
      getIt<PrinterRoleRegistry>();

  static bool _isDisplayDeviceType(String type) {
    final normalized = type.trim().toLowerCase();
    return normalized == 'kds' ||
        normalized == 'kitchen_screen' ||
        normalized == 'order_viewer' ||
        normalized == 'cds' ||
        normalized == 'customer_display';
  }

  static bool _isPhysicalPrinter(DeviceConfig device) {
    final normalized = device.type.trim().toLowerCase();
    if (device.id.startsWith('kitchen:')) return false;
    if (_isDisplayDeviceType(normalized)) return false;
    return normalized == 'printer';
  }

  static Future<DeviceConfig?> _resolvePreferredPrinter({
    bool allowSinglePrinterFallback = true,
  }) async {
    try {
      await _printerRoleRegistry.initialize();
      final devices = await _deviceService.getDevices();
      final printers =
          devices.where(_isPhysicalPrinter).toList(growable: false);

      for (final printer in printers) {
        if (_printerRoleRegistry.resolveRole(printer) ==
            PrinterRole.cashierReceipt) {
          return printer;
        }
      }

      if (allowSinglePrinterFallback && printers.length == 1) {
        return printers.first;
      }
    } catch (_) {
      // Silent fallback.
    }

    return null;
  }

  static Future<void> open({
    required BuildContext context,
    required OrderReceiptData receiptData,
    String? invoiceId,
    String? orderType,
    DeviceConfig? preferredPrinter,
    bool promptPrinterSelectionOnOpen = true,
    bool forcePreferredPrinter = false,
    String? printButtonLabel,
  }) async {
    if (!context.mounted) return;

    final resolvedPrinter = preferredPrinter ??
        await _resolvePreferredPrinter(allowSinglePrinterFallback: true);

    String _buildTitle() {
      String label = receiptData.invoiceNumber.trim();
      if (label.isEmpty) {
        label = invoiceId?.trim() ?? '';
      }
      if (label.isNotEmpty && !label.startsWith('#')) {
        label = '#$label';
      }
      return label.isNotEmpty ? 'معاينة الفاتورة $label' : 'معاينة الفاتورة';
    }

    final normalizedInvoiceId = invoiceId?.trim();
    if (normalizedInvoiceId != null && normalizedInvoiceId.isNotEmpty) {
      try {
        final invoiceHtmlPdfService = getIt<InvoiceHtmlPdfService>();
        final htmlContent = await invoiceHtmlPdfService.generateHtmlString(
          normalizedInvoiceId,
        );

        if (!context.mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfPreviewScreen(
              receiptData: receiptData,
              printer: resolvedPrinter,
              htmlContent: htmlContent,
              title: _buildTitle(),
              promptPrinterSelectionOnOpen: promptPrinterSelectionOnOpen,
              forcePreferredPrinter: forcePreferredPrinter,
              carNumber:
                  receiptData.carNumber.isNotEmpty ? receiptData.carNumber : null,
              orderType: orderType,
              printButtonLabel: printButtonLabel,
            ),
          ),
        );
        return;
      } catch (e) {
        debugPrint('⚠️ Failed to generate HTML invoice preview: $e');
      }
    }

    if (!context.mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          receiptData: receiptData,
          printer: resolvedPrinter,
          promptPrinterSelectionOnOpen: promptPrinterSelectionOnOpen,
          forcePreferredPrinter: forcePreferredPrinter,
          carNumber:
              receiptData.carNumber.isNotEmpty ? receiptData.carNumber : null,
          title: _buildTitle(),
          orderType: orderType,
          printButtonLabel: printButtonLabel,
        ),
      ),
    );
  }
}
