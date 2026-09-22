import 'package:flutter/foundation.dart';

import '../player_state.dart';
import '../lyrics_timeline.dart';

final class LyricClock extends ValueNotifier<Duration> {
  LyricClock() : super(Duration.zero);
  Duration _elapsed = Duration.zero;
  Duration _anchor = Duration.zero;
  PlayerState _state = const PlayerState();

  void synchronize(PlayerState state) {
    _state = state;
    _anchor = _elapsed;
    value = lyricTimelinePosition(state.position, state.lyricOffset);
  }

  void tick(Duration elapsed) {
    if (elapsed < _elapsed) _anchor = Duration.zero;
    _elapsed = elapsed;
    var position = _state.position;
    if (_state.isPlaybackActive &&
        _state.processing == PlayerProcessing.ready) {
      position += Duration(
        microseconds: ((elapsed - _anchor).inMicroseconds * _state.playbackRate)
            .round(),
      );
    }
    if (_state.duration > Duration.zero && position > _state.duration) {
      position = _state.duration;
    }
    value = lyricTimelinePosition(position, _state.lyricOffset);
  }
}
