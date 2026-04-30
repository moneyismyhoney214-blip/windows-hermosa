import 'dart:async';

import '../models/waitlist_mesh_event.dart';
import '../waiter_module/services/waiter_controller.dart';
import 'waitlist_service.dart';

/// Glue between [WaitlistService] (which is transport-agnostic) and
/// [WaiterController] (which owns the LAN socket). Lives as a singleton
/// so a single pair of subscriptions handles every screen.
///
/// Lifecycle: call [attach] once the controller has been constructed
/// (and after the waitlist service is initialized). Call [detach] on
/// sign-out before the controller disposes.
///
/// Why a dedicated object instead of inlining in one of the services?
///   * The waitlist service shouldn't import the waiter module
///     (prevents circular deps + keeps it reusable).
///   * The waiter controller shouldn't know how to persist waitlist
///     state (already has enough responsibility).
///   * Snapshots on peer-HELLO are orthogonal to individual deltas —
///     keeping both pieces together here documents the pattern.
class WaitlistMeshBridge {
  static final WaitlistMeshBridge _instance = WaitlistMeshBridge._internal();
  factory WaitlistMeshBridge() => _instance;
  WaitlistMeshBridge._internal();

  WaiterController? _controller;
  StreamSubscription<WaitlistMeshEventEnvelope>? _eventSub;
  StreamSubscription<WaitlistMeshSnapshot>? _snapshotSub;
  StreamSubscription<String>? _peerHelloSub;

  bool get isAttached => _controller != null;

  /// Wire the service to the controller. Safe to call repeatedly — a
  /// second call on the same controller is a no-op; a call with a
  /// different controller tears down the old subscriptions first.
  void attach(WaiterController controller) {
    if (identical(_controller, controller)) return;
    detach();
    _controller = controller;

    // 1) Local mutations → broadcast to every peer.
    waitlistService.registerBroadcaster(controller.broadcastWaitlistEvent);

    // 2) Remote deltas → apply to local service (without re-broadcasting).
    _eventSub = controller.onWaitlistEvent.listen((envelope) {
      if (envelope.fromSelf) return;
      waitlistService.applyRemote(envelope.event);
    });

    // 3) Remote snapshots → merge into local state.
    _snapshotSub = controller.onWaitlistSnapshot.listen((snapshot) {
      waitlistService.applySnapshot(snapshot);
    });

    // 4) A new peer just announced — push them our current queue so
    // they don't have to wait for the next mutation to catch up. Only
    // fires on peers we haven't already synced to recently (the
    // controller already throttles HELLOs to one per peer per session).
    _peerHelloSub = controller.onPeerHello.listen((peerId) {
      // Skip empty queues — nothing to share, saves bandwidth.
      final snapshot = waitlistService.buildSnapshot();
      if (snapshot.entries.isEmpty) return;
      controller.pushWaitlistSnapshotTo(peerId, snapshot);
    });
  }

  /// Tear down subscriptions + unhook the broadcaster. Called on
  /// sign-out so the next attach starts clean.
  void detach() {
    waitlistService.registerBroadcaster(null);
    _eventSub?.cancel();
    _eventSub = null;
    _snapshotSub?.cancel();
    _snapshotSub = null;
    _peerHelloSub?.cancel();
    _peerHelloSub = null;
    _controller = null;
  }
}

final waitlistMeshBridge = WaitlistMeshBridge();
