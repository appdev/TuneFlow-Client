import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import 'playback_repository.dart';
import 'player_state.dart';
import 'service_audio_handler.dart';

final class PlayerController extends ChangeNotifier {
  PlayerController({
    required this.resolver,
    required this.audio,
    String quality = '128k',
    bool showTranslation = true,
    Future<void> Function(Track track)? reportPlayback,
  }) : state = PlayerState(quality: quality, showTranslation: showTranslation) {
    _reportPlaybackCallback = reportPlayback;
    audio.bindQueueCallbacks(previous: previous, next: next);
    _subscription = audio.snapshots.listen(_onSnapshot);
  }

  final PlaybackResolver resolver;
  final AudioPort audio;
  late final Future<void> Function(Track track)? _reportPlaybackCallback;
  late final StreamSubscription<AudioSnapshot> _subscription;
  PlayerState state;
  final Random _random = Random();

  Future<void> playTracks(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    if (startIndex < 0 || startIndex >= tracks.length) {
      throw RangeError.index(startIndex, tracks, 'startIndex');
    }
    state = PlayerState(
      queue: List.unmodifiable(tracks),
      currentIndex: startIndex,
      quality: state.quality,
      processing: PlayerProcessing.loading,
      showLyrics: state.showLyrics,
      showTranslation: state.showTranslation,
      view: state.view,
      playbackMode: state.playbackMode,
    );
    notifyListeners();
    await _playCurrent();
  }

  void enqueue(Track track) {
    state = state.copyWith(queue: List.unmodifiable([...state.queue, track]));
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
    final currentIndex = queue.indexWhere(
      (item) => item.source == current.source && item.id == current.id,
    );
    queue.insert(currentIndex + 1, track);
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

    final nextIndex = index < queue.length ? index : queue.length - 1;
    state = state.copyWith(
      queue: List.unmodifiable(queue),
      currentIndex: nextIndex,
      processing: PlayerProcessing.loading,
      position: Duration.zero,
      duration: Duration.zero,
      buffered: Duration.zero,
      clearLyrics: true,
      error: null,
      lyricsError: null,
    );
    notifyListeners();
    await _playCurrent();
    return true;
  }

  Future<bool> clearQueue() async {
    if (state.queue.isEmpty) return false;
    try {
      await audio.stopPlayback();
    } on Object catch (error) {
      state = state.copyWith(error: error);
      notifyListeners();
      return false;
    }
    state = PlayerState(
      quality: state.quality,
      showTranslation: state.showTranslation,
      view: PlayerView.artwork,
      playbackMode: state.playbackMode,
    );
    notifyListeners();
    return true;
  }

  Future<void> playIndex(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    state = state.copyWith(
      currentIndex: index,
      processing: PlayerProcessing.loading,
      error: null,
    );
    notifyListeners();
    await _playCurrent();
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

  Future<void> pause() => audio.pause();
  Future<void> resume() async {
    if (state.current == null) {
      await audio.resume();
      return;
    }
    if (state.processing == PlayerProcessing.error || state.error != null) {
      state = state.copyWith(processing: PlayerProcessing.loading, error: null);
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
    state = state.copyWith(quality: quality);
    notifyListeners();
    if (state.current == null) return true;
    final played = await _playCurrent();
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

  Future<void> loadLyrics(Future<Lyrics> Function(Track track) loader) async {
    final track = state.current;
    if (track == null) return;
    try {
      final lyrics = await loader(track);
      state = state.copyWith(lyrics: lyrics, lyricsError: null);
    } on Object catch (error) {
      state = state.copyWith(clearLyrics: true, lyricsError: error);
    }
    notifyListeners();
  }

  Future<bool> _playCurrent() async {
    final track = state.current;
    if (track == null) return false;
    try {
      if (await audio.playCachedTrack(track, state.quality)) {
        state = state.copyWith(error: null);
        notifyListeners();
        _reportPlayback(track);
        return true;
      }
    } on Object {
      // A stale or undecodable cache must not prevent a fresh Service resolve.
    }
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final source = await resolver.resolve(track, state.quality);
        await audio.playTrack(track, source.streamUri, state.quality);
        state = state.copyWith(error: null);
        notifyListeners();
        _reportPlayback(track);
        return true;
      } on PlaybackStreamExpiredException catch (error) {
        lastError = error;
        if (attempt == 0) continue;
      } on Object catch (error) {
        lastError = error;
        break;
      }
    }
    state = state.copyWith(
      processing: PlayerProcessing.error,
      error: lastError,
    );
    notifyListeners();
    return false;
  }

  void _reportPlayback(Track track) {
    final report = _reportPlaybackCallback;
    if (report == null) return;
    try {
      unawaited(report(track).catchError((_) {}));
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
    if (newlyCompleted) unawaited(_handleCompletion());
  }

  int _randomQueueIndex() {
    if (state.queue.length < 2) return state.currentIndex;
    final offset = 1 + _random.nextInt(state.queue.length - 1);
    return (state.currentIndex + offset) % state.queue.length;
  }

  Future<void> _handleCompletion() async {
    switch (state.playbackMode) {
      case PlaybackMode.repeatOne:
        state = state.copyWith(
          processing: PlayerProcessing.loading,
          position: Duration.zero,
        );
        notifyListeners();
        await _playCurrent();
      case PlaybackMode.shuffle:
        await playIndex(_randomQueueIndex());
      case PlaybackMode.sequential:
        if (state.currentIndex + 1 < state.queue.length) {
          await playIndex(state.currentIndex + 1);
        }
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
