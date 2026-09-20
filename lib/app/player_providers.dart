import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../diagnostics/app_logger.dart';

import '../features/connection/connection_controller.dart';
import '../features/downloads/download_repository.dart';
import '../features/downloads/user_download_coordinator.dart';
import '../features/playback_history/playback_history_repository.dart';
import '../features/playback_history/playback_platform.dart';
import '../features/player/current_track_actions_controller.dart';
import '../features/player/playback_repository.dart';
import '../features/player/player_controller.dart';
import '../features/playlists/favorite_playlist.dart';
import '../features/playlists/playlist_repository.dart';
import '../features/radio/radio_controller.dart';
import '../features/radio/radio_repository.dart';
import '../storage/app_settings_controller.dart';
import '../storage/app_preferences.dart';
import 'app_providers.dart';

final playerControllerProvider = Provider<PlayerController?>((ref) {
  final api = ref.watch(
    connectionProvider.select((connection) => connection.value?.api),
  );
  if (api == null) return null;
  final quality =
      ref.read(appSettingsProvider).value?.quality.apiValue ?? '128k';
  final showTranslation =
      ref.read(appSettingsProvider).value?.showTranslation ?? true;
  final settings = ref.read(appSettingsProvider).value ?? const AppSettings();
  final controller = PlayerController(
    resolver: PlaybackRepository(api),
    audio: ref.read(audioPortProvider),
    quality: quality,
    showTranslation: showTranslation,
    showLyrics: settings.showLyrics,
    showRomanization: settings.showRomanization,
    lyricFontSize: settings.lyricFontSize,
    lyricAlignment: settings.lyricAlignment,
    lyricAuxiliaryOrder: settings.lyricAuxiliaryOrder,
    useTraditionalLyrics: settings.useTraditionalLyrics,
    emphasizeActiveLyric: settings.emphasizeActiveLyric,
    rememberPlaybackProgress: settings.rememberPlaybackProgress,
    autoSkipPlaybackErrors: settings.autoSkipPlaybackErrors,
    trackStateStore: ref.read(trackPlaybackStateStoreProvider),
    reportPersistenceError: (error) {
      AppLogger.instance.record(
        AppLogEvent.playbackStateFailed,
        level: AppLogLevel.warning,
        error: error,
      );
      ref.read(appMessageCenterProvider).enqueue('本地播放设置保存失败', '当前会话仍会保留更改。');
    },
    sessions: PlaybackHistoryRepository(
      api,
      platform: currentPlaybackPlatform(),
    ),
  );
  ref.listen(appSettingsProvider, (previous, next) {
    final value = next.value;
    if (value != null) controller.applySettings(value);
  });
  ref.onDispose(controller.dispose);
  return controller;
});

final radioControllerProvider = Provider<RadioController?>((ref) {
  final api = ref.watch(
    connectionProvider.select((connection) => connection.value?.api),
  );
  final player = ref.watch(playerControllerProvider);
  if (api == null || player == null) return null;
  final controller = RadioController(
    repository: RadioRepository(api),
    player: player,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final currentTrackActionsProvider = Provider<CurrentTrackActionsController?>((
  ref,
) {
  final api = ref.watch(
    connectionProvider.select((connection) => connection.value?.api),
  );
  final player = ref.watch(playerControllerProvider);
  if (api == null || player == null) return null;
  final playlists = PlaylistRepository(api);
  final downloads = DownloadRepository(api);
  final controller = CurrentTrackActionsController(
    player: player,
    favorites: LovePlaylistFavorites(playlists),
    download: (track, quality, {required confirmReplacement}) =>
        UserDownloadCoordinator(
          downloads,
        ).create(track, quality, confirmReplacement: confirmReplacement),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
