import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';
import 'package:musicfree_service_client/design/components/app_glass_surface.dart';
import 'package:musicfree_service_client/features/downloads/download_repository.dart';
import 'package:musicfree_service_client/features/home/home_controller.dart';
import 'package:musicfree_service_client/features/home/home_screen.dart';
import 'package:musicfree_service_client/features/library/library_repository.dart';
import 'package:musicfree_service_client/features/playback_history/playback_history_repository.dart';
import 'package:musicfree_service_client/features/playlists/playlist_repository.dart';
import 'package:musicfree_service_client/features/recommendations/recommendation_controller.dart';
import 'package:musicfree_service_client/features/recommendations/recommendation_repository.dart';
import 'package:musicfree_service_client/storage/app_image_cache_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../support/fake_app_image_cache.dart';
import '../../support/test_image_cache_manager.dart';
import '../recommendations/recommendation_test_data.dart';

Widget harness(Widget child) => AppImageCacheScope(
  cache: FakeAppImageCache(manager: TestImageCacheManager()),
  child: ShadApp.custom(
    theme: buildLightTheme(),
    appBuilder: (context) => MaterialApp(
      theme: Theme.of(context),
      home: ShadAppBuilder(child: child),
    ),
  ),
);

void main() {
  testWidgets(
    'preserves the in-flight home controller when navigation rebuilds its route',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final coldStartReady = Completer<void>();
      final coldStartApi = ServiceApi(
        ServiceOrigin.parse('http://cold-start.local'),
        client: MockClient((request) async {
          await coldStartReady.future;
          final Object data = switch (request.url.path) {
            '/api/v1/playlists' => [
              {'id': 'preserved', 'name': '返回后仍保留'},
            ],
            '/api/v1/playlists/preserved' => {
              'id': 'preserved',
              'name': '返回后仍保留',
              'tracks': <Object?>[],
            },
            _ => <Object?>[],
          };
          return http.Response(
            jsonEncode({'data': data}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final replacementRequests = <String>[];
      final returnedApi = ServiceApi(
        ServiceOrigin.parse('http://returned.local'),
        client: MockClient((request) async {
          replacementRequests.add(request.url.path);
          return http.Response(
            jsonEncode({'data': <Object?>[]}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      HomeController controller(ServiceApi api) => HomeController(
        playlists: PlaylistRepository(api),
        downloads: DownloadRepository(api),
        library: LibraryRepository(api),
      );
      final coldStartController = controller(coldStartApi);
      final returnedController = controller(returnedApi);

      var currentController = coldStartController;
      late StateSetter rebuild;
      await tester.pumpWidget(
        harness(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return HomeScreen(
                key: const Key('home-route'),
                controller: currentController,
                onSearch: () {},
                onPlaylists: () {},
                onDownloads: () {},
              );
            },
          ),
        ),
      );
      await tester.pump();
      rebuild(() => currentController = returnedController);
      await tester.pump();
      expect(replacementRequests, isEmpty);

      coldStartReady.complete();
      await tester.pumpAndSettle();

      expect(coldStartController.state.playlists.single.displayName, '返回后仍保留');
      expect(coldStartController.state.error, isNull);
      expect(find.text('返回后仍保留'), findsOneWidget);
      expect(replacementRequests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows dashboard shortcuts and playlist summary', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'data': request.url.path.endsWith('playlists')
                ? [
                    {'id': 'one', 'name': 'One'},
                    {'id': 'two', 'name': 'Two'},
                  ]
                : <Object?>[],
          }),
          200,
        ),
      ),
    );
    final controller = HomeController(
      playlists: PlaylistRepository(api),
      downloads: DownloadRepository(api),
      library: LibraryRepository(api),
    );
    await controller.refresh();

    await tester.pumpWidget(
      harness(
        HomeScreen(
          controller: controller,
          onSearch: () {},
          onPlaylists: () {},
          onDownloads: () {},
          now: () => DateTime(2026, 1, 1, 20),
        ),
      ),
    );

    expect(find.byKey(const Key('home-search')), findsOneWidget);
    expect(find.byKey(const Key('home-downloads')), findsOneWidget);
    expect(find.byKey(const Key('home-settings')), findsNothing);
    expect(find.text('我的歌单'), findsOneWidget);
    expect(find.textContaining('晚上好'), findsOneWidget);
    final playlistMetric = tester.widget<Text>(find.text('2 个歌单'));
    expect(playlistMetric.maxLines, 1);
    expect(playlistMetric.softWrap, isFalse);
    expect(
      tester.getSize(find.byKey(const Key('home-search'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(find.byKey(const Key('home-wide-layout')), findsOneWidget);
  });

  testWidgets('home playlist uses the first available track artwork', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        final Object data = switch (request.url.path) {
          '/api/v1/playlists' => [
            {'id': 'default', 'name': 'list__name_default'},
          ],
          '/api/v1/playlists/default' => {
            'id': 'default',
            'name': 'default',
            'tracks': [
              {'id': 'local', 'name': 'Local', 'source': 'local'},
              {
                'id': 'covered',
                'name': 'Covered',
                'source': 'wy',
                'meta': {
                  'picUrl': 'https://p2.music.126.net/playlist-cover.jpg',
                },
              },
            ],
          },
          _ => <Object?>[],
        };
        return http.Response(
          jsonEncode({'data': data}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final controller = HomeController(
      playlists: PlaylistRepository(api),
      downloads: DownloadRepository(api),
      library: LibraryRepository(api),
    );
    await controller.refresh();

    await tester.pumpWidget(
      harness(
        HomeScreen(
          controller: controller,
          onSearch: () {},
          onPlaylists: () {},
          onDownloads: () {},
        ),
      ),
    );

    final networkImages = tester.widgetList<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(networkImages.single.imageUrl, contains('playlist-cover.jpg'));
  });

  testWidgets(
    'desktop home shows placeholder artwork for a track without art',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          final data = request.url.path == '/api/v1/downloads'
              ? [
                  {
                    'id': 'missing-artwork-download',
                    'status': 'completed',
                    'musicInfo': {
                      'id': 'missing-artwork',
                      'name': '无封面歌曲',
                      'singer': '测试歌手',
                      'source': 'local',
                    },
                    'quality': 'flac',
                    'extension': 'flac',
                    'fileName': 'missing-artwork.flac',
                    'downloaded': 2048,
                    'total': 2048,
                    'progress': 100,
                    'createdAt': 1000,
                    'updatedAt': 2000,
                  },
                ]
              : <Object?>[];
          return http.Response(
            jsonEncode({'data': data}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final controller = HomeController(
        playlists: PlaylistRepository(api),
        downloads: DownloadRepository(api),
        library: LibraryRepository(api),
      );
      await controller.refresh();

      await tester.pumpWidget(
        harness(
          HomeScreen(
            controller: controller,
            onSearch: () {},
            onPlaylists: () {},
            onDownloads: () {},
          ),
        ),
      );

      expect(find.text('无封面歌曲'), findsWidgets);
      expect(
        find.byKey(const Key('artwork-fallback-local:missing-artwork')),
        findsNWidgets(2),
      );
    },
  );

  testWidgets('mobile home uses an immersive gallery composition', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        final data = request.url.path == '/api/v1/downloads'
            ? [
                {
                  'id': 'wind-download',
                  'status': 'completed',
                  'musicInfo': {
                    'id': 'wind',
                    'name': '晚风',
                    'singer': '伍佰 & China Blue',
                    'source': 'kw',
                  },
                  'quality': 'flac',
                  'extension': 'flac',
                  'fileName': 'wind.flac',
                  'downloaded': 2048,
                  'total': 2048,
                  'progress': 100,
                  'createdAt': 1000,
                  'updatedAt': 2000,
                },
              ]
            : <Object?>[];
        return http.Response(
          jsonEncode({'data': data}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final controller = HomeController(
      playlists: PlaylistRepository(api),
      downloads: DownloadRepository(api),
      library: LibraryRepository(api),
    );
    await controller.refresh();
    expect(controller.state.error, isNull, reason: '${controller.state.error}');
    expect(controller.state.featured.firstOrNull?.title, '晚风');

    await tester.pumpWidget(
      harness(
        HomeScreen(
          controller: controller,
          onSearch: () {},
          onPlaylists: () {},
          onDownloads: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('home-mobile-layout')), findsOneWidget);
    expect(find.byKey(const Key('home-mobile-masthead')), findsOneWidget);
    expect(find.byKey(const Key('brand-logo')), findsOneWidget);
    expect(find.text('TuneFlow'), findsOneWidget);
    expect(find.byTooltip('设置'), findsNothing);
    expect(find.byType(AppGlassSurface), findsWidgets);
    expect(find.text('继续听点熟悉的。'), findsOneWidget);
    expect(find.byKey(const Key('home-feature-card')), findsOneWidget);
    expect(find.text('晚风'), findsWidgets);
    final galleryArtwork = tester.widget<AppArtwork>(
      find.descendant(
        of: find.byType(InkWell),
        matching: find.byType(AppArtwork),
      ),
    );
    expect(galleryArtwork.showFallbackBorder, isFalse);
    expect(find.text('1 首本地音乐'), findsNothing);
    expect(find.text('音源元数据已更新，缓存音乐仍可播放。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home renders Service content instead of fixed demo copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        final data = switch (request.url.path) {
          '/api/v1/downloads' => [
            {
              'id': 'download-dynamic',
              'status': 'completed',
              'musicInfo': {
                'id': 'dynamic-track',
                'name': '来自 Service 的歌',
                'singer': '真实歌手',
                'source': 'tx',
                'pic': 'https://example.com/cover.jpg',
              },
              'quality': 'flac',
              'extension': 'flac',
              'fileName': 'dynamic.flac',
              'downloaded': 2048,
              'total': 2048,
              'progress': 100,
              'createdAt': 1000,
              'updatedAt': 2000,
            },
          ],
          '/api/v1/library/tracks' => [
            {
              'id': 'local-track',
              'musicInfo': {
                'id': 'local-track',
                'name': '本地歌曲',
                'singer': '本地歌手',
                'source': 'local',
              },
              'size': 4096,
              'extension': 'flac',
              'streamUrl': '/api/v1/library/tracks/local-track/stream',
            },
          ],
          _ => <Object?>[],
        };
        return http.Response(
          jsonEncode({'data': data}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final controller = HomeController(
      playlists: PlaylistRepository(api),
      downloads: DownloadRepository(api),
      library: LibraryRepository(api),
    );
    await controller.refresh();
    expect(controller.state.error, isNull, reason: '${controller.state.error}');
    expect(controller.state.featured.first.title, '来自 Service 的歌');
    expect(controller.state.library.single.track.title, '本地歌曲');

    await tester.pumpWidget(
      harness(
        HomeScreen(
          controller: controller,
          onSearch: () {},
          onPlaylists: () {},
          onDownloads: () {},
        ),
      ),
    );
    expect(find.text('来自 Service 的歌'), findsWidgets);
    expect(find.text('真实歌手'), findsWidgets);
    expect(find.text('最近下载'), findsOneWidget);
    expect(find.text('1 首本地音乐'), findsOneWidget);
    expect(find.textContaining('伍佰'), findsNothing);
    expect(find.text('让声音\n占据房间。'), findsNothing);
  });

  testWidgets('hero uses recommendation only when listening history is empty', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var includeHistory = false;
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        final Object data = switch (request.url.path) {
          '/api/v1/recommendations/daily' => recommendationSnapshotJson(),
          '/api/v1/playback/history' when includeHistory => [
            {
              'track': {
                'id': 'history-hero',
                'name': 'History Hero',
                'singer': 'Known Artist',
                'source': 'kw',
              },
              'startedAt': 123,
            },
          ],
          _ => <Object?>[],
        };
        return http.Response(
          jsonEncode({'data': data}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    HomeController makeController(String cacheKey) => HomeController(
      playlists: PlaylistRepository(api),
      downloads: DownloadRepository(api),
      library: LibraryRepository(api),
      history: PlaybackHistoryRepository(api, platform: 'other'),
      recommendations: RecommendationController(
        repository: RecommendationRepository(api),
        cache: SharedRecommendationCache(
          serviceOrigin: Uri.parse('http://$cacheKey.local'),
        ),
      ),
    );

    final recommendationHome = makeController('hero-recommendation');
    await recommendationHome.refresh();
    await tester.pumpWidget(
      harness(
        HomeScreen(
          key: const ValueKey('recommendation-home'),
          controller: recommendationHome,
          onSearch: () {},
          onPlaylists: () {},
          onDownloads: () {},
          onRecommendations: () {},
          onRecommendationSettings: () {},
          loadRecommendationPicture: (_) async => null,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Track 0'), findsWidgets);
    expect(find.text('播放推荐'), findsOneWidget);

    includeHistory = true;
    final historyHome = makeController('hero-history');
    await historyHome.refresh();
    await tester.pumpWidget(
      harness(
        HomeScreen(
          key: const ValueKey('history-home'),
          controller: historyHome,
          onSearch: () {},
          onPlaylists: () {},
          onDownloads: () {},
          onRecommendations: () {},
          onRecommendationSettings: () {},
          loadRecommendationPicture: (_) async => null,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('History Hero'), findsWidgets);
    expect(find.text('继续播放'), findsOneWidget);
    expect(find.text('播放推荐'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
