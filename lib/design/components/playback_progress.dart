import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../design_tokens.dart';

final class PlaybackProgress extends StatelessWidget {
  const PlaybackProgress({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.compact = false,
    this.hitExtent = 28,
    this.trackHeight = 4,
    this.thumbDiameter = 12,
    this.activeTrackColor,
    this.inactiveTrackColor,
    this.labelColor,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final bool compact;
  final double hitExtent;
  final double trackHeight;
  final double thumbDiameter;
  final Color? activeTrackColor;
  final Color? inactiveTrackColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final durationMs = duration.inMilliseconds;
    final maximum = durationMs <= 0 ? 1.0 : durationMs.toDouble();
    final value = position.inMilliseconds.clamp(0, maximum.toInt()).toDouble();
    final tokens = AppTokens.of(context);
    final timeStyle = AppTypography.counter.copyWith(
      color: labelColor ?? tokens.muted,
    );
    return SizedBox(
      key: const Key('playback-progress'),
      height: hitExtent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 42,
            child: Text(
              _clock(position),
              textAlign: TextAlign.right,
              style: timeStyle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              key: const Key('playback-progress-hit-area'),
              height: hitExtent,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  void seekAt(double dx) {
                    if (durationMs <= 0) return;
                    final fraction = (dx / constraints.maxWidth).clamp(
                      0.0,
                      1.0,
                    );
                    onSeek(
                      Duration(milliseconds: (maximum * fraction).round()),
                    );
                  }

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      ShadSlider(
                        key: ValueKey((value, maximum)),
                        initialValue: value,
                        max: maximum,
                        enabled: durationMs > 0,
                        trackHeight: trackHeight,
                        thumbRadius: thumbDiameter / 2,
                        activeTrackColor: activeTrackColor ?? tokens.accent,
                        inactiveTrackColor:
                            inactiveTrackColor ?? tokens.playbackTrackInactive,
                        onChanged: (next) =>
                            onSeek(Duration(milliseconds: next.round())),
                      ),
                      Positioned.fill(
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: durationMs > 0
                              ? (event) => seekAt(event.localPosition.dx)
                              : null,
                          onPointerMove: durationMs > 0
                              ? (event) => seekAt(event.localPosition.dx)
                              : null,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 42, child: Text(_clock(duration), style: timeStyle)),
        ],
      ),
    );
  }
}

String _clock(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
