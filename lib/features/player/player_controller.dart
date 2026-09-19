import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import '../../storage/app_preferences.dart';
import '../playback_history/playback_history_repository.dart';
import 'playback_repository.dart';
import 'player_state.dart';
import 'service_audio_handler.dart';
import 'track_playback_state_store.dart';

typedef _PlaybackTerminal = ({
  bool completed,
  Duration position,
  Duration duration,
});

final class _ActivePlaybackSession {
  String? playbackId;
  _PlaybackTerminal? terminal;
}

final class PlaybackContext {
  const PlaybackContext({this.recommendationItemId, this.radioSessionId});

  final String? recommendationItemId;
  final String? radioSessionId;
}

final class PlayerController extends ChangeNotifier {
  PlayerController({
    required this.resolver,
    required this.audio,
    String quality = '128k',
    bool showLyrics = false,
    bool showTranslation = true,
    bool showRomanization = false,
    LyricFontSize lyricFontSize = LyricFontSize.standard,
    LyricAlignment lyricAlignment = LyricAlignment.adaptive,
    LyricAuxiliaryOrder lyricAuxiliaryOrder =
        LyricAuxiliaryOrder.translationFirst,
    bool useTraditionalLyrics = false,
    bool emphasizeActiveLyric = true,
    bool rememberPlaybackProgress = false,
    bool autoSkipPlaybackErrors = false,
    TrackPlaybackStateStore? trackStateStore,
    void Function(Object error)? reportPersistenceError,
    PlaybackSessionPort? sessions,
  }) : state = PlayerState(
         quality: quality,
         showLyrics: showLyrics,
         showTranslation: showTranslation,
         showRomanization: showRomanization,
         lyricFontSize: lyricFontSize,
         lyricAlignment: lyricAlignment,
         lyricAuxiliaryOrder: lyricAuxiliaryOrder,
         useTraditionalLyrics: useTraditionalLyrics,
         emphasizeActiveLyric: emphasizeActiveLyric,
       ),
       _rememberPlaybackProgress = rememberPlaybackProgress,
       _autoSkipPlaybackErrors = autoSkipPlaybackErrors,
       _trackStateStore = trackStateStore,
       _reportPersistenceError = reportPersistenceError {
    _sessions = sessions;
    audio.bindQueueCallbacks(previous: previous, next: next);
    _subscription = audio.snapshots.listen(_onSnapshot);
  }

  final PlaybackResolver resolver;
  final AudioPort audio;
  final TrackPlaybackStateStore? _trackStateStore;
  final void Function(Object error)? _reportPersistenceError;
  late final PlaybackSessionPort? _sessions;
  late final StreamSubscription<AudioSnapshot> _subscription;
  PlayerState state;
  final Random _random = Random();
  _ActivePlaybackSession? _activeSession;
  List<PlaybackContext?> _playbackContexts = const [];
  int _playGeneration = 0;
  int? _bundleLyricsGeneration;
  int _lyricsRequestGeneration = 0;
  ({String source, String id, int generation, Future<bool> future})?
  _lyricsRefresh;
  ({String source, String id, int generation, Future<bool> future})?
  _artworkRefresh;
  Future<bool> Function()? _sequentialQueueEndHandler;
  bool _rememberPlaybackProgress;
  bool _autoSkipPlaybackErrors;
  String? _trackStateKey;
  int? _lastResumeWriteBucket;
  String? _clearedResumeKey;
  ({String key, int generation, Duration position})? _pendingResume;
  final Set<String> _failedTrackKeys = {};
  bool _handlingPlaybackFailure = false;

  void setSequentialQueueEndHandler(Future<bool> Function()? handler) {
    _sequentialQueueEndHandler = handler;
  }

  PlaybackContext? get currentPlaybackContext => _currentPlaybackContext;

