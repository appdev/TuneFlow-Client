import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/catalog/catalog_track_list.dart';
import 'package:musicfree_service_client/features/playlists/playlist_detail_controller.dart';
import 'package:musicfree_service_client/features/playlists/playlist_detail_screen.dart';
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

void main() {
  testWidgets('renders playlist metadata from the Service detail', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = PlaylistRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'id': 'remote-mix',
                'name': 'Remote Mix',
                'tracks': [
                  {
                    'id': 'one',
                    'name': 'One',
                    'singer': 'Artist A',
                    'source': 'kw',
                    'interval': 200,
                    'types': ['flac'],
                  },
                  {
                    'id': 'two',
                    'name': 'Two',
                    'singer': 'Artist B',
                    'source': 'kw',
                    'img': 'https://cdn.example.test/two.jpg',
                  },
                ],
              },
            }),
            200,
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      harness(
        PlaylistDetailScreen(
          controller: PlaylistDetailController(repository, 'remote-mix'),
          playTracks: (tracks, {startIndex = 0}) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('playlist-detail-route')), findsOneWidget);
    expect(find.text('Remote Mix'), findsWidgets);
    expect(find.textContaining('2 首'), findsWidgets);
    expect(find.textContaining('24 首'), findsNothing);
    expect(find.textContaining('伍佰 & China Blue 的夜路'), findsNothing);
    expect(find.byType(CatalogTrackTableHeader), findsOneWidget);
    expect(find.byType(CatalogTrackRow), findsNWidgets(2));
    expect(find.text('封面'), findsOneWidget);
    expect(find.text('歌曲名'), findsOneWidget);
    expect(find.text('无损'), findsOneWidget);
    expect(find.text('3:20'), findsOneWidget);
    expect(find.byIcon(LucideIcons.gripVertical), findsNWidgets(2));
    expect(
      tester.getSize(find.byKey(const Key('playlist-hero-artwork'))).height,
      240,
    );
    expect(find.byType(Image), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final layout in [
    (name: 'mobile', size: const Size(390, 844)),
    (name: 'desktop', size: const Size(1200, 900)),
  ]) {
    testWidgets(
      '${layout.name} reorder callback uses Flutter-adjusted destination index',
      (tester) => _expectAdjustedReorder(tester, layout.size),
    );
  }
}

Future<void> _expectAdjustedReorder(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  int? capturedPosition;
  List<Object?>? capturedTrackIds;
  final repository = PlaylistRepository(
    ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        const tracks = [
          {'id': 'one', 'name': 'One', 'singer': 'Artist A', 'source': 'kw'},
          {'id': 'two', 'name': 'Two', 'singer': 'Artist B', 'source': 'kw'},
        ];
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedPosition = body['position'] as int;
          capturedTrackIds = body['trackIds'] as List<Object?>;
          return http.Response(jsonEncode({'data': tracks}), 200);
        }
        return http.Response(
          jsonEncode({
            'data': {
              'id': 'remote-mix',
              'name': 'Remote Mix',
              'tracks': tracks,
            },
          }),
          200,
        );
      }),
    ),
  );

  await tester.pumpWidget(
    harness(
      PlaylistDetailScreen(
        controller: PlaylistDetailController(repository, 'remote-mix'),
        playTracks: (tracks, {startIndex = 0}) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();

  final list = tester.widget<ReorderableListView>(
    find.byType(ReorderableListView).first,
  );
  expect(list.onReorderItem, isNotNull);

  list.onReorderItem!(0, 1);
  await tester.pumpAndSettle();

  expect(capturedPosition, 1);
  expect(capturedTrackIds, ['one']);
}
