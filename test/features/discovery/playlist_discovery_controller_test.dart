import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/discovery/playlist_discovery_controller.dart';
import 'package:musicfree_service_client/features/search/search_repository.dart';

http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode({'data': data}),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> body(http.Request request) =>
    Map<String, Object?>.from(jsonDecode(request.body) as Map);

Map<String, Object?> capabilities() => {
  'sources': [
    for (final source in ['kw', 'kg', 'tx', 'wy', 'mg'])
      {
        'id': source,
        'name': source.toUpperCase(),
        'searchKinds': ['track', 'playlist'],
        'playlistDiscovery': {'tags': true, 'browse': true, 'detail': true},
      },
  ],
};

Map<String, Object?> filters(String source) => {
  'source': source,
  'sorts': [
    if (source == 'kw') {'id': 'new', 'name': '最新'},
    {'id': source == 'kw' ? 'hot' : 'recommend', 'name': '最热歌单'},
  ],
  'hotTags': [
    {'id': '2189-10000', 'name': '短视频'},
  ],
  'groups': [
    {
      'name': '主题',
      'tags': [
        {'id': '2189-10000', 'name': '短视频'},
      ],
    },
  ],
};

Map<String, Object?> browsePage(
  String source,
  int page, {
  String suffix = '',
}) => {
  'source': source,
  'page': page,
  'limit': 30,
  'total': 31,
  'hasMore': page == 1,
  'list': [
    {
      'id': '$source-$page$suffix',
      'kind': 'playlist',
      'name': '$source playlist',
      'source': source,
    },
  ],
};

void main() {
  test('loads native providers and resets filters and pages', () async {
    final browseBodies = <Map<String, Object?>>[];
    final repository = SearchRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          if (request.method == 'GET') return response(capabilities());
          final requestBody = body(request);
          final source = requestBody['source']! as String;
          if (request.url.path.endsWith('/tags')) {
            return response(filters(source));
          }
          browseBodies.add(requestBody);
          return response(browsePage(source, requestBody['page']! as int));
        }),
      ),
    );
    final controller = PlaylistDiscoveryController(repository);

    await controller.load();

    expect(controller.state.providers.map((provider) => provider.id), [
      'kw',
      'kg',
      'tx',
      'wy',
      'mg',
    ]);
    expect(controller.state.source, 'kw');
    expect(controller.state.sortId, 'hot');
    expect(controller.state.page, 1);
    expect(controller.state.phase, DiscoveryPhase.ready);

    await controller.selectTag('2189-10000');
    expect(controller.state.page, 1);
    expect(browseBodies.last['tagId'], '2189-10000');

    await controller.goToPage(2);
    expect(controller.state.page, 2);
    expect(controller.state.items.single.id, 'kw-2');

    await controller.selectProvider('kg');
    expect(controller.state.source, 'kg');
    expect(controller.state.sortId, 'recommend');
    expect(controller.state.tagId, '');
    expect(controller.state.page, 1);
  });

  test('a delayed old browse cannot replace the selected provider', () async {
    final delayed = Completer<http.Response>();
    final repository = SearchRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          if (request.method == 'GET') return response(capabilities());
          final requestBody = body(request);
          final source = requestBody['source']! as String;
          if (request.url.path.endsWith('/tags')) {
            return response(filters(source));
          }
          if (source == 'kw' && requestBody['tagId'] == 'slow') {
            return delayed.future;
          }
          return response(browsePage(source, requestBody['page']! as int));
        }),
      ),
    );
    final controller = PlaylistDiscoveryController(repository);
    await controller.load();

    final oldRequest = controller.selectTag('slow');
    await controller.selectProvider('kg');
    delayed.complete(response(browsePage('kw', 1, suffix: '-stale')));
    await oldRequest;

    expect(controller.state.source, 'kg');
    expect(controller.state.items.single.source, 'kg');
    expect(controller.state.items.single.id, 'kg-1');
  });
}
