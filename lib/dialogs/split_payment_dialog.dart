import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/api/api_constants.dart';
import '../services/language_service.dart';

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
    _remainingAmount = widget.total;
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
      _selectedPayments.removeAt(index);
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
      _remainingAmount = (widget.total - totalPaid);
      // Fix floating point precision issues
      if (_remainingAmount.abs() < 0.001) _remainingAmount = 0;
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
    final maxAllowed = widget.total - sumOthers;
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
        final lastRemaining = (widget.total - sumExceptLast).clamp(0.0, widget.total);
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 900;
    final dialogDirection =
        translationService.isRTL ? TextDirection.rtl : TextDirection.ltr;
    final insetPadding = EdgeInsets.symmetric(
      horizontal: isCompact ? 10 : 24,
      vertical: isCompact ? 12 : 24,
    );
    final dialogWidth = isCompact
        ? (size.width - insetPadding.horizontal).clamp(280.0, 560.0).toDouble()
        : 1000.0;
    final dialogHeight = isCompact
        ? (size.height - insetPadding.vertical).clamp(520.0, 900.0).toDouble()
        : 700.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: insetPadding,
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: Colors.white,
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _t('split_payment'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon:
                                const Icon(LucideIcons.x, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      color: const Color(0xFFF59E0B),
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: Column(
                        children: [
                          _SummaryItem(
                            label: _t('grand_total'),
                            value: widget.total.toStringAsFixed(2),
                          ),
                          const SizedBox(height: 8),
                          _SummaryItem(
                            label: _t('paid_amount'),
                            value: (widget.total - _remainingAmount)
                                .toStringAsFixed(2),
                          ),
                          const SizedBox(height: 8),
                          _SummaryItem(
                            label: _t('remaining_amount'),
                            value: _remainingAmount.toStringAsFixed(2),
                            valueColor: _remainingAmount > 0
                                ? Colors.yellow
                                : Colors.white,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: const Color(0xFFF8FAFC),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t('select_payment_methods'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 90,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _availableMethods.length,
                                itemBuilder: (context, index) {
                                  final method = _availableMethods[index];
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: InkWell(
                                      onTap: () => _addPaymentMethod(method),
                                      child: Container(
                                        width: 100,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: const Color(0xFFE2E8F0)),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(method['icon'],
                                                color: method['color'],
                                                size: 24),
                                            const SizedBox(height: 6),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6),
                                              child: Text(
                                                method['label'],
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
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
                            const SizedBox(height: 14),
                            Text(
                              _t('distributed_amounts'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: ListView.builder(
                                itemCount: _selectedPayments.length,
                                itemBuilder: (context, index) {
                                  final payment = _selectedPayments[index];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFE2E8F0),
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
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                payment['name'],
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () =>
                                                  _removePaymentMethod(index),
                                              icon: const Icon(
                                                LucideIcons.trash2,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                        TextField(
                                          controller: payment['controller'],
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                          decoration: InputDecoration(
                                            suffixText: ApiConstants.currency,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                          ),
                                          onChanged: (value) =>
                                              _onAmountChanged(index),
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
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(12),
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
                              minimumSize: const Size.fromHeight(48),
                              backgroundColor: const Color(0xFFF59E0B),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _t('confirm_payment'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                            ),
                            child: Text(translationService.t('cancel')),
                          ),
                        ],
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
                                backgroundColor: Colors.white,
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
                        color: const Color(0xFFF8FAFC),
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
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: const Color(0xFFE2E8F0)),
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
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: const Color(0xFFE2E8F0)),
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
                                          child: TextField(
                                            controller: payment['controller'],
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(
                                              suffixText: ApiConstants.currency,
                                              border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8)),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8),
                                            ),
                                            onChanged: (value) =>
                                                _calculateRemaining(),
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

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _SummaryItem(
      {required this.label,
      required this.value,
      this.valueColor = Colors.white});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 16)),
        Text('$value ${ApiConstants.currency}',
            style: TextStyle(
                color: valueColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace')),
      ],
    );
  }
}
