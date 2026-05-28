import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../services/logger_service.dart';
import '../models/network_message.dart';
import '../models/waiter.dart';
import 'mesh_auth_service.dart';

/// Waiter-peer WebSocket hub.
///
/// On every waiter device this service:
///   * Binds an [HttpServer] that upgrades any inbound connection to a
///     WebSocket (so peers can push messages to *this* waiter).
///   * Opens outbound WebSocket connections to every discovered peer so
///     *this* waiter can push to them.
///   * Exposes a single [incoming] stream and a single [broadcast] method
///     regardless of direction — the transport is an implementation detail.
///
/// A minimal [WireMessageType.hello] handshake happens on every new
/// connection so both sides know who is on the wire.
class WaiterNetworkService {
  final Waiter Function() selfProvider;
  final int preferredPort;
  /// Application-layer auth — signs every outgoing message and
  /// verifies every incoming one. Optional so unit tests / pre-login
  /// boot don't have to wire one up; in production the locator
  /// always supplies one.
  final MeshAuthService? auth;

  HttpServer? _server;
  int _boundPort = 0;
  bool _disposed = false;

  final Map<String, _PeerConnection> _peers = {};
  // Last host:port per peer for autonomous reconnect without a new mDNS event.
  final Map<String, _PeerAddress> _lastKnownAddresses = {};
  final Map<String, Timer> _reconnectTimers = {};
  // Track in-flight outbound connects so a discovery burst doesn't spawn parallel sockets.
  final Set<String> _connectingPeerIds = <String>{};
  final StreamController<WireMessage> _incoming =
      StreamController<WireMessage>.broadcast();

  /// Bounded LRU of recently-seen WireMessage IDs. A peer flapping its
  /// WS connection or a multicast bouncing off two interfaces can land
  /// the same message twice; without dedup, listeners would double-
  /// process it (a duplicate kitchen ticket, a phantom paymentPending,
  /// a second pickup-claim ack). Capped at [_seenIdLimit] so the set
  /// can't grow unbounded over a long shift.
  static const int _seenIdLimit = 512;
  final LinkedHashSet<String> _seenMessageIds = LinkedHashSet<String>();
  // Inbound channels closed after handshake timeout (MESH-5) to avoid FD exhaustion.
  static const Duration _helloTimeout = Duration(seconds: 5);
  final Map<_PeerConnection, Timer> _helloTimers = {};

  Stream<WireMessage> get incoming => _incoming.stream;

  /// Port we are actually bound to — needed for the mDNS advertisement.
  int get boundPort => _boundPort;

  WaiterNetworkService({
    required this.selfProvider,
    this.preferredPort = 47231,
    this.auth,
  });

  // --- Lifecycle ---

