import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Monitors network connectivity and provides online/offline status.
///
/// Uses connectivity_plus for network change events, plus a real HTTP
/// check to verify actual internet access (not just WiFi connected).
class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _subscription;
  Timer? _periodicCheck;

  bool _isOnline = true;
  bool _isInitialized = false;

  /// Current connectivity status.
  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;

  /// Callbacks for connectivity changes.
  final List<VoidCallback> _onOnlineCallbacks = [];
  final List<VoidCallback> _onOfflineCallbacks = [];

  /// Register a callback for when the device comes online.
  void onOnline(VoidCallback callback) {
    _onOnlineCallbacks.add(callback);
  }

  /// Register a callback for when the device goes offline.
  void onOffline(VoidCallback callback) {
    _onOfflineCallbacks.add(callback);
  }

  /// Remove an online callback.
  void removeOnOnline(VoidCallback callback) {
    _onOnlineCallbacks.remove(callback);
  }

  /// Remove an offline callback.
  void removeOnOffline(VoidCallback callback) {
    _onOfflineCallbacks.remove(callback);
  }

  /// Initialize connectivity monitoring.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Check initial status
    await _checkConnectivity();

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      _onConnectivityChanged(result);
    });

    // Periodic real connectivity check every 30 seconds
    _periodicCheck = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkConnectivity(),
    );

    debugPrint('ConnectivityService initialized (online: $_isOnline)');
  }

  void _onConnectivityChanged(ConnectivityResult result) {
    final hasConnection = result != ConnectivityResult.none;
    if (hasConnection) {
      // Network interface available - verify with real check
      _checkConnectivity();
    } else {
      _updateStatus(false);
    }
  }

  /// Perform a real connectivity check by pinging a reliable host.
  Future<bool> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('portal.hermosaapp.com')
          .timeout(const Duration(seconds: 5));
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      _updateStatus(online);
      return online;
    } on SocketException {
      _updateStatus(false);
      return false;
    } on TimeoutException {
      _updateStatus(false);
      return false;
    } catch (_) {
      // On any error, try a fallback host
      try {
        final result = await InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 3));
        final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
        _updateStatus(online);
        return online;
      } catch (_) {
        _updateStatus(false);
        return false;
      }
    }
  }

  /// Force a connectivity check and return the result.
  Future<bool> checkNow() async {
    return await _checkConnectivity();
  }

  /// Mark as offline immediately (called when a network error occurs).
  /// This avoids waiting for the periodic check or listener.
  void markOffline() {
    _updateStatus(false);
    // Schedule a recheck in 5 seconds to see if connectivity returns
    Future.delayed(const Duration(seconds: 5), () => _checkConnectivity());
  }

  void _updateStatus(bool online) {
    if (_isOnline == online) return;

    final wasOffline = !_isOnline;
    _isOnline = online;
    notifyListeners();

    if (online) {
      debugPrint('Network: ONLINE');
      if (wasOffline) {
        for (final cb in _onOnlineCallbacks) {
          try {
            cb();
          } catch (e) {
            debugPrint('Error in onOnline callback: $e');
          }
        }
      }
    } else {
      debugPrint('Network: OFFLINE');
      for (final cb in _onOfflineCallbacks) {
        try {
          cb();
        } catch (e) {
          debugPrint('Error in onOffline callback: $e');
        }
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _periodicCheck?.cancel();
    _onOnlineCallbacks.clear();
    _onOfflineCallbacks.clear();
    super.dispose();
  }
}
