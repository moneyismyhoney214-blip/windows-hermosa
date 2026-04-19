import 'base_client.dart';
import 'api_constants.dart';

/// Service for salon-specific employee and appointment APIs
class SalonEmployeeService {
  final BaseClient _client = BaseClient();

  // PERF: in-memory cache for `getAvailableTimes`. The same
  // (employee, service, date) triple is often queried multiple times in a
  // single booking session (user flips the date picker back and forth), so
  // we memoize with a short TTL to eliminate redundant round-trips.
  static const Duration _availableTimesTtl = Duration(minutes: 2);
  final Map<String, _CachedEntry<List<Map<String, dynamic>>>>
      _availableTimesCache = {};

  /// Clear all cached available-time results (e.g. after booking creation so
  /// freshly-consumed slots disappear on the next fetch).
  void invalidateAvailableTimesCache() => _availableTimesCache.clear();

  /// Get employee options for dropdown selection.
  /// Returns list with {label, value, is_active} from /seller/filters/branches/{branchId}/allEmployees
  Future<Map<String, dynamic>> getEmployeeOptions() async {
    final response =
        await _client.get(ApiConstants.salonEmployeeOptionsEndpoint);
    if (response is Map<String, dynamic>) return response;
    // If response is a bare list, wrap it
    return {'data': response};
  }

  /// Get available time slots for an employee on a specific date for a service.
  /// API: POST /seller/bookings/branches/{branchId}/employees/{employeeId} (_method=PATCH)
  /// Returns list of {label, value} time slots.
  Future<List<Map<String, dynamic>>> getAvailableTimes({
    required int employeeId,
    required int serviceId,
    required String date,
  }) async {
    final cacheKey = '$employeeId|$serviceId|$date';
    final cached = _availableTimesCache[cacheKey];
    if (cached != null && !cached.isExpired(_availableTimesTtl)) {
      return cached.value;
    }

    final endpoint =
        ApiConstants.salonEmployeeAvailableTimesEndpoint(employeeId);
    final response = await _client.post(endpoint, {
      '_method': 'PATCH',
      'service_id': serviceId,
      'date': date,
    });
    final data = response is Map<String, dynamic>
        ? response['data']
        : response;
    List<Map<String, dynamic>> result;
    if (data is List) {
      result = data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } else {
      result = const [];
    }
    _availableTimesCache[cacheKey] = _CachedEntry(result);
    return result;
  }

