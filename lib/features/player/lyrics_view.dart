import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
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
import 'lyrics/lyric_clock.dart';
import 'lyrics/timed_lyric_text.dart';
import 'package:flutter/scheduler.dart';

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

final class _LyricsViewState extends State<LyricsView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _clock = LyricClock();
  late final Ticker _ticker;
  var _clockIndex = -1;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock.synchronize(widget.state);
    _ticker = createTicker((elapsed) {
      _clock.tick(elapsed);
      final index = activeLyricIndex(_timelineLines, _clock.value);
      if (index != _clockIndex) setState(() => _clockIndex = index);
    });
  }

  void _syncTicker() {
    final running =
        _foreground &&
        widget.state.isPlaybackActive &&
        widget.state.processing == PlayerProcessing.ready &&
        TickerMode.valuesOf(context).enabled &&
        !AppGlassPolicyScope.policyOf(context).reduceMotion;
    if (running && !_ticker.isActive) _ticker.start();
    if (!running && _ticker.isActive) _ticker.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _clock.synchronize(widget.state);
    _syncTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _clock.synchronize(widget.state);
    _syncTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

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
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
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
        (lyrics.original.isEmpty &&
            (lyrics.translation?.isEmpty ?? true) &&
            (lyrics.verbatim?.isEmpty ?? true))) {
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
    final active = activeLyricIndex(lines, _clock.value);
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
        final selected = line.agent != null && line.end != null
            ? _clock.value >= line.time && _clock.value < line.end!
            : index == active;
        final lineAlign = line.agent == 'v2' ? TextAlign.right : textAlign;
        String displayText(String value) =>
            state.useTraditionalLyrics ? toTraditionalChinese(value) : value;
        Widget auxiliaryText(String value) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            displayText(value),
            textAlign: lineAlign,
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
          LyricAuxiliaryOrder.romanizationAbove => [
            if (translation != null) auxiliaryText(translation),
          ],
        };
        final seekPosition = lyricSeekPosition(
          lineTime: line.time,
          offset: state.lyricOffset,
          duration: state.duration,
        );
        return _LyricStagger(
          active: active,
          index: index,
          enabled: _following && !reduceMotion,
          child: AnimatedDefaultTextStyle(
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
                        if (state.lyricAuxiliaryOrder ==
                                LyricAuxiliaryOrder.romanizationAbove &&
                            romanization != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: auxiliaryText(romanization),
                          ),
                        if (line.words.isEmpty)
                          Text(
                            displayText(line.text.isEmpty ? '•••' : line.text),
                            key: selected ? ValueKey('lyrics-$index') : null,
                            textAlign: lineAlign,
                          )
                        else
                          Builder(
                            builder: (context) => TimedLyricText(
                              key: selected ? ValueKey('lyrics-$index') : null,
                              line: line,
                              clock: _clock,
                              active: selected,
                              style: DefaultTextStyle.of(context).style,
                              textAlign: lineAlign,
                              displayText: displayText,
                            ),
                          ),
                        if (line.background case final bg?) ...[
                          const SizedBox(height: 4),
                          TimedLyricText(
                            line: bg,
                            clock: _clock,
                            active:
                                _clock.value >= bg.time &&
                                _clock.value < (bg.end ?? line.end ?? bg.time),
                            style: AppTypography.metadata.copyWith(
                              color:
                                  widget.foreground ??
                                  AppTokens.of(context).foreground,
                            ),
                            textAlign: lineAlign,
                            displayText: displayText,
                          ),
                          if (state.showTranslation && bg.translation != null)
                            auxiliaryText(bg.translation!),
                          if (state.showRomanization && bg.romanization != null)
                            auxiliaryText(bg.romanization!),
                        ],
                        ...auxiliary,
                      ],
                    ),
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

final class _LyricStagger extends StatefulWidget {
  const _LyricStagger({
    required this.active,
    required this.index,
    required this.enabled,
    required this.child,
  });
  final int active;
  final int index;
  final bool enabled;
  final Widget child;

  @override
  State<_LyricStagger> createState() => _LyricStaggerState();
}

final class _LyricStaggerState extends State<_LyricStagger>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController.unbounded(vsync: this);
  Timer? _delay;

  @override
  void didUpdateWidget(covariant _LyricStagger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _delay?.cancel();
      _motion.stop();
      _motion.value = 0;
      return;
    }
    final delta = widget.active - oldWidget.active;
    if (delta == 0) return;
    _delay?.cancel();
    _motion.stop();
    if (oldWidget.active < 0 || delta.abs() > 10) {
      _motion.value = 0;
      return;
    }
    final distance = (widget.index - widget.active).abs().clamp(0, 6);
    _motion.value = (_motion.value + delta.sign * distance * 4).clamp(-32, 32);
    _delay = Timer(Duration(milliseconds: distance * 35), () {
      if (!mounted || !widget.enabled) return;
      _motion.animateWith(
        SpringSimulation(
          SpringDescription.withDampingRatio(
            mass: 1,
            stiffness: 200,
            ratio: .9,
          ),
          _motion.value,
          0,
          0,
          tolerance: const Tolerance(distance: .05, velocity: .1),
        ),
      );
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    builder: (_, child) =>
        Transform.translate(offset: Offset(0, _motion.value), child: child),
    child: widget.child,
  );
}
