import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../api/models.dart';

const maxTrackPlaybackStateEntries = 500;
const minLyricOffsetMilliseconds = -5000;
const maxLyricOffsetMilliseconds = 5000;

final class TrackPlaybackState {
  const TrackPlaybackState({
    this.lyricOffset = Duration.zero,
    this.resumePosition,
    required this.lastAccessedAt,
  });

  final Duration lyricOffset;
  final Duration? resumePosition;
  final DateTime lastAccessedAt;
}

abstract interface class TrackPlaybackStateStore {
  Future<TrackPlaybackState?> read(Track track);
  Future<void> writeLyricOffset(Track track, Duration offset);
  Future<void> writeResumePosition(Track track, Duration position);
  Future<void> clearResumePosition(Track track);
}

final class SharedTrackPlaybackStateStore implements TrackPlaybackStateStore {
  SharedTrackPlaybackStateStore({
    SharedPreferencesAsync? preferences,
    DateTime Function()? clock,
  }) : _preferences = preferences ?? _tryPreferences(),
       _clock = clock ?? DateTime.now;

  static const _storageKey = 'track_playback_state_v1';

  final SharedPreferencesAsync? _preferences;
  final DateTime Function() _clock;
  Map<String, Map<String, Object?>> _memory = {};
  bool _loaded = false;
  Future<void> _operation = Future<void>.value();

  @override
  Future<TrackPlaybackState?> read(Track track) => _enqueue(() async {
    final entries = await _readEntries();
    final key = _trackKey(track);
    final entry = entries[key];
    if (entry == null) return null;
    final state = _decodeEntry(entry);
    if (state == null) return null;
    entry['a'] = _clock().millisecondsSinceEpoch;
    _memory[key] = Map<String, Object?>.from(entry);
    return state;
  });

  @override
  Future<void> writeLyricOffset(Track track, Duration offset) async {
    final milliseconds = offset.inMilliseconds.clamp(
      minLyricOffsetMilliseconds,
      maxLyricOffsetMilliseconds,
    );
    await _enqueue(
      () => _mutate(track, (entry) {
        if (milliseconds == 0) {
          entry.remove('o');
        } else {
          entry['o'] = milliseconds;
        }
      }),
    );
  }

  @override
  Future<void> writeResumePosition(Track track, Duration position) => _enqueue(
    () => _mutate(track, (entry) => entry['p'] = position.inMilliseconds),
  );

  @override
  Future<void> clearResumePosition(Track track) =>
      _enqueue(() => _mutate(track, (entry) => entry.remove('p')));

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _operation.then<T>((_) => action());
    _operation = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<void> _mutate(
    Track track,
    void Function(Map<String, Object?> entry) update,
  ) async {
    final entries = await _readEntries();
    final key = _trackKey(track);
    final entry = entries[key] ?? <String, Object?>{};
    update(entry);
    entry['a'] = _clock().millisecondsSinceEpoch;
    if (!entry.containsKey('o') && !entry.containsKey('p')) {
      entries.remove(key);
    } else {
      entries[key] = entry;
    }
    await _writeEntries(entries);
  }

  Future<Map<String, Map<String, Object?>>> _readEntries() async {
    if (_loaded) {
      return _memory.map(
        (key, value) => MapEntry(key, Map<String, Object?>.from(value)),
      );
    }
    final preferences = _preferences;
    if (preferences == null) {
      _loaded = true;
      return _memory.map(
        (key, value) => MapEntry(key, Map<String, Object?>.from(value)),
      );
    }
    final encoded = await preferences.getString(_storageKey);
    if (encoded == null) {
      _loaded = true;
      return {};
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        _loaded = true;
        return {};
      }
      final entries = <String, Map<String, Object?>>{};
      for (final item in decoded.entries) {
        if (item.key is String && item.value is Map) {
          entries[item.key as String] = Map<String, Object?>.from(
            item.value as Map,
          );
        }
      }
      _memory = entries.map(
        (key, value) => MapEntry(key, Map<String, Object?>.from(value)),
      );
      _loaded = true;
      return entries;
    } on Object {
      _loaded = true;
      return {};
    }
  }

  Future<void> _writeEntries(Map<String, Map<String, Object?>> entries) async {
    if (entries.length > maxTrackPlaybackStateEntries) {
      final keys = entries.keys.toList()
        ..sort((left, right) {
          final leftAccess = entries[left]?['a'];
          final rightAccess = entries[right]?['a'];
          return (rightAccess is num ? rightAccess.toInt() : 0).compareTo(
            leftAccess is num ? leftAccess.toInt() : 0,
          );
        });
      for (final key in keys.skip(maxTrackPlaybackStateEntries)) {
        entries.remove(key);
      }
    }
    _memory = entries.map(
      (key, value) => MapEntry(key, Map<String, Object?>.from(value)),
    );
    _loaded = true;
    await _preferences?.setString(_storageKey, jsonEncode(entries));
  }

  TrackPlaybackState? _decodeEntry(Map<String, Object?> entry) {
    final offset = entry['o'];
    final position = entry['p'];
    final accessed = entry['a'];
    if (offset != null && offset is! num ||
        position != null && position is! num ||
        accessed is! num) {
      return null;
    }
    final offsetMilliseconds = offset is num
        ? offset.toInt().clamp(
            minLyricOffsetMilliseconds,
            maxLyricOffsetMilliseconds,
          )
        : 0;
    return TrackPlaybackState(
      lyricOffset: Duration(milliseconds: offsetMilliseconds),
      resumePosition: position == null
          ? null
          : Duration(milliseconds: (position as num).toInt()),
      lastAccessedAt: DateTime.fromMillisecondsSinceEpoch(accessed.toInt()),
    );
  }

  String _trackKey(Track track) => jsonEncode([track.source, track.id]);
}

SharedPreferencesAsync? _tryPreferences() {
  try {
    return SharedPreferencesAsync();
  } on StateError {
    return null;
  }
}
