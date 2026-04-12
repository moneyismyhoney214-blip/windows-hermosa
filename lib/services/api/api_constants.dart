class ApiConstants {
  // Base URLs
  static const String authBaseUrl = 'https://portal.hermosaapp.com';
  static const String baseUrl = 'https://portal.hermosaapp.com';
  static const String testBaseUrl = 'https://portal.hermosaapp.com';
  static const String customersBaseUrl = 'https://portal.hermosaapp.com';

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

  // Auth - JWT login uses different domain
  static const String jwtLoginEndpoint = '/seller/login';
  static const String logoutEndpoint = '/seller/logout';
  static const String profileEndpoint = '/seller/profile';
  static String get branchesEndpoint => '/seller/branches';
  static String get profileBranchesEndpoint => '/seller/profile/branches';
  static String get branchSettingEndpoint => '/seller/branch-setting/$branchId';

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

  // Locations
  static const String countriesEndpoint = '/countries';
  static String citiesEndpoint(int countryId) =>
      '/countries/cities?country_id=$countryId';
}
