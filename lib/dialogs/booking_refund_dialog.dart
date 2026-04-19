import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models.dart';
import '../services/api/api_constants.dart';
import '../services/api/device_service.dart';
import '../services/api/order_service.dart';
import '../services/language_service.dart';
import '../services/print_orchestrator_service.dart';
import '../services/printer_language_settings_service.dart';
import '../services/printer_role_registry.dart';
import '../locator.dart';
import '../services/app_themes.dart';

class _RefundItem {
  final int id;
  final String name;
  final double price;
  final int quantity;
  const _RefundItem({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
  });
  @override
  bool operator ==(Object other) => other is _RefundItem && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// Returns the refunded pre-tax amount, or null if cancelled.
Future<double?> showBookingRefundDialog({
  required BuildContext context,
  required String bookingId,
  required String bookingLabel,
}) async {
  return showDialog<double>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BookingRefundDialog(
      bookingId: bookingId,
      bookingLabel: bookingLabel,
    ),
  );
}

class BookingRefundDialog extends StatefulWidget {
  final String bookingId;
  final String bookingLabel;

  const BookingRefundDialog({
    super.key,
    required this.bookingId,
    required this.bookingLabel,
  });

  @override
  State<BookingRefundDialog> createState() => _BookingRefundDialogState();
}

