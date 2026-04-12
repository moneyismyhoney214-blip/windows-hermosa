import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermosa_pos/services/display_app_service.dart';

class _WsTestRecord {
  final String testName;
  final bool passed;
  final int durationMs;
  final Map<String, dynamic> inputSample;
  final Map<String, dynamic> responseBody;
  final String reason;

  _WsTestRecord({
    required this.testName,
    required this.passed,
    required this.durationMs,
    required this.inputSample,
    required this.responseBody,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'test_name': testName,
        'status': passed ? 'PASSED' : 'FAILED',
        'duration_ms': durationMs,
        'input_sample': inputSample,
        'response_body': responseBody,
        'reason': reason,
        'evidence_screenshots': <String>[],
      };
}

class _LocalDisplayServer {
  HttpServer? _server;
  final List<WebSocket> clients = [];
  final List<Map<String, dynamic>> received = [];
  int connectionCount = 0;
  bool sendMalformedAfterAuth = false;
  bool spamAfterAuth = false;
  bool closeAfterAuth = false;
  final String challenge = 'test_challenge_123';

  Future<int> start({int port = 0}) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen((request) async {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      connectionCount++;
      final ws = await WebSocketTransformer.upgrade(request);
      clients.add(ws);
      ws.add(jsonEncode({'type': 'AUTH_CHALLENGE', 'challenge': challenge}));
      ws.listen(
        (message) async {
          final decoded =
              jsonDecode(message.toString()) as Map<String, dynamic>;
          received.add(decoded);
          if (decoded['type'] == 'AUTH_RESPONSE') {
            ws.add(jsonEncode({
              'type': 'AUTH_SUCCESS',
              'token': 'server-token',
              'currentMode': 'CDS',
              'supportsNearPay': true,
            }));
            if (sendMalformedAfterAuth) {
              ws.add('{bad-json');
            }
            if (spamAfterAuth) {
              for (var i = 0; i < 200; i++) {
                ws.add(jsonEncode({
                  'type': 'PAYMENT_STATUS',
                  'data': {'status': 'authenticating', 'message': 'tick-$i'}
                }));
              }
            }
            if (closeAfterAuth) {
              await Future<void>.delayed(const Duration(milliseconds: 200));
              await ws.close();
            }
          }
          if (decoded['type'] == 'PING') {
            ws.add(jsonEncode({'type': 'PONG'}));
          }
          if (decoded['type'] == 'UPDATE_CART') {
            ws.add(jsonEncode({
              'type': 'CART_UPDATED',
              'data': {
                'itemsCount':
                    ((decoded['data']?['items'] as List?) ?? const []).length
              }
            }));
          }
          if (decoded['type'] == 'NEW_ORDER') {
            ws.add(jsonEncode({
              'type': 'ORDER_RECEIVED',
              'data': {'orderId': decoded['data']?['id']?.toString()}
            }));
          }
        },
        onDone: () {
          clients.remove(ws);
        },
      );
    });
    return _server!.port;
  }

  Future<void> stop() async {
    for (final ws in List<WebSocket>.from(clients)) {
      await ws.close();
    }
    clients.clear();
    await _server?.close(force: true);
    _server = null;
  }
}