  Future<void> playTracks(
    List<Track> tracks, {
    int startIndex = 0,
    List<PlaybackContext?>? contexts,
    PlayerQueueKind queueKind = PlayerQueueKind.manual,
  }) async {
    if (tracks.isEmpty) return;
    if (startIndex < 0 || startIndex >= tracks.length) {
      throw RangeError.index(startIndex, tracks, 'startIndex');
    }
    if (contexts != null && contexts.length != tracks.length) {
      throw ArgumentError.value(
        contexts.length,
        'contexts',
        'Playback contexts must match the queue length.',
      );
    }
    if (_rememberPlaybackProgress) await _flushResumePosition();
    _resetPlaybackFailureChain();
    _playGeneration++;
    final endingSession = _endSession(completed: false);
    _playbackContexts = List.unmodifiable(
      contexts ?? List<PlaybackContext?>.filled(tracks.length, null),
    );
    state = PlayerState(
      queue: List.unmodifiable(tracks),
      currentIndex: startIndex,
      quality: state.quality,
      processing: PlayerProcessing.loading,
      playbackPending: true,
      showLyrics: state.showLyrics,
      showTranslation: state.showTranslation,
      showRomanization: state.showRomanization,
      lyricFontSize: state.lyricFontSize,
      lyricAlignment: state.lyricAlignment,
      lyricAuxiliaryOrder: state.lyricAuxiliaryOrder,
      useTraditionalLyrics: state.useTraditionalLyrics,
      emphasizeActiveLyric: state.emphasizeActiveLyric,
      view: state.view,
      playbackMode: state.playbackMode,
      queueKind: queueKind,
      volume: state.volume,
      muted: state.muted,
      playbackRate: state.playbackRate,
    );
    notifyListeners();
    await endingSession;
    await _playCurrent();
  }

  void enqueue(Track track) {
    _playbackContexts = List.unmodifiable([..._playbackContexts, null]);
    state = state.copyWith(queue: List.unmodifiable([...state.queue, track]));
    notifyListeners();
  }

  void enqueueTracks(
    List<Track> tracks, {
    List<PlaybackContext?>? contexts,
    PlayerQueueKind? queueKind,
  }) {
    if (tracks.isEmpty) return;
    if (contexts != null && contexts.length != tracks.length) {
      throw ArgumentError.value(
        contexts.length,
        'contexts',
        'Playback contexts must match the appended tracks.',
      );
    }
    _playbackContexts = List.unmodifiable([
      ..._playbackContexts,
      ...(contexts ?? List<PlaybackContext?>.filled(tracks.length, null)),
    ]);
    state = state.copyWith(
      queue: List.unmodifiable([...state.queue, ...tracks]),
      queueKind: queueKind,
    );
    notifyListeners();
  }

  Future<void> playNext(Track track) async {
    final current = state.current;
    if (current == null) {
      await play(track);
      return;
    }
    if (current.source == track.source && current.id == track.id) return;
    final queue = state.queue
        .where((item) => item.source != track.source || item.id != track.id)
        .toList();
    final contexts = <PlaybackContext?>[];
    for (var index = 0; index < state.queue.length; index++) {
      final item = state.queue[index];
      if (item.source == track.source && item.id == track.id) continue;
      contexts.add(
        index < _playbackContexts.length ? _playbackContexts[index] : null,
      );
    }
    final currentIndex = queue.indexWhere(
      (item) => item.source == current.source && item.id == current.id,
    );
    queue.insert(currentIndex + 1, track);
    contexts.insert(currentIndex + 1, null);
    _playbackContexts = List.unmodifiable(contexts);
    state = state.copyWith(
      queue: List.unmodifiable(queue),
      currentIndex: currentIndex,
    );
    notifyListeners();
  }

  Future<void> play(Track track) => playTracks([track]);

  bool updateTrackArtwork(Track track, Uri picture) {
    final pictureUrl = picture.toString();
    var changed = false;
    final queue = state.queue
        .map((item) {
          if (item.source != track.source || item.id != track.id) return item;
          if (item.raw['pic'] == pictureUrl) return item;
          changed = true;
          return Track.fromJson({...item.toJson(), 'pic': pictureUrl});
        })
        .toList(growable: false);
    if (!changed) return false;
    state = state.copyWith(queue: List.unmodifiable(queue));
    notifyListeners();
    return true;
  }

