import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models.dart';
import '../services/api/api_constants.dart';
import '../services/language_service.dart';
import 'split_payment_dialog.dart';
import '../services/app_themes.dart';

class PaymentTenderDialog extends StatefulWidget {
  final double total;
  final double taxRate;
  final Function(List<Map<String, dynamic>> pays)? onConfirmWithPays;
  final VoidCallback onConfirm;
  final ValueChanged<String>? onNoteChanged;
  final Map<String, bool> enabledMethods;
  final List<PromoCode> promocodes;
  final PromoCode? appliedPromoCode;
  final ValueChanged<PromoCode?>? onPromoCodeChanged;

  const PaymentTenderDialog({
    super.key,
    required this.total,
    this.taxRate = 0.15,
    required this.onConfirm,
    this.onConfirmWithPays,
    this.enabledMethods = const {
      'cash': false,
      'card': false,
      'mada': false,
      'visa': false,
      'benefit': false,
      'stc': false,
      'bank_transfer': false,
      'wallet': false,
      'cheque': false,
      'petty_cash': false,
      'pay_later': false,
      'tabby': false,
      'tamara': false,
      'keeta': false,
      'my_fatoorah': false,
      'jahez': false,
      'talabat': false,
      'hunger_station': false,
    },
    this.onNoteChanged,
    this.promocodes = const [],
    this.appliedPromoCode,
    this.onPromoCodeChanged,
  });

  @override
  State<PaymentTenderDialog> createState() => _PaymentTenderDialogState();
}

class _PaymentTenderDialogState extends State<PaymentTenderDialog> {
  String? _selectedMethod;
  PromoCode? _localPromo;
  final TextEditingController _noteController = TextEditingController();

