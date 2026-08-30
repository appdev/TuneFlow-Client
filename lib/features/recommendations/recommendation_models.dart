import '../../api/models.dart';
import '../../api/service_exception.dart';

enum RecommendationStatus {
  warming,
  generating,
  ready,
  degraded,
  stale,
  disabled,
}

enum RecommendationBucket { newTrack, familiar }

enum RecommendationReasonType {
  playlistCooccurrence,
  artistAffinity,
  albumAffinity,
  tagAffinity,
  familiarReplay,
  exploration,
}

final class RecommendationReason {
  const RecommendationReason({
    required this.type,
    required this.labels,
    this.seedTrackName,
  });

  factory RecommendationReason.fromJson(Object? value) {
    final json = jsonObject(value, 'recommendation.reason');
    final rawType = jsonString(json['type'], 'recommendation.reason.type');
    final type = switch (rawType) {
      'playlist_cooccurrence' => RecommendationReasonType.playlistCooccurrence,
      'artist_affinity' => RecommendationReasonType.artistAffinity,
      'album_affinity' => RecommendationReasonType.albumAffinity,
      'tag_affinity' => RecommendationReasonType.tagAffinity,
      'familiar_replay' => RecommendationReasonType.familiarReplay,
      'exploration' => RecommendationReasonType.exploration,
      _ => throw ServiceException(
        'INVALID_RESPONSE',
        'Service response contains an invalid recommendation reason.',
        details: {'type': rawType},
      ),
    };
    final seedTrackName = json['seedTrackName'];
    if (seedTrackName != null && seedTrackName is! String) {
      throw const ServiceException(
        'INVALID_RESPONSE',
        'Service response contains an invalid recommendation seed track.',
      );
    }
    return RecommendationReason(
      type: type,
      seedTrackName: seedTrackName as String?,
      labels: jsonList(json['labels'], 'recommendation.reason.labels')
          .map((item) => jsonString(item, 'recommendation.reason.label'))
          .toList(growable: false),
    );
  }

  final RecommendationReasonType type;
  final String? seedTrackName;
  final List<String> labels;

  Map<String, Object?> toJson() => {
    'type': switch (type) {
      RecommendationReasonType.playlistCooccurrence => 'playlist_cooccurrence',
      RecommendationReasonType.artistAffinity => 'artist_affinity',
      RecommendationReasonType.albumAffinity => 'album_affinity',
      RecommendationReasonType.tagAffinity => 'tag_affinity',
      RecommendationReasonType.familiarReplay => 'familiar_replay',
      RecommendationReasonType.exploration => 'exploration',
    },
    if (seedTrackName != null) 'seedTrackName': seedTrackName,
    'labels': labels,
  };
}

final class RecommendationItem {
  const RecommendationItem({
    required this.id,
    required this.canonicalTrackId,
    required this.track,
    required this.bucket,
    required this.reason,
    this.feedback = const RecommendationItemFeedback(),
  });

  factory RecommendationItem.fromJson(Object? value) {
    final json = jsonObject(value, 'recommendation.item');
    final rawBucket = jsonString(json['bucket'], 'recommendation.item.bucket');
    return RecommendationItem(
      id: jsonString(json['recommendationItemId'], 'recommendation.item.id'),
      canonicalTrackId: jsonString(
        json['canonicalTrackId'],
        'recommendation.item.canonicalTrackId',
      ),
      track: Track.fromJson(json['track']),
      bucket: switch (rawBucket) {
        'new' => RecommendationBucket.newTrack,
        'familiar' => RecommendationBucket.familiar,
        _ => throw ServiceException(
          'INVALID_RESPONSE',
          'Service response contains an invalid recommendation bucket.',
          details: {'bucket': rawBucket},
        ),
      },
      reason: RecommendationReason.fromJson(json['reason']),
      feedback: json['feedback'] == null
          ? const RecommendationItemFeedback()
          : RecommendationItemFeedback.fromJson(json['feedback']),
    );
  }

  final String id;
  final String canonicalTrackId;
  final Track track;
  final RecommendationBucket bucket;
  final RecommendationReason reason;
  final RecommendationItemFeedback feedback;

  RecommendationItem copyWith({RecommendationItemFeedback? feedback}) =>
      RecommendationItem(
        id: id,
        canonicalTrackId: canonicalTrackId,
        track: track,
        bucket: bucket,
        reason: reason,
        feedback: feedback ?? this.feedback,
      );

  Map<String, Object?> toJson() => {
    'recommendationItemId': id,
    'canonicalTrackId': canonicalTrackId,
    'track': track.toJson(),
    'bucket': bucket == RecommendationBucket.newTrack ? 'new' : 'familiar',
    'reason': reason.toJson(),
    'feedback': feedback.toJson(),
  };
}

final class RecommendationItemFeedback {
  const RecommendationItemFeedback({
    this.interested = false,
    this.interestedFeedbackId,
  });

