import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../player/player_controller.dart';
import '../player/player_state.dart';
import 'radio_models.dart';
import 'radio_preferences.dart';
import 'radio_repository.dart';

final class RadioState {
  const RadioState({
    this.session,
    this.loading = false,
    this.autoContinuation = false,
    this.error,
  });
  final RadioBatch? session;
  final bool loading;
  final bool autoContinuation;
  final Object? error;

  RadioState copyWith({
    Object? session = _unchanged,
    bool? loading,
    bool? autoContinuation,
    Object? error = _unchanged,
  }) => RadioState(
    session: identical(session, _unchanged)
        ? this.session
        : session as RadioBatch?,
    loading: loading ?? this.loading,
    autoContinuation: autoContinuation ?? this.autoContinuation,
    error: identical(error, _unchanged) ? this.error : error,
  );
}

final class RadioController extends ChangeNotifier {
  RadioController({
    required this.repository,
    required this.player,
    RadioPreferences? preferences,
    DateTime Function()? clock,
  }) : preferences = preferences ?? RadioPreferences(),
       _clock = clock ?? DateTime.now {
    player.setSequentialQueueEndHandler(_continueAtQueueEnd);
    player.addListener(_handlePlayerChange);
    unawaited(_loadPreference());
  }

  final RadioSessionPort repository;
  final PlayerController player;
  final RadioPreferences preferences;
  final DateTime Function() _clock;
  DateTime? _prefetchRetryAfter;
  RadioState state = const RadioState();
  int _queueGeneration = 0;
  int _requestGeneration = 0;
  Future<bool>? _continuationRequest;
  bool _disposed = false;
  bool _closing = false;

  String _requestId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<void> _loadPreference() async {
    final value = await preferences.readAutoContinuation();
    if (_disposed) return;
    state = state.copyWith(autoContinuation: value);
    notifyListeners();
    _maybePrefetch();
  }

  Future<void> setAutoContinuation(bool value) async {
    state = state.copyWith(autoContinuation: value, error: null);
    notifyListeners();
    try {
      await preferences.writeAutoContinuation(value);
      _maybePrefetch();
    } on Object catch (error) {
      if (_disposed) return;
      state = state.copyWith(autoContinuation: !value, error: error);
      notifyListeners();
    }
  }

  Future<bool> startDedicated() async {
    if (_disposed || _closing || state.loading) return false;
    final previousSessionId = state.session?.sessionId;
    final generation = ++_requestGeneration;
    _prefetchRetryAfter = null;
    state = state.copyWith(session: null, loading: true, error: null);
    notifyListeners();
    try {
      await _closeSession(previousSessionId);
      final batch = await repository.create(
        mode: RadioMode.dedicated,
        queueGeneration: ++_queueGeneration,
        requestId: _requestId(),
        currentTrack: player.state.current,
        queuedTracks: player.state.queue.take(100).toList(growable: false),
      );
      if (!_isCurrent(generation)) {
        await _closeSession(batch.sessionId);
        return false;
      }
      if (batch.items.isEmpty) {
        await _closeSession(batch.sessionId);
        throw StateError('暂时没有可播放的推荐歌曲。');
      }
      state = state.copyWith(session: batch, loading: false, error: null);
      notifyListeners();
      try {
        await player.playTracks(
          batch.items.map((item) => item.track).toList(growable: false),
          contexts: _contexts(batch),
          queueKind: PlayerQueueKind.dedicatedRadio,
        );
      } on Object catch (error) {
        if (_isCurrent(generation)) {
          await _closeSession(batch.sessionId);
          state = state.copyWith(session: null, loading: false, error: error);
          notifyListeners();
        }
        return false;
      }
      return true;
    } on Object catch (error) {
      if (!_isCurrent(generation)) return false;
      state = state.copyWith(loading: false, error: error);
      notifyListeners();
      return false;
    }
  }

  Future<void> stop() async {
    if (_closing) return;
    _closing = true;
    _requestGeneration++;
    final sessionId = state.session?.sessionId;
    if (!_disposed) {
      state = state.copyWith(session: null, loading: false, error: null);
      notifyListeners();
    }
    await _closeSession(sessionId);
    _closing = false;
  }

  List<PlaybackContext> _contexts(RadioBatch batch) => batch.items
      .map(
        (item) => PlaybackContext(
          recommendationItemId: item.recommendationItemId,
          radioSessionId: batch.sessionId,
        ),
      )
      .toList(growable: false);

  Future<bool> _continueAtQueueEnd() async {
    final pending = _continuationRequest;
    if (pending != null) return pending;
    if (!_canContinue()) return false;
    return _startContinuationRequest();
  }

