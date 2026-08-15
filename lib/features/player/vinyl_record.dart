import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/app_glass_policy.dart';
import '../../design/components/artwork.dart';
import '../../design/design_tokens.dart';

final class VinylRecord extends StatefulWidget {
  const VinylRecord({
    super.key,
    required this.turnKey,
    required this.artworkKey,
    required this.spindleKey,
    required this.source,
    required this.seed,
    required this.semanticLabel,
    required this.rotating,
    this.artworkFraction = 1,
    this.discColor,
  });

  final Key turnKey;
  final Key artworkKey;
  final Key spindleKey;
  final AppArtworkSource source;
  final String seed;
  final String semanticLabel;
  final bool rotating;
  final double artworkFraction;
  final Color? discColor;

  @override
  State<VinylRecord> createState() => _VinylRecordState();
}

final class _VinylRecordState extends State<VinylRecord>
    with SingleTickerProviderStateMixin {
  static const _rotationPeriod = Duration(seconds: 18);

  late final AnimationController _rotation;
  var _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppGlassPolicyScope.policyOf(context).reduceMotion;
    _syncRotation();
  }

  @override
  void didUpdateWidget(covariant VinylRecord oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rotating != widget.rotating) _syncRotation();
  }

  void _syncRotation() {
    final shouldRotate = widget.rotating && !_reduceMotion;
    if (shouldRotate && !_rotation.isAnimating) {
      _rotation.repeat(period: _rotationPeriod);
    } else if (!shouldRotate && _rotation.isAnimating) {
      _rotation.stop(canceled: false);
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SizedBox.expand(
      child: RepaintBoundary(
        child: RotationTransition(
          key: widget.turnKey,
          turns: _rotation,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final diameter = constraints.biggest.shortestSide;
              final artworkDiameter = diameter * widget.artworkFraction;
              final spindleDiameter = math.max(8.0, diameter * .055);
              return Center(
                child: SizedBox.square(
                  dimension: diameter,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: ExcludeSemantics(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.discColor ?? tokens.surface,
                              boxShadow: AppShadows.raised,
                            ),
                          ),
                        ),
                      ),
                      SizedBox.square(
                        dimension: artworkDiameter,
                        child: AppArtwork(
                          key: widget.artworkKey,
                          source: widget.source,
                          seed: widget.seed,
                          semanticLabel: widget.semanticLabel,
                          size: artworkDiameter,
                          borderRadius: artworkDiameter,
                        ),
                      ),
                      Positioned.fill(
                        child: ExcludeSemantics(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: const VinylGroovesPainter(
                                grooveColor: Color(0x1EFFFFFF),
                                highlightColor: Color(0x28FFFFFF),
                              ),
                            ),
                          ),
                        ),
                      ),
                      ExcludeSemantics(
                        child: Container(
                          key: widget.spindleKey,
                          width: spindleDiameter,
                          height: spindleDiameter,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: tokens.background,
                            border: Border.all(
                              color: tokens.foreground.withValues(alpha: .55),
                              width: 1.5,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

final class VinylGroovesPainter extends CustomPainter {
  const VinylGroovesPainter({
    required this.grooveColor,
    required this.highlightColor,
  });

  final Color grooveColor;
  final Color highlightColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final groovePaint = Paint()
      ..color = grooveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.55, radius * .0038);
    for (var index = 0; index < 7; index++) {
      final grooveRadius = radius * (.72 + index * .04);
      canvas.drawCircle(center, grooveRadius, groovePaint);
    }

    final highlightPaint = Paint()
      ..color = highlightColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.9, radius * .0075);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * .91),
      math.pi * 1.08,
      math.pi * .26,
      false,
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant VinylGroovesPainter oldDelegate) =>
      oldDelegate.grooveColor != grooveColor ||
      oldDelegate.highlightColor != highlightColor;
}
