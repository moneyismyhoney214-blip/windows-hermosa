import 'package:hermosa_pos/models.dart';
import 'package:hermosa_pos/services/api/base_client.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';
import 'package:hermosa_pos/services/cache_service.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';
import 'package:hermosa_pos/locator.dart';

class TableService {
  final BaseClient _client = BaseClient();
  final CacheService _cache = getIt<CacheService>();
  final OfflineDatabaseService _offlineDb = OfflineDatabaseService();
  final ConnectivityService _connectivity = ConnectivityService();

  /// Fetch tables from API (offline-first)
  Future<List<TableItem>> getTables() async {
    if (_connectivity.isOffline) {
      return _getTablesOffline();
    }

    try {
      final response = await _client.get(ApiConstants.tablesEndpoint);
      List<TableItem> tables = [];

      if (response is Map && response['data'] is List) {
        final data = response['data'] as List;
        tables = data
            .map((e) => TableItem.fromJson(e as Map<String, dynamic>))
            .toList();

        // Cache tables
        await _cache.set('tables', data,
            expiry: const Duration(hours: 1));
        // Save to SQLite for offline
        await _offlineDb.saveTables(
            data.cast<Map<String, dynamic>>(), ApiConstants.branchId);
      }

      return tables;
    } catch (e) {
      return _getTablesOffline();
    }
  }

  Future<List<TableItem>> _getTablesOffline() async {
    try {
      final localData = await _offlineDb.getTables(ApiConstants.branchId);
      if (localData.isNotEmpty) {
        return localData.map((e) => TableItem.fromJson(e)).toList();
      }
    } catch (_) {}
    final cached = await _cache.get('tables');
    if (cached is List) {
      return cached.map((e) => TableItem.fromJson(e)).toList();
    }
    return [];
  }

  /// Get single table details to check if it's active
  /// Returns null if table is deactivated (data: null)
  Future<TableItem?> getTableDetails(String tableId) async {
    try {
      final endpoint = '${ApiConstants.tablesEndpoint}/$tableId';
      final response = await _client.get(endpoint);

      // If data is null, table is deactivated by administrator
      if (response['data'] == null) {
        return null;
      }

      // If data exists, return the table
      if (response['data'] is Map) {
        return TableItem.fromJson(response['data'] as Map<String, dynamic>);
      }

      return null;
    } catch (e) {
      // If error occurs, try to find it in cached list
      final cached = await _cache.get('tables');
      if (cached is List) {
        final tables = cached.map((e) => TableItem.fromJson(e)).toList();
        final table = tables.where((t) => t.id == tableId).toList();
        if (table.isNotEmpty) return table.first;
      }
      return null;
    }
  }

  /// Check if table is active/deactivated
  Future<bool> isTableActive(String tableId) async {
    final table = await getTableDetails(tableId);
    return table != null && table.isActive;
  }

  /// Create a new table
  Future<Map<String, dynamic>> createTable(Map<String, dynamic> data) async {
    return await _client.post(ApiConstants.tablesEndpoint, data);
  }

  /// Update an existing table
  Future<Map<String, dynamic>> updateTable(
      String tableId, Map<String, dynamic> data) async {
    try {
      return await _client.patch(
          '${ApiConstants.tablesEndpoint}/$tableId', data);
    } on ApiException catch (e) {
      if (e.statusCode == 405) {
        return await _client.put(
            '${ApiConstants.tablesEndpoint}/$tableId', data);
      }
      rethrow;
    }
  }

  /// Delete a table
  /// DELETE /seller/branches/{branch_id}/restaurantTables/{table_id}
  Future<Map<String, dynamic>> deleteTable(String tableId) async {
    final normalizedId = tableId.trim();
    if (normalizedId.isEmpty) {
      throw ApiException('Table id is required for delete');
    }
    return await _client.delete('${ApiConstants.tablesEndpoint}/$normalizedId');
  }
}
