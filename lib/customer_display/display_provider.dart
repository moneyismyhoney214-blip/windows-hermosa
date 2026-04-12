import 'package:flutter/foundation.dart';

enum DisplayMode { none, cds }

enum PaymentDisplayStatus { idle, processing, success, failed, cancelled }

class DisplayProvider extends ChangeNotifier {
  static const String pendingIsNewOrderEventKey = '__is_new_order_event';

  DisplayMode _currentMode = DisplayMode.none;
  Map<String, dynamic> _cartData = {};
  final List<Map<String, dynamic>> _orders = [];
  final List<Map<String, dynamic>> _pendingOrders = [];
  Map<String, dynamic> _catalogContext = {};
  String? _statusMessage;
  String _languageCode = 'ar';

  // Payment state
  PaymentDisplayStatus _paymentStatus = PaymentDisplayStatus.idle;
  Map<String, dynamic> _paymentData = {};
  String? _paymentMessage;
  Map<String, dynamic>? _transactionData;
  Map<String, dynamic>? _statusOverlay;

  DisplayMode get currentMode => _currentMode;
  Map<String, dynamic> get cartData => _cartData;
  List<Map<String, dynamic>> get orders => List.unmodifiable(_orders);
  Map<String, dynamic> get catalogContext =>
      Map<String, dynamic>.unmodifiable(_catalogContext);
  String? get statusMessage => _statusMessage;
  String get languageCode => _languageCode;

  // Payment getters
  PaymentDisplayStatus get paymentStatus => _paymentStatus;
  Map<String, dynamic> get paymentData => _paymentData;
  String? get paymentMessage => _paymentMessage;
  Map<String, dynamic>? get transactionData => _transactionData;
  bool get isShowingPayment => _paymentStatus != PaymentDisplayStatus.idle;
  bool get isPaymentProcessing =>
      _paymentStatus == PaymentDisplayStatus.processing;
  bool get isPaymentSuccess => _paymentStatus == PaymentDisplayStatus.success;
  bool get isPaymentFailed => _paymentStatus == PaymentDisplayStatus.failed;
  bool get hasStatusOverlay =>
      _statusOverlay != null && _statusOverlay!.isNotEmpty;
  Map<String, dynamic>? get statusOverlay => _statusOverlay;

  bool shouldShowIdle(DateTime now) {
    return _orders.isEmpty && _cartData.isEmpty;
  }

  void setStatusOverlay(Map<String, dynamic>? overlay) {
    final normalized = overlay?.map((k, v) => MapEntry(k.toString(), v));
    if (_statusOverlay == normalized) return;
    _statusOverlay = normalized;
    notifyListeners();
  }

  void setMode(String mode) {
    switch (mode.toUpperCase()) {
      case 'CDS':
        _currentMode = DisplayMode.cds;
        _statusMessage = 'Customer Display Mode Active';
        break;
      default:
        _currentMode = DisplayMode.none;
        _statusMessage = 'Unknown mode: $mode';
    }
    notifyListeners();
  }

  void updateCartData(Map<String, dynamic> data) {
    _cartData = Map<String, dynamic>.from(data);
    _syncLanguageFromPayload(data);
    notifyListeners();
  }

  void addOrder(Map<String, dynamic> orderData) {
    final order = Map<String, dynamic>.from(orderData);
    final orderId = order['id']?.toString().trim() ?? '';
    if (orderId.isEmpty) return;
    final normalizedStatus = _normalizedStatus(order['status']);

    if (normalizedStatus == 8) {
      removeOrder(orderId);
      return;
    }

    final index = _orders.indexWhere((row) => row['id']?.toString() == orderId);
    final isNewOrder = index < 0;
    if (!isNewOrder) {
      _orders[index] = {..._orders[index], ...order};
    } else {
      _orders.add(order);
    }

    final pendingIndex = _pendingOrders.indexWhere(
      (row) => row['id']?.toString() == orderId,
    );
    final pendingWasNew =
        pendingIndex >= 0 &&
        _pendingOrders[pendingIndex][pendingIsNewOrderEventKey] == true;
    final pendingPayload = Map<String, dynamic>.from(order)
      ..[pendingIsNewOrderEventKey] = isNewOrder || pendingWasNew;
    if (pendingIndex >= 0) {
      _pendingOrders[pendingIndex] = pendingPayload;
    } else {
      _pendingOrders.add(pendingPayload);
    }
    notifyListeners();
  }

  /// Drain pending orders in FIFO order without dropping burst events.
  List<Map<String, dynamic>> drainPendingOrders() {
    if (_pendingOrders.isEmpty) {
      return const [];
    }
    final pending = _pendingOrders
        .map((order) => Map<String, dynamic>.from(order))
        .toList(growable: false);
    _pendingOrders.clear();
    return pending;
  }

  void removeOrder(String orderId) {
    _orders.removeWhere((order) => order['id'] == orderId);
    _pendingOrders.removeWhere((order) => order['id'] == orderId);
    notifyListeners();
  }

  void applyOrderStatusUpdate(String orderId, dynamic status) {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) return;

    final statusCode = _normalizedStatus(status);
    final index = _orders.indexWhere(
      (order) => order['id']?.toString() == normalizedOrderId,
    );
    if (index < 0) return;

    final next = Map<String, dynamic>.from(_orders[index]);
    next['status'] = statusCode.toString();
    _orders[index] = next;

