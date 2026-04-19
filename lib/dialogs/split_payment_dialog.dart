import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/api/api_constants.dart';
import '../services/language_service.dart';
import '../services/app_themes.dart';
import '../widgets/amount_num_pad_sheet.dart';

class SplitPaymentDialog extends StatefulWidget {
  final double total;
  final Map<String, bool> enabledMethods;

  const SplitPaymentDialog({
    super.key,
    required this.total,
    required this.enabledMethods,
  });

  @override
  State<SplitPaymentDialog> createState() => _SplitPaymentDialogState();
}

class _SplitPaymentDialogState extends State<SplitPaymentDialog> {
  final List<Map<String, dynamic>> _selectedPayments = [];
  double _remainingAmount = 0;

  // Use the same 2-decimal rounding as every displayed amount. widget.total
  // can carry sub-halala precision from raw tax math (e.g. 14.50 * 1.15 =
  // 16.675). Each text field is rounded to 2 decimals, so comparing their
  // sum against the raw total leaves a ±0.005 drift that keeps the "pay"
  // button grayed even when the user has fully allocated the bill.
  double get _total => double.parse(widget.total.toStringAsFixed(2));

  String _t(String key, {Map<String, dynamic>? args}) {
    return translationService.t(key, args: args);
  }

  List<Map<String, dynamic>> get _allPossibleMethods => [
        {
          'id': 'cash',
          'label': _t('cash'),
          'icon': LucideIcons.banknote,
          'color': Colors.green,
          'bg': Colors.green[50]
        },
        {
          'id': 'card',
          'label': _t('card'),
          'icon': LucideIcons.creditCard,
          'color': Colors.orange,
          'bg': Colors.orange[50]
        },
        {
          'id': 'mada',
          'label': _t('mada'),
          'icon': LucideIcons.creditCard,
          'color': Colors.orange,
          'bg': Colors.orange[50]
        },
        {
          'id': 'visa',
          'label': _t('visa_master'),
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
          'label': _t('bank_transfer'),
          'icon': LucideIcons.send,
          'color': Colors.orange,
          'bg': Colors.orange[50]
        },
        {
          'id': 'wallet',
          'label': _t('wallet'),
          'icon': LucideIcons.wallet,
          'color': Colors.teal,
          'bg': Colors.teal[50]
        },
      {
        'id': 'cheque',
        'label': _t('cheque'),
        'icon': LucideIcons.fileCheck,
        'color': Colors.brown,
        'bg': Colors.brown[50]
      },
      {
        'id': 'petty_cash',
        'label': _t('petty_cash'),
        'icon': LucideIcons.banknote,
        'color': Colors.teal,
        'bg': Colors.teal[50]
      },
      {
        'id': 'pay_later',
        'label': _t('pay_later'),
        'icon': LucideIcons.clock,
        'color': Colors.indigo,
        'bg': Colors.indigo[50]
      },
      {
        'id': 'tabby',
        'label': _t('tabby'),
        'icon': LucideIcons.creditCard,
        'color': Colors.blueGrey,
        'bg': Colors.blueGrey[50]
      },
      {
        'id': 'tamara',
        'label': _t('tamara'),
        'icon': LucideIcons.creditCard,
        'color': Colors.deepPurple,
        'bg': Colors.deepPurple[50]
      },
      {
        'id': 'keeta',
        'label': _t('keeta'),
        'icon': LucideIcons.truck,
        'color': Colors.orange,
        'bg': Colors.orange[50]
      },
      {
        'id': 'my_fatoorah',
        'label': _t('my_fatoorah'),
        'icon': LucideIcons.wallet,
        'color': Colors.cyan,
        'bg': Colors.cyan[50]
      },
      {
        'id': 'jahez',
        'label': _t('jahez'),
        'icon': LucideIcons.truck,
        'color': Colors.green,
        'bg': Colors.green[50]
      },
      {
        'id': 'talabat',
        'label': _t('talabat'),
        'icon': LucideIcons.shoppingBag,
        'color': Colors.red,
        'bg': Colors.red[50]
      },
    ];

