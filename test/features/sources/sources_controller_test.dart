import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/sources/source_repository.dart';
import 'package:musicfree_service_client/features/sources/sources_controller.dart';

Map<String, Object?> source(
  String id, {
  required bool active,
  bool? enabled,
  int? priority,
}) => {
  'id': id,
  'name': '音源 $id',
  'description': '',
  'version': '1.0.0',
  'author': 'Test',
  'homepage': '',
  'active': active,
  if (enabled != null) 'enabled': enabled,
  if (enabled != null || priority != null) 'priority': priority,
  'sources': {
    'kw': {
      'type': 'music',
      'actions': ['musicUrl', 'lyric'],
      'qualitys': ['320k', 'flac'],
    },
  },
};

http.Response ok(Object? data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('installs, imports, deletes and exposes the export endpoint', () async {
    final calls = <(String, String, Object?)>[];
    var installed = false;
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        final body = request.body.isEmpty ? null : jsonDecode(request.body);
        calls.add((request.method, request.url.path, body));
        if (request.method == 'GET') {
          return ok([
            if (installed)
              source('installed', active: true, enabled: true, priority: 0),
          ]);
        }
        if (request.method == 'DELETE') {
          installed = false;
          return http.Response('', 204);
        }
        installed = true;
        return ok(
          source('installed', active: true, enabled: true, priority: 0),
        );
      }),
    );
    final repository = SourceRepository(api);
    final controller = SourcesController(repository);

    await controller.installScript('  const source = {};  ');
    await controller.importUrl('  https://example.com/source.js  ');
    await controller.delete('installed');

    expect(calls[0].$1, 'POST');
    expect(calls[0].$2, '/api/v1/sources');
    expect(calls[0].$3, {'script': 'const source = {};'});
    expect(calls[2].$1, 'POST');
    expect(calls[2].$2, '/api/v1/sources/import');
    expect(calls[2].$3, {'url': 'https://example.com/source.js'});
    expect(calls[4].$1, 'DELETE');
    expect(calls[4].$2, '/api/v1/sources/installed');
    expect(controller.state.items, isEmpty);
    expect(
      repository.exportUri.toString(),
      'http://service.local/api/v1/sources/export',
    );
  });

  test(
    'parses ordered summaries compatibly and submits the complete array',
    () async {
      Object? requestBody;
      String? requestMethod;
      final api = ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          requestMethod = request.method;
          requestBody = jsonDecode(request.body);
          return ok([
            source('b', active: true, enabled: true, priority: 0),
            source('a', active: false, enabled: true, priority: 1),
          ]);
        }),
      );
      final repository = SourceRepository(api);

      final legacy = InstalledMusicSource.fromJson(
        source('legacy', active: true),
      );
      final result = await repository.configureEnabled(['b', 'a']);

      expect((legacy.enabled, legacy.priority), (true, 0));
      expect(requestMethod, 'PUT');
      expect(requestBody, {
        'sourceIds': ['b', 'a'],
      });
      expect(result.map((item) => (item.id, item.enabled, item.priority)), [
        ('b', true, 0),
        ('a', true, 1),
      ]);
    },
  );

  test('reorders and toggles the complete enabled source array', () async {
    final submitted = <List<String>>[];
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return ok([
            source('a', active: true, enabled: true, priority: 0),
            source('b', active: false, enabled: true, priority: 1),
            source('c', active: false, enabled: false),
          ]);
        }
        final ids = (jsonDecode(request.body)['sourceIds'] as List)
            .cast<String>();
        submitted.add(ids);
        return ok([
          for (var index = 0; index < ids.length; index++)
            source(
              ids[index],
              active: index == 0,
              enabled: true,
              priority: index,
            ),
          if (!ids.contains('a')) source('a', active: false, enabled: false),
          if (!ids.contains('b')) source('b', active: false, enabled: false),
          if (!ids.contains('c')) source('c', active: false, enabled: false),
        ]);
      }),
    );
    final controller = SourcesController(SourceRepository(api));

    await controller.refresh();
    expect(controller.state.enabledSources.map((item) => item.id), ['a', 'b']);
    expect(controller.state.disabledSources.map((item) => item.id), ['c']);
    expect(controller.state.primarySource?.id, 'a');

    await controller.reorder(1, 0);
    await controller.toggle('a', false);
    await controller.toggle('c', true);

    expect(submitted, [
      ['b', 'a'],
      ['b'],
      ['b', 'c'],
    ]);
    expect(controller.state.enabledSources.map((item) => item.id), ['b', 'c']);
    expect(controller.state.saving, isFalse);
  });

  test(
    'rolls back a failed mutation and refreshes authoritative state',
    () async {
      var getCount = 0;
      final api = ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          if (request.method == 'GET') {
            getCount++;
            return ok([
              source('a', active: true, enabled: true, priority: 0),
              source('b', active: false, enabled: false),
            ]);
          }
          return http.Response(
            jsonEncode({
              'error': {'code': 'SOURCE_INVALID', 'message': 'Cannot activate'},
            }),
            502,
          );
        }),
      );
      final controller = SourcesController(SourceRepository(api));

      await controller.refresh();
      expect(controller.state.error, isNull);
      await controller.toggle('b', true);

      expect(controller.state.primarySource?.id, 'a');
      expect(controller.state.disabledSources.map((item) => item.id), ['b']);
      expect(controller.state.error, isNotNull);
      expect(controller.state.saving, isFalse);
      expect(getCount, 2);
    },
  );
}
