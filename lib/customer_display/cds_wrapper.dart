import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'display_provider.dart';
import 'models.dart';
import 'display_language_service.dart';
import 'app_error_handler.dart';
import 'cds_page.dart';

class CdsPageWrapper extends StatefulWidget {
  const CdsPageWrapper({super.key});

  @override
  State<CdsPageWrapper> createState() => _CdsPageWrapperState();
}

class _CdsPageWrapperState extends State<CdsPageWrapper> {
  VideoPlayerController? _successController;
  bool _successAnimationReady = false;
  bool _hasPinnedLastFrame = false;
  DisplayProvider? _provider;

  @override
  void initState() {
    super.initState();
    // Initialize video immediately
    _initSuccessAnimation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Get provider reference and add listener
    _provider = context.read<DisplayProvider>();
    _provider?.removeListener(_onProviderChanged);
    _provider?.addListener(_onProviderChanged);
  }

  void _onProviderChanged() {
    // Force rebuild when provider changes
    if (mounted && _provider != null) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _provider?.removeListener(_onProviderChanged);
    _successController?.dispose();
    super.dispose();
  }

  Future<void> _initSuccessAnimation() async {
    debugPrint('🎬 Starting to load success animation...');
    final candidateAssets = <String>[
      'assets/animation/Success.mp4',
      'assets/animation/Success.webm',
    ];
    for (final assetPath in candidateAssets) {
      try {
        debugPrint('🎬 Trying: $assetPath');
        final controller = VideoPlayerController.asset(assetPath);
        await controller.initialize();
        debugPrint('✅ Loaded: $assetPath (size: ${controller.value.size})');
        controller
          ..setLooping(false)
          ..setVolume(0)
          ..play();
        controller.addListener(() {
          if (_hasPinnedLastFrame) return;
          if (!controller.value.isInitialized) return;
          final duration = controller.value.duration;
          if (duration == Duration.zero) return;
          final position = controller.value.position;
          final reachedEnd = position >= duration - const Duration(milliseconds: 50);
          if (!reachedEnd) return;
          _hasPinnedLastFrame = true;
          debugPrint('🏁 Video ended, pinning last frame');
          if (mounted) {
            controller.pause();
            controller.seekTo(duration);
          }
        });
        if (!mounted) {
          await controller.dispose();
          return;
        }
        setState(() {
          _successController = controller;
          _successAnimationReady = true;
        });
        debugPrint('🎉 Animation READY! Ready=$_successAnimationReady');
        return;
      } catch (e) {
        debugPrint('❌ Failed to load $assetPath: $e');
      }
    }
    debugPrint('⚠️ No animation could be loaded');
    if (!mounted) return;
    setState(() => _successAnimationReady = false);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DisplayProvider>(
      builder: (context, provider, child) {
        // Force rebuild when payment status changes to success
        final currentStatus = provider.paymentStatus;
        
        // Convert real cart data from provider
        final cartData = provider.cartData;
        final languageCode = provider.languageCode;
        final cart = _convertCartData(cartData, languageCode: languageCode);
        final catalogContext = provider.catalogContext;
        final catalogProducts = _extractProducts(
          catalogContext,
          languageCode: languageCode,
        );
        final catalogCategories = _extractCategories(
          catalogContext,
          catalogProducts,
          languageCode: languageCode,
        );
        final disabledMealIds = _extractDisabledMealIds(catalogContext);
        final promoCode = _extractPromoCode(cartData);
        final discountAmount = _extractDiscountAmount(cartData);
        final originalTotal = _extractOriginalTotal(cartData);
        final discountedTotal = _extractDiscountedTotal(cartData);
        final subtotalAmount = _extractSubtotal(cartData);
        final taxAmount = _extractTax(cartData);
        final totalAmount = _extractTotal(cartData);
        final taxRate = _extractTaxRate(cartData);
        final isOrderFree = _extractIsOrderFree(cartData);
        final orderDiscountType = _extractOrderDiscountType(cartData);
        final orderDiscountValue = _extractOrderDiscountValue(cartData);
        final orderDiscountPercent = _extractOrderDiscountPercent(cartData);
        final discountSource = _extractDiscountSource(cartData);
        final currencySymbol = _extractCurrencySymbol(cartData, catalogContext);
        final showPayment = provider.isShowingPayment;
        final showStatusOverlay = provider.hasStatusOverlay && !showPayment;

        final baseScreen = CustomerFacingScreen(
          cart: cart,
          languageCode: languageCode,
          currencySymbol: currencySymbol,
          orderNumber: cartData['orderNumber']?.toString(),
          promoCode: promoCode,
          discountAmount: discountAmount,
          originalTotal: originalTotal,
          discountedTotal: discountedTotal,
          subtotalAmount: subtotalAmount,
          taxAmount: taxAmount,
          totalAmount: totalAmount,
          taxRate: taxRate,
          isOrderFree: isOrderFree,
          orderDiscountType: orderDiscountType,
          orderDiscountValue: orderDiscountValue,
          orderDiscountPercent: orderDiscountPercent,
          discountSource: discountSource,
          catalogProducts: catalogProducts,
          catalogCategories: catalogCategories,
          disabledMealIds: disabledMealIds,
          onToggleMealAvailability: (product, isDisabled) {
            AppErrorHandler.guardSync(
              page: 'CDS',
              action: 'onToggleMealAvailability',
              run: () {
                final mealId =
                    product['id']?.toString() ??
                    product['meal_id']?.toString() ??
                    product['product_id']?.toString() ??
                    '';
                if (mealId.isEmpty) return;
                provider.applyMealAvailability(
                  mealId: mealId,
                  mealName: product['name']?.toString() ?? 'Meal',
                  categoryName: product['category']?.toString(),
                  isDisabled: isDisabled,
                );
              },
            );
          },
        );

        return Stack(
          children: [
            baseScreen,
            if (showStatusOverlay)
              Positioned.fill(
                child: _buildStatusOverlay(
                  provider: provider,
                  languageCode: languageCode,
                  currencySymbol: currencySymbol,
                ),
              ),
            if (showPayment)
            Positioned.fill(
              key: ValueKey('payment_${currentStatus}_$_successAnimationReady'),
              child: _buildPaymentOverlay(
                provider: provider,
                languageCode: languageCode,
                isSuccessAnimationReady: _successAnimationReady,
                successController: _successController,
                currentStatus: currentStatus,
              ),
            ),
            // Reconnect banner removed per UX request.
          ],
        );
      },
    );
  }

