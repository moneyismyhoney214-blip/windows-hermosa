import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../models.dart';

/// Per-table carts living only on the waiter device.
///
/// Tracks two lists per table:
///   * `_carts[tableId]` — the current draft (not yet sent to the kitchen)
///   * `_sent[tableId]`  — everything already sent in previous rounds, kept so
///                        the waiter and the cashier can see the full history
///                        of the table without re-querying the backend.
///
/// Guests are also persisted per-table so "number of people" survives when
/// the waiter reopens the screen.
class WaiterCartStore extends ChangeNotifier {
  final Map<String, List<CartItem>> _carts = {};
  final Map<String, List<CartItem>> _sent = {};
  final Map<String, int> _guestCounts = {};
  /// Table → backend booking id of an in-flight submission that failed
  /// (e.g. network drop after createBooking succeeded on the server but
  /// the response was lost). Retry paths pass this into
  /// `WaiterBillingService.processBill(existingBookingId: ...)` so the
  /// backend isn't double-charged with a ghost booking. Cleared on
  /// successful completion or on explicit release.
  final Map<String, String> _pendingBookingIds = {};

  /// Persistence scope — set by [hydrate] right after the waiter signs
  /// in. Null means "don't write to disk" (viewer sessions / signed-out
  /// state).
  String? _persistScope;
  Timer? _persistDebounce;

  static const String _persistKeyPrefix = 'waiter_cart_store_v1_';

  String? pendingBookingIdFor(String tableId) => _pendingBookingIds[tableId];

  void setPendingBookingId(String tableId, String bookingId) {
    if (bookingId.isEmpty) return;
    _pendingBookingIds[tableId] = bookingId;
    _schedulePersist();
  }

  void clearPendingBookingId(String tableId) {
    if (_pendingBookingIds.remove(tableId) != null) _schedulePersist();
  }

  List<CartItem> itemsFor(String tableId) =>
      List.unmodifiable(_carts[tableId] ?? const <CartItem>[]);

  List<CartItem> sentItemsFor(String tableId) =>
      List.unmodifiable(_sent[tableId] ?? const <CartItem>[]);

  /// Union of sent + current draft — useful for billing / cashier display.
  List<CartItem> allItemsFor(String tableId) {
    final out = <CartItem>[];
    out.addAll(_sent[tableId] ?? const []);
    out.addAll(_carts[tableId] ?? const []);
    return List.unmodifiable(out);
  }

  int? guestsFor(String tableId) => _guestCounts[tableId];

  bool hasItems(String tableId) =>
      (_carts[tableId]?.isNotEmpty ?? false);

  bool hasSentItems(String tableId) =>
      (_sent[tableId]?.isNotEmpty ?? false);

  void setGuests(String tableId, int count) {
    _guestCounts[tableId] = count;
    notifyListeners();
    _schedulePersist();
  }

  void addItem(String tableId, CartItem item) {
    _carts.putIfAbsent(tableId, () => <CartItem>[]).add(item);
    notifyListeners();
    _schedulePersist();
  }

  void updateItem(String tableId, int index, CartItem newItem) {
    final list = _carts[tableId];
    if (list == null || index < 0 || index >= list.length) return;
    list[index] = newItem;
    notifyListeners();
    _schedulePersist();
  }

  void removeItem(String tableId, int index) {
    final list = _carts[tableId];
    if (list == null || index < 0 || index >= list.length) return;
    list.removeAt(index);
    if (list.isEmpty) _carts.remove(tableId);
    notifyListeners();
    _schedulePersist();
  }

  /// Promote the current draft to "sent" — called after successfully
  /// handing the order off to the kitchen.
  void markDraftAsSent(String tableId) {
    final draft = _carts[tableId];
    if (draft == null || draft.isEmpty) return;
    _sent.putIfAbsent(tableId, () => <CartItem>[]).addAll(draft);
    _carts.remove(tableId);
    notifyListeners();
    _schedulePersist();
  }

  /// Replace the table's "sent" list with the given items. Used after
  /// an external edit (EditOrderDialog) so the local cart stays in
  /// sync with the backend — otherwise the next pay-later PATCH would
  /// overwrite the edited booking with stale local state. Passing an
  /// empty list removes the sent bucket entirely.
  void setSentItems(String tableId, List<CartItem> items) {
    if (items.isEmpty) {
      if (_sent.remove(tableId) != null) {
        notifyListeners();
        _schedulePersist();
      }
      return;
    }
    _sent[tableId] = List<CartItem>.from(items);
    notifyListeners();
    _schedulePersist();
  }

