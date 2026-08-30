import 'package:flutter/foundation.dart';

import 'recommendation_models.dart';
import 'recommendation_repository.dart';

enum RecommendationFeedbackOperation { interested, negative }

final class RecommendationState {
  const RecommendationState({
    this.snapshot,
    this.loading = false,
    this.refreshing = false,
    this.cached = false,
    this.feedbackItemId,
    this.feedbackOperation,
    this.error,
  });

  final DailyRecommendations? snapshot;
  final bool loading;
  final bool refreshing;
  final bool cached;
  final String? feedbackItemId;
  final RecommendationFeedbackOperation? feedbackOperation;
  final Object? error;

  RecommendationState copyWith({
    DailyRecommendations? snapshot,
    bool? loading,
    bool? refreshing,
    bool? cached,
    String? feedbackItemId,
    RecommendationFeedbackOperation? feedbackOperation,
    bool clearFeedbackItem = false,
    Object? error,
    bool clearError = false,
  }) => RecommendationState(
    snapshot: snapshot ?? this.snapshot,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    cached: cached ?? this.cached,
    feedbackItemId: clearFeedbackItem
        ? null
        : feedbackItemId ?? this.feedbackItemId,
    feedbackOperation: clearFeedbackItem
        ? null
        : feedbackOperation ?? this.feedbackOperation,
    error: clearError ? null : error ?? this.error,
  );
}

final class RecommendationController extends ChangeNotifier {
  RecommendationController({required this.repository, required this.cache});

  final RecommendationRepository repository;
  final RecommendationCache cache;
  RecommendationState state = const RecommendationState();
  bool _disposed = false;

  Future<void> load() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, clearError: true);
    _notify();
    if (state.snapshot == null) {
      final cached = await cache.read();
      if (cached != null && !_disposed) {
        state = state.copyWith(snapshot: cached, cached: true);
        _notify();
      }
    }
    try {
      final snapshot = await repository.daily();
      if (_disposed) return;
      await _adoptRemote(snapshot);
    } on Object catch (error) {
      if (_disposed) return;
      state = state.copyWith(loading: false, error: error);
    }
    _notify();
  }

  Future<void> refresh() async {
    if (state.refreshing) return;
    state = state.copyWith(refreshing: true, clearError: true);
    _notify();
    try {
      await repository.refresh();
      final snapshot = await repository.daily();
      if (_disposed) return;
      await _adoptRemote(snapshot);
    } on Object catch (error) {
      if (_disposed) return;
      state = state.copyWith(refreshing: false, error: error);
      _notify();
    }
  }

  Future<void> _adoptRemote(DailyRecommendations snapshot) async {
    if (snapshot.status == RecommendationStatus.disabled) {
      await cache.clear();
      state = RecommendationState(snapshot: snapshot);
      return;
    }
    if (!snapshot.isComplete && state.snapshot?.isComplete == true) {
      state = state.copyWith(
        loading: false,
        refreshing: snapshot.status == RecommendationStatus.generating,
        clearError: true,
      );
      return;
    }
    state = state.copyWith(
      snapshot: snapshot,
      loading: false,
      refreshing: snapshot.status == RecommendationStatus.generating,
      cached: false,
      clearError: true,
    );
    if (snapshot.isComplete) await cache.write(snapshot);
  }

  Future<RecommendationFeedbackResult?> dislikeTrack(RecommendationItem item) =>
      _feedback(
        item,
        () => repository.dislikeTrack(item),
        remove: (candidate) => candidate.id == item.id,
      );

  Future<RecommendationFeedbackResult?> toggleInterest(
    RecommendationItem item,
  ) async {
    if (state.feedbackItemId != null) return null;
    state = state.copyWith(
      feedbackItemId: item.id,
      feedbackOperation: RecommendationFeedbackOperation.interested,
      clearError: true,
    );
    _notify();
    try {
      final current = item.feedback;
      final result = current.interested
          ? await repository.undo(current.interestedFeedbackId!)
          : await repository.interestTrack(item);
      if (_disposed) return result;
      final snapshot = state.snapshot;
      if (snapshot != null) {
        final interested = result.active;
        final updated = snapshot.copyWith(
          items: snapshot.items
              .map(
                (candidate) => candidate.id == item.id
                    ? candidate.copyWith(
                        feedback: RecommendationItemFeedback(
                          interested: interested,
                          interestedFeedbackId: interested ? result.id : null,
                        ),
                      )
                    : candidate,
              )
              .toList(growable: false),
        );
        state = state.copyWith(snapshot: updated, clearFeedbackItem: true);
        await cache.write(updated);
      } else {
        state = state.copyWith(clearFeedbackItem: true);
      }
      _notify();
      return result;
    } on Object catch (error) {
      if (!_disposed) {
        state = state.copyWith(error: error, clearFeedbackItem: true);
        _notify();
      }
      return null;
    }
  }

  Future<RecommendationFeedbackResult?> dislikeArtist(
    RecommendationItem item,
  ) => _feedback(
    item,
    () => repository.dislikeArtist(item.track.artist),
    remove: (candidate) => candidate.track.artist == item.track.artist,
  );

  Future<RecommendationFeedbackResult?> _feedback(
    RecommendationItem item,
    Future<RecommendationFeedbackResult> Function() request, {
    required bool Function(RecommendationItem) remove,
  }) async {
    if (state.feedbackItemId != null) return null;
    state = state.copyWith(
      feedbackItemId: item.id,
      feedbackOperation: RecommendationFeedbackOperation.negative,
      clearError: true,
    );
    _notify();
    try {
      final result = await request();
      if (_disposed) return result;
      final snapshot = state.snapshot;
      if (snapshot != null && result.active) {
        final updated = snapshot.copyWith(
          items: snapshot.items
              .where((candidate) => !remove(candidate))
              .toList(growable: false),
        );
        state = state.copyWith(snapshot: updated, clearFeedbackItem: true);
        await cache.write(updated);
      } else {
        state = state.copyWith(clearFeedbackItem: true);
      }
      _notify();
      return result;
    } on Object catch (error) {
      if (!_disposed) {
        state = state.copyWith(error: error, clearFeedbackItem: true);
        _notify();
      }
      return null;
    }
  }

  Future<bool> undo(RecommendationFeedbackResult feedback) async {
    try {
      final result = await repository.undo(feedback.id);
      return !result.active;
    } on Object catch (error) {
      if (!_disposed) {
        state = state.copyWith(error: error);
        _notify();
      }
      return false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
