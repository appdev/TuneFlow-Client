import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../../api/models.dart';
import '../../storage/media_cache.dart';
import 'player_state.dart';

String audioCacheExtension(String quality) =>
    quality.toLowerCase().contains('flac') ? '.flac' : '.mp3';

const notificationArtworkHeaders = {
  'Referer': 'https://music.163.com/',
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 Chrome/120 Safari/537.36',
};

MediaItem mediaItemForTrack(
  Track track, {
  required Uri fallbackArtUri,
  Duration? duration,
}) {
  final artwork = track.raw['pic'];
  final artworkUrl = artwork is String ? artwork.trim() : '';
  return MediaItem(
    id: track.id,
    title: track.title.isEmpty ? track.id : track.title,
    artist: track.artist,
    duration: duration,
    artUri: artworkUrl.isEmpty ? fallbackArtUri : Uri.parse(artworkUrl),
    artHeaders: artworkUrl.isEmpty ? null : notificationArtworkHeaders,
  );
}

final class PlaybackStreamExpiredException implements Exception {
  const PlaybackStreamExpiredException();

  @override
  String toString() => 'Playback stream token expired.';
}

abstract interface class AudioPort {
  Stream<AudioSnapshot> get snapshots;
  void bindQueueCallbacks({
    required Future<void> Function() previous,
    required Future<void> Function() next,
  });
  Future<bool> playCachedTrack(Track track, String quality);
  Future<void> playTrack(Track track, Uri streamUri, String quality);
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> stopPlayback();
}

final class SilentAudioPort implements AudioPort {
  @override
  Stream<AudioSnapshot> get snapshots => Stream.value(const AudioSnapshot());
  @override
  void bindQueueCallbacks({
    required Future<void> Function() previous,
    required Future<void> Function() next,
  }) {}
  @override
  Future<void> pause() async {}
  @override
  Future<bool> playCachedTrack(Track track, String quality) async => false;
  @override
  Future<void> playTrack(Track track, Uri streamUri, String quality) async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stopPlayback() async {}
}

