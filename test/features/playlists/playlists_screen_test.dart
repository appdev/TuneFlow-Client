import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/playlist_card.dart';
import 'package:musicfree_service_client/features/library/library_repository.dart';
import 'package:musicfree_service_client/features/playlists/playlist_repository.dart';
import 'package:musicfree_service_client/features/playlists/playlists_controller.dart';
import 'package:musicfree_service_client/features/playlists/playlists_screen.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: ShadAppBuilder(child: child),
  ),
);

void main() {
  testWidgets('renders playlist cards and delegates detail navigation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'data': switch (request.url.path) {
              '/api/v1/playlists' => [
                {'id': 'love', 'name': 'list__name_love'},
              ],
              '/api/v1/library/tracks' => [
                {
                  'id': 'local-file',
                  'musicInfo': {
                    'id': 'local-track',
                    'name': 'Local',
                    'source': 'kw',
                  },
                  'size': 12,
                  'extension': 'mp3',
                  'streamUrl': '/api/v1/library/tracks/local-file/stream',
                },
              ],
              _ => {
                'id': 'love',
                'name': 'love',
                'tracks': [
                  {
                    'id': 'one',
                    'name': 'One',
                    'source': 'kw',
                    'img': 'https://cdn.example.test/one.jpg',
                  },
                  {'id': 'two', 'name': 'Two', 'source': 'kw'},
                ],
              },
            },
          }),
          200,
        ),
      ),
    );
    final controller = PlaylistsController(
      PlaylistRepository(api),
      library: LibraryRepository(api),
    );
    await controller.refresh();
    String? opened;
    var localOpened = false;

    await tester.pumpWidget(
      harness(
        PlaylistsScreen(
          controller: controller,
          onOpen: (id) => opened = id,
          onOpenLocal: () => localOpened = true,
        ),
      ),
    );
    final local = find.byKey(const Key('local-library-card'));
    final love = find.byKey(const Key('playlist-love'));
    expect(local, findsOneWidget);
    expect(
      tester.getTopLeft(local).dy,
      lessThanOrEqualTo(tester.getTopLeft(love).dy),
    );
    await tester.tap(local);
    expect(localOpened, isTrue);
    expect(opened, isNull);
    await tester.tap(find.byKey(const Key('playlist-love')));

    expect(opened, 'love');
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('本地音乐'), findsOneWidget);
    expect(find.text('1 首'), findsOneWidget);
    expect(find.text('2 首'), findsOneWidget);
    expect(find.text('本地收藏'), findsNothing);
    expect(find.text('本地歌单'), findsNothing);
    expect(find.byKey(const Key('create-playlist')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('create-playlist'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(find.byKey(const Key('playlists-gallery-wide')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('playlist-love'))).width,
      lessThanOrEqualTo(playlistGalleryMaxItemExtent),
    );
  });

  testWidgets('keeps an empty read-only local library card discoverable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'data': request.url.path == '/api/v1/playlists'
                ? <Object?>[]
                : request.url.path == '/api/v1/library/tracks'
                ? <Object?>[]
                : <String, Object?>{},
          }),
          200,
        ),
      ),
    );
    final controller = PlaylistsController(
      PlaylistRepository(api),
      library: LibraryRepository(api),
    );
    await controller.refresh();

    await tester.pumpWidget(
      harness(
        PlaylistsScreen(
          controller: controller,
          onOpen: (_) {},
          onOpenLocal: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('local-library-card')), findsOneWidget);
    expect(find.text('0 首'), findsOneWidget);
    expect(find.byTooltip('删除歌单'), findsNothing);
    expect(find.text('还没有歌单'), findsNothing);
  });
}