  Future<bool> removeAt(int index) async {
    if (index < 0 || index >= state.queue.length) return false;
    if (state.queue.length == 1) return clearQueue();

    final removingCurrent = index == state.currentIndex;
    final queue = [...state.queue]..removeAt(index);
    final contexts = [..._playbackContexts];
    if (index < contexts.length) contexts.removeAt(index);
    _playbackContexts = List.unmodifiable(contexts);
    if (!removingCurrent) {
      final nextIndex = index < state.currentIndex
          ? state.currentIndex - 1
          : state.currentIndex;
      state = state.copyWith(
        queue: List.unmodifiable(queue),
        currentIndex: nextIndex,
      );
      notifyListeners();
      return true;
    }

    if (_rememberPlaybackProgress) await _flushResumePosition();
    _playGeneration++;
    final endingSession = _endSession(completed: false);
    final nextIndex = index < queue.length ? index : queue.length - 1;
    state = state.copyWith(
      queue: List.unmodifiable(queue),
      currentIndex: nextIndex,
      processing: PlayerProcessing.loading,
      playbackPending: true,
      position: Duration.zero,
      duration: Duration.zero,
      buffered: Duration.zero,
      clearLyrics: true,
      bundleCompleteness: null,
      error: null,
      lyricsError: null,
    );
    notifyListeners();
    await endingSession;
    await _playCurrent();
    return true;
  }

  Future<bool> clearQueue() async {
    if (state.queue.isEmpty) return false;
    if (_rememberPlaybackProgress) await _flushResumePosition();
    _playGeneration++;
    try {
      await audio.stopPlayback();
    } on Object catch (error) {
      state = state.copyWith(error: error);
      notifyListeners();
      return false;
    }
    await _endSession(completed: false);
    _playbackContexts = const [];
    state = PlayerState(
      quality: state.quality,
      showLyrics: state.showLyrics,
      showTranslation: state.showTranslation,
      showRomanization: state.showRomanization,
      lyricFontSize: state.lyricFontSize,
      lyricAlignment: state.lyricAlignment,
      lyricAuxiliaryOrder: state.lyricAuxiliaryOrder,
      useTraditionalLyrics: state.useTraditionalLyrics,
      emphasizeActiveLyric: state.emphasizeActiveLyric,
      view: PlayerView.artwork,
      playbackMode: state.playbackMode,
      queueKind: PlayerQueueKind.manual,
      volume: state.volume,
      muted: state.muted,
      playbackRate: state.playbackRate,
    );
    notifyListeners();
    return true;
  }

  Future<void> playIndex(int index) async {
    _resetPlaybackFailureChain();
    await _playIndex(index);
  }

  Future<void> _playIndex(int index, {bool allowAutoSkip = true}) async {
    if (index < 0 || index >= state.queue.length) return;
    if (_rememberPlaybackProgress) await _flushResumePosition();
    _playGeneration++;
    final endingSession = _endSession(completed: false);
    state = state.copyWith(
      currentIndex: index,
      processing: PlayerProcessing.loading,
      playbackPending: true,
      clearLyrics: true,
      bundleCompleteness: null,
      error: null,
    );
    notifyListeners();
    await endingSession;
    await _playCurrent(allowAutoSkip: allowAutoSkip);
  }

  Future<void> previous() => state.playbackMode == PlaybackMode.shuffle
      ? playIndex(_randomQueueIndex())
      : playIndex(state.currentIndex - 1);
  Future<void> next() => state.playbackMode == PlaybackMode.shuffle
      ? playIndex(_randomQueueIndex())
      : playIndex(state.currentIndex + 1);

  void cyclePlaybackMode() {
    final nextMode = switch (state.playbackMode) {
      PlaybackMode.sequential => PlaybackMode.repeatOne,
      PlaybackMode.repeatOne => PlaybackMode.shuffle,
      PlaybackMode.shuffle => PlaybackMode.sequential,
    };
    state = state.copyWith(playbackMode: nextMode);
    notifyListeners();
  }

  Future<bool> setVolume(double value) async {
    final controls = audio;
    if (controls is! AudioControlPort) return false;
    final normalized = value.clamp(0, 1).toDouble();
    final previous = state;
    state = state.copyWith(
      volume: normalized,
      muted: normalized == 0 ? true : false,
    );
    notifyListeners();
    try {
      await (controls as AudioControlPort).setVolume(normalized);
      return true;
    } on Object {
      state = previous;
      notifyListeners();
      return false;
    }
  }

  Future<bool> setMuted(bool value) async {
    final controls = audio;
    if (controls is! AudioControlPort) return false;
    final previous = state;
    state = state.copyWith(muted: value);
    notifyListeners();
    try {
      await (controls as AudioControlPort).setVolume(
        value ? 0 : state.volume.clamp(.01, 1),
      );
      return true;
    } on Object {
      state = previous;
      notifyListeners();
      return false;
    }
  }