  bool _canContinue() {
    if (_disposed ||
        _closing ||
        state.loading ||
        player.state.playbackMode != PlaybackMode.sequential ||
        player.state.currentIndex < 0) {
      return false;
    }
    final radioQueue =
        player.state.queueKind == PlayerQueueKind.dedicatedRadio ||
        player.state.queueKind == PlayerQueueKind.radioContinuation;
    return (radioQueue && state.session != null) || state.autoContinuation;
  }

  int get _remainingTracks =>
      player.state.queue.length - player.state.currentIndex - 1;

  void _maybePrefetch() {
    if (_continuationRequest != null || !_canContinue()) return;
    final retryAfter = _prefetchRetryAfter;
    if (retryAfter != null && _clock().isBefore(retryAfter)) return;
    if (_remainingTracks <= 2) unawaited(_startContinuationRequest());
  }

  Future<bool> _startContinuationRequest() {
    final pending = _continuationRequest;
    if (pending != null) return pending;
    final generation = _requestGeneration;
    final queueFingerprint = _queueFingerprint();
    final request = _fetchContinuation(generation, queueFingerprint);
    _continuationRequest = request;
    return request.whenComplete(() {
      if (identical(_continuationRequest, request)) {
        _continuationRequest = null;
      }
    });
  }

  Future<bool> _fetchContinuation(
    int generation,
    String queueFingerprint,
  ) async {
    final active = state.session;
    final radioQueue =
        player.state.queueKind == PlayerQueueKind.dedicatedRadio ||
        player.state.queueKind == PlayerQueueKind.radioContinuation;
    state = state.copyWith(loading: true, error: null);
    notifyListeners();
    try {
      final batch = active == null
          ? await repository.create(
              mode: RadioMode.queueContinuation,
              queueGeneration: ++_queueGeneration,
              requestId: _requestId(),
              currentTrack: player.state.current,
              queuedTracks: player.state.queue
                  .skip(player.state.currentIndex + 1)
                  .take(100)
                  .toList(growable: false),
            )
          : await repository.next(
              sessionId: active.sessionId,
              queueGeneration: ++_queueGeneration,
              requestId: _requestId(),
              currentTrack: player.state.current,
              queuedTracks: player.state.queue
                  .skip(player.state.currentIndex + 1)
                  .take(100)
                  .toList(growable: false),
            );
      if (!_isCurrent(generation) ||
          queueFingerprint != _queueFingerprint() ||
          (!radioQueue && !state.autoContinuation) ||
          player.state.playbackMode != PlaybackMode.sequential) {
        if (active == null) await _closeSession(batch.sessionId);
        if (_isCurrent(generation)) {
          state = state.copyWith(loading: false);
          notifyListeners();
        }
        return false;
      }
      if (batch.items.isEmpty) {
        _prefetchRetryAfter = _clock().add(const Duration(seconds: 30));
        if (active == null) await _closeSession(batch.sessionId);
        if (!_isCurrent(generation)) return false;
        state = state.copyWith(
          session: active == null ? null : batch,
          loading: false,
        );
        notifyListeners();
        return false;
      }
      _prefetchRetryAfter = null;
      state = state.copyWith(session: batch, loading: false, error: null);
      player.enqueueTracks(
        batch.items.map((item) => item.track).toList(growable: false),
        contexts: _contexts(batch),
        queueKind: active == null && !radioQueue
            ? PlayerQueueKind.radioContinuation
            : player.state.queueKind,
      );
      notifyListeners();
      return true;
    } on Object catch (error) {
      if (!_isCurrent(generation)) return false;
      _prefetchRetryAfter = _clock().add(const Duration(seconds: 30));
      state = state.copyWith(loading: false, error: error);
      notifyListeners();
      return false;
    }
  }

  void _handlePlayerChange() {
    if (_disposed || _closing) return;
    if (player.state.queue.isEmpty &&
        (state.session != null || _continuationRequest != null)) {
      unawaited(stop());
      return;
    }
    if (state.session != null &&
        player.state.queueKind == PlayerQueueKind.manual) {
      unawaited(stop());
      return;
    }
    _maybePrefetch();
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _requestGeneration;

  String _queueFingerprint() => player.state.queue
      .map(
        (track) =>
            '${track.source.length}:${track.source}${track.id.length}:${track.id}',
      )
      .join('|');

  Future<void> _closeSession(String? sessionId) async {
    if (sessionId == null) return;
    try {
      await repository.close(sessionId);
    } on Object {
      /* Session close is best-effort. */
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _requestGeneration++;
    player.setSequentialQueueEndHandler(null);
    player.removeListener(_handlePlayerChange);
    final sessionId = state.session?.sessionId;
    if (sessionId != null) unawaited(_closeSession(sessionId));
    super.dispose();
  }
}

const _unchanged = Object();
