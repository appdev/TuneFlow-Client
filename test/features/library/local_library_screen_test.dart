import 'dart:convert';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/library/library_repository.dart';
import 'package:musicfree_service_client/features/library/local_library_controller.dart';
import 'package:musicfree_service_client/features/library/local_library_screen.dart';
import 'package:musicfree_service_client/features/playlists/playlist_repository.dart';
import 'package:musicfree_service_client/storage/app_image_cache_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../support/fake_app_image_cache.dart';
import '../../support/test_image_cache_manager.dart';

Widget harness(Widget child) => AppImageCacheScope(
  cache: FakeAppImageCache(manager: TestImageCacheManager()),
  child: ShadApp.custom(
    theme: buildLightTheme(),
    appBuilder: (context) => MaterialApp(
      theme: Theme.of(context),
      home: Scaffold(body: ShadAppBuilder(child: child)),
    ),
  ),
);

LocalLibraryController controllerWith(List<Object?> records) =>
    LocalLibraryController(
      LibraryRepository(
        ServiceApi(
          ServiceOrigin.parse('http://service.local'),
          client: MockClient(
            (_) async => http.Response(jsonEncode({'data': records}), 200),
          ),
        ),
      ),
    );

PlaylistRepository playlistsWith(
  Future<http.Response> Function(http.Request) handler,
) => PlaylistRepository(
  ServiceApi(
    ServiceOrigin.parse('http://service.local'),
    client: MockClient(handler),
  ),
);

PlaylistRepository emptyPlaylists() => playlistsWith(
  (_) async => http.Response(jsonEncode({'data': <Object?>[]}), 200),
);

Map<String, Object?> libraryJson(String fileId, String trackId, String name) =>
    {
      'id': fileId,
      'musicInfo': {
        'id': trackId,
        'name': name,
        'singer': 'Artist $name',
        'source': 'local',
      },
      'size': 12,
      'extension': 'mp3',
      'streamUrl': '/api/v1/library/tracks/$fileId/stream',
    };

