import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/features/player/lyrics/lyric_clock.dart';
import 'package:musicfree_service_client/features/player/lyrics_timeline.dart';
import 'package:musicfree_service_client/features/player/player_state.dart';

void main() {
  test('TTML infers missing word ends and retains an unpaired background', () {
    final lines = parseLyricsTimeline(
      const Lyrics(
        original: '',
        verbatim:
            '<tt><body><p begin="00:01" end="00:05"><span begin="00:01">a</span>'
            '<span begin="00:03">b</span></p>'
            '<p begin="00:06" end="00:08"><span role="x-bg" begin="00:06" end="00:08">voice</span></p>'
            '</body></tt>',
      ),
    );
    expect(lines.first.words.first.end, const Duration(seconds: 3));
    expect(lines.last.background?.text, 'voice');
  });
  test(
    'verbatim drives words while server auxiliary tracks retain their identity',
    () {
      final lines = parseLyricsTimeline(
        const Lyrics(
          original: '[00:01]Hello world',
          verbatim: '[00:01]<00:01>Hello <00:02>world<00:04>',
          translation: '[00:01.10]你好 世界',
          romanization: '[00:01]he lo',
        ),
      );
      expect(lines.single.text, 'Hello world');
      expect(lines.single.translation, '你好 世界');
      expect(lines.single.romanization, 'he lo');
      expect(lines.single.words.last.end, const Duration(seconds: 4));
      expect(lines.single.words.last.progress(const Duration(seconds: 3)), .5);
    },
  );

  test(
    'repeated timestamps stay separate and malformed verbatim falls back',
    () {
      final lines = parseLyricsTimeline(
        const Lyrics(original: '[00:01][00:03]Repeated', verbatim: '<broken'),
      );
      expect(lines.map((l) => l.time.inSeconds), [1, 3]);
      expect(lines.every((l) => l.words.isEmpty), isTrue);
    },
  );

  test('verbatim-only and offset-tag lyrics are available', () {
    final lines = parseLyricsTimeline(
      const Lyrics(
        original: '',
        verbatim: '[offset:200]\n[00:01]你[00:02]好[00:03]',
      ),
    );
    expect(lines.single.time.inMilliseconds, 800);
    expect(lines.single.words.last.end.inMilliseconds, 2800);
  });

  test('TTML preserves duet, exact word end and background lyrics', () {
    final lines = parseLyricsTimeline(
      const Lyrics(
        original: '',
        verbatim: '''
<tt xmlns:ttm="http://www.w3.org/ns/ttml#metadata">
<head><metadata><ttm:agent xml:id="a"/><ttm:agent xml:id="b"/></metadata></head>
<body><div><p begin="00:01" end="00:05" ttm:agent="a">
<span begin="00:01" end="00:02">你</span><span begin="00:03" end="00:04">好</span>
<span ttm:role="x-translation">Hello</span><span ttm:role="x-roman">ni hao</span>
<span ttm:role="x-bg" begin="00:02" end="00:05"><span begin="00:02" end="00:05">和声</span></span>
</p><p begin="00:03" end="00:06" ttm:agent="b"><span begin="00:03" end="00:06">对唱</span></p></div></body></tt>''',
      ),
    );
    expect(lines.map((l) => l.agent), ['v1', 'v2']);
    expect(lines.first.words.first.end, const Duration(seconds: 2));
    expect(lines.first.background?.text, '和声');
    expect(lines.first.translation, 'Hello');
    expect(lines.first.romanization, 'ni hao');
  });

  test('clock follows speed, freezes during buffering, resets after seek', () {
    final clock = LyricClock();
    addTearDown(clock.dispose);
    final state = const PlayerState(
      playing: true,
      processing: PlayerProcessing.ready,
      position: Duration(seconds: 1),
      duration: Duration(seconds: 30),
      playbackRate: 2,
    );
    clock.synchronize(state);
    clock.tick(const Duration(milliseconds: 500));
    expect(clock.value, const Duration(seconds: 2));
    clock.synchronize(
      state.copyWith(
        position: const Duration(seconds: 2),
        processing: PlayerProcessing.buffering,
      ),
    );
    clock.tick(const Duration(seconds: 4));
    expect(clock.value, const Duration(seconds: 2));
    clock.synchronize(
      state.copyWith(
        position: const Duration(seconds: 10),
        lyricOffset: const Duration(milliseconds: 500),
      ),
    );
    clock.tick(const Duration(milliseconds: 4500));
    expect(clock.value, const Duration(milliseconds: 10500));
    clock.synchronize(
      state.copyWith(playing: false, position: const Duration(seconds: 3)),
    );
    clock.tick(const Duration(seconds: 9));
    expect(clock.value, const Duration(seconds: 3));
  });
}
