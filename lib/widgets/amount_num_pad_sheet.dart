import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api/api_constants.dart';
import '../services/language_service.dart';

/// In-app numeric keypad for SAR amount entry.
///
/// We don't rely on the system numeric keyboard because on phones it pushes
/// its own UI up and squeezes the hosting dialog — especially the split
/// payment dialog where the text field can end up off-screen.
///
/// Usage:
/// ```dart
/// final result = await AmountNumPadSheet.show(
///   context,
///   initial: 12.50,
///   max: 100.00,
/// );
/// if (result != null) controller.text = result.toStringAsFixed(2);
/// ```
class AmountNumPadSheet extends StatefulWidget {
  final double initial;
  final double? max;
  final String? title;

  const AmountNumPadSheet({
    super.key,
    required this.initial,
    this.max,
    this.title,
  });

  static Future<double?> show(
    BuildContext context, {
    required double initial,
    double? max,
    String? title,
  }) {
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => AmountNumPadSheet(
        initial: initial,
        max: max,
        title: title,
      ),
    );
  }

  @override
  State<AmountNumPadSheet> createState() => _AmountNumPadSheetState();
}

class _AmountNumPadSheetState extends State<AmountNumPadSheet> {
  late String _buffer;

  String get _title =>
      widget.title ?? translationService.t('amount');

  @override
  void initState() {
    super.initState();
    _buffer = widget.initial > 0 ? widget.initial.toStringAsFixed(2) : '0';
  }

  double get _currentValue => double.tryParse(_buffer) ?? 0;
  bool get _isWithinMax =>
      widget.max == null || _currentValue <= widget.max! + 0.001;
  bool get _canConfirm => _currentValue > 0 && _isWithinMax;

  void _appendDigit(String d) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_buffer == '0') {
        _buffer = d;
      } else {
        // Respect 2-decimal cap.
        if (_buffer.contains('.')) {
          final decimals = _buffer.split('.').last;
          if (decimals.length >= 2) return;
        }
        _buffer = '$_buffer$d';
      }
    });
  }

  void _appendDot() {
    HapticFeedback.selectionClick();
    if (_buffer.contains('.')) return;
    setState(() {
      _buffer = '$_buffer.';
    });
  }

  void _backspace() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_buffer.length <= 1) {
        _buffer = '0';
      } else {
        _buffer = _buffer.substring(0, _buffer.length - 1);
        if (_buffer.endsWith('.')) {
          _buffer = _buffer.substring(0, _buffer.length - 1);
        }
      }
    });
  }

  void _clear() {
    HapticFeedback.selectionClick();
    setState(() => _buffer = '0');
  }

  void _fillMax() {
    final max = widget.max;
    if (max == null) return;
    HapticFeedback.selectionClick();
    setState(() => _buffer = max.toStringAsFixed(2));
  }

  void _confirm() {
    if (!_canConfirm) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(_currentValue);
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = translationService.isRTL;
    final media = MediaQuery.of(context);
    final availableHeight = media.size.height - media.viewPadding.top;
    // Scale the keypad height to the available viewport so the amount
    // preview and the Cancel/Confirm row always stay on screen.
    final maxSheetHeight = (availableHeight * 0.72).clamp(380.0, 640.0);

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHandle(),
            _buildHeader(),
            _buildAmountDisplay(),
            if (widget.max != null) _buildMaxHint(),
            const SizedBox(height: 4),
            Expanded(child: _buildKeypad()),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFFCBD5E1),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.pop(context),
            icon: const Icon(LucideIcons.x, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountDisplay() {
    final valid = _isWithinMax;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: valid ? const Color(0xFFFBBF24) : Colors.red,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Text(
              ApiConstants.currency,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF92400E),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  _buffer,
                  maxLines: 1,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color:
                        valid ? const Color(0xFF92400E) : Colors.red.shade700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaxHint() {
    final max = widget.max!;
    final isRtl = translationService.isRTL;
    final maxLabel = isRtl ? 'الحد الأقصى' : 'Max';
    final fillLabel = isRtl ? 'املأ المتبقي' : 'Fill remaining';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              '$maxLabel: '
              '${max.toStringAsFixed(2)} ${ApiConstants.currency}',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
              ),
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _fillMax,
            icon: const Icon(LucideIcons.check, size: 14),
            label: Text(fillLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildKeypad() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          _buildKeyRow(['1', '2', '3']),
          _buildKeyRow(['4', '5', '6']),
          _buildKeyRow(['7', '8', '9']),
          _buildKeyRow(['.', '0', 'back']),
        ],
      ),
    );
  }

  Widget _buildKeyRow(List<String> keys) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: keys.map((k) => Expanded(child: _buildKey(k))).toList(),
        ),
      ),
    );
  }

  Widget _buildKey(String key) {
    if (key == 'back') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: _KeyTile(
          onTap: _backspace,
          onLongPress: _clear,
          child: const Icon(
            LucideIcons.delete,
            color: Color(0xFF475569),
            size: 24,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: _KeyTile(
        onTap: () => key == '.' ? _appendDot() : _appendDigit(key),
        child: Text(
          key,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: const Color(0xFF64748B),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(translationService.t('cancel')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _canConfirm ? _confirm : null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE2E8F0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(LucideIcons.check, size: 20),
              label: Text(
                translationService.t('confirm'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyTile extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  const _KeyTile({
    required this.onTap,
    required this.child,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Center(child: child),
      ),
    );
  }
}
