import '../../models/customer.dart';
import '../../models/location.dart';
import 'api_constants.dart';
import 'base_client.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:hermosa_pos/services/offline/offline_pos_database.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';

class CustomerService {
  final BaseClient _client = BaseClient();
  final OfflineDatabaseService _offlineDb = OfflineDatabaseService();
  final OfflinePosDatabase _posDb = OfflinePosDatabase();
  final ConnectivityService _connectivity = ConnectivityService();

  /// The base URL for customer API (test server)
  static const String _baseUrl = ApiConstants.customersBaseUrl;

  String _resolveCustomerType(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? 'individual' : normalized;
  }

  Future<List<Customer>> getCustomers({int page = 1, String? search}) async {
    // OFFLINE MODE: Return from local database
    if (_connectivity.isOffline) {
      return _getCustomersOffline(search: search);
    }

    final sellerId = ApiConstants.sellerId;
    final branchId = ApiConstants.branchId;
    final queryParams = <String, String>{'page': page.toString()};
    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }

    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    final primaryEndpoint = '/seller/sellers/$sellerId/customers?$queryString';
    final fallbackEndpoint = search != null && search.isNotEmpty
        ? '/seller/filters/branches/$branchId/allCustomers?search=${Uri.encodeComponent(search)}'
        : '/seller/filters/branches/$branchId/allCustomers';

    final endpoints = [primaryEndpoint, fallbackEndpoint];

    for (final endpoint in endpoints) {
      try {
        final response = await _client.get(endpoint, skipGlobalAuth: false);
        final customers = _parseCustomersResponse(response);
        if (customers.isNotEmpty) {
          // Save to SQLite for offline
          if (response is Map && response['data'] is List) {
            await _offlineDb.saveCustomers(
              (response['data'] as List).cast<Map<String, dynamic>>(),
              sellerId,
            );
          }
          return customers;
        }
      } catch (e) {
        print('Error fetching customers from $endpoint: $e');
      }
    }

