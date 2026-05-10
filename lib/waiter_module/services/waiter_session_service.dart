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
    // Blank the keys before removing them so a force-kill between the
    // two removes can't leave the device in a "stale branch, no name"
    // state. setString('') is a single atomic write per key on
    // SharedPreferences; the subsequent removes are belt-and-braces
    // cleanup that the next sign-in will overwrite anyway.
    //
    // Why both keys must clear in lockstep: if waiter A signs out and
    // waiter B signs in later on a DIFFERENT branch, initialize() at
    // line 29 reads `_kBranchKey ?? branchId`. A stale branch value
    // would seed B's session with A's branch until sign-in overwrites,
    // and any mesh broadcast in that window leaks to/from the wrong
    // branch.
    await prefs.setString(_kNameKey, '');
    await prefs.setString(_kBranchKey, '');
    await prefs.remove(_kNameKey);
    await prefs.remove(_kBranchKey);
    _self = _self?.copyWith(name: '', status: WaiterStatus.offline);
    notifyListeners();
  }

  void setStatus(WaiterStatus status) {
    if (_self == null) return;
    _self = _self!.copyWith(status: status);
    notifyListeners();
  }
}