  Future<bool> setPlaybackRate(double value) async {
    const supported = <double>[.5, .75, 1, 1.25, 1.5, 2];
    if (!supported.contains(value)) return false;
    final controls = audio;
    if (controls is! AudioControlPort) return false;
    final previous = state;
    state = state.copyWith(playbackRate: value);
    notifyListeners();
    try {
      await (controls as AudioControlPort).setSpeed(value);
      return true;
    } on Object {
      state = previous;
      notifyListeners();
      return false;
    }
  }

  Future<void> pause() => audio.pause();
  Future<void> resume() async {
    if (state.current == null) {
      await audio.resume();
      return;
    }
    if (state.processing == PlayerProcessing.error || state.error != null) {
      state = state.copyWith(
        processing: PlayerProcessing.loading,
        playbackPending: true,
        error: null,
      );
      notifyListeners();
      await _playCurrent();
      return;
    }
    if (state.processing == PlayerProcessing.completed) {
      await audio.seek(Duration.zero);
    }
    await audio.resume();
  }

  Future<void> seek(Duration position) => audio.seek(position);

  Future<bool> setQuality(String quality) async {
    if (quality == state.quality) return true;
    final previousQuality = state.quality;
    final hasCurrentTrack = state.current != null;
    state = state.copyWith(
      quality: quality,
      processing: hasCurrentTrack ? PlayerProcessing.loading : null,
      playbackPending: hasCurrentTrack,
    );
    notifyListeners();
    if (state.current == null) return true;
    final played = await _playCurrent(startSession: false);
    if (played) return true;
    state = state.copyWith(quality: previousQuality);
    notifyListeners();
    return false;
  }

  void setShowLyrics(bool value) {
    state = state.copyWith(
      showLyrics: value,
      view: value ? PlayerView.lyrics : PlayerView.artwork,
    );
    notifyListeners();
  }

  void setView(PlayerView view) {
    state = state.copyWith(view: view, showLyrics: view == PlayerView.lyrics);
    notifyListeners();
  }

  void setShowTranslation(bool value) {
    state = state.copyWith(showTranslation: value);
    notifyListeners();
  }

  void setShowRomanization(bool value) {
    state = state.copyWith(showRomanization: value);
    notifyListeners();
  }

  void setLyricFontSize(LyricFontSize value) {
    state = state.copyWith(lyricFontSize: value);
    notifyListeners();
  }

  void setLyricAlignment(LyricAlignment value) {
    state = state.copyWith(lyricAlignment: value);
    notifyListeners();
  }

  void setLyricAuxiliaryOrder(LyricAuxiliaryOrder value) {
    state = state.copyWith(lyricAuxiliaryOrder: value);
    notifyListeners();
  }

  void setUseTraditionalLyrics(bool value) {
    state = state.copyWith(useTraditionalLyrics: value);
    notifyListeners();
  }

  void setEmphasizeActiveLyric(bool value) {
    state = state.copyWith(emphasizeActiveLyric: value);
    notifyListeners();
  }

  void applySettings(AppSettings settings) {
    _rememberPlaybackProgress = settings.rememberPlaybackProgress;
    _autoSkipPlaybackErrors = settings.autoSkipPlaybackErrors;
    if (!_rememberPlaybackProgress) _pendingResume = null;
    if (!_autoSkipPlaybackErrors) _resetPlaybackFailureChain();
    state = state.copyWith(
      showLyrics: settings.showLyrics,
      showTranslation: settings.showTranslation,
      showRomanization: settings.showRomanization,
      lyricFontSize: settings.lyricFontSize,
      lyricAlignment: settings.lyricAlignment,
      lyricAuxiliaryOrder: settings.lyricAuxiliaryOrder,
      useTraditionalLyrics: settings.useTraditionalLyrics,
      emphasizeActiveLyric: settings.emphasizeActiveLyric,
    );
    notifyListeners();
  }

