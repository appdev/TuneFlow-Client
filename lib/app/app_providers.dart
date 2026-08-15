import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_message_center.dart';
import '../features/connection/connection_repository.dart';
import '../features/player/service_audio_handler.dart';
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

final audioPortProvider = Provider<AudioPort>((ref) => SilentAudioPort());

final appImageCacheProvider = Provider<AppImageCache?>((ref) => null);

final mediaCacheProvider = Provider<MediaCache?>((ref) => null);

final appMessageCenterProvider = Provider<AppMessageCenter>((ref) {
  final center = AppMessageCenter();
  ref.onDispose(center.dispose);
  return center;
});

final macOSMenuBarPortProvider = Provider<MacOSMenuBarPort>((ref) {
  final port = InactiveMacOSMenuBarPort();
  ref.onDispose(port.dispose);
  return port;
});
