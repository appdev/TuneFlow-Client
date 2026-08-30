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
  }) : preferences = preferences ?? RadioPreferences() {
    player.setSequentialQueueEndHandler(_continueAtQueueEnd);
    player.addListener(_handlePlayerChange);
    unawaited(_loadPreference());
  }

  final RadioSessionPort repository;
  final PlayerController player;
  final RadioPreferences preferences;
  RadioState state = const RadioState();
  int _queueGeneration = 0;
  bool _disposed = false;
  bool _closing = false;

  String _requestId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<void> _loadPreference() async {
    final value = await preferences.readAutoContinuation();
    if (_disposed) return;
    state = state.copyWith(autoContinuation: value);
    notifyListeners();
  }

  Future<void> setAutoContinuation(bool value) async {
    state = state.copyWith(autoContinuation: value, error: null);
    notifyListeners();
    try {
      await preferences.writeAutoContinuation(value);
    } on Object catch (error) {
      if (_disposed) return;
      state = state.copyWith(autoContinuation: !value, error: error);
      notifyListeners();
    }
  }

  Future<bool> startDedicated() async {
    if (state.loading) return false;
    state = state.copyWith(loading: true, error: null);
    notifyListeners();
    try {
      await _closeActive();
      final batch = await repository.create(
        mode: RadioMode.dedicated,
        queueGeneration: ++_queueGeneration,
        requestId: _requestId(),
        currentTrack: player.state.current,
        queuedTracks: player.state.queue,
      );
      if (batch.items.isEmpty) throw StateError('暂时没有可播放的推荐歌曲。');
      state = state.copyWith(session: batch, loading: false, error: null);
      notifyListeners();
      await player.playTracks(
        batch.items.map((item) => item.track).toList(growable: false),
        contexts: _contexts(batch),
        queueKind: PlayerQueueKind.dedicatedRadio,
      );
      return true;
    } on Object catch (error) {
      state = state.copyWith(loading: false, error: error);
      notifyListeners();
      return false;
    }
  }

  Future<void> stop() async {
    if (_closing) return;
    _closing = true;
    await _closeActive();
    if (!_disposed) {
      state = state.copyWith(session: null, loading: false, error: null);
      notifyListeners();
    }
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
    if (_disposed ||
        state.loading ||
        player.state.playbackMode != PlaybackMode.sequential) {
      return false;
    }
    final active = state.session;
    final dedicated =
        player.state.queueKind == PlayerQueueKind.dedicatedRadio ||
        player.state.queueKind == PlayerQueueKind.radioContinuation;
    if (!dedicated && !state.autoContinuation) return false;
    state = state.copyWith(loading: true, error: null);
    notifyListeners();
    try {
      final batch = active == null
          ? await repository.create(
              mode: RadioMode.queueContinuation,
              queueGeneration: ++_queueGeneration,
              requestId: _requestId(),
              currentTrack: player.state.current,
              queuedTracks: const [],
            )
          : await repository.next(
              sessionId: active.sessionId,
              queueGeneration: ++_queueGeneration,
              requestId: _requestId(),
              currentTrack: player.state.current,
              queuedTracks: const [],
            );
      if (batch.items.isEmpty) {
        state = state.copyWith(session: batch, loading: false);
        notifyListeners();
        return false;
      }
      state = state.copyWith(session: batch, loading: false, error: null);
      player.enqueueTracks(
        batch.items.map((item) => item.track).toList(growable: false),
        contexts: _contexts(batch),
        queueKind: active == null && !dedicated
            ? PlayerQueueKind.radioContinuation
            : player.state.queueKind,
      );
      notifyListeners();
      return true;
    } on Object catch (error) {
      state = state.copyWith(loading: false, error: error);
      notifyListeners();
      return false;
    }
  }

  void _handlePlayerChange() {
    if (state.session == null || state.loading || _closing) return;
    if (player.state.queueKind == PlayerQueueKind.manual ||
        player.state.queue.isEmpty) {
      unawaited(stop());
    }
  }

  Future<void> _closeActive() async {
    final sessionId = state.session?.sessionId;
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
    player.setSequentialQueueEndHandler(null);
    player.removeListener(_handlePlayerChange);
    final sessionId = state.session?.sessionId;
    if (sessionId != null) unawaited(repository.close(sessionId));
    super.dispose();
  }
}

const _unchanged = Object();
