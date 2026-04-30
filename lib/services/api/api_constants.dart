class ApiConstants {
  // Base URLs
  static const String authBaseUrl = 'https://portal.hermosaapp.com';
  static const String baseUrl = 'https://portal.hermosaapp.com';
  static const String testBaseUrl = 'https://portal.hermosaapp.com';
  static const String customersBaseUrl = 'https://portal.hermosaapp.com';
  // Forgot-password flow lives on the public API host (see HAR capture).
  static const String forgotBaseUrl = 'https://portal.hermosaapp.com';

  // API Headers
  static const String _defaultAcceptLanguage = 'ar';
  static String _acceptLanguage = _defaultAcceptLanguage;

  static String get acceptLanguage => _acceptLanguage;

  static void setAcceptLanguage(String langCode) {
    final normalized = langCode.trim().toLowerCase();
    if (normalized.isEmpty) {
      _acceptLanguage = _defaultAcceptLanguage;
      return;
    }
    _acceptLanguage = normalized;
  }

  static Map<String, String> get defaultHeaders => {
        'Accept': 'application/json',
        'Accept-Language': _acceptLanguage,
        'Accept-Platform': 'dashboard',
        'Accept-ISO': 'SAU',
      };

  // Branch ID - will be set from login response
  static int branchId = 0;

  // Seller ID - will be set from login response (User ID)
  static int sellerId = 1;

  // Currency - will be set from login response (taxObject.currency)
  static String currency = 'ر.س';

  // ── Tax configuration ─────────────────────────────────────────────────
  // All three fields are sourced from the active branch's `taxObject` at
  // login time and refreshed via `/seller/filters/branches/{id}/getTax`.
  //
  //   * `hasTax`         — branch has VAT enabled
  //   * `taxPercentage`  — integer percentage (e.g. 15 for 15% VAT)
  //   * `taxRate`        — same value as a 0.0–1.0 multiplier (15 → 0.15)
  //   * `digitsNumber`   — currency precision for displays/receipts
  //
  // Use `effectiveTaxRate` for math (returns 0 when tax is disabled) and
  // `isTaxActive` to gate UI that should disappear when the branch has
  // no VAT configured.
  static bool hasTax = true;
  static int taxPercentage = 15;
  static double taxRate = 0.15;
  static int digitsNumber = 2;

  /// Tax multiplier safe for arithmetic — always 0 when tax is disabled.
  static double get effectiveTaxRate => hasTax ? taxRate : 0.0;

  /// True when the active branch should display + calculate VAT.
  static bool get isTaxActive => hasTax && taxPercentage > 0;

  /// Round a money value to the active branch's currency precision
  /// (`digitsNumber`). Saudi Arabia → 2 decimals; Bahrain/Kuwait → 3.
  ///
  /// Critical for payment payloads: backend rejects invoices when
  /// `sum(payments) ≠ invoice.total` at the server precision, so any
  /// amount we send must already be rounded to `digitsNumber` decimals.
  static double roundMoney(double value) {
    final digits = digitsNumber.clamp(0, 6);
    return double.parse(value.toStringAsFixed(digits));
  }

  /// Format a money value for display, padded to `digitsNumber` decimals.
  static String formatMoney(double value) {
    final digits = digitsNumber.clamp(0, 6);
    return value.toStringAsFixed(digits);
  }

  // Branch module - "restaurants" or "salons", set from branch selection
  static String branchModule = '';

  // Country id of the active branch (matches `value` in
  // `portal.hermosaapp.com/countries/cities`). Drives the default
  // country code on phone-input pickers — Saudi (1) is the safe
  // fallback when the branch hasn't been resolved yet.
  static int branchCountryId = 1;

  // Whether the active branch has WhatsApp notifications enabled.
  // Sourced from `/seller/branches[*].whatsapp_status`. Used to gate the
  // waitlist (notify-when-table-ready) UI on both cashier + waiter — when
  // the branch can't send WhatsApp, hide the entry points instead of
  // surfacing a button that always errors out.
  static bool whatsappEnabled = true;

  // Whether the active branch has waiter-module features enabled.
  // Sourced from `/seller/branches[*].have_waiters` (login response is
  // missing the field — value is filled at branch-select / bootstrap from
  // the canonical `/seller/branches` payload). Restaurant-only flag —
  // when false, the cashier still shows the tables screen but hides the
  // waiter-mesh actions inside it (pickup / migrate / release / message).
  // Default `true` keeps existing behaviour for branches/older API
  // payloads that don't return the field at all.
  static bool haveWaiters = true;

  // Auth - JWT login uses different domain
  static const String jwtLoginEndpoint = '/seller/login';
  static const String logoutEndpoint = '/seller/logout';
  static const String profileEndpoint = '/seller/profile';

  // Forgot-password flow — 3 steps. Each step's response returns a
  // `signed_route` (`/seller/forgot/check?...` then `/seller/forgot/reset?...`)
  // that the next call must use verbatim — the signature + expires + account
  // id are baked into that path.
  static const String forgotEndpoint = '/seller/forgot';
  static String get branchesEndpoint => '/seller/branches';
  static String get profileBranchesEndpoint => '/seller/profile/branches';
  static String get branchSettingEndpoint => '/seller/branch-setting/$branchId';

  /// Branch tax configuration — returns `{has_tax, tax_percentage,
  /// digits_number, currency}`. Authoritative refresh source consumed by
  /// `BranchService.refreshTaxConfig`.
  static String getBranchTaxEndpoint(int id) =>
      '/seller/filters/branches/$id/getTax';

  // Promo codes
  static String get promocodesEndpoint =>
      '/seller/branches/$branchId/promocodes';
  static String get allPromocodesFilterEndpoint =>
      '/seller/filters/branches/$branchId/allPromocode';
  static String getPromoCodeEndpoint(String code) =>
      '/seller/branches/$branchId/getPromoCode?code=$code';

  // Products & Categories
  static String get categoriesEndpoint =>
      '/seller/filters/resource/branches/$branchId/categories?scope=types&type=meals&all=false';
  static String get mainCategoriesEndpoint => '/seller/main-categories';
  static String get mealCategoriesEndpoint =>
      '/seller/branches/$branchId/meal-categories';
  static String get categoriesWithMealsEndpoint =>
      '/seller/filters/resource/branches/$branchId/categories?scope=types&type=meals&all=false';
  static String get productsEndpoint => '/seller/branches/$branchId/products';
  static String get mealsEndpoint => '/seller/branches/$branchId/meals';
  static String mealsPaginatedEndpoint(int page, {int? categoryId, int perPage = 100}) {
    String endpoint = '/seller/branches/$branchId/meals?page=$page&per_page=$perPage';
    if (categoryId != null) {
      endpoint += '&category_id=$categoryId';
    }
    return endpoint;
  }

  static String mealDetailsEndpoint(String mealId) =>
      '/seller/branches/$branchId/meals/$mealId';
  static String mealAddonsEndpoint(String mealId) =>
      '/seller/branches/$branchId/meals/$mealId/mealAddons';
  static String mealOptionsEndpoint(String mealId) =>
      '/seller/branches/$branchId/meals/$mealId/options';

  // Menu Lists (Hungerstation, etc.)
  static String get menuListsEndpoint =>
      '/seller/branches/$branchId/menuLists';
  static String menuListDetailsEndpoint(int menuId) =>
      '/seller/branches/$branchId/menuLists/$menuId';

  // Orders/Bookings
  static String get bookingsEndpoint => '/seller/branches/$branchId/bookings';
  static String get bookingsPublicEndpoint => '/branches/$branchId/bookings';
  static String get bookingCreateMetadataEndpoint =>
      '/seller/branches/$branchId/bookings/create';
  static String get invoicesEndpoint => '/seller/branches/$branchId/invoices';
  static String bookingDetailsEndpoint(String orderId) =>
      '/seller/branches/$branchId/bookings/$orderId';
  static String get calculateInvoiceEndpoint =>
      '/seller/calculate/branches/$branchId/invoices';
  static String invoiceDetailsEndpoint(String invoiceId) =>
      '/seller/branches/$branchId/invoices/$invoiceId';
  static String invoicePdfEndpoint(String invoiceId) =>
      '/seller/branches/$branchId/invoices/$invoiceId/pdf';
  static String invoicePdfWithWhatsAppEndpoint(String invoiceId) =>
      '/seller/branches/$branchId/invoices/$invoiceId/pdf/1';
  static String invoiceEmployeesEndpoint(String invoiceId) =>
      '/seller/employees/branches/$branchId/invoices/$invoiceId';
  static const String sendInvoiceWhatsAppEndpoint =
      '/seller/invoices/send-whatsapp';
  static String bookingInvoiceEndpoint(String orderId) =>
      '/seller/invoices/branches/$branchId/bookings/$orderId';
  static String bookingRefundEndpoint(String orderId) =>
      '/seller/refund/branches/$branchId/bookings/$orderId';
  static String invoiceRefundEndpoint(String invoiceId) =>
      '/seller/refund/branches/$branchId/invoices/$invoiceId';
  static String refundedMealsEndpoint({
    String? bookingId,
    String? invoiceId,
  }) {
    final queryParams = <String, String>{};
    final normalizedBookingId = bookingId?.trim() ?? '';
    final normalizedInvoiceId = invoiceId?.trim() ?? '';

    if (normalizedBookingId.isNotEmpty) {
      queryParams['booking_id'] = normalizedBookingId;
    } else if (normalizedInvoiceId.isNotEmpty) {
      queryParams['invoice_id'] = normalizedInvoiceId;
    }

    final query = Uri(queryParameters: queryParams).query;
    final endpoint = '/seller/refunded-meals/branches/$branchId';
    return query.isEmpty ? endpoint : '$endpoint?$query';
  }

  static String bookingPrintCountEndpoint(String orderId) =>
      '/seller/booking-update-print-count/$orderId';
  static String sendOrderWhatsAppEndpoint(String orderId) =>
      '/seller/booking/send-whatsapp/$orderId';
  static String sendMultiOrdersWhatsAppEndpoint() =>
      '/seller/booking/send-multi-whatsapp/$branchId';
  static String get printersEndpoint => '/seller/branches/$branchId/printers';
  static String printerDetailsEndpoint(String printerId) =>
      '/seller/branches/$branchId/printers/$printerId';
  static String get kitchensEndpoint => '/seller/branches/$branchId/kitchens';
  static String kitchenDetailsEndpoint(String kitchenId) =>
      '/seller/branches/$branchId/kitchens/$kitchenId';
  static const String kitchenReceiptGenerateByBookingEndpoint =
      '/seller/kitchen-receipts/generate-by-booking';
  static const String getTypesEndpoint = '/seller/get-types';

  // Tables
  static String get tablesEndpoint =>
      '/seller/branches/$branchId/restaurantTables';

  // Reports
  static String get salesReportsEndpoint =>
      '/seller/branches/$branchId/salesReports';
  static String get salesReportsDetailsEndpoint =>
      '/seller/branches/$branchId/sales_reports/get_details';
  static String get buysReportsEndpoint =>
      '/seller/branches/$branchId/buysReports';
  static String get buysReportsDetailsEndpoint =>
      '/seller/branches/$branchId/buys_reports/get_details';
  static String get taxDeclarationReportEndpoint =>
      '/seller/branches/$branchId/taxDeclarationReport';
  static String get incomingMonthlyReportEndpoint =>
      '/seller/branches/$branchId/incomingMonthlyReport';
  static String get salesPayEndpoint => '/seller/branches/$branchId/salesPay';
  static String get salesPayWithTimeEndpoint =>
      '/seller/branches/$branchId/salesPayWithTime';
  static String get employeesReportEndpoint =>
      '/seller/branches/$branchId/employeesReport';
  static String get productsReportEndpoint =>
      '/seller/branches/$branchId/productsReport';
  static String get categoriesReportEndpoint =>
      '/seller/branches/$branchId/categoriesReport';
  static String get sendReportWhatsAppEndpoint =>
      '/seller/reports/send-whatsapp';

  // Daily Closing Reports - تقارير الإقفالية اليومية
  static String get salesPayReportEndpoint =>
      '/seller/branches/$branchId/salesPay';
  static String get salesPaySummaryEndpoint =>
      '/seller/branches/$branchId/salesPaySummary';
  static String get salesPaySummaryWithTimeEndpoint =>
      '/seller/branches/$branchId/salesPaySummaryWithTime';
  static String get buysPayReportEndpoint =>
      '/seller/branches/$branchId/buysPay';
  static String get productsPayReportEndpoint =>
      '/seller/branches/$branchId/productsPay';
  static String get categoriesPayReportEndpoint =>
      '/seller/branches/$branchId/categoriesPay';
  static String get employeesPayReportEndpoint =>
      '/seller/branches/$branchId/employeesPay';
  static String get mealsPayReportEndpoint =>
      '/seller/branches/$branchId/mealsPay';
  static String get dailyInvoicesEndpoint =>
      '/seller/branches/$branchId/invoices';
  static String get invoiceStatisticsEndpoint =>
      '/seller/statistics/branches/$branchId/invoices';
  static String get depositsEndpoint => '/seller/branches/$branchId/deposits';
  static String get depositsStatisticsEndpoint =>
      '/seller/statistics/branches/$branchId/deposits';
  static String get depositRefundsEndpoint =>
      '/seller/branches/$branchId/depositRefunds';
  static String get outgoingsEndpoint => '/seller/branches/$branchId/outgoings';
  static String get outgoingsStatisticsEndpoint =>
      '/seller/statistics/branches/$branchId/outgoings';

  // Payment Methods
  static String get payMethodsEndpoint =>
      '/seller/filters/branches/$branchId/payMethods';

  // NearPay Auth
  static const String nearPayAuthTokenEndpoint = '/nearpay/auth/token';

  // NearPay Sessions & Transactions
  static const String nearPayPurchaseSessionEndpoint =
      '/seller/nearpay/session/purchase';
  static const String nearPayRefundSessionEndpoint =
      '/seller/nearpay/session/refund';
  static String nearPaySessionStatusEndpoint(String sessionId) =>
      '/seller/nearpay/session/$sessionId';
  static String get nearPayTransactionsEndpoint =>
      '/seller/nearpay/transactions';
  static String nearPayTransactionByIdEndpoint(String transactionId) =>
      '/seller/nearpay/transactions/$transactionId';

  // Customers (Test Server)
  static String customersEndpoint(int sellerId) =>
      '/seller/sellers/$sellerId/customers';
  static String customerDetailsEndpoint(int sellerId, int customerId) =>
      '/seller/sellers/$sellerId/customers/$customerId';

  // Salon - Categories & Services
  static String get serviceCategoriesEndpoint =>
      '/seller/filters/resource/branches/$branchId/categories?scope=types&type=services&all=false';

  // Salon - Employees & Appointments
  static String get salonEmployeeOptionsEndpoint =>
      '/seller/filters/branches/$branchId/allEmployees';
  static String salonEmployeeAvailableTimesEndpoint(int employeeId) =>
      '/seller/bookings/branches/$branchId/employees/$employeeId';
  static String salonServiceEmployeesEndpoint(int serviceId) =>
      '/seller/bookings/branches/$branchId/services/$serviceId';
  static String get salonAppointmentsCalendarEndpoint =>
      '/seller/branches/$branchId/appointments';
  static String salonEmployeeServiceIncomeReportEndpoint(int employeeId) =>
      '/seller/incomingServiceReport/branches/$branchId/employees/$employeeId';

  // Deposits (عرابين)
  static String depositDetailsEndpoint(int depositId) =>
      '/seller/branches/$branchId/deposits/$depositId';
  static String get allServicesFilterEndpoint =>
      '/seller/filters/resource/branches/$branchId/allServices';
  static String get allDepositsFilterEndpoint =>
      '/seller/filters/branches/$branchId/allDeposits';

  // Locations
  static const String countriesEndpoint = '/countries';
  static String citiesEndpoint(int countryId) =>
      '/countries/cities?country_id=$countryId';

  // ── Offline Sync API ──
  static const String syncManifestEndpoint = '/sync/manifest';
  static String syncResourceEndpoint(String resource, {String? cursor}) {
    final base = '/sync/resources/$resource';
    if (cursor != null && cursor.isNotEmpty) return '$base?cursor=$cursor';
    return '$base?cursor=';
  }
  static const String syncPosEndpoint = '/sync/pos';
  static const String syncLoginEndpoint = '/login';
  static const String syncLogoutEndpoint = '/logout';
}
