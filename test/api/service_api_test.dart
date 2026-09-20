import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_exception.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/diagnostics/app_logger.dart';

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
    expect(logs, hasLength(3));
    expect(logs[1], '[HTTP] Request body omitted (11 chars)');
    expect(logs[2], contains('status=201'));
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
    expect(logs, hasLength(2));
    expect(logs[1], contains('status=503'));
    expect(logs[1], contains('bytes='));
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

  test('redacts HTTP query values and response bodies in debug logs', () async {
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

    expect(logs, hasLength(2));
    expect(
      logs.first,
      '[HTTP] --> GET '
      'http://service.local/api/v1/search?keyword=%3Credacted%3E&source=%3Credacted%3E',
    );
    expect(logs[1], contains('[HTTP] <-- GET'));
    expect(logs[1], contains('status=200'));
    expect(logs[1], contains('duration='));
    expect(logs[1], contains('bytes=13'));
    expect(logs.join('\n'), isNot(contains('private query')));
    expect(logs.join('\n'), isNot(contains('{"data":null}')));
  });

  test('adds one safe operation id to the completed HTTP diagnostic', () async {
    final diagnostics = AppLogger(includeDebug: false);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      diagnostics: diagnostics,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {'ok': true},
          }),
          200,
        ),
      ),
    );

    await api.request('GET', '/api/v1/test');

    final fields = (jsonDecode(diagnostics.snapshot().single)['fields'] as Map);
    expect(fields['operation_id'], matches(RegExp(r'^[a-f0-9]{16}$')));
    expect(fields['route'], '/api/v1/:id');
    expect(fields.containsKey('body'), isFalse);
  });

  test('logs HTTP network failures without private request details', () async {
    final logs = <String>[];
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((_) async => throw StateError('private details')),
      log: logs.add,
    );

    await expectLater(
      api.request('GET', '/api/v1/test?token=secret'),
      throwsA(
        isA<ServiceException>().having((e) => e.code, 'code', 'NETWORK_ERROR'),
      ),
    );

    expect(logs, hasLength(2));
    expect(logs.last, contains('[HTTP] xx> GET'));
    expect(logs.last, contains('token=%3Credacted%3E'));
    expect(logs.last, contains('error=StateError'));
    expect(logs.last, isNot(contains('private details')));
  });
}
