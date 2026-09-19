import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/features/player/lyrics_view.dart';
import 'package:musicfree_service_client/features/player/player_state.dart';
import 'package:musicfree_service_client/storage/app_preferences.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget harness(Widget child) => ShadApp.custom(
  theme: buildLightTheme(),
  appBuilder: (context) => MaterialApp(
    theme: Theme.of(context),
    home: Scaffold(body: ShadAppBuilder(child: child)),
  ),
);

PlayerState lyricState({
  Duration position = const Duration(seconds: 1),
  Duration offset = Duration.zero,
  bool showTranslation = true,
  bool showRomanization = true,
  String trackId = 'one',
  LyricFontSize fontSize = LyricFontSize.standard,
  LyricAlignment alignment = LyricAlignment.adaptive,
  LyricAuxiliaryOrder auxiliaryOrder = LyricAuxiliaryOrder.translationFirst,
  bool useTraditional = false,
  bool emphasizeActive = true,
}) => PlayerState(
  queue: [
    Track.fromJson({'id': trackId, 'name': trackId, 'source': 'kw'}),
  ],
  currentIndex: 0,
  position: position,
  duration: const Duration(seconds: 30),
  lyricOffset: offset,
  showTranslation: showTranslation,
  showRomanization: showRomanization,
  lyricFontSize: fontSize,
  lyricAlignment: alignment,
  lyricAuxiliaryOrder: auxiliaryOrder,
  useTraditionalLyrics: useTraditional,
  emphasizeActiveLyric: emphasizeActive,
  lyrics: const Lyrics(
    original: '[00:01]First\n[00:05]Second\n[00:10]Third',
    translation: '[00:01]第一句',
    romanization: '[00:01]Dai ichi',
  ),
);

void main() {
  testWidgets('renders auxiliary tracks and taps a timed line with offset', (
    tester,
  ) async {
    Duration? seek;
    await tester.pumpWidget(
      harness(
        SizedBox(
          height: 500,
          child: LyricsView(
            state: lyricState(offset: const Duration(milliseconds: 500)),
            onSeek: (value) => seek = value,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('第一句'), findsOneWidget);
    expect(find.text('Dai ichi'), findsOneWidget);
    await tester.tap(find.text('Second'));
    await tester.pump();

    expect(seek, const Duration(milliseconds: 5500));
  });

  testWidgets('user browsing pauses follow and exposes recovery', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        SizedBox(
          height: 260,
          child: LyricsView(state: lyricState(), onSeek: (_) {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -120),
    );
    await tester.pump();

    expect(find.byKey(const Key('lyrics-return-to-current')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lyrics-return-to-current')));
    await tester.pump();
    expect(find.byKey(const Key('lyrics-return-to-current')), findsNothing);
  });

  testWidgets('untimed lyrics stay selectable and are not seekable', (
    tester,
  ) async {
    var seekCount = 0;
    await tester.pumpWidget(
      harness(
        SizedBox(
          height: 260,
          child: LyricsView(
            state: const PlayerState(
              lyrics: Lyrics(original: 'Plain untimed lyrics'),
            ),
            onSeek: (_) => seekCount++,
          ),
        ),
      ),
    );

    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('Plain untimed lyrics'), findsOneWidget);
    expect(seekCount, 0);
  });

  testWidgets('font, alignment and auxiliary visibility follow player state', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        SizedBox(
          height: 500,
          child: LyricsView(
            state: lyricState(
              showTranslation: false,
              showRomanization: false,
              fontSize: LyricFontSize.large,
              alignment: LyricAlignment.left,
            ),
            onSeek: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('第一句'), findsNothing);
    expect(find.text('Dai ichi'), findsNothing);
    final activeTexts = tester.widgetList<Text>(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.key == const ValueKey('lyrics-0'),
      ),
    );
    expect(activeTexts, isNotEmpty);
    expect(activeTexts.first.textAlign, TextAlign.left);
    final activeStyle = tester
        .widgetList<AnimatedDefaultTextStyle>(
          find.ancestor(
            of: find.byKey(const ValueKey('lyrics-0')),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        )
        .firstWhere((style) => style.style.fontSize == 32);
    expect(activeStyle.style.fontSize, 32);
  });

  testWidgets('changing tracks restores automatic following', (tester) async {
    final state = ValueNotifier<PlayerState>(lyricState());
    addTearDown(state.dispose);
    await tester.pumpWidget(
      harness(
        SizedBox(
          height: 260,
          child: ValueListenableBuilder<PlayerState>(
            valueListenable: state,
            builder: (context, value, _) =>
                LyricsView(state: value, onSeek: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -120),
    );
    await tester.pump();
    expect(find.byKey(const Key('lyrics-return-to-current')), findsOneWidget);

    state.value = lyricState(trackId: 'two');
    await tester.pump();
    expect(find.byKey(const Key('lyrics-return-to-current')), findsNothing);
  });

  testWidgets('applies right alignment and configured auxiliary order', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        SizedBox(
          height: 500,
          child: LyricsView(
            state: lyricState(
              alignment: LyricAlignment.right,
              auxiliaryOrder: LyricAuxiliaryOrder.romanizationFirst,
            ),
            onSeek: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widgetList<Text>(find.text('First')).first.textAlign,
      TextAlign.right,
    );
    expect(
      tester.getTopLeft(find.text('Dai ichi').first).dy,
      lessThan(tester.getTopLeft(find.text('第一句').first).dy),
    );
  });

  testWidgets('converts displayed lyrics and can disable active-line zoom', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        SizedBox(
          height: 500,
          child: LyricsView(
            state: lyricState(useTraditional: true, emphasizeActive: false)
                .copyWith(
                  lyrics: const Lyrics(
                    original: '[00:01]专业后台',
                    translation: '[00:01]简体歌词',
                  ),
                ),
            onSeek: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('專業後台'), findsWidgets);
    expect(find.text('簡體歌詞'), findsWidgets);
    final style = tester
        .widgetList<AnimatedDefaultTextStyle>(
          find.ancestor(
            of: find.byKey(const ValueKey('lyrics-0')),
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        )
        .firstWhere((style) => style.style.fontSize == 20);
    expect(style.style.fontSize, 20);
  });
}
