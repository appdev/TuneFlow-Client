import '../../api/service_api.dart';
import '../../api/service_exception.dart';

const _autoDownloadOnPlayKey = 'player.autoDownloadOnPlay';
const _lanOriginKey = 'service.lanOrigin';
const _externalOriginKey = 'service.externalOrigin';
const officialMusicBrainzBaseUrl = 'https://musicbrainz.org/ws/2/';

final class ServiceFunctionSettings {
  const ServiceFunctionSettings({
    required this.autoDownloadOnPlay,
    required this.downloadEnabled,
    required this.groupByPlaylist,
    required this.fileName,
    required this.maxConcurrent,
    required this.skipExisting,
    required this.useOtherSource,
    required this.downloadLyrics,
    required this.downloadTranslatedLyrics,
    required this.downloadRomanizedLyrics,
    required this.downloadVerbatimLyrics,
    required this.lyricEncoding,
    required this.embedPicture,
    required this.embedLyrics,
    required this.embedTranslatedLyrics,
    required this.embedRomanizedLyrics,
    required this.embedVerbatimLyrics,
    required this.recommendationTimeZone,
    this.musicBrainzBaseUrl = officialMusicBrainzBaseUrl,
    this.recommendationAiEnabled = false,
    this.recommendationAiBaseUrl = '',
    this.recommendationAiModel = '',
  });

  factory ServiceFunctionSettings.fromJson(Object? value) {
    if (value is! Map) {
      throw const ServiceException(
        'INVALID_RESPONSE',
        'Service settings response is invalid.',
      );
    }
    final json = Map<String, Object?>.from(value);
    bool boolean(String key) {
      final result = json[key];
      if (result is bool) return result;
      throw ServiceException(
        'INVALID_RESPONSE',
        'Service settings response is missing $key.',
      );
    }

    String string(String key) {
      final result = json[key];
      if (result is String) return result;
      throw ServiceException(
        'INVALID_RESPONSE',
        'Service settings response is missing $key.',
      );
    }

    int integer(String key) {
      final result = json[key];
      if (result is int) return result;
      throw ServiceException(
        'INVALID_RESPONSE',
        'Service settings response is missing $key.',
      );
    }

    return ServiceFunctionSettings(
      autoDownloadOnPlay: boolean('player.autoDownloadOnPlay'),
      downloadEnabled: boolean('download.enable'),
      groupByPlaylist: boolean('download.isSavePathGroupByListName'),
      fileName: string('download.fileName'),
      maxConcurrent: integer('download.maxDownloadNum'),
      skipExisting: boolean('download.skipExistFile'),
      useOtherSource: boolean('download.isUseOtherSource'),
      downloadLyrics: boolean('download.isDownloadLrc'),
      downloadTranslatedLyrics: boolean('download.isDownloadTLrc'),
      downloadRomanizedLyrics: boolean('download.isDownloadRLrc'),
      downloadVerbatimLyrics: boolean('download.isDownloadVerbatimLyric'),
      lyricEncoding: string('download.lrcFormat'),
      embedPicture: boolean('download.isEmbedPic'),
      embedLyrics: boolean('download.isEmbedLyric'),
      embedTranslatedLyrics: boolean('download.isEmbedLyricT'),
      embedRomanizedLyrics: boolean('download.isEmbedLyricR'),
      embedVerbatimLyrics: boolean('download.isEmbedVerbatimLyric'),
      recommendationTimeZone: string('recommendation.timeZone'),
      musicBrainzBaseUrl: json.containsKey('recommendation.musicBrainzBaseUrl')
          ? string('recommendation.musicBrainzBaseUrl')
          : officialMusicBrainzBaseUrl,
      recommendationAiEnabled: json.containsKey('recommendation.ai.enabled')
          ? boolean('recommendation.ai.enabled')
          : false,
      recommendationAiBaseUrl: json.containsKey('recommendation.ai.baseUrl')
          ? string('recommendation.ai.baseUrl')
          : '',
      recommendationAiModel: json.containsKey('recommendation.ai.model')
          ? string('recommendation.ai.model')
          : '',
    );
  }

  final bool autoDownloadOnPlay;
  final bool downloadEnabled;
  final bool groupByPlaylist;
  final String fileName;
  final int maxConcurrent;
  final bool skipExisting;
  final bool useOtherSource;
  final bool downloadLyrics;
  final bool downloadTranslatedLyrics;
  final bool downloadRomanizedLyrics;
  final bool downloadVerbatimLyrics;
  final String lyricEncoding;
  final bool embedPicture;
  final bool embedLyrics;
  final bool embedTranslatedLyrics;
  final bool embedRomanizedLyrics;
  final bool embedVerbatimLyrics;
  final String recommendationTimeZone;
  final String musicBrainzBaseUrl;
  final bool recommendationAiEnabled;
  final String recommendationAiBaseUrl;
  final String recommendationAiModel;

