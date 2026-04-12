import 'base_client.dart';
import 'api_constants.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';

/// Service for filter/lookup data APIs
class FilterService {
  final BaseClient _client = BaseClient();
  final OfflineDatabaseService _offlineDb = OfflineDatabaseService();
  final ConnectivityService _connectivity = ConnectivityService();

  /// Get payment methods available for the branch (offline-first)
  Future<Map<String, dynamic>> getPaymentMethods({
    String? type,
    bool withoutDeferred = true,
  }) async {
    // OFFLINE MODE
    if (_connectivity.isOffline) {
      final local =
          await _offlineDb.getPaymentMethods(ApiConstants.branchId);
      return {'data': local, '_offline': true};
    }

    final queryParams = <String, String>{};
    if (type != null) queryParams['type'] = type;
    if (withoutDeferred) queryParams['without_deferred'] = 'true';

    final queryString =
        queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');
    final endpoint = queryString.isNotEmpty
        ? '${ApiConstants.payMethodsEndpoint}?$queryString'
        : ApiConstants.payMethodsEndpoint;

    try {
      final response = await _client.get(endpoint);
      // Save to SQLite for offline
      if (response is Map && response['data'] is List) {
        await _offlineDb.savePaymentMethods(
          (response['data'] as List).cast<Map<String, dynamic>>(),
          ApiConstants.branchId,
        );
      }
      return response;
    } catch (e) {
      final local =
          await _offlineDb.getPaymentMethods(ApiConstants.branchId);
      if (local.isNotEmpty) return {'data': local, '_offline': true};
      rethrow;
    }
  }

  /// Get all customers for the branch
  Future<Map<String, dynamic>> getCustomers({
    String? search,
    String? id,
  }) async {
    final queryParams = <String, String>{};
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (id != null && id.isNotEmpty) queryParams['id'] = id;

    final queryString =
        queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');
    final endpoint = queryString.isNotEmpty
        ? '/seller/filters/branches/${ApiConstants.branchId}/allCustomers?$queryString'
        : '/seller/filters/branches/${ApiConstants.branchId}/allCustomers';

    return await _client.get(endpoint);
  }

  /// Get all employees/cashiers for the branch
  Future<Map<String, dynamic>> getEmployees({
    bool? isActive,
  }) async {
    final queryParams = <String, String>{};
    if (isActive != null) queryParams['is_active'] = isActive.toString();

    final queryString =
        queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');
    final endpoint = queryString.isNotEmpty
        ? '/seller/filters/branches/${ApiConstants.branchId}/allEmployees?$queryString'
        : '/seller/filters/branches/${ApiConstants.branchId}/allEmployees';

    return await _client.get(endpoint);
  }

  /// Get all invoices for filter dropdown
  Future<Map<String, dynamic>> getInvoicesForFilter({
    String? search,
    String? id,
  }) async {
    final queryParams = <String, String>{};
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (id != null && id.isNotEmpty) queryParams['id'] = id;

    final queryString =
        queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');
    final endpoint = queryString.isNotEmpty
        ? '/seller/filters/branches/${ApiConstants.branchId}/allInvoices?$queryString'
        : '/seller/filters/branches/${ApiConstants.branchId}/allInvoices';

    return await _client.get(endpoint);
  }

  /// Get all meals for filter dropdown
  Future<Map<String, dynamic>> getMealsForFilter() async {
    return await _client
        .get('/seller/filters/branches/${ApiConstants.branchId}/allMeals');
  }

  /// Get all promo codes
  Future<Map<String, dynamic>> getPromoCodes() async {
    return await _client
        .get('/seller/filters/branches/${ApiConstants.branchId}/allPromocode');
  }

  /// Get outgoing types
  Future<Map<String, dynamic>> getOutgoingTypes() async {
    return await _client.get(
        '/seller/filters/branches/${ApiConstants.branchId}/allOutgoingTypes');
  }

  /// Get companies list
  Future<Map<String, dynamic>> getCompanies() async {
    return await _client
        .get('/seller/filters/branches/${ApiConstants.branchId}/allCompanies');
  }

  /// Get suppliers list
  Future<Map<String, dynamic>> getSuppliers() async {
    return await _client
        .get('/seller/filters/branches/${ApiConstants.branchId}/allSuppliers');
  }

  /// Get units
  Future<Map<String, dynamic>> getUnits() async {
    return await _client
        .get('/seller/filters/branches/${ApiConstants.branchId}/units');
  }

  /// Get resource categories
  Future<Map<String, dynamic>> getResourceCategories({
    String? scope,
    String? type,
    bool? all,
  }) async {
    final queryParams = <String, String>{};
    if (scope != null) queryParams['scope'] = scope;
    if (type != null) queryParams['type'] = type;
    if (all != null) queryParams['all'] = all.toString();

    final queryString =
        queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');
    final endpoint = queryString.isNotEmpty
        ? '/seller/filters/resource/branches/${ApiConstants.branchId}/categories?$queryString'
        : '/seller/filters/resource/branches/${ApiConstants.branchId}/categories';

    return await _client.get(endpoint);
  }

  /// Get resource meals
  Future<Map<String, dynamic>> getResourceMeals() async {
    return await _client.get(
        '/seller/filters/resource/branches/${ApiConstants.branchId}/allMeals');
  }

  /// Get resource suppliers
  Future<Map<String, dynamic>> getResourceSuppliers() async {
    return await _client.get(
        '/seller/filters/resource/branches/${ApiConstants.branchId}/allSuppliers');
  }

  /// Get all cashiers
  Future<Map<String, dynamic>> getAllCashiers() async {
    return await _client
        .get('/seller/filters/branches/${ApiConstants.branchId}/allCashiers');
  }
}
