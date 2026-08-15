import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/connection/connection_controller.dart';
import '../features/downloads/download_repository.dart';
import '../features/playback_history/playback_history_repository.dart';
import '../features/playback_history/playback_platform.dart';
import '../features/player/current_track_actions_controller.dart';
import '../features/player/playback_repository.dart';
import '../features/player/player_controller.dart';
import '../features/playlists/favorite_playlist.dart';
import '../features/playlists/playlist_repository.dart';
import '../storage/app_settings_controller.dart';
import 'app_providers.dart';

final playerControllerProvider = Provider<PlayerController?>((ref) {
  final connected = ref.watch(connectionProvider).value;
  if (connected == null) return null;
  final quality =
      ref.read(appSettingsProvider).value?.quality.apiValue ?? '128k';
  final showTranslation =
      ref.read(appSettingsProvider).value?.showTranslation ?? true;
  final controller = PlayerController(
    resolver: PlaybackRepository(connected.api),
    audio: ref.read(audioPortProvider),
    quality: quality,
    showTranslation: showTranslation,
    sessions: PlaybackHistoryRepository(
      connected.api,
      platform: currentPlaybackPlatform(),
    ),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final currentTrackActionsProvider = Provider<CurrentTrackActionsController?>((
  ref,
) {
  final connected = ref.watch(connectionProvider).value;
  final player = ref.watch(playerControllerProvider);
  if (connected == null || player == null) return null;
  final playlists = PlaylistRepository(connected.api);
  final downloads = DownloadRepository(connected.api);
  final controller = CurrentTrackActionsController(
    player: player,
    favorites: LovePlaylistFavorites(playlists),
    download: (track, quality) async {
      await downloads.create(track, quality);
    },
  );
  ref.onDispose(controller.dispose);
  return controller;
});
