import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../design/app_glass_policy.dart';

import '../lyrics_timeline.dart';

final class TimedLyricText extends StatefulWidget {
  const TimedLyricText({
    super.key,
    required this.line,
    required this.clock,
    required this.active,
    required this.style,
    required this.textAlign,
    required this.displayText,
  });
  final TimedLyricLine line;
  final ValueListenable<Duration> clock;
  final bool active;
  final TextStyle style;
  final TextAlign textAlign;
  final String Function(String) displayText;

  @override
  State<TimedLyricText> createState() => _TimedLyricTextState();
}

final class _TimedLyricTextState extends State<TimedLyricText> {
  _WordPainter? _painter;

  @override
  void dispose() {
    _painter?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final clock = widget.clock;
    final active = widget.active;
    final style = widget.style;
    final textAlign = widget.textAlign;
    final displayText = widget.displayText;
    if (line.words.isEmpty) {
      return Text(
        displayText(line.text.isEmpty ? '•••' : line.text),
        textAlign: textAlign,
        style: style,
      );
    }
    final words = [
      for (final word in line.words)
        TimedLyricWord(displayText(word.text), word.start, word.end),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter =
            TextPainter(
              text: TextSpan(
                text: words.map((w) => w.text).join(),
                style: style,
              ),
              textDirection: Directionality.of(context),
              textAlign: textAlign,
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(
              minWidth: constraints.maxWidth,
              maxWidth: constraints.maxWidth,
            );
        final height = painter.height;
        painter.dispose();
        _painter?.release();
        _painter = _WordPainter(
          words: words,
          clock: clock,
          active: active,
          style: style,
          alignment: textAlign,
          direction: Directionality.of(context),
          scaler: MediaQuery.textScalerOf(context),
          animate: !AppGlassPolicyScope.policyOf(context).reduceMotion,
        );
        return Semantics(
          label: displayText(line.text),
          child: SizedBox(
            width: constraints.maxWidth,
            height: height,
            child: RepaintBoundary(child: CustomPaint(painter: _painter)),
          ),
        );
      },
    );
  }
}

final class _WordPainter extends CustomPainter {
  _WordPainter({
    required this.words,
    required this.clock,
    required this.active,
    required this.style,
    required this.alignment,
    required this.direction,
    required this.scaler,
    required this.animate,
  }) : super(repaint: active ? clock : null);
  final List<TimedLyricWord> words;
  final ValueListenable<Duration> clock;
  final bool active;
  final TextStyle style;
  final TextAlign alignment;
  final TextDirection direction;
  final TextScaler scaler;
  final bool animate;
  TextPainter? _base;
  TextPainter? _highlight;
  TextPainter? _glow;
  final Paint _glowPaint = Paint();
  Size? _size;
  List<List<TextBox>> _boxes = const [];

  void _layout(Size size) {
    if (_size == size) return;
    _base?.dispose();
    _highlight?.dispose();
    _glow?.dispose();
    final text = words.map((w) => w.text).join();
    TextPainter make(TextStyle textStyle) => TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: direction,
      textAlign: alignment,
      textScaler: scaler,
    )..layout(minWidth: size.width, maxWidth: size.width);
    final color = style.color ?? Colors.white;
    _base = make(
      style.copyWith(color: color.withValues(alpha: active ? .4 : 1)),
    );
    _highlight = make(style);
    if (animate && active) {
      _glow = make(
        style.copyWith(shadows: [Shadow(color: color, blurRadius: 8)]),
      );
    }
    var offset = 0;
    _boxes = [
      for (final word in words)
        (() {
          final start = offset;
          offset += word.text.length;
          return _highlight!.getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: offset),
          );
        })(),
    ];
    _size = size;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _layout(size);
    _base!.paint(canvas, Offset.zero);
    if (!active) return;
    for (var i = 0; i < words.length; i++) {
      final boxes = _boxes[i];
      final progress = words[i].progress(clock.value);
      final sustained =
          _glow != null &&
          words[i].end - words[i].start >= const Duration(seconds: 1) &&
          progress > 0 &&
          progress < 1;
      var remaining =
          boxes.fold<double>(0, (sum, box) => sum + box.right - box.left) *
          progress;
      for (final box in boxes) {
        final width = math.min(remaining, box.right - box.left);
        if (width <= 0) break;
        final rect = box.direction == TextDirection.rtl
            ? Rect.fromLTRB(box.right - width, box.top, box.right, box.bottom)
            : Rect.fromLTRB(box.left, box.top, box.left + width, box.bottom);
        canvas.save();
        canvas.clipRect(rect);
        _highlight!.paint(canvas, Offset.zero);
        canvas.restore();
        if (sustained) {
          _glowPaint.color = Colors.white.withValues(
            alpha: .35 * math.sin(progress * math.pi),
          );
          canvas.saveLayer(rect.inflate(4), _glowPaint);
          canvas.clipRect(rect.inflate(4));
          _glow!.paint(canvas, Offset.zero);
          canvas.restore();
        }
        remaining -= width;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WordPainter oldDelegate) => true;

  void release() {
    _base?.dispose();
    _highlight?.dispose();
    _glow?.dispose();
  }
}
