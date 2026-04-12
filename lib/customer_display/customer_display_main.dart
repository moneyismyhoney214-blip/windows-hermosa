import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'cds_page.dart';
import 'models.dart';

/// Secondary entry point for the customer-facing display.
///
/// This runs in a separate Flutter engine on the secondary screen
/// via Android's Presentation API. It receives data from the main
/// cashier app through a MethodChannel.
@pragma('vm:entry-point')
void customerDisplayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CustomerDisplayApp());
}

class CustomerDisplayApp extends StatefulWidget {
  const CustomerDisplayApp({super.key});

  @override
  State<CustomerDisplayApp> createState() => _CustomerDisplayAppState();
}

class _CustomerDisplayAppState extends State<CustomerDisplayApp> {
  static const _channel = MethodChannel('com.hermosaapp.presentation');

  // Display state
  Map<String, dynamic> _cartData = {};
  Map<String, dynamic> _catalogContext = {};
  String _languageCode = 'ar';

  // Payment state
  String? _paymentStatus;
  String? _paymentMessage;


  // Status overlay
  Map<String, dynamic>? _statusOverlay;

  @override
  void initState() {
    super.initState();
    _setupChannel();
    // Notify the main app that we're ready
    _channel.invokeMethod('secondaryDisplayReady', null);
  }

