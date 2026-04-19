import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models.dart';
import 'display_language_service.dart';

class CustomerFacingScreen extends StatelessWidget {
  const CustomerFacingScreen({
    super.key,
    required this.cart,
    this.orderNumber,
    this.languageCode = 'ar',
    this.currencySymbol = '',
    this.promoCode,
    this.discountAmount,
    this.originalTotal,
    this.discountedTotal,
    this.taxRate,
    this.subtotalAmount,
    this.taxAmount,
    this.totalAmount,
    this.isOrderFree = false,
    this.orderDiscountType,
    this.orderDiscountValue,
    this.orderDiscountPercent,
    this.discountSource,
    this.cashFloat,
    this.catalogProducts = const <Map<String, dynamic>>[],
    this.catalogCategories = const <String>[],
    this.disabledMealIds = const <String>{},
    required this.onToggleMealAvailability,
    this.onClose,
  });

  final List<CartItem> cart;
  final String? orderNumber;
  final String languageCode;
  final String currencySymbol;
  final String? promoCode;
  final double? discountAmount;
  final double? originalTotal;
  final double? discountedTotal;
  final double? taxRate;
  final double? subtotalAmount;
  final double? taxAmount;
  final double? totalAmount;
  final bool isOrderFree;
  final String? orderDiscountType;
  final double? orderDiscountValue;
  final double? orderDiscountPercent;
  final String? discountSource;
  final Map<String, dynamic>? cashFloat;
  final List<Map<String, dynamic>> catalogProducts;
  final List<String> catalogCategories;
  final Set<String> disabledMealIds;
  final void Function(Map<String, dynamic> product, bool isDisabled)
  onToggleMealAvailability;
  final VoidCallback? onClose;