  factory RecommendationItemFeedback.fromJson(Object? value) {
    final json = jsonObject(value, 'recommendation.item.feedback');
    final interested = json['interested'];
    if (interested is! bool) {
      throw const ServiceException(
        'INVALID_RESPONSE',
        'Service response contains invalid recommendation feedback state.',
      );
    }
    final feedbackId = json['interestedFeedbackId'];
    if (feedbackId != null && feedbackId is! String) {
      throw const ServiceException(
        'INVALID_RESPONSE',
        'Service response contains an invalid recommendation feedback id.',
      );
    }
    if (interested && feedbackId == null) {
      throw const ServiceException(
        'INVALID_RESPONSE',
        'Interested recommendation feedback is missing its id.',
      );
    }
    return RecommendationItemFeedback(
      interested: interested,
      interestedFeedbackId: feedbackId as String?,
    );
  }

  final bool interested;
  final String? interestedFeedbackId;

  Map<String, Object?> toJson() => {
    'interested': interested,
    'interestedFeedbackId': interestedFeedbackId,
  };
}

final class DailyRecommendations {
  const DailyRecommendations({
    required this.status,
    required this.localDate,
    required this.sourceCoverage,
    required this.items,
    this.snapshotLocalDate,
    this.version,
    this.generatedAt,
    this.lastErrorCode,
  });

  factory DailyRecommendations.fromJson(Object? value) {
    final json = jsonObject(value, 'recommendations');
    final rawStatus = jsonString(json['status'], 'recommendations.status');
    final version = json['version'];
    final generatedAt = json['generatedAt'];
    if (version != null && version is! int) {
      throw const ServiceException(
        'INVALID_RESPONSE',
        'Service response contains an invalid recommendation version.',
      );
    }
    if (generatedAt != null && generatedAt is! num) {
      throw const ServiceException(
        'INVALID_RESPONSE',
        'Service response contains an invalid recommendation timestamp.',
      );
    }
    return DailyRecommendations(
      status: switch (rawStatus) {
        'warming' => RecommendationStatus.warming,
        'generating' => RecommendationStatus.generating,
        'ready' => RecommendationStatus.ready,
        'degraded' => RecommendationStatus.degraded,
        'stale' => RecommendationStatus.stale,
        'disabled' => RecommendationStatus.disabled,
        _ => throw ServiceException(
          'INVALID_RESPONSE',
          'Service response contains an invalid recommendation status.',
          details: {'status': rawStatus},
        ),
      },
      localDate: jsonString(json['localDate'], 'recommendations.localDate'),
      snapshotLocalDate: json['snapshotLocalDate'] == null
          ? null
          : jsonString(
              json['snapshotLocalDate'],
              'recommendations.snapshotLocalDate',
            ),
      version: version as int?,
      generatedAt: generatedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((generatedAt as num).toInt()),
      lastErrorCode: json['lastErrorCode'] == null
          ? null
          : jsonString(json['lastErrorCode'], 'recommendations.lastErrorCode'),
      sourceCoverage:
          jsonList(json['sourceCoverage'], 'recommendations.sourceCoverage')
              .map((item) => jsonString(item, 'recommendations.source'))
              .toList(growable: false),
      items: jsonList(
        json['items'],
        'recommendations.items',
      ).map(RecommendationItem.fromJson).toList(growable: false),
    );
  }

  final RecommendationStatus status;
  final String localDate;
  final String? snapshotLocalDate;
  final int? version;
  final DateTime? generatedAt;
  final String? lastErrorCode;
  final List<String> sourceCoverage;
  final List<RecommendationItem> items;

  bool get isComplete =>
      version != null &&
      (status == RecommendationStatus.ready ||
          status == RecommendationStatus.degraded ||
          status == RecommendationStatus.stale);

  DailyRecommendations copyWith({List<RecommendationItem>? items}) =>
      DailyRecommendations(
        status: status,
        localDate: localDate,
        snapshotLocalDate: snapshotLocalDate,
        version: version,
        generatedAt: generatedAt,
        lastErrorCode: lastErrorCode,
        sourceCoverage: sourceCoverage,
        items: items ?? this.items,
      );

  Map<String, Object?> toJson() => {
    'status': status.name,
    'localDate': localDate,
    'snapshotLocalDate': snapshotLocalDate,
    'version': version,
    'generatedAt': generatedAt?.millisecondsSinceEpoch,
    'lastErrorCode': lastErrorCode,
    'sourceCoverage': sourceCoverage,
    'items': items.map((item) => item.toJson()).toList(growable: false),
  };
}

final class RecommendationFeedbackResult {
  const RecommendationFeedbackResult({
    required this.id,
    required this.active,
    required this.type,
  });

  factory RecommendationFeedbackResult.fromJson(Object? value) {
    final json = jsonObject(value, 'recommendation.feedback');
    final active = json['active'];
    if (active is! bool) {
      throw const ServiceException(
        'INVALID_RESPONSE',
        'Service response contains an invalid recommendation feedback.',
      );
    }
    return RecommendationFeedbackResult(
      id: jsonString(json['feedbackId'], 'recommendation.feedback.id'),
      active: active,
      type: jsonString(json['type'], 'recommendation.feedback.type'),
    );
  }

  final String id;
  final bool active;
  final String type;
}
