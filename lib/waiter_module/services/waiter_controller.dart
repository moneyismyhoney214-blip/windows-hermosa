import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../locator.dart';
import '../../models/booking_invoice.dart';
import '../../models/waitlist_mesh_event.dart';
import '../../services/api/api_constants.dart';
import '../../services/api/branch_service.dart';
import '../../services/api/order_service.dart';
import '../../services/logger_service.dart';
import '../../services/whatsapp_service.dart';
import '../models/network_message.dart';
import '../models/table_migrate_event.dart';
import '../models/table_pickup_request.dart';
import '../models/waiter.dart';
import '../models/waiter_message.dart';
import '../models/waiter_table_event.dart';
import 'mesh_auth_service.dart';
import 'waiter_billing_service.dart';
import 'waiter_cart_store.dart';
import 'waiter_config_store.dart';
import 'waiter_discovery_service.dart';
import 'waiter_message_store.dart';
import 'waiter_network_service.dart';
import 'waiter_notification_service.dart';
import 'waiter_order_outbox.dart';
import 'waiter_pickup_store.dart';
import 'waiter_roster_service.dart';
import 'waiter_session_service.dart';
import 'waiter_table_customer_store.dart';
import 'waiter_table_registry.dart';

part 'waiter_controller_parts/waiter_controller.broadcasts.dart';

/// How often we send a [WireMessageType.heartbeat] to every connected peer.
/// 15s is well under [WaiterRosterService.staleThreshold] (45s) so a peer
/// that's reachable should always have at least 2 heartbeats in-window.
const Duration _kHeartbeatInterval = Duration(seconds: 15);

/// How often we sweep the roster for peers that stopped heartbeating.
const Duration _kStaleSweepInterval = Duration(seconds: 10);

/// Wraps a [TableLifecycleEvent] with the source it arrived from. The UI
/// needs to know whether an event is the echo of its own broadcast (in
/// which case the triggering code already handled the side effects) or
/// a remote event (which requires local state updates).
class WaiterTableEventEnvelope {
  final TableLifecycleEvent event;

  /// True when this controller's own [broadcastTableEvent] produced the
  /// event. False when the event was received off the wire from a peer.
  final bool fromSelf;

  const WaiterTableEventEnvelope({
    required this.event,
    required this.fromSelf,
  });
}

/// Top-level coordinator for the waiter module.
///
/// Wires discovery, network, roster, messaging and notifications together so
/// that screens can consume a single ChangeNotifier.
///
/// Lifecycle:
///   1. `initialize(branchId)` — hydrate session from SharedPreferences
///   2. `start()` — bind WS server, start mDNS, connect to discovered peers
///   3. `stop()` — disconnect, stop discovery, dispose resources
class WaiterController extends ChangeNotifier {
  final WaiterSessionService session;
  final WaiterRosterService roster;
  final WaiterMessageStore messages;
  final WaiterNotificationService notifications;
  final WaiterTableRegistry tableRegistry;
  final WaiterConfigStore configStore;
  final WaiterPickupStore pickupStore;

  WaiterNetworkService? _net;
  WaiterDiscoveryService? _discovery;

  StreamSubscription<WireMessage>? _msgSub;
  StreamSubscription<Waiter>? _foundSub;
  StreamSubscription<String>? _lostSub;

  Timer? _heartbeatTimer;
  Timer? _staleSweepTimer;

  final StreamController<WaiterMessage> _callStream =
      StreamController<WaiterMessage>.broadcast();

  /// Fires when a WAITER_CALL is received so the UI can flash a banner.
  Stream<WaiterMessage> get onIncomingCall => _callStream.stream;

  final StreamController<WaiterTableEventEnvelope> _tableEventStream =
      StreamController<WaiterTableEventEnvelope>.broadcast();

  /// Fires for every TABLE_* event from any peer (including self echo).
  /// The envelope's [WaiterTableEventEnvelope.fromSelf] flag lets callers
  /// skip echoes of their own broadcasts while still reacting to events
  /// a different device (e.g. the cashier) originated for the same table.
  Stream<WaiterTableEventEnvelope> get onTableEvent => _tableEventStream.stream;

  final StreamController<String> _peerHelloStream =
      StreamController<String>.broadcast();

  /// Emits a peer id every time we see its HELLO / WAITER_ANNOUNCE. The
  /// cashier side subscribes to push its printer / KDS snapshot so late
  /// joiners catch up without a separate request round-trip.
  Stream<String> get onPeerHello => _peerHelloStream.stream;

  final StreamController<String> _configSyncRequestStream =
      StreamController<String>.broadcast();

  /// Emits the sender id of a CONFIG_SYNC_REQUEST. Unused on the happy
  /// path in Phase 1 (cashier pushes on HELLO), reserved for a future
  /// "refresh config" button on the waiter side.
  Stream<String> get onConfigSyncRequest => _configSyncRequestStream.stream;

  final StreamController<TablePickupRequest> _pickupRequestStream =
      StreamController<TablePickupRequest>.broadcast();

  /// Fires when a TABLE_PICKUP_REQUEST is received. Waiter UI listens to
  /// pop a notification banner + play the incoming-call sound.
  Stream<TablePickupRequest> get onPickupRequest =>
      _pickupRequestStream.stream;

  final StreamController<TablePickupRequest> _pickupUpdateStream =
      StreamController<TablePickupRequest>.broadcast();

  /// Fires on every claim/cancel update for an existing pickup so the
  /// cashier's tables screen can flip its card, and so waiters can
  /// re-render "accepted by X" in their notifications.
  Stream<TablePickupRequest> get onPickupUpdate =>
      _pickupUpdateStream.stream;

  final StreamController<TableMigrateEvent> _tableMigrateStream =
      StreamController<TableMigrateEvent>.broadcast();

  /// Fires on every table migration — every peer (cashier + waiters)
  /// sees it. The owner of `oldTableId` also performs the cart+registry
  /// shuffle; other peers just log it for UI/audit.
  Stream<TableMigrateEvent> get onTableMigrate => _tableMigrateStream.stream;

