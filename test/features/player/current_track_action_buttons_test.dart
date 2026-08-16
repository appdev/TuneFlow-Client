import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/downloads/user_download_coordinator.dart';
import 'package:musicfree_service_client/features/player/current_track_action_buttons.dart';
import 'package:musicfree_service_client/features/player/current_track_actions_controller.dart';
import 'package:musicfree_service_client/features/player/playback_repository.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/features/player/player_state.dart';
import 'package:musicfree_service_client/features/player/service_audio_handler.dart';
import 'package:musicfree_service_client/features/playlists/favorite_playlist.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('renders accessible 44px favorite and download actions', (
    tester,
  ) async {
    final fixture = await _pumpActions(tester);

    for (final key in ['test-favorite', 'test-download']) {
      expect(tester.getSize(find.byKey(Key(key))), const Size.square(44));
    }
    expect(find.bySemanticsLabel('收藏当前歌曲'), findsOneWidget);
    expect(find.bySemanticsLabel('下载当前歌曲'), findsOneWidget);

    await tester.tap(find.byKey(const Key('test-favorite')));
    await tester.pump();

    expect(fixture.favorites.setCalls, ['kw:a:true']);
    expect(find.bySemanticsLabel('取消收藏'), findsOneWidget);
    expect(
      tester.widget<ShadButton>(find.byKey(const Key('test-favorite'))).variant,
      ShadButtonVariant.secondary,
    );
  });

  testWidgets('downloads directly and shows success feedback', (tester) async {
    final fixture = await _pumpActions(tester);

    await tester.tap(find.byKey(const Key('test-download')));
    await _pumpFiniteAnimations(tester);

    expect(fixture.downloadCalls, ['kw:a:128k']);
    expect(find.text('已加入下载队列'), findsOneWidget);
  });

  testWidgets('shows stable download progress and restores after failure', (
    tester,
  ) async {
    final gate = Completer<void>();
    final fixture = await _pumpActions(tester, downloadGate: gate);

    await tester.tap(find.byKey(const Key('test-download')));
    await tester.pump();

    expect(fixture.downloadCalls, ['kw:a:128k']);
    expect(find.byKey(const Key('test-download-loading')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('test-download'))),
      const Size.square(44),
    );

    gate.completeError(StateError('download failed'));
    await _pumpFiniteAnimations(tester);

    expect(find.text('下载失败'), findsOneWidget);
    expect(find.byKey(const Key('test-download-loading')), findsNothing);
    expect(
      tester.widget<ShadButton>(find.byKey(const Key('test-download'))).enabled,
      isTrue,
    );
  });

  testWidgets('rolls back favorite shape and reports a failed action', (
    tester,
  ) async {
    final fixture = await _pumpActions(
      tester,
      favoriteError: StateError('favorite failed'),
    );

    await tester.tap(find.byKey(const Key('test-favorite')));
    await _pumpFiniteAnimations(tester);

    expect(fixture.favorites.setCalls, ['kw:a:true']);
    expect(find.text('收藏失败'), findsOneWidget);
    expect(find.bySemanticsLabel('收藏当前歌曲'), findsOneWidget);
    expect(
      tester.widget<ShadButton>(find.byKey(const Key('test-favorite'))).variant,
      ShadButtonVariant.ghost,
    );
  });
}

Future<_ActionsFixture> _pumpActions(
  WidgetTester tester, {
  Completer<void>? downloadGate,
  Object? favoriteError,
}) async {
  final player = PlayerController(
    resolver: _FakeResolver(),
    audio: _FakeAudio(),
  );
  await player.playTracks([
    Track.fromJson({'id': 'a', 'name': 'A', 'source': 'kw'}),
  ]);
  final favorites = _FakeFavorites()..setError = favoriteError;
  final downloadCalls = <String>[];
  final actions = CurrentTrackActionsController(
    player: player,
    favorites: favorites,
    download: (track, quality, {required confirmReplacement}) async {
      downloadCalls.add('${track.source}:${track.id}:$quality');
      if (downloadGate != null) await downloadGate.future;
      return UserDownloadResult(job: _queuedDownload(), replaced: false);
    },
  );
  addTearDown(actions.dispose);
  addTearDown(player.dispose);

  await tester.pumpWidget(
    ShadApp.custom(
      theme: buildLightTheme(),
      appBuilder: (context) => MaterialApp(
        theme: Theme.of(context),
        home: Scaffold(
          body: ShadAppBuilder(
            child: Center(
              child: CurrentTrackActionButtons(
                controller: actions,
                keyPrefix: 'test',
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return _ActionsFixture(favorites: favorites, downloadCalls: downloadCalls);
}

DownloadJob _queuedDownload() => DownloadJob.fromJson({
  'id': 'download-a',
  'status': 'waiting',
  'musicInfo': {'id': 'a', 'name': 'A', 'source': 'kw'},
  'quality': '128k',
  'extension': 'mp3',
  'fileName': 'a.mp3',
  'downloaded': 0,
  'total': 0,
  'progress': 0,
  'queuePosition': 1,
  'createdAt': 1000,
  'updatedAt': 1000,
});

Future<void> _pumpFiniteAnimations(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final class _ActionsFixture {
  const _ActionsFixture({required this.favorites, required this.downloadCalls});

  final _FakeFavorites favorites;
  final List<String> downloadCalls;
}

final class _FakeFavorites implements FavoritePlaylistPort {
  Object? setError;
  final setCalls = <String>[];

  @override
  Future<bool> contains(Track track) async => false;

  @override
  Future<void> setFavorite(Track track, bool favorite) async {
    setCalls.add('${track.source}:${track.id}:$favorite');
    if (setError case final error?) throw error;
  }
}

final class _FakeResolver implements PlaybackResolver {
  @override
  Future<PlaybackSource> resolve(Track track, String quality) async =>
      PlaybackSource(
        resolved: ResolvedTrack(
          url: '/api/v1/streams/${track.id}',
          quality: quality,
          expiresAt: 1,
        ),
        streamUri: Uri.parse('http://service.local/api/v1/streams/${track.id}'),
      );
}

final class _FakeAudio implements AudioPort {
  @override
  Stream<AudioSnapshot> get snapshots => Stream.value(
    const AudioSnapshot(
      playing: true,
      processing: PlayerProcessing.ready,
      duration: Duration(minutes: 3),
    ),
  );

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