  Widget _buildStatusOverlay({
    required DisplayProvider provider,
    required String languageCode,
    required String currencySymbol,
  }) {
    final overlay = provider.statusOverlay ?? const <String, dynamic>{};
    final title = overlay['title']?.toString() ?? '';
    final subtitle = overlay['subtitle']?.toString() ?? '';
    final type = overlay['type']?.toString();
    final amount = _parseNullableDouble(overlay['amount']);
    final accent = type == 'refund'
        ? const Color(0xFFEF4444)
        : const Color(0xFF22C55E);
    final amountText = amount > 0
        ? DisplayLanguageService.t(
            'currency_suffix',
            languageCode: languageCode,
            args: {
              'value': amount.toStringAsFixed(2),
              'currency': currencySymbol,
            },
          )
        : '';

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      alignment: Alignment.center,
      child: Directionality(
        textDirection: DisplayLanguageService.isRtl(languageCode)
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: Container(
          width: 520,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                type == 'refund' ? Icons.restart_alt : Icons.check_circle,
                size: 72,
                color: accent,
              ),
              if (title.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE5E7EB),
                  ),
                ),
              ],
              if (amountText.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  amountText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentOverlay({
    required DisplayProvider provider,
    required String languageCode,
    required bool isSuccessAnimationReady,
    required VideoPlayerController? successController,
    required PaymentDisplayStatus currentStatus,
  }) {
    final code = languageCode.trim().toLowerCase();
    final isArabic = code.isEmpty || code.startsWith('ar');
    final isSuccess = currentStatus == PaymentDisplayStatus.success;
    
    debugPrint('🔍 Build Overlay: status=$currentStatus, success=$isSuccess, ready=$isSuccessAnimationReady, ctrl=${successController != null}');
    
    String title;
    String subtitle;
    Color accent;
    IconData icon;

    switch (currentStatus) {
      case PaymentDisplayStatus.processing:
        title = isArabic ? 'جاري معالجة الدفع' : 'Processing Payment';
        subtitle = isArabic ? 'يرجى الانتظار...' : 'Please wait...';
        accent = const Color(0xFF0EA5E9);
        icon = Icons.sync_rounded;
        break;
      case PaymentDisplayStatus.success:
        title = isArabic ? 'شكراً لزيارتكم' : 'Thank you for your visit';
        subtitle = isArabic ? 'نتمنى رؤيتك مرة أخرى' : 'See you again soon';
        accent = const Color(0xFF22C55E);
        icon = Icons.check_box_rounded;
        break;
      case PaymentDisplayStatus.failed:
        title = isArabic ? 'فشل الدفع' : 'Payment Failed';
        subtitle = provider.paymentMessage?.trim().isNotEmpty == true
            ? provider.paymentMessage!.trim()
            : (isArabic ? 'يرجى المحاولة مرة أخرى' : 'Please try again');
        accent = const Color(0xFFEF4444);
        icon = Icons.error_rounded;
        break;
      case PaymentDisplayStatus.cancelled:
        title = isArabic ? 'تم إلغاء الدفع' : 'Payment Cancelled';
        subtitle = isArabic ? 'يمكنك المحاولة مرة أخرى' : 'You can try again';
        accent = const Color(0xFF94A3B8);
        icon = Icons.cancel_rounded;
        break;
      case PaymentDisplayStatus.idle:
        return const SizedBox.shrink();
    }

    return Container(
      color: Colors.black.withValues(alpha: 0.66),
      alignment: Alignment.center,
      child: Container(
        width: 520,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
        decoration: BoxDecoration(
          color: isSuccess ? Colors.white : const Color(0xFF111827),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isSuccess ? 0.22 : 0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Show video animation for success, icon for other states
            if (isSuccess && isSuccessAnimationReady && successController != null)
              Container(
                width: 150,
                height: 150,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: VideoPlayer(successController),
                ),
              )
            else
              Icon(icon, size: 72, color: accent),
            if (title.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: isSuccess ? const Color(0xFF111827) : Colors.white,
                ),
              ),
            ],
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: isSuccess
                      ? const Color(0xFF4B5563)
                      : const Color(0xFFD1D5DB),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<CartItem> _convertCartData(
    Map<String, dynamic> cartData, {
    required String languageCode,
  }) {
    if (cartData.isEmpty) return [];

    final rawItems = cartData['items'];
    final items = rawItems is List ? rawItems : const [];
    if (items.isEmpty) return [];

    return items.whereType<Map>().map((item) {
      final itemMap = Map<String, dynamic>.from(item);

      // Parse extras
      final rawExtras = itemMap['extras'];
      final extrasRaw = rawExtras is List ? rawExtras : const [];
      final extras = extrasRaw.whereType<Map>().map((e) {
        final extraMap = Map<String, dynamic>.from(e);
        final localizedName = _localizedText(
          extraMap['name'] ?? extraMap['label'] ?? extraMap['title'],
          languageCode: languageCode,
        );
        return ProductExtra(
          id: extraMap['id']?.toString() ?? '',
          name: localizedName,
          nameEn: _localizedText(
            extraMap['nameEn'] ?? extraMap['name'],
            languageCode: 'en',
          ),
          price: _parseDouble(extraMap['price']),
        );
      }).toList();

      // Parse price - handle both number and string formats (e.g. "6.00 SAR")
      final unitPrice = _parseDouble(itemMap['price'] ?? itemMap['unitPrice']);
      final localizedProductName = _localizedText(
        itemMap['name'],
        languageCode: languageCode,
      );
      final localizedCategory = _localizedText(
        itemMap['category'],
        languageCode: languageCode,
      );

      // Create Product from the data
      final product = Product(
        id: itemMap['productId']?.toString() ?? itemMap['id']?.toString() ?? '',
        name: localizedProductName,
        nameEn: _localizedText(
          itemMap['nameEn'] ?? itemMap['name'],
          languageCode: 'en',
        ),
        basePrice: unitPrice,
        category: localizedCategory,
        imageUrl: itemMap['imageUrl']?.toString() ?? '',
        availableExtras: extras,
      );

      // ✅ استخراج بيانات الخصم للمنتج
      final discountData = _asMap(
        itemMap['discount_data'] ?? itemMap['discountData'],
      );
      final discount = _parseNullableDouble(
        discountData?['discount'] ?? itemMap['discount'],
      );
      final discountTypeStr =
          (discountData?['discount_type'] ??
                  itemMap['discount_type'] ??
                  itemMap['discountType'])
              ?.toString();
      final discountType = discountTypeStr == 'percentage'
          ? DiscountType.percentage
          : DiscountType.amount;
      final isFree = _parseBool(
        discountData?['is_free'] ??
            itemMap['is_free'] ??
            itemMap['isFree'] ??
            false,
      );
      final originalUnitPrice = _parseNullableDouble(
        discountData?['original_unit_price'] ??
            itemMap['original_unit_price'] ??
            itemMap['originalUnitPrice'],
      );
      final originalTotal = _parseNullableDouble(
        discountData?['original_total'] ??
            itemMap['original_total'] ??
            itemMap['originalTotal'],
      );
      final finalTotal = _parseNullableDouble(
        discountData?['final_total'] ??
            itemMap['final_total'] ??
            itemMap['finalTotal'] ??
            itemMap['totalPrice'],
      );

      return CartItem(
        cartId: itemMap['cartId']?.toString() ?? UniqueKey().toString(),
        product: product,
        quantity: _parseInt(itemMap['quantity']),
        selectedExtras: extras,
        discount: discount,
        discountType: discountType,
        isFree: isFree,
        originalUnitPrice: originalUnitPrice > 0 ? originalUnitPrice : null,
        originalTotal: originalTotal > 0 ? originalTotal : null,
        finalTotal: finalTotal > 0 ? finalTotal : null,
      );
    }).toList();
  }

  /// Parse a value to double, handling strings like "6.00 SAR"
  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      // Remove currency suffix (e.g. "6.00 SAR" -> "6.00")
      final cleaned = value.replaceAll(RegExp(r'[^0-9.]'), '');
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0.0;
  }

  int _parseInt(dynamic value) {
    if (value == null) return 1;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 1;
    return 1;
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  double _parseNullableDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll(RegExp(r'[^0-9.\-]'), '');
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0.0;
  }

  bool _parseBool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty) return defaultValue;
    if (const ['1', 'true', 'yes', 'on'].contains(text)) return true;
    if (const ['0', 'false', 'no', 'off'].contains(text)) return false;
    return defaultValue;
  }

  String? _extractPromoCode(Map<String, dynamic> cartData) {
    final promoMap = _asMap(cartData['promo']);
    final candidates = <dynamic>[
      promoMap?['code'],
      cartData['promocodeValue'],
      cartData['promoCode'],
      cartData['promo_code'],
    ];
    for (final candidate in candidates) {
      final text = candidate?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  double? _extractDiscountAmount(Map<String, dynamic> cartData) {
    final promoMap = _asMap(cartData['promo']);
    final amount = _parseNullableDouble(
      promoMap?['discount_amount'] ??
          cartData['discount_amount'] ??
          cartData['discountAmount'] ??
          cartData['discount'],
    );
    return amount > 0 ? amount : null;
  }

  double? _extractOriginalTotal(Map<String, dynamic> cartData) {
    final amount = _parseNullableDouble(
      cartData['original_total'] ?? cartData['originalTotal'],
    );
    return amount > 0 ? amount : null;
  }

  double? _extractDiscountedTotal(Map<String, dynamic> cartData) {
    final amount = _parseNullableDouble(
      cartData['discounted_total'] ?? cartData['discountedTotal'],
    );
    if (amount > 0) return amount;
    final fallback = _parseNullableDouble(cartData['total']);
    return fallback > 0 ? fallback : null;
  }

  double? _extractSubtotal(Map<String, dynamic> cartData) {
    final raw = cartData['subtotal'];
    if (raw == null) return null;
    final amount = _parseNullableDouble(raw);
    return amount >= 0 ? amount : null;
  }

  double? _extractTax(Map<String, dynamic> cartData) {
    final raw = cartData['tax'];
    if (raw == null) return null;
    final amount = _parseNullableDouble(raw);
    return amount >= 0 ? amount : null;
  }

  double? _extractTotal(Map<String, dynamic> cartData) {
    final raw = cartData['total'];
    if (raw == null) return null;
    final amount = _parseNullableDouble(raw);
    return amount >= 0 ? amount : null;
  }

  double? _extractTaxRate(Map<String, dynamic> cartData) {
    final directRaw = cartData['tax_rate'] ?? cartData['taxRate'];
    if (directRaw != null) {
      final direct = _parseNullableDouble(directRaw);
      if (direct <= 0) return 0.0;
      return direct > 1.0 ? (direct / 100.0).clamp(0.0, 1.0) : direct;
    }

    final percentageRaw =
        cartData['tax_percentage'] ?? cartData['taxPercentage'];
    if (percentageRaw != null) {
      final percentage = _parseNullableDouble(percentageRaw);
      if (percentage <= 0) return 0.0;
      return (percentage / 100.0).clamp(0.0, 1.0);
    }

    final subtotal = _parseNullableDouble(cartData['subtotal']);
    final tax = _parseNullableDouble(cartData['tax']);
    if (subtotal > 0 && tax > 0) {
      return (tax / subtotal).clamp(0.0, 1.0);
    }
    return null;
  }

  bool _extractIsOrderFree(Map<String, dynamic> cartData) {
    final raw = cartData['is_order_free'] ?? cartData['isOrderFree'];
    return _parseBool(raw, defaultValue: false);
  }

  String? _extractOrderDiscountType(Map<String, dynamic> cartData) {
    final raw = cartData['order_discount_type'] ?? cartData['discount_type'];
    final text = raw?.toString().trim().toLowerCase();
    if (text == null || text.isEmpty) return null;
    if (text == 'percentage' || text == 'amount') return text;
    if (text == 'fixed') return 'amount';
    return null;
  }

  double? _extractOrderDiscountValue(Map<String, dynamic> cartData) {
    final promoMap = _asMap(cartData['promo']);
    final amount = _parseNullableDouble(
      cartData['order_discount_value'] ??
          cartData['order_fixed_discount'] ??
          cartData['fixed_discount'] ??
          promoMap?['fixed_discount_amount'] ??
          cartData['discount_amount'] ??
          cartData['discount'],
    );
    return amount >= 0 ? amount : null;
  }

  double? _extractOrderDiscountPercent(Map<String, dynamic> cartData) {
    final promoMap = _asMap(cartData['promo']);
    final percentage = _parseNullableDouble(
      cartData['order_discount_percent'] ??
          cartData['discount_percent'] ??
          cartData['discount_percentage'] ??
          promoMap?['discount_percent'] ??
          promoMap?['discount_percentage'],
    ).clamp(0.0, 100.0);
    return percentage > 0 ? percentage : null;
  }

  String? _extractDiscountSource(Map<String, dynamic> cartData) {
    final raw = cartData['discount_source']?.toString().trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    if (const ['promo', 'manual', 'free', 'none'].contains(raw)) return raw;
    return null;
  }

  String _extractCurrencySymbol(
    Map<String, dynamic> cartData,
    Map<String, dynamic> context,
  ) {
    final candidates = <dynamic>[
      cartData['currency'],
      cartData['currency_symbol'],
      cartData['currencySymbol'],
      context['currency'],
      context['currency_symbol'],
      context['currencySymbol'],
    ];
    for (final candidate in candidates) {
      final text = candidate?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return 'ر.س';
  }

  List<Map<String, dynamic>> _extractProducts(
    Map<String, dynamic> context, {
    required String languageCode,
  }) {
    final raw = context['products'];
    if (raw is! List) return const [];

    return raw
        .whereType<Map>()
        .map((item) {
          final map = Map<String, dynamic>.from(item);
          return {
            'id':
                map['id']?.toString() ??
                map['meal_id']?.toString() ??
                map['product_id']?.toString() ??
                '',
            'name': _localizedText(
              map['name'] ?? map['title'],
              languageCode: languageCode,
            ),
            'category': _localizedText(
              map['category'],
              languageCode: languageCode,
            ),
            'price': _parseDouble(map['price']),
          };
        })
        .where((item) => (item['id'] as String).isNotEmpty)
        .toList();
  }

  List<String> _extractCategories(
    Map<String, dynamic> context,
    List<Map<String, dynamic>> products, {
    required String languageCode,
  }) {
    final categories = <String>{};
    final rawCategories = context['categories'];
    if (rawCategories is List) {
      for (final item in rawCategories) {
        if (item is Map) {
          final name = _localizedText(item['name'], languageCode: languageCode);
          if (name.isNotEmpty) categories.add(name);
        } else if (item is String && item.trim().isNotEmpty) {
          categories.add(item.trim());
        }
      }
    }

    for (final product in products) {
      final category = product['category']?.toString().trim() ?? '';
      if (category.isNotEmpty) categories.add(category);
    }

    final sorted = categories.toList()..sort((a, b) => a.compareTo(b));
    return sorted;
  }

  String _localizedText(dynamic value, {required String languageCode}) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is Map) {
      final normalizedCode = languageCode.trim().toLowerCase();
      final map = value.map((k, v) => MapEntry(k.toString(), v));
      final candidates = <dynamic>[map[normalizedCode], map['en'], map['ar']];
      for (final candidate in candidates) {
        final text = candidate?.toString().trim();
        if (text != null && text.isNotEmpty) return text;
      }
      for (final candidate in map.values) {
        final text = candidate?.toString().trim();
        if (text != null && text.isNotEmpty) return text;
      }
    }
    return value.toString().trim();
  }

  Set<String> _extractDisabledMealIds(Map<String, dynamic> context) {
    final result = <String>{};
    final raw = context['disabled_meals'];
    if (raw is! List) return result;

    for (final item in raw) {
      if (item is! Map) continue;
      final payload = Map<String, dynamic>.from(item);
      final mealId =
          payload['meal_id']?.toString() ??
          payload['product_id']?.toString() ??
          payload['productId']?.toString() ??
          '';
      if (mealId.isEmpty) continue;
      if (payload['is_disabled'] == true) {
        result.add(mealId);
      }
    }
    return result;
  }
}