  final StreamController<WaitlistMeshEventEnvelope> _waitlistEventStream =
      StreamController<WaitlistMeshEventEnvelope>.broadcast();

  /// Fires for every waitlist delta (added/updated/removed/notified/
  /// seated/cancelled). Includes self-echoes via the envelope's
  /// [WaitlistMeshEventEnvelope.fromSelf] flag so the local service can
  /// skip its own broadcasts and remote peers can apply deltas without
  /// re-broadcasting.
  Stream<WaitlistMeshEventEnvelope> get onWaitlistEvent =>
      _waitlistEventStream.stream;

  final StreamController<WaitlistMeshSnapshot> _waitlistSnapshotStream =
      StreamController<WaitlistMeshSnapshot>.broadcast();

  /// Full-queue snapshots received from a peer catch-up (typically
  /// fired when a new device joins the mesh). The local service
  /// reconciles its in-memory list with the received snapshot on a
  /// last-write-wins basis.
  Stream<WaitlistMeshSnapshot> get onWaitlistSnapshot =>
      _waitlistSnapshotStream.stream;

  final StreamController<String> _openTableStream =
      StreamController<String>.broadcast();

  /// Emits a table id when this device should jump straight into the
  /// order-composition screen for that table — fired when the waiter
  /// accepts a cashier "pickup" request or a call pinned to a table, so
  /// they can start taking the order immediately instead of hunting for
  /// the table on the grid. The shell switches to the tables tab and the
  /// tables screen pushes the order screen.
  Stream<String> get onOpenTableRequest => _openTableStream.stream;

  bool _running = false;
  bool get isRunning => _running;

  /// Bumped on every [stop] / [clearSessionStores]. Fire-and-forget work
  /// kicked off during one session (e.g. the background pay-later
  /// reconcile) captures this on entry and bails the moment it changes,
  /// so a stale reconcile can't resurrect rows the next session cleared.
  int _sessionGeneration = 0;

  /// Single-flight guard: if two callers hit [start] back-to-back while the
  /// first is still awaiting mDNS/Bonsoir, the second mustn't spin up a
  /// second set of broadcasts. They both wait on the same Future.
  Future<void>? _starting;

  /// Table id the current device is *actively composing an order for*.
  /// Set by [WaiterOrderScreen] on enter, cleared on exit. Used to gate
  /// disruptive UI (pickup banner, incoming call sound) so the waiter's
  /// in-progress work isn't interrupted. Only one at a time.
  String? _activeOrderingTableId;

  /// True while this waiter has the order-composition screen open for
  /// some table. UI should treat the waiter as busy.
  bool get isTakingOrderNow => _activeOrderingTableId != null;

  String? get activeOrderingTableId => _activeOrderingTableId;

  /// Mark the waiter as actively composing an order for [tableId].
  /// Clears any previous value so a nav hop from table A → B doesn't
  /// leak the stale id. Also flips this waiter's presence to `busy` and
  /// broadcasts it so the cashier's roster shows who's tied up.
  void setActiveOrderingTable(String tableId) {
    _activeOrderingTableId = tableId;
    final self = session.self;
    if (self != null && !self.isViewer && self.status != WaiterStatus.busy) {
      session.setStatus(WaiterStatus.busy);
      _broadcastStatus();
    }
  }

  void clearActiveOrderingTable([String? tableId]) {
    if (tableId != null && _activeOrderingTableId != tableId) return;
    _activeOrderingTableId = null;
    // Back to free only if we were busy for this; don't stomp manual on-break/offline.
    final self = session.self;
    if (self != null && !self.isViewer && self.status == WaiterStatus.busy) {
      session.setStatus(WaiterStatus.free);
      _broadcastStatus();
    }
  }

  WaiterController({
    required this.session,
    required this.roster,
    required this.messages,
    required this.notifications,
    required this.tableRegistry,
    required this.configStore,
    required this.pickupStore,
  });

  // --- Lifecycle ---

  /// Ensure the controller is running as a read-only viewer (used by the
  /// cashier so its tables screen can mirror waiter state). Safe to call
  /// repeatedly — second call is a no-op once running *and* the branch
  /// matches. If the branch changed (e.g. the cashier signed out and
  /// logged into a different branch), we tear down and re-start so the
  /// mDNS broadcast carries the new branch id.
  Future<void> ensureViewer({
    required String name,
    required String branchId,
  }) async {
    if (_running) {
      final current = session.self?.branchId;
      if (current == branchId) return;
      debugPrint(
          '🔄 ensureViewer: branch switched ($current → $branchId), restarting');
      await stop();
      // Clear prior-branch mesh state before the new identity hydrates from disk.
      await clearSessionStores();
    }
    debugPrint('👁️ ensureViewer starting on branch $branchId');
    await session.assignViewerIdentity(name: name, branchId: branchId);
    await start();
  }

  /// Wipe every in-memory store that holds session-scoped data. Called
  /// on logout (end-shift) and branch switch so the next user/branch
  /// starts with a clean slate and doesn't inherit the previous
  /// shift's drafts, claimed pickups, notifications, or table
  /// ownership. Config (printer list + KDS endpoint) is NOT cleared —
  /// that's the cashier's domain and survives the waiter turnover.
  /// Returns a future that completes only after every session-scoped
  /// store has finished clearing — including the table registry's
  /// disk persistence. Callers on the logout / branch-switch path MUST
  /// await this so a fast re-login's hydrate doesn't race the disk
  /// wipe and resurrect state the user explicitly cleared.
  Future<void> clearSessionStores() async {
    _sessionGeneration++;
    messages.clear();
    pickupStore.clear();
    await tableRegistry.clearAll();
    roster.clear();
    try {
      await getIt<WaiterCartStore>().clearAll();
    } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
    // Drop outbox: prevents next signed-in waiter from flushing prior waiter's orders.
    try {
      await getIt<WaiterOrderOutbox>().clearAll();
    } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
    // Drop billing cache: cross-branch shared tablet may have different pay-methods/tax.
    try {
      getIt<WaiterBillingService>().clearSessionCaches();
    } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
    // Drop BranchService caches: prevents stale pay-method config across branch switch.
    try {
      getIt<BranchService>().clearSessionCaches();
    } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
    // Drop mesh MAC key so next start() derives a fresh per-branch key.
    try {
      getIt<MeshAuthService>().clear();
    } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
    debugPrint('🧹 waiter session stores cleared');
  }

