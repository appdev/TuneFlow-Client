import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/features/player/lyrics_view.dart';
import 'package:musicfree_service_client/features/player/player_controller.dart';
import 'package:musicfree_service_client/features/player/player_shortcuts.dart';
import 'package:musicfree_service_client/features/player/player_state.dart';
import 'package:musicfree_service_client/storage/app_preferences.dart';
import 'lyrics_view_test.dart' show harness, lyricState;
import 'player_controller_test.dart' show FakeAudio, FakeResolver, track;

void main() {
  testWidgets('word lyrics wrap, seek, and retain romanization above original', (
    tester,
  ) async {
    Duration? sought;
    await tester.pumpWidget(
      harness(
        SizedBox(
          width: 220,
          height: 420,
          child: LyricsView(
            state:
                lyricState(
                  auxiliaryOrder: LyricAuxiliaryOrder.romanizationAbove,
                ).copyWith(
                  lyrics: const Lyrics(
                    original:
                        '[00:01]A long line that wraps across the narrow viewport',
                    verbatim:
                        '[00:01]<00:01>A long line that wraps <00:03>across the narrow viewport<00:05>',
                    romanization: '[00:01]romanization',
                    translation: '[00:01]译文',
                  ),
                ),
            onSeek: (position) => sought = position,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('romanization')).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('lyrics-0'))).dy),
    );
    await tester.tap(find.byKey(const ValueKey('lyrics-0')));
    await tester.pump();
    expect(sought, const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard playback respects text input focus', (tester) async {
    final audio = FakeAudio();
    final player = PlayerController(resolver: FakeResolver(), audio: audio);
    final inputFocus = FocusNode();
    await player.play(track('a'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerShortcuts(
            controller: player,
            child: TextField(focusNode: inputFocus),
          ),
        ),
      ),
    );
    audio.controller.add(
      const AudioSnapshot(processing: PlayerProcessing.ready),
    );
    await tester.pump();
    final resumes = audio.resumeCalls;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(audio.resumeCalls, resumes + 1);
    audio.controller.add(
      const AudioSnapshot(processing: PlayerProcessing.buffering),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(audio.pauseCalls, 1);
    inputFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(audio.resumeCalls, resumes + 1);
    expect(audio.pauseCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    inputFocus.dispose();
    player.dispose();
    await audio.controller.close();
  });
}