    // Fallback to offline
    return _getCustomersOffline(search: search);
  }

  /// Get customers from local database
  Future<List<Customer>> _getCustomersOffline({String? search}) async {
    try {
      final localData = await _offlineDb.getCustomers(
        ApiConstants.sellerId,
        search: search,
      );
      final customers = <Customer>[];
      for (final raw in localData) {
        final customer = _parseCustomer(raw);
        if (customer != null) customers.add(customer);
      }
      if (customers.isNotEmpty) return customers;
    } catch (_) {}
    // Try bundled POS database (synced via sync API)
    try {
      final posData = await _posDb.getCustomers(
        ApiConstants.sellerId,
        search: search,
      );
      final customers = <Customer>[];
      for (final raw in posData) {
        final customer = _parseCustomer(raw);
        if (customer != null) customers.add(customer);
      }
      return customers;
    } catch (e) {
      return [];
    }
  }

  List<Customer> _parseCustomersResponse(dynamic response) {
    if (response is! Map || response['data'] is! List) {
      return [];
    }

    final List<Customer> parsed = [];
    for (final raw in response['data'] as List) {
      final customer = _parseCustomer(raw);
      if (customer != null) {
        parsed.add(customer);
      }
    }
    return parsed;
  }

  Customer? _parseCustomer(dynamic raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);

    // allCustomers filter format: {label, value, ...}
    if (json.containsKey('value') && json.containsKey('label')) {
      final id = int.tryParse(json['value']?.toString() ?? '') ?? 0;
      final label = json['label']?.toString() ?? '';
      final parts = label.split('|').map((e) => e.trim()).toList();
      final name = parts.isNotEmpty && parts.first.isNotEmpty
          ? parts.first
          : 'Customer #$id';
      final mobile = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;

      return Customer(
        id: id,
        name: name,
        mobile: mobile,
        email: null,
        avatar: null,
      );
    }

    // Full customer format normalization
    if (json['country_id'] == null && json['country'] is Map) {
      json['country_id'] = (json['country'] as Map<String, dynamic>)['id'];
    }
    if (json['city_id'] == null && json['city'] is Map) {
      json['city_id'] = (json['city'] as Map<String, dynamic>)['id'];
    }

    if (json['id'] == null) return null;
    if (json['name'] == null || json['name'].toString().trim().isEmpty) {
      json['name'] = json['mobile']?.toString() ??
          json['mobile_display']?.toString() ??
          'Customer #${json['id']}';
    }

    for (final key in const [
      'name',
      'email',
      'mobile',
      'birthdate',
      'type',
      'tax_number',
      'commercial_register',
      'zatca_postal_number',
      'zatca_street_name',
      'zatca_building_number',
      'zatca_plot_identification',
      'zatca_city_sub_division',
      'avatar',
    ]) {
      if (json[key] != null && json[key] is! String) {
        json[key] = json[key].toString();
      }
    }

    try {
      return Customer.fromJson(json);
    } catch (e) {
      print('Skipping malformed customer payload: $e');
      return null;
    }
  }

  Future<Customer> createCustomer(Map<String, String> data) async {
    // OFFLINE MODE: Save locally and queue for sync
    if (_connectivity.isOffline) {
      return _createCustomerOffline(data);
    }

    final endpoint = '/seller/sellers/${ApiConstants.sellerId}/customers';
    final customerType = _resolveCustomerType(data['type']);

    // Ensure required fields are present if missing
    if (!data.containsKey('country_id')) data['country_id'] = '1';
    if (!data.containsKey('city_id')) data['city_id'] = '1';

    // Add empty fields that the API expects (Laravel form-data)
    final allFields = <String, String>{
      'name': data['name'] ?? '',
      'email': data['email'] ?? '',
      'mobile': data['mobile'] ?? '',
      'country_id': data['country_id'] ?? '1',
      'city_id': data['city_id'] ?? '1',
      'birthdate': data['birthdate'] ?? '',
      'type': customerType,
      'tax_number': data['tax_number'] ?? '',
      'commercial_register': data['commercial_register'] ?? '',
      'zatca_postal_number': data['zatca_postal_number'] ?? '',
      'zatca_street_name': data['zatca_street_name'] ?? '',
      'zatca_building_number': data['zatca_building_number'] ?? '',
      'zatca_plot_identification': data['zatca_plot_identification'] ?? '',
      'zatca_city_sub_division': data['zatca_city_sub_division'] ?? '',
    };

    // Separate files from fields
    Map<String, String> files = {};
    if (data.containsKey('avatar') &&
        data['avatar'] != null &&
        data['avatar']!.isNotEmpty) {
      files['avatar'] = data['avatar']!;
    }

    try {
      print('🔄 Creating customer at: $_baseUrl$endpoint');
      final response = await _client.postMultipart(endpoint, allFields,
          files: files, customBaseUrl: _baseUrl);

      if (response != null) {
        if (response['data'] != null) {
          return Customer.fromJson(response['data']);
        } else if (response['message'] != null) {
          throw Exception(response['message'].toString());
        } else if (response['error'] != null) {
          throw Exception(response['error'].toString());
        }
      }
      throw Exception('فشل في إنشاء العميل: استجابة غير صالحة من الخادم');
    } catch (e) {
      print('❌ Create customer failed: $e');
      rethrow;
    }
  }

  Future<Customer> updateCustomer(
      int customerId, Map<String, String> data) async {
    final endpoint =
        '/seller/sellers/${ApiConstants.sellerId}/customers/$customerId';

    // Separate files from fields
    Map<String, String> files = {};
    if (data.containsKey('avatar') &&
        data['avatar'] != null &&
        data['avatar']!.isNotEmpty) {
      files['avatar'] = data['avatar']!;
      data.remove('avatar');
    }

    final Map<String, String> fields = Map.from(data);
    fields['_method'] = 'PATCH';

    // Add empty fields expected by API
    fields.putIfAbsent('birthdate', () => '');
    fields['type'] = _resolveCustomerType(fields['type']);
    fields.putIfAbsent('tax_number', () => '');
    fields.putIfAbsent('commercial_register', () => '');
    fields.putIfAbsent('zatca_postal_number', () => '');
    fields.putIfAbsent('zatca_street_name', () => '');
    fields.putIfAbsent('zatca_building_number', () => '');
    fields.putIfAbsent('zatca_plot_identification', () => '');
    fields.putIfAbsent('zatca_city_sub_division', () => '');

    final response = await _client.postMultipart(endpoint, fields,
        files: files, customBaseUrl: _baseUrl);

    if (response != null && response['data'] != null) {
      return Customer.fromJson(response['data']);
    }
    throw Exception('Failed to update customer');
  }

  Future<void> deleteCustomer(int customerId) async {
    final endpoint =
        '/seller/sellers/${ApiConstants.sellerId}/customers/$customerId';
    await _client.delete(endpoint, customBaseUrl: _baseUrl);
  }

  /// Create customer offline
  Future<Customer> _createCustomerOffline(Map<String, String> data) async {
    final localId = await _offlineDb.saveLocalCustomer(
      data.cast<String, dynamic>(),
      ApiConstants.sellerId,
    );

    // Add to sync queue
    await _offlineDb.addToSyncQueue(
      operation: 'CREATE_CUSTOMER',
      endpoint: '/seller/sellers/${ApiConstants.sellerId}/customers',
      method: 'POST',
      payload: data.cast<String, dynamic>(),
      localRefTable: 'customers',
      localRefId: localId,
    );

    return Customer(
      id: localId.hashCode,
      name: data['name'] ?? '',
      mobile: data['mobile'],
      email: data['email'],
      avatar: null,
    );
  }

  Future<List<Country>> getCountries() async {
    if (_connectivity.isOffline) {
      return _getCountriesOffline();
    }

    try {
      final response = await _client.get(ApiConstants.countriesEndpoint,
          customBaseUrl: _baseUrl);
      if (response != null && response['data'] is List) {
        await _offlineDb.saveCountries(
            (response['data'] as List).cast<Map<String, dynamic>>());
        return (response['data'] as List)
            .map((json) => Country.fromJson(json))
            .toList();
      }
    } catch (e) {
      return _getCountriesOffline();
    }
    return [];
  }

  Future<List<Country>> _getCountriesOffline() async {
    try {
      final local = await _offlineDb.getCountries();
      return local.map((json) => Country.fromJson(json)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<City>> getCities(int countryId) async {
    if (_connectivity.isOffline) {
      return _getCitiesOffline(countryId);
    }

    try {
      final response = await _client.get(ApiConstants.citiesEndpoint(countryId),
          customBaseUrl: _baseUrl);
      if (response != null && response['data'] is List) {
        await _offlineDb.saveCities(
            (response['data'] as List).cast<Map<String, dynamic>>(), countryId);
        return (response['data'] as List)
            .map((json) => City.fromJson(json))
            .toList();
      }
    } catch (e) {
      return _getCitiesOffline(countryId);
    }
    return [];
  }

  Future<List<City>> _getCitiesOffline(int countryId) async {
    try {
      final local = await _offlineDb.getCities(countryId);
      return local.map((json) => City.fromJson(json)).toList();
    } catch (_) {
      return [];
    }
  }
}
