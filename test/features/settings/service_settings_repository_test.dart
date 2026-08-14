import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_exception.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/settings/service_settings_repository.dart';

http.Response data(Object? value) =>
    http.Response(jsonEncode({'data': value}), 200);

ServiceSettingsRepository repositoryFor(
  Future<http.Response> Function(http.Request request) handler,
) => ServiceSettingsRepository(
  ServiceApi(
    ServiceOrigin.parse('http://service.local'),
    client: MockClient(handler),
  ),
);

void main() {
  test('reads the Service auto-download setting', () async {
    final repository = repositoryFor((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/settings');
      return data({'player.autoDownloadOnPlay': true});
    });

    expect(await repository.getAutoDownloadOnPlay(), isTrue);
  });

  test('patches only the Service auto-download setting', () async {
    final repository = repositoryFor((request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/v1/settings');
      expect(jsonDecode(request.body), {'player.autoDownloadOnPlay': false});
      return data({'player.autoDownloadOnPlay': false});
    });

    expect(await repository.setAutoDownloadOnPlay(false), isFalse);
  });

  test('rejects a Service response missing the auto-download setting', () {
    final repository = repositoryFor((_) async => data({'player.volume': 1}));

    expect(
      repository.getAutoDownloadOnPlay(),
      throwsA(
        isA<ServiceException>().having(
          (error) => error.code,
          'code',
          'INVALID_RESPONSE',
        ),
      ),
    );
  });

  test('rejects a non-boolean auto-download setting', () {
    final repository = repositoryFor(
      (_) async => data({'player.autoDownloadOnPlay': 'true'}),
    );

    expect(
      repository.getAutoDownloadOnPlay(),
      throwsA(
        isA<ServiceException>().having(
          (error) => error.code,
          'code',
          'INVALID_RESPONSE',
        ),
      ),
    );
  });
}
