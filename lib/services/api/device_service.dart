import 'dart:convert';
import 'dart:developer' as developer;

import 'package:hermosa_pos/locator.dart';
import 'package:hermosa_pos/models.dart';
import 'package:hermosa_pos/services/cache_service.dart';
import 'package:hermosa_pos/utils/paper_width_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_constants.dart';
import 'base_client.dart';

class DeviceService {
  final BaseClient _client = BaseClient();
  final CacheService _cache = getIt<CacheService>();
  static const String _localOverridesKey = 'device_local_overrides_v1';
  static const String _devicesCacheKey = 'devices_list_v1';

  static const List<String> _fallbackDeviceTypes = <String>[
    'printer',
    'kds',
    'kitchen_screen',
    'order_viewer',
    'notification',
    'payment',
    'sub_cashier',
  ];

  /// Load all devices from LOCAL storage only (no API).
  Future<List<DeviceConfig>> getDevices() async {
    final localOverrides = await _loadLocalOverrides();
    final devices = _allDevicesFromOverrides(localOverrides);
    return devices;
  }

  /// Read devices from local storage (same as getDevices — no API).
  Future<List<DeviceConfig>> getCachedDevices() async {
    return getDevices();
  }

  List<DeviceConfig> _allDevicesFromOverrides(
      Map<String, Map<String, dynamic>> overrides) {
    final devices = <DeviceConfig>[];
    overrides.forEach((id, data) {
      final ip = (data['ip'] ?? '').toString();
      final name = (data['name'] ?? 'Printer').toString();
      if (ip.isEmpty && (data['bluetooth_address'] ?? '').toString().isEmpty) {
        return; // Skip entries with no connection info
      }
      devices.add(DeviceConfig(
        id: id,
        name: name,
        ip: ip,
        port: (data['port'] ?? '9100').toString(),
        type: (data['type'] ?? 'printer').toString(),
        model: (data['model'] ?? 'default').toString(),
        isOnline: false,
        copies: int.tryParse((data['copies'] ?? 1).toString()) ?? 1,
        paperWidthMm: _normalizePaperWidthMm(data['paper_width_mm']),
        connectionType: _parseConnectionType(
            data['connection_type'] ?? data['connectionType']),
        bluetoothAddress: data['bluetooth_address']?.toString(),
        bluetoothName: data['bluetooth_name']?.toString(),
      ));
    });
    return devices;
  }

  Future<List<String>> getSupportedDeviceTypes() async {
    try {
      final res = await _client.get(ApiConstants.getTypesEndpoint);
      final collected = <String>{..._fallbackDeviceTypes};
      _collectKnownTypes(res, collected);
      return collected.toList()..sort();
    } catch (_) {
      return List<String>.from(_fallbackDeviceTypes);
    }
  }

  /// Create device LOCALLY only (no API call).
  Future<DeviceConfig> createDevice(DeviceConfig device) async {
    final normalizedType = device.type.trim().toLowerCase();
    final normalizedName = device.name.trim();

    if (normalizedName.isEmpty) {
      throw ApiException(
        'Device name is required',
        userMessage: 'اسم الجهاز مطلوب.',
      );
    }

    final prefix = _isCdsDeviceType(normalizedType)
        ? 'cds'
        : _isKdsDeviceType(normalizedType)
            ? 'kitchen'
            : 'printer';

    final created = DeviceConfig(
      id: '$prefix:local_${DateTime.now().millisecondsSinceEpoch}',
      name: normalizedName,
      ip: device.ip,
      port: device.port.isNotEmpty ? device.port : '9100',
      type: normalizedType.isEmpty ? 'printer' : normalizedType,
      model: device.model,
      connectionType: device.connectionType,
      bluetoothAddress: device.bluetoothAddress,
      bluetoothName: device.bluetoothName,
      isOnline: false,
      copies: device.copies,
      paperWidthMm: _normalizePaperWidthMm(device.paperWidthMm),
    );
    await _saveLocalOverride(created);
    return created;
  }

  Future<Map<String, List<String>>> getPrinterCategoryAssignments() async {
    final response = await _client.get(ApiConstants.printersEndpoint);
    final printers = _extractList(response);
    final result = <String, List<String>>{};

    for (final raw in printers) {
      final item = _asMap(raw);
      if (item == null) continue;
      final id = item['id']?.toString().trim();
      if (id == null || id.isEmpty) continue;

      final normalizedCategories = <String>{};
      final rawCategories = item['categories'];
      if (rawCategories is List) {
        for (final category in rawCategories) {
          final parsed = _parseCategoryId(category);
          if (parsed != null) normalizedCategories.add(parsed);
        }
      }

      result['printer:$id'] = normalizedCategories.toList()..sort();
    }

    return result;
  }

