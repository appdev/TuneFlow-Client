import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/discovery/online_playlist_detail_controller.dart';
import 'package:musicfree_service_client/features/discovery/online_playlist_detail_screen.dart';
import 'package:musicfree_service_client/features/downloads/download_repository.dart';
import 'package:musicfree_service_client/features/player/playback_repository.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/features/player/player_state.dart';
import 'package:musicfree_service_client/features/player/service_audio_handler.dart';
import 'package:musicfree_service_client/features/playlists/playlist_repository.dart';
import 'package:musicfree_service_client/features/search/search_repository.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

final class _Resolver implements PlaybackResolver {
  @override
  Future<PlaybackSource> resolve(Track track, String quality) async =>
      PlaybackSource(
        resolved: const ResolvedTrack(
          url: '/stream',
          quality: '128k',
          expiresAt: 1,
        ),
        streamUri: Uri.parse('http://service.local/stream'),
      );
}

final class _Audio implements AudioPort {
  final snapshotsController = StreamController<AudioSnapshot>.broadcast();
  @override
  Stream<AudioSnapshot> get snapshots => snapshotsController.stream;
  @override
  void bindQueueCallbacks({
    required Future<void> Function() previous,
    required Future<void> Function() next,
  }) {}
  @override
  Future<void> pause() async {}
  @override
  Future<bool> playCachedTrack(Track track, String quality) async => false;
  @override
  Future<void> playTrack(Track track, Uri streamUri, String quality) async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stopPlayback() async {}
}

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

