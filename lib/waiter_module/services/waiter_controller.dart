import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../locator.dart';
import '../models/network_message.dart';
import '../models/table_migrate_event.dart';
import '../models/table_pickup_request.dart';
import '../models/waiter.dart';
import '../models/waiter_message.dart';
import '../models/waiter_table_event.dart';
import 'waiter_cart_store.dart';
import 'waiter_config_store.dart';
import 'waiter_discovery_service.dart';
import 'waiter_message_store.dart';
import 'waiter_network_service.dart';
import 'waiter_notification_service.dart';
import 'waiter_pickup_store.dart';
import 'waiter_roster_service.dart';
import 'waiter_session_service.dart';
import 'waiter_table_registry.dart';

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

  bool _running = false;
  bool get isRunning => _running;

  /// Single-flight guard: if two callers hit [start] back-to-back while the
  /// first is still awaiting mDNS/Bonsoir, the second mustn't spin up a
  /// second set of broadcasts. They both wait on the same Future.
  Future<void>? _starting;

  WaiterController({
    required this.session,
    required this.roster,
    required this.messages,
    required this.notifications,
    required this.tableRegistry,
    required this.configStore,
    required this.pickupStore,
  });

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

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
      // Previous branch's mesh state must not leak into the new one.
      // tableRegistry, messageStore, pickupStore all hold data scoped
      // to the prior branch — clear before the new identity goes live.
      clearSessionStores();
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
  void clearSessionStores() {
    messages.clear();
    pickupStore.clear();
    tableRegistry.clearAll();
    roster.clear();
    try {
      getIt<WaiterCartStore>().clearAll();
    } catch (_) {}
    debugPrint('🧹 waiter session stores cleared');
  }

  Future<void> start() async {
    if (_running) return;
    // Join an in-flight start instead of spawning a second broadcast.
    // Without this, two rapid `ensureViewer` calls (e.g. Tables screen
    // rebuilt twice during login) each initialize discovery — producing
    // the duplicate `waiter-Cashier-viewer (2)` service we see on the
    // LAN and two socket listeners racing to HELLO the same peers.
    if (_starting != null) return _starting!;
    final self = session.self;
    if (self == null) {
      throw StateError('WaiterController.start() called before session init');
    }

    final completer = Completer<void>();
    _starting = completer.future;

    // Guard against partial-startup wedges: if any step throws, the
    // resources we already brought up must be released so a retry isn't
    // blocked by `_running=true` holding a dead controller.
    try {
      _net = WaiterNetworkService(selfProvider: () => session.self!);
      final port = await _net!.startServer();

      _discovery = WaiterDiscoveryService(self: self, advertisedPort: port);
      await _discovery!.start();

      _msgSub = _net!.incoming.listen(_handleIncoming);
      _foundSub = _discovery!.onFound.listen(_handlePeerFound);
      _lostSub = _discovery!.onLost.listen((_) {});

      _heartbeatTimer =
          Timer.periodic(_kHeartbeatInterval, (_) => _heartbeat());
      _staleSweepTimer =
          Timer.periodic(_kStaleSweepInterval, (_) => _sweepStalePeers());

      _running = true; // commit AFTER successful setup
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

  Future<void> _tearDownPartialStart() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _staleSweepTimer?.cancel();
    _staleSweepTimer = null;
    try { await _msgSub?.cancel(); } catch (_) {}
    try { await _foundSub?.cancel(); } catch (_) {}
    try { await _lostSub?.cancel(); } catch (_) {}
    _msgSub = null;
    _foundSub = null;
    _lostSub = null;
    try { await _discovery?.dispose(); } catch (_) {}
    try { await _net?.dispose(); } catch (_) {}
    _discovery = null;
    _net = null;
    _running = false;
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _staleSweepTimer?.cancel();
    _staleSweepTimer = null;

    // Notify peers we're leaving.
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
    _callStream.close();
    _tableEventStream.close();
    _peerHelloStream.close();
    _configSyncRequestStream.close();
    _pickupRequestStream.close();
    _pickupUpdateStream.close();
    _tableMigrateStream.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Outbound actions
  // ---------------------------------------------------------------------------

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
    // Broadcast target → fan out to everyone on the LAN. Directed → one.
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
    // Update our local copy first for instant UI feedback.
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
  }

  void broadcastTableEvent(TableLifecycleEvent event) {
    _tableEventStream
        .add(WaiterTableEventEnvelope(event: event, fromSelf: true));
    final self = session.self!;
    _net?.broadcast(WireMessage(
      type: WireMessageType.tableUpdate,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
      data: event.toJson(),
    ));
  }

  /// Fan out a fresh kitchen-printer snapshot to every connected waiter.
  /// Only the cashier (viewer) should call this; waiters produce no
  /// authoritative config. `payload` is the full JSON map from
  /// [SyncedKitchenPrintersConfig.toJson].
  void broadcastKitchenPrintersConfig(Map<String, dynamic> payload) {
    final self = session.self;
    if (self == null) return;
    if (!self.isViewer) return;
    _net?.broadcast(WireMessage(
      type: WireMessageType.configKitchenPrinters,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
      data: payload,
    ));
  }

  /// Same as [broadcastKitchenPrintersConfig] but targets a single peer —
  /// used for the push-on-HELLO catch-up so late joiners match state
  /// without flooding the network.
  void pushKitchenPrintersConfigTo(
    String peerId,
    Map<String, dynamic> payload,
  ) {
    final self = session.self;
    if (self == null) return;
    if (!self.isViewer) return;
    _net?.sendTo(
      peerId,
      WireMessage(
        type: WireMessageType.configKitchenPrinters,
        senderId: self.id,
        senderName: self.name,
        branchId: self.branchId,
        data: payload,
      ),
    );
  }

  /// Broadcast the KDS host/port the cashier is connected to.
  void broadcastKdsEndpoint(Map<String, dynamic> payload) {
    final self = session.self;
    if (self == null) return;
    if (!self.isViewer) return;
    _net?.broadcast(WireMessage(
      type: WireMessageType.configKdsEndpoint,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
      data: payload,
    ));
  }

  void pushKdsEndpointTo(String peerId, Map<String, dynamic> payload) {
    final self = session.self;
    if (self == null) return;
    if (!self.isViewer) return;
    _net?.sendTo(
      peerId,
      WireMessage(
        type: WireMessageType.configKdsEndpoint,
        senderId: self.id,
        senderName: self.name,
        branchId: self.branchId,
        data: payload,
      ),
    );
  }

  /// Ask the nearest cashier (viewer) to replay its latest config
  /// snapshots. Intended for a future waiter-side "refresh" action —
  /// unused in the Phase 1 happy path because the cashier already pushes
  /// on every HELLO.
  void requestConfigSync() {
    final self = session.self;
    if (self == null) return;
    _net?.broadcast(WireMessage(
      type: WireMessageType.configSyncRequest,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
    ));
  }

  // ---------------------------------------------------------------------------
  // Table pickup ("استلام") — Uber-style broadcast/claim.
  // ---------------------------------------------------------------------------

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
      // Cashiers can't claim their own broadcasts. Silent no-op: a
      // cashier tapping the accept button by mistake shouldn't crash.
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
    // Fold the claim into the existing table-lifecycle plumbing so the
    // cashier's tables screen reuses the standard "assigned" visual
    // and the claimer's own tableRegistry reflects ownership.
    broadcastTableEvent(TableLifecycleEvent(
      kind: TableLifecycleKind.assigned,
      tableId: claimed.tableId,
      tableNumber: claimed.tableNumber,
      waiterId: self.id,
      waiterName: self.name,
    ));
    return claimed;
  }

  // ---------------------------------------------------------------------------
  // Table migration — cashier moves a seated party to a different table.
  // ---------------------------------------------------------------------------

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
    if (!self.isViewer) {
      throw StateError(
        'Only the cashier (viewer) may migrate a table.',
      );
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
    return event;
  }

  /// Called internally (by [_handleIncoming]) when an incoming migrate
  /// names a table *this* device owns. Moves cart state and broadcasts
  /// a release + assign so every other peer's registry converges.
  void _applyMigrateAsOwner(TableMigrateEvent event) {
    final self = session.self;
    if (self == null) return;

    // Move the local cart (drafts + sent + guests) to the new table.
    WaiterCartStore? cart;
    try {
      cart = getIt<WaiterCartStore>();
    } catch (_) {}
    cart?.moveTableCart(event.oldTableId, event.newTableId);

    final snapshot = tableRegistry.lookup(event.oldTableId);
    final guests = snapshot?.guestCount;
    final total = snapshot?.total;
    final itemCount = snapshot?.itemCount;
    final items = snapshot?.items;

    // Release the old table so the cashier's tables screen flips it to
    // available + clears our own registry entry.
    broadcastTableEvent(TableLifecycleEvent(
      kind: TableLifecycleKind.released,
      tableId: event.oldTableId,
      tableNumber: event.oldTableNumber,
      waiterId: self.id,
      waiterName: self.name,
    ));

    // Re-assign the new table with the carried-over order state so the
    // cashier sees exactly what the party already ordered, but under
    // the new table number.
    broadcastTableEvent(TableLifecycleEvent(
      kind: TableLifecycleKind.assigned,
      tableId: event.newTableId,
      tableNumber: event.newTableNumber,
      waiterId: self.id,
      waiterName: self.name,
      guestCount: guests,
      total: total,
      itemCount: itemCount,
      items: items,
    ));
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

  // ---------------------------------------------------------------------------
  // Inbound handling
  // ---------------------------------------------------------------------------

  void _handlePeerFound(Waiter peer) {
    final self = session.self;
    if (self == null) return;
    if (peer.branchId.isNotEmpty &&
        self.branchId.isNotEmpty &&
        peer.branchId != self.branchId) {
      return; // Different branch — ignore
    }
    roster.upsert(peer);
    // Only connect once we have host+port. For outbound we initiate from the
    // lower id to avoid both sides dialling each other.
    if (peer.host != null && peer.port != null && self.id.compareTo(peer.id) < 0) {
      _net?.connectToPeer(peer);
    }
  }

  void _handleIncoming(WireMessage msg) {
    // If we're mid-shutdown, don't touch any streams — they may be
    // closed already and .add() on a closed StreamController throws.
    // Network callbacks can arrive after we cancel our own subscription
    // so this guard isn't theoretical.
    if (!_running) return;

    final self = session.self;
    if (self == null) return;
    if (msg.senderId == self.id) return; // ignore self-loop

    // Cross-branch isolation: mDNS discovery already filters by branch,
    // but a peer that connects directly (e.g. a stale cached IP after a
    // branch switch) would bypass that filter. Drop any message whose
    // envelope disagrees with ours so branches never bleed into each
    // other's rosters or table state.
    if (self.branchId.isNotEmpty &&
        msg.branchId.isNotEmpty &&
        msg.branchId != self.branchId) {
      return;
    }

    // Any inbound message proves the peer is alive — refresh lastSeen so
    // the sweep doesn't mark it offline. This works for every message
    // type (not just HEARTBEAT) so quiet peers stay online as long as
    // they're exchanging table/messages/etc.
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
        // Late joiner: snapshot every table I currently own and push the
        // TABLE_UPDATE events to just this peer so their registry matches
        // ours without them having to wait for an edit. Only on first
        // sight so duplicate HELLOs during reconnect don't re-flood.
        if (isNewPeer) {
          _pushOwnedTablesSnapshotTo(msg.senderId);
          // Waiter-side: re-announce my own claimed pickups to the new
          // peer so a claim whose original broadcast dropped (cashier
          // restart, Wi-Fi glitch) still converges once both ends see
          // each other. Viewers never claim, so this is a no-op there.
          if (!self.isViewer) _replayOwnClaimsTo(msg.senderId);
        }
        // Emit on every HELLO (not just first sight). The cashier side
        // listens on [onPeerHello] and pushes its current printer + KDS
        // snapshots; the waiter's [WaiterConfigStore] version-gates the
        // payload so repeated pushes are idempotent.
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
            notifications.playCall();
            _callStream.add(incoming);
          }
        }
        break;

      case WireMessageType.waiterCallAccepted:
        // A peer claimed a broadcast. Update our local copy so the
        // accept button turns into "تم الاستلام بواسطة X" on every
        // device that's still showing the notification.
        //
        // Anti-spoof: the payload's `waiter_id` must match the wire
        // envelope's `sender_id` — otherwise a malicious peer could
        // forge "X accepted" on X's behalf.
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
          _tableEventStream.add(WaiterTableEventEnvelope(
            event: TableLifecycleEvent.fromJson(msg.data),
            fromSelf: false,
          ));
        } catch (_) {}
        break;

      case WireMessageType.heartbeat:
        // Keep-alive only — already refreshed lastSeen above.
        break;

      case WireMessageType.configKitchenPrinters:
        // Cashier echoes its snapshot back to itself if a second cashier
        // broadcasts; isViewer guard on the store would accept valid
        // newer versions. On the waiter device this populates the store
        // so future direct-print-from-waiter can resolve printers.
        if (self.isViewer) break;
        unawaited(
          configStore.applyKitchenPrinters(msg.data, sourceId: msg.senderId),
        );
        break;

      case WireMessageType.configKdsEndpoint:
        if (self.isViewer) break;
        unawaited(
          configStore.applyKdsEndpoint(msg.data, sourceId: msg.senderId),
        );
        break;

      case WireMessageType.configSyncRequest:
        // Only viewers respond. Re-emit so the cashier bootstrap can
        // decide whether to honor the request.
        if (!self.isViewer) break;
        _configSyncRequestStream.add(msg.senderId);
        break;

      case WireMessageType.tablePickupRequest:
        // Cashier echoes its own broadcast (self-loop already filtered
        // above). For a viewer the best action is to record — a second
        // cashier on the LAN shouldn't silently diverge.
        //
        // Anti-spoof: only a viewer (cashier) legitimately issues
        // pickup requests. Reject if the sender isn't one, otherwise
        // any waiter could fabricate "cashier X requested a pickup"
        // and every tablet would ring.
        if (!msg.senderId.startsWith(Waiter.viewerIdPrefix)) {
          debugPrint(
              '⚠️ dropping TABLE_PICKUP_REQUEST from non-viewer sender=${msg.senderId}');
          break;
        }
        try {
          final req = TablePickupRequest.fromJson(msg.data);
          final recorded = pickupStore.recordRequest(req);
          if (recorded && !self.isViewer) {
            // Only a real waiter gets the audible alert — cashiers
            // watching the tables screen already see the card change.
            notifications.playCall();
            _pickupRequestStream.add(req);
          } else if (recorded && self.isViewer) {
            _pickupRequestStream.add(req);
          }
        } catch (_) {}
        break;

      case WireMessageType.tablePickupClaimed:
        try {
          final rid = msg.data['request_id']?.toString() ?? '';
          final wid = msg.data['waiter_id']?.toString() ?? '';
          final wname = msg.data['waiter_name']?.toString() ?? '';
          if (rid.isEmpty || wid.isEmpty) break;

          // Anti-spoof: the claimer in the payload must be the sender.
          // Without this a peer can forge "Waiter X claimed" on X's
          // behalf and every device would accept it.
          if (wid != msg.senderId) {
            debugPrint(
                '⚠️ dropping TABLE_PICKUP_CLAIMED: waiter_id=$wid != sender_id=${msg.senderId}');
            break;
          }

          final claimedAt = DateTime.tryParse(
            msg.data['claimed_at']?.toString() ?? '',
          );

          // Orphan claim recovery: if the cashier restarted while a
          // pickup was in flight, it no longer has the original request
          // in memory. Synthesize a minimal record from what the claim
          // carries so the tables screen still flips the card and the
          // claim is visible in the notifications feed.
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
        } catch (_) {}
        break;

      case WireMessageType.tablePickupCancelled:
        // Anti-spoof: only cashiers can cancel. Without this a rogue
        // waiter could dismiss a pending request from other waiters'
        // banners. We enforce viewer-prefix on the sender id since
        // that's the LAN-level marker for "this peer is a cashier".
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
        } catch (_) {}
        break;

      case WireMessageType.tableMigrate:
        try {
          final event = TableMigrateEvent.fromJson(msg.data);
          _tableMigrateStream.add(event);
          // Only the waiter that currently owns the old table needs to
          // do the cart shuffle + re-broadcast release/assign — every
          // other peer picks up the state change from those echoes.
          final ownerId = tableRegistry.ownerIdFor(event.oldTableId);
          if (ownerId != null && ownerId == self.id) {
            _applyMigrateAsOwner(event);
          }
        } catch (_) {}
        break;

      case WireMessageType.helloAck:
      case WireMessageType.ack:
      case WireMessageType.error:
      case WireMessageType.newOrder:
      case WireMessageType.updateCart:
      case WireMessageType.orderEdit:
      case WireMessageType.orderCancel:
        // Waiter peers don't act on these; the KDS handles kitchen traffic.
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Keep-alive
  // ---------------------------------------------------------------------------

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
    // Roster is a ChangeNotifier — subscribers (tables screen, home
    // shell) will re-render automatically when peers flip to offline.
    // No need for a separate event stream.
    final flipped = roster.sweepStale();
    // Tear down any half-dead socket so the next HELLO from this peer
    // starts fresh: if we kept the old conn, `connectToPeer` would
    // short-circuit on `_peers.containsKey(...)` and we'd never pick
    // up their reconnect. _scheduleReconnect fires on drop for
    // outbound conns, so this also re-establishes the link
    // autonomously when they come back.
    for (final id in flipped) {
      _net?.closeConnectionTo(id);
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

  // ---------------------------------------------------------------------------
  // Broadcast helpers
  // ---------------------------------------------------------------------------

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