final class ServiceAudioHandler extends BaseAudioHandler
    with SeekHandler
    implements AudioPort {
  ServiceAudioHandler({required Uri fallbackArtUri, MediaCache? cache})
    : _fallbackArtUri = fallbackArtUri,
      _cache = cache {
    _subscriptions = [
      _player.playbackEventStream.listen((_) => _publishSnapshot()),
      _player.positionStream.listen(
        (position) =>
            _publishSnapshot(position: position, publishPlaybackState: false),
      ),
      _player.durationStream.listen(_updateMediaItemDuration),
    ];
  }

  final AudioPlayer _player = AudioPlayer();
  final Uri _fallbackArtUri;
  final MediaCache? _cache;
  final StreamController<AudioSnapshot> _snapshots =
      StreamController<AudioSnapshot>.broadcast();
  AudioSnapshot _last = const AudioSnapshot();
  late final List<StreamSubscription<dynamic>> _subscriptions;
  MediaCacheLease? _audioLease;
  StreamSubscription<double>? _cacheProgress;
  Future<void> Function() _previous = _nothing;
  Future<void> Function() _next = _nothing;

  static Future<void> _nothing() async {}

  @override
  Stream<AudioSnapshot> get snapshots async* {
    yield _last;
    yield* _snapshots.stream;
  }

  @override
  void bindQueueCallbacks({
    required Future<void> Function() previous,
    required Future<void> Function() next,
  }) {
    _previous = previous;
    _next = next;
  }

  @override
  Future<bool> playCachedTrack(Track track, String quality) async {
    final cache = _cache;
    if (cache == null) return false;
    MediaCacheLease lease;
    try {
      lease = await cache.acquireAudio(
        source: track.source,
        trackId: track.id,
        quality: quality,
      );
    } on Object {
      return false;
    }
    if (!await lease.file.exists()) {
      await lease.release();
      return false;
    }
    _setMediaItem(track);
    try {
      await _player.setFilePath(lease.file.path);
      await _replaceCacheLease(lease);
      await _startPlayback();
      return true;
    } on Object {
      await cache.invalidate(lease.file);
      await lease.release();
      rethrow;
    }
  }

  @override
  Future<void> playTrack(Track track, Uri streamUri, String quality) async {
    _setMediaItem(track);
    MediaCacheLease? lease;
    StreamSubscription<double>? progress;
    IndexedAudioSource source = AudioSource.uri(streamUri);
    final cache = _cache;
    if (cache != null) {
      try {
        lease = await cache.acquireAudio(
          source: track.source,
          trackId: track.id,
          quality: quality,
        );
        // just_audio has no stable equivalent that exposes progressive cache
        // download.
        // ignore: experimental_member_use
        final caching = LockCachingAudioSource(
          streamUri,
          cacheFile: lease.file,
        );
        source = await caching.resolve();
        progress = caching.downloadProgressStream
            .where((value) => value >= 1)
            .take(1)
            .listen((_) => unawaited(cache.reconcile().catchError((_) {})));
      } on Object {
        await progress?.cancel();
        await lease?.release();
        lease = null;
        progress = null;
        source = AudioSource.uri(streamUri);
      }
    }
    try {
      await _player.setAudioSource(source);
      await _replaceCacheLease(lease, progress: progress);
      await _startPlayback();
    } on PlayerException catch (error) {
      await progress?.cancel();
      await lease?.release();
      final detail = '${error.code} ${error.message}'.toLowerCase();
      if (detail.contains('401') || detail.contains('403')) {
        throw const PlaybackStreamExpiredException();
      }
      rethrow;
    } on Object {
      await progress?.cancel();
      await lease?.release();
      rethrow;
    }
  }

  Future<void> _replaceCacheLease(
    MediaCacheLease? next, {
    StreamSubscription<double>? progress,
  }) async {
    final previousLease = _audioLease;
    final previousProgress = _cacheProgress;
    _audioLease = next;
    _cacheProgress = progress;
    await previousProgress?.cancel();
    await previousLease?.release();
  }

  Future<void> _startPlayback() async {
    final playback = _player.play();
    await Future.any<void>([
      _player.playingStream.firstWhere((playing) => playing),
      playback,
    ]);
    unawaited(playback.catchError((Object _) {}));
  }

  void _publishSnapshot({
    Duration? position,
    bool publishPlaybackState = true,
  }) {
    final processing = switch (_player.processingState) {
      ProcessingState.idle => PlayerProcessing.idle,
      ProcessingState.loading => PlayerProcessing.loading,
      ProcessingState.buffering => PlayerProcessing.buffering,
      ProcessingState.ready => PlayerProcessing.ready,
      ProcessingState.completed => PlayerProcessing.completed,
    };
    final currentPosition = position ?? _player.position;
    final playing = effectivePlaybackPlaying(
      playing: _player.playing,
      processing: processing,
    );
    _last = AudioSnapshot(
      playing: playing,
      processing: processing,
      position: currentPosition,
      duration: _player.duration ?? Duration.zero,
      buffered: _player.bufferedPosition,
    );
    _snapshots.add(_last);
    if (!publishPlaybackState) return;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {MediaAction.seek},
        playing: playing,
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        updatePosition: currentPosition,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ),
    );
  }

  void _setMediaItem(Track track) {
    mediaItem.add(mediaItemForTrack(track, fallbackArtUri: _fallbackArtUri));
  }

  void _updateMediaItemDuration(Duration? duration) {
    final current = mediaItem.value;
    if (current == null || duration == null || current.duration == duration) {
      return;
    }
    mediaItem.add(current.copyWith(duration: duration));
    _publishSnapshot();
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> resume() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> stopPlayback() async {
    await _player.stop();
    await _replaceCacheLease(null);
    _publishSnapshot(position: Duration.zero);
  }

  @override
  Future<void> skipToPrevious() => _previous();
  @override
  Future<void> skipToNext() => _next();

  @override
  Future<void> stop() async {
    await _player.stop();
    await _replaceCacheLease(null);
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    await _snapshots.close();
    await _player.dispose();
    return super.stop();
  }
}