  void clearTable(String tableId) {
    final removed = _carts.remove(tableId) != null;
    final removedSent = _sent.remove(tableId) != null;
    final removedGuests = _guestCounts.remove(tableId) != null;
    final removedPending = _pendingBookingIds.remove(tableId) != null;
    if (removed || removedSent || removedGuests || removedPending) {
      notifyListeners();
      _schedulePersist();
    }
  }

  /// Wipe every table's draft + sent cart + guest count. Used when a
  /// waiter ends their shift or a cashier switches branch — the next
  /// user of the device shouldn't see the previous session's in-flight
  /// orders. Awaits the disk wipe so a fast re-login's hydrate doesn't
  /// race the remove.
  Future<void> clearAll() async {
    final hadAny = _carts.isNotEmpty ||
        _sent.isNotEmpty ||
        _guestCounts.isNotEmpty ||
        _pendingBookingIds.isNotEmpty;
    _carts.clear();
    _sent.clear();
    _guestCounts.clear();
    _pendingBookingIds.clear();
    if (hadAny) notifyListeners();
    await clearPersisted();
  }

  /// Carry the entire per-table cart (drafts + sent + guest count) over
  /// to a different table id. Used by [WaiterController] when the
  /// cashier migrates a party to a new table — the guests take their
  /// already-fired order with them.
  ///
  /// Returns `true` if any state actually moved. If [newTableId] already
  /// has items they are preserved and the incoming entries are appended
  /// — this matches the "merge" semantics a chef would expect if the
  /// destination table happened to have been touched separately.
  bool moveTableCart(String oldTableId, String newTableId) {
    if (oldTableId == newTableId) return false;
    final draft = _carts.remove(oldTableId);
    final sent = _sent.remove(oldTableId);
    final guests = _guestCounts.remove(oldTableId);
    // Retry-stub booking id must follow the table — orphaned stubs strand on free tables otherwise.
    final pendingBookingId = _pendingBookingIds.remove(oldTableId);
    if ((draft == null || draft.isEmpty) &&
        (sent == null || sent.isEmpty) &&
        guests == null &&
        pendingBookingId == null) {
      return false;
    }
    if (draft != null && draft.isNotEmpty) {
      _carts.putIfAbsent(newTableId, () => <CartItem>[]).addAll(draft);
    }
    if (sent != null && sent.isNotEmpty) {
      _sent.putIfAbsent(newTableId, () => <CartItem>[]).addAll(sent);
    }
    if (guests != null) {
      // Destination's existing guest count wins (party size doesn't change with the table).
      _guestCounts[newTableId] = _guestCounts[newTableId] ?? guests;
    }
    if (pendingBookingId != null) {
      _pendingBookingIds[newTableId] = pendingBookingId;
    }
    notifyListeners();
    _schedulePersist();
    return true;
  }

  // --- Persistence ---

  /// Load drafts + sent + guests + pending-booking-ids saved for this
  /// waiter on this device. Called by [WaiterController.start]
  /// immediately after [WaiterTableRegistry.hydrate] so a waiter
  /// reopening the app lands on the same draft they were mid-composing.
  ///
  /// Scope mirrors the registry's: `branchId + name` — a shared device
  /// handing off between waiters won't cross-pollute carts.
  Future<void> hydrate({
    required String branchId,
    required String name,
  }) async {
    _persistScope = _scopeFor(branchId: branchId, name: name);
    try {
      final prefs = await SharedPreferences.getInstance();
      final primaryKey = '$_persistKeyPrefix$_persistScope';
      final backupKey = '$primaryKey.bak';
      // Dual-slot read (primary + backup) for power-loss recovery; mirrors registry.
      Map? decoded;
      for (final key in [primaryKey, backupKey]) {
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        try {
          final parsed = jsonDecode(raw);
          if (parsed is Map) {
            decoded = parsed;
            break;
          }
        } catch (e) {
          debugPrint('⚠️ WaiterCartStore: slot "$key" corrupt ($e)');
        }
      }
      if (decoded == null) return;
      _carts.clear();
      _sent.clear();
      _guestCounts.clear();
      _pendingBookingIds.clear();
      decoded.forEach((tableId, blob) {
        if (tableId is! String || blob is! Map) return;
        try {
          final draft = _decodeItemList(blob['drafts']);
          final sent = _decodeItemList(blob['sent']);
          final guests = (blob['guests'] as num?)?.toInt();
          final pendingId = blob['pending_booking_id']?.toString();
          if (draft.isNotEmpty) _carts[tableId] = draft;
          if (sent.isNotEmpty) _sent[tableId] = sent;
          if (guests != null) _guestCounts[tableId] = guests;
          if (pendingId != null && pendingId.isNotEmpty) {
            _pendingBookingIds[tableId] = pendingId;
          }
        } catch (e) {
          debugPrint(
              '⚠️ WaiterCartStore.hydrate: skipped bad row $tableId ($e)');
        }
      });
      if (_carts.isNotEmpty ||
          _sent.isNotEmpty ||
          _guestCounts.isNotEmpty ||
          _pendingBookingIds.isNotEmpty) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('⚠️ WaiterCartStore.hydrate failed: $e');
    }
  }

