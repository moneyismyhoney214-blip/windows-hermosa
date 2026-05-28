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

  /// When true the host should skip the "notify & wait" flow: the picked
  /// table is held for the party and the order screen opens immediately
  /// so the waiter can start taking the order ("Seat now" button).
  bool _seatImmediately = false;
  bool get seatImmediately => _seatImmediately;

  /// Enter assign mode with the given entry. No-ops when already
  /// assigning — a second tap on the same entry shouldn't toggle it
  /// off by accident.
  void beginAssign(WaitlistEntry entry) {
    if (_pending?.id == entry.id && !_seatImmediately) return;
    _pending = entry;
    _seatImmediately = false;
    notifyListeners();
  }

  /// Enter assign mode in "seat now" intent — same table-picking UX, but
  /// the host seats the party (holds the table) and opens the order
  /// screen straight away instead of sending a waiting message.
  void beginSeat(WaitlistEntry entry) {
    if (_pending?.id == entry.id && _seatImmediately) return;
    _pending = entry;
    _seatImmediately = true;
    notifyListeners();
  }

  /// Exit assign mode. Called after a successful notify, when the user
  /// dismisses the banner, or when the entry is removed/updated from
  /// under us.
  void clear() {
    if (_pending == null && !_seatImmediately) return;
    _pending = null;
    _seatImmediately = false;
    notifyListeners();
  }
}

final waitlistAssignController = WaitlistAssignController();
