import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../api/sse_transport.dart';
import '../events/event_coordinator.dart';
import '../features/connection/connection_controller.dart';
import '../features/settings/settings_controller.dart';
import '../features/playlists/playlist_repository.dart';
import '../platform/macos_menu_bar_coordinator.dart';
import '../features/settings/service_settings_repository.dart';
import '../features/search/search_repository.dart';
import '../storage/app_settings_controller.dart';
import 'app_providers.dart';
import 'player_providers.dart';

final macOSMenuBarCoordinatorProvider = Provider<MacOSMenuBarCoordinator>((
  ref,
) {
  final api = ref.watch(
    connectionProvider.select((connection) => connection.value?.api),
  );
  final messages = ref.read(appMessageCenterProvider);
  final coordinator = MacOSMenuBarCoordinator(
    player: ref.watch(playerControllerProvider),
    favorites: api == null
        ? null
        : LovePlaylistFavorites(PlaylistRepository(api)),
    menuBar: ref.read(macOSMenuBarPortProvider),
    reportFailure: messages.enqueue,
    revealPendingMessages: messages.revealPending,
    hidePendingMessages: messages.hide,
  );
  unawaited(coordinator.start());
  ref.onDispose(() => unawaited(coordinator.dispose()));
  return coordinator;
});

final settingsControllerProvider = Provider<SettingsController?>((ref) {
  final ready = ref.watch(
    appSettingsProvider.select((settings) => settings.value != null),
  );
  if (!ready) return null;
  final settings = ref.read(appSettingsProvider).value!;
  final api = ref.watch(
    connectionProvider.select((connection) => connection.value?.api),
  );
  final diagnostics = ref.read(connectionProvider).value?.diagnostics;
  final serviceSettings = api == null ? null : ServiceSettingsRepository(api);
  final controller = SettingsController(
    settings: settings,
    save: ref.read(appSettingsProvider.notifier).saveSettings,
    connect: ref.read(connectionProvider.notifier).connect,
    disconnect: ref.read(connectionProvider.notifier).disconnect,
    setPlayerQuality: (quality) async {
      await ref.read(playerControllerProvider)?.setQuality(quality);
    },
    initialDiagnostics: diagnostics,
    mediaCache: ref.read(mediaCacheProvider),
    imageCache: ref.read(appImageCacheProvider),
    loadAutoDownloadOnPlay: serviceSettings?.getAutoDownloadOnPlay,
    updateAutoDownloadOnPlay: serviceSettings?.setAutoDownloadOnPlay,
    loadServiceAccessOrigins: serviceSettings?.getAccessOrigins,
    updateServiceAccessOrigins: serviceSettings?.updateAccessOrigins,
    applyServiceEndpoints: ref.read(connectionProvider.notifier).applyEndpoints,
  );
  ref.listen(appSettingsProvider, (previous, next) {
    final updated = next.value;
    if (updated != null) controller.syncSettings(updated);
  });
  ref.listen(
    connectionProvider.select((connection) => connection.value?.diagnostics),
    (previous, next) => controller.syncConnection(next),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final class EventInvalidation extends ChangeNotifier {
  int sourcesVersion = 0;
  int playlistsVersion = 0;
  int downloadsVersion = 0;
  int libraryVersion = 0;
  final Map<String, int> _playlistDetails = {};

  void sources() {
    sourcesVersion++;
    notifyListeners();
  }

  void playlists() {
    playlistsVersion++;
    notifyListeners();
  }

  void downloads() {
    downloadsVersion++;
    notifyListeners();
  }

  void library() {
    libraryVersion++;
    notifyListeners();
  }

  void playlistDetail(String id) {
    _playlistDetails[id] = (_playlistDetails[id] ?? 0) + 1;
    notifyListeners();
  }

  int playlistDetailVersion(String id) => _playlistDetails[id] ?? 0;
}

final eventInvalidationProvider = Provider<EventInvalidation>((ref) {
  final invalidation = EventInvalidation();
  ref.onDispose(invalidation.dispose);
  return invalidation;
});

final eventSubscriptionProvider = Provider<StreamSubscription<DomainEvent>?>((
  ref,
) {
  final api = ref.watch(
    connectionProvider.select((connection) => connection.value?.api),
  );
  if (api == null) return null;
  final invalidation = ref.read(eventInvalidationProvider);
  final player = ref.watch(playerControllerProvider);
  final search = SearchRepository(api);
  final lyricsLoader = search.lyrics;
  final coordinator = EventCoordinator(
    invalidateSources: invalidation.sources,
    invalidatePlaylists: invalidation.playlists,
    invalidateDownloads: invalidation.downloads,
    invalidateLibrary: invalidation.library,
    invalidatePlaylistDetail: invalidation.playlistDetail,
    trackResourcesUpdated: (source, trackId, resources) {
      if (resources.contains('lyrics')) {
        unawaited(
          player?.refreshLyricsIfMissing(
            lyricsLoader,
            source: source,
            trackId: trackId,
          ),
        );
      }
      if (resources.contains('picture')) {
        unawaited(
          player?.refreshArtworkIfMissing(
            search.picture,
            source: source,
            trackId: trackId,
          ),
        );
      }
    },
  );
  final transport = SseTransport(
    api,
    onConnected: () async {
      await player?.refreshLyricsIfMissing(lyricsLoader);
    },
  );
  final subscription = transport.events().listen(coordinator.accept);
  ref.onDispose(() {
    subscription.cancel();
    transport.close();
  });
  return subscription;
});