  Future<void> setLyricOffset(Duration value) async {
    final track = state.current;
    if (track == null) return;
    final milliseconds = value.inMilliseconds.clamp(
      minLyricOffsetMilliseconds,
      maxLyricOffsetMilliseconds,
    );
    final offset = Duration(milliseconds: milliseconds);
    state = state.copyWith(lyricOffset: offset);
    notifyListeners();
    try {
      await _trackStateStore?.writeLyricOffset(track, offset);
    } on Object catch (error) {
      _reportPersistenceError?.call(error);
    }
  }

  Future<void> loadLyrics(Future<Lyrics> Function(Track track) loader) async {
    final track = state.current;
    if (track == null) return;
    final generation = _playGeneration;
    final requestGeneration = ++_lyricsRequestGeneration;
    if (_bundleLyricsGeneration == generation &&
        state.lyrics?.original.trim().isNotEmpty == true) {
      return;
    }
    try {
      final lyrics = await loader(track);
      if (!_isCurrent(generation, track) ||
          requestGeneration != _lyricsRequestGeneration ||
          _bundleLyricsGeneration == generation) {
        return;
      }
      state = state.copyWith(lyrics: lyrics, lyricsError: null);
    } on Object catch (error) {
      if (!_isCurrent(generation, track) ||
          requestGeneration != _lyricsRequestGeneration ||
          _bundleLyricsGeneration == generation) {
        return;
      }
      state = state.copyWith(clearLyrics: true, lyricsError: error);
    }
    notifyListeners();
  }

  Future<bool> refreshLyricsIfMissing(
    Future<Lyrics> Function(Track track) loader, {
    String? source,
    String? trackId,
  }) {
    final track = state.current;
    if (track == null ||
        (source != null && track.source != source) ||
        (trackId != null && track.id != trackId) ||
        state.lyrics?.original.trim().isNotEmpty == true) {
      return Future.value(false);
    }
    final generation = _playGeneration;
    final pending = _lyricsRefresh;
    if (pending != null &&
        pending.source == track.source &&
        pending.id == track.id &&
        pending.generation == generation) {
      return pending.future;
    }
    late final Future<bool> operation;
    operation =
        (() async {
          await loadLyrics(loader);
          final current = state.current;
          return current?.source == track.source &&
              current?.id == track.id &&
              state.lyrics?.original.trim().isNotEmpty == true;
        })().whenComplete(() {
          if (identical(_lyricsRefresh?.future, operation)) {
            _lyricsRefresh = null;
          }
        });
    _lyricsRefresh = (
      source: track.source,
      id: track.id,
      generation: generation,
      future: operation,
    );
    return operation;
  }

  Future<bool> refreshArtworkIfMissing(
    Future<String> Function(Track track) loader, {
    String? source,
    String? trackId,
  }) {
    final track = state.current;
    if (track == null ||
        (source != null && track.source != source) ||
        (trackId != null && track.id != trackId) ||
        _hasArtwork(track)) {
      return Future.value(false);
    }
    final generation = _playGeneration;
    final pending = _artworkRefresh;
    if (pending != null &&
        pending.source == track.source &&
        pending.id == track.id &&
        pending.generation == generation) {
      return pending.future;
    }
    late final Future<bool> operation;
    operation =
        (() async {
          try {
            final picture = await loader(track);
            if (!_isCurrent(generation, track) || picture.trim().isEmpty) {
              return false;
            }
            final raw = state.current!.toJson()..['pic'] = picture;
            final updated = Track.fromJson(raw);
            final queue = [...state.queue]..[state.currentIndex] = updated;
            state = state.copyWith(queue: List.unmodifiable(queue));
            notifyListeners();
            return true;
          } on Object {
            return false;
          }
        })().whenComplete(() {
          if (identical(_artworkRefresh?.future, operation)) {
            _artworkRefresh = null;
          }
        });
    _artworkRefresh = (
      source: track.source,
      id: track.id,
      generation: generation,
      future: operation,
    );
    return operation;
  }

