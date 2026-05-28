library main_screen;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hermosa_pos/dialogs/edit_order_dialog.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';
import 'package:hermosa_pos/services/api/auth_service.dart';
import 'package:hermosa_pos/services/api/base_client.dart';
import 'package:hermosa_pos/services/api/branch_service.dart';
import 'package:hermosa_pos/services/api/device_service.dart';
import 'package:hermosa_pos/services/api/error_handler.dart';
import 'package:hermosa_pos/services/api/order_service.dart';
import 'package:hermosa_pos/services/api/product_service.dart';
import 'package:hermosa_pos/services/api/promocode_service.dart';
import 'package:hermosa_pos/services/api/table_service.dart';
import 'package:hermosa_pos/services/cashier_sound_service.dart';
import 'package:hermosa_pos/services/printer_service.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../controllers/cart_controller.dart';
import '../controllers/order_totals_calculator.dart';
import '../controllers/payment_logic.dart';
import '../controllers/payment_method_policy.dart';
import '../customer_display/nearpay/nearpay_bootstrap.dart';
import '../customer_display/nearpay/nearpay_config_service.dart';
import '../customer_display/nearpay/nearpay_service.dart' as np_local;
import '../data.dart';
import '../dialogs/booking_details_dialog.dart';
import '../dialogs/meal_details_dialog.dart';
import '../dialogs/payment_success_view.dart';
import '../dialogs/payment_tender_dialog.dart';
import '../dialogs/product_customization_dialog.dart';
import '../dialogs/salon_package_selection_dialog.dart';
import '../dialogs/salon_service_selection_dialog.dart';
import '../locator.dart';
import '../models.dart';
import '../models/booking_invoice.dart';
import '../models/customer.dart';
import '../models/receipt_data.dart';
import '../services/api/salon_employee_service.dart';
import '../services/app_themes.dart';
import '../services/cashier_mesh_bootstrap.dart';
import '../services/category_printer_route_registry.dart';
import '../services/display_app_service.dart';
import '../services/invoice_html_pdf_service.dart';
import '../services/kds_meal_availability_service.dart';
import '../services/kitchen_printer_route_registry.dart';
import '../services/language_service.dart';
import '../services/logger_service.dart';
import '../services/nearpay/nearpay_service.dart';
import '../services/presentation_service.dart';
import '../services/print_job_cache_service.dart';
import '../services/print_orchestrator_service.dart';
import '../services/printer_language_settings_service.dart';
import '../services/printer_role_registry.dart';
import '../services/receipt_builder_service.dart';
import '../services/remote_nearpay_dispatcher.dart';
import '../services/salon_invoice_events.dart';
import '../utils/display_device_selection.dart';
import '../utils/ui_feedback.dart';
import '../widgets/order_panel.dart';
import '../widgets/pdf_preview_screen.dart';
import '../widgets/product_card.dart';
import '../widgets/settings_view.dart';
import 'bookings_screen.dart';
import 'branch_selection_screen.dart';
import 'customers_screen.dart';
import 'deposits_screen.dart';
import 'invoices_screen.dart';
import 'login_screen.dart';
import 'main_screen_parts/invoice_attempts_builder.dart';
import 'main_screen_parts/payment_process_helpers.dart' as pph;
import 'orders_screen.dart';
import 'reports_screen.dart';
import 'review_tickets_screen.dart';
import 'table_management_screen.dart';

part 'main_screen_parts/main_screen.build_widgets.dart';
part 'main_screen_parts/main_screen.cart.dart';
part 'main_screen_parts/main_screen.devices.dart';
part 'main_screen_parts/main_screen.kitchen_print.dart';
part 'main_screen_parts/main_screen.kitchen_print.dispatch.dart';
part 'main_screen_parts/main_screen.kitchen_print.helpers.dart';
part 'main_screen_parts/main_screen.localization.dart';
part 'main_screen_parts/main_screen.menu_lists.dart';
part 'main_screen_parts/main_screen.payment.dart';
part 'main_screen_parts/main_screen.payment.helpers.dart';
part 'main_screen_parts/main_screen.payment.process.dart';
part 'main_screen_parts/main_screen.payment.receipt.dart';
part 'main_screen_parts/main_screen.products.dart';
part 'main_screen_parts/main_screen.promo.dart';
part 'main_screen_parts/main_screen.salon.dart';
part 'main_screen_parts/main_screen.session.dart';
part 'main_screen_parts/main_screen.settings.dart';
part 'main_screen_parts/main_screen.tax.dart';
part 'main_screen_parts/main_screen.utils.dart';