  List<CartItem> _decodeItemList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <CartItem>[];
    for (final entry in raw) {
      if (entry is Map) {
        try {
          out.add(_decodeCartItem(
              entry.map((k, v) => MapEntry(k.toString(), v))));
        } catch (_) {
          // Drop malformed item; partial cart beats no cart.
        }
      }
    }
    return out;
  }

  CartItem _decodeCartItem(Map<String, dynamic> j) {
    double toDouble(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.trim()) ?? 0.0;
      return 0.0;
    }

    Map<String, String> readMap(dynamic raw) {
      if (raw is! Map) return const {};
      final out = <String, String>{};
      raw.forEach((k, v) {
        final key = k.toString().trim().toLowerCase();
        final val = v?.toString().trim() ?? '';
        if (key.isNotEmpty && val.isNotEmpty) out[key] = val;
      });
      return out;
    }

    final extrasRaw = j['extras'];
    final extras = <Extra>[];
    if (extrasRaw is List) {
      for (final e in extrasRaw) {
        if (e is Map) {
          final optionTr = readMap(e['optionTranslations']);
          final attributeTr = readMap(e['attributeTranslations']);
          extras.add(Extra(
            id: (e['id'] ?? '').toString(),
            name: (e['name'] ?? '').toString(),
            price: toDouble(e['price']),
            // Restore per-language addon labels — without these, bilingual rendering breaks after app restart.
            optionTranslations: optionTr,
            attributeTranslations: attributeTr,
          ));
        }
      }
    }

    final localizedNames = readMap(j['localizedNames']);
    final nameAr = j['nameAr']?.toString() ?? '';
    final nameEn = j['nameEn']?.toString() ?? '';

    final product = Product(
      id: (j['meal_id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      nameAr: nameAr,
      nameEn: nameEn,
      price: toDouble(j['unit_price']),
      category: '',
      categoryId: j['category_id']?.toString(),
      localizedNames: localizedNames,
    );

    return CartItem(
      cartId: (j['cart_id']?.toString().isNotEmpty == true)
          ? j['cart_id']!.toString()
          : const Uuid().v4(),
      product: product,
      quantity: (() {
        final q = toDouble(j['quantity']);
        return q == 0 ? 1.0 : q;
      })(),
      selectedExtras: extras,
      discount: toDouble(j['discount']),
      discountType: j['discount_type'] == 'percentage'
          ? DiscountType.percentage
          : DiscountType.amount,
      isFree: j['is_free'] == true,
      notes: (j['notes'] ?? '').toString(),
    );
  }

  Map<String, dynamic> _encodeCartItem(CartItem item) {
    return {
      'cart_id': item.cartId,
      'meal_id': item.product.id,
      'name': item.product.name,
      // Persist all translation fields — bilingual rendering breaks after restart without them.
      if (item.product.nameAr.isNotEmpty) 'nameAr': item.product.nameAr,
      if (item.product.nameEn.isNotEmpty) 'nameEn': item.product.nameEn,
      if (item.product.localizedNames.isNotEmpty)
        'localizedNames': item.product.localizedNames,
      'unit_price': item.product.price,
      if (item.product.categoryId != null)
        'category_id': item.product.categoryId,
      'quantity': item.quantity,
      'notes': item.notes,
      'discount': item.discount,
      'discount_type':
          item.discountType == DiscountType.percentage ? 'percentage' : 'amount',
      'is_free': item.isFree,
      if (item.selectedExtras.isNotEmpty)
        'extras': item.selectedExtras
            .map((e) => {
                  'id': e.id,
                  'name': e.name,
                  'price': e.price,
                  if (e.optionTranslations.isNotEmpty)
                    'optionTranslations': e.optionTranslations,
                  if (e.attributeTranslations.isNotEmpty)
                    'attributeTranslations': e.attributeTranslations,
                })
            .toList(),
    };
  }

  void _schedulePersist() {
    if (_persistScope == null) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 300), _flushPersist);
  }

  /// Persist immediately, cancelling any pending debounce. Used right after
  /// a successful "create booking" so a crash before the 300ms debounce
  /// can't leave the just-sent items still flagged as drafts on disk — which
  /// on the next launch would make a re-entry PATCH and re-dispatch them to
  /// the kitchen a second time.
  Future<void> flushNow() {
    _persistDebounce?.cancel();
    return _flushPersist();
  }

  // Serialise persist writes — chaining flushes keeps the backup→primary pair atomic vs the next flush + clearPersisted.
  Future<void> _persistTail = Future<void>.value();

  Future<void> _flushPersist() {
    _persistTail = _persistTail.then((_) => _flushPersistOnce());
    return _persistTail;
  }

  Future<void> _flushPersistOnce() async {
    final scope = _persistScope;
    if (scope == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final tables = <String>{
        ..._carts.keys,
        ..._sent.keys,
        ..._guestCounts.keys,
        ..._pendingBookingIds.keys,
      };
      final blob = <String, dynamic>{};
      for (final tableId in tables) {
        final row = <String, dynamic>{};
        final drafts = _carts[tableId];
        if (drafts != null && drafts.isNotEmpty) {
          row['drafts'] = drafts.map(_encodeCartItem).toList();
        }
        final sent = _sent[tableId];
        if (sent != null && sent.isNotEmpty) {
          row['sent'] = sent.map(_encodeCartItem).toList();
        }
        final guests = _guestCounts[tableId];
        if (guests != null) row['guests'] = guests;
        final pid = _pendingBookingIds[tableId];
        if (pid != null && pid.isNotEmpty) row['pending_booking_id'] = pid;
        if (row.isNotEmpty) blob[tableId] = row;
      }
      final encoded = jsonEncode(blob);
      final primaryKey = '$_persistKeyPrefix$scope';
      final backupKey = '$primaryKey.bak';
      // Backup-first, primary-second — crash mid-write leaves backup coherent.
      await prefs.setString(backupKey, encoded);
      await prefs.setString(primaryKey, encoded);
    } catch (e) {
      debugPrint('⚠️ WaiterCartStore persist failed: $e');
    }
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    _persistDebounce = null;
    super.dispose();
  }

  /// Drop the on-disk snapshot. Called on sign-out so the next user of
  /// this device starts with a clean slate.
  Future<void> clearPersisted() async {
    final scope = _persistScope;
    _persistDebounce?.cancel();
    _persistScope = null;
    if (scope == null) return;
    // Chain wipe onto the flush tail — a mid-flight write can't resurrect the cleared cart.
    _persistTail = _persistTail.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final primaryKey = '$_persistKeyPrefix$scope';
        await prefs.remove(primaryKey);
        await prefs.remove('$primaryKey.bak');
      } catch (e) {
        debugPrint('⚠️ WaiterCartStore clearPersisted failed: $e');
      }
    });
    return _persistTail;
  }

  /// Deliberately mirror the registry's scope logic — must produce an
  /// identical key for the same (branchId, name) so both stores agree
  /// on which waiter owns which slot. `Uri.encodeComponent` guarantees
  /// whitespace variants of a name can't collide on a shared tablet.
  static String _scopeFor({required String branchId, required String name}) {
    final safeBranch = Uri.encodeComponent(branchId.trim());
    final safeName = Uri.encodeComponent(name.trim());
    return '${safeBranch}_$safeName';
  }

  double draftSubtotalFor(String tableId) =>
      itemsFor(tableId).fold<double>(0, (s, i) => s + i.totalPrice);

  double sentSubtotalFor(String tableId) =>
      sentItemsFor(tableId).fold<double>(0, (s, i) => s + i.totalPrice);

  double subtotalFor(String tableId) =>
      draftSubtotalFor(tableId) + sentSubtotalFor(tableId);

  int itemCountFor(String tableId) {
    // Sum fractional quantities first, then ceil once — per-line ceiling inflates totals (two 0.5s become 2 instead of 1).
    final qty = allItemsFor(tableId).fold<double>(0, (s, i) => s + i.quantity);
    return qty <= 0 ? 0 : qty.ceil();
  }
}
