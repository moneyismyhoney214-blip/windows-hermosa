library orders_screen;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/booking_invoice.dart';
import '../services/api/order_service.dart';
import '../services/api/base_client.dart';
import '../services/api/error_handler.dart';
import '../services/language_service.dart';
import '../services/app_themes.dart';
import '../services/api/api_constants.dart';
import '../services/display_app_service.dart';
import '../dialogs/booking_details_dialog.dart';
import '../dialogs/edit_order_dialog.dart';
import '../locator.dart';
import '../dialogs/payment_tender_dialog.dart';
import '../dialogs/booking_refund_dialog.dart';
import '../utils/order_status.dart';
import '../services/api/branch_service.dart';
import '../services/api/device_service.dart';
import '../services/printer_service.dart';
import '../services/printer_role_registry.dart';
import '../models/receipt_data.dart';

part 'orders_screen_parts/orders_screen.helpers.dart';
part 'orders_screen_parts/orders_screen.lifecycle.dart';
part 'orders_screen_parts/orders_screen.data.dart';
part 'orders_screen_parts/orders_screen.processing.dart';
part 'orders_screen_parts/orders_screen.widgets.dart';
part 'orders_screen_parts/orders_screen.actions.dart';
part 'orders_screen_parts/orders_screen.details.dart';
part 'orders_screen_parts/orders_screen.utils.dart';
part 'orders_screen_parts/orders_screen.legacy.dart';

class OrdersScreen extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback? onNavigateToInvoices;

  /// Callback to print receipt using the same logic as normal payment flow.
  final Future<void> Function({
    required OrderReceiptData receiptData,
    String? invoiceId,
  })? onPrintReceipt;

  /// Callback to print order change ticket to kitchen printers.
  final void Function(List<OrderChange> changes, String orderNumber, {bool isFullCancel})? onPrintOrderChanges;

  const OrdersScreen({
    super.key,
    required this.onBack,
    this.onNavigateToInvoices,
    this.onPrintReceipt,
    this.onPrintOrderChanges,
  });

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with WidgetsBindingObserver {
  final OrderService _orderService = getIt<OrderService>();
  final DisplayAppService _displayAppService = getIt<DisplayAppService>();
  final NumberFormat _amountFormatter = NumberFormat('#,##0.##');

  List<Booking> _bookings = [];
  Map<String, dynamic> _bookingsRawResponse = {};
  Map<String, dynamic> _orderDetailsRawResponse = {};
  Map<String, dynamic> _orderInvoiceRawResponse = {};
  Map<String, dynamic> _updateStatusRawResponse = {};
  Map<String, dynamic> _updateDataRawResponse = {};
  Map<String, dynamic> _singleWhatsAppRawResponse = {};
  Map<String, dynamic> _multiWhatsAppRawResponse = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  final Set<int> _selectedBookingIds = <int>{};
  final Set<int> _payingBookingIds = <int>{};
  Timer? _autoRefreshTimer;
  bool _isRealtimeRefreshing = false;

  // Pagination
  int _bookingPage = 1;
  bool _hasMoreBookings = true;

  // Track refunded amounts locally (pre-tax) so card totals update immediately
  final Map<int, double> _bookingRefundedAmounts = {};

  final ScrollController _bookingScrollController = ScrollController();

  // Filters
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatus = 'all';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    translationService.addListener(_onLanguageChanged);
    _bookingScrollController.addListener(_onBookingScroll);
    _loadData();
    _startAutoRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // PERF: pause the 10-s polling timer while the app is backgrounded/hidden
    // so we don't drain battery and fire needless API calls.
    if (state == AppLifecycleState.resumed) {
      _startAutoRefresh();
    } else {
      _autoRefreshTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    translationService.removeListener(_onLanguageChanged);
    _bookingScrollController.dispose();
    _searchController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
      body: Column(
        children: [
          // Header
          _buildHeader(),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorView()
                    : _buildBookingsList(),
          ),
        ],
      ),
    );
  }
}