  ServiceFunctionSettings copyWith({
    bool? autoDownloadOnPlay,
    bool? downloadEnabled,
    bool? groupByPlaylist,
    String? fileName,
    int? maxConcurrent,
    bool? skipExisting,
    bool? useOtherSource,
    bool? downloadLyrics,
    bool? downloadTranslatedLyrics,
    bool? downloadRomanizedLyrics,
    bool? downloadVerbatimLyrics,
    String? lyricEncoding,
    bool? embedPicture,
    bool? embedLyrics,
    bool? embedTranslatedLyrics,
    bool? embedRomanizedLyrics,
    bool? embedVerbatimLyrics,
    String? recommendationTimeZone,
    String? musicBrainzBaseUrl,
    bool? recommendationAiEnabled,
    String? recommendationAiBaseUrl,
    String? recommendationAiModel,
  }) => ServiceFunctionSettings(
    autoDownloadOnPlay: autoDownloadOnPlay ?? this.autoDownloadOnPlay,
    downloadEnabled: downloadEnabled ?? this.downloadEnabled,
    groupByPlaylist: groupByPlaylist ?? this.groupByPlaylist,
    fileName: fileName ?? this.fileName,
    maxConcurrent: maxConcurrent ?? this.maxConcurrent,
    skipExisting: skipExisting ?? this.skipExisting,
    useOtherSource: useOtherSource ?? this.useOtherSource,
    downloadLyrics: downloadLyrics ?? this.downloadLyrics,
    downloadTranslatedLyrics:
        downloadTranslatedLyrics ?? this.downloadTranslatedLyrics,
    downloadRomanizedLyrics:
        downloadRomanizedLyrics ?? this.downloadRomanizedLyrics,
    downloadVerbatimLyrics:
        downloadVerbatimLyrics ?? this.downloadVerbatimLyrics,
    lyricEncoding: lyricEncoding ?? this.lyricEncoding,
    embedPicture: embedPicture ?? this.embedPicture,
    embedLyrics: embedLyrics ?? this.embedLyrics,
    embedTranslatedLyrics: embedTranslatedLyrics ?? this.embedTranslatedLyrics,
    embedRomanizedLyrics: embedRomanizedLyrics ?? this.embedRomanizedLyrics,
    embedVerbatimLyrics: embedVerbatimLyrics ?? this.embedVerbatimLyrics,
    recommendationTimeZone:
        recommendationTimeZone ?? this.recommendationTimeZone,
    musicBrainzBaseUrl: musicBrainzBaseUrl ?? this.musicBrainzBaseUrl,
    recommendationAiEnabled:
        recommendationAiEnabled ?? this.recommendationAiEnabled,
    recommendationAiBaseUrl:
        recommendationAiBaseUrl ?? this.recommendationAiBaseUrl,
    recommendationAiModel: recommendationAiModel ?? this.recommendationAiModel,
  );

  Map<String, Object?> toPatch() => {
    'player.autoDownloadOnPlay': autoDownloadOnPlay,
    'download.enable': downloadEnabled,
    'download.isSavePathGroupByListName': groupByPlaylist,
    'download.fileName': fileName,
    'download.maxDownloadNum': maxConcurrent,
    'download.skipExistFile': skipExisting,
    'download.isUseOtherSource': useOtherSource,
    'download.isDownloadLrc': downloadLyrics,
    'download.isDownloadTLrc': downloadTranslatedLyrics,
    'download.isDownloadRLrc': downloadRomanizedLyrics,
    'download.isDownloadVerbatimLyric': downloadVerbatimLyrics,
    'download.lrcFormat': lyricEncoding,
    'download.isEmbedPic': embedPicture,
    'download.isEmbedLyric': embedLyrics,
    'download.isEmbedLyricT': embedTranslatedLyrics,
    'download.isEmbedLyricR': embedRomanizedLyrics,
    'download.isEmbedVerbatimLyric': embedVerbatimLyrics,
    'recommendation.timeZone': recommendationTimeZone,
    'recommendation.musicBrainzBaseUrl': musicBrainzBaseUrl,
    'recommendation.ai.enabled': recommendationAiEnabled,
    'recommendation.ai.baseUrl': recommendationAiBaseUrl,
    'recommendation.ai.model': recommendationAiModel,
  };