void main() {
  testWidgets('online detail renders real metadata and plays loaded tracks', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1162, 768);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        final Object value;
        if (request.url.path.endsWith('/detail')) {
          value = {
            'source': 'kw',
            'page': 1,
            'limit': 1000,
            'total': 2,
            'hasMore': false,
            'playlist': {
              'id': 'list-1',
              'kind': 'playlist',
              'name': '短视频DJ热门歌曲｜网红BGM',
              'source': 'kw',
              'author': '第一天',
              'total': 1,
              'playCount': '450.4万',
              'description':
                  '苦苦爱着一个人是什么感觉？一个人煎熬的日子很痛，痛到无法和对方表明心意；'
                  '任何时候、任何地点、任何事情都是一个人承受。',
            },
            'tracks': [
              {'songmid': 'one', 'name': 'One', 'source': 'kw'},
              {
                'songmid': 'two',
                'name': 'Two',
                'source': 'kw',
                'pic': 'https://cdn.example.test/two.jpg',
              },
            ],
          };
        } else if (request.url.path.endsWith('/picture')) {
          value = {'url': 'https://cdn.example.test/one.jpg'};
        } else {
          value = <Object?>[];
        }
        return http.Response(
          jsonEncode({'data': value}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final player = PlayerController(resolver: _Resolver(), audio: _Audio());
    await player.play(
      Track.fromJson({'id': 'one', 'name': 'One', 'source': 'kw'}),
    );
    final controller = OnlinePlaylistDetailController(
      catalog: SearchRepository(api),
      playlists: PlaylistRepository(api),
      source: 'kw',
      playlistId: 'list-1',
    );

    await tester.pumpWidget(
      harness(
        SizedBox(
          width: 694,
          child: OnlinePlaylistDetailScreen(
            controller: controller,
            player: player,
            downloads: DownloadRepository(api),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    expect(find.text('短视频DJ热门歌曲｜网红BGM'), findsOneWidget);
    expect(find.textContaining('450.4万'), findsOneWidget);
    expect(find.byKey(const Key('catalog-track-kw-one')), findsOneWidget);
    expect(
      player.state.current?.raw['pic'],
      'https://cdn.example.test/one.jpg',
    );

    await tester.tap(find.byKey(const Key('search-track-kw-one')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('search-track-kw-one')));
    await tester.pumpAndSettle();
    expect(player.state.queue.map((track) => track.id), ['one', 'two']);
    expect(player.state.currentIndex, 0);

    await tester.tap(find.byKey(const Key('online-playlist-play-all')));
    await tester.pumpAndSettle();
    expect(player.state.queue.map((track) => track.id), ['one', 'two']);
    expect(
      player.state.current?.raw['pic'],
      'https://cdn.example.test/one.jpg',
    );
    expect(find.text('重命名'), findsNothing);
    expect(find.text('删除歌单'), findsNothing);
  });

  testWidgets('online playback uses the loaded list at interaction time', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final pictureResponse = Completer<http.Response>();
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/picture')) {
          return pictureResponse.future;
        }
        if (request.url.path.endsWith('/detail')) {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final page = body['page'] as int;
          return http.Response(
            jsonEncode({
              'data': {
                'source': 'kw',
                'page': page,
                'limit': 2,
                'total': 3,
                'hasMore': page == 1,
                'playlist': {
                  'id': 'list-1',
                  'kind': 'playlist',
                  'name': 'Paged list',
                  'source': 'kw',
                },
                'tracks': page == 1
                    ? [
                        {'id': 'one', 'name': 'One', 'source': 'kw'},
                        {
                          'id': 'two',
                          'name': 'Two',
                          'source': 'kw',
                          'pic': 'https://cdn.example.test/two.jpg',
                        },
                      ]
                    : [
                        {
                          'id': 'three',
                          'name': 'Three',
                          'source': 'kw',
                          'pic': 'https://cdn.example.test/three.jpg',
                        },
                      ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(jsonEncode({'data': <Object?>[]}), 200);
      }),
    );
    final player = PlayerController(resolver: _Resolver(), audio: _Audio());
    final controller = OnlinePlaylistDetailController(
      catalog: SearchRepository(api),
      playlists: PlaylistRepository(api),
      source: 'kw',
      playlistId: 'list-1',
    );

    await tester.pumpWidget(
      harness(
        OnlinePlaylistDetailScreen(
          controller: controller,
          player: player,
          downloads: DownloadRepository(api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-track-kw-one')));
    await tester.pump();
    await controller.loadPage(2);
    await tester.pump();
    pictureResponse.complete(
      http.Response(
        jsonEncode({
          'data': {'url': 'https://cdn.example.test/one.jpg'},
        }),
        200,
      ),
    );
    await tester.pumpAndSettle();

    expect(player.state.queue.map((track) => track.id), ['one', 'two']);
    expect(player.state.currentIndex, 0);
  });

  testWidgets('scrolling near the end automatically loads the next page', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1162, 768);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final requestedPages = <int>[];
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        if (!request.url.path.endsWith('/detail')) {
          return http.Response(jsonEncode({'data': <Object?>[]}), 200);
        }
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final page = body['page'] as int;
        requestedPages.add(page);
        return http.Response(
          jsonEncode({
            'data': {
              'source': 'kw',
              'page': page,
              'limit': 20,
              'total': 21,
              'hasMore': page == 1,
              'playlist': {
                'id': 'list-1',
                'kind': 'playlist',
                'name': 'Paged list',
                'source': 'kw',
                'total': 21,
              },
              'tracks': page == 1
                  ? List.generate(
                      20,
                      (index) => {
                        'id': 'track-$index',
                        'name': 'Track $index',
                        'source': 'kw',
                      },
                    )
                  : [
                      {
                        'id': 'last-track',
                        'name': 'Last page track',
                        'source': 'kw',
                      },
                    ],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final player = PlayerController(resolver: _Resolver(), audio: _Audio());
    final controller = OnlinePlaylistDetailController(
      catalog: SearchRepository(api),
      playlists: PlaylistRepository(api),
      source: 'kw',
      playlistId: 'list-1',
    );

    await tester.pumpWidget(
      harness(
        OnlinePlaylistDetailScreen(
          controller: controller,
          player: player,
          downloads: DownloadRepository(api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedPages, [1]);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    expect(requestedPages, [1, 2]);
    expect(controller.state.tracks.last.title, 'Last page track');
    expect(find.text('加载更多'), findsNothing);
  });

  testWidgets(
    'unrelated parent rebuild keeps the loaded online playlist detail',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1162, 768);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var detailRequests = 0;
      final api = ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/detail')) {
            detailRequests++;
            return http.Response(
              jsonEncode({
                'data': {
                  'source': 'kw',
                  'page': 1,
                  'limit': 1,
                  'total': 1,
                  'hasMore': false,
                  'playlist': {
                    'id': 'list-1',
                    'kind': 'playlist',
                    'name': '已加载歌单',
                    'source': 'kw',
                  },
                  'tracks': [
                    {'id': 'one', 'name': 'One', 'source': 'kw'},
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            jsonEncode({'data': <Object?>[]}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final player = PlayerController(resolver: _Resolver(), audio: _Audio());

      OnlinePlaylistDetailScreen buildScreen() => OnlinePlaylistDetailScreen(
        key: const ValueKey('online-playlist-kw-list-1'),
        controller: OnlinePlaylistDetailController(
          catalog: SearchRepository(api),
          playlists: PlaylistRepository(api),
          source: 'kw',
          playlistId: 'list-1',
        ),
        player: player,
        downloads: DownloadRepository(api),
      );

      await tester.pumpWidget(harness(buildScreen()));
      await tester.pumpAndSettle();
      expect(find.text('已加载歌单'), findsOneWidget);
      expect(detailRequests, 1);

      await tester.pumpWidget(harness(buildScreen()));
      await tester.pumpAndSettle();

      expect(find.text('已加载歌单'), findsOneWidget);
      expect(find.text('歌单详情加载失败'), findsNothing);
      expect(detailRequests, 1);
    },
  );
}
