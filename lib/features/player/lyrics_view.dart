import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../../design/app_glass_policy.dart';
import '../../design/components/app_states.dart';
import '../../design/design_tokens.dart';
import '../../storage/app_preferences.dart';
import 'chinese_script_converter.dart';
import 'lyrics_timeline.dart';
import 'player_state.dart';

final class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.state,
    required this.onSeek,
    this.verticalPadding = 120,
    this.edgeFade = false,
    this.horizontalPadding = 20,
    this.textAlign = TextAlign.center,
    this.foreground,
    this.mutedForeground,
  });

  final PlayerState state;
  final ValueChanged<Duration> onSeek;
  final double verticalPadding;
  final bool edgeFade;
  final double horizontalPadding;
  final TextAlign textAlign;
  final Color? foreground;
  final Color? mutedForeground;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

final class _LyricsViewState extends State<LyricsView> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  Lyrics? _lastLyrics;
  Lyrics? _timelineSource;
  List<TimedLyricLine> _timelineLines = const [];
  String? _lastTrackKey;
  int? _lastActive;
  bool _following = true;
  bool _programmaticScroll = false;

  void _followActiveLine({
    required Lyrics lyrics,
    required int active,
    required bool reduceMotion,
  }) {
    if (identical(_lastLyrics, lyrics) && _lastActive == active) return;
    _lastLyrics = lyrics;
    _lastActive = active;
    if (active < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_itemScrollController.isAttached) return;
      _programmaticScroll = true;
      if (reduceMotion) {
        _itemScrollController.jumpTo(index: active, alignment: .35);
      } else {
        await _itemScrollController.scrollTo(
          index: active,
          alignment: .35,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          opacityAnimationWeights: const [20, 20, 60],
        );
      }
      if (mounted) _programmaticScroll = false;
    });
  }

  void _resumeFollowing(int active, bool reduceMotion) {
    setState(() {
      _following = true;
      _lastActive = null;
    });
    final lyrics = widget.state.lyrics;
    if (lyrics != null) {
      _followActiveLine(
        lyrics: lyrics,
        active: active,
        reduceMotion: reduceMotion,
      );
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_programmaticScroll && _following && event.delta.dy.abs() > 0) {
      setState(() => _following = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.lyricsError != null) {
      return const AppEmptyState(
        message: '歌词暂不可用',
        icon: LucideIcons.messageSquareText,
      );
    }
    final lyrics = state.lyrics;
    if (lyrics == null ||
        (lyrics.original.isEmpty && (lyrics.translation?.isEmpty ?? true))) {
      return const AppEmptyState(message: '暂无歌词');
    }
    if (!identical(_timelineSource, lyrics)) {
      _timelineSource = lyrics;
      _timelineLines = parseLyricsTimeline(lyrics);
    }
    final lines = _timelineLines;
    final track = state.current;
    final trackKey = track == null ? null : '${track.source}\u0000${track.id}';
    if (_lastTrackKey != trackKey || !identical(_lastLyrics, lyrics)) {
      _lastTrackKey = trackKey;
      _lastLyrics = lyrics;
      _lastActive = null;
      _following = true;
    }
    if (lines.isEmpty) {
      return ScrollConfiguration(
        key: const Key('lyrics-scroll-configuration'),
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: widget.horizontalPadding,
            vertical: 20,
          ),
          child: SelectableText(
            state.useTraditionalLyrics
                ? toTraditionalChinese(lyrics.original)
                : lyrics.original,
            textAlign: widget.textAlign,
          ),
        ),
      );
    }
    final active = activeLyricIndex(
      lines,
      lyricTimelinePosition(state.position, state.lyricOffset),
    );
    final reduceMotion = AppGlassPolicyScope.policyOf(context).reduceMotion;
    if (_following) {
      _followActiveLine(
        lyrics: lyrics,
        active: active,
        reduceMotion: reduceMotion,
      );
    }
    final textAlign = switch (state.lyricAlignment) {
      LyricAlignment.adaptive => widget.textAlign,
      LyricAlignment.left => TextAlign.left,
      LyricAlignment.center => TextAlign.center,
      LyricAlignment.right => TextAlign.right,
    };
    final (inactiveSize, activeSize) = switch (state.lyricFontSize) {
      LyricFontSize.small => (17.0, 24.0),
      LyricFontSize.standard => (20.0, 28.0),
      LyricFontSize.large => (23.0, 32.0),
    };
    final list = ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      padding: EdgeInsets.symmetric(
        horizontal: widget.horizontalPadding,
        vertical: widget.verticalPadding,
      ),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        final selected = index == active;
        String displayText(String value) =>
            state.useTraditionalLyrics ? toTraditionalChinese(value) : value;
        Widget auxiliaryText(String value) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            displayText(value),
            textAlign: textAlign,
            style: AppTypography.metadata.copyWith(
              color:
                  widget.mutedForeground ??
                  AppTokens.of(context).foregroundSecondary,
            ),
          ),
        );
        final translation = state.showTranslation ? line.translation : null;
        final romanization = state.showRomanization ? line.romanization : null;
        final auxiliary = switch (state.lyricAuxiliaryOrder) {
          LyricAuxiliaryOrder.translationFirst => [
            if (translation != null) auxiliaryText(translation),
            if (romanization != null) auxiliaryText(romanization),
          ],
          LyricAuxiliaryOrder.romanizationFirst => [
            if (romanization != null) auxiliaryText(romanization),
            if (translation != null) auxiliaryText(translation),
          ],
        };
        final seekPosition = lyricSeekPosition(
          lineTime: line.time,
          offset: state.lyricOffset,
          duration: state.duration,
        );
        return AnimatedDefaultTextStyle(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          style: AppTypography.body.copyWith(
            fontSize: selected && state.emphasizeActiveLyric
                ? activeSize
                : inactiveSize,
            height: 1.35,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected
                ? widget.foreground ?? AppTokens.of(context).foreground
                : widget.mutedForeground ?? AppTokens.of(context).muted,
          ),
          child: Semantics(
            button: true,
            label: '跳转到 ${displayText(line.text)}',
            child: InkWell(
              onTap: () {
                widget.onSeek(seekPosition);
                _resumeFollowing(index, reduceMotion);
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: switch (textAlign) {
                      TextAlign.center => CrossAxisAlignment.center,
                      TextAlign.right ||
                      TextAlign.end => CrossAxisAlignment.end,
                      _ => CrossAxisAlignment.start,
                    },
                    children: [
                      Text(
                        displayText(line.text),
                        key: selected ? ValueKey('lyrics-$active') : null,
                        textAlign: textAlign,
                      ),
                      ...auxiliary,
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    final scrollbarFreeList = ScrollConfiguration(
      key: const Key('lyrics-scroll-configuration'),
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Listener(onPointerMove: _handlePointerMove, child: list),
    );
    final fadedList = !widget.edgeFade
        ? scrollbarFreeList
        : ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0, .08, .92, 1],
            ).createShader(bounds),
            child: scrollbarFreeList,
          );
    return Stack(
      children: [
        Positioned.fill(child: fadedList),
        if (!_following)
          Positioned(
            right: 8,
            bottom: 8,
            child: ShadButton.secondary(
              key: const Key('lyrics-return-to-current'),
              height: 44,
              onPressed: () => _resumeFollowing(active, reduceMotion),
              child: const Text('回到当前歌词'),
            ),
          ),
      ],
    );
  }
}
