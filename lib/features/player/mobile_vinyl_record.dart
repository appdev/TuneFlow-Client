import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/app_glass_policy.dart';
import '../../design/components/artwork.dart';
import '../../design/design_tokens.dart';

final class MobileVinylRecord extends StatefulWidget {
  const MobileVinylRecord({
    super.key,
    required this.source,
    required this.seed,
    required this.semanticLabel,
    required this.rotating,
  });

  final AppArtworkSource source;
  final String seed;
  final String semanticLabel;
  final bool rotating;

  @override
  State<MobileVinylRecord> createState() => _MobileVinylRecordState();
}

final class _MobileVinylRecordState extends State<MobileVinylRecord>
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
  void didUpdateWidget(covariant MobileVinylRecord oldWidget) {
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
      key: const Key('player-mobile-vinyl'),
      child: RepaintBoundary(
        child: RotationTransition(
          key: const Key('player-mobile-vinyl-turn'),
          turns: _rotation,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final diameter = constraints.biggest.shortestSide;
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
                              color: tokens.surface,
                              boxShadow: AppShadows.raised,
                            ),
                          ),
                        ),
                      ),
                      SizedBox.square(
                        dimension: diameter,
                        child: AppArtwork(
                          key: const Key('player-mobile-vinyl-artwork'),
                          source: widget.source,
                          seed: widget.seed,
                          semanticLabel: widget.semanticLabel,
                          size: diameter,
                          borderRadius: diameter,
                        ),
                      ),
                      Positioned.fill(
                        child: ExcludeSemantics(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _VinylGroovesPainter(
                                grooveColor: Colors.white.withValues(
                                  alpha: .24,
                                ),
                                highlightColor: Colors.white.withValues(
                                  alpha: .3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      ExcludeSemantics(
                        child: Container(
                          key: const Key('player-mobile-vinyl-spindle'),
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

final class _VinylGroovesPainter extends CustomPainter {
  const _VinylGroovesPainter({
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
      ..strokeWidth = math.max(0.7, radius * .006);
    for (var index = 0; index < 9; index++) {
      final grooveRadius = radius * (.69 + index * .035);
      canvas.drawCircle(center, grooveRadius, groovePaint);
    }

    final highlightPaint = Paint()
      ..color = highlightColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.2, radius * .012);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * .91),
      math.pi * 1.08,
      math.pi * .34,
      false,
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _VinylGroovesPainter oldDelegate) =>
      oldDelegate.grooveColor != grooveColor ||
      oldDelegate.highlightColor != highlightColor;
}