  Future<int> startServer() async {
    if (_server != null) return _boundPort;

    int attempt = preferredPort;
    HttpServer? server;
    for (int i = 0; i < 20; i++) {
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, attempt);
        break;
      } on SocketException {
        attempt += 1;
      }
    }
    server ??= await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    _boundPort = server.port;
    debugPrint('🖧 Waiter WS server listening on :$_boundPort');

    server.listen((HttpRequest req) async {
      if (!WebSocketTransformer.isUpgradeRequest(req)) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }
      try {
        // ignore: close_sinks  // ownership passes to _handleChannel via the channel
        final ws = await WebSocketTransformer.upgrade(req);
        final channel = IOWebSocketChannel(ws);
        _handleChannel(channel, inbound: true);
      } catch (e) {
        debugPrint('⚠️ Waiter WS upgrade failed: $e');
      }
    }, onError: (e) {
      debugPrint('⚠️ Waiter HttpServer error: $e');
    });

    return _boundPort;
  }

  Future<void> connectToPeer(Waiter peer) async {
    if (peer.host == null || peer.port == null) return;
    // Remember target so _scheduleReconnect can retry without mDNS.
    _lastKnownAddresses[peer.id] =
        _PeerAddress(host: peer.host!, port: peer.port!);
    if (_peers.containsKey(peer.id)) return; // already connected
    // Dedup overlapping mDNS-event-driven connect attempts.
    if (_connectingPeerIds.contains(peer.id)) return;
    _connectingPeerIds.add(peer.id);
    try {
      final uri = Uri.parse('ws://${peer.host}:${peer.port}/waiter');
      final channel = WebSocketChannel.connect(uri);
      _handleChannel(channel, inbound: false, knownPeerId: peer.id);
      // Send HELLO immediately so the peer associates our id with the channel.
      _sendHandshake(channel);
    } catch (e) {
      debugPrint('⚠️ Waiter WS connect to ${peer.name} failed: $e');
      _scheduleReconnect(peer.id);
    } finally {
      _connectingPeerIds.remove(peer.id);
    }
  }

  void _scheduleReconnect(String peerId) {
    if (_disposed) return;
    if (!_lastKnownAddresses.containsKey(peerId)) return;
    _reconnectTimers[peerId]?.cancel();
    _reconnectTimers[peerId] = Timer(const Duration(seconds: 3), () {
      _reconnectTimers.remove(peerId);
      final addr = _lastKnownAddresses[peerId];
      if (_disposed || addr == null || _peers.containsKey(peerId)) return;
      debugPrint('🔁 Reconnecting to peer $peerId at ${addr.host}:${addr.port}');
      final self = selfProvider();
      connectToPeer(Waiter(
        id: peerId,
        name: '', // name will be refreshed on HELLO
        branchId: self.branchId,
        host: addr.host,
        port: addr.port,
      ));
    });
  }

  void _handleChannel(
    WebSocketChannel channel, {
    required bool inbound,
    String? knownPeerId,
  }) {
    final conn = _PeerConnection(
      channel: channel,
      peerId: knownPeerId,
      inbound: inbound,
    );

    if (knownPeerId != null) _peers[knownPeerId] = conn;

    // Inbound HELLO timeout — silent half-open peers would exhaust server FDs otherwise.
    if (inbound) {
      _helloTimers[conn] = Timer(_helloTimeout, () {
        _helloTimers.remove(conn);
        if (conn.peerId != null) return; // HELLO arrived
        debugPrint(
          '⏱ Closing inbound WS that never sent HELLO within '
          '${_helloTimeout.inSeconds}s',
        );
        _dropConnection(conn);
      });
    }

    channel.stream.listen(
      (raw) {
        if (raw is! String) return;
        // App-layer auth before parse — bad-MAC forgeries dropped silently to avoid polluting dedup. Unsigned accepted in pre-login boot window.
        if (auth != null && !auth!.verifyRaw(raw)) {
          debugPrint('🚫 Waiter mesh: dropping unsigned/forged message');
          return;
        }
        final msg = WireMessage.tryDecode(raw);
        if (msg == null) return;

        // Drop replays/multicast bounces — sliding LRU window prevents double-processing.
        if (_seenMessageIds.contains(msg.id)) {
          return;
        }
        _seenMessageIds.add(msg.id);
        if (_seenMessageIds.length > _seenIdLimit) {
          final oldest = _seenMessageIds.first;
          _seenMessageIds.remove(oldest);
        }

        if (msg.type == WireMessageType.hello) {
          _helloTimers.remove(conn)?.cancel();
          if (conn.peerId == null) {
            conn.peerId = msg.senderId;
            // Close stale prior connection so reconnects don't leak sockets.
            final prior = _peers[msg.senderId];
            if (prior != null && prior != conn) {
              try {
                prior.channel.sink.close();
              } catch (e) { Log.w('waiter-net', 'cleanup/socket op failed', error: e); }
            }
            _peers[msg.senderId] = conn;
          }
          _sendAck(channel, msg);
          // Inbound replies with HELLO so remote locks our id; outbound already sent its HELLO.
          if (inbound) _sendHandshake(channel);
        }

        _incoming.add(msg);
      },
      onError: (e) {
        debugPrint('⚠️ Waiter WS stream error: $e');
        _dropConnection(conn);
      },
      onDone: () => _dropConnection(conn),
      cancelOnError: true,
    );
    // Don't pre-send HELLO on inbound — racy with remote's HELLO; reply only after receiving.
  }

  /// Wire-encode + sign a message in one place so every outbound
  /// path (HELLO, ACK, broadcast, sendTo) gets the MAC the receiver
  /// expects. When [auth] is null (test wiring or pre-locator boot),
  /// falls back to the unsigned encoding the receiver also accepts
  /// in its boot window.
  String _encodeForWire(WireMessage msg) {
    final a = auth;
    return a != null ? a.signMessage(msg) : msg.encode();
  }

  void _sendHandshake(WebSocketChannel ch) {
    final me = selfProvider();
    final hello = WireMessage(
      type: WireMessageType.hello,
      senderId: me.id,
      senderName: me.name,
      branchId: me.branchId,
      data: {
        'status': me.status.wireValue,
      },
    );
    try {
      ch.sink.add(_encodeForWire(hello));
    } catch (e) { Log.w('waiter-net', 'cleanup/socket op failed', error: e); }
  }

  void _sendAck(WebSocketChannel ch, WireMessage original) {
    final me = selfProvider();
    final ack = WireMessage(
      type: WireMessageType.ack,
      senderId: me.id,
      senderName: me.name,
      branchId: me.branchId,
      data: {'ref': original.id},
    );
    try {
      ch.sink.add(_encodeForWire(ack));
    } catch (e) { Log.w('waiter-net', 'cleanup/socket op failed', error: e); }
  }

  void _dropConnection(_PeerConnection conn) {
    _helloTimers.remove(conn)?.cancel();
    try {
      conn.channel.sink.close();
    } catch (e) { Log.w('waiter-net', 'cleanup/socket op failed', error: e); }
    final id = conn.peerId;
    if (id != null && _peers[id] == conn) {
      _peers.remove(id);
      // Outbound: schedule reconnect — transient Wi-Fi glitches shouldn't strand the mesh.
      if (!conn.inbound) {
        _scheduleReconnect(id);
      }
    }
  }

  // --- Sending ---

  /// Forcibly close any open socket to [peerId]. Called when the roster
  /// sweep decides a peer is stale — keeping a half-dead socket open
  /// means `connectToPeer` would short-circuit on `_peers.containsKey`
  /// and reconnect logic never engages. Closing ensures the next HELLO
  /// from that peer lands on a fresh connection.
  void closeConnectionTo(String peerId) {
    // Drop remembered address and cancel retry FIRST so _dropConnection can't re-arm the loop.
    _lastKnownAddresses.remove(peerId);
    _reconnectTimers.remove(peerId)?.cancel();
    final conn = _peers[peerId];
    if (conn == null) return;
    _dropConnection(conn);
  }

  /// Fan-out a message to every connected peer.
  void broadcast(WireMessage msg) {
    final encoded = _encodeForWire(msg);
    for (final conn in _peers.values.toList(growable: false)) {
      try {
        conn.channel.sink.add(encoded);
      } catch (e) { Log.w('waiter-net', 'cleanup/socket op failed', error: e); }
    }
  }

  /// Send to a single peer by id. Silently drops if not connected.
  void sendTo(String peerId, WireMessage msg) {
    final conn = _peers[peerId];
    if (conn == null) return;
    try {
      conn.channel.sink.add(_encodeForWire(msg));
    } catch (e) { Log.w('waiter-net', 'cleanup/socket op failed', error: e); }
  }

  /// Connected peer ids, for UI / debugging.
  Iterable<String> get connectedPeerIds => _peers.keys;

  // --- Disposal ---

  Future<void> dispose() async {
    _disposed = true;
    for (final t in _reconnectTimers.values) {
      t.cancel();
    }
    _reconnectTimers.clear();
    for (final t in _helloTimers.values) {
      t.cancel();
    }
    _helloTimers.clear();
    _seenMessageIds.clear();
    _lastKnownAddresses.clear();
    for (final conn in _peers.values.toList(growable: false)) {
      _dropConnection(conn);
    }
    _peers.clear();
    try {
      await _server?.close(force: true);
    } catch (e) { Log.w('waiter-net', 'cleanup/socket op failed', error: e); }
    _server = null;
    await _incoming.close();
  }
}

class _PeerAddress {
  final String host;
  final int port;
  const _PeerAddress({required this.host, required this.port});
}

class _PeerConnection {
  final WebSocketChannel channel;
  String? peerId;
  final bool inbound;

  _PeerConnection({
    required this.channel,
    required this.peerId,
    required this.inbound,
  });
}

// ignore: unused_element
String _encodeMap(Map<String, dynamic> m) => jsonEncode(m);
