import 'dart:io';

import 'package:audio_service/audio_service.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'features/player/notification_artwork.dart';
import 'features/player/service_audio_handler.dart';
import 'platform/app_platform.dart';
import 'platform/desktop_window_bootstrap.dart';
import 'storage/app_image_cache.dart';
import 'storage/app_preferences.dart';
import 'storage/media_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    debugPrint('Local media cache unavailable: $error');
    mediaCache = null;
  }
  AppImageCache? imageCache;
  CeAppImageCache? imageCacheCandidate;
  try {
    final appCache = await getApplicationCacheDirectory();
    imageCacheCandidate = CeAppImageCache(
      cacheBaseDirectory: Directory(
        '${appCache.path}${Platform.pathSeparator}image-cache',
      ),
      metadataBaseDirectory: Directory(
        '${support.path}${Platform.pathSeparator}image-cache-metadata',
      ),
    );
    await imageCacheCandidate.refreshUsage();
    imageCache = imageCacheCandidate;
  } on Object catch (error) {
    debugPrint('Primary local image cache unavailable: $error');
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
      debugPrint('Fallback local image cache unavailable: $fallbackError');
      await imageCacheCandidate?.dispose();
      imageCacheCandidate = null;
    }
  }
  final languageCode = PlatformDispatcher.instance.locale.languageCode;
  final playbackChannelName = languageCode == 'zh'
      ? '音流播放'
      : 'TuneFlow Playback';
  final audio = await AudioService.init<ServiceAudioHandler>(
    builder: () => ServiceAudioHandler(
      fallbackArtUri: notificationPlaceholder,
      cache: mediaCache,
    ),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.musicfree.serviceclient.playback',
      androidNotificationChannelName: playbackChannelName,
      androidNotificationOngoing: true,
    ),
  );
  runApp(
    MusicFreeServiceApp(
      preferences: preferences,
      audio: audio,
      mediaCache: mediaCache,
      imageCache: imageCache,
    ),
  );
}