  bool get _useArabicUi {
    final code = translationService.currentLanguageCode.trim().toLowerCase();
    return code.startsWith('ar') || code.startsWith('ur');
  }

  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  Future<void> _handleSplitPayment() async {
    final List<Map<String, dynamic>>? result =
        await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) => SplitPaymentDialog(
        total: widget.total,
        enabledMethods: widget.enabledMethods,
      ),
    );

    if (result != null && result.isNotEmpty) {
      // تطبيق الكوبون على الـ parent عند تأكيد الدفع فقط
      if (_localPromo?.id != widget.appliedPromoCode?.id) {
        widget.onPromoCodeChanged?.call(_localPromo);
      }
      _pushNote();
      if (widget.onConfirmWithPays != null) {
        widget.onConfirmWithPays!(result);
      } else {
        widget.onConfirm();
      }
    }
  }

  List<Map<String, dynamic>> get _allPossibleMethods => [
        {
          'id': 'cash',
          'label': translationService.t('cash'),
          'icon': LucideIcons.banknote,
          'color': Colors.green,
          'bg': Colors.green[50]
        },
        {
          'id': 'card',
          'label': translationService.t('card'),
          'icon': LucideIcons.creditCard,
          'color': Colors.orange,
          'bg': Colors.orange[50]
        },
        {
          'id': 'mada',
          'label': _tr('مدى', 'Mada'),
          'icon': LucideIcons.creditCard,
          'color': Colors.orange,
          'bg': Colors.orange[50]
        },
        {
          'id': 'visa',
          'label': _tr('فيزا / ماستر', 'Visa / Master'),
          'icon': LucideIcons.wallet,
          'color': Colors.blue,
          'bg': Colors.blue[50]
        },
        {
          'id': 'stc',
          'label': 'STC Pay',
          'icon': LucideIcons.smartphone,
          'color': Colors.purple,
          'bg': Colors.purple[50]
        },
        {
          'id': 'benefit',
          'label': 'Benefit',
          'icon': LucideIcons.smartphone,
          'color': Colors.red,
          'bg': Colors.red[50]
        },
        {
          'id': 'bank_transfer',
          'label': _tr('تحويل بنكي', 'Bank Transfer'),
          'icon': LucideIcons.send,
          'color': Colors.orange,
          'bg': Colors.orange[50]
        },
        {
          'id': 'wallet',
          'label': _tr('المحفظة', 'Wallet'),
          'icon': LucideIcons.wallet,
          'color': Colors.teal,
          'bg': Colors.teal[50]
        },
        {
          'id': 'cheque',
          'label': _tr('شيك', 'Cheque'),
          'icon': LucideIcons.fileCheck,
          'color': Colors.brown,
          'bg': Colors.brown[50]
        },
        {
          'id': 'petty_cash',
          'label': _tr('بيتي كاش', 'Petty Cash'),
          'icon': LucideIcons.banknote,
          'color': Colors.teal,
          'bg': Colors.teal[50]
        },
        {
          'id': 'pay_later',
          'label': _tr('الدفع بالآجل', 'Pay Later'),
          'icon': LucideIcons.clock,
          'color': Colors.indigo,
          'bg': Colors.indigo[50]
        },
        {
          'id': 'tabby',
          'label': _tr('تابي', 'Tabby'),
          'icon': LucideIcons.creditCard,
          'color': Colors.blueGrey,
          'bg': Colors.blueGrey[50]
        },
        {
          'id': 'tamara',
          'label': _tr('تمارا', 'Tamara'),
          'icon': LucideIcons.creditCard,
          'color': Colors.deepPurple,
          'bg': Colors.deepPurple[50]
        },
        {
          'id': 'keeta',
          'label': _tr('كيتا', 'Keeta'),
          'icon': LucideIcons.truck,
          'color': Colors.orange,
          'bg': Colors.orange[50]
        },
        {
          'id': 'my_fatoorah',
          'label': _tr('ماي فاتورة', 'My Fatoorah'),
          'icon': LucideIcons.wallet,
          'color': Colors.cyan,
          'bg': Colors.cyan[50]
        },
        {
          'id': 'jahez',
          'label': _tr('جاهز', 'Jahez'),
          'icon': LucideIcons.truck,
          'color': Colors.green,
          'bg': Colors.green[50]
        },
        {
          'id': 'talabat',
          'label': _tr('طلبات', 'Talabat'),
          'icon': LucideIcons.shoppingBag,
          'color': Colors.red,
          'bg': Colors.red[50]
        },
        {
          'id': 'hunger_station',
          'label': _tr('هنقر ستيشن', 'Hunger Station'),
          'icon': LucideIcons.truck,
          'color': Colors.deepOrange,
          'bg': Colors.deepOrange[50]
        },
      ];

  Map<String, dynamic> get _splitMethod => <String, dynamic>{
        'id': 'split',
        'label': translationService.t('split_payment'),
        'icon': LucideIcons.layers,
        'color': Colors.indigo,
      };

  List<Map<String, dynamic>> get _methods {
    final enabledBaseMethods = _allPossibleMethods.where((m) {
      final id = m['id'] as String;
      return widget.enabledMethods[id] == true;
    }).toList();

    // Show split only when there are at least two enabled methods.
    if (enabledBaseMethods.length > 1) {
      return [...enabledBaseMethods, _splitMethod];
    }
    return enabledBaseMethods;
  }

  Map<String, dynamic>? _methodById(String? id) {
    if (id == null) return null;
    for (final method in _methods) {
      if (method['id'] == id) return method;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _localPromo = widget.appliedPromoCode;
  }

  void _pushNote() {
    final note = _noteController.text.trim();
    if (note.isNotEmpty) {
      widget.onNoteChanged?.call(note);
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _confirmSelectedMethod() {
    if (_selectedMethod == null) return;
    if (_selectedMethod == 'split') {
      _handleSplitPayment();
      return;
    }
    final method = _methodById(_selectedMethod);
    if (method == null) return;
    // تطبيق الكوبون على الـ parent عند تأكيد الدفع فقط
    if (_localPromo?.id != widget.appliedPromoCode?.id) {
      widget.onPromoCodeChanged?.call(_localPromo);
    }
    _pushNote();
    if (widget.onConfirmWithPays != null) {
      widget.onConfirmWithPays!([
        {
          'name': method['label'],
          'pay_method': method['id'],
          'amount': widget.total,
          'index': 0,
        }
      ]);
      return;
    }
    widget.onConfirm();
  }

  Widget _buildSummarySection({
    required double subtotal,
    required double tax,
    required bool isCompact,
  }) {
    return _SectionCard(
      title: _tr('ملخص الفاتورة', 'Invoice Summary'),
      icon: LucideIcons.receipt,
      compact: isCompact,
      expandChild: !isCompact,
      child: Column(
        children: [
          _SummaryLine(
            label: translationService.t('amount'),
            value: subtotal.toStringAsFixed(2),
            compact: isCompact,
          ),
          _SummaryLine(
            label: translationService.t('tax'),
            value: tax.toStringAsFixed(2),
            compact: isCompact,
          ),
          _SummaryLine(
            label: translationService.t('discount'),
            value: '0.00',
            compact: isCompact,
          ),
          _SummaryLine(
            label: translationService.t('total'),
            value: widget.total.toStringAsFixed(2),
            strong: true,
            compact: isCompact,
          ),
          const Divider(height: 20),
          _SummaryLine(
            label: translationService.t('remaining_amount'),
            value: widget.total.toStringAsFixed(2),
            strong: true,
            valueColor: const Color(0xFFF58220),
            compact: isCompact,
          ),
        ],
      ),
    );
  }

  Widget _buildMethodsSection({
    required bool isCompact,
    required Map<String, dynamic>? selectedMethod,
  }) {
    final methodsGrid = _methods.isEmpty
        ? Center(
            child: Text(
              _tr(
                'لا توجد طرق دفع مفعّلة لهذا الفرع',
                'No payment methods are enabled for this branch',
              ),
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          )
        : GridView.builder(
            shrinkWrap: isCompact,
            physics: isCompact
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isCompact ? 2 : 3,
              childAspectRatio: isCompact ? 1.2 : 1.3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _methods.length,
            itemBuilder: (context, index) {
              final method = _methods[index];
              final methodId = method['id'] as String;
              final isSelected = _selectedMethod == methodId;
              return InkWell(
                onTap: () {
                  if (methodId == 'split') {
                    _handleSplitPayment();
                  } else {
                    setState(() => _selectedMethod = methodId);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (context.isDark
                            ? context.appPrimary.withValues(alpha: 0.15)
                            : const Color(0xFFFFF7ED))
                        : context.appCardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? context.appPrimary : context.appBorder,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        method['icon'],
                        color: isSelected ? context.appPrimary : method['color'],
                        size: isCompact ? 22 : 26,
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          method['label'],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isCompact ? 12 : 14,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? context.appPrimary
                                : (context.isDark ? Colors.white : context.appText),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );

    return _SectionCard(
      title: _tr('طرق الدفع', 'Payment Methods'),
      icon: LucideIcons.wallet,
      compact: isCompact,
      expandChild: !isCompact,
      child: Column(
        children: [
          if (isCompact) methodsGrid else Expanded(child: methodsGrid),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 16,
              vertical: isCompact ? 10 : 12,
            ),
            decoration: BoxDecoration(
              color: context.appBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.appBorder),
            ),
            child: isCompact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        selectedMethod?['label']?.toString() ??
                            _tr(
                              'لم يتم اختيار طريقة دفع',
                              'No payment method selected',
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${widget.total.toStringAsFixed(2)} ${ApiConstants.currency}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedMethod?['label']?.toString() ??
                              _tr(
                                'لم يتم اختيار طريقة دفع',
                                'No payment method selected',
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.total.toStringAsFixed(2)} ${ApiConstants.currency}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoCodeButton() {
    final hasPromo = _localPromo != null;
    final promo = _localPromo;
    String label;
    if (hasPromo) {
      final discountText = promo!.type == DiscountType.percentage
          ? '${promo.discount.toStringAsFixed(0)}%'
          : '${promo.discount.toStringAsFixed(2)} ${ApiConstants.currency}';
      label = '${promo.code} ($discountText)';
    } else {
      label = _tr('اختر كوبون', 'Select Coupon');
    }

    return InkWell(
      onTap: () async {
        final selected = await showDialog<PromoCode?>(
          context: context,
          builder: (ctx) => _PaymentPromoDialog(
            promocodes: widget.promocodes,
            activePromoId: _localPromo?.id,
          ),
        );
        if (selected != null) {
          setState(() => _localPromo = selected);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: hasPromo
              ? context.appPrimary.withValues(alpha: 0.1)
              : context.appCardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasPromo ? context.appPrimary : context.appBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasPromo ? LucideIcons.badgePercent : LucideIcons.ticket,
              size: 18,
              color: hasPromo ? context.appPrimary : context.appTextMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: hasPromo ? FontWeight.w600 : FontWeight.normal,
                  color: hasPromo
                      ? const Color(0xFFF58220)
                      : const Color(0xFF94A3B8),
                ),
              ),
            ),
            if (hasPromo)
              GestureDetector(
                onTap: () => setState(() => _localPromo = null),
                child: const Icon(LucideIcons.x, size: 16, color: Color(0xFFF58220)),
              )
            else
              const Icon(LucideIcons.chevronDown, size: 16, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  Widget _buildExtrasSection({required bool isCompact}) {
    return _SectionCard(
      title: _tr('خيارات إضافية', 'Extra Options'),
      icon: LucideIcons.ticket,
      compact: isCompact,
      expandChild: !isCompact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPromoCodeButton(),
          const SizedBox(height: 14),
          Text(
            _tr('ملاحظات الطلب', 'Order Notes'),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          if (isCompact)
            TextField(
              controller: _noteController,
              minLines: 3,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: _tr('أدخل ملاحظات الطلب...', 'Enter order notes...'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                alignLabelWithHint: true,
              ),
            )
          else
            Expanded(
              child: TextField(
                controller: _noteController,
                maxLines: null,
                expands: true,
                decoration: InputDecoration(
                  hintText:
                      _tr('أدخل ملاحظات الطلب...', 'Enter order notes...'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignLabelWithHint: true,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBar({
    required bool isCompact,
    required bool isUltraCompact,
  }) {
    return Container(
      padding: EdgeInsets.all(isCompact ? (isUltraCompact ? 8 : 12) : 20),
      decoration: BoxDecoration(
        color: context.appCardBg,
        border: Border(top: BorderSide(color: context.appBorder)),
      ),
      child: isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  onPressed:
                      _selectedMethod != null ? _confirmSelectedMethod : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size.fromHeight(isUltraCompact ? 42 : 48),
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _selectedMethod == null
                        ? translationService.t('select_payment_method')
                        : translationService.t('pay'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(height: isUltraCompact ? 6 : 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size.fromHeight(isUltraCompact ? 40 : 44),
                    foregroundColor: const Color(0xFF64748B),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  child: Text(translationService.t('cancel')),
                ),
              ],
            )
          : Row(
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(120, 48),
                    foregroundColor: const Color(0xFF64748B),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  child: Text(translationService.t('cancel')),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed:
                      _selectedMethod != null ? _confirmSelectedMethod : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(220, 52),
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _selectedMethod == null
                        ? translationService.t('select_payment_method')
                        : translationService.t('pay'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeTaxRate = widget.taxRate.clamp(0.0, 1.0);
    final subtotal =
        safeTaxRate > 0 ? widget.total / (1.0 + safeTaxRate) : widget.total;
    final tax = widget.total - subtotal;
    final selectedMethod = _methodById(_selectedMethod);
    final dialogDirection =
        translationService.isRTL ? TextDirection.rtl : TextDirection.ltr;
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 900;
    final isUltraCompact = isCompact && size.height < 720;
    final insetPadding = EdgeInsets.symmetric(
      horizontal: isCompact ? 10 : 24,
      vertical: isCompact ? (isUltraCompact ? 6 : 12) : 24,
    );
    final availableHeight = (size.height - insetPadding.vertical).toDouble();
    final dialogWidth = isCompact
        ? (size.width - insetPadding.horizontal).clamp(280.0, 560.0).toDouble()
        : 1320.0;
    final dialogHeight = isCompact
        ? availableHeight
        : (availableHeight < 760 ? availableHeight : 760.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: insetPadding,
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: context.appBg,
          borderRadius: BorderRadius.circular(isCompact ? 18 : 24),
          border: Border.all(color: context.appBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Directionality(
          textDirection: dialogDirection,
          child: Column(
            children: [
              Container(
                height: isCompact ? (isUltraCompact ? 52 : 64) : 72,
                padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 24),
                color: const Color(0xFFF59E0B),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(LucideIcons.x, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        translationService.t('payment'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isCompact ? (isUltraCompact ? 22 : 26) : 34,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(isCompact ? 12 : 20),
                  child: isCompact
                      ? ListView(
                          children: [
                            _buildSummarySection(
                              subtotal: subtotal,
                              tax: tax,
                              isCompact: true,
                            ),
                            const SizedBox(height: 12),
                            _buildMethodsSection(
                              isCompact: true,
                              selectedMethod: selectedMethod,
                            ),
                            const SizedBox(height: 12),
                            _buildExtrasSection(isCompact: true),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildSummarySection(
                                subtotal: subtotal,
                                tax: tax,
                                isCompact: false,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: _buildMethodsSection(
                                isCompact: false,
                                selectedMethod: selectedMethod,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildExtrasSection(isCompact: false),
                            ),
                          ],
                        ),
                ),
              ),
              _buildActionBar(
                isCompact: isCompact,
                isUltraCompact: isUltraCompact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final bool compact;
  final bool expandChild;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.compact = false,
    this.expandChild = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        mainAxisSize: expandChild ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 20 : 26,
                    fontWeight: FontWeight.w800,
                    color: context.isDark ? Colors.white : const Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
          Divider(
            height: compact ? 16 : 22,
            color: context.appBorder,
          ),
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  final Color? valueColor;
  final bool compact;

  const _SummaryLine({
    required this.label,
    required this.value,
    this.strong = false,
    this.valueColor,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = !compact && constraints.maxWidth < 280;
        final strongValueSize = compact ? 20.0 : (isNarrow ? 24.0 : 30.0);
        final normalValueSize = compact ? 16.0 : (isNarrow ? 20.0 : 24.0);

        return Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.isDark ? Colors.white : context.appTextMuted,
                  fontSize: strong ? (compact ? 14 : 18) : (compact ? 13 : 16),
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    '$value ${ApiConstants.currency}',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: valueColor ?? (context.isDark ? Colors.white : const Color(0xFF0F172A)),
                      fontSize: strong ? strongValueSize : normalValueSize,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Promo Code Dialog for Payment Screen
// ---------------------------------------------------------------------------
class _PaymentPromoDialog extends StatefulWidget {
  final List<PromoCode> promocodes;
  final String? activePromoId;

  const _PaymentPromoDialog({
    required this.promocodes,
    this.activePromoId,
  });

  @override
  State<_PaymentPromoDialog> createState() => _PaymentPromoDialogState();
}

class _PaymentPromoDialogState extends State<_PaymentPromoDialog> {
  final _searchController = TextEditingController();
  List<PromoCode> _filtered = [];

  bool get _useArabicUi {
    final code = translationService.currentLanguageCode.trim().toLowerCase();
    return code.startsWith('ar') || code.startsWith('ur');
  }

  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  @override
  void initState() {
    super.initState();
    _filtered = widget.promocodes;
    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = widget.promocodes;
      } else {
        _filtered = widget.promocodes
            .where((p) => p.code.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Directionality(
        textDirection: _useArabicUi ? TextDirection.rtl : TextDirection.ltr,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
                decoration: const BoxDecoration(
                  color: Color(0xFFF58220),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.badgePercent, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _tr('الكوبونات', 'Promo Codes'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, color: Colors.white, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Search
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: _tr('ابحث عن كوبون...', 'Search coupon...'),
                    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(LucideIcons.search, size: 16, color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
              ),

              // List
              Flexible(
                child: _filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _tr('لا توجد كوبونات', 'No coupons found'),
                            style: const TextStyle(color: Color(0xFF94A3B8)),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final promo = _filtered[index];
                          final isApplied = widget.activePromoId == promo.id;
                          final discountText = promo.type == DiscountType.percentage
                              ? '${promo.discount.toStringAsFixed(0)}%'
                              : '${promo.discount.toStringAsFixed(2)} ${ApiConstants.currency}';

                          return InkWell(
                            onTap: () => Navigator.pop(context, promo),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isApplied
                                    ? (context.isDark
                                        ? context.appPrimary.withValues(alpha: 0.15)
                                        : const Color(0xFFFFF7ED))
                                    : context.appCardBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isApplied
                                      ? context.appPrimary
                                      : context.appBorder,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF58220).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      discountText,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFF58220),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      promo.code,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                  ),
                                  if (isApplied)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF22C55E),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _tr('مطبّق', 'Applied'),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