  Future<bool> _playCurrent({
    bool startSession = true,
    bool allowAutoSkip = true,
  }) async {
    final track = state.current;
    if (track == null) return false;
    final generation = ++_playGeneration;
    final storedState = _loadTrackState(track, generation);
    _bundleLyricsGeneration = null;
    try {
      if (await audio.playCachedTrack(track, state.quality)) {
        if (!_isCurrent(generation, track)) return false;
        state = state.copyWith(playbackPending: false, error: null);
        notifyListeners();
        unawaited(_refreshCachedLocalResources(track, generation));
        if (startSession) await _startSession(track);
        await _scheduleResume(track, generation, storedState);
        _resetPlaybackFailureChain();
        return true;
      }
    } on Object {
      // A stale or undecodable cache must not prevent a fresh Service resolve.
    }
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final source = await _resolve(track);
        if (!_isCurrent(generation, track)) return false;
        final playbackTrack = _applyResolvedBundle(
          source,
          generation: generation,
        );
        await audio.playTrack(playbackTrack, source.streamUri, state.quality);
        if (!_isCurrent(generation, playbackTrack)) return false;
        state = state.copyWith(playbackPending: false, error: null);
        notifyListeners();
        if (startSession) await _startSession(playbackTrack);
        await _scheduleResume(playbackTrack, generation, storedState);
        _resetPlaybackFailureChain();
        return true;
      } on PlaybackStreamExpiredException catch (error) {
        if (!_isCurrent(generation, track)) return false;
        lastError = error;
        if (attempt == 0) continue;
      } on Object catch (error) {
        if (!_isCurrent(generation, track)) return false;
        lastError = error;
        break;
      }
    }
    if (!_isCurrent(generation, track)) return false;
    state = state.copyWith(
      playbackPending: false,
      processing: PlayerProcessing.error,
      error: lastError,
    );
    notifyListeners();
    if (_autoSkipPlaybackErrors && allowAutoSkip) {
      return _advanceAfterPlaybackFailure(track);
    }
    return false;
  }

  Future<TrackPlaybackState?> _loadTrackState(
    Track track,
    int generation,
  ) async {
    final store = _trackStateStore;
    if (store == null) return null;
    final key = _keyFor(track);
    if (_trackStateKey != key) {
      _trackStateKey = key;
      _lastResumeWriteBucket = null;
      _pendingResume = null;
      state = state.copyWith(lyricOffset: Duration.zero);
      notifyListeners();
    }
    try {
      final stored = await store.read(track);
      if (_isCurrent(generation, track) && stored != null) {
        state = state.copyWith(lyricOffset: stored.lyricOffset);
        notifyListeners();
      }
      return stored;
    } on Object catch (error) {
      _reportPersistenceError?.call(error);
      return null;
    }
  }

  Future<void> _scheduleResume(
    Track track,
    int generation,
    Future<TrackPlaybackState?> storedState,
  ) async {
    if (!_rememberPlaybackProgress) return;
    final stored = await storedState;
    final position = stored?.resumePosition;
    if (position == null || position <= const Duration(seconds: 5)) return;
    if (!_isCurrent(generation, track)) return;
    _pendingResume = (
      key: _keyFor(track),
      generation: generation,
      position: position,
    );
    _tryRestorePendingResume();
  }

  void _tryRestorePendingResume() {
    final pending = _pendingResume;
    final track = state.current;
    if (pending == null || track == null || state.duration <= Duration.zero) {
      return;
    }
    if (pending.generation != _playGeneration ||
        pending.key != _keyFor(track)) {
      _pendingResume = null;
      return;
    }
    _pendingResume = null;
    if (state.duration - pending.position < const Duration(seconds: 10)) {
      unawaited(_clearResumePosition(track));
      return;
    }
    final position = pending.position > state.duration
        ? state.duration
        : pending.position;
    unawaited(audio.seek(position).catchError((Object _) {}));
  }

  Future<bool> _advanceAfterPlaybackFailure(Track failed) async {
    if (_handlingPlaybackFailure) return false;
    _handlingPlaybackFailure = true;
    try {
      _failedTrackKeys.add(_keyFor(failed));
      for (
        var index = state.currentIndex + 1;
        index < state.queue.length;
        index++
      ) {
        final candidate = state.queue[index];
        final candidateKey = _keyFor(candidate);
        if (_failedTrackKeys.contains(candidateKey)) continue;
        await _playIndex(index, allowAutoSkip: false);
        if (state.processing != PlayerProcessing.error) return true;
        _failedTrackKeys.add(candidateKey);
      }
      return false;
    } finally {
      _handlingPlaybackFailure = false;
    }
  }

  void _resetPlaybackFailureChain() {
    _failedTrackKeys.clear();
  }

  String _keyFor(Track track) => '${track.source}\u0000${track.id}';

  Future<void> _clearResumePosition(Track track) async {
    final key = _keyFor(track);
    if (_clearedResumeKey == key) return;
    _clearedResumeKey = key;
    try {
      await _trackStateStore?.clearResumePosition(track);
    } on Object catch (error) {
      if (_clearedResumeKey == key) _clearedResumeKey = null;
      _reportPersistenceError?.call(error);
    }
  }

  void _persistResumeFromSnapshot(Track track) {
    if (!_rememberPlaybackProgress || _trackStateStore == null) return;
    if (state.duration > Duration.zero &&
        state.duration - state.position < const Duration(seconds: 10)) {
      _lastResumeWriteBucket = null;
      unawaited(_clearResumePosition(track));
      return;
    }
    if (state.position <= const Duration(seconds: 5)) return;
    final bucket = state.position.inSeconds ~/ 5;
    if (_lastResumeWriteBucket == bucket) return;
    _lastResumeWriteBucket = bucket;
    _clearedResumeKey = null;
    unawaited(
      _trackStateStore
          .writeResumePosition(track, state.position)
          .catchError((Object error) => _reportPersistenceError?.call(error)),
    );
  }

  Future<void> _flushResumePosition() async {
    final track = state.current;
    final store = _trackStateStore;
    if (!_rememberPlaybackProgress || track == null || store == null) return;
    if (state.duration > Duration.zero &&
        state.duration - state.position < const Duration(seconds: 10)) {
      await _clearResumePosition(track);
      return;
    }
    if (state.position <= const Duration(seconds: 5)) return;
    _clearedResumeKey = null;
    try {
      await store.writeResumePosition(track, state.position);
    } on Object catch (error) {
      _reportPersistenceError?.call(error);
    }
  }

  Future<PlaybackSource> _resolve(Track track) {
    final recommendationItemId = _currentPlaybackContext?.recommendationItemId;
    final currentResolver = resolver;
    if (recommendationItemId != null &&
        currentResolver is ContextualPlaybackResolver) {
      return (currentResolver as ContextualPlaybackResolver).resolveWithContext(
        track,
        state.quality,
        recommendationItemId: recommendationItemId,
      );
    }
    return currentResolver.resolve(track, state.quality);
  }

  PlaybackContext? get _currentPlaybackContext {
    final index = state.currentIndex;
    return index >= 0 && index < _playbackContexts.length
        ? _playbackContexts[index]
        : null;
  }

  bool _isCurrent(int generation, Track track) {
    final current = state.current;
    return generation == _playGeneration &&
        current?.source == track.source &&
        current?.id == track.id;
  }

  Future<void> _refreshCachedLocalResources(Track track, int generation) async {
    if (track.source != 'local' ||
        (_hasArtwork(track) && _hasLyricsResource(track))) {
      return;
    }
    try {
      final source = await _resolve(track);
      if (!_isCurrent(generation, track)) return;
      _applyResolvedResources(source, generation: generation);
    } on Object {
      // Optional resource refresh must not make cached audio unavailable.
    }
  }

  bool _hasArtwork(Track track) {
    final value = track.raw['pic'];
    return value is String && value.trim().isNotEmpty;
  }

  bool _hasLyricsResource(Track track) {
    final meta = track.raw['meta'];
    return meta is Map &&
        meta['lyricsUrl'] is String &&
        (meta['lyricsUrl']! as String).trim().isNotEmpty;
  }

  Track _applyResolvedBundle(PlaybackSource source, {required int generation}) {
    return _applyResolvedResources(source, generation: generation);
  }

  Track _applyResolvedResources(
    PlaybackSource source, {
    required int generation,
  }) {
    final current = state.current!;
    final raw = current.toJson();
    final pictureUri = source.pictureUri;
    if (pictureUri != null) raw['pic'] = pictureUri.toString();
    final lyricsUri = source.lyricsUri;
    if (lyricsUri != null) {
      final existingMeta = raw['meta'];
      raw['meta'] = {
        if (existingMeta is Map) ...Map<String, Object?>.from(existingMeta),
        'lyricsUrl': lyricsUri.toString(),
      };
    }
    final updated = Track.fromJson(raw);
    final queue = [...state.queue]..[state.currentIndex] = updated;
    final bundleLyrics = source.bundleLyrics;
    final hasBundleLyrics = bundleLyrics?.original.trim().isNotEmpty == true;
    if (hasBundleLyrics) {
      _bundleLyricsGeneration = generation;
      _lyricsRequestGeneration++;
    }
    state = state.copyWith(
      queue: List.unmodifiable(queue),
      lyrics: hasBundleLyrics ? bundleLyrics : null,
      bundleCompleteness: source.resolved.completeness,
      lyricsError: null,
    );
    notifyListeners();
    return updated;
  }

  Future<void> _startSession(Track track) async {
    final sessions = _sessions;
    if (sessions == null || _activeSession != null) return;
    final entry = _ActivePlaybackSession();
    _activeSession = entry;
    try {
      final recommendationItemId =
          _currentPlaybackContext?.recommendationItemId;
      if (recommendationItemId != null &&
          sessions is RecommendationPlaybackSessionPort) {
        entry.playbackId = await (sessions as RecommendationPlaybackSessionPort)
            .startRecommendation(
              track,
              recommendationItemId: recommendationItemId,
            );
      } else {
        entry.playbackId = await sessions.start(track);
      }
      final terminal = entry.terminal;
      if (terminal != null) await _reportSessionEnd(entry, terminal);
    } on Object {
      if (_activeSession == entry) _activeSession = null;
      // Playback history is best-effort and must not alter player state.
    }
  }

  Future<void> _endSession({required bool completed}) async {
    final entry = _activeSession;
    if (entry == null) return;
    _activeSession = null;
    final terminal = (
      completed: completed,
      position: state.position,
      duration: state.duration,
    );
    entry.terminal = terminal;
    if (entry.playbackId != null) await _reportSessionEnd(entry, terminal);
  }

  Future<void> _reportSessionEnd(
    _ActivePlaybackSession entry,
    _PlaybackTerminal terminal,
  ) async {
    final sessions = _sessions;
    final playbackId = entry.playbackId;
    if (sessions == null || playbackId == null) return;
    try {
      await sessions.end(
        playbackId,
        completed: terminal.completed,
        position: terminal.position,
        duration: terminal.duration,
      );
    } on Object {
      // Playback history is best-effort and must not alter player state.
    }
  }

  void _onSnapshot(AudioSnapshot snapshot) {
    final newlyCompleted =
        snapshot.processing == PlayerProcessing.completed &&
        state.processing != PlayerProcessing.completed;
    state = state.copyWith(
      playing: effectivePlaybackPlaying(
        playing: snapshot.playing,
        processing: snapshot.processing,
      ),
      processing: snapshot.processing,
      position: snapshot.position,
      duration: snapshot.duration,
      buffered: snapshot.buffered,
    );
    notifyListeners();
    _tryRestorePendingResume();
    final track = state.current;
    if (track != null) _persistResumeFromSnapshot(track);
    if (newlyCompleted) unawaited(_handleCompletion());
  }

  int _randomQueueIndex() {
    if (state.queue.length < 2) return state.currentIndex;
    final offset = 1 + _random.nextInt(state.queue.length - 1);
    return (state.currentIndex + offset) % state.queue.length;
  }

  Future<void> _handleCompletion() async {
    final completedTrack = state.current;
    if (_rememberPlaybackProgress && completedTrack != null) {
      await _clearResumePosition(completedTrack);
    }
    await _endSession(completed: true);
    switch (state.playbackMode) {
      case PlaybackMode.repeatOne:
        state = state.copyWith(
          processing: PlayerProcessing.loading,
          playbackPending: true,
          position: Duration.zero,
        );
        notifyListeners();
        await _playCurrent();
      case PlaybackMode.shuffle:
        await playIndex(_randomQueueIndex());
      case PlaybackMode.sequential:
        if (state.currentIndex + 1 < state.queue.length) {
          await playIndex(state.currentIndex + 1);
        } else if (await (_sequentialQueueEndHandler?.call() ??
                Future.value(false)) &&
            state.currentIndex + 1 < state.queue.length) {
          await playIndex(state.currentIndex + 1);
        }
    }
  }

  @override
  void dispose() {
    unawaited(_flushResumePosition());
    _playGeneration++;
    unawaited(_endSession(completed: false));
    _subscription.cancel();
    super.dispose();
  }
}
