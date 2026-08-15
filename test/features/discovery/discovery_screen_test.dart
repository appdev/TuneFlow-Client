import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';
import 'package:musicfree_service_client/features/discovery/discovery_screen.dart';
import 'package:musicfree_service_client/features/playlists/playlist_repository.dart';
import 'package:musicfree_service_client/features/search/search_repository.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

http.Response _data(Object value) => http.Response(
  jsonEncode({'data': value}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets('mobile charts prioritizes tracks and preserves track rows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/catalog/capabilities') {
          return _data({
            'sources': [
              {
                'id': 'kw',
                'name': '酷我音乐',
                'searchKinds': ['track'],
                'leaderboards': true,
              },
            ],
          });
        }
        if (request.url.path == '/api/v1/catalog/leaderboards') {
          return _data({
            'source': 'kw',
            'list': [
              for (var index = 1; index <= 4; index++)
                {
                  'id': 'board-$index',
                  'providerId': 'board-$index',
                  'name': '榜单$index',
                  'source': 'kw',
                },
            ],
          });
        }
        if (request.url.path == '/api/v1/catalog/leaderboards/tracks') {
          return _data({
            'list': [
              {
                'songmid': 'track-1',
                'name': '晚风',
                'singer': '伍佰',
                'source': 'kw',
              },
            ],
            'total': 1,
          });
        }
        throw StateError('Unexpected request: ${request.url}');
      }),
    );

    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        builder: (context, child) => ShadAppBuilder(child: child!),
        home: Scaffold(
          body: DiscoveryScreen(
            repository: SearchRepository(api),
            kind: DiscoveryKind.charts,
            onSearch: () {},
            playTracks: (_, {startIndex = 0}) async {},
            playlists: PlaylistRepository(api),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('榜单3'), findsOneWidget);
    expect(find.text('榜单4'), findsNothing);
    expect(find.text('晚风'), findsOneWidget);
    expect(find.byType(AppArtwork), findsNothing);
    expect(
      find.byKey(const Key('leaderboard-favorite-kw-track-1')),
      findsOneWidget,
    );
  });

  testWidgets('playing a leaderboard track preserves its queue and index', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/catalog/capabilities') {
          return _data({
            'sources': [
              {
                'id': 'kw',
                'name': '酷我音乐',
                'searchKinds': ['track'],
                'leaderboards': true,
              },
            ],
          });
        }
        if (request.url.path == '/api/v1/catalog/leaderboards') {
          return _data({
            'source': 'kw',
            'list': [
              {
                'id': 'rise',
                'providerId': 'rise',
                'name': '飙升榜',
                'source': 'kw',
              },
            ],
          });
        }
        if (request.url.path == '/api/v1/catalog/leaderboards/tracks') {
          return _data({
            'list': [
              {'songmid': 'one', 'name': 'One', 'source': 'kw'},
              {'songmid': 'two', 'name': 'Two', 'source': 'kw'},
              {'songmid': 'three', 'name': 'Three', 'source': 'kw'},
            ],
            'total': 3,
          });
        }
        throw StateError('Unexpected request: ${request.url}');
      }),
    );
    List<String> queued = const [];
    var selectedIndex = -1;

    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        builder: (context, child) => ShadAppBuilder(child: child!),
        home: Scaffold(
          body: DiscoveryScreen(
            repository: SearchRepository(api),
            kind: DiscoveryKind.charts,
            onSearch: () {},
            playTracks: (tracks, {startIndex = 0}) async {
              queued = tracks.map((track) => track.id).toList();
              selectedIndex = startIndex;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Two'));
    await tester.pump();

    expect(queued, ['one', 'two', 'three']);
    expect(selectedIndex, 1);

    queued = const [];
    selectedIndex = -1;
    await tester.tap(find.byKey(const Key('leaderboard-more-kw-two')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('track-action-playNow')));
    await tester.pump();

    expect(queued, ['one', 'two', 'three']);
    expect(selectedIndex, 1);
  });

  testWidgets('leaderboard reports a localized playlist add failure', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final requests = <String>[];
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.method == 'GET' &&
            request.url.path == '/api/v1/catalog/capabilities') {
          return _data({
            'sources': [
              {
                'id': 'kw',
                'name': '酷我音乐',
                'searchKinds': ['track'],
                'leaderboards': true,
              },
            ],
          });
        }
        if (request.method == 'GET' &&
            request.url.path == '/api/v1/playlists') {
          return _data([
            {'id': 'love', 'name': '我的收藏'},
          ]);
        }
        if (request.url.path == '/api/v1/catalog/leaderboards') {
          return _data({
            'source': 'kw',
            'list': [
              {
                'id': 'rise',
                'providerId': 'rise',
                'name': '飙升榜',
                'source': 'kw',
              },
            ],
          });
        }
        if (request.url.path == '/api/v1/catalog/leaderboards/tracks') {
          return _data({
            'list': [
              {
                'songmid': 'track-1',
                'name': '晚风',
                'singer': '伍佰',
                'source': 'kw',
              },
            ],
            'total': 1,
          });
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/playlists/love/tracks') {
          return http.Response(
            jsonEncode({
              'error': {'code': 'WRITE_FAILED', 'message': 'internal failure'},
            }),
            500,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        throw StateError(
          'Unexpected request: ${request.method} ${request.url}',
        );
      }),
    );

    await tester.pumpWidget(
      ShadApp(
        theme: buildLightTheme(),
        builder: (context, child) => ShadAppBuilder(child: child!),
        home: Scaffold(
          body: DiscoveryScreen(
            repository: SearchRepository(api),
            kind: DiscoveryKind.charts,
            onSearch: () {},
            playlists: PlaylistRepository(api),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester
        .widget<IconButton>(
          find.byKey(const Key('leaderboard-favorite-kw-track-1')),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(requests, contains('GET /api/v1/playlists'));
    expect(find.text('添加到歌单'), findsOneWidget);
    await tester.tap(find.text('我的收藏'));
    await tester.pumpAndSettle();

    expect(find.text('添加失败'), findsOneWidget);
    expect(find.text('暂时无法添加到该歌单，请稍后重试。'), findsOneWidget);
    expect(find.textContaining('internal failure'), findsNothing);
  });
}