  Widget _buildBrandMark({double size = 40}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5EB),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: const Color(0xFFF27D26).withValues(alpha: 0.3),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Image.asset(
          'assets/hermosa app ico.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = DisplayLanguageService.normalizeLanguageCode(languageCode);
    final isRtl = DisplayLanguageService.isRtl(lang);

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: Stack(
            children: [
              Positioned(
                top: -80,
                right: isRtl ? -80 : null,
                left: isRtl ? null : -80,
                child: Container(
                  width: 600,
                  height: 600,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF5EB).withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              SafeArea(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: cart.isEmpty
                      ? _buildWelcomeScreen(lang)
                      : _buildOrderScreen(context, lang),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeScreen(String lang) {
    return Center(
      key: const ValueKey('cds_welcome'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.shade100),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _buildBrandMark(size: 48),
          ),
          const SizedBox(height: 16),
          Text(
            'HERMOSA POS',
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              color: const Color(0xFF1B2538),
            ),
          ),
          const SizedBox(height: 48),
          const _AnimatedWelcomeWord(),
        ],
      ),
    );
  }

  Widget _buildOrderScreen(BuildContext context, String lang) {
    return LayoutBuilder(
      key: const ValueKey('cds_order'),
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;

        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Row(
                children: [
                  _buildBrandMark(size: 32),
                  const SizedBox(width: 12),
                  Text(
                    'HERMOSA POS',
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1B2538),
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Expanded(
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildCartPanel(
                              context,
                              lang,
                              compact: false,
                            ),
                          ),
                          const SizedBox(width: 32),
                          Expanded(flex: 2, child: _buildInfoPanel(lang)),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildInfoPanel(lang, compact: true),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: math.max(
                                420,
                                constraints.maxHeight * 0.72,
                              ),
                              child: _buildCartPanel(
                                context,
                                lang,
                                compact: true,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCartPanel(
    BuildContext context,
    String lang, {
    required bool compact,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DisplayLanguageService.t('cds_cart_list', languageCode: lang),
                style: TextStyle(fontFamily: 'Cairo',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B2538),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  DisplayLanguageService.t(
                    'cds_order_no',
                    languageCode: lang,
                    args: {
                      'order': orderNumber?.trim().isNotEmpty == true
                          ? orderNumber!
                          : '-',
                    },
                  ),
                  style: TextStyle(fontFamily: 'Cairo',
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (isOrderFree || _showPromo || _showDiscount) ...[
            const SizedBox(height: 16),
            _buildFinancialHighlights(lang, compact: compact),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: _AutoScrollCartList(
              cart: cart,
              itemBuilder: (item) => _buildOrderItem(context, item, lang),
            ),
          ),
          const SizedBox(height: 16),
          _buildSummaryRow(
            DisplayLanguageService.t('cds_subtotal', languageCode: lang),
            _formatMoney(_subtotal, lang),
          ),
          const SizedBox(height: 10),
          _buildSummaryRow(
            DisplayLanguageService.t(
              'cds_tax',
              languageCode: lang,
              args: {'rate': _taxRateLabel},
            ),
            _formatMoney(_tax, lang),
            isLastBeforeTotal: !_showDiscount,
          ),
          if (_showDiscount) ...[
            const SizedBox(height: 10),
            _buildSummaryRow(
              DisplayLanguageService.t(
                'cds_discount',
                languageCode: lang,
                args: {'amount': _formatMoney(_effectiveDiscount, lang)},
              ),
              '',
              valueColor: const Color(0xFF2D9F7F),
            ),
            const SizedBox(height: 10),
            _buildSummaryRow(
              DisplayLanguageService.t(
                'cds_before_discount',
                languageCode: lang,
                args: {'amount': _formatMoney(_beforeDiscountTotal, lang)},
              ),
              '',
            ),
            const SizedBox(height: 10),
            _buildSummaryRow(
              DisplayLanguageService.t(
                'cds_after_discount',
                languageCode: lang,
                args: {'amount': _formatMoney(_afterDiscountTotal, lang)},
              ),
              '',
              isLastBeforeTotal: true,
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                DisplayLanguageService.t('cds_total_final', languageCode: lang),
                style: TextStyle(fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B2538),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _afterDiscountTotal.toStringAsFixed(2),
                    style: TextStyle(fontFamily: 'Cairo',
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF27D26),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _resolvedCurrency(lang),
                    style: TextStyle(fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialHighlights(String lang, {required bool compact}) {
    final tiles = <Widget>[];
    if (isOrderFree) {
      tiles.add(
        _infoChip(lang.startsWith('ar') ? 'الطلب مجاني' : 'Free order'),
      );
    }
    if (_showDiscount) {
      final source = discountSource?.trim().toLowerCase();
      if ((orderDiscountValue ?? 0) > 0) {
        final value = orderDiscountValue ?? 0;
        final label = lang.startsWith('ar')
            ? 'خصم مبلغ: ${_formatMoney(value, lang)}'
            : 'Fixed discount: ${_formatMoney(value, lang)}';
        tiles.add(_infoChip(label));
      }
      if ((orderDiscountPercent ?? 0) > 0) {
        final pct = (orderDiscountPercent ?? 0).clamp(0.0, 100.0);
        final label = lang.startsWith('ar')
            ? 'خصم نسبة: ${pct.toStringAsFixed(0)}%'
            : 'Percentage discount: ${pct.toStringAsFixed(0)}%';
        tiles.add(_infoChip(label));
      }
      if (source == 'promo' && _showPromo) {
        final sourceLabel = lang.startsWith('ar')
            ? 'مصدر الخصم: كوبون'
            : 'Source: promo';
        tiles.add(_infoChip(sourceLabel));
      }
    }
    if (_showPromo) {
      tiles.add(_infoChip(_translatedPromo(lang)));
    }

    return Wrap(spacing: 8, runSpacing: 8, children: tiles);
  }

  Widget _infoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3F8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontFamily: 'Cairo',
          color: Color(0xFF5E6673),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildOrderItem(BuildContext context, CartItem item, String lang) {
    final productMap = _resolveProductMap(item);
    final unavailable = _isUnavailable(item.product.id, productMap);
    final hasDiscount = item.hasDiscount;
    final rawTotal = item.finalTotal ?? item.totalPrice;
    // عرض السعر شامل الضريبة
    final effectiveFinalTotal = rawTotal + (rawTotal * _resolvedTaxRate);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onLongPress: () {
        final nextDisabled = !unavailable;
        onToggleMealAvailability(productMap, nextDisabled);
        final statusText = DisplayLanguageService.t(
          nextDisabled ? 'cds_status_unavailable' : 'cds_status_available',
          languageCode: lang,
        );
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          SnackBar(
            content: Text(statusText),
            duration: const Duration(milliseconds: 900),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade50)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF5EB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item.quantity.toString(),
                      style: TextStyle(fontFamily: 'Cairo',
                        color: Color(0xFFF27D26),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: unavailable
                                ? const Color(0xFF9AA3AF)
                                : const Color(0xFF1B2538),
                          ),
                        ),
                        // Secondary-language name (Arabic/English pair) so
                        // non-Arabic-speaking customers can confirm the item.
                        if (item.displayNameEn.isNotEmpty &&
                            item.displayNameEn != item.displayName)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              item.displayNameEn,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: unavailable
                                    ? const Color(0xFFB0B7C3)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        // عرض الإضافات (extras)
                        if (item.selectedExtras.isNotEmpty && !unavailable)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _groupExtras(item.selectedExtras),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        if (unavailable)
                          Text(
                            DisplayLanguageService.t(
                              'cds_status_unavailable',
                              languageCode: lang,
                            ),
                            style: TextStyle(fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFB42318),
                            ),
                          ),
                        // ✅ عرض بيانات الخصم للمنتج
                        if (hasDiscount && !unavailable) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              // عرض السعر الأصلي شامل الضريبة مشطوب
                              if (item.originalPrice > rawTotal)
                                Text(
                                  (item.originalPrice + (item.originalPrice * _resolvedTaxRate)).toStringAsFixed(2),
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              const SizedBox(width: 8),
                              // شارة الخصم
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF2D9F7F,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item.isFree
                                      ? 'مجاني'
                                      : item.discountType ==
                                            DiscountType.percentage
                                      ? '-${item.discount.toStringAsFixed(0)}%'
                                      : '-${_formatMoney(item.discountValue, lang)}',
                                  style: TextStyle(fontFamily: 'Cairo',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2D9F7F),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // ✅ عرض السعر النهائي مع الخصم
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  effectiveFinalTotal.toStringAsFixed(2),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: unavailable
                        ? const Color(0xFF9AA3AF)
                        : hasDiscount
                        ? const Color(0xFF2D9F7F)
                        : const Color(0xFF1B2538),
                  ),
                ),
                if (hasDiscount && !unavailable)
                  Text(
                    _resolvedCurrency(lang),
                    style: TextStyle(fontFamily: 'Cairo',
                      fontSize: 10,
                      color: Color(0xFF2D9F7F),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isLastBeforeTotal = false,
    Color valueColor = Colors.grey,
  }) {
    return Container(
      padding: isLastBeforeTotal ? const EdgeInsets.only(bottom: 16) : null,
      decoration: isLastBeforeTotal
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            )
          : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontFamily: 'Cairo',
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (value.isNotEmpty)
            Text(
              value,
              style: TextStyle(fontFamily: 'Cairo', color: valueColor, fontWeight: FontWeight.w500),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(String lang, {bool compact = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) const Spacer(flex: 1),
        Text(
          DisplayLanguageService.t(
            'cds_current_order_title',
            languageCode: lang,
          ),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: compact ? 34 : 48,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1B2538),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          DisplayLanguageService.t(
            'cds_current_order_subtitle',
            languageCode: lang,
          ),
          style: TextStyle(fontFamily: 'Cairo',
            fontSize: 18,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (!compact) ...[
          const Spacer(flex: 2),
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.arrow_back, color: Colors.grey),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Map<String, dynamic> _resolveProductMap(CartItem item) {
    for (final product in catalogProducts) {
      final id =
          product['id']?.toString() ??
          product['meal_id']?.toString() ??
          product['product_id']?.toString() ??
          '';
      if (id.isNotEmpty && id == item.product.id) {
        return <String, dynamic>{...product};
      }
    }
    return <String, dynamic>{
      'id': item.product.id,
      'meal_id': item.product.id,
      'product_id': item.product.id,
      'name': item.displayName,
      'category': item.product.category,
      'price': item.product.basePrice,
    };
  }

  bool _isUnavailable(String productId, Map<String, dynamic> productMap) {
    if (productId.isNotEmpty && disabledMealIds.contains(productId)) {
      return true;
    }
    final id =
        productMap['id']?.toString() ??
        productMap['meal_id']?.toString() ??
        productMap['product_id']?.toString() ??
        '';
    if (id.isNotEmpty && disabledMealIds.contains(id)) {
      return true;
    }
    final flag = productMap['is_disabled'];
    return flag == true || flag?.toString() == '1';
  }

  String _translatedPromo(String lang) {
    final code = promoCode?.trim();
    if (code == null || code.isEmpty) return '';
    return DisplayLanguageService.t(
      'cds_promo',
      languageCode: lang,
      args: {'code': code},
    );
  }

  String _groupExtras(List<ProductExtra> extras) {
    // Group by id so the Arabic/English pair for the same addon stays aligned.
    // Rendering both names lets customers recognize the modifier regardless
    // of which language they read.
    final grouped = <String, _ExtraGroupEntry>{};
    for (final e in extras) {
      final key = e.id.isNotEmpty ? e.id : e.name;
      final existing = grouped[key];
      if (existing == null) {
        grouped[key] =
            _ExtraGroupEntry(nameAr: e.name, nameEn: e.nameEn, count: 1);
      } else {
        existing.count += 1;
      }
    }
    return grouped.values.map((entry) {
      final label = (entry.nameEn.isNotEmpty && entry.nameEn != entry.nameAr)
          ? '${entry.nameAr} / ${entry.nameEn}'
          : entry.nameAr;
      return entry.count > 1 ? '${entry.count}x$label' : label;
    }).join('، ');
  }

  String _resolvedCurrency(String lang) {
    final symbol = currencySymbol.trim();
    if (symbol.isNotEmpty) return symbol;
    return DisplayLanguageService.t('currency_default', languageCode: lang);
  }

  String _formatMoney(double value, String lang) {
    return DisplayLanguageService.t(
      'currency_suffix',
      languageCode: lang,
      args: {
        'value': value.toStringAsFixed(2),
        'currency': _resolvedCurrency(lang),
      },
    );
  }

  bool get _showPromo => promoCode?.trim().isNotEmpty == true;

  double get _resolvedTaxRate => (taxRate ?? 0.15).clamp(0.0, 1.0).toDouble();

  String get _taxRateLabel {
    final percent = _resolvedTaxRate * 100;
    if ((percent - percent.roundToDouble()).abs() < 0.001) {
      return percent.round().toString();
    }
    return percent.toStringAsFixed(2);
  }

  // ✅ الإجمالي الفرعي الأصلي قبل الخصم (للعرض)
  double get _subtotal {
    if (subtotalAmount != null && subtotalAmount! > 0) {
      return subtotalAmount!;
    }
    // حساب من المنتجات - نستخدم originalPrice قبل الخصم
    return cart.fold<double>(0.0, (sum, item) => sum + item.originalPrice);
  }

  // الإجمالي الفرعي بعد الخصم (للحسابات الداخلية)
  double get _discountedSubtotal =>
      cart.fold<double>(0.0, (sum, item) => sum + item.totalPrice);

  // ✅ الضريبة محسوبة على الإجمالي بعد الخصم (الطريقة الشائعة)
  double get _tax => taxAmount ?? (_discountedSubtotal * _resolvedTaxRate);

  // ✅ الإجمالي الإجمالي (subtotal + tax) قبل الخصم
  double get _grossTotal =>
      totalAmount ?? (_subtotal + (_subtotal * _resolvedTaxRate));

  double get _effectiveDiscount {
    final stackedOrderDiscount = _stackedOrderDiscountAmount;
    if (stackedOrderDiscount > 0) {
      return stackedOrderDiscount;
    }

    // أولوية للخصم الصريح على الطلب كله
    if ((discountAmount ?? 0) > 0) {
      return discountAmount!;
    }

    // لو في originalTotal و discountedTotal من السيرفر، استخدم الفرق
    if (originalTotal != null && discountedTotal != null) {
      final diff = originalTotal! - discountedTotal!;
      if (diff > 0) {
        return diff;
      }
    }

    // ✅ حساب خصومات المنتجات الفردية (نسبة أو سعر أو مجاني)
    // لما السيرفر مش بيبعت discountedTotal صريح
    final itemsDiscount = cart.fold<double>(
      0.0,
      (sum, item) => sum + item.discountValue,
    );
    if (itemsDiscount > 0) {
      return itemsDiscount;
    }

    return 0;
  }

  double get _stackedOrderDiscountAmount {
    final fixed = (orderDiscountValue ?? 0).clamp(0.0, _subtotal).toDouble();
    final percent = (orderDiscountPercent ?? 0).clamp(0.0, 100.0).toDouble();
    if (fixed <= 0 && percent <= 0) return 0;
    final afterFixed = math.max(0.0, _subtotal - fixed);
    final percentAmount = afterFixed * (percent / 100.0);
    return fixed + percentAmount;
  }

  bool get _showDiscount {
    if (_effectiveDiscount > 0) return true;
    if (originalTotal != null && discountedTotal != null) {
      return (originalTotal! - discountedTotal!) > 0.0001;
    }
    return false;
  }

  double get _beforeDiscountTotal {
    // لو السيرفر بيبعت originalTotal صريح، استخدمه
    final original = originalTotal;
    if (original != null && original > 0) {
      return original;
    }

    // ✅ استخدم _grossTotal اللي بيحسب الإجمالي قبل الخصم
    return _grossTotal;
  }

  double get _afterDiscountTotal {
    final explicit = discountedTotal;
    if (explicit != null && explicit >= 0) {
      return explicit;
    }
    final calculated = _beforeDiscountTotal - _effectiveDiscount;
    return math.max(0, calculated);
  }
}

class _AnimatedWelcomeWord extends StatefulWidget {
  const _AnimatedWelcomeWord();

  @override
  State<_AnimatedWelcomeWord> createState() => _AnimatedWelcomeWordState();
}

class _AnimatedWelcomeWordState extends State<_AnimatedWelcomeWord>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _floatAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(
      begin: 0,
      end: -10,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _scaleAnimation = Tween<double>(
      begin: 1,
      end: 1.035,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _fadeAnimation = Tween<double>(
      begin: 0.82,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatAnimation.value),
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(
              opacity: _fadeAnimation.value,
              child: Text(
                'welcome',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1B2538),
                  height: 1.2,
                  letterSpacing: 1.2,
                  shadows: [
                    Shadow(
                      color: const Color(
                        0xFFF27D26,
                      ).withValues(alpha: 0.18 + (_controller.value * 0.18)),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Auto-scrolls to the bottom whenever the cart changes,
/// so the latest added item is always visible.
class _AutoScrollCartList extends StatefulWidget {
  final List<CartItem> cart;
  final Widget Function(CartItem item) itemBuilder;

  const _AutoScrollCartList({
    required this.cart,
    required this.itemBuilder,
  });

  @override
  State<_AutoScrollCartList> createState() => _AutoScrollCartListState();
}

class _AutoScrollCartListState extends State<_AutoScrollCartList> {
  final ScrollController _controller = ScrollController();
  int _previousLength = 0;

  @override
  void didUpdateWidget(covariant _AutoScrollCartList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Scroll to bottom when a new item is added
    if (widget.cart.length > _previousLength) {
      _scrollToBottom();
    }
    _previousLength = widget.cart.length;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      _controller.animateTo(
        _controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      itemCount: widget.cart.length,
      itemBuilder: (context, index) {
        return widget.itemBuilder(widget.cart[index]);
      },
    );
  }
}

class _ExtraGroupEntry {
  final String nameAr;
  final String nameEn;
  int count;
  _ExtraGroupEntry({
    required this.nameAr,
    required this.nameEn,
    required this.count,
  });
}