void main() {
  test('local library cover skips missing and invalid artwork', () {
    final items = [
      LibraryTrack.fromJson({
        ...libraryJson('file-a', 'a', 'A'),
        'pictureUrl': 'not-a-service-url',
      }),
      LibraryTrack.fromJson({
        ...libraryJson('file-b', 'b', 'B'),
        'pictureUrl':
            'http://service.local/api/v1/library/tracks/file-b/picture',
      }),
    ];

    expect(
      firstAvailableLibraryArtwork(items),
      Uri.parse('http://service.local/api/v1/library/tracks/file-b/picture'),
    );
  });

  for (final size in [const Size(390, 844), const Size(1200, 800)]) {
    testWidgets('renders a local library at ${size.width}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = controllerWith([
        libraryJson('file-a', 'a', 'A'),
        libraryJson('file-b', 'b', 'B'),
      ]);
      await controller.refresh();
      List<String> queued = const [];
      var selectedIndex = -1;

      await tester.pumpWidget(
        harness(
          LocalLibraryScreen(
            controller: controller,
            playlists: emptyPlaylists(),
            playTracks: (tracks, {startIndex = 0}) async {
              queued = tracks.map((track) => track.id).toList(growable: false);
              selectedIndex = startIndex;
            },
          ),
        ),
      );

      expect(find.byKey(const Key('local-library-route')), findsOneWidget);
      expect(find.text('本地音乐'), findsOneWidget);
      expect(find.text('2 首'), findsOneWidget);
      expect(
        find.byKey(const Key('local-library-hero-artwork')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('artwork-fallback-local-library')),
        findsOneWidget,
      );
      if (size.width == 390) {
        expect(
          find.byKey(const Key('local-library-mobile-scroll')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('artwork-fallback-local:a')),
          findsOneWidget,
        );
      }
      expect(find.byKey(const Key('local-library-play-all')), findsOneWidget);
      expect(find.byKey(const Key('playlist-rename')), findsNothing);
      expect(find.byKey(const Key('playlist-delete')), findsNothing);
      expect(find.byTooltip('从歌单移除'), findsNothing);
      expect(find.byTooltip('拖动排序'), findsNothing);
      expect(find.byTooltip('从服务端删除'), findsNWidgets(2));

      await tester.tap(find.text('B').last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(queued, ['a', 'b']);
      expect(selectedIndex, 1);
    });
  }

  testWidgets('uses the absolute Service picture URL for local artwork', (
    tester,
  ) async {
    final controller = controllerWith([
      {
        ...libraryJson('file-a', 'a', 'A'),
        'pictureUrl': '/api/v1/library/tracks/file-a/picture',
      },
    ]);
    await controller.refresh();

    await tester.pumpWidget(
      harness(
        LocalLibraryScreen(
          controller: controller,
          playlists: emptyPlaylists(),
          playTracks: (_, {startIndex = 0}) async {},
        ),
      ),
    );

    expect(
      tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .map((image) => image.imageUrl),
      contains('http://service.local/api/v1/library/tracks/file-a/picture'),
    );
  });

  testWidgets('shows an empty library with disabled play all', (tester) async {
    final controller = controllerWith(<Object?>[]);
    await controller.refresh();

    await tester.pumpWidget(
      harness(
        LocalLibraryScreen(
          controller: controller,
          playlists: emptyPlaylists(),
          playTracks: (_, {startIndex = 0}) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无本地音乐'), findsOneWidget);
    final button = tester.widget<ShadButton>(
      find.descendant(
        of: find.byKey(const Key('local-library-play-all')),
        matching: find.byType(ShadButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('confirms and deletes the Service library file', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final calls = <http.Request>[];
    final controller = LocalLibraryController(
      LibraryRepository(
        ServiceApi(
          ServiceOrigin.parse('http://service.local'),
          client: MockClient((request) async {
            calls.add(request);
            if (request.method == 'DELETE') return http.Response('', 204);
            return http.Response(
              jsonEncode({
                'data': [libraryJson('file-a', 'track-a', 'A')],
              }),
              200,
            );
          }),
        ),
      ),
    );
    await controller.refresh();
    await tester.pumpWidget(
      harness(
        LocalLibraryScreen(
          controller: controller,
          playlists: emptyPlaylists(),
          playTracks: (_, {startIndex = 0}) async {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('local-library-delete-file-a')));
    await tester.pumpAndSettle();
    expect(find.text('从 Service 删除这首音乐？'), findsOneWidget);
    expect(find.textContaining('歌词、封面'), findsOneWidget);
    expect(calls.where((request) => request.method == 'DELETE'), isEmpty);

    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();

    expect(calls.last.method, 'DELETE');
    expect(calls.last.url.path, '/api/v1/library/tracks/file-a');
    expect(find.text('暂无本地音乐'), findsOneWidget);
  });

  for (final size in [const Size(390, 844), const Size(1200, 800)]) {
    testWidgets('favorites local music into a playlist at ${size.width}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = controllerWith([
        libraryJson('file-a', 'track-a', 'A'),
      ]);
      await controller.refresh();
      final calls = <http.Request>[];
      final playlists = playlistsWith((request) async {
        calls.add(request);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'daily', 'name': '每日收藏'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(jsonEncode({'data': <Object?>[]}), 200);
      });
      var playCount = 0;

      await tester.pumpWidget(
        harness(
          LocalLibraryScreen(
            controller: controller,
            playlists: playlists,
            playTracks: (_, {startIndex = 0}) async => playCount += 1,
          ),
        ),
      );

      final favorite = find.byKey(
        const Key('local-library-favorite-local-track-a'),
      );
      await tester.ensureVisible(favorite);
      tester.widget<IconButton>(favorite).onPressed!();
      await tester.pumpAndSettle();
      expect(calls.where((request) => request.method == 'GET'), hasLength(1));
      expect(find.text('添加到歌单'), findsOneWidget);
      await tester.tap(find.byKey(const Key('local-library-playlist-daily')));
      await tester.pumpAndSettle();

      expect(playCount, 0);
      final post = calls.singleWhere((request) => request.method == 'POST');
      expect(post.url.path, '/api/v1/playlists/daily/tracks');
      final body = jsonDecode(post.body) as Map<String, Object?>;
      final tracks = body['tracks']! as List<Object?>;
      expect((tracks.single as Map<String, Object?>)['id'], 'track-a');
      expect(find.text('已添加到 每日收藏'), findsOneWidget);
    });
  }

  testWidgets('shows the existing empty playlist state for local music', (
    tester,
  ) async {
    final controller = controllerWith([libraryJson('file-a', 'track-a', 'A')]);
    await controller.refresh();
    await tester.pumpWidget(
      harness(
        LocalLibraryScreen(
          controller: controller,
          playlists: emptyPlaylists(),
          playTracks: (_, {startIndex = 0}) async {},
        ),
      ),
    );

    final favorite = find.byKey(
      const Key('local-library-favorite-local-track-a'),
    );
    await tester.ensureVisible(favorite);
    tester.widget<IconButton>(favorite).onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('还没有歌单'), findsOneWidget);
  });
}
