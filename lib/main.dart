import 'dart:io';

import 'package:audio_service/audio_service.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'diagnostics/app_logger.dart';
import 'diagnostics/diagnostic_runtime.dart';
import 'features/player/notification_artwork.dart';
import 'features/player/service_audio_handler.dart';
import 'platform/app_platform.dart';
import 'platform/desktop_window_bootstrap.dart';
import 'platform/macos_menu_bar.dart';
import 'storage/app_image_cache.dart';
import 'storage/app_preferences.dart';
import 'storage/media_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    final diagnostics = DiagnosticRuntime(AppLogger.instance)..install();
    await diagnostics.openStore();
    AppLogger.instance.record(AppLogEvent.appStarted);
  }
  try {
    await _startApp();
  } on Object catch (error, stack) {
    AppLogger.instance.record(
      AppLogEvent.startupFailed,
      level: AppLogLevel.error,
      error: error,
      stackTrace: stack,
    );
    await AppLogger.instance.flush();
    rethrow;
  }
}

Future<void> _startApp() async {
  try {
    await LiquidGlassWidgets.initialize();
  } on Object catch (error) {
    AppLogger.instance.record(
      AppLogEvent.shaderUnavailable,
      level: AppLogLevel.warning,
      error: error,
    );
  }
  // Browsers use web audio and browser storage, never native directories or
  // window/menu channels. Keep this boundary before all native initialization.
  if (kIsWeb) {
    final audio = await initializeAudio(
      Uri.base.resolve('assets/assets/artwork/default_track_artwork.png'),
    );
    runApp(
      MusicFreeServiceApp(preferences: SharedAppPreferences(), audio: audio),
    );
    return;
  }
  final appPlatform = resolveAppPlatform(defaultTargetPlatform);
  await initializeDesktopWindow(appPlatform);
  final preferences = SharedAppPreferences();
  final settings = await preferences.read();
  final support = await getApplicationSupportDirectory();
  final notificationPlaceholder = await prepareNotificationPlaceholderArtwork(
    supportDirectory: support,
  );
  MediaCache? mediaCache;
  try {
    mediaCache = FileMediaCache(
      root: Directory('${support.path}${Platform.pathSeparator}media-cache'),
    );
    await mediaCache.initialize(limitBytes: settings.cacheLimitBytes);
  } on Object catch (error) {
    AppLogger.instance.record(
      AppLogEvent.mediaCacheUnavailable,
      level: AppLogLevel.warning,
      error: error,
    );
    mediaCache = null;
  }
  AppImageCache? imageCache;
  CeAppImageCache? imageCacheCandidate;
  final persistentImageDirectory = Directory(
    '${support.path}${Platform.pathSeparator}image-cache',
  );
  try {
    final appCache = await getApplicationCacheDirectory();
    await copyLegacyImageCacheIfNeeded(
      legacy: Directory('${appCache.path}${Platform.pathSeparator}image-cache'),
      persistent: persistentImageDirectory,
    );
  } on Object catch (error) {
    AppLogger.instance.record(
      AppLogEvent.imageCacheMigrationFailed,
      level: AppLogLevel.warning,
      error: error,
    );
  }
  try {
    imageCacheCandidate = CeAppImageCache(
      cacheBaseDirectory: persistentImageDirectory,
      metadataBaseDirectory: Directory(
        '${support.path}${Platform.pathSeparator}image-cache-metadata',
      ),
    );
    await imageCacheCandidate.refreshUsage();
    imageCache = imageCacheCandidate;
  } on Object catch (error) {
    AppLogger.instance.record(
      AppLogEvent.imageCacheUnavailable,
      level: AppLogLevel.warning,
      error: error,
    );
    await imageCacheCandidate?.dispose();
    imageCacheCandidate = null;
    try {
      imageCacheCandidate = CeAppImageCache(
        cacheBaseDirectory: Directory(
          '${support.path}${Platform.pathSeparator}image-cache-fallback',
        ),
        metadataBaseDirectory: Directory(
          '${support.path}${Platform.pathSeparator}'
          'image-cache-fallback-metadata',
        ),
      );
      await imageCacheCandidate.refreshUsage();
      imageCache = imageCacheCandidate;
    } on Object catch (fallbackError) {
      AppLogger.instance.record(
        AppLogEvent.imageCacheFallbackFailed,
        level: AppLogLevel.warning,
        error: fallbackError,
      );
      await imageCacheCandidate?.dispose();
      imageCacheCandidate = null;
    }
  }
  final audio = await initializeAudio(
    notificationPlaceholder,
    cache: mediaCache,
  );
  runApp(
    MusicFreeServiceApp(
      preferences: preferences,
      audio: audio,
      mediaCache: mediaCache,
      imageCache: imageCache,
      macOSMenuBar: Platform.isMacOS ? MethodChannelMacOSMenuBarPort() : null,
    ),
  );
}

Future<ServiceAudioHandler> initializeAudio(
  Uri notificationPlaceholder, {
  MediaCache? cache,
}) async {
  final languageCode = PlatformDispatcher.instance.locale.languageCode;
  final playbackChannelName = languageCode == 'zh'
      ? '音流播放'
      : 'TuneFlow Playback';
  return AudioService.init<ServiceAudioHandler>(
    builder: () => ServiceAudioHandler(
      fallbackArtUri: notificationPlaceholder,
      cache: cache,
    ),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.musicfree.serviceclient.playback',
      androidNotificationChannelName: playbackChannelName,
      androidNotificationOngoing: true,
    ),
  );
}
