import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/features/player/lyrics_timeline.dart';

void main() {
  test('parses multiple LRC timestamps and aligns translated lines', () {
    final lines = parseLyricsTimeline(
      const Lyrics(
        original: '[00:01.20]First\n[00:03.005][00:04.00]Second',
        translation: '[00:01.20]第一句\n[00:03.005]第二句',
        romanization: '[00:01.20]Dai ichi\n[00:04.00]Dai ni',
      ),
    );

    expect(lines.map((line) => line.time.inMilliseconds), [1200, 3005, 4000]);
    expect(lines.first.translation, '第一句');
    expect(lines.first.romanization, 'Dai ichi');
    expect(lines[1].translation, '第二句');
    expect(lines[1].romanization, isNull);
    expect(lines.last.translation, isNull);
    expect(lines.last.romanization, 'Dai ni');
  });

  test('active lyric index follows playback position at boundaries', () {
    const lines = [
      TimedLyricLine(time: Duration(seconds: 1), text: 'a'),
      TimedLyricLine(time: Duration(seconds: 3), text: 'b'),
    ];

    expect(activeLyricIndex(lines, const Duration(milliseconds: 999)), -1);
    expect(activeLyricIndex(lines, const Duration(seconds: 1)), 0);
    expect(activeLyricIndex(lines, const Duration(seconds: 4)), 1);
  });

  test('keeps the last non-empty value for duplicate timestamps', () {
    final lines = parseLyricsTimeline(
      const Lyrics(original: '[00:01]First\n[00:01]\n[00:01]Last'),
    );

    expect(lines.single.text, 'Last');
  });

  test('applies lyric offsets and clamps seek positions', () {
    expect(
      lyricTimelinePosition(
        const Duration(seconds: 3),
        const Duration(milliseconds: 500),
      ),
      const Duration(milliseconds: 2500),
    );
    expect(
      lyricTimelinePosition(
        const Duration(milliseconds: 200),
        const Duration(milliseconds: 500),
      ),
      Duration.zero,
    );
    expect(
      lyricTimelinePosition(
        const Duration(seconds: 3),
        const Duration(milliseconds: -500),
      ),
      const Duration(milliseconds: 3500),
    );
    expect(
      lyricSeekPosition(
        lineTime: const Duration(milliseconds: 200),
        offset: const Duration(milliseconds: -500),
        duration: const Duration(seconds: 10),
      ),
      Duration.zero,
    );
    expect(
      lyricSeekPosition(
        lineTime: const Duration(seconds: 9),
        offset: const Duration(seconds: 2),
        duration: const Duration(seconds: 10),
      ),
      const Duration(seconds: 10),
    );
  });
}