  Future<void> start() async {
    if (_running) return;
    // Single-flight: rapid back-to-back start() calls must share one broadcast.
    if (_starting != null) return _starting!;
    final self = session.self;
    if (self == null) {
      throw StateError('WaiterController.start() called before session init');
    }

    // Captured so a stop() during awaits below won't re-flip _running back to true.
    final startGen = _sessionGeneration;

    final completer = Completer<void>();
    _starting = completer.future;

    // Partial-startup guard: release any resources we brought up if a step throws.
    try {
      // Hydrate registry from disk before network so the waiter doesn't see an empty grid.
      // Scoped by branch+name (not deviceId) for correct shared-tablet handoff.
      if (!self.isViewer && self.name.trim().isNotEmpty) {
        try {
          await tableRegistry.hydrate(
            branchId: self.branchId,
            name: self.name,
            selfId: self.id,
          );
          // Hydrate cart store so mid-composition drafts survive an app crash.
          try {
            await getIt<WaiterCartStore>().hydrate(
              branchId: self.branchId,
              name: self.name,
            );
          } catch (e) {
            debugPrint('⚠️ cartStore.hydrate failed: $e');
          }
          // Backend reconcile: covers createBooking-succeeded-but-app-died window.
          unawaited(_reconcileFromBackendPayLaterBookings(self));
        } catch (e) {
          debugPrint('⚠️ tableRegistry.hydrate failed: $e');
        }
      }

      // Prewarm branch receipt cache so waiter's receipt header matches cashier's.
      try {
        unawaited(getIt<BranchService>().fetchAndCacheBranchReceiptInfo());
        unawaited(getIt<BranchService>().refreshTaxConfig());
      } catch (e) {
        debugPrint('⚠️ waiter: fetchAndCacheBranchReceiptInfo failed: $e');
      }

      // Derive per-branch MAC key before network so signing/verification both have it.
      try {
        getIt<MeshAuthService>().deriveKey(
          branchId: self.branchId,
          sellerId: ApiConstants.sellerId.toString(),
        );
      } catch (e) {
        debugPrint('⚠️ MeshAuth deriveKey failed (non-fatal): $e');
      }
      // Boot-race: sellerId=0 → key scoped to branchId:0 silently HMAC-rejects peers.
      if (ApiConstants.sellerId == 0) {
        Timer(const Duration(seconds: 3), () {
          if (!_running) return;
          final s = session.self;
          if (s == null || ApiConstants.sellerId == 0) return;
          try {
            getIt<MeshAuthService>().deriveKey(
              branchId: s.branchId,
              sellerId: ApiConstants.sellerId.toString(),
            );
            _announceSelf();
            debugPrint('🔐 MeshAuth key re-derived after sellerId resolved');
          } catch (e) {
            debugPrint('⚠️ MeshAuth re-derive failed: $e');
          }
        });
      }

      _net = WaiterNetworkService(
        selfProvider: () => session.self!,
        // App-layer HMAC on every WireMessage; see MeshAuthService for threat model.
        auth: getIt<MeshAuthService>(),
      );
      final port = await _net!.startServer();

      _discovery = WaiterDiscoveryService(self: self, advertisedPort: port);
      await _discovery!.start();

      _msgSub = _net!.incoming.listen(_handleIncoming);
      _foundSub = _discovery!.onFound.listen(_handlePeerFound);
      _lostSub = _discovery!.onLost.listen((_) {});

      // stop()/clear ran mid-await — unwind and stay stopped.
      if (_sessionGeneration != startGen) {
        await _tearDownPartialStart();
        completer.complete();
        return;
      }

      _heartbeatTimer =
          Timer.periodic(_kHeartbeatInterval, (_) => _heartbeat());
      _staleSweepTimer =
          Timer.periodic(_kStaleSweepInterval, (_) => _sweepStalePeers());

      _running = true;
      _announceSelf();
      notifyListeners();
      completer.complete();
    } catch (e, st) {
      debugPrint('⚠️ WaiterController.start() failed: $e');
      debugPrintStack(stackTrace: st);
      await _tearDownPartialStart();
      completer.completeError(e, st);
      rethrow;
    } finally {
      _starting = null;
    }
  }