    final pendingIndex = _pendingOrders.indexWhere(
      (order) => order['id']?.toString() == normalizedOrderId,
    );
    final pendingWasNew =
        pendingIndex >= 0 &&
        _pendingOrders[pendingIndex][pendingIsNewOrderEventKey] == true;
    final pendingPayload = Map<String, dynamic>.from(next)
      ..[pendingIsNewOrderEventKey] = pendingWasNew;
    if (pendingIndex >= 0) {
      _pendingOrders[pendingIndex] = pendingPayload;
    } else {
      _pendingOrders.add(pendingPayload);
    }
    notifyListeners();
  }

  int _normalizedStatus(dynamic rawStatus) {
    final value = rawStatus?.toString().trim().toLowerCase() ?? '';
    switch (value) {
      case '1':
      case 'confirmed':
      case 'pending':
      case 'new':
        return 1;
      case '2':
      case 'started':
      case 'start':
      case 'in_progress':
        return 2;
      case '3':
      case 'finished':
      case 'done':
      case 'ended':
        return 3;
      case '4':
      case 'preparing':
      case 'processing':
        return 4;
      case '5':
      case 'ready':
      case 'ready_for_delivery':
        return 5;
      case '6':
      case 'on_the_way':
      case 'out_for_delivery':
        return 6;
      case '7':
      case 'completed':
        return 7;
      case '8':
      case 'cancelled':
      case 'canceled':
        return 8;
      default:
        return 1;
    }
  }

  void clearOrders() {
    _orders.clear();
    _pendingOrders.clear();
    notifyListeners();
  }

  void clearCart() {
    _cartData = {};
    notifyListeners();
  }

  void updateCatalogContext(Map<String, dynamic> context) {
    _catalogContext = Map<String, dynamic>.from(context);
    _syncLanguageFromPayload(context);
    notifyListeners();
  }

  void setLanguageCode(String languageCode) {
    final normalized = languageCode.trim().toLowerCase();
    if (normalized.isEmpty || normalized == _languageCode) return;
    _languageCode = normalized;
    notifyListeners();
  }

  void _syncLanguageFromPayload(Map<String, dynamic> payload) {
    final raw = payload['language_code'] ?? payload['lang'];
    final code = raw?.toString().trim().toLowerCase();
    if (code == null || code.isEmpty || code == _languageCode) return;
    _languageCode = code;
  }

  void applyMealAvailability({
    required String mealId,
    required bool isDisabled,
    String? mealName,
    String? categoryName,
  }) {
    if (mealId.trim().isEmpty) return;
    final next = Map<String, dynamic>.from(_catalogContext);
    final raw = next['disabled_meals'];
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          list.add(item.map((k, v) => MapEntry(k.toString(), v)));
        }
      }
    }

    list.removeWhere((item) {
      final id =
          item['meal_id']?.toString() ??
          item['product_id']?.toString() ??
          item['productId']?.toString() ??
          '';
      return id == mealId;
    });

    if (isDisabled) {
      list.add({
        'meal_id': mealId,
        'product_id': mealId,
        'meal_name': mealName ?? 'Meal',
        'category_name': categoryName,
        'is_disabled': true,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }

    next['disabled_meals'] = list;
    _catalogContext = next;
    notifyListeners();
  }

  // ========== PAYMENT METHODS ==========

  /// Start showing payment UI
  void startPayment(Map<String, dynamic> data) {
    _paymentStatus = PaymentDisplayStatus.processing;
    _paymentData = Map<String, dynamic>.from(data);
    _paymentMessage = null;
    _transactionData = null;
    debugPrint(
      'Display: Starting payment - ${data['amount']} ${data['orderNumber']}',
    );
    notifyListeners();
  }

  /// Update payment status during processing
  void updatePaymentStatus(String status, {String? message}) {
    switch (status.toLowerCase()) {
      case 'processing':
        _paymentStatus = PaymentDisplayStatus.processing;
        break;
      case 'waiting_card':
      case 'reading':
        _paymentStatus = PaymentDisplayStatus.processing;
        break;
      case 'pin_entry':
        _paymentStatus = PaymentDisplayStatus.processing;
        break;
      case 'success':
        _paymentStatus = PaymentDisplayStatus.success;
        break;
      case 'failed':
      case 'error':
        _paymentStatus = PaymentDisplayStatus.failed;
        break;
      case 'cancelled':
        _paymentStatus = PaymentDisplayStatus.cancelled;
        break;
    }
    _paymentMessage = message;
    debugPrint('Display: Payment status updated to $status');
    notifyListeners();
  }

  /// Mark payment as successful
  void setPaymentSuccess(Map<String, dynamic>? data) {
    _paymentStatus = PaymentDisplayStatus.success;
    _transactionData = data != null ? Map<String, dynamic>.from(data) : null;
    _paymentMessage = null;
    debugPrint('Display: Payment success - $data');
    notifyListeners();
  }

  /// Mark payment as failed
  void setPaymentFailed(String errorMessage) {
    _paymentStatus = PaymentDisplayStatus.failed;
    _paymentMessage = errorMessage;
    debugPrint('Display: Payment failed - $errorMessage');
    notifyListeners();
  }

  /// Cancel payment
  void cancelPayment() {
    _paymentStatus = PaymentDisplayStatus.cancelled;
    _paymentMessage = 'Payment cancelled';
    debugPrint('Display: Payment cancelled');
    notifyListeners();
  }

  /// Clear payment and return to cart view
  void clearPayment() {
    _paymentStatus = PaymentDisplayStatus.idle;
    _paymentData = {};
    _paymentMessage = null;
    _transactionData = null;
    debugPrint('Display: Payment cleared');
    notifyListeners();
  }

  void reset() {
    _currentMode = DisplayMode.none;
    _cartData = {};
    _orders.clear();
    _pendingOrders.clear();
    _catalogContext = {};
    _statusMessage = null;
    _paymentStatus = PaymentDisplayStatus.idle;
    _paymentData = {};
    _paymentMessage = null;
    _transactionData = null;
    _languageCode = 'ar';
    notifyListeners();
  }
}