  Map<String, Object?> changesFrom(ServiceFunctionSettings previous) {
    final before = previous.toPatch();
    return Map.fromEntries(
      toPatch().entries.where((entry) => before[entry.key] != entry.value),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ServiceFunctionSettings &&
      _mapsEqual(toPatch(), other.toPatch());

  @override
  int get hashCode => Object.hashAll(
    toPatch().entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}

final class MusicBrainzConnectionTestResult {
  const MusicBrainzConnectionTestResult({
    required this.ok,
    required this.normalizedBaseUrl,
    required this.errorCode,
  });

  factory MusicBrainzConnectionTestResult.fromJson(Object? value) {
    if (value is! Map) {
      throw const ServiceException(
        'INVALID_RESPONSE',
        'MusicBrainz connection test response is invalid.',
      );
    }
    final json = Map<String, Object?>.from(value);
    final ok = json['ok'];
    final normalizedBaseUrl = json['normalizedBaseUrl'];
    final errorCode = json['errorCode'];
    if (ok is! bool ||
        normalizedBaseUrl is! String ||
        (errorCode != null && errorCode is! String)) {
      throw const ServiceException(
        'INVALID_RESPONSE',
        'MusicBrainz connection test response is invalid.',
      );
    }
    return MusicBrainzConnectionTestResult(
      ok: ok,
      normalizedBaseUrl: normalizedBaseUrl,
      errorCode: errorCode as String?,
    );
  }

  final bool ok;
  final String normalizedBaseUrl;
  final String? errorCode;
}

final class AiConnectionTestResult {
  const AiConnectionTestResult({required this.ok, this.errorCode});

  factory AiConnectionTestResult.fromJson(Object? value) {
    if (value is! Map ||
        value['ok'] is! bool ||
        (value['errorCode'] != null && value['errorCode'] is! String)) {
      throw const ServiceException(
        'INVALID_RESPONSE',
        'AI connection test response is invalid.',
      );
    }
    return AiConnectionTestResult(
      ok: value['ok']! as bool,
      errorCode: value['errorCode'] as String?,
    );
  }

  final bool ok;
  final String? errorCode;
}

bool _mapsEqual(Map<String, Object?> left, Map<String, Object?> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}

final class ServiceAccessOrigins {
  const ServiceAccessOrigins({
    required this.lanOrigin,
    required this.externalOrigin,
  });

  final String lanOrigin;
  final String externalOrigin;

  @override
  bool operator ==(Object other) =>
      other is ServiceAccessOrigins &&
      other.lanOrigin == lanOrigin &&
      other.externalOrigin == externalOrigin;

  @override
  int get hashCode => Object.hash(lanOrigin, externalOrigin);
}

final class ServiceSettingsRepository {
  const ServiceSettingsRepository(this.api);

  final ServiceApi api;

  Future<ServiceFunctionSettings> getFunctionSettings() async =>
      ServiceFunctionSettings.fromJson(
        await api.request('GET', '/api/v1/settings'),
      );

  Future<ServiceFunctionSettings> updateFunctionSettings(
    ServiceFunctionSettings value,
    ServiceFunctionSettings previous,
  ) async {
    final patch = value.changesFrom(previous);
    if (patch.isEmpty) return value;
    return ServiceFunctionSettings.fromJson(
      await api.request('PATCH', '/api/v1/settings', body: patch),
    );
  }

  Future<MusicBrainzConnectionTestResult> testMusicBrainzConnection(
    String baseUrl,
  ) async => MusicBrainzConnectionTestResult.fromJson(
    await api.request(
      'POST',
      '/api/v1/recommendations/musicbrainz/test',
      body: {'baseUrl': baseUrl},
    ),
  );

  Future<AiConnectionTestResult> testRecommendationAiConnection() async =>
      AiConnectionTestResult.fromJson(
        await api.request('POST', '/api/v1/recommendations/ai/test'),
      );

  Future<void> reanalyzeRecommendationAi() async {
    await api.request('POST', '/api/v1/recommendations/ai/reanalyze');
  }

  Future<bool> getAutoDownloadOnPlay() async =>
      _readBoolean(await api.request('GET', '/api/v1/settings'));

  Future<bool> setAutoDownloadOnPlay(bool value) async => _readBoolean(
    await api.request(
      'PATCH',
      '/api/v1/settings',
      body: {_autoDownloadOnPlayKey: value},
    ),
  );

  Future<ServiceAccessOrigins> getAccessOrigins() async =>
      _readAccessOrigins(await api.request('GET', '/api/v1/settings'));

  Future<ServiceAccessOrigins> updateAccessOrigins(
    ServiceAccessOrigins value,
  ) async => _readAccessOrigins(
    await api.request(
      'PATCH',
      '/api/v1/settings',
      body: {
        _lanOriginKey: value.lanOrigin,
        _externalOriginKey: value.externalOrigin,
      },
    ),
  );

  bool _readBoolean(Object? value) {
    if (value case final Map data) {
      final setting = data[_autoDownloadOnPlayKey];
      if (setting is bool) return setting;
    }
    throw const ServiceException(
      'INVALID_RESPONSE',
      'Service settings response is missing player.autoDownloadOnPlay.',
    );
  }

  ServiceAccessOrigins _readAccessOrigins(Object? value) {
    if (value case final Map data) {
      final lanOrigin = data[_lanOriginKey];
      final externalOrigin = data[_externalOriginKey];
      if (lanOrigin is String && externalOrigin is String) {
        return ServiceAccessOrigins(
          lanOrigin: lanOrigin,
          externalOrigin: externalOrigin,
        );
      }
    }
    throw const ServiceException(
      'INVALID_RESPONSE',
      'Service settings response is missing access origins.',
    );
  }
}
