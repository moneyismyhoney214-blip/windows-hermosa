import 'package:flutter/foundation.dart';
import 'package:hermosa_pos/services/api/base_client.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';
import 'package:hermosa_pos/services/offline/offline_pos_database.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';

/// Service for the Offline POS sync API endpoints.
///
/// Handles:
/// - GET /sync/manifest → discover available resources & cursors
/// - GET /sync/resources/{resource}?cursor= → download resources page by page
/// - POST /sync/pos → upload pending offline sales
class SyncApiService {
  static final SyncApiService _instance = SyncApiService._internal();
  factory SyncApiService() => _instance;
  SyncApiService._internal();

  final BaseClient _client = BaseClient();
  final OfflinePosDatabase _posDb = OfflinePosDatabase();
  final ConnectivityService _connectivity = ConnectivityService();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  // ═══════════════════════════════════════════════════════════════════
  //  MANIFEST
  // ═══════════════════════════════════════════════════════════════════

  /// Fetch the sync manifest from the server.
  /// Returns the list of available resources and their metadata.
  Future<Map<String, dynamic>?> fetchManifest() async {
    if (_connectivity.isOffline) {
      return _posDb.getManifest();
    }

    try {
      final response = await _client.get(ApiConstants.syncManifestEndpoint);
      if (response is Map) {
        final manifest =
            response.map((k, v) => MapEntry(k.toString(), v));
        await _posDb.saveManifest(manifest);
        debugPrint('Sync manifest fetched: ${manifest.keys.toList()}');
        return manifest;
      }
    } catch (e) {
      debugPrint('Failed to fetch sync manifest: $e');
      // Fall back to cached manifest
      return _posDb.getManifest();
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  RESOURCE DOWNLOAD
  // ═══════════════════════════════════════════════════════════════════

  /// Download a resource (e.g. "employees", "customers") using cursor-based
  /// pagination. Data is inserted directly into the local SQLite database.
  ///
  /// Returns the total number of rows synced in this call.
  Future<int> syncResource(String resource, {String? tableName}) async {
    if (_connectivity.isOffline) {
      debugPrint('Cannot sync resource $resource: offline');
      return 0;
    }

    final targetTable = tableName ?? resource;
    int totalSynced = 0;
    String? cursor = await _posDb.getSyncCursor(resource);

    debugPrint('Starting sync for $resource (cursor: ${cursor ?? "none"})');

    // Page through until we get an empty response or no next cursor
    bool hasMore = true;
    while (hasMore) {
      try {
        final endpoint = ApiConstants.syncResourceEndpoint(
          resource,
          cursor: cursor,
        );
        final response = await _client.get(endpoint);

        if (response is! Map) {
          hasMore = false;
          break;
        }

        final data = response['data'];
        final List<Map<String, dynamic>> rows;

        if (data is List) {
          rows = data
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList();
        } else if (data is Map && data['data'] is List) {
          // Nested data envelope
          rows = (data['data'] as List)
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList();
        } else {
          hasMore = false;
          break;
        }

        if (rows.isEmpty) {
          hasMore = false;
          break;
        }

        // Upsert into local database
        final inserted = await _posDb.upsertRows(targetTable, rows);
        totalSynced += inserted;

        // Extract next cursor
        final nextCursor = _extractNextCursor(response);
        if (nextCursor != null && nextCursor.isNotEmpty && nextCursor != cursor) {
          cursor = nextCursor;
          await _posDb.updateSyncCursor(resource, cursor, addCount: inserted);
        } else {
          hasMore = false;
          // Save final cursor state
          if (cursor != null) {
            await _posDb.updateSyncCursor(resource, cursor, addCount: inserted);
          }
        }

        debugPrint(
            'Synced $inserted $resource rows (total: $totalSynced, cursor: $cursor)');
      } catch (e) {
        debugPrint('Error syncing $resource page: $e');
        hasMore = false;
      }
    }

    debugPrint('Sync complete for $resource: $totalSynced rows');
    return totalSynced;
  }

  /// Extract the next cursor from a sync response.
  String? _extractNextCursor(Map response) {
    // Try standard cursor patterns
    for (final key in [
      'next_cursor',
      'cursor',
      'next_page_cursor',
      'meta.next_cursor',
    ]) {
      final value = _getNestedValue(response, key);
      if (value != null) return value.toString();
    }

    // Try pagination meta
    final meta = response['meta'];
    if (meta is Map) {
      final next = meta['next_cursor'] ?? meta['cursor'];
      if (next != null) return next.toString();
    }

    // Try links.next
    final links = response['links'];
    if (links is Map && links['next'] is String) {
      final nextUrl = links['next'] as String;
      final uri = Uri.tryParse(nextUrl);
      if (uri != null) {
        return uri.queryParameters['cursor'];
      }
    }

    return null;
  }

  dynamic _getNestedValue(Map map, String dotPath) {
    final parts = dotPath.split('.');
    dynamic current = map;
    for (final part in parts) {
      if (current is Map) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  POS SALE UPLOAD
  // ═══════════════════════════════════════════════════════════════════

  /// Upload a single POS sale to the server via POST /sync/pos.
  Future<Map<String, dynamic>> uploadPosSale(
      Map<String, dynamic> payload) async {
    final response = await _client.post(
      ApiConstants.syncPosEndpoint,
      payload,
    );
    if (response is Map) {
      return response.map((k, v) => MapEntry(k.toString(), v));
    }
    return {'status': 200, 'data': response};
  }

  /// Upload all pending POS sales from the local database.
  /// Returns (synced, failed) counts.
  Future<({int synced, int failed})> uploadPendingSales() async {
    if (_connectivity.isOffline) return (synced: 0, failed: 0);
    if (_isSyncing) return (synced: 0, failed: 0);

    _isSyncing = true;
    int synced = 0;
    int failed = 0;

    try {
      final pendingSales = await _posDb.getPendingSales();
      if (pendingSales.isEmpty) return (synced: 0, failed: 0);

      debugPrint('Uploading ${pendingSales.length} pending POS sales...');

      for (final sale in pendingSales) {
        final uuid = sale['uuid'] as String;
        try {
          final payload = _posDb.buildSyncPosPayload(sale);
          await uploadPosSale(payload);
          await _posDb.markSaleSynced(uuid);
          synced++;
          debugPrint('POS sale uploaded: $uuid');
        } catch (e) {
          await _posDb.markSaleFailed(uuid, e.toString());
          failed++;
          debugPrint('POS sale upload failed ($uuid): $e');
        }
      }
    } finally {
      _isSyncing = false;
    }

    debugPrint('POS sale upload complete: $synced synced, $failed failed');
    return (synced: synced, failed: failed);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  FULL SYNC (download all resources + upload sales)
  // ═══════════════════════════════════════════════════════════════════

  /// Run a full sync cycle:
  /// 1. Fetch manifest
  /// 2. Download resources (employees, customers)
  /// 3. Upload pending POS sales
  Future<SyncApiResult> fullSync() async {
    if (_connectivity.isOffline) {
      return SyncApiResult(
        success: false,
        message: 'No internet connection',
      );
    }
    if (_isSyncing) {
      return SyncApiResult(
        success: false,
        message: 'Sync already in progress',
      );
    }

    _isSyncing = true;
    int resourcesSynced = 0;
    int salesSynced = 0;
    int salesFailed = 0;
    final errors = <String>[];

    try {
      // 1. Fetch manifest
      await fetchManifest();

      // 2. Download resources
      for (final resource in ['employees', 'customers']) {
        try {
          final count = await syncResource(resource);
          resourcesSynced += count;
        } catch (e) {
          errors.add('$resource sync: $e');
          debugPrint('Resource sync error ($resource): $e');
        }
      }

      // 3. Upload pending sales
      final uploadResult = await uploadPendingSales();
      salesSynced = uploadResult.synced;
      salesFailed = uploadResult.failed;
    } catch (e) {
      errors.add('Full sync error: $e');
      debugPrint('Full sync error: $e');
    } finally {
      _isSyncing = false;
    }

    return SyncApiResult(
      success: errors.isEmpty && salesFailed == 0,
      resourcesSynced: resourcesSynced,
      salesSynced: salesSynced,
      salesFailed: salesFailed,
      errors: errors,
      message: 'Resources: $resourcesSynced, Sales: $salesSynced synced, '
          '$salesFailed failed',
    );
  }
}

/// Result of a sync API operation.
class SyncApiResult {
  final bool success;
  final int resourcesSynced;
  final int salesSynced;
  final int salesFailed;
  final List<String> errors;
  final String? message;

  SyncApiResult({
    required this.success,
    this.resourcesSynced = 0,
    this.salesSynced = 0,
    this.salesFailed = 0,
    this.errors = const [],
    this.message,
  });
}
