import '../../api/models.dart';

enum PlayerProcessing { idle, loading, buffering, ready, completed, error }

enum PlayerView { artwork, lyrics, queue }

enum PlaybackMode { sequential, repeatOne, shuffle }

final class AudioSnapshot {
  const AudioSnapshot({
    this.playing = false,
    this.processing = PlayerProcessing.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
  });

  final bool playing;
  final PlayerProcessing processing;
  final Duration position;
  final Duration duration;
  final Duration buffered;
}

final class PlayerState {
  const PlayerState({
    this.queue = const [],
    this.currentIndex = -1,
    this.quality = '128k',
    this.playing = false,
    this.processing = PlayerProcessing.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.lyrics,
    this.showLyrics = false,
    this.showTranslation = true,
    this.view = PlayerView.artwork,
    this.playbackMode = PlaybackMode.sequential,
    this.error,
    this.lyricsError,
  });

  final List<Track> queue;
  final int currentIndex;
  final String quality;
  final bool playing;
  final PlayerProcessing processing;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final Lyrics? lyrics;
  final bool showLyrics;
  final bool showTranslation;
  final PlayerView view;
  final PlaybackMode playbackMode;
  final Object? error;
  final Object? lyricsError;

  Track? get current => currentIndex >= 0 && currentIndex < queue.length
      ? queue[currentIndex]
      : null;

  bool get canPrevious =>
      queue.length > 1 &&
      (playbackMode == PlaybackMode.shuffle || currentIndex > 0);

  bool get canNext =>
      queue.length > 1 &&
      (playbackMode == PlaybackMode.shuffle || currentIndex + 1 < queue.length);

  PlayerState copyWith({
    List<Track>? queue,
    int? currentIndex,
    String? quality,
    bool? playing,
    PlayerProcessing? processing,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    Lyrics? lyrics,
    bool clearLyrics = false,
    bool? showLyrics,
    bool? showTranslation,
    PlayerView? view,
    PlaybackMode? playbackMode,
    Object? error = _unchanged,
    Object? lyricsError = _unchanged,
  }) => PlayerState(
    queue: queue ?? this.queue,
    currentIndex: currentIndex ?? this.currentIndex,
    quality: quality ?? this.quality,
    playing: playing ?? this.playing,
    processing: processing ?? this.processing,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    buffered: buffered ?? this.buffered,
    lyrics: clearLyrics ? null : lyrics ?? this.lyrics,
    showLyrics: showLyrics ?? this.showLyrics,
    showTranslation: showTranslation ?? this.showTranslation,
    view: view ?? this.view,
    playbackMode: playbackMode ?? this.playbackMode,
    error: identical(error, _unchanged) ? this.error : error,
    lyricsError: identical(lyricsError, _unchanged)
        ? this.lyricsError
        : lyricsError,
  );
}

const _unchanged = Object();
