import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/features/player/track_playback_state_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Track track(String source, String id) =>
    Track.fromJson({'id': id, 'name': id, 'source': source});

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('round trips independent offset and resume values', () async {
    final store = SharedTrackPlaybackStateStore();
    final value = track('source', 'id');

    await store.writeLyricOffset(value, const Duration(milliseconds: 650));
    await store.writeResumePosition(value, const Duration(seconds: 42));

    final state = await store.read(value);
    expect(state?.lyricOffset, const Duration(milliseconds: 650));
    expect(state?.resumePosition, const Duration(seconds: 42));

    await store.writeLyricOffset(value, Duration.zero);
    await store.clearResumePosition(value);
    expect(await store.read(value), isNull);
  });

  test('logical track keys cannot collide on delimiters', () async {
    final store = SharedTrackPlaybackStateStore();
    final first = track('a:b', 'c');
    final second = track('a', 'b:c');

    await store.writeLyricOffset(first, const Duration(milliseconds: 100));
    await store.writeLyricOffset(second, const Duration(milliseconds: 200));

    expect(
      (await store.read(first))?.lyricOffset,
      const Duration(milliseconds: 100),
    );
    expect(
      (await store.read(second))?.lyricOffset,
      const Duration(milliseconds: 200),
    );
  });

  test('concurrent updates preserve both fields and other tracks', () async {
    final store = SharedTrackPlaybackStateStore();
    final first = track('kw', 'a');
    final second = track('kw', 'b');
    await Future.wait([
      store.writeLyricOffset(first, const Duration(milliseconds: 300)),
      store.writeResumePosition(first, const Duration(seconds: 42)),
      store.writeResumePosition(second, const Duration(seconds: 25)),
    ]);
    final reloaded = SharedTrackPlaybackStateStore();
    expect(
      (await reloaded.read(first))?.lyricOffset,
      const Duration(milliseconds: 300),
    );
    expect(
      (await reloaded.read(first))?.resumePosition,
      const Duration(seconds: 42),
    );
    expect(
      (await reloaded.read(second))?.resumePosition,
      const Duration(seconds: 25),
    );
  });

  test('clamps offsets and ignores malformed storage', () async {
    final store = SharedTrackPlaybackStateStore();
    final value = track('source', 'id');

    await store.writeLyricOffset(value, const Duration(seconds: 20));
    expect(
      (await store.read(value))?.lyricOffset,
      const Duration(milliseconds: maxLyricOffsetMilliseconds),
    );

    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          'track_playback_state_v1': '{broken',
        });
    expect(await SharedTrackPlaybackStateStore().read(value), isNull);
  });

  test('evicts the least recently used entry above the bound', () async {
    var tick = 0;
    final store = SharedTrackPlaybackStateStore(
      clock: () => DateTime.fromMillisecondsSinceEpoch(++tick),
    );

    for (var index = 0; index <= maxTrackPlaybackStateEntries; index++) {
      await store.writeLyricOffset(
        track('source', '$index'),
        const Duration(milliseconds: 100),
      );
    }

    expect(await store.read(track('source', '0')), isNull);
    expect(await store.read(track('source', '500')), isNotNull);
  });
}