  /// Cross-check the backend's open pay-later bookings against the
  /// local registry and inject any we missed. Covers a narrow but real
  /// crash window: `createBooking` succeeds on the server, but the app
  /// dies before `broadcastTableEvent(paymentPending)` fires — leaving
  /// the booking orphaned from the local view until this reconcile
  /// runs on next launch.
  ///
  /// Only injects; never overwrites — live mesh events are always
  /// newer than the HTTP snapshot, and `registry.apply` on new events
  /// will naturally update the injected rows.
  Future<void> _reconcileFromBackendPayLaterBookings(Waiter self) async {
    // Captured: abandon paging if session generation bumps mid-flight.
    final gen = _sessionGeneration;
    bool sessionChanged() => gen != _sessionGeneration;
    try {
      final orderService = getIt<OrderService>();
      // Bounded to 4×50 = 200 rows max so a pathological result never hammers backend.
      const maxPages = 4;
      const perPage = 50;
      var injected = 0;
      final selfNameNormalized = self.name.trim();
      // Dedupe across overlapping pages.
      final seenBookingIds = <String>{};
      for (var page = 1; page <= maxPages; page++) {
        if (sessionChanged()) return;
        final resp = await orderService.getBookings(
          page: page,
          perPage: perPage,
          // 401 here (WAITER role denied) must not tear down the fresh session.
          skipGlobalAuth: true,
        );
        if (sessionChanged()) return;
        final data = resp['data'];
        if (data is! List) break;
        if (data.isEmpty) break;
        for (final raw in data) {
          if (raw is! Map) continue;
          Booking booking;
          try {
            booking = Booking.fromJson(
                raw.map((k, v) => MapEntry(k.toString(), v)));
          } catch (e) {
            Log.d('catch', 'non-fatal: $e');
            continue;
          }
          // Mirror cashier's `_canCreateInvoiceForBooking` filter.
          if (booking.isPaid) continue;
          final statusLower = booking.status.toLowerCase();
          if (statusLower == '8' ||
              statusLower == 'cancelled' ||
              statusLower == 'canceled') {
            continue;
          }
          // Filter to OUR bookings only (backend tags creator as `cashier_name`).
          final cashier = (booking.raw['cashier_name'] ??
                  raw['cashier_name'])
              ?.toString()
              .trim();
          if (cashier == null ||
              cashier.isEmpty ||
              cashier != selfNameNormalized) {
            continue;
          }
          final tableId = booking.tableId?.toString();
          if (tableId == null || tableId.isEmpty) continue;
          final bookingIdStr = booking.id.toString();
          if (!seenBookingIds.add(bookingIdStr)) continue;
          if (tableRegistry.lookup(tableId) != null) continue;
          if (sessionChanged()) return;
          // Broadcast (not raw apply) so online peers converge immediately.
          broadcastTableEvent(TableLifecycleEvent(
            kind: TableLifecycleKind.paymentPending,
            tableId: tableId,
            tableNumber: booking.tableName ?? '',
            waiterId: self.id,
            waiterName: self.name,
            total: booking.total,
            itemCount: booking.meals.length,
            orderId: booking.id.toString(),
          ));
          injected += 1;
        }
        if (data.length < perPage) break;
      }
      if (injected > 0) {
        debugPrint(
            '🔁 backend reconcile injected $injected orphan pay-later booking(s)');
      }
    } catch (e) {
      debugPrint('⚠️ backend reconcile failed (non-fatal): $e');
    }
  }

  Future<void> _tearDownPartialStart() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _staleSweepTimer?.cancel();
    _staleSweepTimer = null;
    try { await _msgSub?.cancel(); } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
    try { await _foundSub?.cancel(); } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
    try { await _lostSub?.cancel(); } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
    _msgSub = null;
    _foundSub = null;
    _lostSub = null;
    try { await _discovery?.dispose(); } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
    try { await _net?.dispose(); } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
    _discovery = null;
    _net = null;
    _running = false;
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _sessionGeneration++;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _staleSweepTimer?.cancel();
    _staleSweepTimer = null;

    _broadcastLeave();

