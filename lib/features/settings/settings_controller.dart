import 'package:flutter/material.dart';

import '../../api/service_origin.dart';
import '../../storage/app_image_cache.dart';
import '../../storage/app_preferences.dart';
import '../../storage/media_cache.dart';
import '../connection/connection_repository.dart';

typedef SaveSettings = Future<void> Function(AppSettings settings);
typedef LoadAutoDownloadOnPlay = Future<bool> Function();
typedef UpdateAutoDownloadOnPlay = Future<bool> Function(bool value);

final class SettingsController extends ChangeNotifier {
  SettingsController({
    required AppSettings settings,
    required SaveSettings save,
    required Future<void> Function(String origin) connect,
    required Future<void> Function() disconnect,
    required Future<void> Function(String quality) setPlayerQuality,
    Future<ConnectionDiagnostics> Function(String origin)? diagnostics,
    MediaCache? mediaCache,
    AppImageCache? imageCache,
    LoadAutoDownloadOnPlay? loadAutoDownloadOnPlay,
    UpdateAutoDownloadOnPlay? updateAutoDownloadOnPlay,
  }) : state = settings,
       _save = save,
       _connect = connect,
       _disconnect = disconnect,
       _setPlayerQuality = setPlayerQuality,
       _diagnostics = diagnostics,
       _mediaCache = mediaCache,
       _imageCache = imageCache,
       _loadAutoDownloadOnPlay = loadAutoDownloadOnPlay,
       _updateAutoDownloadOnPlay = updateAutoDownloadOnPlay {
    cacheUsage =
        mediaCache?.usage.value ??
        MediaCacheUsage(audioBytes: 0, limitBytes: settings.cacheLimitBytes);
    imageCacheBytes = imageCache?.usageBytes.value ?? 0;
    mediaCache?.usage.addListener(_cacheUsageChanged);
    imageCache?.usageBytes.addListener(_imageCacheUsageChanged);
  }

  final SaveSettings _save;
  final Future<void> Function(String origin) _connect;
  final Future<void> Function() _disconnect;
  final Future<void> Function(String quality) _setPlayerQuality;
  final Future<ConnectionDiagnostics> Function(String origin)? _diagnostics;
  final MediaCache? _mediaCache;
  final AppImageCache? _imageCache;
  final LoadAutoDownloadOnPlay? _loadAutoDownloadOnPlay;
  final UpdateAutoDownloadOnPlay? _updateAutoDownloadOnPlay;
  AppSettings state;
  ConnectionDiagnostics? connection;
  bool diagnosticsLoading = false;
  Object? diagnosticsError;
  late MediaCacheUsage cacheUsage;
  late int imageCacheBytes;
  bool cacheBusy = false;
  Object? cacheError;
  bool? autoDownloadOnPlay;
  bool serviceSettingsBusy = false;
  Object? serviceSettingsError;
  bool _disposed = false;

  bool get serviceSettingsAvailable =>
      _loadAutoDownloadOnPlay != null && _updateAutoDownloadOnPlay != null;

  Future<void> refreshServiceSettings() async {
    final load = _loadAutoDownloadOnPlay;
    if (load == null || serviceSettingsBusy) return;
    serviceSettingsBusy = true;
    serviceSettingsError = null;
    autoDownloadOnPlay = null;
    _notifyIfActive();
    try {
      final value = await load();
      if (!_disposed) autoDownloadOnPlay = value;
    } on Object catch (error) {
      if (!_disposed) serviceSettingsError = error;
    } finally {
      serviceSettingsBusy = false;
      _notifyIfActive();
    }
  }

