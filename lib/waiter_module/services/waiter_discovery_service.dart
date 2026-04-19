import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../models/waiter.dart';

/// Zero-config service discovery for the waiter LAN protocol.
///
/// Each waiter device:
///   1. Advertises itself as `_hermosa-waiter._tcp` with TXT records:
///        id, name, branch_id, status
///      so peers can discover it and pre-populate the roster.
///   2. Browses the same service type to learn about other waiters.
///
/// This is only used for *waiter peers*. To talk to the KDS / cashier we
/// reuse their existing WebSocket endpoints (see [WaiterKitchenBridge]).
class WaiterDiscoveryService {
  static const String serviceType = '_hermosa-waiter._tcp';

  final Waiter _self;
  final int advertisedPort;

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;

  final StreamController<Waiter> _found =
      StreamController<Waiter>.broadcast();
  final StreamController<String> _lost = StreamController<String>.broadcast();

  /// Fires whenever a peer is discovered (or updated).
  Stream<Waiter> get onFound => _found.stream;

  /// Fires with the peer's service name when it disappears.
  Stream<String> get onLost => _lost.stream;

  bool _started = false;

  WaiterDiscoveryService({required Waiter self, required this.advertisedPort})
      : _self = self;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await _startBroadcast();
    } catch (e, st) {
      debugPrint('⚠️ Waiter broadcast failed: $e');
      debugPrintStack(stackTrace: st);
    }
    try {
      await _startDiscovery();
    } catch (e, st) {
      debugPrint('⚠️ Waiter discovery failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> _startBroadcast() async {
    final service = BonsoirService(
      name: 'waiter-${_self.name}-${_self.id.substring(0, _self.id.length < 6 ? _self.id.length : 6)}',
      type: serviceType,
      port: advertisedPort,
      attributes: {
        'id': _self.id,
        'name': _self.name,
        'branch_id': _self.branchId,
        'status': _self.status.wireValue,
      },
    );
    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.ready;
    await _broadcast!.start();
    debugPrint('📣 Waiter broadcasting as ${service.name} on :$advertisedPort');
  }

  Future<void> _startDiscovery() async {
    _discovery = BonsoirDiscovery(type: serviceType);
    await _discovery!.ready;
    _discoverySub = _discovery!.eventStream?.listen((event) {
      final svc = event.service;
      switch (event.type) {
        case BonsoirDiscoveryEventType.discoveryStarted:
          debugPrint('🔎 Waiter discovery: browser started');
          break;
        case BonsoirDiscoveryEventType.discoveryServiceFound:
          if (svc != null) {
            debugPrint('🔎 Waiter discovery: found ${svc.name} — resolving…');
            svc.resolve(_discovery!.serviceResolver);
          }
          break;
        case BonsoirDiscoveryEventType.discoveryServiceResolved:
          if (svc is ResolvedBonsoirService) {
            debugPrint(
                '🔎 Waiter discovery: resolved ${svc.name} at ${svc.host}:${svc.port}');
          }
          if (svc != null) _emitFound(svc);
          break;
        case BonsoirDiscoveryEventType.discoveryServiceResolveFailed:
          debugPrint(
              '⚠️ Waiter discovery: resolve failed for ${svc?.name ?? '?'}');
          break;
        case BonsoirDiscoveryEventType.discoveryServiceLost:
          if (svc != null) {
            debugPrint('🔎 Waiter discovery: lost ${svc.name}');
            _lost.add(svc.name);
          }
          break;
        default:
          break;
      }
    });
    await _discovery!.start();
    debugPrint('🔎 Waiter discovery started (browsing $serviceType)');
  }

  void _emitFound(BonsoirService svc) {
    final attrs = svc.attributes;
    final id = attrs['id'];
    final name = attrs['name'] ?? svc.name;
    final branchId = attrs['branch_id'] ?? '';
    if (id == null || id.isEmpty) return;
    if (id == _self.id) return; // ignore self

    String? host;
    if (svc is ResolvedBonsoirService) {
      host = svc.host;
    }
    final port = svc.port;

    _found.add(Waiter(
      id: id,
      name: name,
      branchId: branchId,
      status: WaiterStatusX.fromWire(attrs['status']),
      host: host,
      port: port,
      lastSeen: DateTime.now(),
    ));
  }

  // Note: real-time status updates go over the open WebSocket via
  // [WireMessageType.waiterStatus]; the TXT record is only a bootstrap
  // hint seen by *new* joiners. We deliberately don't try to mutate the
  // TXT at runtime because cross-platform bonsoir can't do it
  // atomically (stop+start leaves a brief gap where the service
  // disappears) and the live WS broadcast makes it unnecessary.

  Future<void> dispose() async {
    try {
      await _discoverySub?.cancel();
    } catch (_) {}
    try {
      await _discovery?.stop();
    } catch (_) {}
    try {
      await _broadcast?.stop();
    } catch (_) {}
    await _found.close();
    await _lost.close();
  }
}
