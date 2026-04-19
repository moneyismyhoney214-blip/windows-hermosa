import 'base_client.dart';
import 'api_constants.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';

class ReportService {
  final BaseClient _client = BaseClient();
  final OfflineDatabaseService _offlineDb = OfflineDatabaseService();
  final ConnectivityService _connectivity = ConnectivityService();

  /// Generic offline-aware GET that caches results in SQLite.
  ///
  /// The cache key is scoped by the effective language so a report fetched
  /// in Arabic doesn't get handed back to a later English-language request.
  /// When [acceptLanguage] is supplied we force that exact locale on this
  /// single request (and its cache bucket) — this is how the reports screen
  /// prints category names in the printer language no matter what the app
  /// UI language happens to be.
  Future<Map<String, dynamic>> _offlineGet(
      String endpoint, String cacheKey,
      {String? acceptLanguage}) async {
    final effectiveLang = (acceptLanguage?.trim().isNotEmpty == true)
        ? acceptLanguage!.trim().toLowerCase()
        : ApiConstants.acceptLanguage;
    final scopedKey = '${cacheKey}__$effectiveLang';
    if (_connectivity.isOffline) {
      final cached =
          await _offlineDb.getCachedReport(scopedKey, ApiConstants.branchId);
      if (cached != null) return cached;
      return {'data': [], '_offline': true};
    }

    try {
      final response = await _client.get(
        endpoint,
        headers: acceptLanguage?.trim().isNotEmpty == true
            ? {'Accept-Language': acceptLanguage!.trim().toLowerCase()}
            : null,
      );
      if (response is Map<String, dynamic>) {
        await _offlineDb.cacheReport(
            scopedKey, response, ApiConstants.branchId);
        return response;
      }
      return {'data': response};
    } catch (e) {
      final cached =
          await _offlineDb.getCachedReport(scopedKey, ApiConstants.branchId);
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Get sales report summary
  Future<Map<String, dynamic>> getSalesReport({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.salesReportsEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'sales_report_${dateFrom}_$dateTo');
  }

  /// Get detailed sales report
  Future<Map<String, dynamic>> getSalesReportDetails({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.salesReportsDetailsEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'sales_details_${dateFrom}_$dateTo');
  }

  /// Get purchases report
  Future<Map<String, dynamic>> getPurchasesReport({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.buysReportsEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'purchases_${dateFrom}_$dateTo');
  }

  /// Get purchases report details
  Future<Map<String, dynamic>> getPurchasesReportDetails({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.buysReportsDetailsEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'purchases_details_${dateFrom}_$dateTo');
  }

  /// Get employees report
  Future<Map<String, dynamic>> getEmployeesReport({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.employeesReportEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'employees_${dateFrom}_$dateTo');
  }

  /// Get products report
  Future<Map<String, dynamic>> getProductsReport({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.productsReportEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'products_${dateFrom}_$dateTo');
  }

  /// Get categories report
  Future<Map<String, dynamic>> getCategoriesReport({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.categoriesReportEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'categories_${dateFrom}_$dateTo');
  }

  /// Send report via WhatsApp
  Future<Map<String, dynamic>> sendReportViaWhatsApp({
    required String dateFrom,
    required String dateTo,
    required String phoneNumber,
  }) async {
    final endpoint = ApiConstants.sendReportWhatsAppEndpoint;
    return await _client.post(endpoint, {
      'date_from': dateFrom,
      'date_to': dateTo,
      'phone': phoneNumber,
    });
  }

  /// Get sales by payment method summary
  Future<Map<String, dynamic>> getSalesByPaymentMethod({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.salesPayEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'sales_pay_${dateFrom}_$dateTo');
  }

  /// Get sales payments with time
  Future<Map<String, dynamic>> getSalesPaymentsWithTime({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.salesPayWithTimeEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'sales_pay_time_${dateFrom}_$dateTo');
  }

  /// Get sales summary details
  Future<Map<String, dynamic>> getSalesSummaryDetails({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.salesReportsDetailsEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'sales_summary_${dateFrom}_$dateTo');
  }

  // ==================== Daily Closing Reports - تقارير الإقفالية اليومية ====================

  /// Get sales by payment method report (Daily Closing)
  Future<Map<String, dynamic>> getDailyClosingSalesPayReport({
    required String dateFrom,
    required String dateTo,
    String? cashierId,
    String? acceptLanguage,
  }) async {
    String endpoint =
        '${ApiConstants.salesPayReportEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    if (cashierId != null && cashierId.isNotEmpty) {
      endpoint += '&cashier_id=$cashierId';
    }
    return _offlineGet(endpoint, 'daily_closing_${dateFrom}_${dateTo}_$cashierId',
        acceptLanguage: acceptLanguage);
  }

  /// Send daily closing report via WhatsApp
  Future<Map<String, dynamic>> sendDailyClosingReportWhatsApp({
    required String dateFrom,
    required String dateTo,
    String? cashierId,
  }) async {
    String endpoint =
        '${ApiConstants.salesPayReportEndpoint}?date_from=$dateFrom&date_to=$dateTo&send=1';
    if (cashierId != null && cashierId.isNotEmpty) {
      endpoint += '&cashier_id=$cashierId';
    }
    return await _client.get(endpoint);
  }

  /// Get sales pay summary
  Future<Map<String, dynamic>> getSalesPaySummary() async {
    return _offlineGet(ApiConstants.salesPaySummaryEndpoint, 'sales_pay_summary');
  }

  /// Get sales pay summary with time
  Future<Map<String, dynamic>> getSalesPaySummaryWithTime() async {
    return _offlineGet(ApiConstants.salesPaySummaryWithTimeEndpoint, 'sales_pay_summary_time');
  }

  /// Get purchases by payment method report
  Future<Map<String, dynamic>> getBuysPayReport({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.buysPayReportEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'buys_pay_${dateFrom}_$dateTo');
  }

  /// Get products by payment method report
  Future<Map<String, dynamic>> getProductsPayReport({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.productsPayReportEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'products_pay_${dateFrom}_$dateTo');
  }

  /// Get categories by payment method report
  Future<Map<String, dynamic>> getCategoriesPayReport({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.categoriesPayReportEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'categories_pay_${dateFrom}_$dateTo');
  }

  /// Get categories sales report (meals breakdown by category)
  Future<Map<String, dynamic>> getCategoriesSalesReport({
    required String dateFrom,
    required String dateTo,
    String? cashierId,
    String? acceptLanguage,
  }) async {
    String endpoint =
        '/seller/branches/${ApiConstants.branchId}/categories?all=true&category=meals&type=meals&date_from=$dateFrom&date_to=$dateTo';
    if (cashierId != null && cashierId.isNotEmpty) {
      endpoint += '&cashier_id=$cashierId';
    }
    try {
      return await _offlineGet(endpoint, 'categories_sales_${dateFrom}_$dateTo',
          acceptLanguage: acceptLanguage);
    } catch (_) {
      return {'data': {}};
    }
  }

  /// Get employees by payment method report
  Future<Map<String, dynamic>> getEmployeesPayReport({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.employeesPayReportEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'employees_pay_${dateFrom}_$dateTo');
  }

  /// Get meals by payment method report
  Future<Map<String, dynamic>> getMealsPayReport({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.mealsPayReportEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'meals_pay_${dateFrom}_$dateTo');
  }

  /// Get daily invoices list
  Future<Map<String, dynamic>> getDailyInvoices({
    required String dateFrom,
    required String dateTo,
    int perPage = 50,
  }) async {
    final endpoint =
        '${ApiConstants.dailyInvoicesEndpoint}?date_from=$dateFrom&date_to=$dateTo&per_page=$perPage';
    return _offlineGet(endpoint, 'daily_invoices_${dateFrom}_$dateTo');
  }

  /// Get invoices statistics
  Future<Map<String, dynamic>> getInvoiceStatistics({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.invoiceStatisticsEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'invoice_stats_${dateFrom}_$dateTo');
  }

  /// Get deposits list
  Future<Map<String, dynamic>> getDeposits({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.depositsEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'deposits_${dateFrom}_$dateTo');
  }

  /// Get deposits statistics
  Future<Map<String, dynamic>> getDepositsStatistics({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.depositsStatisticsEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'deposits_stats_${dateFrom}_$dateTo');
  }

  /// Get deposit refunds list
  Future<Map<String, dynamic>> getDepositRefunds({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.depositRefundsEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'deposit_refunds_${dateFrom}_$dateTo');
  }

  /// Get outgoings list
  Future<Map<String, dynamic>> getOutgoings({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.outgoingsEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'outgoings_${dateFrom}_$dateTo');
  }

  /// Get outgoings statistics
  Future<Map<String, dynamic>> getOutgoingsStatistics({
    required String dateFrom,
    required String dateTo,
  }) async {
    final endpoint =
        '${ApiConstants.outgoingsStatisticsEndpoint}?date_from=$dateFrom&date_to=$dateTo';
    return _offlineGet(endpoint, 'outgoings_stats_${dateFrom}_$dateTo');
  }
}
