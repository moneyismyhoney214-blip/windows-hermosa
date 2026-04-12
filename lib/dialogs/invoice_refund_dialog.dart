import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/api/api_constants.dart';
import '../services/api/device_service.dart';
import '../services/api/order_service.dart';
import '../services/invoice_html_pdf_service.dart';
import '../services/print_audit_service.dart';
import '../services/printer_role_registry.dart';
import '../services/zatca_printer_service.dart';
import '../models.dart';
import '../locator.dart';

enum _RefundMode { full, partial }

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
  @override
  bool operator ==(Object other) => other is _RefundCandidate && other.id == id && other.type == type;
  @override
  int get hashCode => Object.hash(id, type);
}

Future<bool> showInvoiceRefundDialog({
  required BuildContext context,
  required String invoiceId,
  required String invoiceLabel,
  bool startPartial = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => InvoiceRefundDialog(
      invoiceId: invoiceId,
      invoiceLabel: invoiceLabel,
      startPartial: startPartial,
    ),
  );
  return result == true;
}

class InvoiceRefundDialog extends StatefulWidget {
  final String invoiceId;
  final String invoiceLabel;
  final bool startPartial;

  const InvoiceRefundDialog({
    super.key,
    required this.invoiceId,
    required this.invoiceLabel,
    this.startPartial = false,
  });

  @override
  State<InvoiceRefundDialog> createState() => _InvoiceRefundDialogState();
}

