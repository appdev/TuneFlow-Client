import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../api/sse_transport.dart';
import '../events/event_coordinator.dart';
import '../features/connection/connection_controller.dart';
import '../features/connection/connection_repository.dart';
import '../features/settings/settings_controller.dart';
import '../features/settings/service_settings_repository.dart';
import '../storage/app_settings_controller.dart';
import 'app_providers.dart';
import 'player_providers.dart';

final settingsControllerProvider = Provider<SettingsController?>((ref) {
  final ready = ref.watch(
    appSettingsProvider.select((settings) => settings.value != null),
  );
  if (!ready) return null;
  final settings = ref.read(appSettingsProvider).value!;
  final connected = ref.watch(connectionProvider).value;
  final serviceSettings = connected == null
      ? null
      : ServiceSettingsRepository(connected.api);
  final controller = SettingsController(
    settings: settings,
    save: ref.read(appSettingsProvider.notifier).saveSettings,
    connect: ref.read(connectionProvider.notifier).connect,
    disconnect: ref.read(connectionProvider.notifier).disconnect,
    setPlayerQuality: (quality) async {
      await ref.read(playerControllerProvider)?.setQuality(quality);
    },
    diagnostics: ConnectionRepository().diagnostics,
    mediaCache: ref.read(mediaCacheProvider),
    imageCache: ref.read(appImageCacheProvider),
    loadAutoDownloadOnPlay: serviceSettings?.getAutoDownloadOnPlay,
    updateAutoDownloadOnPlay: serviceSettings?.setAutoDownloadOnPlay,
  );
  ref.listen(appSettingsProvider, (previous, next) {
    final updated = next.value;
    if (updated != null) controller.syncSettings(updated);
  });
  ref.onDispose(controller.dispose);
  return controller;
});

final class EventInvalidation extends ChangeNotifier {
  int playlistsVersion = 0;
  int downloadsVersion = 0;
  final Map<String, int> _playlistDetails = {};

  void playlists() {
    playlistsVersion++;
    notifyListeners();
  }

  void downloads() {
    downloadsVersion++;
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
  final connected = ref.watch(connectionProvider).value;
  if (connected == null) return null;
  final invalidation = ref.read(eventInvalidationProvider);
  final coordinator = EventCoordinator(
    invalidatePlaylists: invalidation.playlists,
    invalidateDownloads: invalidation.downloads,
    invalidatePlaylistDetail: invalidation.playlistDetail,
  );
  final transport = SseTransport(connected.api);
  final subscription = transport.events().listen(coordinator.accept);
  ref.onDispose(() {
    subscription.cancel();
    transport.close();
  });
  return subscription;
});
