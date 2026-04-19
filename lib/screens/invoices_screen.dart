library invoices_screen;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../dialogs/booking_details_dialog.dart';
import '../dialogs/invoice_details_dialog.dart';
import '../dialogs/invoice_refund_dialog.dart';
import '../models/booking_invoice.dart';
import '../models/receipt_data.dart';
import '../services/api/api_constants.dart';
import '../services/api/base_client.dart';
import '../services/api/error_handler.dart';
import '../services/api/order_service.dart';
import '../services/api/branch_service.dart';
import '../services/display_app_service.dart';
import '../services/invoice_preview_helper.dart';
import '../services/language_service.dart';
import '../services/app_themes.dart';
import '../locator.dart';

part 'invoices_screen_parts/invoices_screen.helpers.dart';
part 'invoices_screen_parts/invoices_screen.data_loading.dart';
part 'invoices_screen_parts/invoices_screen.payment_resolvers.dart';
part 'invoices_screen_parts/invoices_screen.invoice_state.dart';
part 'invoices_screen_parts/invoices_screen.actions.dart';
part 'invoices_screen_parts/invoices_screen.widgets.dart';
part 'invoices_screen_parts/invoices_screen.refunded_meals_dialog.dart';

const int _perPage = 20;

class InvoicesScreen extends StatefulWidget {
  final VoidCallback onBack;

  /// Callback to print receipt using the same logic as normal payment flow.
  final Future<void> Function({
    required OrderReceiptData receiptData,
    String? invoiceId,
  })? onPrintReceipt;

  const InvoicesScreen({
    super.key,
    required this.onBack,
    this.onPrintReceipt,
  });

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen>
    with WidgetsBindingObserver {
  final OrderService _orderService = getIt<OrderService>();
  final DisplayAppService _displayAppService = getIt<DisplayAppService>();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  final NumberFormat _amountFormatter = NumberFormat('#,##0.##');

  List<Invoice> _invoices = [];
  final Set<int> _refundingInvoiceIds = <int>{};
  Timer? _autoRefreshTimer;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isSendingWhatsApp = false;
  bool _invoiceHelperSupported = true;
  bool _hasMore = true;
  String? _error;
  String _activeDate = '';

  int _page = 1;

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeDate = _todayForApi();
    _scrollController.addListener(_onScroll);
    _loadInvoices(reset: true);
    _startAutoRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // PERF: pause the 15-s polling timer when the app is backgrounded/hidden
    // so we stop burning battery and network on an unseen screen.
    if (state == AppLifecycleState.resumed) {
      _startAutoRefresh();
    } else {
      _autoRefreshTimer?.cancel();
    }
  }

  @override

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorView()
                    : _buildInvoicesList(),
          ),
        ],
      ),
    );
  }


}
