import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/storage/app_preferences.dart';
import 'package:musicfree_service_client/features/settings/settings_controller.dart';
import 'package:musicfree_service_client/features/settings/service_settings_repository.dart';
import 'package:musicfree_service_client/features/connection/connection_repository.dart';
import 'package:musicfree_service_client/features/connection/network_type_monitor.dart';
import 'package:musicfree_service_client/storage/media_cache.dart';

import '../../support/fake_media_cache.dart';
import '../../support/fake_app_image_cache.dart';
import '../../support/test_image_cache_manager.dart';

SettingsController controllerForServiceSettings({
  required Future<bool> Function() load,
  required Future<bool> Function(bool value) update,
}) => SettingsController(
  settings: const AppSettings(),
  save: (_) async {},
  connect: (_) async {},
  disconnect: () async {},
  setPlayerQuality: (_) async {},
  loadAutoDownloadOnPlay: load,
  updateAutoDownloadOnPlay: update,
);

void main() {
  test(
    'failed endpoint apply restores shared origins and stays connected',
    () async {
      const previous = ServiceAccessOrigins(
        lanOrigin: 'http://old-lan.local',
        externalOrigin: 'https://old-external.example',
      );
      final updates = <ServiceAccessOrigins>[];
      final controller = SettingsController(
        settings: const AppSettings(origin: 'https://bootstrap.example'),
        save: (_) async {},
        connect: (_) async {},
        disconnect: () async {},
        setPlayerQuality: (_) async {},
        loadServiceAccessOrigins: () async => previous,
        updateServiceAccessOrigins: (value) async {
          updates.add(value);
          return value;
        },
        applyServiceEndpoints:
            ({
              required bootstrapOrigin,
              required lanOrigin,
              required externalOrigin,
            }) async {
              throw StateError('probe failed');
            },
      );

      await expectLater(
        controller.saveConnectionSettings(
          lanOrigin: 'http://new-lan.local/',
          externalOrigin: 'https://new-external.example/',
        ),
        throwsStateError,
      );

      expect(updates, [
        const ServiceAccessOrigins(
          lanOrigin: 'http://new-lan.local',
          externalOrigin: 'https://new-external.example',
        ),
        previous,
      ]);
      expect(controller.state.origin, 'https://bootstrap.example');
      expect(controller.connectionSettingsError, isA<StateError>());
    },
  );

  test('uncertain shared PATCH restores freshly loaded origins', () async {
    const cached = ServiceAccessOrigins(
      lanOrigin: 'http://cached-lan.local',
      externalOrigin: 'https://cached-external.example',
    );
    const fresh = ServiceAccessOrigins(
      lanOrigin: 'http://fresh-lan.local',
      externalOrigin: 'https://fresh-external.example',
    );
    var current = cached;
    final updates = <ServiceAccessOrigins>[];
    final controller = SettingsController(
      settings: const AppSettings(origin: 'https://bootstrap.example'),
      save: (_) async {},
      connect: (_) async {},
      disconnect: () async {},
      setPlayerQuality: (_) async {},
      loadServiceAccessOrigins: () async => current,
      updateServiceAccessOrigins: (value) async {
        updates.add(value);
        if (updates.length == 1) throw StateError('response lost');
        return value;
      },
      applyServiceEndpoints:
          ({
            required bootstrapOrigin,
            required lanOrigin,
            required externalOrigin,
          }) async {},
    );
    await controller.refreshServiceSettings();
    current = fresh;

    await expectLater(
      controller.saveConnectionSettings(
        lanOrigin: 'http://new-lan.local',
        externalOrigin: 'https://new-external.example',
      ),
      throwsStateError,
    );

    expect(updates.last, fresh);
  });

  test(
    'updates every approved preference and delegates connection intents',
    () async {
      var saved = const AppSettings(origin: 'http://old.local');
      final connections = <String>[];
      var disconnects = 0;
      final qualities = <String>[];
      final controller = SettingsController(
        settings: saved,
        save: (value) async => saved = value,
        connect: (origin) async => connections.add(origin),
        disconnect: () async => disconnects++,
        setPlayerQuality: (quality) async => qualities.add(quality),
      );

      await controller.setThemeMode(ThemeMode.dark);
      await controller.setLanguage(AppLanguage.en);
      await controller.setQuality(PlaybackQuality.high320k);
      await controller.setKeepAwake(true);
      await controller.setShowLyrics(true);
      await controller.setReduceTransparency(true);
      await controller.replaceOrigin('http://new.local/');
      await controller.disconnect();

      expect(saved.themeMode, ThemeMode.dark);
      expect(saved.language, AppLanguage.en);
      expect(saved.quality, PlaybackQuality.high320k);
      expect(saved.keepAwake, isTrue);
      expect(saved.showLyrics, isTrue);
      expect(saved.reduceTransparency, isTrue);
      expect(qualities, ['320k']);
      expect(connections, ['http://new.local']);
      expect(disconnects, 1);
    },
  );

  test('syncs live connection diagnostics without probing', () {
    final controller = SettingsController(
      settings: const AppSettings(origin: 'http://service.local'),
      save: (_) async {},
      connect: (_) async {},
      disconnect: () async {},
      setPlayerQuality: (_) async {},
    );
    final diagnostics = ConnectionDiagnostics(
      origin: 'http://192.168.1.20:3124',
      connected: true,
      latency: const Duration(milliseconds: 12),
      apiVersion: 'v1',
      networkRoute: NetworkRoute.lan,
      endpointRole: EndpointRole.lan,
      checkedAt: DateTime.fromMillisecondsSinceEpoch(1),
    );

    controller.syncConnection(diagnostics);

    expect(controller.connection, same(diagnostics));
  });

  test(
    'updates the local cache limit and persists the device setting',
    () async {
      var saved = const AppSettings();
      final cache = FakeMediaCache();
      final controller = SettingsController(
        settings: saved,
        save: (value) async => saved = value,
        connect: (_) async {},
        disconnect: () async {},
        setPlayerQuality: (_) async {},
        mediaCache: cache,
      );

      await controller.setCacheLimit(10 * bytesPerGiB);

      expect(saved.cacheLimitBytes, 10 * bytesPerGiB);
      expect(cache.setLimits, [10 * bytesPerGiB]);
      expect(controller.cacheUsage.limitBytes, 10 * bytesPerGiB);
      expect(controller.cacheBusy, isFalse);
    },
  );

  test('reports and clears audio and image caches independently', () async {
    final cache = FakeMediaCache(
      usage: const MediaCacheUsage(
        audioBytes: 12,
        limitBytes: defaultMediaCacheLimitBytes,
      ),
    );
    final images = FakeAppImageCache(
      manager: TestImageCacheManager(),
      usageBytes: 5,
    );
    final controller = SettingsController(
      settings: const AppSettings(),
      save: (_) async {},
      connect: (_) async {},
      disconnect: () async {},
      setPlayerQuality: (_) async {},
      mediaCache: cache,
      imageCache: images,
    );

    expect(controller.cacheUsage.audioBytes, 12);
    expect(controller.imageCacheBytes, 5);

    await controller.clearLocalCache();

    expect(cache.clearCalls, 1);
    expect(images.clearCalls, 1);
    expect(controller.cacheUsage.totalBytes, 0);
    expect(controller.imageCacheBytes, 0);
  });

  test('a failed audio clear still attempts the image cache', () async {
    final cache = FakeMediaCache(
      usage: const MediaCacheUsage(
        audioBytes: 12,
        limitBytes: defaultMediaCacheLimitBytes,
      ),
    )..error = StateError('audio clear failed');
    final images = FakeAppImageCache(
      manager: TestImageCacheManager(),
      usageBytes: 5,
    );
    final controller = SettingsController(
      settings: const AppSettings(),
      save: (_) async {},
      connect: (_) async {},
      disconnect: () async {},
      setPlayerQuality: (_) async {},
      mediaCache: cache,
      imageCache: images,
    );

    await expectLater(controller.clearLocalCache(), throwsStateError);

    expect(cache.clearCalls, 1);
    expect(images.clearCalls, 1);
    expect(controller.imageCacheBytes, 0);
    expect(controller.cacheError, isA<StateError>());
  });

  test('refreshes current audio and image cache usage', () async {
    final cache = FakeMediaCache();
    final images = FakeAppImageCache(manager: TestImageCacheManager());
    final controller = SettingsController(
      settings: const AppSettings(),
      save: (_) async {},
      connect: (_) async {},
      disconnect: () async {},
      setPlayerQuality: (_) async {},
      mediaCache: cache,
      imageCache: images,
    );

    await controller.refreshCacheUsage();

    expect(cache.reconcileCalls, 1);
    expect(images.refreshCalls, 1);
  });

  test('accepts settings changed by another app controller', () {
    final controller = SettingsController(
      settings: const AppSettings(),
      save: (_) async {},
      connect: (_) async {},
      disconnect: () async {},
      setPlayerQuality: (_) async {},
    );

    controller.syncSettings(
      const AppSettings(
        themeMode: ThemeMode.dark,
        cacheLimitBytes: 10 * bytesPerGiB,
      ),
    );

    expect(controller.state.themeMode, ThemeMode.dark);
    expect(controller.state.cacheLimitBytes, 10 * bytesPerGiB);
  });

  test('loads and updates the shared Service auto-download setting', () async {
    var serviceValue = true;
    final updates = <bool>[];
    final controller = controllerForServiceSettings(
      load: () async => serviceValue,
      update: (value) async {
        updates.add(value);
        serviceValue = value;
        return serviceValue;
      },
    );

    await controller.refreshServiceSettings();
    expect(controller.autoDownloadOnPlay, isTrue);

    await controller.setAutoDownloadOnPlay(false);

    expect(updates, [false]);
    expect(controller.autoDownloadOnPlay, isFalse);
    expect(controller.serviceSettingsError, isNull);
  });

  test('a failed Service setting load keeps the value unknown', () async {
    final controller = controllerForServiceSettings(
      load: () async => throw StateError('offline'),
      update: (value) async => value,
    );

    await controller.refreshServiceSettings();

    expect(controller.autoDownloadOnPlay, isNull);
    expect(controller.serviceSettingsError, isA<StateError>());
    expect(controller.serviceSettingsBusy, isFalse);
  });

  test(
    'a failed Service setting update preserves the confirmed value',
    () async {
      final controller = controllerForServiceSettings(
        load: () async => true,
        update: (_) async => throw StateError('write failed'),
      );
      await controller.refreshServiceSettings();

      await controller.setAutoDownloadOnPlay(false);

      expect(controller.autoDownloadOnPlay, isTrue);
      expect(controller.serviceSettingsError, isA<StateError>());
      expect(controller.serviceSettingsBusy, isFalse);
    },
  );

  test('suppresses concurrent Service setting updates', () async {
    final pending = Completer<bool>();
    var updates = 0;
    final controller = controllerForServiceSettings(
      load: () async => false,
      update: (_) {
        updates++;
        return pending.future;
      },
    );
    await controller.refreshServiceSettings();

    final first = controller.setAutoDownloadOnPlay(true);
    final second = controller.setAutoDownloadOnPlay(true);
    expect(controller.serviceSettingsBusy, isTrue);
    expect(updates, 1);
    pending.complete(true);
    await Future.wait([first, second]);

    expect(controller.autoDownloadOnPlay, isTrue);
    expect(controller.serviceSettingsBusy, isFalse);
  });

  test(
    'reports Service settings unavailable without injected operations',
    () async {
      final controller = SettingsController(
        settings: const AppSettings(),
        save: (_) async {},
        connect: (_) async {},
        disconnect: () async {},
        setPlayerQuality: (_) async {},
      );

      await controller.refreshServiceSettings();
      await controller.setAutoDownloadOnPlay(true);

      expect(controller.serviceSettingsAvailable, isFalse);
      expect(controller.autoDownloadOnPlay, isNull);
      expect(controller.serviceSettingsBusy, isFalse);
    },
  );
}
