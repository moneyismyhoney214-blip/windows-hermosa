import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models.dart';
import '../services/api/api_constants.dart';

class ProductCard extends StatefulWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onQuickAdd;
  final Function(Product)? onLongPress;
  final bool isDisabled;
  final double taxRate;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onQuickAdd,
    this.onLongPress,
    this.isDisabled = false,
    this.taxRate = 0.0,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  Timer? _longPressTimer;
  bool _isPressed = false;

  void _startLongPress() {
    setState(() => _isPressed = true);
    _longPressTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _isPressed) {
        if (widget.onLongPress != null) {
          widget.onLongPress!(widget.product);
        }
      }
    });
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    setState(() => _isPressed = false);
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: widget.isDisabled ? const Color(0xFFFFF5F5) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: _isPressed
            ? Border.all(color: const Color(0xFFF58220), width: 2)
            : widget.isDisabled
                ? Border.all(color: const Color(0xFFEF4444), width: 1.6)
                : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPressStart: (_) => _startLongPress(),
          onLongPressEnd: (_) => _cancelLongPress(),
          onLongPressCancel: () => _cancelLongPress(),
          onPanDown: (_) => _startLongPress(),
          onPanCancel: () => _cancelLongPress(),
          onPanEnd: (_) => _cancelLongPress(),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product Image
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: _isPressed
                              ? Border.all(
                                  color: const Color(0xFFF58220)
                                      .withValues(alpha: 0.3),
                                  width: 2,
                                )
                              : null,
                        ),
                        child: widget.product.image != null &&
                                widget.product.image!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                  widget.product.image!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(LucideIcons.image,
                                          size: 32, color: Color(0xFFCBD5E1)),
                                ),
                              )
                            : const Icon(LucideIcons.image,
                                size: 32, color: Color(0xFFCBD5E1)),
                      ),
                      if (widget.isDisabled)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'نفذت الوجبة',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final hasExtras = widget.product.extras.isNotEmpty;
                    final isNarrowHeader = constraints.maxWidth < 130;

                    final extraBadge = Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.plusCircle,
                            size: 12,
                            color: Color(0xFFD97706),
                          ),
                          SizedBox(width: 2),
                          Text(
                            'إضافات',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ],
                      ),
                    );

                    final titleText = Text(
                      widget.product.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _isPressed
                            ? const Color(0xFFF58220)
                            : const Color(0xFF1E293B),
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    );

                    if (hasExtras && isNarrowHeader) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          titleText,
                          const SizedBox(height: 4),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: extraBadge,
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: titleText),
                        if (hasExtras) ...[
                          const SizedBox(width: 4),
                          extraBadge,
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 120;

                    final priceChip = Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          '${(widget.product.price * (1 + widget.taxRate)).toStringAsFixed(2)} ${ApiConstants.currency}',
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF58220),
                          ),
                        ),
                      ),
                    );

                    final addButton = Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: widget.onQuickAdd ?? widget.onTap,
                        borderRadius: BorderRadius.circular(16),
                        child: Ink(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: widget.isDisabled
                                ? const Color(0xFFB91C1C)
                                : _isPressed
                                    ? const Color(0xFF9A3412)
                                    : const Color(0xFFF58220),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFF58220)
                                    .withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            LucideIcons.plus,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    );

                    if (isCompact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          priceChip,
                          const SizedBox(height: 6),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: addButton,
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: priceChip),
                        const SizedBox(width: 6),
                        addButton,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
