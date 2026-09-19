import '../../api/models.dart';
import '../../api/service_exception.dart';
import '../recommendations/recommendation_models.dart';

enum RadioMode { dedicated, queueContinuation }

enum RadioBatchStatus { active, degraded }

enum RadioAiStatus { enhanced, profileOnly, local, disabled, unavailable }

enum RadioRankingSource {
  ai,
  aiProfileLocalRank,
  local,
  dailyFallback,
  familiarFallback,
}

const radioBatchSize = 10;

final class RadioItem {
  const RadioItem({
    required this.recommendationItemId,
    required this.radioSessionId,
    required this.canonicalTrackId,
    required this.track,
    required this.rankingSource,
    required this.reason,
  });

  factory RadioItem.fromJson(Object? value) {
    final json = jsonObject(value, 'radio.item');
    return RadioItem(
      recommendationItemId: jsonString(
        json['recommendationItemId'],
        'radio.item.recommendationItemId',
      ),
      radioSessionId: jsonString(
        json['radioSessionId'],
        'radio.item.radioSessionId',
      ),
      canonicalTrackId: jsonString(
        json['canonicalTrackId'],
        'radio.item.canonicalTrackId',
      ),
      track: Track.fromJson(json['track']),
      rankingSource: switch (jsonString(
        json['rankingSource'],
        'radio.item.rankingSource',
      )) {
        'ai' => RadioRankingSource.ai,
        'ai_profile_local_rank' => RadioRankingSource.aiProfileLocalRank,
        'local' => RadioRankingSource.local,
        'daily_fallback' => RadioRankingSource.dailyFallback,
        'familiar_fallback' => RadioRankingSource.familiarFallback,
        _ => throw const ServiceException(
          'INVALID_RESPONSE',
          'Service returned an invalid radio ranking source.',
        ),
      },
      reason: RecommendationReason.fromJson(json['reason']),
    );
  }

  final String recommendationItemId;
  final String radioSessionId;
  final String canonicalTrackId;
  final Track track;
  final RadioRankingSource rankingSource;
  final RecommendationReason reason;
}

final class RadioBatch {
  const RadioBatch({
    required this.sessionId,
    required this.mode,
    required this.status,
    required this.aiStatus,
    required this.items,
    this.profileId,
  });

  factory RadioBatch.fromJson(Object? value) {
    final json = jsonObject(value, 'radio.batch');
    final sessionId = jsonString(json['sessionId'], 'radio.sessionId');
    final items = jsonList(
      json['items'],
      'radio.items',
    ).map(RadioItem.fromJson).toList(growable: false);
    if (items.length > radioBatchSize ||
        items.any((item) => item.radioSessionId != sessionId) ||
        items.map((item) => item.recommendationItemId).toSet().length !=
            items.length) {
      throw const ServiceException(
        'INVALID_RESPONSE',
        'Service returned an invalid radio batch.',
      );
    }
    final profileId = json['profileId'];
    if (profileId != null && profileId is! String) {
      throw const ServiceException(
        'INVALID_RESPONSE',
        'Service returned an invalid radio profile id.',
      );
    }
    return RadioBatch(
      sessionId: sessionId,
      mode: switch (jsonString(json['mode'], 'radio.mode')) {
        'dedicated' => RadioMode.dedicated,
        'queue_continuation' => RadioMode.queueContinuation,
        _ => throw const ServiceException(
          'INVALID_RESPONSE',
          'Service returned an invalid radio mode.',
        ),
      },
      status: switch (jsonString(json['status'], 'radio.status')) {
        'active' => RadioBatchStatus.active,
        'degraded' => RadioBatchStatus.degraded,
        _ => throw const ServiceException(
          'INVALID_RESPONSE',
          'Service returned an invalid radio status.',
        ),
      },
      aiStatus: parseRadioAiStatus(
        jsonString(json['aiStatus'], 'radio.aiStatus'),
      ),
      profileId: profileId as String?,
      items: items,
    );
  }

  final String sessionId;
  final RadioMode mode;
  final RadioBatchStatus status;
  final RadioAiStatus aiStatus;
  final String? profileId;
  final List<RadioItem> items;
}

RadioAiStatus parseRadioAiStatus(String value) => switch (value) {
  'enhanced' => RadioAiStatus.enhanced,
  'profile_only' => RadioAiStatus.profileOnly,
  'local' => RadioAiStatus.local,
  'disabled' => RadioAiStatus.disabled,
  'unavailable' => RadioAiStatus.unavailable,
  _ => throw const ServiceException(
    'INVALID_RESPONSE',
    'Service returned an invalid AI status.',
  ),
};

final class RadioAiServiceStatus {
  const RadioAiServiceStatus({
    required this.enabled,
    required this.configured,
    required this.healthy,
    required this.profileSource,
    this.profileId,
    this.generatedAt,
    this.lastErrorCode,
  });

  factory RadioAiServiceStatus.fromJson(Object? value) {
    final json = jsonObject(value, 'radio.aiStatus');
    final enabled = json['enabled'];
    final configured = json['configured'];
    final healthy = json['healthy'];
    if (enabled is! bool || configured is! bool || healthy is! bool) {
      throw const ServiceException(
        'INVALID_RESPONSE',
        'Service returned an invalid AI status.',
      );
    }
    final generatedAt = json['generatedAt'];
    return RadioAiServiceStatus(
      enabled: enabled,
      configured: configured,
      healthy: healthy,
      profileSource: jsonString(json['profileSource'], 'radio.profileSource'),
      profileId: json['profileId'] == null
          ? null
          : jsonString(json['profileId'], 'radio.profileId'),
      generatedAt: generatedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((generatedAt as num).toInt()),
      lastErrorCode: json['lastErrorCode'] == null
          ? null
          : jsonString(json['lastErrorCode'], 'radio.lastErrorCode'),
    );
  }

  final bool enabled;
  final bool configured;
  final bool healthy;
  final String profileSource;
  final String? profileId;
  final DateTime? generatedAt;
  final String? lastErrorCode;
}
