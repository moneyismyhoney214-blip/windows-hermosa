library orders_screen;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../dialogs/booking_details_dialog.dart';
import '../dialogs/booking_refund_dialog.dart';
import '../dialogs/edit_order_dialog.dart';
import '../dialogs/payment_tender_dialog.dart';
import '../locator.dart';
import '../models/booking_invoice.dart';
import '../models/receipt_data.dart';
import '../services/api/api_constants.dart';
import '../services/api/base_client.dart';
import '../services/api/branch_service.dart';
import '../services/api/device_service.dart';
import '../services/api/error_handler.dart';
import '../services/api/order_service.dart';
import '../services/app_themes.dart';
import '../services/cache_service.dart';
import '../services/cashier_mesh_bootstrap.dart';
import '../services/display_app_service.dart';
import '../services/language_service.dart';
import '../services/logger_service.dart';
import '../services/printer_role_registry.dart';
import '../services/printer_service.dart';
import '../services/salon_invoice_events.dart';
import '../utils/order_status.dart';
import '../utils/ui_feedback.dart';

part 'orders_screen_parts/orders_screen.actions.dart';
part 'orders_screen_parts/orders_screen.data.dart';
part 'orders_screen_parts/orders_screen.details.dart';
part 'orders_screen_parts/orders_screen.helpers.dart';
part 'orders_screen_parts/orders_screen.legacy.dart';
part 'orders_screen_parts/orders_screen.lifecycle.dart';
part 'orders_screen_parts/orders_screen.processing.dart';
part 'orders_screen_parts/orders_screen.utils.dart';
part 'orders_screen_parts/orders_screen.widgets.dart';

