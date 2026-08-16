import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/app_glass_surface.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';
import 'package:musicfree_service_client/features/catalog/catalog_track_list.dart';
import 'package:musicfree_service_client/features/downloads/download_repository.dart';
import 'package:musicfree_service_client/features/player/playback_repository.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/features/player/player_state.dart';
import 'package:musicfree_service_client/features/player/service_audio_handler.dart';
import 'package:musicfree_service_client/features/playlists/playlist_repository.dart';
import 'package:musicfree_service_client/features/search/search_controller.dart'
    as feature;
import 'package:musicfree_service_client/features/search/search_desktop_results.dart';
import 'package:musicfree_service_client/features/search/search_history_repository.dart';
import 'package:musicfree_service_client/features/search/search_repository.dart';
import 'package:musicfree_service_client/features/search/search_mobile_results.dart';
import 'package:musicfree_service_client/features/search/search_screen.dart';
import 'package:musicfree_service_client/features/search/search_track_artwork.dart';
import 'package:musicfree_service_client/features/search/track_action.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

PlayerController testPlayer() =>
    PlayerController(resolver: _Resolver(), audio: _Audio());

final class _Resolver implements PlaybackResolver {
  @override
  Future<PlaybackSource> resolve(Track track, String quality) async =>
      PlaybackSource(
        resolved: ResolvedTrack(url: '/stream', quality: quality, expiresAt: 0),
        streamUri: Uri.parse('http://service.local/stream'),
      );
}

final class _Audio implements AudioPort {
  @override
  Stream<AudioSnapshot> get snapshots => const Stream.empty();
  @override
  void bindQueueCallbacks({
    required Future<void> Function() previous,
    required Future<void> Function() next,
  }) {}
  @override
  Future<void> pause() async {}
  @override
  Future<bool> playCachedTrack(Track track, String quality) async => true;
  @override
  Future<void> playTrack(Track track, Uri streamUri, String quality) async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stopPlayback() async {}
}