  /// Get employees who can perform a specific service.
  /// API: GET /seller/bookings/branches/{branchId}/services/{serviceId}
  /// Returns list of {label, value, is_active} employees.
  Future<List<Map<String, dynamic>>> getServiceEmployees(int serviceId) async {
    final endpoint = ApiConstants.salonServiceEmployeesEndpoint(serviceId);
    final response = await _client.get(endpoint);
    final data = response is Map<String, dynamic>
        ? response['data']
        : response;
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  /// Get appointments calendar with optional filters
  Future<Map<String, dynamic>> getAppointmentsCalendar({
    String? dateFrom,
    String? dateTo,
    int? employeeId,
  }) async {
    final queryParams = <String, String>{};
    if (dateFrom != null) queryParams['date_from'] = dateFrom;
    if (dateTo != null) queryParams['date_to'] = dateTo;
    if (employeeId != null) {
      queryParams['employee_id'] = employeeId.toString();
    }

    final queryString =
        queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');
    final endpoint = queryString.isNotEmpty
        ? '${ApiConstants.salonAppointmentsCalendarEndpoint}?$queryString'
        : ApiConstants.salonAppointmentsCalendarEndpoint;

    final response = await _client.get(endpoint);
    if (response is Map<String, dynamic>) return response;
    return {'data': response};
  }

  /// Get services assigned to an employee in a branch.
  /// Returns list of service IDs this employee can perform.
  /// API: GET /seller/services/employees/{employeeId}/branches/{branchId}/edit
  Future<List<int>> getEmployeeServiceIds(int employeeId) async {
    final endpoint =
        '/seller/services/employees/$employeeId/branches/${ApiConstants.branchId}/edit';
    final response = await _client.get(endpoint);
    final data = response is Map<String, dynamic> ? response['data'] : null;
    if (data is Map<String, dynamic>) {
      final services = data['services'];
      if (services is List) {
        return services
            .map((s) => s is int ? s : int.tryParse(s.toString()) ?? 0)
            .where((id) => id > 0)
            .toList();
      }
    }
    return [];
  }

  /// Load service→employees mapping for all employees.
  /// Returns a map: { serviceId: [employeeMap, ...] }
  ///
  /// PERF: runs all `getEmployeeServiceIds` calls in parallel with Future.wait
  /// instead of sequentially awaiting each one (previous N+1 pattern took
  /// N × round-trip-latency; now takes ~1 round-trip total).
  Future<Map<int, List<Map<String, dynamic>>>> buildServiceEmployeeMap(
    List<Map<String, dynamic>> employees,
  ) async {
    final validEmployees = <MapEntry<int, Map<String, dynamic>>>[];
    for (final emp in employees) {
      final empId = emp['id'] is int
          ? emp['id'] as int
          : int.tryParse(emp['id']?.toString() ?? '') ?? 0;
      if (empId > 0) validEmployees.add(MapEntry(empId, emp));
    }

    final results = await Future.wait(
      validEmployees.map((e) async {
        try {
          return await getEmployeeServiceIds(e.key);
        } catch (_) {
          return <int>[];
        }
      }),
      eagerError: false,
    );

    final map = <int, List<Map<String, dynamic>>>{};
    for (var i = 0; i < validEmployees.length; i++) {
      final emp = validEmployees[i].value;
      for (final sId in results[i]) {
        map.putIfAbsent(sId, () => []).add(emp);
      }
    }
    return map;
  }

  // ── Deposits (عرابين) ────────────────────────────────────────────

  /// Get paginated list of deposits.
  /// API: GET /seller/branches/{branchId}/deposits?page={page}&per_page={perPage}
  Future<Map<String, dynamic>> getDeposits({
    int page = 1,
    int perPage = 15,
  }) async {
    final endpoint =
        '${ApiConstants.depositsEndpoint}?page=$page&per_page=$perPage';
    final response = await _client.get(endpoint);
    if (response is Map<String, dynamic>) return response;
    return {'data': response};
  }

  /// Get single deposit details (invoice).
  /// API: GET /seller/branches/{branchId}/deposits/{depositId}
  Future<Map<String, dynamic>> getDepositDetails(int depositId) async {
    final endpoint = ApiConstants.depositDetailsEndpoint(depositId);
    final response = await _client.get(endpoint);
    if (response is Map<String, dynamic>) return response;
    return {'data': response};
  }

  /// Create a new deposit (multipart form-data).
  /// API: POST /seller/branches/{branchId}/deposits
  Future<Map<String, dynamic>> createDeposit(
      Map<String, String> fields) async {
    final response = await _client.postMultipart(
      ApiConstants.depositsEndpoint,
      fields,
    );
    if (response is Map<String, dynamic>) return response;
    return {'data': response};
  }

  /// Get all services for dropdown (label, value, price).
  /// API: GET /seller/filters/resource/branches/{branchId}/allServices
  Future<List<Map<String, dynamic>>> getAllServices() async {
    final response = await _client.get(ApiConstants.allServicesFilterEndpoint);
    final data =
        response is Map<String, dynamic> ? response['data'] : response;
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  /// Get deposits for a specific customer (for invoice integration).
  /// API: GET /seller/filters/branches/{branchId}/allDeposits?customer_id={id}
  Future<List<Map<String, dynamic>>> getCustomerDeposits(
      int customerId) async {
    final endpoint =
        '${ApiConstants.allDepositsFilterEndpoint}?customer_id=$customerId';
    final response = await _client.get(endpoint);
    final data =
        response is Map<String, dynamic> ? response['data'] : response;
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  // ── End Deposits ──────────────────────────────────────────────────

  /// Get employee service income report
  Future<Map<String, dynamic>> getEmployeeServiceIncomeReport({
    required int employeeId,
    String? dateFrom,
    String? dateTo,
  }) async {
    final queryParams = <String, String>{};
    if (dateFrom != null) queryParams['date_from'] = dateFrom;
    if (dateTo != null) queryParams['date_to'] = dateTo;

    final queryString =
        queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');
    final baseEndpoint =
        ApiConstants.salonEmployeeServiceIncomeReportEndpoint(employeeId);
    final endpoint = queryString.isNotEmpty
        ? '$baseEndpoint?$queryString'
        : baseEndpoint;

    final response = await _client.get(endpoint);
    if (response is Map<String, dynamic>) return response;
    return {'data': response};
  }
}

class _CachedEntry<T> {
  final T value;
  final DateTime cachedAt;
  _CachedEntry(this.value) : cachedAt = DateTime.now();

  bool isExpired(Duration ttl) =>
      DateTime.now().difference(cachedAt) > ttl;
}
