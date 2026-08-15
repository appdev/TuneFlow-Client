import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/discovery/discovery_hub_screen.dart';
import 'package:musicfree_service_client/features/playlists/playlist_repository.dart';
import 'package:musicfree_service_client/features/search/search_repository.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

http.Response data(Object? value) => http.Response(
  jsonEncode({'data': value}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

void main() {
  testWidgets('discovery switches between square and charts by tap and swipe', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/api/v1/catalog/capabilities':
            return data({
              'sources': [
                {
                  'id': 'kw',
                  'name': '酷我音乐',
                  'searchKinds': ['track', 'playlist'],
                  'leaderboards': true,
                  'playlistDiscovery': {
                    'tags': true,
                    'browse': true,
                    'detail': true,
                  },
                },
              ],
            });
          case '/api/v1/catalog/playlists/tags':
            return data({
              'source': 'kw',
              'sorts': [
                {'id': 'hot', 'name': '最热'},
              ],
              'hotTags': <Object?>[],
              'groups': <Object?>[],
            });
          case '/api/v1/catalog/playlists/browse':
            return data({
              'source': 'kw',
              'page': 1,
              'limit': 30,
              'total': 0,
              'hasMore': false,
              'list': <Object?>[],
            });
          case '/api/v1/catalog/leaderboards':
            return data({
              'source': 'kw',
              'list': [
                {'id': 'kw__16', 'bangid': '16', 'name': '热歌榜'},
              ],
            });
          case '/api/v1/catalog/leaderboards/tracks':
            return data({'list': <Object?>[], 'total': 0});
          default:
            return data(<Object?>[]);
        }
      }),
    );

    await tester.pumpWidget(
      harness(
        DiscoveryHubScreen(
          repository: SearchRepository(api),
          playlists: PlaylistRepository(api),
          playTracks: (_, {startIndex = 0}) async {},
          onOpenPlaylist: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('discovery-tab-playlists')), findsOneWidget);
    expect(find.byKey(const Key('playlist-square-layout')), findsOneWidget);

    await tester.tap(find.byKey(const Key('discovery-tab-charts')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('charts-layout')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('discovery-tab-view')),
      const Offset(320, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('playlist-square-layout')), findsOneWidget);
  });
}
