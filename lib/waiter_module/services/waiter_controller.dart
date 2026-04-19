import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/network_message.dart';
import '../models/waiter.dart';
import '../models/waiter_message.dart';
import '../models/waiter_table_event.dart';
import 'waiter_discovery_service.dart';
import 'waiter_message_store.dart';
import 'waiter_network_service.dart';
import 'waiter_notification_service.dart';
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
    }
    debugPrint('👁️ ensureViewer starting on branch $branchId');
    await session.assignViewerIdentity(name: name, branchId: branchId);
    await start();
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
        if (isNewPeer) _pushOwnedTablesSnapshotTo(msg.senderId);
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
        final mid = msg.data['message_id']?.toString();
        final wid = msg.data['waiter_id']?.toString();
        final wname = msg.data['waiter_name']?.toString();
        final atRaw = msg.data['accepted_at']?.toString();
        if (mid != null && wid != null && wname != null) {
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
