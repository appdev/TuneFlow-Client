import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../design_tokens.dart';

final class PlaybackProgress extends StatefulWidget {
  const PlaybackProgress({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.trackIdentity,
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
  final Object? trackIdentity;
  final bool compact;
  final double hitExtent;
  final double trackHeight;
  final double thumbDiameter;
  final Color? activeTrackColor;
  final Color? inactiveTrackColor;
  final Color? labelColor;

  @override
  State<PlaybackProgress> createState() => _PlaybackProgressState();
}

final class _PlaybackProgressState extends State<PlaybackProgress> {
  late final slider = ShadSliderController(initialValue: _position);
  int? _pointer;
  double? _preview;

  double get _maximum => widget.duration > Duration.zero
      ? widget.duration.inMilliseconds.toDouble()
      : 1;
  double get _position =>
      widget.position.inMilliseconds.clamp(0, _maximum).toDouble();

  @override
  void didUpdateWidget(covariant PlaybackProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackIdentity != widget.trackIdentity ||
        oldWidget.duration != widget.duration) {
      _pointer = null;
      _preview = null;
    }
    if (_preview == null) slider.value = _position;
  }

  void _resetPreview() {
    setState(() {
      _pointer = null;
      _preview = null;
      slider.value = _position;
    });
  }

  @override
  void dispose() {
    slider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final durationMs = widget.duration.inMilliseconds;
    final maximum = _maximum;
    final position = Duration(milliseconds: (_preview ?? _position).round());
    final tokens = AppTokens.of(context);
    final timeStyle = AppTypography.counter.copyWith(
      color: widget.labelColor ?? tokens.muted,
    );
    return SizedBox(
      key: const Key('playback-progress'),
      height: widget.hitExtent,
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
              height: widget.hitExtent,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  void previewAt(double dx) {
                    if (durationMs <= 0 || constraints.maxWidth <= 0) return;
                    final fraction = (dx / constraints.maxWidth).clamp(
                      0.0,
                      1.0,
                    );
                    setState(() {
                      _preview = maximum * fraction;
                      slider.value = _preview!;
                    });
                  }

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      ShadSlider(
                        controller: slider,
                        max: maximum,
                        enabled: durationMs > 0,
                        trackHeight: widget.trackHeight,
                        thumbRadius: widget.thumbDiameter / 2,
                        semanticFormatterCallback: (value) =>
                            _clock(Duration(milliseconds: value.round())),
                        activeTrackColor:
                            widget.activeTrackColor ?? tokens.accent,
                        inactiveTrackColor:
                            widget.inactiveTrackColor ??
                            tokens.playbackTrackInactive,
                        onChanged: (next) =>
                            widget.onSeek(Duration(milliseconds: next.round())),
                      ),
                      Positioned.fill(
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: durationMs > 0
                              ? (event) {
                                  if (_pointer != null) return;
                                  _pointer = event.pointer;
                                  previewAt(event.localPosition.dx);
                                }
                              : null,
                          onPointerMove: durationMs > 0
                              ? (event) {
                                  if (_pointer == event.pointer) {
                                    previewAt(event.localPosition.dx);
                                  }
                                }
                              : null,
                          onPointerUp: (event) {
                            if (_pointer != event.pointer) return;
                            final target = _preview;
                            _resetPreview();
                            if (target != null) {
                              widget.onSeek(
                                Duration(milliseconds: target.round()),
                              );
                            }
                          },
                          onPointerCancel: (event) {
                            if (_pointer == event.pointer) _resetPreview();
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 42,
            child: Text(_clock(widget.duration), style: timeStyle),
          ),
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
