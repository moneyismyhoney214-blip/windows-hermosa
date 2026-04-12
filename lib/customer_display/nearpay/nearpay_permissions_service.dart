/// NearPay Permissions Service
/// 
/// Handles runtime permission requests for NearPay SDK
/// 
/// Required permissions for NearPay Tap to Pay:
/// - ACCESS_FINE_LOCATION (required for payment processing)
/// - ACCESS_NETWORK_STATE (required for connectivity)
/// - INTERNET (required for API communication)
/// - READ_PHONE_STATE (required for device identification)
/// - NFC (required for card reading)
library;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class NearPayPermissionsService {
  static final NearPayPermissionsService _instance =
      NearPayPermissionsService._internal();
  factory NearPayPermissionsService() => _instance;
  NearPayPermissionsService._internal();

  /// List of all permissions required by NearPay SDK
  static final List<Permission> _requiredPermissions = [
    Permission.location, // ACCESS_FINE_LOCATION
    Permission.phone, // READ_PHONE_STATE
    // Note: INTERNET and ACCESS_NETWORK_STATE are auto-granted
    // Note: NFC is handled separately via feature check
  ];

  /// Check if all required permissions are granted
  Future<bool> get isAllPermissionsGranted async {
    for (final permission in _requiredPermissions) {
      final status = await permission.status;
      if (!status.isGranted) {
        debugPrint('❌ Permission not granted: ${permission.toString()}');
        return false;
      }
    }
    debugPrint('✅ All NearPay permissions granted');
    return true;
  }

  /// Request all required permissions
  /// Returns true if all permissions are granted
  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      debugPrint('📋 Requesting NearPay permissions...');

      // Request permissions
      final statuses = await _requiredPermissions.request();

      // Check results
      bool allGranted = true;
      for (final entry in statuses.entries) {
        final permission = entry.key;
        final status = entry.value;

        if (status.isGranted) {
          debugPrint('✅ Permission granted: ${permission.toString()}');
        } else if (status.isDenied) {
          debugPrint('⚠️ Permission denied: ${permission.toString()}');
          debugPrint('   → User denied permission, can request again');
          allGranted = false;
        } else if (status.isPermanentlyDenied) {
          debugPrint('❌ Permission permanently denied: ${permission.toString()}');
          debugPrint('   → User must enable in settings');
          allGranted = false;
        }
      }

      // Special handling for location permission (critical for NearPay)
      final locationStatus = await Permission.location.status;
      if (locationStatus.isDenied || locationStatus.isPermanentlyDenied) {
        debugPrint('⚠️ LOCATION permission is critical for NearPay!');
        debugPrint('   → Payment may not work without location');
      }

      return allGranted;
    }

    // iOS not supported yet
    debugPrint('ℹ️ NearPay permissions only required on Android');
    return true;
  }

  /// Check and request permissions if needed
  /// Returns true if permissions are granted (or not required)
  Future<bool> checkAndRequestIfNeeded() async {
    // Check if already granted
    final alreadyGranted = await isAllPermissionsGranted;
    if (alreadyGranted) {
      debugPrint('✅ Permissions already granted');
      return true;
    }

    // Request permissions
    debugPrint('⚠️ Permissions not granted, requesting...');
    final granted = await requestPermissions();

    if (!granted) {
      debugPrint('⚠️ Some permissions were not granted');
      debugPrint('   → NearPay may have limited functionality');
    }

    return granted;
  }

  /// Open app settings for manual permission grant
  Future<void> openNearPayAppSettings() async {
    debugPrint('🔧 Opening app settings...');
    await openAppSettings();
  }

  /// Get detailed permission status
  Future<Map<String, dynamic>> getPermissionStatus() async {
    final status = <String, dynamic>{};

    for (final permission in _requiredPermissions) {
      final permStatus = await permission.status;
      status[permission.toString()] = {
        'isGranted': permStatus.isGranted,
        'isDenied': permStatus.isDenied,
        'isPermanentlyDenied': permStatus.isPermanentlyDenied,
        'isRestricted': permStatus.isRestricted,
        'isLimited': permStatus.isLimited,
      };
    }

    // Check NFC separately
    // Note: NFC permission is special - it's granted at install time
    // but NFC hardware might not be available
    status['NFC'] = {
      'isGranted': true, // NFC permission is auto-granted
      'note': 'Check NFC hardware availability separately',
    };

    return status;
  }

  /// Print permission status for debugging
  Future<void> debugPrintPermissionStatus() async {
    debugPrint('═══════════════════════════════════════════');
    debugPrint('📋 NearPay Permissions Status');
    debugPrint('═══════════════════════════════════════════');

    final status = await getPermissionStatus();
    status.forEach((permission, data) {
      final granted = data['isGranted'] as bool? ?? false;
      final icon = granted ? '✅' : '❌';
      debugPrint('$icon $permission: ${data['isGranted']}');

      if (data['note'] != null) {
        debugPrint('   → ${data['note']}');
      }
    });

    debugPrint('═══════════════════════════════════════════');
  }
}
