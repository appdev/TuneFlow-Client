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
import 'package:musicfree_service_client/features/discovery/album_detail_controller.dart';
import 'package:musicfree_service_client/features/discovery/album_detail_screen.dart';
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

CatalogCollection seed() => const CatalogCollection(
  id: 'album-1',
  kind: CatalogSearchKind.album,
  name: '叶惠美',
  source: 'wy',
  author: '周杰伦',
);

void main() {
  testWidgets('album detail plays the loaded album from the tapped track', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        final value = request.url.path.endsWith('/albums/detail')
            ? {
                'source': 'wy',
                'page': 1,
                'limit': 30,
                'total': 2,
                'hasMore': false,
                'album': seed().toJson(),
                'tracks': [
                  {'id': 'one', 'name': 'One', 'source': 'wy'},
                  {'id': 'two', 'name': 'Two', 'source': 'wy'},
                ],
              }
            : <Object?>[];
        return http.Response(
          jsonEncode({'data': value}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final player = PlayerController(resolver: _Resolver(), audio: _Audio());
    final controller = AlbumDetailController(
      catalog: SearchRepository(api),
      source: 'wy',
      albumId: 'album-1',
      supported: true,
      initialAlbum: seed(),
    );

    await tester.pumpWidget(
      harness(
        AlbumDetailScreen(
          controller: controller,
          player: player,
          playlists: PlaylistRepository(api),
          downloads: DownloadRepository(api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('叶惠美'), findsOneWidget);
    await tester.tap(find.byKey(const Key('search-track-wy-two')));
    await tester.pumpAndSettle();
    expect(player.state.queue.map((track) => track.id), ['one', 'two']);
    expect(player.state.currentIndex, 1);
  });

  testWidgets('unsupported album detail keeps metadata and explains support', (
    tester,
  ) async {
    final api = ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((_) async => throw StateError('must not request')),
    );
    await tester.pumpWidget(
      harness(
        AlbumDetailScreen(
          controller: AlbumDetailController(
            catalog: SearchRepository(api),
            source: 'wy',
            albumId: 'album-1',
            supported: false,
            initialAlbum: seed(),
          ),
          player: PlayerController(resolver: _Resolver(), audio: _Audio()),
          playlists: PlaylistRepository(api),
          downloads: DownloadRepository(api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('叶惠美'), findsOneWidget);
    expect(find.text('当前音源不支持专辑详情'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