// Storage keys at library level so extensions can reference them unqualified.
const String _requireCustomerSelectionKey =
    'cashier_require_customer_selection';
// Per-branch flag set when the backend rejects a booking with a missing
// `customer_id` 422. Once tripped, the cashier treats customer selection as
// effectively mandatory on that branch and disables the settings toggle.
String _customerRequiredByBackendKeyFor(int branchId) =>
    'cashier_customer_required_by_backend_v1_$branchId';
const String _cdsEnabledKey = 'cashier_cds_enabled_v1';
const String _kdsEnabledKey = 'cashier_kds_enabled_v1';
const String _autoPrintCashierKey = 'cashier_auto_print_cashier_v1';
const String _autoPrintCustomerKey = 'cashier_auto_print_customer_v1';
const String _autoPrintCustomerSecondCopyKey =
    'cashier_auto_print_customer_second_copy_v1';
const String _printKitchenInvoicesKey =
    'cashier_print_kitchen_invoices_v1';
const String _allowPrintWithKdsKey = 'cashier_allow_print_with_kds_v1';
const String _mealIconScaleKey = 'cashier_meal_icon_scale_v1';
const String _sidebarIconScaleKey = 'cashier_sidebar_icon_scale_v1';
const String _categoryLayoutVerticalKey = 'cashier_category_layout_vertical_v1';
const String _cashFloatOpeningBalanceKey =
    'cash_float_opening_balance_v1';
