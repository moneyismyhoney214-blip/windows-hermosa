import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';
import 'package:hermosa_pos/services/api/base_client.dart';
import 'package:hermosa_pos/services/api/device_service.dart';
import 'package:hermosa_pos/models.dart';
import 'package:hermosa_pos/locator.dart';
import 'package:hermosa_pos/services/cache_service.dart';

class _BaseRequestMockClient extends http.BaseClient {
  _BaseRequestMockClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
}

http.StreamedResponse _jsonStreamedResponse(
  Map<String, dynamic> body,
  int statusCode,
) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    statusCode,
    headers: const {'content-type': 'application/json'},
  );
}

void main() {
  late BaseClient client;
  late DeviceService service;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    if (getIt.isRegistered<CacheService>()) {
      getIt.unregister<CacheService>();
    }
    getIt.registerLazySingleton<CacheService>(() => CacheService());
    ApiConstants.branchId = 74;
    client = BaseClient();
    client.setToken('test-token');
    service = DeviceService();
  });

  test('getPrinterCategoryAssignments parses backend categories correctly',
      () async {
    client.setClientForTesting(
      MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/seller/branches/74/printers');
        return http.Response(
          jsonEncode({
            'status': 200,
            'data': [
              {
                'id': 11,
                'name': 'Kitchen A',
                'categories': [
                  '22',
                  43,
                  {'id': '44'},
                  {'value': 45},
                  {'category_id': '46'},
                  null,
                  '',
                  'null'
                ]
              },
              {'id': 12, 'name': 'Kitchen B', 'categories': null},
              {
                'id': 13,
                'name': 'Kitchen C',
                'categories': [
                  {'id': 22},
                  {'id': '22'}
                ]
              }
            ]
          }),
          200,
        );
      }),
    );

    final result = await service.getPrinterCategoryAssignments();

    expect(result['printer:11'], <String>['22', '43', '44', '45', '46']);
    expect(result['printer:12'], <String>[]);
    expect(result['printer:13'], <String>['22']);
  });

  test('updatePrinterCategories sends PUT payload expected by backend',
      () async {
    late Uri capturedUri;
    late String capturedMethod;
    late Map<String, dynamic> capturedBody;
    late String authHeader;

    client.setClientForTesting(
      MockClient((request) async {
        capturedUri = request.url;
        capturedMethod = request.method;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        authHeader = request.headers['authorization'] ?? '';
        return http.Response(
          jsonEncode({'status': 200, 'message': 'updated'}),
          200,
        );
      }),
    );

    await service.updatePrinterCategories(
      printerId: 'printer:13',
      printerName: '  Kitchen Printer  ',
      categoryIds: const ['43', '22', '43', ' ', '22'],
    );

    expect(capturedMethod, 'PUT');
    expect(capturedUri.path, '/seller/branches/74/printers/13');
    expect(authHeader, 'Bearer test-token');
    expect(capturedBody['name'], 'Kitchen Printer');
    expect(capturedBody['categories'], <String>['22', '43']);
  });

  test('updatePrinterCategories rejects invalid printer id locally', () async {
    client.setClientForTesting(
      MockClient((request) async {
        fail('Network should not be called for invalid printer id');
      }),
    );

    expect(
      () => service.updatePrinterCategories(
        printerId: 'printer:',
        printerName: 'P1',
        categoryIds: const ['22'],
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('createDevice keeps trying backend KDS creation even without categories',
      () async {
    final requestedPaths = <String>[];
    late Map<String, String> sentFields;

    client.setClientForTesting(
      _BaseRequestMockClient((request) async {
        requestedPaths.add(request.url.path);

        if (request.method == 'GET') {
          return _jsonStreamedResponse(
            {
              'status': 200,
              'data': <dynamic>[],
            },
            200,
          );
        }

        if (request.method == 'POST' &&
            request.url.path == '/seller/branches/74/kitchens') {
          expect(request, isA<http.MultipartRequest>());
          sentFields = Map<String, String>.from(
              (request as http.MultipartRequest).fields);
          return _jsonStreamedResponse(
            {
              'status': 200,
              'data': {
                'id': 91,
                'name': 'Kitchen Screen',
              },
            },
            200,
          );
        }

        fail('Unexpected request: ${request.method} ${request.url}');
      }),
    );

    final created = await service.createDevice(
      DeviceConfig(
        id: 'draft-kds',
        name: 'Kitchen Screen',
        ip: '10.0.3.1',
        port: '8080',
        type: 'kds',
        model: 'display',
      ),
    );

    expect(created.id, 'kitchen:91');
    expect(created.type, 'kds');
    expect(sentFields['name'], 'Kitchen Screen');
    expect(sentFields['is_active'], 'true');
    expect(
        sentFields.keys.where((key) => key.startsWith('categories[')), isEmpty);
    expect(requestedPaths, contains('/seller/branches/74/meal-categories'));
    expect(requestedPaths, contains('/seller/branches/74/kitchens'));
  });
}
