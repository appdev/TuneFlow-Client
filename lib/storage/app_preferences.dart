import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { system, zh, en }

const bytesPerGiB = 1024 * 1024 * 1024;
const defaultMediaCacheLimitBytes = 5 * bytesPerGiB;
const mediaCacheLimitOptionsBytes = <int>[
  1 * bytesPerGiB,
  2 * bytesPerGiB,
  5 * bytesPerGiB,
  10 * bytesPerGiB,
  20 * bytesPerGiB,
];

enum PlaybackQuality {
  low128k('128k'),
  high320k('320k'),
  lossless('flac');

  const PlaybackQuality(this.apiValue);
  final String apiValue;
}

final class AppSettings {
  const AppSettings({
    this.origin,
    this.lastConnectedOrigin,
    this.lanOrigin,
    this.externalOrigin,
    this.themeMode = ThemeMode.system,
    this.language = AppLanguage.system,
    this.quality = PlaybackQuality.low128k,
    this.keepAwake = false,
    this.showLyrics = false,
    this.showTranslation = true,
    this.reduceTransparency = false,
    this.cacheLimitBytes = defaultMediaCacheLimitBytes,
  });

  final String? origin;
  final String? lastConnectedOrigin;
  final String? lanOrigin;
  final String? externalOrigin;
  final ThemeMode themeMode;
  final AppLanguage language;
  final PlaybackQuality quality;
  final bool keepAwake;
  final bool showLyrics;
  final bool showTranslation;
  final bool reduceTransparency;
  final int cacheLimitBytes;