const String _cashFloatTransactionsTotalKey =
    'cash_float_transactions_total_v1';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TableService _tableService = getIt<TableService>();

  String _activeTab = 'home';
  String _selectedCategory = 'all';
  String _searchQuery = '';
  Timer? _searchDebounce;

  /// CartController owns cart state; `_cart` getter exposes backing list for legacy in-place mutators.
  late final CartController _cartController = CartController();
  List<CartItem> get _cart => _cartController.mutableItems;

  final List<DeviceConfig> _devices = [];

  List<Product> _allProducts = [];
  List<CategoryModel> _categories = [];
  final Set<String> _pinnedCategoryIds = {};
  List<CategoryModel>? _sortedCategoriesCache;

  bool _isMenuListActive = false;
  int? _activeMenuListId;
  String _activeMenuListName = '';
  String _menuListPriceType = 'delivery';
  List<Product> _menuListProducts = [];
  List<CategoryModel> _menuListCategories = [];
  List<Map<String, dynamic>> _availableMenuLists = [];
  List<CategoryModel> _originalCategories = [];
  Map<String, bool> _enabledPayMethods = {
    'cash': false,
    'card': false,
    'mada': false,
    'visa': false,
    'benefit': false,
    'stc': false,
    'bank_transfer': false,
    'wallet': false,
    'cheque': false,
    'petty_cash': false,
    'pay_later': false,
    'tabby': false,
    'tamara': false,
    'keeta': false,
    'my_fatoorah': false,
    'jahez': false,
    'talabat': false,
    'hunger_station': false,
  };
  List<Map<String, dynamic>> _orderTypeOptions = [];
  TableItem? _selectedTable;
  TableItem? _lastSelectedTable;
  Customer? _selectedCustomer;

  /// Order-level promo routed through [_cartController]; null clears.
  PromoCode? get _activePromoCode => _cartController.activePromoCode;
  set _activePromoCode(PromoCode? value) {
    if (value == null) {
      _cartController.clearPromoCode();
    } else {
      _cartController.applyPromoCode(value);
    }
  }

  List<PromoCode> _cachedPromoCodes = [];
  bool _isLoading = true;
  String? _error;
  int _currentPage = 1;
  bool _isLastPage = false;
  bool _isLoadingMore = false;
  final ScrollController _productsScrollController = ScrollController();

  String _selectedOrderType = 'services';
  final TextEditingController _orderNotesController = TextEditingController();
  final TextEditingController _carNumberController = TextEditingController();

  String _userName = 'المستخدم';
  String _userRole = 'كاشير';
  String _initials = 'US';
  bool _requireCustomerSelection = true;
  // Tripped to true when the backend returns a 422 with `customer_id` errors
  // on this branch — locks the settings toggle on and forces the cart label
  // into the "* required" state without waiting for the user to toggle it.
  bool _customerRequiredByBackend = false;
  bool get _effectiveRequireCustomerSelection =>
      _requireCustomerSelection || _customerRequiredByBackend;
  bool _isCdsEnabled = true;
  bool _isKdsEnabled = true;
  bool _autoPrintCashier = true;
  bool _autoPrintCustomer = true;
  bool _autoPrintCustomerSecondCopy = false;
  bool _printKitchenInvoices = true;
  bool _allowPrintWithKds = false;
  double _mealIconScale = 1.0;
  double _sidebarIconScale = 1.0;
  bool _categoryLayoutVertical = false;
  // Init from global VAT config; overwritten by _loadTaxConfiguration once branch-settings resolves.
  bool _isTaxEnabled = ApiConstants.hasTax;
  double _taxRate = ApiConstants.effectiveTaxRate;
  bool _isProfileNearPayEnabled = false;
  String? _lastCreatedBookingId;
  String? _lastMainCartFingerprint;
  /// Cached seller info from the last successful invoice payload (tax_number, etc.)
  Map<String, dynamic>? _cachedSellerInfo;
  Map<String, dynamic>? _cachedBranchMap;
  String? _cachedBranchAddressEn;
  String? _cachedSellerNameEn;
  Map<String, dynamic>? _lastUserData;
  late final KdsMealAvailabilityService _mealAvailabilityService;
  late final DisplayAppService _displayAppService;
  bool _isBootstrappingSession = false;
  double _cashOpeningBalance = 0.0;
  double _cashTransactionsTotal = 0.0;

  bool get _isSalonMode => ApiConstants.branchModule == 'salons';
  /// Selected deposit ID for invoice integration (salon only).
  int? _selectedDepositId;
  /// Deposits for the currently selected customer (salon only).
  List<Map<String, dynamic>> _customerDeposits = [];
  /// In-flight customer id; used to discard stale deposits responses.
  String? _depositsFetchCustomerId;
  String _salonServiceType = 'services';
  List<Map<String, dynamic>> _salonServices = [];
  List<Map<String, dynamic>> _salonPackages = [];
  List<Map<String, dynamic>> _salonEmployees = [];
  int _salonCurrentPage = 1;
  int _salonLastPage = 1;
  /// service ID → list of employees who can perform that service.
  Map<int, List<Map<String, dynamic>>> _serviceEmployeeMap = {};
  /// Branch/seller logo URL — fallback image for salon services.
  String? _salonBranchLogoUrl;

  /// Salon nav: "orders"→"فواتير معلقة", "tables"→"deposits", insert "bookings"+"review_tickets" after "invoices".
  List<NavItem> get _effectiveNavItems {
    if (!_isSalonMode) return navItems;
    final mapped = navItems.map((item) {
      if (item.id == 'tables') {
        return const NavItem(
          id: 'deposits',
          icon: LucideIcons.wallet,
          label: 'deposits',
        );
      }
      return item;
    }).toList();

    final invoicesIndex = mapped.indexWhere((it) => it.id == 'invoices');
    const bookingsItem = NavItem(
      id: 'bookings',
      icon: LucideIcons.calendarCheck,
      label: 'bookings',
    );
    const reviewTicketsItem = NavItem(
      id: 'review_tickets',
      icon: LucideIcons.ticket,
      label: 'review_tickets',
    );
    if (invoicesIndex >= 0) {
      mapped.insert(invoicesIndex + 1, bookingsItem);
      mapped.insert(invoicesIndex + 2, reviewTicketsItem);
    } else {
      mapped.add(bookingsItem);
      mapped.add(reviewTicketsItem);
    }
    return mapped;
  }

  @override
  void initState() {
    super.initState();
    _mealAvailabilityService = getIt<KdsMealAvailabilityService>();
    _mealAvailabilityService.addListener(_onMealAvailabilityChanged);
    _displayAppService = getIt<DisplayAppService>();
    _displayAppService.addMealAvailabilityListener(_handleMealAvailabilitySync);
    WidgetsBinding.instance.addObserver(this);
    _cartController.addListener(_onCartChanged);
    translationService.addListener(_onLanguageChanged);
    // Re-push cart to CDS when invoice languages change.
    printerLanguageSettings.addListener(_onPrinterLanguageChanged);
    // Re-push cart when ProductService harvests new translations.
    ProductService.addCacheListener(_onProductNameCacheChanged);
    _productsScrollController.addListener(_onProductsScroll);
    unawaited(_bootstrapSessionAndLoad());
  }

  /// Folds CartController notifications into the existing setState flow.
  void _onCartChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onMealAvailabilityChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onPrinterLanguageChanged() {
    // Prime ProductService for new primary/secondary so background fetch harvests translations.
    try {
      getIt<ProductService>().primeLanguages([
        printerLanguageSettings.primary,
        if (printerLanguageSettings.allowSecondary)
          printerLanguageSettings.secondary,
      ]);
    } catch (e) {
      Log.d('MainScreen', 'primeLanguages on printer-lang change failed (non-fatal): $e');
    }
    _lastMainCartFingerprint = null;
    _syncDisplayCartFromMain();
  }

  void _onProductNameCacheChanged() {
    if (!mounted) return;
    _lastMainCartFingerprint = null;
    _syncDisplayCartFromMain();
  }

  // Order-level totals routed through [_cartController] for unified notifications.
  double get _orderDiscount => _cartController.orderDiscount;
  set _orderDiscount(double v) =>
      _cartController.setOrderDiscount(v, type: _orderDiscountType);

  DiscountType get _orderDiscountType => _cartController.orderDiscountType;
  set _orderDiscountType(DiscountType t) =>
      _cartController.setOrderDiscount(_orderDiscount, type: t);

  bool get _isOrderFree => _cartController.isOrderFree;
  set _isOrderFree(bool v) => _cartController.setOrderFree(v);
  String? _pendingPaymentTypeAfterTableSelection;
  List<Map<String, dynamic>>? _pendingPaymentPaysAfterTableSelection;
  bool _pendingPaymentShowLoadingAfterTableSelection = true;
  bool _pendingPaymentShowSuccessAfterTableSelection = true;
  bool _pendingPaymentClearCartAfterTableSelection = false;
  bool _pendingPaymentNearPayAfterTableSelection = false;
  double? _cachedGrossOrderTotal;
  int _lastCartHashForTotal = 0;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _cartController.removeListener(_onCartChanged);
    _cartController.dispose();
    translationService.removeListener(_onLanguageChanged);
    printerLanguageSettings.removeListener(_onPrinterLanguageChanged);
    ProductService.removeCacheListener(_onProductNameCacheChanged);
    _displayAppService.removeMealAvailabilityListener(
      _handleMealAvailabilitySync,
    );
    _mealAvailabilityService.removeListener(_onMealAvailabilityChanged);
    unawaited(_mealAvailabilityService.disposeService());
    getIt<DisplayAppService>().clearCallbacks();
    _productsScrollController.removeListener(_onProductsScroll);
    _productsScrollController.dispose();
    _orderNotesController.dispose();
    _carNumberController.dispose();
    // Tear down waiter-mesh viewer to stop broadcasting after logout/branch switch.
    try {
      unawaited(getIt<CashierMeshBootstrap>().stop());
    } catch (e) {
      Log.d('MainScreen', 'stop cashier mesh on dispose failed (non-fatal): $e');
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_canCallBranchApis()) {
        _loadData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_activeTab == 'deposits') {
      return DepositsScreen(
        onBack: () => setState(() => _activeTab = 'home'),
        onPrintReceipt: _autoPrintReceiptCopies,
      );
    }

    if (_activeTab == 'bookings') {
      return BookingsScreen(
        onBack: () => setState(() => _activeTab = 'home'),
        // Fan out salon turn slip to kitchen/KDS/bar printers after fresh booking.
        onPrintSalonTurnTicket: (orderId, bookingData) =>
            triggerSalonTurnPrintFromBookingResponse(
          orderId: orderId,
          bookingData: bookingData,
        ),
      );
    }

    if (_activeTab == 'review_tickets') {
      return ReviewTicketsScreen(
        onBack: () => setState(() => _activeTab = 'home'),
        onPrintSalonTurnTicket: (orderId, bookingData) =>
            triggerSalonTurnPrintFromBookingResponse(
          orderId: orderId,
          bookingData: bookingData,
        ),
      );
    }

    if (_activeTab == 'tables') {
      return TableManagementScreen(
        onBack: () => setState(() => _activeTab = 'home'),
        onPrintOrderChanges: _printOrderChangeTicket,
        onTableTap: (table) {
          Log.d('pay',
              'table tapped id=${table.id} number=${table.number} '
              'activeTab=$_activeTab pending=$_pendingPaymentTypeAfterTableSelection');
          final pendingType = _pendingPaymentTypeAfterTableSelection;
          final pendingPays = _pendingPaymentPaysAfterTableSelection;
          final pendingShowLoading =
              _pendingPaymentShowLoadingAfterTableSelection;
          final pendingShowSuccess =
              _pendingPaymentShowSuccessAfterTableSelection;
          final pendingClearCart = _pendingPaymentClearCartAfterTableSelection;
          final pendingNearPay = _pendingPaymentNearPayAfterTableSelection;
          _clearPendingPaymentAfterTableSelection();

          setState(() {
            _selectedTable = table;
            _lastSelectedTable = table;
            _selectedOrderType = _resolveOrderTypeForBooking(table);
            _activeTab = 'home';
          });

          if (pendingType == 'payment') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Log.d('pay', 'resume pending payment after table select');
              unawaited(
                _processPayment(
                  type: pendingType!,
                  pays: pendingPays,
                  showLoadingOverlay: pendingShowLoading,
                  showSuccessDialog: pendingShowSuccess,
                  clearCartOnSuccess: pendingClearCart,
                  isNearPayCardFlow: pendingNearPay,
                ),
              );
            });
          } else if (pendingType == 'open_tender') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Log.d('pay', 'resume pending open_tender after table select');
              unawaited(_handlePay());
            });
          }
        },
      );
    }

    if (_activeTab == 'orders') {
      return OrdersScreen(
        onBack: () => setState(() => _activeTab = 'home'),
        onNavigateToInvoices: () => setState(() => _activeTab = 'invoices'),
        onPrintReceipt: _autoPrintReceiptCopies,
        onPrintOrderChanges: _printOrderChangeTicket,
      );
    }

    if (_activeTab == 'invoices') {
      return InvoicesScreen(
        onBack: () => setState(() => _activeTab = 'home'),
        onPrintReceipt: _autoPrintReceiptCopies,
      );
    }

    if (_activeTab == 'customers') {
      return CustomersScreen(onBack: () => setState(() => _activeTab = 'home'));
    }

    if (_activeTab == 'settings') {
      return SettingsView(
        devices: _devices,
        categories: _categories,
        onAddDevice: _addDevice,
        onRemoveDevice: _removeDevice,
        requireCustomerSelection: _effectiveRequireCustomerSelection,
        onRequireCustomerSelectionChanged: _setRequireCustomerSelection,
        customerRequirementLocked: _customerRequiredByBackend,
        cdsEnabled: _isCdsEnabled,
        kdsEnabled: _isKdsEnabled,
        onCdsEnabledChanged: _setCdsEnabled,
        onKdsEnabledChanged: _setKdsEnabled,
        autoPrintCashier: _autoPrintCashier,
        onAutoPrintCashierChanged: _setAutoPrintCashier,
        autoPrintCustomer: _autoPrintCustomer,
        onAutoPrintCustomerChanged: _setAutoPrintCustomer,
        autoPrintCustomerSecondCopy: _autoPrintCustomerSecondCopy,
        onAutoPrintCustomerSecondCopyChanged: _setAutoPrintCustomerSecondCopy,
        printKitchenInvoices: _printKitchenInvoices,
        onPrintKitchenInvoicesChanged: _setPrintKitchenInvoices,
        allowPrintWithKds: _allowPrintWithKds,
        onAllowPrintWithKdsChanged: _setAllowPrintWithKds,
        mealIconScale: _mealIconScale,
        onMealIconScaleChanged: _setMealIconScale,
        sidebarIconScale: _sidebarIconScale,
        onSidebarIconScaleChanged: _setSidebarIconScale,
        categoryLayoutVertical: _categoryLayoutVertical,
        onCategoryLayoutVerticalChanged: _setCategoryLayoutVertical,
        onBack: () => setState(() => _activeTab = 'home'),
        onSwitchBranch: _handleSwitchBranch,
      );
    }

    if (_activeTab == 'reports') {
      return Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isSmallScreen = constraints.maxWidth < 900;
            if (isSmallScreen) {
              return Scaffold(
                appBar: AppBar(
                  title: Text(translationService.t('reports')),
                  leading: IconButton(
                    icon: const Icon(LucideIcons.chevronRight),
                    onPressed: () => setState(() => _activeTab = 'home'),
                  ),
                ),
                body: const ReportsScreen(),
              );
            }
            return SafeArea(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    color: Colors.white,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(LucideIcons.chevronRight),
                          onPressed: () =>
                              setState(() => _activeTab = 'home'),
                        ),
                        Text(
                          translationService.t('back_to_main'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Expanded(child: ReportsScreen()),
                ],
              ),
            );
          },
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 700;
        final hasPinnedSidebar = constraints.maxWidth >= 1180;
        final orderPanelWidth = _resolveOrderPanelWidth(
          constraints.maxWidth,
          hasPinnedSidebar: hasPinnedSidebar,
        );
        final cartBadgeLabel =
            _cart.length > 99 ? '99+' : _cart.length.toString();

        if (isPhone) {
          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: context.appBg,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              leading: _buildMoreMenu(iconColor: Colors.black),
              title: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  onChanged: (val) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                    if (mounted) setState(() => _searchQuery = val);
                  });
                },
                  decoration: InputDecoration(
                    hintText: translationService.t('search_placeholder'),
                    prefixIcon: const Icon(
                      LucideIcons.search,
                      size: 18,
                      color: Colors.grey,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              actions: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      icon: const Icon(
                        LucideIcons.shoppingBag,
                        color: Colors.black,
                      ),
                      onPressed: () =>
                          _scaffoldKey.currentState?.openEndDrawer(),
                    ),
                    if (_cart.isNotEmpty)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: IgnorePointer(
                          ignoring: true,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 18,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              cartBadgeLabel,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            endDrawer: Drawer(
              width:
                  constraints.maxWidth > 400 ? 380 : constraints.maxWidth * 0.9,
              child: _buildOrderPanel(),
            ),
            body: Column(
              children: [
                SizedBox(
                  height: 60,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: _effectiveNavItems.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final item = _effectiveNavItems[index];
                      final isSelected = _activeTab == item.id;
                      return ChoiceChip(
                        label: Text(_navLabel(item.id)),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) setState(() => _activeTab = item.id);
                        },
                        avatar: Icon(item.icon, size: 16),
                      );
                    },
                  ),
                ),
                if (!_isSalonMode) _buildHungerstationBar() else _buildSalonServiceTypeBar(),
                if (!_categoryLayoutVertical)
                  RepaintBoundary(child: _buildCategoryBar()),

                Expanded(
                  child: (_categoryLayoutVertical)
                      ? Row(
                          children: [
                            _buildShiftedVerticalCategoryBar(),
                            Expanded(child: _buildContent()),
                          ],
                        )
                      : _buildContent(),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: context.appBg,
          // No AppBar — SafeArea protects against notched/gesture-nav insets.
          body: SafeArea(
            child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    _buildSearchHeader(),
                    _buildNavTabs(),
                    if (!_isSalonMode) _buildHungerstationBar() else _buildSalonServiceTypeBar(),
                    if (!_categoryLayoutVertical)
                      RepaintBoundary(child: _buildCategoryBar()),

                    Expanded(
                      child: (_categoryLayoutVertical)
                          ? Row(
                              children: [
                                _buildShiftedVerticalCategoryBar(),
                                Expanded(child: _buildContent()),
                              ],
                            )
                          : _buildContent(),
                    ),
                  ],
                ),
              ),

              SizedBox(
                width: orderPanelWidth,
                child: _buildOrderPanel(),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}
