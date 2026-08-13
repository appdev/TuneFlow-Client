import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/discovery/playlist_discovery_controller.dart';
import 'package:musicfree_service_client/features/discovery/playlist_discovery_view.dart';
import 'package:musicfree_service_client/features/search/search_repository.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

http.Response data(Object value) => http.Response(
  jsonEncode({'data': value}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

PlaylistDiscoveryController controller() => PlaylistDiscoveryController(
  SearchRepository(
    ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return data({
            'sources': [
              {
                'id': 'kw',
                'name': '酷我音乐',
                'searchKinds': ['track', 'playlist'],
                'playlistDiscovery': {
                  'tags': true,
                  'browse': true,
                  'detail': true,
                },
              },
            ],
          });
        }
        if (request.url.path.endsWith('/tags')) {
          return data({
            'source': 'kw',
            'sorts': [
              {'id': 'hot', 'name': '最热歌单'},
            ],
            'hotTags': [
              {'id': '2189-10000', 'name': '短视频'},
            ],
            'groups': [
              {
                'name': '主题',
                'tags': [
                  {'id': '2189-10000', 'name': '短视频'},
                  {'id': '1265-10000', 'name': '经典'},
                ],
              },
            ],
          });
        }
        return data({
          'source': 'kw',
          'page': 1,
          'limit': 36,
          'total': 1751,
          'hasMore': true,
          'list': [
            {
              'id': 'digest-8__3677488020',
              'kind': 'playlist',
              'name': '真实热门歌单',
              'source': 'kw',
              'author': '第一天',
              'total': 41,
              'playCount': '450.4万',
            },
          ],
        });
      }),
    ),
  ),
);

PlaylistDiscoveryController unavailableController() =>
    PlaylistDiscoveryController(
      SearchRepository(
        ServiceApi(
          ServiceOrigin.parse('http://service.local'),
          client: MockClient((request) async {
            if (request.method == 'GET') {
              return data({
                'sources': [
                  {
                    'id': 'kw',
                    'name': '酷我音乐',
                    'searchKinds': ['track', 'playlist'],
                  },
                ],
              });
            }
            throw StateError('unexpected request: ${request.url}');
          }),
        ),
      ),
    );

void main() {
  testWidgets('unavailable discovery shows a localized actionable error', (
    tester,
  ) async {
    final discovery = unavailableController();
    await discovery.load();

    await tester.pumpWidget(
      harness(
        PlaylistDiscoveryView(controller: discovery, onOpenPlaylist: (_) {}),
      ),
    );

    expect(find.text('无法读取歌单分类'), findsOneWidget);
    expect(
      find.text('当前 Service 没有可用的歌单发现平台，请检查 Service 版本或音源状态。'),
      findsOneWidget,
    );
    expect(find.textContaining('Bad state'), findsNothing);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('wide playlist square uses native filters and real paging', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final discovery = controller();
    await discovery.load();
    CatalogCollection? opened;

    await tester.pumpWidget(
      harness(
        PlaylistDiscoveryView(
          controller: discovery,
          onOpenPlaylist: (playlist) => opened = playlist,
        ),
      ),
    );

    expect(find.text('为你推荐'), findsNothing);
    expect(find.text('第 1 / 18 页'), findsNothing);
    expect(find.text('最热歌单'), findsOneWidget);
    expect(find.text('1 / 49'), findsOneWidget);
    expect(find.text('共 1751 个'), findsOneWidget);
    expect(find.byKey(const Key('playlist-categories-toggle')), findsOneWidget);

    await tester.tap(find.byKey(const Key('playlist-categories-toggle')));
    await tester.pump();
    expect(find.text('主题'), findsOneWidget);
    expect(find.text('经典'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('playlist-card-kw-digest-8__3677488020')),
    );
    expect(opened?.source, 'kw');
    expect(opened?.id, 'digest-8__3677488020');
  });
}
