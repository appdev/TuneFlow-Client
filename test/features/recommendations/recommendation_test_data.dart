Map<String, Object?> recommendationSnapshotJson({
  String status = 'ready',
  int? version = 1,
  int count = 2,
  int? interestedIndex,
}) => {
  'status': status,
  'localDate': '2026-08-30',
  'snapshotLocalDate': status == 'stale' ? '2026-08-29' : '2026-08-30',
  'version': version,
  'generatedAt': 1772323200000,
  'lastErrorCode': status == 'stale' ? 'musicbrainz_timeout' : null,
  'sourceCoverage': ['kw', 'tx'],
  'items': [
    for (var index = 0; index < count; index++)
      {
        'recommendationItemId': 'recommendation-$index',
        'canonicalTrackId': 'canonical-$index',
        'track': {
          'id': 'track-$index',
          'source': index.isEven ? 'kw' : 'tx',
          'name': 'Track $index',
          'singer': index.isEven ? 'Artist A' : 'Artist B',
        },
        'bucket': index.isEven ? 'new' : 'familiar',
        'reason': {
          'type': index.isEven ? 'exploration' : 'familiar_replay',
          'labels': index.isEven ? ['流行'] : <String>[],
        },
        'feedback': {
          'interested': index == interestedIndex,
          'interestedFeedbackId': index == interestedIndex
              ? 'interested-$index'
              : null,
        },
      },
  ],
};
