import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_message_center.dart';
import '../features/connection/endpoint_selector.dart';
import '../features/connection/connection_repository.dart';
import '../features/connection/network_type_monitor.dart';
import '../features/connection/server_endpoint_probe.dart';
import '../features/player/service_audio_handler.dart';
import '../features/player/track_playback_state_store.dart';
import '../platform/macos_menu_bar.dart';
import '../storage/app_image_cache.dart';
import '../storage/app_preferences.dart';
import '../storage/media_cache.dart';

final appPreferencesProvider = Provider<AppPreferences>(
  (ref) => SharedAppPreferences(),
);

final connectionRepositoryProvider = Provider<ConnectionRepository>(
  (ref) => ConnectionRepository(),
);

final networkTypeMonitorProvider = Provider<NetworkTypeMonitor>(
  (ref) => ConnectivityNetworkTypeMonitor(),
);

final serverEndpointProbeProvider = Provider<ServerEndpointProbe>(
  (ref) => ref.watch(connectionRepositoryProvider).endpointProbe,
);

final endpointSelectionServiceProvider = Provider<EndpointSelectionService>((
  ref,
) {
  return EndpointSelectionService(
    probe: ref.watch(serverEndpointProbeProvider),
    connections: ref.watch(connectionRepositoryProvider),
  );
});

final audioPortProvider = Provider<AudioPort>((ref) => SilentAudioPort());

final trackPlaybackStateStoreProvider = Provider<TrackPlaybackStateStore>(
  (ref) => SharedTrackPlaybackStateStore(),
);

final appImageCacheProvider = Provider<AppImageCache?>((ref) => null);

final mediaCacheProvider = Provider<MediaCache?>((ref) => null);

final appMessageCenterProvider = Provider<AppMessageCenter>((ref) {
  final center = AppMessageCenter();
  ref.onDispose(center.dispose);
  return center;
});

final class ServiceSettingsUpdates extends ChangeNotifier {
  int revision = 0;

  void changed() {
    revision++;
    notifyListeners();
  }
}

final serviceSettingsUpdatesProvider = Provider<ServiceSettingsUpdates>((ref) {
  final updates = ServiceSettingsUpdates();
  ref.onDispose(updates.dispose);
  return updates;
});

final macOSMenuBarPortProvider = Provider<MacOSMenuBarPort>((ref) {
  final port = InactiveMacOSMenuBarPort();
  ref.onDispose(port.dispose);
  return port;
});