  void _setupChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onDataFromMain':
          final args = call.arguments;
          if (args is Map) {
            final type = args['type']?.toString() ?? '';
            final data = args['data'];
            final dataMap = data is Map
                ? data.map((k, v) => MapEntry(k.toString(), v))
                : <String, dynamic>{};
            _handleMessage(type, dataMap);
          }
          return true;
        default:
          return null;
      }
    });
  }

  void _handleMessage(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'UPDATE_CART':
        setState(() {
          _cartData = Map<String, dynamic>.from(data);
          _syncLanguage(data);
        });
        break;
      case 'SET_MODE':
        // Secondary display is always CDS mode
        break;
      case 'START_PAYMENT':
        setState(() {
          _paymentStatus = 'processing';
          _paymentMessage = null;
        });
        break;
      case 'PAYMENT_STATUS':
        setState(() {
          _paymentStatus = data['status']?.toString();
          _paymentMessage = data['message']?.toString();
          // Auto-clear after failed/cancelled (success clears when GIF finishes)
          if (_paymentStatus == 'failed' ||
              _paymentStatus == 'cancelled') {
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _paymentStatus = null;
                  _paymentMessage = null;
                });
              }
            });
          }
        });
        break;
      case 'CATALOG_CONTEXT':
        setState(() {
          _catalogContext = Map<String, dynamic>.from(data);
          _syncLanguage(data);
        });
        break;
      case 'LANGUAGE_CHANGED':
        setState(() {
          _languageCode = data['language_code']?.toString() ?? _languageCode;
        });
        break;
      case 'STATUS_OVERLAY':
        setState(() {
          _statusOverlay = Map<String, dynamic>.from(data);
        });
        break;
      case 'CLEAR_STATUS_OVERLAY':
        setState(() {
          _statusOverlay = null;
        });
        break;
    }
  }

  void _syncLanguage(Map<String, dynamic> payload) {
    final code = payload['language_code']?.toString() ??
        payload['lang']?.toString();
    if (code != null && code.trim().isNotEmpty) {
      _languageCode = code.trim().toLowerCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        textTheme: ThemeData.dark().textTheme,
      ),
      home: _buildDisplay(),
    );
  }

  Widget _buildDisplay() {
    final cart = _convertCartData(_cartData);
    final catalogProducts = _extractProducts(_catalogContext);
    final catalogCategories = _extractCategories(_catalogContext, catalogProducts);
    final disabledMealIds = _extractDisabledMealIds(_catalogContext);
    final currencySymbol = _extractCurrencySymbol(_cartData, _catalogContext);

    final showPayment = _paymentStatus != null;
    final showOverlay = _statusOverlay != null && !showPayment;

    final baseScreen = CustomerFacingScreen(
      cart: cart,
      languageCode: _languageCode,
      currencySymbol: currencySymbol,
      orderNumber: _cartData['orderNumber']?.toString(),
      promoCode: _extractPromoCode(_cartData),
      discountAmount: _extractDouble(_cartData['discount_amount'] ?? _cartData['discountAmount']),
      originalTotal: _extractDouble(_cartData['original_total'] ?? _cartData['originalTotal']),
      discountedTotal: _extractDouble(_cartData['discounted_total'] ?? _cartData['discountedTotal'] ?? _cartData['total']),
      subtotalAmount: _extractDouble(_cartData['subtotal']),
      taxAmount: _extractDouble(_cartData['tax']),
      totalAmount: _extractDouble(_cartData['total']),
      taxRate: _extractTaxRate(_cartData),
      isOrderFree: _parseBool(_cartData['is_order_free'] ?? _cartData['isOrderFree']),
      orderDiscountType: _cartData['order_discount_type']?.toString() ?? _cartData['discount_type']?.toString(),
      orderDiscountValue: _extractDouble(_cartData['order_discount_value'] ?? _cartData['discount']),
      orderDiscountPercent: _extractDouble(_cartData['order_discount_percent'] ?? _cartData['discount_percent']),
      discountSource: _cartData['discount_source']?.toString(),
      catalogProducts: catalogProducts,
      catalogCategories: catalogCategories,
      disabledMealIds: disabledMealIds,
      onToggleMealAvailability: (product, isDisabled) {
        final mealId = product['id']?.toString() ??
            product['meal_id']?.toString() ??
            product['product_id']?.toString() ??
            '';
        if (mealId.isEmpty) return;
        // Send back to main app
        _channel.invokeMethod('onMealAvailabilityToggle', {
          'mealId': mealId,
          'productId': mealId,
          'mealName': product['name']?.toString() ?? 'Meal',
          'categoryName': product['category']?.toString(),
          'isDisabled': isDisabled,
        });
      },
    );

    return Stack(
      children: [
        baseScreen,
        if (showOverlay)
          Positioned.fill(child: _buildStatusOverlay()),
        if (showPayment)
          Positioned.fill(child: _buildPaymentOverlay()),
      ],
    );
  }

  Widget _buildStatusOverlay() {
    final overlay = _statusOverlay ?? {};
    final title = overlay['title']?.toString() ?? '';
    final subtitle = overlay['subtitle']?.toString() ?? '';
    final type = overlay['type']?.toString();
    final amount = _extractDouble(overlay['amount']);
    final accent = type == 'refund'
        ? const Color(0xFFEF4444)
        : const Color(0xFF22C55E);

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      alignment: Alignment.center,
      child: Container(
        width: 520,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
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
              Text(title, textAlign: TextAlign.center,
                style: GoogleFonts.cairo(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white)),
            ],
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(subtitle, textAlign: TextAlign.center,
                style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w600, color: const Color(0xFFE5E7EB))),
            ],
            if (amount > 0) ...[
              const SizedBox(height: 14),
              Text(amount.toStringAsFixed(2), textAlign: TextAlign.center,
                style: GoogleFonts.cairo(fontSize: 24, fontWeight: FontWeight.w700, color: accent)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentOverlay() {
    final isArabic = _languageCode.startsWith('ar') || _languageCode.isEmpty;
    final isSuccess = _paymentStatus == 'success';
    final isFailed = _paymentStatus == 'failed';
    final isCancelled = _paymentStatus == 'cancelled';

    String title;
    String subtitle;
    Color accent;
    IconData icon;

    if (isSuccess) {
      title = isArabic ? 'شكراً لزيارتكم' : 'Thank you for your visit';
      subtitle = isArabic ? 'نتمنى رؤيتك مرة أخرى' : 'See you again soon';
      accent = const Color(0xFF22C55E);
      icon = Icons.check_circle_rounded;
    } else if (isFailed) {
      title = isArabic ? 'فشل الدفع' : 'Payment Failed';
      subtitle = _paymentMessage ?? (isArabic ? 'يرجى المحاولة مرة أخرى' : 'Please try again');
      accent = const Color(0xFFEF4444);
      icon = Icons.error_rounded;
    } else if (isCancelled) {
      title = isArabic ? 'تم إلغاء الدفع' : 'Payment Cancelled';
      subtitle = isArabic ? 'يمكنك المحاولة مرة أخرى' : 'You can try again';
      accent = const Color(0xFF94A3B8);
      icon = Icons.cancel_rounded;
    } else {
      title = isArabic ? 'جاري معالجة الدفع' : 'Processing Payment';
      subtitle = isArabic ? 'يرجى الانتظار...' : 'Please wait...';
      accent = const Color(0xFF0EA5E9);
      icon = Icons.sync_rounded;
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
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSuccess)
              _SuccessCheckAnimation(
                onFinished: () {
                  if (mounted) {
                    setState(() {
                      _paymentStatus = null;
                      _paymentMessage = null;
                    });
                  }
                },
              )
            else
              Icon(icon, size: 72, color: accent),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: isSuccess ? const Color(0xFF111827) : Colors.white,
              )),
            const SizedBox(height: 10),
            Text(subtitle, textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: isSuccess ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB),
              )),
          ],
        ),
      ),
    );
  }

  // ─── Data conversion helpers (same as CdsPageWrapper) ───

  List<CartItem> _convertCartData(Map<String, dynamic> cartData) {
    if (cartData.isEmpty) return [];
    final rawItems = cartData['items'];
    final items = rawItems is List ? rawItems : const [];
    if (items.isEmpty) return [];

    return items.whereType<Map>().map((item) {
      final itemMap = Map<String, dynamic>.from(item);
      final rawExtras = itemMap['extras'];
      final extrasRaw = rawExtras is List ? rawExtras : const [];
      final extras = extrasRaw.whereType<Map>().map((e) {
        final extraMap = Map<String, dynamic>.from(e);
        return ProductExtra(
          id: extraMap['id']?.toString() ?? '',
          name: _localizedText(extraMap['name'] ?? extraMap['label']),
          nameEn: _localizedText(extraMap['nameEn'] ?? extraMap['name'], lang: 'en'),
          price: _toDouble(extraMap['price']),
        );
      }).toList();

      final unitPrice = _toDouble(itemMap['price'] ?? itemMap['unitPrice']);
      final product = Product(
        id: itemMap['productId']?.toString() ?? itemMap['id']?.toString() ?? '',
        name: _localizedText(itemMap['name']),
        nameEn: _localizedText(itemMap['nameEn'] ?? itemMap['name'], lang: 'en'),
        basePrice: unitPrice,
        category: _localizedText(itemMap['category']),
        imageUrl: itemMap['imageUrl']?.toString() ?? '',
        availableExtras: extras,
      );

      final discountData = _asMap(itemMap['discount_data'] ?? itemMap['discountData']);
      final discount = _extractDouble(discountData?['discount'] ?? itemMap['discount']);
      final discountTypeStr = (discountData?['discount_type'] ?? itemMap['discount_type'])?.toString();
      final discountType = discountTypeStr == 'percentage' ? DiscountType.percentage : DiscountType.amount;
      final isFree = _parseBool(discountData?['is_free'] ?? itemMap['is_free'] ?? itemMap['isFree']);
      final originalUnitPrice = _extractDouble(discountData?['original_unit_price'] ?? itemMap['originalUnitPrice']);
      final originalTotal = _extractDouble(discountData?['original_total'] ?? itemMap['originalTotal']);
      final finalTotal = _extractDouble(discountData?['final_total'] ?? itemMap['finalTotal'] ?? itemMap['totalPrice']);

      return CartItem(
        cartId: itemMap['cartId']?.toString() ?? UniqueKey().toString(),
        product: product,
        quantity: _toInt(itemMap['quantity']),
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

  List<Map<String, dynamic>> _extractProducts(Map<String, dynamic> ctx) {
    final raw = ctx['products'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((item) {
      final map = Map<String, dynamic>.from(item);
      return <String, dynamic>{
        'id': map['id']?.toString() ?? map['meal_id']?.toString() ?? '',
        'name': _localizedText(map['name'] ?? map['title']),
        'category': _localizedText(map['category']),
        'price': _toDouble(map['price']),
      };
    }).where((m) => (m['id'] as String).isNotEmpty).toList();
  }

  List<String> _extractCategories(Map<String, dynamic> ctx, List<Map<String, dynamic>> products) {
    final categories = <String>{};
    final rawCategories = ctx['categories'];
    if (rawCategories is List) {
      for (final item in rawCategories) {
        if (item is Map) {
          final name = _localizedText(item['name']);
          if (name.isNotEmpty) categories.add(name);
        } else if (item is String && item.trim().isNotEmpty) {
          categories.add(item.trim());
        }
      }
    }
    for (final p in products) {
      final cat = p['category']?.toString().trim() ?? '';
      if (cat.isNotEmpty) categories.add(cat);
    }
    return categories.toList()..sort();
  }

  Set<String> _extractDisabledMealIds(Map<String, dynamic> ctx) {
    final result = <String>{};
    final raw = ctx['disabled_meals'];
    if (raw is! List) return result;
    for (final item in raw) {
      if (item is! Map) continue;
      final payload = Map<String, dynamic>.from(item);
      final mealId = payload['meal_id']?.toString() ?? payload['product_id']?.toString() ?? '';
      if (mealId.isNotEmpty && payload['is_disabled'] == true) {
        result.add(mealId);
      }
    }
    return result;
  }

  String _extractCurrencySymbol(Map<String, dynamic> cart, Map<String, dynamic> ctx) {
    for (final src in [cart, ctx]) {
      for (final key in ['currency', 'currency_symbol', 'currencySymbol']) {
        final val = src[key]?.toString().trim();
        if (val != null && val.isNotEmpty) return val;
      }
    }
    return 'ر.س';
  }

  String? _extractPromoCode(Map<String, dynamic> cartData) {
    final promoMap = _asMap(cartData['promo']);
    for (final val in [promoMap?['code'], cartData['promocodeValue'], cartData['promoCode']]) {
      final text = val?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  double? _extractTaxRate(Map<String, dynamic> cartData) {
    final directRaw = cartData['tax_rate'] ?? cartData['taxRate'];
    if (directRaw != null) {
      final direct = _extractDouble(directRaw);
      if (direct <= 0) return 0.0;
      return direct > 1.0 ? (direct / 100.0).clamp(0.0, 1.0) : direct;
    }
    final percentageRaw = cartData['tax_percentage'] ?? cartData['taxPercentage'];
    if (percentageRaw != null) {
      final pct = _extractDouble(percentageRaw);
      if (pct <= 0) return 0.0;
      return (pct / 100.0).clamp(0.0, 1.0);
    }
    final subtotal = _extractDouble(cartData['subtotal']);
    final tax = _extractDouble(cartData['tax']);
    if (subtotal > 0 && tax > 0) return (tax / subtotal).clamp(0.0, 1.0);
    return null;
  }

  String _localizedText(dynamic value, {String? lang}) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is Map) {
      final code = (lang ?? _languageCode).trim().toLowerCase();
      final map = value.map((k, v) => MapEntry(k.toString(), v));
      for (final key in [code, 'en', 'ar']) {
        final text = map[key]?.toString().trim();
        if (text != null && text.isNotEmpty) return text;
      }
      for (final v in map.values) {
        final text = v?.toString().trim();
        if (text != null && text.isNotEmpty) return text;
      }
    }
    return value.toString().trim();
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
    return null;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll(RegExp(r'[^0-9.]'), '');
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0.0;
  }

  int _toInt(dynamic value) {
    if (value == null) return 1;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 1;
    return 1;
  }

  double _extractDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll(RegExp(r'[^0-9.\-]'), '');
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0.0;
  }

  bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    return const ['1', 'true', 'yes', 'on'].contains(text);
  }
}

/// Smooth animated success check using Flutter's built-in animation.
/// Circle scales up, then check icon fades in, holds, then calls onFinished.
class _SuccessCheckAnimation extends StatefulWidget {
  final VoidCallback? onFinished;

  const _SuccessCheckAnimation({this.onFinished});

  @override
  State<_SuccessCheckAnimation> createState() => _SuccessCheckAnimationState();
}

class _SuccessCheckAnimationState extends State<_SuccessCheckAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _circleController;
  late final AnimationController _checkController;
  late final Animation<double> _circleScale;
  late final Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();

    _circleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _circleScale = CurvedAnimation(
      parent: _circleController,
      curve: Curves.elasticOut,
    );
    _checkScale = CurvedAnimation(
      parent: _checkController,
      curve: Curves.easeOutBack,
    );

    // Sequence: circle pops in -> check fades in -> hold -> dismiss
    _startAnimation();
  }

  Future<void> _startAnimation() async {
    await _circleController.forward();
    if (!mounted) return;
    await _checkController.forward();
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 2000));
    if (mounted) widget.onFinished?.call();
  }

  @override
  void dispose() {
    _circleController.dispose();
    _checkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: ScaleTransition(
        scale: _circleScale,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF22C55E),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: ScaleTransition(
              scale: _checkScale,
              child: const Icon(
                Icons.check_rounded,
                size: 64,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