  List<Map<String, dynamic>> get _availableMethods {
    return _allPossibleMethods.where((m) {
      final id = m['id'] as String;
      return widget.enabledMethods[id] == true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _remainingAmount = _total;
  }

  @override
  void dispose() {
    for (final p in _selectedPayments) {
      final c = p['controller'];
      if (c is TextEditingController) c.dispose();
    }
    _selectedPayments.clear();
    super.dispose();
  }

  void _addPaymentMethod(Map<String, dynamic> method) {
    if (_remainingAmount <= 0) return;

    final remaining = _remainingAmount;
    setState(() {
      _selectedPayments.add({
        'name': method['label'],
        'pay_method': method['id'],
        'amount': remaining,
        'icon': method['icon'],
        'color': method['color'],
        'controller':
            TextEditingController(text: remaining.toStringAsFixed(2)),
      });
      _calculateRemaining();
    });
  }

  void _removePaymentMethod(int index) {
    setState(() {
      final removed = _selectedPayments.removeAt(index);
      final c = removed['controller'];
      if (c is TextEditingController) c.dispose();
      _calculateRemaining();
      // Auto-fill remaining into last method
      _autoFillLastMethod();
    });
  }

  void _calculateRemaining() {
    double totalPaid = 0;
    for (var payment in _selectedPayments) {
      final amount = double.tryParse(payment['controller'].text) ?? 0;
      totalPaid += amount;
    }
    setState(() {
      _remainingAmount = (_total - totalPaid);
      // Tolerate up to 1 halala (0.01 SAR) of rounding drift so a fully
      // allocated split enables the "pay" button even when the raw total
      // carries sub-halala precision.
      if (_remainingAmount.abs() < 0.01) _remainingAmount = 0;
    });
  }

  /// When user changes amount in any field, clamp it and auto-fill the last method
  void _onAmountChanged(int changedIndex) {
    // Clamp: don't allow value > total or negative
    final controller = _selectedPayments[changedIndex]['controller'] as TextEditingController;
    var entered = double.tryParse(controller.text) ?? 0;
    if (entered < 0) {
      entered = 0;
      controller.text = '0';
      controller.selection = TextSelection.fromPosition(
          TextPosition(offset: controller.text.length));
    }

    // Sum all OTHER methods (excluding current)
    double sumOthers = 0;
    for (var i = 0; i < _selectedPayments.length; i++) {
      if (i == changedIndex) continue;
      sumOthers +=
          double.tryParse(_selectedPayments[i]['controller'].text) ?? 0;
    }

    // Max allowed for this field = total - sum of others
    final maxAllowed = _total - sumOthers;
    if (entered > maxAllowed) {
      entered = maxAllowed < 0 ? 0 : maxAllowed;
      controller.text = entered.toStringAsFixed(2);
      controller.selection = TextSelection.fromPosition(
          TextPosition(offset: controller.text.length));
    }

    // Auto-fill last method if editing a non-last field
    if (_selectedPayments.length >= 2) {
      final lastIndex = _selectedPayments.length - 1;
      if (changedIndex != lastIndex) {
        double sumExceptLast = 0;
        for (var i = 0; i < lastIndex; i++) {
          sumExceptLast +=
              double.tryParse(_selectedPayments[i]['controller'].text) ?? 0;
        }
        final lastRemaining = (_total - sumExceptLast).clamp(0.0, _total);
        _selectedPayments[lastIndex]['controller'].text =
            lastRemaining.toStringAsFixed(2);
        _selectedPayments[lastIndex]['amount'] = lastRemaining;
      }
    }

    _calculateRemaining();
  }

  void _autoFillLastMethod() {
    if (_selectedPayments.isEmpty) return;
    if (_remainingAmount <= 0) return;
    final last = _selectedPayments.last;
    final currentAmount = double.tryParse(last['controller'].text) ?? 0;
    final newAmount = currentAmount + _remainingAmount;
    last['controller'].text = newAmount.toStringAsFixed(2);
    last['amount'] = newAmount;
    _calculateRemaining();
  }

  // Maximum this row is allowed to hold: the total minus whatever the other
  // rows already sum to. Prevents the keypad confirm from over-allocating.
  double _maxForRow(int index) {
    double sumOthers = 0;
    for (var i = 0; i < _selectedPayments.length; i++) {
      if (i == index) continue;
      sumOthers +=
          double.tryParse(_selectedPayments[i]['controller'].text) ?? 0;
    }
    final max = _total - sumOthers;
    return max < 0 ? 0 : max;
  }

  Future<void> _editAmount(int index) async {
    final payment = _selectedPayments[index];
    final controller = payment['controller'] as TextEditingController;
    final current = double.tryParse(controller.text) ?? 0;
    final result = await AmountNumPadSheet.show(
      context,
      initial: current,
      max: _maxForRow(index),
      title: payment['name']?.toString(),
    );
    if (!mounted || result == null) return;
    controller.text = result.toStringAsFixed(2);
    payment['amount'] = result;
    _onAmountChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final isCompact = size.width < 900;
    final isPhone = isCompact && size.width < 600;
    // Very short viewports (e.g. landscape phones, or portrait phones while
    // the numeric keypad is open) need tighter spacing — otherwise the
    // summary banner alone eats the space that should belong to the methods.
    final isShortViewport =
        (size.height - viewInsets.bottom) < 560;
    final dialogDirection =
        translationService.isRTL ? TextDirection.rtl : TextDirection.ltr;
    // When the keyboard is open, shrink the dialog's bottom inset so the
    // dialog doesn't try to reserve space beneath the keyboard. This lets
    // the scrollable body actually fit the visible viewport.
    final insetPadding = EdgeInsets.fromLTRB(
      isCompact ? (isPhone ? 8 : 10) : 24,
      isCompact ? (isShortViewport ? 8 : 12) : 24,
      isCompact ? (isPhone ? 8 : 10) : 24,
      (isCompact ? (isShortViewport ? 8 : 12) : 24) + viewInsets.bottom,
    );
    final dialogWidth = isCompact
        ? (size.width - insetPadding.horizontal).clamp(280.0, 560.0).toDouble()
        : 1000.0;
    // Available height = viewport – inset – keyboard. Clamp to a small-enough
    // minimum so we never pick a height larger than what's actually visible.
    final availableHeight =
        (size.height - insetPadding.vertical).clamp(320.0, 900.0).toDouble();
    final dialogHeight = isCompact ? availableHeight : 700.0;

    // Phone-tuned sizes for the method tiles and summary banner.
    final methodTileWidth = isPhone ? 84.0 : 100.0;
    final methodTileHeight = isShortViewport
        ? 68.0
        : (isPhone ? 78.0 : 90.0);
    final methodIconSize = isPhone ? 22.0 : 24.0;
    final methodFontSize = isPhone ? 11.5 : 12.0;
    final summaryGap = isShortViewport ? 4.0 : 8.0;
    final summaryHPad = isPhone ? 12.0 : 14.0;
    final summaryVPad = isShortViewport ? 8.0 : 12.0;
    final bodyPad = isPhone ? 12.0 : 14.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: insetPadding,
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: context.appCardBg,
          borderRadius: BorderRadius.circular(isCompact ? 18 : 24),
        ),
        clipBehavior: Clip.antiAlias,
        child: Directionality(
          textDirection: dialogDirection,
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      color: const Color(0xFFF59E0B),
                      padding: EdgeInsets.symmetric(
                          horizontal: summaryHPad,
                          vertical: isShortViewport ? 8 : 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _t('split_payment'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isShortViewport ? 18 : 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints:
                                const BoxConstraints(minWidth: 36, minHeight: 36),
                            onPressed: () => Navigator.pop(context),
                            icon:
                                const Icon(LucideIcons.x, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      color: const Color(0xFFF59E0B),
                      padding: EdgeInsets.fromLTRB(
                          summaryHPad, 0, summaryHPad, summaryVPad),
                      child: Column(
                        children: [
                          _SummaryItem(
                            label: _t('grand_total'),
                            value: widget.total.toStringAsFixed(2),
                            compact: isShortViewport,
                          ),
                          SizedBox(height: summaryGap),
                          _SummaryItem(
                            label: _t('paid_amount'),
                            value: (widget.total - _remainingAmount)
                                .toStringAsFixed(2),
                            compact: isShortViewport,
                          ),
                          SizedBox(height: summaryGap),
                          _SummaryItem(
                            label: _t('remaining_amount'),
                            value: _remainingAmount.toStringAsFixed(2),
                            valueColor: _remainingAmount > 0
                                ? Colors.yellow
                                : Colors.white,
                            compact: isShortViewport,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: context.appBg,
                        padding: EdgeInsets.fromLTRB(
                            bodyPad, bodyPad, bodyPad, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t('select_payment_methods'),
                              style: TextStyle(
                                fontSize: isPhone ? 15 : 18,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF334155),
                              ),
                            ),
                            SizedBox(height: isPhone ? 8 : 12),
                            SizedBox(
                              height: methodTileHeight,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _availableMethods.length,
                                itemBuilder: (context, index) {
                                  final method = _availableMethods[index];
                                  return Padding(
                                    padding: EdgeInsetsDirectional.only(
                                        end: isPhone ? 6 : 8),
                                    child: InkWell(
                                      onTap: () => _addPaymentMethod(method),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        width: methodTileWidth,
                                        decoration: BoxDecoration(
                                          color: context.appCardBg,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: context.appBorder),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(method['icon'],
                                                color: method['color'],
                                                size: methodIconSize),
                                            SizedBox(
                                                height: isShortViewport ? 2 : 6),
                                            Padding(
                                              padding: EdgeInsets.symmetric(
                                                  horizontal:
                                                      isPhone ? 4 : 6),
                                              child: Text(
                                                method['label'],
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: methodFontSize,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            SizedBox(height: isPhone ? 10 : 14),
                            Text(
                              _t('distributed_amounts'),
                              style: TextStyle(
                                fontSize: isPhone ? 14 : 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF334155),
                              ),
                            ),
                            SizedBox(height: isPhone ? 6 : 10),
                            Expanded(
                              child: _selectedPayments.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 24),
                                        child: Text(
                                          _t('select_payment_methods'),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: const Color(0xFF94A3B8),
                                            fontSize: isPhone ? 12 : 13,
                                          ),
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      itemCount: _selectedPayments.length,
                                      itemBuilder: (context, index) {
                                        final payment =
                                            _selectedPayments[index];
                                        return Container(
                                          margin: EdgeInsets.only(
                                              bottom: isPhone ? 8 : 10),
                                          padding: EdgeInsets.all(
                                              isPhone ? 10 : 12),
                                          decoration: BoxDecoration(
                                            color: context.appCardBg,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: context.appBorder,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    payment['icon'],
                                                    color: payment['color'],
                                                    size: isPhone ? 20 : 24,
                                                  ),
                                                  SizedBox(
                                                      width: isPhone ? 8 : 10),
                                                  Expanded(
                                                    child: Text(
                                                      payment['name'],
                                                      maxLines: 1,
                                                      overflow: TextOverflow
                                                          .ellipsis,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize:
                                                            isPhone ? 13 : 14,
                                                      ),
                                                    ),
                                                  ),
                                                  IconButton(
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    padding: EdgeInsets.zero,
                                                    constraints:
                                                        const BoxConstraints(
                                                            minWidth: 32,
                                                            minHeight: 32),
                                                    onPressed: () =>
                                                        _removePaymentMethod(
                                                            index),
                                                    icon: const Icon(
                                                      LucideIcons.trash2,
                                                      color: Colors.red,
                                                      size: 20,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              _AmountField(
                                                controller:
                                                    payment['controller'],
                                                onTap: () =>
                                                    _editAmount(index),
                                                compact: isPhone,
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Container(
                        color: Colors.white,
                        padding: EdgeInsets.fromLTRB(
                          bodyPad,
                          isShortViewport ? 6 : 10,
                          bodyPad,
                          isShortViewport ? 6 : 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ElevatedButton(
                              onPressed: _remainingAmount == 0 &&
                                      _selectedPayments.isNotEmpty
                                  ? () {
                                      final pays = _selectedPayments
                                          .asMap()
                                          .entries
                                          .map((entry) {
                                        final index = entry.key;
                                        final val = entry.value;
                                        return {
                                          'name': val['name'],
                                          'pay_method': val['pay_method'],
                                          'amount': double.tryParse(
                                                  val['controller'].text) ??
                                              0,
                                          'index': index,
                                        };
                                      }).toList();
                                      Navigator.pop(context, pays);
                                    }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                minimumSize: Size.fromHeight(
                                    isShortViewport ? 42 : 48),
                                backgroundColor: const Color(0xFFF59E0B),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _t('confirm_payment'),
                                style: TextStyle(
                                  fontSize: isShortViewport ? 14 : 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            SizedBox(height: isShortViewport ? 4 : 8),
                            OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size.fromHeight(
                                    isShortViewport ? 38 : 44),
                              ),
                              child: Text(translationService.t('cancel')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Side: Payment Summary & Confirmation (similar to Tender Dialog)
                    Container(
                      width: 350,
                      color: const Color(0xFFF59E0B),
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Text(
                            _t('split_payment'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 24),
                          const Divider(color: Colors.white30),
                          const SizedBox(height: 24),
                          _SummaryItem(
                              label: _t('grand_total'),
                              value: widget.total.toStringAsFixed(2)),
                          const SizedBox(height: 16),
                          _SummaryItem(
                            label: _t('paid_amount'),
                            value: (widget.total - _remainingAmount)
                                .toStringAsFixed(2),
                          ),
                          const SizedBox(height: 16),
                          _SummaryItem(
                            label: _t('remaining_amount'),
                            value: _remainingAmount.toStringAsFixed(2),
                            valueColor: _remainingAmount > 0
                                ? Colors.yellow
                                : Colors.white,
                          ),
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            height: 64,
                            child: ElevatedButton(
                              onPressed: _remainingAmount == 0 &&
                                      _selectedPayments.isNotEmpty
                                  ? () {
                                      final pays = _selectedPayments
                                          .asMap()
                                          .entries
                                          .map((entry) {
                                        final index = entry.key;
                                        final val = entry.value;
                                        return {
                                          'name': val['name'],
                                          'pay_method': val['pay_method'],
                                          'amount': double.tryParse(
                                                  val['controller'].text) ??
                                              0,
                                          'index': index,
                                        };
                                      }).toList();
                                      Navigator.pop(context, pays);
                                    }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: context.appCardBg,
                                disabledBackgroundColor: Colors.grey[300],
                                foregroundColor: const Color(0xFFC2410C),
                                disabledForegroundColor: Colors.grey[600],
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                              child: Text(
                                _t('confirm_payment'),
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(translationService.t('cancel'),
                                style: const TextStyle(color: Colors.white70)),
                          )
                        ],
                      ),
                    ),

                    // Right Side: Selection and Inputs
                    Expanded(
                      child: Container(
                        color: context.appBg,
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _t('select_payment_methods'),
                                  style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF334155)),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(LucideIcons.x,
                                      size: 28, color: Colors.grey),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // Available Methods Horizontal List
                            SizedBox(
                              height: 100,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _availableMethods.length,
                                itemBuilder: (context, index) {
                                  final method = _availableMethods[index];
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: InkWell(
                                      onTap: () => _addPaymentMethod(method),
                                      child: Container(
                                        width: 120,
                                        decoration: BoxDecoration(
                                          color: context.appCardBg,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: context.appBorder),
                                          boxShadow: [
                                            BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.05),
                                                blurRadius: 4)
                                          ],
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(method['icon'],
                                                color: method['color'],
                                                size: 28),
                                            const SizedBox(height: 8),
                                            Text(method['label'],
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),

                            const SizedBox(height: 32),
                            Text(
                              _t('distributed_amounts'),
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF334155)),
                            ),
                            const SizedBox(height: 16),

                            // Selected Payments List
                            Expanded(
                              child: ListView.builder(
                                itemCount: _selectedPayments.length,
                                itemBuilder: (context, index) {
                                  final payment = _selectedPayments[index];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: context.appCardBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: context.appBorder),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(payment['icon'],
                                            color: payment['color']),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            payment['name'],
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          flex: 3,
                                          child: _AmountField(
                                            controller: payment['controller'],
                                            onTap: () => _editAmount(index),
                                            compact: false,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        IconButton(
                                          onPressed: () =>
                                              _removePaymentMethod(index),
                                          icon: const Icon(LucideIcons.trash2,
                                              color: Colors.red),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// Read-only field that mirrors the look of a bordered TextField but opens
// the in-app numeric keypad on tap instead of the system keyboard. Listens
// to the controller so typed values remain visible after the keypad closes.
class _AmountField extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onTap;
  final bool compact;

  const _AmountField({
    required this.controller,
    required this.onTap,
    required this.compact,
  });

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant _AmountField old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text =
        widget.controller.text.trim().isEmpty ? '0.00' : widget.controller.text;
    final isPlaceholder = widget.controller.text.trim().isEmpty;
    final vPad = widget.compact ? 8.0 : 12.0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding:
              EdgeInsets.symmetric(horizontal: 12, vertical: vPad),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFCBD5E1)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.keyboard,
                size: widget.compact ? 16 : 18,
                color: const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: widget.compact ? 15 : 16,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: isPlaceholder
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                ApiConstants.currency,
                style: TextStyle(
                  fontSize: widget.compact ? 12 : 13,
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool compact;
  const _SummaryItem(
      {required this.label,
      required this.value,
      this.valueColor = Colors.white,
      this.compact = false});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white70,
              fontSize: compact ? 13 : 16,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$value ${ApiConstants.currency}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor,
            fontSize: compact ? 15 : 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