  Future<void> setAutoDownloadOnPlay(bool value) async {
    final update = _updateAutoDownloadOnPlay;
    final previous = autoDownloadOnPlay;
    if (update == null ||
        serviceSettingsBusy ||
        previous == null ||
        previous == value) {
      return;
    }
    serviceSettingsBusy = true;
    serviceSettingsError = null;
    _notifyIfActive();
    try {
      final confirmed = await update(value);
      if (!_disposed) autoDownloadOnPlay = confirmed;
    } on Object catch (error) {
      if (!_disposed) {
        autoDownloadOnPlay = previous;
        serviceSettingsError = error;
      }
    } finally {
      serviceSettingsBusy = false;
      _notifyIfActive();
    }
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _persist(AppSettings next) async {
    await _save(next);
    state = next;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) =>
      _persist(state.copyWith(themeMode: value));
  Future<void> setLanguage(AppLanguage value) =>
      _persist(state.copyWith(language: value));

  Future<void> setQuality(PlaybackQuality value) async {
    await _setPlayerQuality(value.apiValue);
    await _persist(state.copyWith(quality: value));
  }

  Future<void> setKeepAwake(bool value) =>
      _persist(state.copyWith(keepAwake: value));
  Future<void> setShowLyrics(bool value) =>
      _persist(state.copyWith(showLyrics: value));
  Future<void> setShowTranslation(bool value) =>
      _persist(state.copyWith(showTranslation: value));
  Future<void> setReduceTransparency(bool value) =>
      _persist(state.copyWith(reduceTransparency: value));

  void syncSettings(AppSettings settings) {
    if (settings == state) return;
    state = settings;
    notifyListeners();
  }

  Future<void> setCacheLimit(int bytes) async {
    if (!mediaCacheLimitOptionsBytes.contains(bytes)) {
      throw ArgumentError.value(bytes, 'bytes', 'Unsupported cache limit');
    }
    if (cacheBusy || bytes == state.cacheLimitBytes) return;
    final previous = state;
    final next = state.copyWith(cacheLimitBytes: bytes);
    cacheBusy = true;
    cacheError = null;
    notifyListeners();
    try {
      await _mediaCache?.setLimit(bytes);
      try {
        await _save(next);
      } on Object {
        await _mediaCache?.setLimit(previous.cacheLimitBytes);
        rethrow;
      }
      state = next;
    } on Object catch (error) {
      cacheError = error;
      rethrow;
    } finally {
      cacheBusy = false;
      notifyListeners();
    }
  }

  Future<void> refreshCacheUsage() async {
    if (cacheBusy) return;
    cacheBusy = true;
    cacheError = null;
    _notifyIfActive();
    Object? firstError;

    Future<void> attempt(Future<void> Function()? action) async {
      if (action == null) return;
      try {
        await action();
      } on Object catch (error) {
        firstError ??= error;
      }
    }

    try {
      await attempt(_mediaCache?.reconcile);
      await attempt(_imageCache?.refreshUsage);
      if (!_disposed) cacheError = firstError;
    } finally {
      cacheBusy = false;
      _notifyIfActive();
    }
  }

  Future<void> clearLocalCache() async {
    if (cacheBusy) return;
    final mediaCache = _mediaCache;
    final imageCache = _imageCache;
    if (mediaCache == null && imageCache == null) {
      throw StateError('Local caches are unavailable');
    }
    cacheBusy = true;
    cacheError = null;
    notifyListeners();
    try {
      Object? firstError;
      StackTrace? firstStackTrace;

      Future<void> attempt(Future<void> Function()? action) async {
        if (action == null) return;
        try {
          await action();
        } on Object catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }

      await attempt(mediaCache?.clearLocal);
      await attempt(imageCache?.clear);
      if (firstError case final error?) {
        Error.throwWithStackTrace(error, firstStackTrace!);
      }
    } on Object catch (error) {
      cacheError = error;
      rethrow;
    } finally {
      cacheBusy = false;
      notifyListeners();
    }
  }

  void _cacheUsageChanged() {
    final cache = _mediaCache;
    if (cache == null) return;
    cacheUsage = cache.usage.value;
    _notifyIfActive();
  }

  void _imageCacheUsageChanged() {
    final cache = _imageCache;
    if (cache == null) return;
    imageCacheBytes = cache.usageBytes.value;
    _notifyIfActive();
  }

  Future<void> replaceOrigin(String rawOrigin) async {
    final origin = ServiceOrigin.parse(rawOrigin).uri.toString();
    await _connect(origin);
    state = state.copyWith(origin: origin);
    notifyListeners();
    await refreshDiagnostics();
  }

  Future<void> refreshDiagnostics() async {
    final origin = state.origin;
    final probe = _diagnostics;
    if (origin == null || probe == null) return;
    diagnosticsLoading = true;
    diagnosticsError = null;
    notifyListeners();
    try {
      connection = await probe(origin);
    } on Object catch (error) {
      diagnosticsError = error;
    } finally {
      diagnosticsLoading = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() => _disconnect();

  @override
  void dispose() {
    _disposed = true;
    _mediaCache?.usage.removeListener(_cacheUsageChanged);
    _imageCache?.usageBytes.removeListener(_imageCacheUsageChanged);
    super.dispose();
  }
}