  AppSettings copyWith({
    String? origin,
    bool clearOrigin = false,
    String? lastConnectedOrigin,
    bool clearLastConnectedOrigin = false,
    String? lanOrigin,
    bool clearLanOrigin = false,
    String? externalOrigin,
    bool clearExternalOrigin = false,
    ThemeMode? themeMode,
    AppLanguage? language,
    PlaybackQuality? quality,
    bool? keepAwake,
    bool? showLyrics,
    bool? showTranslation,
    bool? reduceTransparency,
    int? cacheLimitBytes,
  }) => AppSettings(
    origin: clearOrigin ? null : origin ?? this.origin,
    lastConnectedOrigin: clearLastConnectedOrigin
        ? null
        : lastConnectedOrigin ?? this.lastConnectedOrigin,
    lanOrigin: clearLanOrigin ? null : lanOrigin ?? this.lanOrigin,
    externalOrigin: clearExternalOrigin
        ? null
        : externalOrigin ?? this.externalOrigin,
    themeMode: themeMode ?? this.themeMode,
    language: language ?? this.language,
    quality: quality ?? this.quality,
    keepAwake: keepAwake ?? this.keepAwake,
    showLyrics: showLyrics ?? this.showLyrics,
    showTranslation: showTranslation ?? this.showTranslation,
    reduceTransparency: reduceTransparency ?? this.reduceTransparency,
    cacheLimitBytes: cacheLimitBytes ?? this.cacheLimitBytes,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.origin == origin &&
      other.lastConnectedOrigin == lastConnectedOrigin &&
      other.lanOrigin == lanOrigin &&
      other.externalOrigin == externalOrigin &&
      other.themeMode == themeMode &&
      other.language == language &&
      other.quality == quality &&
      other.keepAwake == keepAwake &&
      other.showLyrics == showLyrics &&
      other.showTranslation == showTranslation &&
      other.reduceTransparency == reduceTransparency &&
      other.cacheLimitBytes == cacheLimitBytes;

  @override
  int get hashCode => Object.hash(
    origin,
    lastConnectedOrigin,
    lanOrigin,
    externalOrigin,
    themeMode,
    language,
    quality,
    keepAwake,
    showLyrics,
    showTranslation,
    reduceTransparency,
    cacheLimitBytes,
  );
}

abstract interface class AppPreferences {
  Future<AppSettings> read();
  Future<void> write(AppSettings settings);
  Future<void> clearOrigin();
}

final class SharedAppPreferences implements AppPreferences {
  SharedAppPreferences([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _originKey = 'service_origin';
  static const _lastConnectedOriginKey = 'service_last_connected_origin';
  static const _lanOriginKey = 'service_lan_origin';
  static const _externalOriginKey = 'service_external_origin';
  static const _themeModeKey = 'theme_mode';
  static const _languageKey = 'language';
  static const _qualityKey = 'playback_quality';
  static const _keepAwakeKey = 'keep_awake';
  static const _showLyricsKey = 'show_lyrics';
  static const _showTranslationKey = 'show_translation';
  static const _reduceTransparencyKey = 'reduce_transparency';
  static const _cacheLimitKey = 'media_cache_limit_bytes';

  final SharedPreferencesAsync _preferences;

  @override
  Future<AppSettings> read() async {
    final origin = await _preferences.getString(_originKey);
    return AppSettings(
      origin: origin,
      lastConnectedOrigin:
          await _preferences.getString(_lastConnectedOriginKey) ?? origin,
      lanOrigin: await _preferences.getString(_lanOriginKey),
      externalOrigin: await _preferences.getString(_externalOriginKey),
      themeMode: _enumValue(
        ThemeMode.values,
        await _preferences.getString(_themeModeKey),
        ThemeMode.system,
      ),
      language: _enumValue(
        AppLanguage.values,
        await _preferences.getString(_languageKey),
        AppLanguage.system,
      ),
      quality: _enumValue(
        PlaybackQuality.values,
        await _preferences.getString(_qualityKey),
        PlaybackQuality.low128k,
      ),
      keepAwake: await _preferences.getBool(_keepAwakeKey) ?? false,
      showLyrics: await _preferences.getBool(_showLyricsKey) ?? false,
      showTranslation: await _preferences.getBool(_showTranslationKey) ?? true,
      reduceTransparency:
          await _preferences.getBool(_reduceTransparencyKey) ?? false,
      cacheLimitBytes: _cacheLimitOrDefault(
        await _preferences.getInt(_cacheLimitKey),
      ),
    );
  }

  @override
  Future<void> write(AppSettings settings) async {
    await _writeNullableString(_originKey, settings.origin);
    await _writeNullableString(
      _lastConnectedOriginKey,
      settings.lastConnectedOrigin,
    );
    await _writeNullableString(_lanOriginKey, settings.lanOrigin);
    await _writeNullableString(_externalOriginKey, settings.externalOrigin);
    await _preferences.setString(_themeModeKey, settings.themeMode.name);
    await _preferences.setString(_languageKey, settings.language.name);
    await _preferences.setString(_qualityKey, settings.quality.name);
    await _preferences.setBool(_keepAwakeKey, settings.keepAwake);
    await _preferences.setBool(_showLyricsKey, settings.showLyrics);
    await _preferences.setBool(_showTranslationKey, settings.showTranslation);
    await _preferences.setBool(
      _reduceTransparencyKey,
      settings.reduceTransparency,
    );
    await _preferences.setInt(_cacheLimitKey, settings.cacheLimitBytes);
  }

  @override
  Future<void> clearOrigin() async {
    await Future.wait([
      _preferences.remove(_originKey),
      _preferences.remove(_lastConnectedOriginKey),
      _preferences.remove(_lanOriginKey),
      _preferences.remove(_externalOriginKey),
    ]);
  }

  Future<void> _writeNullableString(String key, String? value) async {
    if (value == null) {
      await _preferences.remove(key);
    } else {
      await _preferences.setString(key, value);
    }
  }
}

int _cacheLimitOrDefault(int? value) =>
    mediaCacheLimitOptionsBytes.contains(value)
    ? value!
    : defaultMediaCacheLimitBytes;

T _enumValue<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
