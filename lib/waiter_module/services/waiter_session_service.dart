import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/waiter.dart';

/// Persistent identity for the waiter running on *this* device.
///
/// `id` is a stable UUID generated once per device and reused across
/// restarts. `name` is the waiter the user picked at the login screen.
class WaiterSessionService extends ChangeNotifier {
  static const _kDeviceIdKey = 'waiter_device_id';
  static const _kNameKey = 'waiter_name';
  static const _kBranchKey = 'waiter_branch_id';

  Waiter? _self;
  Waiter? get self => _self;

  bool get isSignedIn => _self != null && _self!.name.isNotEmpty;

  Future<Waiter> initialize({required String branchId}) async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_kDeviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await prefs.setString(_kDeviceIdKey, deviceId);
    }
    final name = prefs.getString(_kNameKey) ?? '';
    final storedBranch = prefs.getString(_kBranchKey) ?? branchId;

    _self = Waiter(
      id: deviceId,
      name: name,
      branchId: storedBranch.isEmpty ? branchId : storedBranch,
    );
    notifyListeners();
    return _self!;
  }

  Future<void> signIn({required String name, required String branchId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNameKey, name);
    await prefs.setString(_kBranchKey, branchId);
    _self = (_self ?? await initialize(branchId: branchId)).copyWith(
      name: name,
      branchId: branchId,
      status: WaiterStatus.free,
    );
    notifyListeners();
  }

  /// Assign a transient viewer identity (used by the cashier so it can listen
  /// for waiter broadcasts without advertising itself as a callable waiter).
  /// Not persisted — ephemeral per session. Uses a fresh viewer-prefixed id
  /// so peers know to exclude this peer from "call a waiter" lists.
  Future<void> assignViewerIdentity({
    required String name,
    required String branchId,
  }) async {
    await initialize(branchId: branchId); // ensures device id exists
    _self = Waiter(
      id: '${Waiter.viewerIdPrefix}${const Uuid().v4()}',
      name: name,
      branchId: branchId,
      status: WaiterStatus.offline,
    );
    notifyListeners();
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kNameKey);
    _self = _self?.copyWith(name: '', status: WaiterStatus.offline);
    notifyListeners();
  }

  void setStatus(WaiterStatus status) {
    if (_self == null) return;
    _self = _self!.copyWith(status: status);
    notifyListeners();
  }
}
