import 'package:flutter/foundation.dart';

import '../models/waitlist_entry.dart';

/// Cross-screen bus for the "pick a table for this party" flow.
///
/// Why a singleton and not screen-local state? The cashier opens the
/// waitlist sheet, taps "خصّص طاولة" on an entry, and the sheet pops
/// — but the table grid underneath needs to know we're now in assign
/// mode. Passing the state back through Navigator.pop is fragile (it
/// doesn't cover the waiter module's IndexedStack case where the sheet
/// and grid live in different tabs). A shared ValueNotifier sidesteps
/// that entirely: both screens just listen.
class WaitlistAssignController extends ChangeNotifier {
  static final WaitlistAssignController _instance =
      WaitlistAssignController._internal();
  factory WaitlistAssignController() => _instance;
  WaitlistAssignController._internal();

  WaitlistEntry? _pending;
  WaitlistEntry? get pending => _pending;
  bool get isAssigning => _pending != null;

  /// Enter assign mode with the given entry. No-ops when already
  /// assigning — a second tap on the same entry shouldn't toggle it
  /// off by accident.
  void beginAssign(WaitlistEntry entry) {
    if (_pending?.id == entry.id) return;
    _pending = entry;
    notifyListeners();
  }

  /// Exit assign mode. Called after a successful notify, when the user
  /// dismisses the banner, or when the entry is removed/updated from
  /// under us.
  void clear() {
    if (_pending == null) return;
    _pending = null;
    notifyListeners();
  }
}

final waitlistAssignController = WaitlistAssignController();
