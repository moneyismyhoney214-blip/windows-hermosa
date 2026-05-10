library orders_screen;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/booking_invoice.dart';
import '../services/api/order_service.dart';
import '../services/api/base_client.dart';
import '../services/cache_service.dart';
import '../services/api/error_handler.dart';
import '../services/language_service.dart';
import '../services/app_themes.dart';
import '../services/api/api_constants.dart';
import '../services/display_app_service.dart';
import '../services/salon_invoice_events.dart';
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

  // After a salon refund the backend keeps `total_price` / `grand_total`
  // frozen at the original amount and the bookings-list endpoint may not
  // include the per-row services. These overrides hold the authoritative
  // post-refund state pulled from the booking-detail endpoint so the card
  // total + the create-invoice flow both reflect the remaining items
  // instead of the stale frozen total.
  final Map<int, double> _bookingRemainingPreTaxOverride = {};
  final Map<int, List<Map<String, dynamic>>> _bookingItemsOverride = {};

  // Pending background detail refreshes for salon bookings flagged with
  // `has_cancelled=true` — the list endpoint freezes their `total_price`
  // even though their booking_services are gone, so we lazily fetch the
  // detail to populate the override. The set guards against duplicate
  // in-flight requests when the card re-paints during scroll.
  final Set<int> _bookingDetailRefreshInFlight = {};

  // Salon-only: booking IDs that already have an invoice attached. The
  // /bookings list endpoint returns pay-now bookings without `is_paid`,
  // `has_invoice`, `invoice_id`, or any other indicator — so the orders
  // screen otherwise renders them with the "Create Invoice / Refund /
  // Cancel" buttons. Clicking Create Invoice then errors with 422
  // "booking_id already used". We resolve this by cross-referencing
  // today's invoices in a background fetch and excluding any booking
  // whose id appears there.
  final Set<int> _bookingIdsWithInvoice = <int>{};
  bool _invoiceCrossRefInFlight = false;
  StreamSubscription<SalonInvoiceCreatedEvent>? _salonInvoiceCreatedSub;

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
    // Salon-only: drain any invoice-creation events fired while this screen
    // was unmounted (the user creates the invoice from main_screen, then
    // navigates here — a stream listener can't cover that gap). Apply them
    // BEFORE _loadData so the first paint already excludes invoiced
    // bookings from the action-button list.
    if (ApiConstants.branchModule == 'salons') {
      for (final event in getIt<SalonInvoiceEvents>().recentEvents()) {
        _applySalonInvoiceEvent(event);
      }
      _salonInvoiceCreatedSub =
          getIt<SalonInvoiceEvents>().stream.listen(_onSalonInvoiceCreated);
    }
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
    _salonInvoiceCreatedSub?.cancel();
    super.dispose();
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
    // Pending Invoices tab must show only Pay-Later bookings that are
    // still awaiting an invoice. Once an invoice is posted, drop the
    // booking from the list immediately so the cashier doesn't see it
    // in both Pending and Posted at the same time.
    _bookings.removeWhere((booking) => booking.id == bookingId);
    _selectedBookingIds.remove(bookingId);
    _payingBookingIds.remove(bookingId);

    // Persist into the same map the cross-ref scan uses so re-entering the
    // screen still hides the buttons even before any network call lands.
    final invoiceIdInt = int.tryParse(event.invoiceId ?? '');
    if (invoiceIdInt != null && invoiceIdInt > 0) {
      final dateStr = _todayForApi();
      final cacheKey = _salonInvoiceLinkCacheKey(dateStr);
      // Fire-and-forget — failures here are harmless; the next cross-ref
      // scan would re-derive the entry anyway.
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
        } catch (_) {}
      }();
    }
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
