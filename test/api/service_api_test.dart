import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_exception.dart';
import 'package:musicfree_service_client/api/service_origin.dart';

void main() {
  test('decodes the success envelope and sends JSON', () async {
    final logs = <String>[];
    final client = MockClient((request) async {
      expect(request.url.toString(), 'http://service.local/api/v1/test');
      expect(request.method, 'POST');
      expect(request.headers['content-type'], contains('application/json'));
      expect(jsonDecode(request.body), {'value': 1});
      return http.Response(
        jsonEncode({
          'data': {'ok': true},
        }),
        201,
      );
    });
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: client,
      log: logs.add,
    );

    expect(await api.request('POST', '/api/v1/test', body: {'value': 1}), {
      'ok': true,
    });
    expect(logs, hasLength(4));
    expect(logs[1], '[HTTP] Request: {"value":1}');
    expect(logs[2], contains('status=201'));
    expect(logs[3], '[HTTP] Response: {"data":{"ok":true}}');
  });

  test('maps the service error envelope', () async {
    final logs = <String>[];
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'SOURCE_UNAVAILABLE',
              'message': 'No source',
              'details': {'source': 'kw'},
            },
          }),
          503,
        ),
      ),
      log: logs.add,
    );

    await expectLater(
      api.request('GET', '/api/v1/test'),
      throwsA(
        isA<ServiceException>()
            .having((e) => e.code, 'code', 'SOURCE_UNAVAILABLE')
            .having((e) => e.status, 'status', 503),
      ),
    );
    expect(logs, hasLength(3));
    expect(logs[1], contains('status=503'));
    expect(logs[2], contains('"code":"SOURCE_UNAVAILABLE"'));
  });

  test('rejects redirects and malformed success envelopes', () async {
    var response = http.Response(
      '',
      302,
      headers: {'location': 'https://evil.example'},
    );
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((_) async => response),
    );

    await expectLater(
      api.request('GET', '/api/v1/test'),
      throwsA(
        isA<ServiceException>().having(
          (e) => e.code,
          'code',
          'REDIRECT_REJECTED',
        ),
      ),
    );

    response = http.Response(jsonEncode({'ok': true}), 200);
    await expectLater(
      api.request('GET', '/api/v1/test'),
      throwsA(
        isA<ServiceException>().having(
          (e) => e.code,
          'code',
          'INVALID_RESPONSE',
        ),
      ),
    );
  });

  test('subsequent requests use a switched origin', () async {
    final urls = <String>[];
    final api = ServiceApi(
      ServiceOrigin.parse('https://external.example'),
      client: MockClient((request) async {
        urls.add(request.url.toString());
        return http.Response(
          jsonEncode({
            'data': {'ok': true},
          }),
          200,
        );
      }),
    );

    await api.request('GET', '/api/v1/test');
    api.switchOrigin(ServiceOrigin.parse('http://192.168.1.20:3124'));
    await api.request('GET', '/api/v1/test');

    expect(urls, [
      'https://external.example/api/v1/test',
      'http://192.168.1.20:3124/api/v1/test',
    ]);
  });

  test('logs HTTP query parameters and response body in debug mode', () async {
    final logs = <String>[];
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient(
        (_) async => http.Response(jsonEncode({'data': null}), 200),
      ),
      log: logs.add,
    );

    await api.request(
      'GET',
      '/api/v1/search?keyword=private%20query&source=secret',
    );

    expect(logs, hasLength(3));
    expect(
      logs.first,
      '[HTTP] --> GET '
      'http://service.local/api/v1/search?keyword=private%20query&source=secret',
    );
    expect(logs[1], contains('[HTTP] <-- GET'));
    expect(logs[1], contains('status=200'));
    expect(logs[1], contains('duration='));
    expect(logs.last, '[HTTP] Response: {"data":null}');
  });

  test(
    'logs HTTP network failures with request details in debug mode',
    () async {
      final logs = <String>[];
      final api = ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((_) async => throw StateError('private details')),
        log: logs.add,
      );

      await expectLater(
        api.request('GET', '/api/v1/test?token=secret'),
        throwsA(
          isA<ServiceException>().having(
            (e) => e.code,
            'code',
            'NETWORK_ERROR',
          ),
        ),
      );

      expect(logs, hasLength(2));
      expect(logs.last, contains('[HTTP] xx> GET'));
      expect(logs.last, contains('token=secret'));
      expect(logs.last, contains('error=Bad state: private details'));
    },
  );
}
