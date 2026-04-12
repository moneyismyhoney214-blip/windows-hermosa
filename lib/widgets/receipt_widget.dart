import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/receipt_data.dart';
import '../services/api/api_constants.dart';

class ReceiptWidget extends StatelessWidget {
  final OrderReceiptData data;

  const ReceiptWidget({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 380,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo and seller name
            if (data.sellerLogo != null && data.sellerLogo!.isNotEmpty)
              Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      data.sellerLogo!,
                      height: 80,
                      width: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => 
                        _buildFallbackHeader(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    data.sellerNameAr,
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (data.sellerNameEn.isNotEmpty)
                    Text(
                      data.sellerNameEn,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                      textAlign: TextAlign.center,
                    ),
                ],
              )
            else
              _buildFallbackHeader(),
            const SizedBox(height: 10),
            _buildMetaChipRow(),
            const SizedBox(height: 6),
            _buildInfoRow('الفرع', data.branchName),
            if (data.carNumber.isNotEmpty)
              _buildInfoRow('رقم السيارة', data.carNumber),
            _buildInfoRow('الرقم الضريبي', data.vatNumber),
            _buildInfoRow('رقم الفاتورة', data.invoiceNumber),
            _buildInfoRow('وقت الإصدار', data.issueDateTime),
            _buildInfoRow('الدفع', data.paymentMethod),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      'الصنف',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'الكمية',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'المجموع',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ...data.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.nameAr,
                                style: GoogleFonts.cairo(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                item.nameEn,
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  color: const Color(0xFF64748B),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              // الإضافات تحت اسم الصنف
                              if (item.addons != null && item.addons!.isNotEmpty)
                                ..._groupAddons(item.addons!).map((entry) {
                                  final addon = entry.key;
                                  final qty = entry.value;
                                  final label = qty > 1
                                      ? '+ ${addon.nameAr} x$qty'
                                      : '+ ${addon.nameAr}';
                                  return Text(
                                    label,
                                    style: GoogleFonts.cairo(
                                      fontSize: 10.5,
                                      color: const Color(0xFF64748B),
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              _formatQty(item.quantity),
                              style: GoogleFonts.cairo(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              item.total.toStringAsFixed(2),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 18),
            _buildTotalRow('الإجمالي قبل الضريبة', data.totalExclVat),
            _buildTotalRow('ضريبة القيمة المضافة (15%)', data.vatAmount),
            _buildTotalRow(
              'الإجمالي شامل الضريبة',
              data.totalInclVat,
              isBold: true,
            ),
            const SizedBox(height: 16),
            // Display ZATCA QR image if available, otherwise show base64 QR
            if (data.zatcaQrImage != null && data.zatcaQrImage!.isNotEmpty)
              Column(
                children: [
                  Image.network(
                    data.zatcaQrImage!,
                    height: 180,
                    width: 180,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback to base64 QR if image fails to load
                      if (data.qrCodeBase64.isNotEmpty) {
                        return QrImageView(
                          data: data.qrCodeBase64,
                          version: QrVersions.auto,
                          size: 180.0,
                          gapless: true,
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ZATCA QR Code',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            else if (data.qrCodeBase64.isNotEmpty)
              QrImageView(
                data: data.qrCodeBase64,
                version: QrVersions.auto,
                size: 180.0,
                gapless: true,
              ),
            const SizedBox(height: 10),
            Text(
              'شكراً لزيارتكم',
              style: GoogleFonts.cairo(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              'Thank you for your visit',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Fallback header with orange gradient (when no logo)
  Widget _buildFallbackHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF58220), Color(0xFFE56717)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            data.sellerNameAr,
            style: GoogleFonts.cairo(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          Text(
            data.sellerNameEn,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChipRow() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'فاتورة ضريبية مبسطة - Simplified Tax Invoice',
        textAlign: TextAlign.center,
        style: GoogleFonts.cairo(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF9A3412),
        ),
      ),
    );
  }

  Widget _buildMetaChip(String text, Color bg, {bool isArabic = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: isArabic
            ? GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF334155),
              )
            : GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF334155),
              ),
      ),
    );
  }

  List<MapEntry<ReceiptAddon, int>> _groupAddons(List<ReceiptAddon> addons) {
    final grouped = <String, MapEntry<ReceiptAddon, int>>{};
    for (final a in addons) {
      final key = '${a.nameAr}_${a.price}';
      if (grouped.containsKey(key)) {
        grouped[key] = MapEntry(a, grouped[key]!.value + 1);
      } else {
        grouped[key] = MapEntry(a, 1);
      }
    }
    return grouped.values.toList();
  }

  String _formatQty(double qty) {
    if (qty % 1 == 0) {
      return qty.toStringAsFixed(0);
    }
    return qty.toStringAsFixed(2);
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 12,
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.bold,
            ),
          ),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, double value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: isBold ? 14 : 12.5,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
            ),
          ),
          Text(
            '${value.toStringAsFixed(2)} ${ApiConstants.currency}',
            style: GoogleFonts.inter(
              fontSize: isBold ? 16 : 13,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
