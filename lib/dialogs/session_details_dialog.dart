import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/language_service.dart';
import '../services/app_themes.dart';

/// Read-only viewer for a single booking session (تذكرة مراجعة).
///
/// Renders the response of `GET /seller/branches/{id}/bookingSessions/{id}`
/// — branch + cashier + client header followed by the session items table.
/// Includes the QR code returned in `qr_image` so the cashier can scan
/// straight from the dialog instead of needing to print first.
class SessionDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> sessionData;

  const SessionDetailsDialog({super.key, required this.sessionData});

  bool get _useArabicUi {
    final code = translationService.currentLanguageCode.trim().toLowerCase();
    return code.startsWith('ar') || code.startsWith('ur');
  }

  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 700;
    final dialogWidth = (size.width * (isCompact ? 0.95 : 0.7))
        .clamp(320.0, 720.0)
        .toDouble();
    final dialogHeight = (size.height * 0.85).clamp(420.0, 820.0).toDouble();

    final invoice = _asMap(sessionData['invoice']) ?? const {};
    final invoiceNumber = invoice['invoice_number']?.toString() ?? '';
    final dateStr = invoice['date']?.toString() ?? '';
    final timeStr = invoice['time']?.toString() ?? '';
    final client = _asMap(invoice['client']);
    final cashier = _asMap(invoice['cashier']);
    final itemsRaw = invoice['items'];
    final items = itemsRaw is List
        ? itemsRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final qrBase64 = sessionData['qr_image']?.toString() ?? '';
    Uint8List? qrBytes;
    if (qrBase64.startsWith('data:image')) {
      final commaIdx = qrBase64.indexOf(',');
      if (commaIdx > 0) {
        try {
          qrBytes = base64Decode(qrBase64.substring(commaIdx + 1));
        } catch (_) {}
      }
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            _buildHeader(context, invoiceNumber),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMetaRow(context, dateStr, timeStr),
                    const SizedBox(height: 12),
                    if (client != null)
                      _buildPartyCard(
                        context,
                        title: _tr('العميل', 'Client'),
                        name: client['name']?.toString() ?? '',
                        mobile: client['mobile']?.toString() ?? '',
                      ),
                    if (cashier != null) ...[
                      const SizedBox(height: 8),
                      _buildPartyCard(
                        context,
                        title: _tr('الكاشير', 'Cashier'),
                        name: cashier['fullname']?.toString() ?? '',
                        mobile: cashier['mobile']?.toString() ?? '',
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      _tr('الخدمات', 'Items'),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: context.appText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...items.map((it) => _buildItemRow(context, it)),
                    if (qrBytes != null) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: context.appBorder),
                          ),
                          child: Image.memory(qrBytes, width: 160, height: 160),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String invoiceNumber) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      decoration: BoxDecoration(
        color: context.appCardBg,
        border: Border(bottom: BorderSide(color: context.appBorder)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.ticket,
              color: Color(0xFFF58220), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              invoiceNumber.isEmpty
                  ? _tr('تذكرة مراجعة', 'Review Ticket')
                  : invoiceNumber,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: context.appText,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(LucideIcons.x),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(BuildContext context, String date, String time) {
    return Row(
      children: [
        if (date.isNotEmpty) ...[
          const Icon(LucideIcons.calendar,
              size: 14, color: Color(0xFF94A3B8)),
          const SizedBox(width: 4),
          Text(date, style: TextStyle(color: context.appText, fontSize: 13)),
          const SizedBox(width: 12),
        ],
        if (time.isNotEmpty) ...[
          const Icon(LucideIcons.clock,
              size: 14, color: Color(0xFF94A3B8)),
          const SizedBox(width: 4),
          Text(time, style: TextStyle(color: context.appText, fontSize: 13)),
        ],
      ],
    );
  }

  Widget _buildPartyCard(
    BuildContext context, {
    required String title,
    required String name,
    required String mobile,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.appText.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: context.appText,
            ),
          ),
          if (mobile.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                mobile,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF64748B)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItemRow(BuildContext context, Map<String, dynamic> item) {
    final name = item['item_name']?.toString() ?? '';
    final employee = item['employee_name']?.toString() ?? '';
    final date = item['date']?.toString() ?? '';
    final time = item['time']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.appBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: context.appText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (employee.isNotEmpty) employee,
              if (date.isNotEmpty) date,
              if (time.isNotEmpty) time,
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appCardBg,
        border: Border(top: BorderSide(color: context.appBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(LucideIcons.check, size: 16),
            label: Text(_tr('إغلاق', 'Close')),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF58220),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