class _BookingRefundDialogState extends State<BookingRefundDialog>
    with SingleTickerProviderStateMixin {
  final OrderService _orderService = getIt<OrderService>();

  bool _isLoading = true;
  bool _isProcessing = false;
  String? _error;

  List<_RefundItem> _items = [];
  final Set<_RefundItem> _selectedItems = {};
  bool _allItemsRefunded = false;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  static const _kAccent = Color(0xFFEF4444);
  static const _kAccentLight = Color(0xFFFEF2F2);
  static const _kBorder = Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
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
      final response = await _orderService.showBookingRefund(widget.bookingId);
      if (!mounted) return;

      final data = response['data'];
      final collection = (data is Map ? data['collection'] : null) as List?;

      if (collection == null || collection.isEmpty) {
        setState(() {
          _items = [];
          _allItemsRefunded = true;
          _isLoading = false;
        });
        _fadeCtrl.forward();
        return;
      }

      final items = <_RefundItem>[];
      for (final item in collection) {
        if (item is! Map) continue;
        final m = item.map((k, v) => MapEntry(k.toString(), v));
        final id = int.tryParse(m['id']?.toString() ?? '') ?? 0;
        if (id <= 0) continue;
        items.add(_RefundItem(
          id: id,
          name: m['meal_name']?.toString() ?? m['name']?.toString() ?? 'عنصر',
          price: double.tryParse(m['price']?.toString() ?? '0') ?? 0.0,
          quantity: int.tryParse(m['quantity']?.toString() ?? '1') ?? 1,
        ));
      }

      setState(() {
        _items = items;
        _allItemsRefunded = items.isEmpty;
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
    if (_isProcessing || _selectedItems.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final refundIds = _selectedItems.map((item) => item.id).toList();
      // Snapshot BEFORE awaiting the API call so we can notify the kitchen
      // about the items that were actually refunded. `_selectedItems` is
      // mutable — don't pass it by reference into the fire-and-forget hook.
      final snapshot = List<_RefundItem>.from(_selectedItems);
      // Partial when at least one item survives post-refund; full when we
      // selected every remaining candidate. The kitchen ticket header
      // changes based on this flag (partial cancel vs full cancel).
      final isFullRefund =
          _items.isNotEmpty && snapshot.length >= _items.length;

      await _orderService.processBookingRefund(
        orderId: widget.bookingId,
        payload: {'refund': refundIds},
      );

      if (!mounted) return;
      final refundedPreTax =
          snapshot.fold(0.0, (sum, item) => sum + item.price);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(translationService.t('refund_success')),
        backgroundColor: Color(0xFF10B981),
      ));
      // Fire-and-forget kitchen notification — mirrors the invoice-refund
      // flow. Without this hook, refunds triggered from the Orders screen
      // silently skipped the kitchen, so cooks kept preparing items the
      // cashier had already voided.
      unawaited(_notifyKitchenOfRefund(snapshot, isFullRefund: isFullRefund));
      Navigator.pop(context, refundedPreTax);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(translationService.t('failed_execute_refund', args: {'error': e.toString()}))),
      );
    }
  }

  Future<void> _notifyKitchenOfRefund(
    List<_RefundItem> refundedItems, {
    required bool isFullRefund,
  }) async {
    if (refundedItems.isEmpty) return;
    try {
      final String lang = printerLanguageSettings.primary;
      final String langSecondary =
          printerLanguageSettings.allowSecondary &&
                  printerLanguageSettings.secondary != lang
              ? printerLanguageSettings.secondary
              : '';

      String pick(String code, String ar, String en,
          {String? es, String? tr, String? hi, String? ur}) {
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

      String tl(String ar, String en,
              {String? es, String? tr, String? hi, String? ur}) =>
          pick(lang, ar, en, es: es, tr: tr, hi: hi, ur: ur);
      String tlSec(String ar, String en,
          {String? es, String? tr, String? hi, String? ur}) {
        if (langSecondary.isEmpty) return '';
        return pick(langSecondary, ar, en, es: es, tr: tr, hi: hi, ur: ur);
      }

      // Collect every candidate printer — the orchestrator filters down to
      // Kitchen / KDS / Bar roles internally, so we pass the whole set and
      // let it do the last-mile validation (role + reachable transport).
      final devices = await getIt<DeviceService>().getDevices();
      final registry = getIt<PrinterRoleRegistry>();
      await registry.initialize();

      final kitchenPrinters = devices.where((d) {
        final type = d.type.trim().toLowerCase();
        if (type != 'printer') return false;
        final role = registry.resolveRole(d);
        if (role != PrinterRole.kitchen &&
            role != PrinterRole.kds &&
            role != PrinterRole.bar) {
          return false;
        }
        if (d.connectionType == PrinterConnectionType.bluetooth) {
          return (d.bluetoothAddress ?? '').trim().isNotEmpty;
        }
        return d.ip.trim().isNotEmpty;
      }).toList();
      if (kitchenPrinters.isEmpty) return;

      final items = refundedItems.map((it) {
        final primary = tl('ملغي', 'Cancelled',
            es: 'Cancelado', tr: 'İptal', hi: 'रद्द', ur: 'منسوخ');
        final secondary = tlSec('ملغي', 'Cancelled',
            es: 'Cancelado', tr: 'İptal', hi: 'रद्द', ur: 'منسوخ');
        return <String, dynamic>{
          'name': it.name,
          'nameAr': it.name,
          'quantity': it.quantity,
          'tag': 'Cancelled',
          // Keep `tagAr` for older renderers that haven't picked up the
          // primary/secondary rename; new renderers prefer `tagPrimary`.
          'tagAr': primary,
          'tagPrimary': primary,
          'tagSecondary': secondary,
          'cancelled': true,
          'tagColor': 'black',
        };
      }).toList();

      final orderTypeLabel = isFullRefund
          ? tl('إلغاء فاتورة', 'Invoice Cancelled',
              es: 'Factura Cancelada',
              tr: 'Fatura İptal',
              hi: 'इनवॉइस रद्द',
              ur: 'انوائس منسوخ')
          : tl('استرجاع جزئي', 'Partial Refund',
              es: 'Reembolso Parcial',
              tr: 'Kısmi İade',
              hi: 'आंशिक रिफंड',
              ur: 'جزوی واپسی');
      final noteLabel = isFullRefund
          ? tl('⛔ الطلب ملغي بالكامل', '⛔ Entire order cancelled',
              es: '⛔ Pedido cancelado',
              tr: '⛔ Sipariş tamamen iptal',
              hi: '⛔ पूरा ऑर्डर रद्द',
              ur: '⛔ پورا آرڈر منسوخ')
          : tl('⚠️ إلغاء جزئي', '⚠️ Partial cancellation',
              es: '⚠️ Cancelación parcial',
              tr: '⚠️ Kısmi iptal',
              hi: '⚠️ आंशिक रद्दीकरण',
              ur: '⚠️ جزوی منسوخی');

      await getIt<PrintOrchestratorService>().enqueueKitchenPrint(
        printers: kitchenPrinters,
        orderNumber: widget.bookingLabel,
        orderType: orderTypeLabel,
        items: items,
        note: noteLabel,
        isRtl: lang == 'ar' || lang == 'ur',
        primaryLang: lang,
        secondaryLang: langSecondary.isEmpty ? null : langSecondary,
        allowSecondary: langSecondary.isNotEmpty,
      );
    } catch (e) {
      debugPrint('⚠️ Failed to notify kitchen of booking refund: $e');
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
        color: context.appCardBg.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(LucideIcons.refreshCw,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'استرجاع طلب',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.bookingLabel,
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
    if (_allItemsRefunded) {
      return FadeTransition(opacity: _fadeAnim, child: _buildAllRefunded());
    }
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
            child: CircularProgressIndicator(strokeWidth: 3, color: _kAccent),
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
              setState(() {
                _isLoading = true;
                _error = null;
              });
              _loadData();
            },
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: Text(translationService.t('retry')),
            style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent, foregroundColor: Colors.white),
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
          _buildItemsList(),
          const SizedBox(height: 20),
          _buildAmountRow(),
          const SizedBox(height: 20),
          _buildActions(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'اختر العناصر المراد استرجاعها',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151)),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                if (_selectedItems.length == _items.length) {
                  _selectedItems.clear();
                } else {
                  _selectedItems.addAll(_items);
                }
              }),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _selectedItems.length == _items.length
                    ? 'إلغاء الكل'
                    : 'تحديد الكل',
                style: const TextStyle(fontSize: 12, color: _kAccent),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._items.map((item) => _buildItemRow(item)),
      ],
    );
  }

  Widget _buildItemRow(_RefundItem item) {
    final isSelected = _selectedItems.contains(item);
    return GestureDetector(
      onTap: () => setState(() {
        if (isSelected) {
          _selectedItems.remove(item);
        } else {
          _selectedItems.add(item);
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
                    item.name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'الكمية: ${item.quantity}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            if (item.price > 0)
              Text(
                '${item.price.toStringAsFixed(2)} ${ApiConstants.currency}',
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
    final displayAmount =
        _selectedItems.fold(0.0, (sum, item) => sum + item.price);

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
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.65)),
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
        color: context.appCardBg.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.dollarSign,
                color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final canConfirm = !_isProcessing && _selectedItems.isNotEmpty;

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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text(
                    'تأكيد الاسترجاع',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('إلغاء',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
            child: const Icon(LucideIcons.checkCircle,
                size: 36, color: Color(0xFF16A34A)),
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
            'لا توجد عناصر متبقية قابلة للاسترجاع في هذا الطلب.',
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('إغلاق',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