class OrdersScreen extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback? onNavigateToInvoices;

  /// Callback to print receipt using the same logic as normal payment flow.
  final Future<void> Function({
    required OrderReceiptData receiptData,
    String? invoiceId,
  })? onPrintReceipt;

  /// Callback to print order change ticket to kitchen printers.
  final void Function(
    List<OrderChange> changes,
    String orderNumber, {
    bool isFullCancel,
    String? customerName,
    String? employeeName,
  })? onPrintOrderChanges;

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
  final CacheService _cache = getIt<CacheService>();
  final DisplayAppService _displayAppService = getIt<DisplayAppService>();
  final NumberFormat _amountFormatter = NumberFormat('#,##0.##');

  List<Booking> _bookings = [];
  Map<String, dynamic> _bookingsRawResponse = {};
  Map<String, dynamic> _orderDetailsRawResponse = {};
  Map<String, dynamic> _orderInvoiceRawResponse = {};
  Map<String, dynamic> _updateStatusRawResponse = {};
  final Map<String, dynamic> _updateDataRawResponse = {};
  final Map<String, dynamic> _singleWhatsAppRawResponse = {};
  final Map<String, dynamic> _multiWhatsAppRawResponse = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  final Set<int> _selectedBookingIds = <int>{};
  final Set<int> _payingBookingIds = <int>{};
  Timer? _autoRefreshTimer;
  bool _isRealtimeRefreshing = false;

  int _bookingPage = 1;
  bool _hasMoreBookings = true;

  // Pre-tax refund totals so card totals update immediately
  final Map<int, double> _bookingRefundedAmounts = {};

  // Salon refunds freeze total_price/grand_total in the list endpoint; these overrides hold authoritative post-refund state from the detail endpoint.
  final Map<int, double> _bookingRemainingPreTaxOverride = {};
  final Map<int, List<Map<String, dynamic>>> _bookingItemsOverride = {};

  // Guards duplicate in-flight detail fetches for has_cancelled=true salon bookings (list endpoint freezes their total_price).
  final Set<int> _bookingDetailRefreshInFlight = {};

  // Salon-only cross-ref: /bookings list lacks is_paid/has_invoice/invoice_id for pay-now bookings, so we derive invoiced IDs from today's invoices to suppress Create-Invoice/Refund/Cancel buttons (avoids 422 "booking_id already used").
  final Set<int> _bookingIdsWithInvoice = <int>{};
  bool _invoiceCrossRefInFlight = false;
  StreamSubscription<SalonInvoiceCreatedEvent>? _salonInvoiceCreatedSub;

  final ScrollController _bookingScrollController = ScrollController();

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final String _selectedStatus = 'all';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    translationService.addListener(_onLanguageChanged);
    _bookingScrollController.addListener(_onBookingScroll);
    // Drain invoice-creation events fired while this screen was unmounted (stream listener can't cover that gap) BEFORE _loadData.
    if (ApiConstants.branchModule == 'salons') {
      for (final event in getIt<SalonInvoiceEvents>().recentEvents()) {
        _applySalonInvoiceEvent(event);
      }
      _salonInvoiceCreatedSub =
          getIt<SalonInvoiceEvents>().stream.listen(_onSalonInvoiceCreated);
    }
    // Realtime status push from KDS — avoids the 10s HTTP poll lag after a
    // kitchen bump (waiter would see "جاري التحضير" stale otherwise).
    _displayAppService.addOrderStatusListener(_onKdsOrderStatusChanged);
    _loadData();
    _startAutoRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // PERF: pause 10-s polling while backgrounded to save battery + API calls.
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
    _displayAppService.removeOrderStatusListener(_onKdsOrderStatusChanged);
    _bookingScrollController.dispose();
    _searchController.dispose();
    _autoRefreshTimer?.cancel();
    _salonInvoiceCreatedSub?.cancel();
    super.dispose();
  }

  void _onKdsOrderStatusChanged(String orderId, int status) {
    if (!mounted) return;
    final idx = _bookings.indexWhere((b) => b.id.toString() == orderId);
    if (idx < 0) return;
    final booking = _bookings[idx];
    final currentStatus = booking.raw['status']?.toString();
    if (currentStatus == status.toString()) return;
    setState(() {
      booking.raw['status'] = status;
      // Drop server-supplied display so Booking.statusDisplay falls back to
      // the switch and renders the new label without waiting for the next
      // 10s HTTP poll. The poll will refresh both fields authoritatively.
      booking.raw.remove('status_display');
    });
  }

  void _onSalonInvoiceCreated(SalonInvoiceCreatedEvent event) {
    if (!mounted) return;
    setState(() {
      _applySalonInvoiceEvent(event);
    });
  }

  /// Apply an invoice-creation event to local state. Safe to call from
  /// `initState` (no setState — the state is being built) or from inside a
  /// setState() in the live listener.
  void _applySalonInvoiceEvent(SalonInvoiceCreatedEvent event) {
    final bookingId = int.tryParse(event.bookingId ?? '');
    if (bookingId == null || bookingId <= 0) return;
    _bookingIdsWithInvoice.add(bookingId);
    // Drop the booking from Pending Invoices immediately so it doesn't appear in both Pending + Posted.
    _bookings.removeWhere((booking) => booking.id == bookingId);
    _selectedBookingIds.remove(bookingId);
    _payingBookingIds.remove(bookingId);

    // Persist into the cross-ref cache so re-entry hides buttons before any network call lands.
    final invoiceIdInt = int.tryParse(event.invoiceId ?? '');
    if (invoiceIdInt != null && invoiceIdInt > 0) {
      final dateStr = _todayForApi();
      final cacheKey = _salonInvoiceLinkCacheKey(dateStr);
      // Fire-and-forget — next cross-ref scan re-derives on failure.
      () async {
        try {
          final cachedRaw = await _cache.get(cacheKey);
          final merged = <String, int>{};
          if (cachedRaw is Map) {
            cachedRaw.forEach((k, v) {
              final parsed =
                  v is int ? v : int.tryParse(v?.toString() ?? '');
              if (parsed != null && parsed > 0) {
                merged[k.toString()] = parsed;
              }
            });
          }
          merged[invoiceIdInt.toString()] = bookingId;
          await _cache.set(
            cacheKey,
            merged,
            expiry: const Duration(hours: 6),
          );
        } catch (e) {
          Log.d('OrdersScreen', 'update invoice→booking cache failed (non-fatal): $e');
        }
      }();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
      // Owns its own safe-area: header paints behind the status-bar inset; body needs only the bottom home-indicator inset.
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildErrorView()
                      : _buildBookingsList(),
            ),
          ],
        ),
      ),
    );
  }
}