void main() {
  testWidgets('desktop search leaves navigation controls to window chrome', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient(
        (_) async => http.Response(jsonEncode({'data': <Object?>[]}), 200),
      ),
    );

    await tester.pumpWidget(
      harness(
        SearchScreen(
          controller: feature.SearchController(SearchRepository(api)),
          playlists: PlaylistRepository(api),
          downloads: DownloadRepository(api),
          player: testPlayer(),
        ),
      ),
    );

    expect(find.byKey(const Key('search-wide-layout')), findsOneWidget);
    expect(find.byTooltip('返回'), findsNothing);
    expect(find.byTooltip('前进'), findsNothing);
    expect(tester.getTopLeft(find.byKey(const Key('search-field'))).dx, 30);
  });

  testWidgets('desktop artwork is clipped to a rounded square', (tester) async {
    const artworkSize = 38.0;
    final track = Track.fromJson({
      'id': 'square-cover',
      'name': '晚风',
      'singer': '伍佰 & China Blue',
      'source': 'kw',
    });

    await tester.pumpWidget(
      harness(
        Center(
          child: SearchTrackArtwork(
            track: track,
            loadPicture: (_) async => null,
            size: artworkSize,
            borderRadius: 8,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final frame = find.byKey(const Key('search-artwork-frame-kw-square-cover'));
    expect(tester.getSize(frame), const Size.square(artworkSize));
    expect(
      tester.widget<ClipRRect>(frame).borderRadius,
      BorderRadius.circular(8),
    );
  });

  testWidgets('desktop table columns and row controls share fixed axes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final rowTrack = Track.fromJson({
      'id': 'alignment',
      'name': '晴天',
      'singer': '周杰伦',
      'source': 'tx',
      'albumName': '叶惠美',
      'interval': 253,
      'types': ['flac'],
    });

    await tester.pumpWidget(
      harness(
        SizedBox(
          width: 1200,
          height: 600,
          child: SearchDesktopResults(
            state: feature.SearchState(
              query: '晴天',
              source: 'tx',
              view: feature.SearchView.tracks,
              trackSection: feature.SearchSection(
                items: [rowTrack],
                page: 1,
                total: 1,
                phase: feature.SearchPhase.results,
              ),
            ),
            scrollController: scroll,
            loadPicture: (_) async => null,
            onPlay: (_) {},
            onFavorite: (_) {},
            actionsFor: (_) => const [],
            onViewAll: (_) {},
            onPage: (_) {},
            onRetry: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getCenter(find.text('专辑')).dx,
      closeTo(tester.getCenter(find.text('叶惠美')).dx, .1),
    );
    expect(
      tester.getCenter(find.text('时长')).dx,
      closeTo(tester.getCenter(find.text('4:13')).dx, .1),
    );
    final rowCenter = tester
        .getCenter(find.byKey(const Key('search-track-tx-alignment')))
        .dy;
    expect(
      tester
          .getCenter(find.byKey(const Key('search-favorite-tx-alignment')))
          .dy,
      closeTo(rowCenter, 1),
    );
    expect(tester.getCenter(find.text('4:13')).dy, closeTo(rowCenter, 1));
    expect(
      tester.getSize(find.byKey(const Key('search-track-tx-alignment'))).height,
      58,
    );
    expect(
      tester.widget<SearchTrackArtwork>(find.byType(SearchTrackArtwork)).size,
      38,
    );
    expect(
      tester.getSize(
        find.byKey(const Key('search-artwork-frame-tx-alignment')),
      ),
      const Size.square(38),
    );
    expect(find.text('01'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('compact desktop uses the approved 90 and 54 pixel rhythm', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final track = Track.fromJson({
      'id': 'compact',
      'name': '晚风',
      'singer': '伍佰 & China Blue',
      'source': 'kw',
      'albumName': '求婚事务所 电视原声带',
      'interval': 248,
      'types': ['flac24bit'],
    });

    await tester.pumpWidget(
      harness(
        SizedBox(
          width: 760,
          height: 620,
          child: SearchDesktopResults(
            state: feature.SearchState(
              query: '伍佰',
              source: 'kw',
              view: feature.SearchView.overview,
              trackSection: feature.SearchSection(
                items: [track],
                page: 1,
                total: 1,
                phase: feature.SearchPhase.results,
              ),
            ),
            scrollController: scroll,
            loadPicture: (_) async => null,
            onPlay: (_) {},
            onFavorite: (_) {},
            actionsFor: (_) => const [],
            onViewAll: (_) {},
            onPage: (_) {},
            onRetry: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('search-best-match'))).height,
      90,
    );
    expect(
      tester.getSize(find.byKey(const Key('search-track-kw-compact'))).height,
      54,
    );
    expect(find.text('求婚事务所 电视原声带'), findsNothing);
    expect(find.text('4:08'), findsNothing);
  });

  testWidgets('mobile rows omit artwork and duration with compact metadata', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var pictureRequests = 0;
    final track = Track.fromJson({
      'id': 'one',
      'name': '晴天',
      'singer': '周杰伦',
      'source': 'tx',
      'albumName': '叶惠美',
      'interval': 253,
      'types': ['flac'],
      'pic': 'https://example.test/cover.jpg',
    });
    await tester.pumpWidget(
      harness(
        SearchMobileResults(
          state: feature.SearchState(
            query: '晴天',
            source: 'tx',
            view: feature.SearchView.tracks,
            providers: const [
              CatalogProvider(
                id: 'tx',
                name: '企鹅音乐',
                searchKinds: {CatalogSearchKind.track},
              ),
            ],
            trackSection: feature.SearchSection(
              items: [track],
              page: 1,
              total: 1,
              phase: feature.SearchPhase.results,
            ),
          ),
          scrollController: scroll,
          loadPicture: (_) async {
            pictureRequests += 1;
            return null;
          },
          onPlay: (_) {},
          onFavorite: (_) {},
          onMore: (_) {},
          onViewAll: (_) {},
          onRetry: (_) {},
        ),
      ),
    );

    expect(find.text('晴天'), findsOneWidget);
    expect(find.text('无损'), findsOneWidget);
    expect(find.text('周杰伦'), findsOneWidget);
    expect(find.text('叶惠美'), findsNothing);
    expect(find.text('4:13'), findsNothing);
    expect(find.text('企鹅音乐'), findsNothing);
    expect(find.byType(AppArtwork), findsNothing);
    expect(find.byType(SearchTrackArtwork), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('search-track-tx-one'))).height,
      60,
    );
    expect(pictureRequests, 0);
  });

  testWidgets('mobile overview renders the track list without a feature card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final track = Track.fromJson({
      'id': 'wind',
      'name': '晚风',
      'singer': '伍佰',
      'source': 'kw',
    });
    await tester.pumpWidget(
      harness(
        SearchMobileResults(
          state: feature.SearchState(
            query: '伍佰',
            source: 'kw',
            view: feature.SearchView.overview,
            trackSection: feature.SearchSection(
              items: [track],
              page: 1,
              total: 1,
              phase: feature.SearchPhase.results,
            ),
            playlistSection: const feature.SearchSection(
              items: [
                CatalogCollection(
                  id: 'playlist',
                  name: '不应出现在综合首屏',
                  source: 'kw',
                  kind: CatalogSearchKind.playlist,
                ),
              ],
              phase: feature.SearchPhase.results,
            ),
          ),
          scrollController: scroll,
          loadPicture: (_) async => null,
          onPlay: (_) {},
          onFavorite: (_) {},
          onMore: (_) {},
          onViewAll: (_) {},
          onRetry: (_) {},
        ),
      ),
    );

    expect(find.text('不应出现在综合首屏'), findsNothing);
    expect(find.text('单曲'), findsNothing);
    expect(find.byKey(const Key('search-best-match')), findsNothing);
    expect(find.byKey(const Key('search-track-kw-wind')), findsOneWidget);
  });

  testWidgets('shows Web-equivalent provider tabs and aggregate search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'data': {
              'sources': [
                {
                  'id': 'kw',
                  'name': '酷我音乐',
                  'searchKinds': ['track'],
                },
                {
                  'id': 'kg',
                  'name': '酷狗音乐',
                  'searchKinds': ['track'],
                },
                {
                  'id': 'tx',
                  'name': 'QQ音乐',
                  'searchKinds': ['track'],
                },
                {
                  'id': 'wy',
                  'name': '网易音乐',
                  'searchKinds': ['track'],
                },
                {
                  'id': 'mg',
                  'name': '咪咕音乐',
                  'searchKinds': ['track'],
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    await tester.pumpWidget(
      harness(
        SearchScreen(
          controller: feature.SearchController(SearchRepository(api)),
          playlists: PlaylistRepository(api),
          downloads: DownloadRepository(api),
          player: testPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in ['酷我音乐', '酷狗音乐', 'QQ音乐', '网易音乐', '咪咕音乐', '聚合搜索']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('search history uses the active source without storing one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({
      SearchHistoryRepository.storageKey: ['晚风', '挪威的森林'],
    });
    final preferences = await SharedPreferences.getInstance();
    final searches = <(String, String)>[];
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/catalog/capabilities')) {
          return http.Response(
            jsonEncode({
              'data': {
                'sources': [
                  {
                    'id': 'kw',
                    'name': '酷我音乐',
                    'searchKinds': ['track'],
                  },
                  {
                    'id': 'tx',
                    'name': 'QQ音乐',
                    'searchKinds': ['track'],
                  },
                ],
              },
            }),
            200,
          );
        }
        final body = jsonDecode(request.body) as Map<String, Object?>;
        if (request.url.path.endsWith('/tracks/search')) {
          searches.add((body['source']! as String, body['text']! as String));
        }
        return http.Response(
          jsonEncode({
            'data': {'list': <Object?>[], 'total': 0},
          }),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      harness(
        SearchScreen(
          controller: feature.SearchController(SearchRepository(api)),
          playlists: PlaylistRepository(api),
          downloads: DownloadRepository(api),
          player: testPlayer(),
          history: SearchHistoryRepository(
            loadPreferences: () async => preferences,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-field')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('search-history-panel')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('search-history-panel'))).dx,
      tester.getTopLeft(find.byKey(const Key('search-field'))).dx,
    );
    final historyItem = find.byKey(const Key('search-history-item-0'));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(historyItem));
    await gesture.down(tester.getCenter(historyItem));
    await tester.pump();
    await gesture.up();
    await gesture.removePointer();
    await tester.pump();

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '晚风',
    );
    expect(find.byKey(const Key('search-history-panel')), findsNothing);
    await tester.pumpAndSettle();

    expect(searches.last, ('kw', '晚风'));
  });

  testWidgets('switching provider tabs replaces results with that source', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final searchedSources = <String>[];
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'data': {
                'sources': [
                  for (final source in [
                    ('kw', '酷我音乐'),
                    ('kg', '酷狗音乐'),
                    ('tx', 'QQ音乐'),
                    ('wy', '网易音乐'),
                    ('mg', '咪咕音乐'),
                  ])
                    {
                      'id': source.$1,
                      'name': source.$2,
                      'searchKinds': ['track'],
                    },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        final body = jsonDecode(request.body) as Map<String, Object?>;
        if (request.url.path.endsWith('/tracks/search')) {
          final source = body['source']! as String;
          searchedSources.add(source);
          return http.Response(
            jsonEncode({
              'data': {
                'list': [
                  {
                    'id': '$source-track',
                    'name': '$source result',
                    'singer': 'Artist',
                    'source': source,
                    'types': ['128k', 'flac'],
                    if (source == 'tx')
                      'img': 'https://example.test/qq-cover.jpg',
                  },
                ],
                'total': 1,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path.endsWith('/picture')) {
          return http.Response(
            jsonEncode({
              'data': {'url': 'https://example.test/fallback.jpg'},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(jsonEncode({'data': <Object?>[]}), 200);
      }),
    );

    await tester.pumpWidget(
      harness(
        SearchScreen(
          controller: feature.SearchController(SearchRepository(api)),
          playlists: PlaylistRepository(api),
          downloads: DownloadRepository(api),
          player: testPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), 'jay');

    String? previousSource;
    for (final source in ['kw', 'kg', 'tx', 'wy', 'mg']) {
      await tester.tap(find.byKey(Key('search-source-$source')));
      await tester.pumpAndSettle();
      expect(find.text('$source result'), findsWidgets);
      if (previousSource != null) {
        expect(find.text('$previousSource result'), findsNothing);
      }
      previousSource = source;
    }

    expect(searchedSources, ['kw', 'kg', 'tx', 'wy', 'mg']);
  });

  testWidgets('playing a search result preserves the result queue', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'data': switch (request.url.path) {
              final path when path.endsWith('/catalog/capabilities') => {
                'sources': [
                  {
                    'id': 'kw',
                    'name': '酷我音乐',
                    'searchKinds': ['track'],
                  },
                ],
              },
              final path when path.endsWith('/tracks/search') => {
                'list': [
                  {
                    'id': 'one',
                    'name': 'One',
                    'singer': 'Artist',
                    'source': 'kw',
                  },
                  {
                    'id': 'two',
                    'name': 'Two',
                    'singer': 'Artist',
                    'source': 'kw',
                    'pic': 'https://example.test/two.jpg',
                  },
                ],
                'total': 2,
              },
              final path when path.endsWith('/tracks/picture') => {
                'url':
                    '/api/v1/playback/resources/'
                    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/'
                    'picture',
              },
              _ => <Object?>[],
            },
          }),
          200,
        ),
      ),
    );
    final player = testPlayer();
    final controller = feature.SearchController(SearchRepository(api));

    await tester.pumpWidget(
      harness(
        SearchScreen(
          controller: controller,
          playlists: PlaylistRepository(api),
          downloads: DownloadRepository(api),
          player: player,
        ),
      ),
    );
    expect(find.text('输入关键词搜索音乐'), findsOneWidget);

    await controller.loadCapabilities();
    await controller.search(source: 'kw', query: 'one');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-track-kw-one')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('search-track-kw-one')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('search-track-kw-one')), findsOneWidget);
    expect(player.state.current?.id, 'one');
    expect(player.state.queue.map((track) => track.id), ['one', 'two']);
    expect(player.state.currentIndex, 0);
    expect(
      player.state.current?.raw['pic'],
      'http://service.local/api/v1/playback/resources/'
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/'
          'picture',
    );
    expect(find.byKey(const Key('search-wide-layout')), findsOneWidget);

    final secondRow = tester
        .widgetList<CatalogTrackRow>(find.byType(CatalogTrackRow))
        .singleWhere((row) => row.track.id == 'two');
    await secondRow.actions
        .singleWhere((action) => action.id == TrackActionId.playNow)
        .invoke();

    expect(player.state.queue.map((track) => track.id), ['one', 'two']);
    expect(player.state.currentIndex, 1);
  });

  testWidgets('search playback uses the list visible when playback starts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pictureResponse = Completer<http.Response>();
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/catalog/capabilities')) {
          return http.Response(
            jsonEncode({
              'data': {
                'sources': [
                  {
                    'id': 'kw',
                    'name': '酷我音乐',
                    'searchKinds': ['track'],
                  },
                ],
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/tracks/picture')) {
          return pictureResponse.future;
        }
        if (request.url.path.endsWith('/tracks/search')) {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final next = body['text'] == 'next';
          return http.Response(
            jsonEncode({
              'data': {
                'list': next
                    ? [
                        {'id': 'three', 'name': 'Three', 'source': 'kw'},
                        {'id': 'four', 'name': 'Four', 'source': 'kw'},
                      ]
                    : [
                        {'id': 'one', 'name': 'One', 'source': 'kw'},
                        {
                          'id': 'two',
                          'name': 'Two',
                          'source': 'kw',
                          'pic': 'https://example.test/two.jpg',
                        },
                      ],
                'total': 2,
              },
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'data': <Object?>[]}), 200);
      }),
    );
    final player = testPlayer();
    final controller = feature.SearchController(SearchRepository(api));

    await tester.pumpWidget(
      harness(
        SearchScreen(
          controller: controller,
          playlists: PlaylistRepository(api),
          downloads: DownloadRepository(api),
          player: player,
        ),
      ),
    );
    await controller.loadCapabilities();
    await controller.search(source: 'kw', query: 'first');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-track-kw-one')));
    await tester.pump();
    await controller.search(source: 'kw', query: 'next');
    await tester.pump();
    pictureResponse.complete(
      http.Response(
        jsonEncode({
          'data': {'url': 'https://example.test/one.jpg'},
        }),
        200,
      ),
    );
    await tester.pumpAndSettle();

    expect(player.state.queue.map((track) => track.id), ['one', 'two']);
    expect(player.state.currentIndex, 0);
  });

  testWidgets('mobile search renders touch rows without a desktop table', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient(
        (_) async => http.Response(jsonEncode({'data': <Object?>[]}), 200),
      ),
    );

    await tester.pumpWidget(
      harness(
        SearchScreen(
          controller: feature.SearchController(SearchRepository(api)),
          playlists: PlaylistRepository(api),
          downloads: DownloadRepository(api),
          player: testPlayer(),
        ),
      ),
    );

    expect(find.byKey(const Key('search-mobile-layout')), findsOneWidget);
    expect(find.byKey(const Key('search-mobile-scroll')), findsOneWidget);
    expect(find.byKey(const Key('search-field')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('search-field')),
        matching: find.byType(AppGlassSurface),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile search follows the approved workbench hierarchy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'data': {
                'sources': [
                  {
                    'id': 'kw',
                    'name': '酷我音乐',
                    'searchKinds': ['track', 'album', 'playlist'],
                  },
                  {
                    'id': 'tx',
                    'name': 'QQ音乐',
                    'searchKinds': ['track'],
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        final body = jsonDecode(request.body) as Map<String, Object?>;
        if (body['source'] == 'tx') {
          return http.Response(
            jsonEncode({
              'data': {'list': <Object?>[], 'total': 0},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          jsonEncode({
            'data': {
              'list': [
                {
                  'id': 'wind',
                  'name': '晚风',
                  'singer': '伍佰 & China Blue',
                  'source': 'kw',
                  'types': ['flac'],
                },
              ],
              'total': 42,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await tester.pumpWidget(
      harness(
        SearchScreen(
          controller: feature.SearchController(SearchRepository(api)),
          playlists: PlaylistRepository(api),
          downloads: DownloadRepository(api),
          player: testPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('search-mobile-masthead')), findsOneWidget);
    expect(find.byKey(const Key('brand-logo')), findsOneWidget);
    expect(find.byKey(const Key('search-page-title')), findsOneWidget);
    expect(find.text('搜索'), findsOneWidget);
    expect(find.byKey(const Key('search-mobile-filters')), findsOneWidget);
    expect(find.byKey(const Key('search-source-tabs')), findsNothing);
    expect(find.byKey(const Key('search-view-overview')), findsNothing);
    expect(tester.getSize(find.byKey(const Key('search-field'))).height, 52);

    final mastheadY = tester
        .getTopLeft(find.byKey(const Key('search-mobile-masthead')))
        .dy;
    final titleY = tester
        .getTopLeft(find.byKey(const Key('search-page-title')))
        .dy;
    final fieldY = tester.getTopLeft(find.byKey(const Key('search-field'))).dy;
    final filtersY = tester
        .getTopLeft(find.byKey(const Key('search-mobile-filters')))
        .dy;
    expect(mastheadY, lessThan(titleY));
    expect(titleY, lessThan(fieldY));
    expect(fieldY, lessThan(filtersY));

    await tester.enterText(find.byKey(const Key('search-field')), '伍佰');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('search-results-heading')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('search-results-heading')),
        matching: find.text('歌曲'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('42 首'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .join(' | '),
    );
    expect(find.byKey(const Key('search-best-match')), findsNothing);
    expect(find.byKey(const Key('search-track-kw-wind')), findsOneWidget);
  });

  testWidgets('mobile source control keeps providers in a bottom sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final searchedSources = <String>[];
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'data': {
                'sources': [
                  {
                    'id': 'kw',
                    'name': '酷我音乐',
                    'searchKinds': ['track'],
                  },
                  {
                    'id': 'tx',
                    'name': 'QQ音乐',
                    'searchKinds': ['track'],
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        final body = jsonDecode(request.body) as Map<String, Object?>;
        searchedSources.add(body['source']! as String);
        return http.Response(
          jsonEncode({
            'data': {'list': <Object?>[], 'total': 0},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await tester.pumpWidget(
      harness(
        SearchScreen(
          controller: feature.SearchController(SearchRepository(api)),
          playlists: PlaylistRepository(api),
          downloads: DownloadRepository(api),
          player: testPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), 'Jay');
    await tester.tap(find.byKey(const Key('search-source-control')));
    await tester.pumpAndSettle();

    final sheet = find.byType(ShadSheet);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('酷我音乐')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('QQ音乐')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('全部来源')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('search-source-option-tx')));
    await tester.pumpAndSettle();

    expect(find.byType(ShadSheet), findsNothing);
    expect(searchedSources, ['tx']);
  });

  testWidgets(
    'mobile defaults to all sources and keeps collection tabs usable',
    (tester) async {
      CatalogCollection? openedCollection;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final searches = <(String, String)>[];
      final api = ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'data': {
                  'sources': [
                    {
                      'id': 'kw',
                      'name': '酷我音乐',
                      'searchKinds': ['track'],
                    },
                    {
                      'id': 'wy',
                      'name': '网易音乐',
                      'searchKinds': ['track', 'album'],
                    },
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          final body = jsonDecode(request.body) as Map<String, Object?>;
          searches.add((request.url.path, body['source']! as String));
          final albums = request.url.path.endsWith('/albums/search');
          return http.Response(
            jsonEncode({
              'data': {
                'list': albums
                    ? [
                        {
                          'id': 'jay-album',
                          'kind': 'album',
                          'name': '叶惠美',
                          'source': 'wy',
                        },
                      ]
                    : <Object?>[],
                'total': albums ? 1 : 0,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      await tester.pumpWidget(
        harness(
          SearchScreen(
            controller: feature.SearchController(SearchRepository(api)),
            playlists: PlaylistRepository(api),
            downloads: DownloadRepository(api),
            player: testPlayer(),
            onOpenCollection: (collection) => openedCollection = collection,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('search-source-control')),
          matching: find.text('全部来源'),
        ),
        findsOneWidget,
      );
      final albumInkWell = find.descendant(
        of: find.byKey(const Key('search-mobile-filter-albums')),
        matching: find.byType(InkWell),
      );
      expect(tester.widget<InkWell>(albumInkWell).onTap, isNotNull);

      await tester.enterText(find.byKey(const Key('search-field')), 'Jay');
      await tester.tap(find.byKey(const Key('search-mobile-filter-albums')));
      await tester.pumpAndSettle();

      expect(searches, contains(('/api/v1/catalog/albums/search', 'wy')));
      expect(find.text('叶惠美'), findsOneWidget);
      await tester.tap(find.byKey(const Key('search-collection-wy-jay-album')));
      expect(openedCollection?.id, 'jay-album');
    },
  );

  testWidgets('search layout stays overflow-free across target widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in [320.0, 375.0, 414.0, 768.0]) {
      tester.view.physicalSize = Size(width, 844);
      final api = ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'sources': [
                  {
                    'id': 'kw',
                    'name': '酷我音乐',
                    'searchKinds': ['track', 'album', 'playlist'],
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await tester.pumpWidget(
        harness(
          SearchScreen(
            key: ValueKey(width),
            controller: feature.SearchController(SearchRepository(api)),
            playlists: PlaylistRepository(api),
            downloads: DownloadRepository(api),
            player: testPlayer(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'viewport width $width');
    }
  });
}