  Future<void> updatePrinterCategories({
    required String printerId,
    required String printerName,
    required Iterable<String> categoryIds,
  }) async {
    final normalizedPrinterId = _normalizePrinterId(printerId);
    if (normalizedPrinterId == null) {
      throw ApiException(
        'Invalid printer id: $printerId',
        userMessage: 'تعذر تحديث ربط الأقسام بالطابعة.',
      );
    }

    final normalizedName = printerName.trim();
    if (normalizedName.isEmpty) {
      throw ApiException(
        'Printer name is required',
        userMessage: 'اسم الطابعة مطلوب للتحديث.',
      );
    }

    final normalizedCategoryIds = categoryIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final payload = <String, dynamic>{
      'name': normalizedName,
      'categories': normalizedCategoryIds,
    };

    await _client.put(
      ApiConstants.printerDetailsEndpoint(normalizedPrinterId),
      payload,
    );
  }

  /// Delete device LOCALLY only (no API call).
  Future<void> deleteDevice(String deviceId) async {
    await _removeLocalOverride(deviceId);
    await _removeFromCache(deviceId);
  }

  Future<void> _removeFromCache(String deviceId) async {
    try {
      final cached = await _cache.get(_devicesCacheKey);
      if (cached is List) {
        final filtered = cached.where((item) {
          final map = _asMap(item);
          return map?['id']?.toString() != deviceId;
        }).toList();
        await _cache.set(_devicesCacheKey, filtered,
            expiry: const Duration(hours: 12));
      }
    } catch (_) {}
  }

  Future<void> updateLocalDeviceConfig(DeviceConfig device) async {
    await _saveLocalOverride(device);
  }


  List<dynamic> _extractList(dynamic response) {
    if (response is List) return response;
    if (response is Map<String, dynamic>) {
      final data = response['data'];
      if (data is List) return data;
      if (data is Map<String, dynamic>) {
        for (final key in const ['items', 'list', 'data']) {
          final nested = data[key];
          if (nested is List) return nested;
        }
      }
    }
    return const <dynamic>[];
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  String? _normalizePrinterId(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('printer:')) {
      final id = raw.substring('printer:'.length).trim();
      return id.isEmpty ? null : id;
    }
    return raw;
  }

  String? _parseCategoryId(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      final map = _asMap(value);
      if (map == null) return null;
      final candidate = map['id'] ?? map['value'] ?? map['category_id'];
      return _parseCategoryId(candidate);
    }
    final token = value.toString().trim();
    if (token.isEmpty || token.toLowerCase() == 'null') return null;
    return token;
  }

  void _collectKnownTypes(dynamic value, Set<String> out) {
    if (value is List) {
      for (final item in value) {
        _collectKnownTypes(item, out);
      }
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().trim().toLowerCase();
        if (_looksLikeDeviceType(key)) out.add(key);
        _collectKnownTypes(entry.value, out);
      }
      return;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (_looksLikeDeviceType(normalized)) out.add(normalized);
    }
  }

  bool _looksLikeDeviceType(String value) {
    return value == 'printer' ||
        value == 'kds' ||
        value == 'cds' ||
        value == 'customer_display' ||
        value == 'kitchen_screen' ||
        value == 'order_viewer' ||
        value == 'notification' ||
        value == 'payment' ||
        value == 'sub_cashier' ||
        value.contains('printer') ||
        value.contains('kitchen') ||
        value.contains('cashier') ||
        value.contains('viewer');
  }

  bool _isKdsDeviceType(String value) {
    return value == 'kds' ||
        value == 'kitchen_screen' ||
        value == 'order_viewer';
  }

  bool _isCdsDeviceType(String value) {
    return value == 'cds' || value == 'customer_display';
  }



  Future<Map<String, Map<String, dynamic>>> _loadLocalOverrides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localOverridesKey);
      if (raw == null || raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((key, value) {
        final mapValue = value is Map
            ? value.map((k, v) => MapEntry(k.toString(), v))
            : <String, dynamic>{};
        return MapEntry(key.toString(), mapValue);
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> _persistLocalOverrides(
      Map<String, Map<String, dynamic>> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localOverridesKey, jsonEncode(map));
  }

  Future<void> _saveLocalOverride(DeviceConfig device) async {
    try {
      developer.log(
        '[Printer] saved paperSize: ${device.paperWidthMm}',
        name: 'Printer',
      );
      final map = await _loadLocalOverrides();
      map[device.id] = {
        'name': device.name,
        'ip': device.ip,
        'port': device.port,
        'type': device.type,
        'model': device.model,
        'paper_width_mm': _normalizePaperWidthMm(device.paperWidthMm),
        'connection_type': device.connectionType.name,
        'bluetooth_address': device.bluetoothAddress,
        'bluetooth_name': device.bluetoothName,
      };
      await _persistLocalOverrides(map);
    } catch (_) {}
  }

  PrinterConnectionType _parseConnectionType(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    if (value == 'bluetooth' || value == 'bt') {
      return PrinterConnectionType.bluetooth;
    }
    return PrinterConnectionType.wifi;
  }


  Future<void> _removeLocalOverride(String deviceId) async {
    try {
      final map = await _loadLocalOverrides();
      if (map.remove(deviceId) != null) {
        await _persistLocalOverrides(map);
      }
    } catch (_) {}
  }


  int _normalizePaperWidthMm(dynamic value) {
    return normalizePaperWidthMm(value);
  }
}
