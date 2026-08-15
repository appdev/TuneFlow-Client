import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../../design/app_glass_policy.dart';
import '../../design/components/app_states.dart';
import '../../design/design_tokens.dart';
import 'lyrics_timeline.dart';
import 'player_state.dart';

final class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.state,
    this.verticalPadding = 120,
    this.edgeFade = false,
    this.horizontalPadding = 20,
    this.textAlign = TextAlign.center,
    this.foreground,
    this.mutedForeground,
  });

  final PlayerState state;
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
  int? _lastActive;

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
    });
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
    final lines = parseLyricsTimeline(lyrics);
    if (lines.isEmpty) {
      return ScrollConfiguration(
        key: const Key('lyrics-scroll-configuration'),
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: widget.horizontalPadding,
            vertical: 20,
          ),
          child: SelectableText(lyrics.original, textAlign: widget.textAlign),
        ),
      );
    }
    final active = activeLyricIndex(lines, state.position);
    final reduceMotion = AppGlassPolicyScope.policyOf(context).reduceMotion;
    _followActiveLine(
      lyrics: lyrics,
      active: active,
      reduceMotion: reduceMotion,
    );
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
        return AnimatedDefaultTextStyle(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          style: AppTypography.body.copyWith(
            fontSize: selected ? 28 : 20,
            height: 1.35,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected
                ? widget.foreground ?? AppTokens.of(context).foreground
                : widget.mutedForeground ?? AppTokens.of(context).muted,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: widget.textAlign == TextAlign.center
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  line.text,
                  key: selected ? ValueKey('lyrics-$active') : null,
                  textAlign: widget.textAlign,
                ),
                if (state.showTranslation)
                  if (line.translation case final translation?)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        translation,
                        textAlign: widget.textAlign,
                        style: AppTypography.metadata.copyWith(
                          color:
                              widget.mutedForeground ??
                              AppTokens.of(context).foregroundSecondary,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
    final scrollbarFreeList = ScrollConfiguration(
      key: const Key('lyrics-scroll-configuration'),
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: list,
    );
    if (!widget.edgeFade) return scrollbarFreeList;
    return ShaderMask(
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
  }
}
