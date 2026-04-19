import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/network_message.dart';
import '../models/waiter.dart';

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

  HttpServer? _server;
  int _boundPort = 0;
  bool _disposed = false;

  final Map<String, _PeerConnection> _peers = {};
  // Remember the last resolved host:port for each peer so we can reconnect
  // autonomously after a WS drop without waiting for a new mDNS event.
  final Map<String, _PeerAddress> _lastKnownAddresses = {};
  final Map<String, Timer> _reconnectTimers = {};
  // Track outbound connects that haven't produced a registered socket yet
  // so two rapid discovery events don't spawn two parallel connections to
  // the same peer.
  final Set<String> _connectingPeerIds = <String>{};
  final StreamController<WireMessage> _incoming =
      StreamController<WireMessage>.broadcast();

  Stream<WireMessage> get incoming => _incoming.stream;

  /// Port we are actually bound to — needed for the mDNS advertisement.
  int get boundPort => _boundPort;

  WaiterNetworkService({
    required this.selfProvider,
    this.preferredPort = 47231,
  });

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

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
    if (server == null) {
      // Last resort — let the OS pick any port.
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
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
    // Remember the target so [_scheduleReconnect] can try again later even
    // after mDNS stops re-emitting.
    _lastKnownAddresses[peer.id] =
        _PeerAddress(host: peer.host!, port: peer.port!);
    if (_peers.containsKey(peer.id)) return; // already connected
    // Dedup overlapping attempts: a burst of mDNS events (common when a
    // peer comes online) can fire this twice before the first socket is
    // registered, producing two parallel connections to the same peer.
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
    // Coalesce overlapping retries.
    _reconnectTimers[peerId]?.cancel();
    _reconnectTimers[peerId] = Timer(const Duration(seconds: 3), () {
      _reconnectTimers.remove(peerId);
      final addr = _lastKnownAddresses[peerId];
      if (_disposed || addr == null || _peers.containsKey(peerId)) return;
      debugPrint('🔁 Reconnecting to peer $peerId at ${addr.host}:${addr.port}');
      // Reconstruct a minimal Waiter to reuse [connectToPeer].
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

    // Index by whatever id we have so duplicate connects are avoided.
    if (knownPeerId != null) _peers[knownPeerId] = conn;

    channel.stream.listen(
      (raw) {
        if (raw is! String) return;
        final msg = WireMessage.tryDecode(raw);
        if (msg == null) return;

        // On HELLO we lock the peer id to this connection.
        if (msg.type == WireMessageType.hello) {
          if (conn.peerId == null) {
            conn.peerId = msg.senderId;
            // Close any stale prior connection to the same peer so we
            // don't leak sockets when a peer reconnects.
            final prior = _peers[msg.senderId];
            if (prior != null && prior != conn) {
              try {
                prior.channel.sink.close();
              } catch (_) {}
            }
            _peers[msg.senderId] = conn;
          }
          _sendAck(channel, msg);
          // Inbound peers reply with HELLO so the remote locks *our*
          // id too. Outbound peers already sent HELLO in connectToPeer
          // and their remote's HELLO is a reply — no further reply.
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
    // Note: we do NOT pre-send HELLO for inbound. Sending before we know
    // the remote's id racy — the remote's HELLO may arrive mid-send and
    // a second HELLO would duplicate. Reply only after receiving HELLO.
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
      ch.sink.add(hello.encode());
    } catch (_) {}
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
      ch.sink.add(ack.encode());
    } catch (_) {}
  }

  void _dropConnection(_PeerConnection conn) {
    try {
      conn.channel.sink.close();
    } catch (_) {}
    final id = conn.peerId;
    if (id != null && _peers[id] == conn) {
      _peers.remove(id);
      // For outbound connections we know the remote address — schedule a
      // reconnect so a transient glitch (Wi-Fi hiccup) doesn't stop the
      // waiters talking to each other for the rest of the shift.
      if (!conn.inbound) {
        _scheduleReconnect(id);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  /// Forcibly close any open socket to [peerId]. Called when the roster
  /// sweep decides a peer is stale — keeping a half-dead socket open
  /// means `connectToPeer` would short-circuit on `_peers.containsKey`
  /// and reconnect logic never engages. Closing ensures the next HELLO
  /// from that peer lands on a fresh connection.
  void closeConnectionTo(String peerId) {
    final conn = _peers[peerId];
    if (conn == null) return;
    _dropConnection(conn);
  }

  /// Fan-out a message to every connected peer.
  void broadcast(WireMessage msg) {
    final encoded = msg.encode();
    for (final conn in _peers.values.toList(growable: false)) {
      try {
        conn.channel.sink.add(encoded);
      } catch (_) {}
    }
  }

  /// Send to a single peer by id. Silently drops if not connected.
  void sendTo(String peerId, WireMessage msg) {
    final conn = _peers[peerId];
    if (conn == null) return;
    try {
      conn.channel.sink.add(msg.encode());
    } catch (_) {}
  }

  /// Connected peer ids, for UI / debugging.
  Iterable<String> get connectedPeerIds => _peers.keys;

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    _disposed = true;
    for (final t in _reconnectTimers.values) {
      t.cancel();
    }
    _reconnectTimers.clear();
    _lastKnownAddresses.clear();
    for (final conn in _peers.values.toList(growable: false)) {
      _dropConnection(conn);
    }
    _peers.clear();
    try {
      await _server?.close(force: true);
    } catch (_) {}
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

// Re-export jsonEncode usage to keep the file self-contained if ever reused.
// ignore: unused_element
String _encodeMap(Map<String, dynamic> m) => jsonEncode(m);
