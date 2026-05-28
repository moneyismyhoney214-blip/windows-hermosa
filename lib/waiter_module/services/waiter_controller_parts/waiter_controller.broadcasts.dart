part of '../waiter_controller.dart';

// Broadcast / unicast helpers extracted from waiter_controller.dart. All
// methods stay instance methods on `WaiterController` via the extension
// below — no behaviour change, just file-level separation so the main
// controller file stays under the god-file threshold.

extension WaiterControllerBroadcasts on WaiterController {
  void broadcastTableEvent(TableLifecycleEvent event) {
    // Apply locally first so our own registry is up-to-date even
    // without a round-trip from a peer. Matches incoming semantics in
    // _handleIncoming.
    tableRegistry.apply(event);
    _tableEventStream
        .add(WaiterTableEventEnvelope(event: event, fromSelf: true));
    // Mesh not up yet (no session) — the local apply above still
    // happened, which is all a not-yet-connected device can do. Bailing
    // here instead of `session.self!` keeps callers (incl. the cashier's
    // reconcile loop) from crashing when broadcast races startup.
    final self = session.self;
    if (self == null) return;
    _net?.broadcast(WireMessage(
      type: WireMessageType.tableUpdate,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
      data: event.toJson(),
    ));
  }

  /// Broadcast a waitlist delta to every connected peer. The local
  /// [WaitlistService] calls this via the mesh bridge for every mutation
  /// so both the cashier and every waiter see the same queue.
  ///
  /// A self-echo is emitted on [onWaitlistEvent] so any other local
  /// listener (e.g. a badge counter that watches the stream rather than
  /// the service directly) gets a uniform signal regardless of origin.
  void broadcastWaitlistEvent(WaitlistMeshEvent event) {
    _waitlistEventStream.add(
      WaitlistMeshEventEnvelope(event: event, fromSelf: true),
    );
    final self = session.self;
    if (self == null) return;
    _net?.broadcast(WireMessage(
      type: WireMessageType.waitlistEvent,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
      data: event.toJson(),
    ));
  }

  /// Send a full-queue snapshot to a specific peer. Used as HELLO
  /// catch-up so a freshly joined device starts with the same waitlist
  /// the rest of the LAN already has — without waiting for the next
  /// mutation.
  void pushWaitlistSnapshotTo(
    String peerId,
    WaitlistMeshSnapshot snapshot,
  ) {
    final self = session.self;
    if (self == null) return;
    _net?.sendTo(
      peerId,
      WireMessage(
        type: WireMessageType.waitlistSnapshot,
        senderId: self.id,
        senderName: self.name,
        branchId: self.branchId,
        data: snapshot.toJson(),
      ),
    );
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

  /// Broadcast the cashier's WAWP credentials (`{instance_id,
  /// access_token}`) so every waiter can send waitlist messages through
  /// the WAWP API — the same channel the cashier's "Send invoice via
  /// WhatsApp" uses — instead of the `wa.me` deep-link fallback. The
  /// waiter token's branch-settings endpoint doesn't always carry these,
  /// so the cashier (which always has them) is the source of truth.
  /// Viewer-only, like the other config broadcasts.
  void broadcastWhatsAppConfig(Map<String, dynamic> payload) {
    final self = session.self;
    if (self == null) return;
    if (!self.isViewer) return;
    _net?.broadcast(WireMessage(
      type: WireMessageType.configWhatsApp,
      senderId: self.id,
      senderName: self.name,
      branchId: self.branchId,
      data: payload,
    ));
  }

  void pushWhatsAppConfigTo(String peerId, Map<String, dynamic> payload) {
    final self = session.self;
    if (self == null) return;
    if (!self.isViewer) return;
    _net?.sendTo(
      peerId,
      WireMessage(
        type: WireMessageType.configWhatsApp,
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
}