void main() {
  final records = <_WsTestRecord>[];
  late _LocalDisplayServer server;
  late DisplayAppService service;

  Future<void> runCaseInternal(
    String name,
    Future<void> Function() body, {
    Map<String, dynamic> input = const {},
    Map<String, dynamic> response = const {},
  }) async {
    final sw = Stopwatch()..start();
    var passed = false;
    var reason = 'ok';
    try {
      await body();
      passed = true;
    } catch (e) {
      reason = e.toString();
      rethrow;
    } finally {
      sw.stop();
      records.add(
        _WsTestRecord(
          testName: name,
          passed: passed,
          durationMs: sw.elapsedMilliseconds,
          inputSample: input,
          responseBody: response,
          reason: reason,
        ),
      );
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = _LocalDisplayServer();
    service = DisplayAppService();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  tearDown(() async {
    service.dispose();
    await server.stop();
  });

  tearDownAll(() async {
    final dir = Directory('test_reports');
    await dir.create(recursive: true);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('test_reports/cashier_display_validation_$ts.json');
    final payload = {
      'suite': 'cashier_display_ws_integration',
      'generated_at': DateTime.now().toIso8601String(),
      'records': records.map((e) => e.toJson()).toList(),
      'summary': {
        'total': records.length,
        'passed': records.where((r) => r.passed).length,
        'failed': records.where((r) => !r.passed).length,
      }
    };
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  });

  test('connect + auth handshake', () async {
    await runCaseInternal(
      'ws_connect_auth',
      () async {
        final port = await server.start();
        await service.connect('127.0.0.1', port: port);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(service.status, ConnectionStatus.connected);
        final hasAuthResponse =
            server.received.any((m) => m['type'] == 'AUTH_RESPONSE');
        expect(hasAuthResponse, isTrue);
      },
      input: {'ip': '127.0.0.1'},
      response: {'expected': 'AUTH_SUCCESS'},
    );
  });

  test('disconnect flow', () async {
    await runCaseInternal(
      'ws_disconnect',
      () async {
        final port = await server.start();
        await service.connect('127.0.0.1', port: port);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        service.disconnect();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(service.status, ConnectionStatus.disconnected);
      },
      input: {'action': 'disconnect'},
      response: {'status': 'disconnected'},
    );
  });

  test('message round-trip and ping/pong', () async {
    await runCaseInternal(
      'ws_round_trip_ping',
      () async {
        final port = await server.start();
        await service.connect('127.0.0.1', port: port);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        service.updateCartDisplay(
          items: const [],
          subtotal: 0,
          tax: 0,
          total: 0,
          orderNumber: '',
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(server.received.any((m) => m['type'] == 'UPDATE_CART'), isTrue);
      },
      input: {'message': 'UPDATE_CART'},
      response: {'server_received': true},
    );
  });

  test('error handling and reconnection', () async {
    await runCaseInternal(
      'ws_reconnect_after_close',
      () async {
        server.closeAfterAuth = true;
        final port = await server.start();
        await service.connect('127.0.0.1', port: port);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await server.stop();

        final replacement = _LocalDisplayServer();
        server = replacement;
        await server.start(port: port);

        await Future<void>.delayed(const Duration(seconds: 4));
        expect(service.status, ConnectionStatus.connected);
      },
      input: {'scenario': 'server_close_then_restart'},
      response: {'expected': 'reconnected'},
    );
  });

  test('concurrent connect calls do not duplicate session', () async {
    await runCaseInternal(
      'ws_concurrent_connect',
      () async {
        final port = await server.start();
        await Future.wait([
          service.connect('127.0.0.1', port: port),
          service.connect('127.0.0.1', port: port),
          service.connect('127.0.0.1', port: port),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(service.status, ConnectionStatus.connected);
        expect(server.connectionCount <= 2, isTrue);
      },
      input: {'parallel_calls': 3},
      response: {'max_connections_expected': 2},
    );
  });

  test('malformed messages are ignored without crash', () async {
    await runCaseInternal(
      'ws_malformed_message',
      () async {
        server.sendMalformedAfterAuth = true;
        final port = await server.start();
        await service.connect('127.0.0.1', port: port);
        await Future<void>.delayed(const Duration(milliseconds: 700));
        expect(service.status, ConnectionStatus.connected);
      },
      input: {'payload': '{bad-json'},
      response: {'expected': 'no_crash'},
    );
  });

  test('high-frequency message spam remains stable', () async {
    await runCaseInternal(
      'ws_high_frequency_spam',
      () async {
        server.spamAfterAuth = true;
        final port = await server.start();
        await service.connect('127.0.0.1', port: port);
        await Future<void>.delayed(const Duration(seconds: 1));
        expect(service.status, ConnectionStatus.connected);
      },
      input: {'spam_count': 200},
      response: {'expected': 'connected'},
    );
  });

  test('ack feedback is tracked for cart and orders', () async {
    await runCaseInternal(
      'ws_ack_feedback_tracking',
      () async {
        final port = await server.start();
        await service.connect('127.0.0.1', port: port);
        await Future<void>.delayed(const Duration(milliseconds: 400));

        service.updateCartDisplay(
          items: const [
            {'id': 1, 'name': 'Item', 'quantity': 1}
          ],
          subtotal: 10,
          tax: 1.5,
          total: 11.5,
          orderNumber: '1002',
        );
        service.sendOrderToKitchen(
          orderId: 'ORD-1002',
          orderNumber: '1002',
          orderType: 'dine_in',
          items: const [
            {'id': 1, 'name': 'Item', 'quantity': 1}
          ],
          switchMode: false,
        );

        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(service.lastCartAckAt, isNotNull);
        expect(service.lastOrderAckId, 'ORD-1002');
        expect(service.lastOrderAckAt, isNotNull);
      },
      input: {'scenario': 'cart_and_order_ack'},
      response: {'expected': 'ack_timestamps_and_order_id'},
    );
  });

  test('offline NEW_ORDER is queued then replayed after reconnect', () async {
    await runCaseInternal(
      'ws_offline_queue_replay_new_order',
      () async {
        server.closeAfterAuth = true;
        final port = await server.start();
        await service.connect('127.0.0.1', port: port);
        await Future<void>.delayed(const Duration(milliseconds: 700));

        // While disconnected/reconnecting, this order should be queued locally.
        service.sendOrderToKitchen(
          orderId: 'ORD-1001',
          orderNumber: '1001',
          orderType: 'dine_in',
          items: const [
            {'id': 1, 'name': 'Dish A', 'quantity': 1}
          ],
          switchMode: false,
        );

        await server.stop();
        final replacement = _LocalDisplayServer();
        server = replacement;
        await server.start(port: port);

        await Future<void>.delayed(const Duration(seconds: 4));
        expect(service.status, ConnectionStatus.connected);
        final replayed = server.received.any(
          (m) =>
              m['type'] == 'NEW_ORDER' &&
              m['data'] is Map &&
              (m['data']['id']?.toString() == 'ORD-1001'),
        );
        expect(replayed, isTrue);
      },
      input: {'scenario': 'offline_send_then_replay'},
      response: {'expected': 'NEW_ORDER_replayed'},
    );
  });
}