class _InvoiceRefundDialogState extends State<InvoiceRefundDialog>
    with SingleTickerProviderStateMixin {
  final OrderService _orderService = getIt<OrderService>();

  bool _isLoading = true;
  bool _isProcessing = false;
  String? _error;

  List<_RefundCandidate> _candidates = [];

  _RefundMode _mode = _RefundMode.full;
  final Set<_RefundCandidate> _selectedItems = {};
  double _refundAmount = 0;
  bool _allItemsRefunded = false;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  static const _kAccent = Color(0xFFEF4444);
  static const _kAccentLight = Color(0xFFFEF2F2);
  static const _kBorder = Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    _mode = widget.startPartial ? _RefundMode.partial : _RefundMode.full;
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadData();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      Map<String, dynamic> invoiceDetails;
      try {
        invoiceDetails = await _orderService.getInvoice(widget.invoiceId);
      } catch (_) {
        invoiceDetails = await _orderService.getInvoiceHelper(widget.invoiceId);
      }
      final refundPreview = await _orderService.showInvoiceRefund(widget.invoiceId);

      if (!mounted) return;

      final payload = _asMap(invoiceDetails['data']) ?? invoiceDetails;
      final data = _asMap(payload['invoice']) ?? payload;
      final previewPayload = _asMap(refundPreview['data']) ?? _asMap(refundPreview) ?? {};
      final previewInvoice = _asMap(previewPayload['invoice']) ??
          _asMap(previewPayload['data']) ??
          previewPayload;

      var amount = _parsePrice(
        previewInvoice['refund_total'] ??
            previewInvoice['refund_amount'] ??
            previewInvoice['amount'] ??
            previewPayload['refund_total'] ??
            previewPayload['refund_amount'] ??
            previewPayload['amount'],
      );

      final candidates = _extractCandidates(data, payload, previewPayload);

      // If no direct refund amount field, sum up from candidates
      if (amount == 0 && candidates.isNotEmpty) {
        amount = candidates.fold(0.0, (sum, c) => sum + c.total);
      }
      // Fallback to invoice total if still 0
      if (amount == 0) {
        amount = _parsePrice(
          previewInvoice['total'] ??
              previewPayload['total'] ??
              data['grand_total'] ??
              data['total'] ??
              payload['grand_total'] ??
              payload['total'],
        );
      }

      final allRefunded = candidates.isEmpty && amount == 0;

      setState(() {
        _candidates = candidates;
        _refundAmount = amount;
        _allItemsRefunded = allRefunded;
        _isLoading = false;
      });
      _fadeCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _confirm() async {
    if (_isProcessing) return;
    if (_mode == _RefundMode.partial && _selectedItems.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final refundPayload = <String, dynamic>{
        'refund_reason': 'طلب العميل',
      };

      // Determine which items to refund
      final Iterable<_RefundCandidate> itemsToRefund;
      if (_mode == _RefundMode.partial) {
        itemsToRefund = _selectedItems;
      } else {
        // Full refund: send all candidate IDs explicitly
        itemsToRefund = _candidates;
      }

      final mealIds = itemsToRefund
          .where((c) => c.type == _RefundCandidateType.meal || c.type == _RefundCandidateType.unknown)
          .map((c) => c.id)
          .toList();
      final productIds = itemsToRefund
          .where((c) => c.type == _RefundCandidateType.product)
          .map((c) => c.id)
          .toList();
      if (mealIds.isNotEmpty) refundPayload['refund_meals'] = mealIds;
      if (productIds.isNotEmpty) refundPayload['refund_products'] = productIds;

      final result = await _orderService.processInvoiceRefund(
        invoiceId: widget.invoiceId,
        payload: refundPayload,
      );

      if (!mounted) return;
      final msg = result['message']?.toString().trim();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          (msg != null && msg.isNotEmpty) ? msg : 'تم تنفيذ الاسترجاع بنجاح',
        ),
        backgroundColor: const Color(0xFF10B981),
      ));

      // Print credit note (فاتورة دائن) with refunded items
      _printCreditNote(itemsToRefund.toList());

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تنفيذ الاسترجاع: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width * 0.9).clamp(300.0, 520.0).toDouble();
    final maxHeight = size.height * 0.88;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              Flexible(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(LucideIcons.refreshCw, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'استرجاع فاتورة',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.invoiceLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _isProcessing ? null : () => Navigator.pop(context),
            icon: const Icon(LucideIcons.x, color: Colors.white, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildLoading();
    if (_error != null) return _buildError();
    if (_allItemsRefunded) return FadeTransition(opacity: _fadeAnim, child: _buildAllRefunded());
    return FadeTransition(opacity: _fadeAnim, child: _buildForm());
  }

  Widget _buildLoading() {
    return SizedBox(
      height: 180,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: _kAccent,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'جاري تحميل بيانات الاسترجاع...',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.alertCircle, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 12),
          const Text(
            'تعذر تحميل البيانات',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              setState(() { _isLoading = true; _error = null; });
              _loadData();
            },
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('إعادة المحاولة'),
            style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildModeToggle(),
          if (_mode == _RefundMode.partial) ...[
            const SizedBox(height: 16),
            _buildItemsList(),
          ],
          const SizedBox(height: 20),
          _buildAmountRow(),
          const SizedBox(height: 20),
          _buildActions(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _modeTab(_RefundMode.full, LucideIcons.fileX, 'استرجاع كامل'),
          _modeTab(_RefundMode.partial, LucideIcons.checkSquare, 'استرجاع عناصر'),
        ],
      ),
    );
  }

  Widget _modeTab(_RefundMode mode, IconData icon, String label) {
    final isSelected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 6, offset: const Offset(0, 2))]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: isSelected ? _kAccent : Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? _kAccent : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildItemsList() {
    if (_candidates.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.alertTriangle, size: 18, color: Color(0xFFD97706)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'تم استرجاع جميع العناصر مسبقاً',
                style: TextStyle(fontSize: 13, color: Color(0xFF92400E)),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'اختر العناصر المراد استرجاعها',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF374151)),
            ),
            const Spacer(),
            if (_candidates.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  if (_selectedItems.length == _candidates.length) {
                    _selectedItems.clear();
                  } else {
                    _selectedItems.addAll(_candidates);
                  }
                }),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _selectedItems.length == _candidates.length ? 'إلغاء الكل' : 'تحديد الكل',
                  style: const TextStyle(fontSize: 12, color: _kAccent),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ..._candidates.map((c) => _buildCandidateRow(c)),
      ],
    );
  }

  Widget _buildCandidateRow(_RefundCandidate candidate) {
    final isSelected = _selectedItems.contains(candidate);
    return GestureDetector(
      onTap: () => setState(() {
        if (isSelected) {
          _selectedItems.remove(candidate);
        } else {
          _selectedItems.add(candidate);
        }
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _kAccentLight : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFFFCA5A5) : _kBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isSelected ? _kAccent : Colors.white,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: isSelected ? _kAccent : Colors.grey.shade400,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidate.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                  ),
                  if (candidate.quantity > 0 || candidate.total > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      _buildCandidateSubtitle(candidate),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ],
              ),
            ),
            if (candidate.total > 0)
              Text(
                '${candidate.total.toStringAsFixed(2)} ${ApiConstants.currency}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? _kAccent : const Color(0xFF374151),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountRow() {
    final double displayAmount = _mode == _RefundMode.partial
        ? _selectedItems.fold(0.0, (sum, c) => sum + c.total)
        : _refundAmount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF334155)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'المبلغ المتوقع للاسترجاع',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.65)),
              ),
              const SizedBox(height: 4),
              Text(
                '${displayAmount.toStringAsFixed(2)} ${ApiConstants.currency}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.dollarSign, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final canConfirm = !_isProcessing &&
        (_mode == _RefundMode.full || _selectedItems.isNotEmpty);

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: canConfirm ? _confirm : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade200,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text(
                    'تأكيد الاسترجاع',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: TextButton(
            onPressed: _isProcessing ? null : () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('إلغاء', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildAllRefunded() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF86EFAC), width: 2),
            ),
            child: const Icon(LucideIcons.checkCircle, size: 36, color: Color(0xFF16A34A)),
          ),
          const SizedBox(height: 16),
          const Text(
            'تم استرجاع جميع العناصر',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'لا توجد عناصر متبقية قابلة للاسترجاع في هذه الفاتورة.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('إغلاق', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── helpers ───────────────────────────────────────────────────────────────

  String _buildCandidateSubtitle(_RefundCandidate c) {
    final parts = <String>[];
    if (c.quantity > 0) parts.add('الكمية: ${c.quantity}');
    if (c.total > 0) parts.add('${c.total.toStringAsFixed(2)} ${ApiConstants.currency}');
    return parts.join(' • ');
  }

  double _parsePrice(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) {
      var s = v.replaceAll(',', '').trim();
      final cur = ApiConstants.currency.trim();
      if (cur.isNotEmpty) s = s.replaceAll(cur, '');
      s = s.replaceAll('SAR', '').replaceAll('QAR', '').replaceAll('RS', '').replaceAll('ر.س', '').replaceAll(RegExp(r'[^\d.\-]'), '');
      return double.tryParse(s) ?? 0.0;
    }
    return 0.0;
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return null;
  }

  Future<void> _printCreditNote(List<_RefundCandidate> refundedItems) async {
    try {
      final invoiceHtmlPdfService = getIt<InvoiceHtmlPdfService>();
      final refundTotal = refundedItems.fold(0.0, (sum, c) => sum + c.total);

      final itemMaps = refundedItems.map((c) => <String, dynamic>{
        'name': c.name,
        'quantity': c.quantity,
        'total': c.total,
        'unit_price': c.quantity > 0 ? c.total / c.quantity : c.total,
      }).toList();

      final pdfPath = await invoiceHtmlPdfService.generateCreditNotePdf(
        widget.invoiceId,
        refundedItems: itemMaps,
        refundTotal: refundTotal,
      );

      final pdfFile = File(pdfPath);
      if (!await pdfFile.exists()) return;
      final pdfBytes = await pdfFile.readAsBytes();

      final devices = await getIt<DeviceService>().getDevices();
      final printers = devices.where((d) {
        final type = d.type.trim().toLowerCase();
        return type == 'printer' && !d.id.startsWith('kitchen:');
      }).toList();

      if (printers.isEmpty) return;

      final registry = getIt<PrinterRoleRegistry>();
      await registry.initialize();

      // Prefer cashier receipt printers, fallback to any physical printer
      var targetPrinters = printers
          .where((p) => registry.resolveRole(p) == PrinterRole.cashierReceipt)
          .toList();
      if (targetPrinters.isEmpty) {
        targetPrinters = printers
            .where((p) {
              final role = registry.resolveRole(p);
              return role != PrinterRole.kitchen &&
                  role != PrinterRole.kds &&
                  role != PrinterRole.bar;
            })
            .toList();
      }
      if (targetPrinters.isEmpty) targetPrinters = printers;

      for (final printer in targetPrinters) {
        try {
          await ZatcaPrinterService().printPdfBytes(printer, pdfBytes);
          printAuditService.logAttempt(
            printerIp: printer.connectionType == PrinterConnectionType.bluetooth
                ? (printer.bluetoothAddress ?? 'BT')
                : printer.ip,
            jobType: 'credit_note',
            success: true,
          );
        } catch (e) {
          printAuditService.logAttempt(
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

  List<_RefundCandidate> _extractCandidates(
    Map<String, dynamic> data,
    Map<String, dynamic> payload,
    Map<String, dynamic> previewPayload,
  ) {
    final seen = <String>{};
    final results = <_RefundCandidate>[];

    void add({
      required _RefundCandidateType type,
      required int id,
      required String name,
      required double total,
      required int qty,
    }) {
      if (id <= 0) return;
      final key = '${type.name}:$id';
      if (seen.contains(key)) return;
      seen.add(key);
      results.add(_RefundCandidate(id: id, type: type, name: name, total: total, quantity: qty));
    }

    void addFromList(dynamic src, {required _RefundCandidateType type, required List<String> idKeys}) {
      if (src is! List) return;
      for (final item in src.whereType<Map>()) {
        final m = item.map((k, v) => MapEntry(k.toString(), v));
        int id = 0;
        for (final k in idKeys) {
          id = int.tryParse(m[k]?.toString() ?? '') ?? 0;
          if (id > 0) break;
        }
        if (id <= 0) continue;
        final name = m['name']?.toString() ?? m['meal_name']?.toString() ?? m['product_name']?.toString() ?? 'عنصر';
        final qty = int.tryParse(m['quantity']?.toString() ?? '1') ?? 1;
        final total = _parsePrice(m['total'] ?? m['amount'] ?? m['price']);
        add(type: type, id: id, name: name, total: total, qty: qty);
      }
    }

    addFromList(previewPayload['sales_meals'] ?? previewPayload['meals'], type: _RefundCandidateType.meal, idKeys: const ['sales_meal_id', 'meal_id', 'item_id']);
    addFromList(previewPayload['sales_products'] ?? previewPayload['products'], type: _RefundCandidateType.product, idKeys: const ['sales_product_id', 'product_id', 'item_id']);
    addFromList(data['items'] ?? data['meals'] ?? payload['items'] ?? payload['meals'], type: _RefundCandidateType.unknown, idKeys: const ['id', 'item_id', 'meal_id']);

    return results;
  }
}
