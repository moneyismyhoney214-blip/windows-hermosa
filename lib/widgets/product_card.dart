import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models.dart';
import '../services/api/api_constants.dart';
import '../services/app_themes.dart';

class ProductCard extends StatefulWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onQuickAdd;
  final Function(Product)? onLongPress;
  final bool isDisabled;
  final double taxRate;
  final String? placeholderImageUrl;
  /// When true, [product.price] is already VAT-inclusive (e.g. salon
  /// services), so the card must not multiply by `(1 + taxRate)` again.
  final bool priceIsTaxInclusive;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onQuickAdd,
    this.onLongPress,
    this.isDisabled = false,
    this.taxRate = 0.0,
    this.placeholderImageUrl,
    this.priceIsTaxInclusive = false,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  Timer? _longPressTimer;
  bool _isPressed = false;
  late String _formattedPrice;

  @override
  void initState() {
    super.initState();
    _formattedPrice = _computePrice();
  }

  @override
  void didUpdateWidget(covariant ProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.price != widget.product.price ||
        oldWidget.taxRate != widget.taxRate ||
        oldWidget.priceIsTaxInclusive != widget.priceIsTaxInclusive) {
      _formattedPrice = _computePrice();
    }
  }

  String _computePrice() {
    final multiplier = widget.priceIsTaxInclusive ? 1.0 : (1 + widget.taxRate);
    return '${(widget.product.price * multiplier).toStringAsFixed(ApiConstants.digitsNumber)} ${ApiConstants.currency}';
  }

  Widget _buildProductImage() {
    final productImg = widget.product.image;
    final hasProductImg = productImg != null && productImg.isNotEmpty;
    if (hasProductImg) {
      return CachedNetworkImage(
        imageUrl: productImg,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: 300,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (context, url) => _fallbackImage(),
        errorWidget: (context, url, error) => _fallbackImage(),
      );
    }
    return _fallbackImage();
  }

  Widget _fallbackImage() {
    final logo = widget.placeholderImageUrl;
    if (logo != null && logo.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: logo,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: 300,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, __) => _emptyIcon(),
        errorWidget: (_, __, ___) => _emptyIcon(),
      );
    }
    return _emptyIcon();
  }

  /// Empty-image placeholder. Salon services rarely carry a per-service
  /// image, and the original 32px grey glyph rendered as a near-invisible
  /// smudge. Salon mode shows a clearly visible scissors badge in the
  /// salon brand palette — warm orange (#F58220) on a cream disc — which
  /// reads well in both men's and women's salons (vs. the gender-coded
  /// pink it had before). Restaurant mode keeps the neutral glyph.
  Widget _emptyIcon() {
    final isSalon = ApiConstants.branchModule == 'salons';
    if (isSalon) {
      return Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED), // cream — salon brand light
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFF58220), width: 1.5),
          ),
          child: const Icon(
            LucideIcons.scissors,
            size: 38,
            color: Color(0xFFF58220), // salon brand
          ),
        ),
      );
    }
    return const Center(
      child: Icon(LucideIcons.image, size: 32, color: Color(0xFFCBD5E1)),
    );
  }

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
    if (_isPressed) setState(() => _isPressed = false);
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPressStart: (_) => _startLongPress(),
        onLongPressEnd: (_) => _cancelLongPress(),
        onLongPressCancel: () => _cancelLongPress(),
        onPanDown: (_) => _startLongPress(),
        onPanCancel: () => _cancelLongPress(),
        onPanEnd: (_) => _cancelLongPress(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: widget.isDisabled
                ? (context.isDark ? const Color(0xFF2D1A1A) : const Color(0xFFFFF5F5))
                : context.appCardBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: context.isDark
                ? const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : const [
                    BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
            border: _isPressed
                ? Border.all(color: context.appPrimary, width: 2)
                : widget.isDisabled
                    ? Border.all(color: const Color(0xFFEF4444), width: 1.6)
                    : Border.all(color: context.appBorder, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Product Image
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: context.appSurfaceAlt,
                      ),
                      child: _buildProductImage(),
                    ),
                    if (widget.isDisabled)
                      Positioned(
                        top: 6,
                        right: 6,
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
                      )
                    else
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _formattedPrice,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Product Name
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 6),
                child: Text(
                  widget.product.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _isPressed ? context.appPrimary : context.appText,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// `_ExtraBadge` used to live here as a "has add-ons" pill shown over a
// product card. It was abandoned during a UI refresh and never wired
// back in — analyzer flagged it as unused_element. Removed to keep the
// file honest. Restore the previous source from git history if a future
// design re-introduces the badge.
