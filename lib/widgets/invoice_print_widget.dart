library invoice_print_widget;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hermosa_pos/utils/paper_width_utils.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/receipt_data.dart';
import '../services/api/api_constants.dart';
import 'invoice_html_template.dart';

/// Dashed Divider Widget

part 'invoice_print_widget_parts/invoice_print_widget.helpers.dart';
part 'invoice_print_widget_parts/invoice_print_widget.html.dart';
part 'invoice_print_widget_parts/invoice_print_widget.header.dart';
part 'invoice_print_widget_parts/invoice_print_widget.items.dart';
part 'invoice_print_widget_parts/invoice_print_widget.totals.dart';
part 'invoice_print_widget_parts/invoice_print_widget.footer_qr.dart';
part 'invoice_print_widget_parts/invoice_print_widget.translators.dart';
part 'invoice_print_widget_parts/invoice_print_widget.test_view.dart';
part 'invoice_print_widget_parts/invoice_print_widget.kitchen_view.dart';

// Static helpers relocated from InvoicePrintWidget class to library-level
// so extensions can reference them without qualification.
// Bodies preserved verbatim from the original file.

/// Format a datetime string to "yyyy-MM-dd hh:mm a" (no seconds)
String _formatDateTime(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  try {
    final dt = DateTime.parse(raw);
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $amPm';
  } catch (_) {
    // If parsing fails, try to strip seconds from "2026-04-15 14:30:45"
    final match = RegExp(r'(\d{4}-\d{2}-\d{2})\s+(\d{1,2}):(\d{2})').firstMatch(raw);
    if (match != null) {
      final date = match.group(1)!;
      final h = int.tryParse(match.group(2)!) ?? 0;
      final m = match.group(3)!;
      final hour = h % 12 == 0 ? 12 : h % 12;
      final amPm = h >= 12 ? 'PM' : 'AM';
      return '$date ${hour.toString().padLeft(2, '0')}:$m $amPm';
    }
    return raw;
  }
}

/// Group addons by name, returning a list of (addon, count) entries.
List<MapEntry<ReceiptAddon, int>> _groupedAddons(List<ReceiptAddon> addons) {
  final map = <String, MapEntry<ReceiptAddon, int>>{};
  for (final addon in addons) {
    final key = addon.nameAr;
    if (map.containsKey(key)) {
      map[key] = MapEntry(addon, map[key]!.value + 1);
    } else {
      map[key] = MapEntry(addon, 1);
    }
  }
  return map.values.toList();
}

class DottedDivider extends StatelessWidget {
  const DottedDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.constrainWidth();
        const dotWidth = 2.0;
        const dotSpace = 4.0;
        final dotCount = (boxWidth / (dotWidth + dotSpace)).floor();
        return Flex(
          direction: Axis.horizontal,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(dotCount, (_) {
            return SizedBox(
              width: dotWidth,
              height: 2,
              child: const DecoratedBox(
                decoration: BoxDecoration(color: Colors.grey),
              ),
            );
          }),
        );
      },
    );
  }
}

class DashedDivider extends StatelessWidget {
  final Color color;
  const DashedDivider({super.key, this.color = Colors.black});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 4.0;
        const dashSpace = 3.0;
        final dashCount = (boxWidth / (dashWidth + dashSpace)).floor();
        return Flex(
          direction: Axis.horizontal,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: dashWidth,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: color),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Invoice Print Widget - Black & White Theme
class InvoicePrintWidget extends StatelessWidget {
  final OrderReceiptData? data;
  final Map<String, dynamic>? kitchenData;
  final bool isTest;
  final int paperWidthMm;
  final String? orderType;
  final String? tableNumber;
  final String? carNumber;
  final String? dailyOrderNumber;
  final String? carBrand;
  final String? carModel;
  final String? carPlateNumber;
  final String? carYear;
  final String? clientName;
  final String? clientPhone;
  final String? clientTaxNumber;
  final String? commercialRegisterNumber;
  final String? returnPolicy;
  final bool useHtmlView;
  final String primaryLang;
  final String secondaryLang;
  final bool allowSecondary;

  const InvoicePrintWidget({
    super.key,
    this.data,
    this.kitchenData,
    this.isTest = false,
    this.paperWidthMm = 58,
    this.orderType,
    this.tableNumber,
    this.carNumber,
    this.dailyOrderNumber,
    this.carBrand,
    this.carModel,
    this.carPlateNumber,
    this.carYear,
    this.clientName,
    this.clientPhone,
    this.clientTaxNumber,
    this.commercialRegisterNumber,
    this.returnPolicy,
    this.useHtmlView = false,
    this.isRtl = true,
    this.isCreditNote = false,
    this.primaryLang = 'ar',
    this.secondaryLang = 'en',
    this.allowSecondary = true,
  });

  final bool isRtl;
  final bool isCreditNote;

  @override
  Widget build(BuildContext context) {
    final receiptWidth = _receiptWidth;

    // Restore the original wrapper (padding 8, fontSize 20, line-height 1.4)
    // for every receipt type. Earlier tighter values broke QR capture on the
    // cashier receipt; inner widgets still have their own compact font sizes
    // where they explicitly set fontSize.
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        key: const ValueKey('invoice-print-root'),
        width: receiptWidth,
        color: Colors.white,
        padding: const EdgeInsets.all(5),
        child: DefaultTextStyle(
          style: GoogleFonts.tajawal(
            color: Colors.black,
            fontSize: isTest ? 24 : 20,
            fontWeight: FontWeight.bold,
            height: 1.4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isTest)
                _buildTestView()
              else if (kitchenData != null)
                _buildKitchenView()
              else if (data != null) ...[
                _buildHeader(),
                _buildInvoiceTitle(),
                if (clientName != null ||
                    clientPhone != null ||
                    clientTaxNumber != null)
                  _buildClientInfo(),
                if ((orderType?.isNotEmpty == true
                            ? orderType
                            : data!.orderType) ==
                        'restaurant_parking' ||
                    (data!.carNumber.isNotEmpty) ||
                    (carNumber != null && carNumber!.isNotEmpty))
                  _buildCarInfo(),
                _buildItems(),
                _buildTotals(),
                _buildFooter(),
              ] else
                const Center(child: Text('لا توجد بيانات للطباعة')),
            ],
          ),
        ),
      ),
    );
  }

}
