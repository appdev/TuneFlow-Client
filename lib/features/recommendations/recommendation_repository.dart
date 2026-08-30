import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../api/service_api.dart';
import 'recommendation_models.dart';

abstract interface class RecommendationCache {
  Future<DailyRecommendations?> read();
  Future<void> write(DailyRecommendations value);
  Future<void> clear();
}

final class SharedRecommendationCache implements RecommendationCache {
  SharedRecommendationCache({
    required Uri serviceOrigin,
    SharedPreferencesAsync? preferences,
  }) : _serviceOrigin = serviceOrigin.toString(),
       _preferences = preferences ?? _tryPreferences();

  static const _key = 'daily_recommendations_snapshot_v1';

  final String _serviceOrigin;
  final SharedPreferencesAsync? _preferences;
  DailyRecommendations? _memory;

  @override
  Future<DailyRecommendations?> read() async {
    final preferences = _preferences;
    if (preferences == null) return _memory;
    final encoded = await preferences.getString(_key);
    if (encoded == null) return null;
    try {
      final wrapper = jsonDecode(encoded);
      if (wrapper is! Map || wrapper['serviceOrigin'] != _serviceOrigin) {
        return null;
      }
      final snapshot = DailyRecommendations.fromJson(wrapper['snapshot']);
      return snapshot.isComplete ? snapshot : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(DailyRecommendations value) async {
    if (!value.isComplete) return;
    _memory = value;
    await _preferences?.setString(
      _key,
      jsonEncode({'serviceOrigin': _serviceOrigin, 'snapshot': value.toJson()}),
    );
  }

  @override
  Future<void> clear() async {
    _memory = null;
    await _preferences?.remove(_key);
  }
}

SharedPreferencesAsync? _tryPreferences() {
  try {
    return SharedPreferencesAsync();
  } on StateError {
    return null;
  }
}

final class RecommendationRepository {
  const RecommendationRepository(this.api);

  final ServiceApi api;

  Future<DailyRecommendations> daily() async => DailyRecommendations.fromJson(
    await api.request('GET', '/api/v1/recommendations/daily'),
  );

  Future<void> refresh() async {
    await api.request('POST', '/api/v1/recommendations/daily/refresh');
  }

  Future<RecommendationFeedbackResult> dislikeTrack(
    RecommendationItem item,
  ) async => RecommendationFeedbackResult.fromJson(
    await api.request(
      'POST',
      '/api/v1/recommendations/feedback',
      body: {'type': 'not_interested_track', 'track': item.track.toJson()},
    ),
  );

  Future<RecommendationFeedbackResult> interestTrack(
    RecommendationItem item,
  ) async => RecommendationFeedbackResult.fromJson(
    await api.request(
      'POST',
      '/api/v1/recommendations/feedback',
      body: {'type': 'interested_track', 'track': item.track.toJson()},
    ),
  );

  Future<RecommendationFeedbackResult> dislikeArtist(String artist) async =>
      RecommendationFeedbackResult.fromJson(
        await api.request(
          'POST',
          '/api/v1/recommendations/feedback',
          body: {'type': 'not_interested_artist', 'artist': artist},
        ),
      );

  Future<RecommendationFeedbackResult> undo(String feedbackId) async =>
      RecommendationFeedbackResult.fromJson(
        await api.request(
          'POST',
          '/api/v1/recommendations/feedback',
          body: {'type': 'undo', 'feedbackId': feedbackId},
        ),
      );
}