    await _msgSub?.cancel();
    await _foundSub?.cancel();
    await _lostSub?.cancel();
    await _discovery?.dispose();
    await _net?.dispose();
    _discovery = null;
    _net = null;
    roster.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _staleSweepTimer?.cancel();
    // Defensive: dispose() may be called without a prior stop().
    unawaited(_msgSub?.cancel());
    unawaited(_foundSub?.cancel());
    unawaited(_lostSub?.cancel());
    _msgSub = null;
    _foundSub = null;
    _lostSub = null;
    _callStream.close();
    _tableEventStream.close();
    _peerHelloStream.close();
    _configSyncRequestStream.close();
    _pickupRequestStream.close();
    _pickupUpdateStream.close();
    _tableMigrateStream.close();
    _waitlistEventStream.close();
    _waitlistSnapshotStream.close();
    _openTableStream.close();
    super.dispose();
  }

  // --- Outbound actions ---

  /// Change this waiter's status and let everyone know.
  Future<void> setStatus(WaiterStatus status) async {
    session.setStatus(status);
    _broadcastStatus();
  }

  /// Send a chat message to a specific peer. Saved locally and delivered.
  /// Fire a broadcast call: every waiter on the LAN receives it, the
  /// first to tap "accept" claims it, and the rest see the acceptance
  /// state roll in. Exclusively used by the cashier (viewer) — the
  /// waiter module's UI has no entry point for this.
  ///
  /// We hard-guard on the session: a rogue waiter caller would be a
  /// bug, not a feature, and allowing it would re-introduce the
  /// peer-to-peer chat we just removed.
  WaiterMessage sendMessage({
    String? toWaiterId,
    required String text,
    String? tableId,
    String? tableNumber,
    bool isCall = false,
  }) {
    final self = session.self!;
    if (!self.isViewer) {
      throw StateError(
        'Waiter-to-waiter calls are disabled. sendMessage is only allowed '
        'from a viewer (cashier) session.',
      );
    }
    final targetId = toWaiterId ?? kBroadcastWaiterId;
    final peer =
        (targetId == kBroadcastWaiterId) ? null : roster.byId(targetId);
    final msg = WaiterMessage(
      fromWaiterId: self.id,
      fromWaiterName: self.name,
      toWaiterId: targetId,
      toWaiterName: peer?.name,
      text: text,
      tableId: tableId,
      tableNumber: tableNumber,
      isCall: isCall,
    );
    messages.record(message: msg, incoming: false);
    final wire = WireMessage(
      type: isCall ? WireMessageType.waiterCall : WireMessageType.waiterMessage,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
      data: msg.toJson(),
    );
    if (targetId == kBroadcastWaiterId) {
      _net?.broadcast(wire);
    } else {
      _net?.sendTo(targetId, wire);
    }
    return msg;
  }

  /// Claim a broadcast notification. Emits WAITER_CALL_ACCEPTED so every
  /// other device marks the item as "accepted by me" and hides the
  /// accept button. Safe to call on a non-broadcast message (no-op).
  void acceptCall(String messageId) {
    final self = session.self;
    if (self == null) return;
    // Optimistic local update for instant UI feedback.
    messages.markAccepted(
      messageId: messageId,
      waiterId: self.id,
      waiterName: self.name,
    );
    _net?.broadcast(WireMessage(
      type: WireMessageType.waiterCallAccepted,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
      data: {
        'message_id': messageId,
        'waiter_id': self.id,
        'waiter_name': self.name,
        'accepted_at': DateTime.now().toIso8601String(),
      },
    ));
    // If pinned to a table, jump the waiter straight to the order screen.
    if (!self.isViewer) {
      WaiterMessage? msg;
      for (final m in messages.all) {
        if (m.id == messageId) {
          msg = m;
          break;
        }
      }
      final tableId = msg?.tableId;
      if (tableId != null && tableId.isNotEmpty) {
        _openTableStream.add(tableId);
      }
    }
  }


  // --- Table pickup ("استلام") — Uber-style broadcast/claim. ---

  /// Broadcast a pickup request for [tableId]. Cashier-only: waiters
  /// must not call this (there's no UI for it, and it would bypass the
  /// cashier as the source of truth for who's sitting down).
  TablePickupRequest? requestTablePickup({
    required String tableId,
    required String tableNumber,
    String? note,
  }) {
    final self = session.self;
    if (self == null) return null;
    if (!self.isViewer) {
      throw StateError(
        'Only the cashier (viewer) may initiate a table pickup request.',
      );
    }
    final req = TablePickupRequest(
      cashierId: self.id,
      cashierName: self.name,
      tableId: tableId,
      tableNumber: tableNumber,
      note: note,
    );
    pickupStore.recordRequest(req);
    _net?.broadcast(WireMessage(
      type: WireMessageType.tablePickupRequest,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
      data: req.toJson(),
    ));
    return req;
  }

  /// Claim a pickup request. First waiter to broadcast wins — local
  /// dedupe via [WaiterPickupStore.markClaimed] drops later claims so
  /// the UI never flips back to an older waiter.
  ///
  /// Also broadcasts a [TableLifecycleEvent.assigned] so the cashier's
  /// existing tables-screen plumbing flips the card to "occupied by X"
  /// without needing a pickup-specific hook.
  TablePickupRequest? claimTablePickup(String requestId) {
    final self = session.self;
    if (self == null) return null;
    if (self.isViewer) {
      // Cashiers can't claim their own broadcasts; silent no-op.
      return null;
    }
    final stored = pickupStore.byId(requestId);
    if (stored == null) return null;
    if (stored.isClaimed) return stored;
    if (stored.cancelled) return stored;
    final claimed = pickupStore.markClaimed(
      requestId: requestId,
      waiterId: self.id,
      waiterName: self.name,
    );
    if (claimed == null) return null;
    _pickupUpdateStream.add(claimed);
    _net?.broadcast(WireMessage(
      type: WireMessageType.tablePickupClaimed,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
      data: {
        'request_id': claimed.requestId,
        'table_id': claimed.tableId,
        'table_number': claimed.tableNumber,
        'waiter_id': self.id,
        'waiter_name': self.name,
        'claimed_at':
            (claimed.claimedAt ?? DateTime.now()).toIso8601String(),
      },
    ));
    // Reuse the standard "assigned" lifecycle event for cashier UI + registry.
    broadcastTableEvent(TableLifecycleEvent(
      kind: TableLifecycleKind.assigned,
      tableId: claimed.tableId,
      tableNumber: claimed.tableNumber,
      waiterId: self.id,
      waiterName: self.name,
    ));
    // Clock-skew tie-break: navigate only if we actually won.
    if (claimed.claimedByWaiterId == self.id) {
      _openTableStream.add(claimed.tableId);
    }
    return claimed;
  }

  // --- Table migration — cashier moves a seated party to another table. ---

  /// Broadcast a migration. Cashier-only. Every peer (including the
  /// waiter that owned `oldTableId`) reacts in [_handleIncoming] — the
  /// owner does the heavy lifting (cart move + broadcasting
  /// release/assign for the cashier's tables screen to catch up), other
  /// peers just log the event.
  TableMigrateEvent? migrateTable({
    required String oldTableId,
    required String oldTableNumber,
    required String newTableId,
    required String newTableNumber,
  }) {
    final self = session.self;
    if (self == null) return null;
    // Waiter initiator must own source table (prevent relocating another's table).
    if (!self.isViewer) {
      final owner = tableRegistry.ownerIdFor(oldTableId);
      if (owner != null && owner != self.id) {
        throw StateError(
          'Only the owning waiter (or the cashier) may migrate this table.',
        );
      }
    }
    if (oldTableId == newTableId) return null;
    final event = TableMigrateEvent(
      oldTableId: oldTableId,
      oldTableNumber: oldTableNumber,
      newTableId: newTableId,
      newTableNumber: newTableNumber,
      initiatedById: self.id,
      initiatedByName: self.name,
    );
    _tableMigrateStream.add(event);
    _net?.broadcast(WireMessage(
      type: WireMessageType.tableMigrate,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
      data: event.toJson(),
    ));
    // Live owner handles the shuffle in _handleIncoming; otherwise initiator does it.
    final ownerId = tableRegistry.ownerIdFor(oldTableId);
    final liveWaiterOwnerId =
        (ownerId != null && ownerId.trim().isNotEmpty && roster.byId(ownerId) != null)
            ? ownerId
            : null;
    if (liveWaiterOwnerId != null) {
      if (liveWaiterOwnerId == self.id) _applyMigrateAsOwner(event);
    } else {
      _applyMigrateAsOwner(event);
    }
    return event;
  }

  /// Carry a seated party's full registry state from the old table to the
  /// new one and tell every peer. Called either by the owning waiter (via
  /// [_handleIncoming]) or — when no live waiter owns the table — by
  /// whoever initiated the migrate (see [migrateTable]). The new table
  /// keeps the SAME owner (a waiter id, or '' for a cashier-created
  /// order), the SAME booking id, the SAME items/guests, and the SAME
  /// billing phase (pay-later / paid) — only the table number changes.
  void _applyMigrateAsOwner(TableMigrateEvent event) {
    final self = session.self;
    if (self == null) return;

    WaiterCartStore? cart;
    try {
      cart = getIt<WaiterCartStore>();
    } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
    cart?.moveTableCart(event.oldTableId, event.newTableId);
    try {
      getIt<WaiterTableCustomerStore>().moveTable(
        event.oldTableId,
        event.newTableId,
      );
    } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }

    final snapshot = tableRegistry.lookup(event.oldTableId);
    final guests = snapshot?.guestCount;
    final total = snapshot?.total;
    final itemCount = snapshot?.itemCount;
    final items = snapshot?.items;
    // Carry booking id so order actions stay reachable and no new booking is created.
    final carriedOrderId = snapshot?.orderId;
    // Destination keeps the source's owner, NOT the migrator.
    final ownerWaiterId = snapshot?.waiterId ?? self.id;
    final ownerWaiterName = snapshot?.waiterName ?? self.name;

    broadcastTableEvent(TableLifecycleEvent(
      kind: TableLifecycleKind.released,
      tableId: event.oldTableId,
      tableNumber: event.oldTableNumber,
      waiterId: ownerWaiterId,
      waiterName: ownerWaiterName,
    ));

    broadcastTableEvent(TableLifecycleEvent(
      kind: TableLifecycleKind.assigned,
      tableId: event.newTableId,
      tableNumber: event.newTableNumber,
      waiterId: ownerWaiterId,
      waiterName: ownerWaiterName,
      guestCount: guests,
      total: total,
      itemCount: itemCount,
      items: items,
      orderId: carriedOrderId,
    ));
    // Re-emit billing phase so Edit/Invoice/Refund stay reachable on the new tableId.
    if (snapshot?.paid == true && carriedOrderId != null) {
      broadcastTableEvent(TableLifecycleEvent(
        kind: TableLifecycleKind.paid,
        tableId: event.newTableId,
        tableNumber: event.newTableNumber,
        waiterId: ownerWaiterId,
        waiterName: ownerWaiterName,
        guestCount: guests,
        total: total,
        itemCount: itemCount,
        items: items,
        orderId: carriedOrderId,
      ));
    } else if (snapshot?.paymentPending == true && carriedOrderId != null) {
      broadcastTableEvent(TableLifecycleEvent(
        kind: TableLifecycleKind.paymentPending,
        tableId: event.newTableId,
        tableNumber: event.newTableNumber,
        waiterId: ownerWaiterId,
        waiterName: ownerWaiterName,
        guestCount: guests,
        total: total,
        itemCount: itemCount,
        items: items,
        orderId: carriedOrderId,
      ));
    }
  }

  /// Cashier-only. Dismisses a still-pending request (if a waiter
  /// already claimed, cancel is a no-op — the table stays assigned).
  TablePickupRequest? cancelTablePickup(String requestId) {
    final self = session.self;
    if (self == null) return null;
    if (!self.isViewer) return null;
    final stored = pickupStore.byId(requestId);
    if (stored == null) return null;
    if (stored.isClaimed) return stored;
    final cancelled = pickupStore.markCancelled(requestId);
    if (cancelled == null) return null;
    _pickupUpdateStream.add(cancelled);
    _net?.broadcast(WireMessage(
      type: WireMessageType.tablePickupCancelled,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
      data: {
        'request_id': requestId,
        'table_id': stored.tableId,
        'table_number': stored.tableNumber,
      },
    ));
    return cancelled;
  }

  // --- Inbound handling ---

  void _handlePeerFound(Waiter peer) {
    final self = session.self;
    if (self == null) return;
    if (peer.branchId.isNotEmpty &&
        self.branchId.isNotEmpty &&
        peer.branchId != self.branchId) {
      return;
    }
    roster.upsert(peer);
    // Lower id initiates to avoid both sides dialling each other.
    if (peer.host != null && peer.port != null && self.id.compareTo(peer.id) < 0) {
      _net?.connectToPeer(peer);
    }
  }

  void _handleIncoming(WireMessage msg) {
    // Shutdown guard: late network callbacks may arrive after we cancel.
    if (!_running) return;

    final self = session.self;
    if (self == null) return;
    if (msg.senderId == self.id) return;

    // Cross-branch isolation: drop messages whose envelope disagrees with ours.
    if (self.branchId.isNotEmpty &&
        msg.branchId.isNotEmpty &&
        msg.branchId != self.branchId) {
      return;
    }

    // Any inbound traffic proves liveness; refresh lastSeen for all message types.
    roster.touch(msg.senderId);

    switch (msg.type) {
      case WireMessageType.hello:
      case WireMessageType.waiterAnnounce:
        final isNewPeer = roster.byId(msg.senderId) == null;
        roster.upsert(Waiter(
          id: msg.senderId,
          name: msg.senderName,
          branchId: msg.branchId,
          status: WaiterStatusX.fromWire(msg.data['status']?.toString()),
        ));
        // First-sight late-joiner: push owned tables + replay our claims.
        if (isNewPeer) {
          _pushOwnedTablesSnapshotTo(msg.senderId);
          if (!self.isViewer) _replayOwnClaimsTo(msg.senderId);
        }
        // Emit on every HELLO; cashier pushes printer/KDS snapshots (version-gated).
        _peerHelloStream.add(msg.senderId);
        break;

      case WireMessageType.waiterStatus:
        final existing = roster.byId(msg.senderId);
        if (existing != null) {
          roster.upsert(existing.copyWith(
            status:
                WaiterStatusX.fromWire(msg.data['status']?.toString()),
          ));
        }
        break;

      case WireMessageType.waiterLeave:
        roster.markOffline(msg.senderId);
        break;

      case WireMessageType.waiterCall:
      case WireMessageType.waiterMessage:
        final incoming = WaiterMessage.fromJson(msg.data);
        // Surface if it's a broadcast or it's pinned to me.
        final forMe = incoming.toWaiterId == self.id;
        final isBroadcastForWaiter = incoming.isBroadcast && !self.isViewer;
        if (forMe || isBroadcastForWaiter) {
          messages.record(message: incoming, incoming: true);
          if (incoming.isCall) {
            // Suppress ring while composing an order (FR-CTL-7 / NFR-USE-3).
            if (!isTakingOrderNow) {
              notifications.playCall();
              _callStream.add(incoming);
            }
          }
        }
        break;

      case WireMessageType.waiterCallAccepted:
        // Anti-spoof: payload waiter_id must equal envelope sender_id.
        final mid = msg.data['message_id']?.toString();
        final wid = msg.data['waiter_id']?.toString();
        final wname = msg.data['waiter_name']?.toString();
        final atRaw = msg.data['accepted_at']?.toString();
        if (mid != null && wid != null && wname != null) {
          if (wid != msg.senderId) {
            debugPrint(
                '⚠️ dropping WAITER_CALL_ACCEPTED: waiter_id=$wid != sender_id=${msg.senderId}');
            break;
          }
          messages.markAccepted(
            messageId: mid,
            waiterId: wid,
            waiterName: wname,
            at: atRaw != null ? DateTime.tryParse(atRaw) : null,
          );
        }
        break;

      case WireMessageType.tableAssign:
      case WireMessageType.tableRelease:
      case WireMessageType.tableUpdate:
      case WireMessageType.tablePaymentStatus:
        try {
          final event = TableLifecycleEvent.fromJson(msg.data);
          // Apply before stream emit so listeners see an already-updated registry.
          tableRegistry.apply(event);
          _tableEventStream.add(WaiterTableEventEnvelope(
            event: event,
            fromSelf: false,
          ));
        } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
        break;

      case WireMessageType.heartbeat:
        // Re-assert status so missed WAITER_STATUS broadcasts self-heal within one interval.
        final hb = roster.byId(msg.senderId);
        if (hb != null) {
          final s = WaiterStatusX.fromWire(msg.data['status']?.toString());
          if (s != hb.status) roster.upsert(hb.copyWith(status: s));
        }
        break;

      case WireMessageType.configKitchenPrinters:
        // Anti-spoof: only cashiers (viewer- prefix) push printer config.
        if (!msg.senderId.startsWith(Waiter.viewerIdPrefix)) {
          debugPrint(
              '⚠️ dropping CONFIG_KITCHEN_PRINTERS from non-viewer sender=${msg.senderId}');
          break;
        }
        if (self.isViewer) break;
        unawaited(
          configStore.applyKitchenPrinters(msg.data, sourceId: msg.senderId),
        );
        break;

      case WireMessageType.configKdsEndpoint:
        // Anti-spoof: only cashiers may repoint KDS endpoint.
        if (!msg.senderId.startsWith(Waiter.viewerIdPrefix)) {
          debugPrint(
              '⚠️ dropping CONFIG_KDS_ENDPOINT from non-viewer sender=${msg.senderId}');
          break;
        }
        if (self.isViewer) break;
        unawaited(
          configStore.applyKdsEndpoint(msg.data, sourceId: msg.senderId),
        );
        break;

      case WireMessageType.configWhatsApp:
        // Anti-spoof: only cashiers hand out WAWP credentials.
        if (!msg.senderId.startsWith(Waiter.viewerIdPrefix)) {
          debugPrint(
              '⚠️ dropping CONFIG_WHATSAPP from non-viewer sender=${msg.senderId}');
          break;
        }
        if (self.isViewer) break;
        final waId = msg.data['instance_id']?.toString();
        final waTok = msg.data['access_token']?.toString();
        if (waId != null && waId.trim().isNotEmpty &&
            waTok != null && waTok.trim().isNotEmpty) {
          whatsAppService.applyBackendCredentials(
            instanceId: waId,
            accessToken: waTok,
          );
          debugPrint('📥 CONFIG_WHATSAPP applied (instance="$waId")');
        }
        break;

      case WireMessageType.configSyncRequest:
        // Only viewers respond; re-emit for cashier bootstrap.
        if (!self.isViewer) break;
        _configSyncRequestStream.add(msg.senderId);
        break;

      case WireMessageType.tablePickupRequest:
        // Anti-spoof: only cashiers issue pickup requests.
        if (!msg.senderId.startsWith(Waiter.viewerIdPrefix)) {
          debugPrint(
              '⚠️ dropping TABLE_PICKUP_REQUEST from non-viewer sender=${msg.senderId}');
          break;
        }
        try {
          final req = TablePickupRequest.fromJson(msg.data);
          final recorded = pickupStore.recordRequest(req);
          if (recorded && !self.isViewer) {
            // Suppress ring while composing an order; request still persists in pickupStore.
            if (!isTakingOrderNow) {
              notifications.playCall();
            }
            _pickupRequestStream.add(req);
          } else if (recorded && self.isViewer) {
            _pickupRequestStream.add(req);
          }
        } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
        break;

      case WireMessageType.tablePickupClaimed:
        try {
          final rid = msg.data['request_id']?.toString() ?? '';
          final wid = msg.data['waiter_id']?.toString() ?? '';
          final wname = msg.data['waiter_name']?.toString() ?? '';
          if (rid.isEmpty || wid.isEmpty) break;

          // Anti-spoof: payload waiter_id must equal envelope sender_id.
          if (wid != msg.senderId) {
            debugPrint(
                '⚠️ dropping TABLE_PICKUP_CLAIMED: waiter_id=$wid != sender_id=${msg.senderId}');
            break;
          }

          final claimedAt = DateTime.tryParse(
            msg.data['claimed_at']?.toString() ?? '',
          );

          // Orphan claim recovery after cashier restart: synthesize from payload.
          if (self.isViewer && pickupStore.byId(rid) == null) {
            final synthTableId = msg.data['table_id']?.toString() ?? '';
            final synthTableNumber =
                msg.data['table_number']?.toString() ?? '';
            if (synthTableId.isNotEmpty) {
              pickupStore.recordRequest(TablePickupRequest(
                requestId: rid,
                cashierId: self.id,
                cashierName: self.name,
                tableId: synthTableId,
                tableNumber: synthTableNumber,
              ));
            }
          }

          final updated = pickupStore.markClaimed(
            requestId: rid,
            waiterId: wid,
            waiterName: wname,
            at: claimedAt,
          );
          if (updated != null) _pickupUpdateStream.add(updated);
        } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
        break;

      case WireMessageType.tablePickupCancelled:
        // Anti-spoof: only cashiers may cancel pickups.
        if (!msg.senderId.startsWith(Waiter.viewerIdPrefix)) {
          debugPrint(
              '⚠️ dropping TABLE_PICKUP_CANCELLED from non-viewer sender=${msg.senderId}');
          break;
        }
        try {
          final rid = msg.data['request_id']?.toString() ?? '';
          if (rid.isEmpty) break;
          final updated = pickupStore.markCancelled(rid);
          if (updated != null) _pickupUpdateStream.add(updated);
        } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
        break;

      case WireMessageType.tableMigrate:
        try {
          final event = TableMigrateEvent.fromJson(msg.data);
          _tableMigrateStream.add(event);
          // Only the owner does the cart shuffle; other peers pick up via echoes.
          final ownerId = tableRegistry.ownerIdFor(event.oldTableId);
          if (ownerId != null && ownerId == self.id) {
            _applyMigrateAsOwner(event);
          }
        } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
        break;

      case WireMessageType.waitlistEvent:
        try {
          final event = WaitlistMeshEvent.fromJson(msg.data);
          _waitlistEventStream.add(
            WaitlistMeshEventEnvelope(event: event, fromSelf: false),
          );
        } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
        break;

      case WireMessageType.waitlistSnapshot:
        try {
          final snapshot = WaitlistMeshSnapshot.fromJson(msg.data);
          _waitlistSnapshotStream.add(snapshot);
        } catch (e) { Log.w('waiter-ctrl', 'cleanup/dispatch catch swallowed', error: e); }
        break;

      case WireMessageType.helloAck:
      case WireMessageType.ack:
      case WireMessageType.error:
      case WireMessageType.newOrder:
      case WireMessageType.updateCart:
      case WireMessageType.orderEdit:
      case WireMessageType.orderCancel:
        // KDS handles kitchen traffic; waiter peers ignore.
        break;
    }
  }

  // --- Keep-alive ---

  void _heartbeat() {
    final self = session.self;
    if (self == null) return;
    _net?.broadcast(WireMessage(
      type: WireMessageType.heartbeat,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
      data: {'status': self.status.wireValue},
    ));
  }

  void _sweepStalePeers() {
    final flipped = roster.sweepStale();
    // Tear down half-dead sockets so a fresh HELLO isn't short-circuited.
    for (final id in flipped) {
      _net?.closeConnectionTo(id);
      // Drop transient "taking order" rows; committed pay-later/paid tables stay.
      tableRegistry.dropTakingOrderForWaiter(id);
    }
  }

  /// Send every pickup I (a waiter) claimed to [peerId] as a fresh
  /// TABLE_PICKUP_CLAIMED so a peer that missed the original broadcast
  /// converges. Runs on first HELLO from a given peer.
  void _replayOwnClaimsTo(String peerId) {
    final self = session.self;
    if (self == null) return;
    for (final req in pickupStore.all) {
      if (req.claimedByWaiterId != self.id) continue;
      final claimedAt = req.claimedAt;
      if (claimedAt == null) continue;
      _net?.sendTo(
        peerId,
        WireMessage(
          type: WireMessageType.tablePickupClaimed,
          senderId: self.id,
          senderName: self.name,
          branchId: self.branchId,
          data: {
            'request_id': req.requestId,
            'table_id': req.tableId,
            'table_number': req.tableNumber,
            'waiter_id': self.id,
            'waiter_name': self.name,
            'claimed_at': claimedAt.toIso8601String(),
          },
        ),
      );
    }
  }

  /// Send every table this device owns to [peerId] as a TABLE_UPDATE so
  /// late joiners don't start with an empty registry.
  void _pushOwnedTablesSnapshotTo(String peerId) {
    final self = session.self;
    if (self == null) return;
    for (final entry in tableRegistry.ownedBy(self.id)) {
      final tableId = entry.key;
      final own = entry.value;
      final event = TableLifecycleEvent(
        kind: own.paid
            ? TableLifecycleKind.paid
            : (own.paymentPending
                ? TableLifecycleKind.paymentPending
                : TableLifecycleKind.updated),
        tableId: tableId,
        tableNumber: own.tableNumber,
        waiterId: self.id,
        waiterName: self.name,
        guestCount: own.guestCount,
        total: own.total,
        itemCount: own.itemCount,
        items: own.items,
      );
      _net?.sendTo(
        peerId,
        WireMessage(
          type: WireMessageType.tableUpdate,
          senderId: self.id,
          senderName: self.name,
          branchId: self.branchId,
          data: event.toJson(),
        ),
      );
    }
  }

  // --- Broadcast helpers ---

  void _announceSelf() {
    final self = session.self!;
    _net?.broadcast(WireMessage(
      type: WireMessageType.waiterAnnounce,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
      data: {'status': self.status.wireValue},
    ));
  }

  void _broadcastStatus() {
    final self = session.self!;
    _net?.broadcast(WireMessage(
      type: WireMessageType.waiterStatus,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
      data: {'status': self.status.wireValue},
    ));
  }

  void _broadcastLeave() {
    final self = session.self;
    if (self == null) return;
    _net?.broadcast(WireMessage(
      type: WireMessageType.waiterLeave,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
    ));
  }
}
