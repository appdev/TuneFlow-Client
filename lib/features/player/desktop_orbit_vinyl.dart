import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../design/app_glass_policy.dart';
import '../../design/components/artwork.dart';
import '../../design/design_tokens.dart';
import 'artwork_palette.dart';

final class DesktopOrbitVinyl extends StatefulWidget {
  const DesktopOrbitVinyl({
    super.key,
    required this.source,
    required this.palette,
    required this.seed,
    required this.semanticLabel,
    required this.rotating,
  });

  final AppArtworkSource source;
  final ArtworkPalette palette;
  final String seed;
  final String semanticLabel;
  final bool rotating;

  @override
  State<DesktopOrbitVinyl> createState() => _DesktopOrbitVinylState();
}

final class _DesktopOrbitVinylState extends State<DesktopOrbitVinyl>
    with SingleTickerProviderStateMixin {
  static const _rotationPeriod = Duration(seconds: 18);

  late final AnimationController _rotation;
  late Widget _turntable;
  var _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(vsync: this);
    _turntable = _buildTurntable();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppGlassPolicyScope.policyOf(context).reduceMotion;
    _syncRotation();
  }

  @override
  void didUpdateWidget(covariant DesktopOrbitVinyl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_visualsChanged(oldWidget)) _turntable = _buildTurntable();
    if (oldWidget.rotating != widget.rotating) _syncRotation();
  }

  bool _visualsChanged(DesktopOrbitVinyl oldWidget) =>
      oldWidget.source.url != widget.source.url ||
      oldWidget.source.fallbackSeed != widget.source.fallbackSeed ||
      oldWidget.palette != widget.palette ||
      oldWidget.seed != widget.seed ||
      oldWidget.semanticLabel != widget.semanticLabel;

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
  Widget build(BuildContext context) => SizedBox.expand(
    key: const Key('player-desktop-orbit-vinyl'),
    child: _turntable,
  );

  Widget _buildTurntable() => RotationTransition(
    key: const Key('player-desktop-orbit-turn'),
    turns: _rotation,
    child: RepaintBoundary(
      key: const Key('player-desktop-orbit-raster'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final diameter = constraints.biggest.shortestSide;
          final artworkDiameter = diameter * .60;
          final spindleDiameter = math.max(8.0, diameter * .022);
          final accent = HSVColor.fromColor(widget.palette.vinylAccent);
          final darkAccent = accent
              .withValue((accent.value * .66).clamp(.22, .62))
              .toColor();
          final lightAccent = accent
              .withSaturation((accent.saturation * .72).clamp(.28, .62))
              .withValue((accent.value * 1.16).clamp(.62, .98))
              .toColor();
          return Center(
            child: SizedBox.square(
              dimension: diameter,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: DecoratedBox(
                        key: const Key('player-desktop-vinyl-base'),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: [
                              darkAccent.withValues(alpha: .76),
                              widget.palette.vinylAccent.withValues(alpha: .82),
                              lightAccent.withValues(alpha: .60),
                              widget.palette.vinylAccent.withValues(alpha: .72),
                              darkAccent.withValues(alpha: .74),
                            ],
                          ),
                          boxShadow: AppShadows.raised,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: ClipPath(
                        key: const Key('player-desktop-vinyl-refraction'),
                        clipper: const _VinylRingClipper(innerFraction: .62),
                        child: Opacity(
                          opacity: .18,
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaX: 6,
                              sigmaY: 6,
                              tileMode: TileMode.mirror,
                            ),
                            child: Transform.scale(
                              scale: 1.2,
                              child: AppArtwork(
                                source: widget.source,
                                seed: widget.seed,
                                semanticLabel: widget.semanticLabel,
                                size: diameter,
                                borderRadius: diameter,
                                showFallback: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: const Key('player-desktop-vinyl-grooves'),
                          painter: TexturedVinylPainter(
                            grooveColor: Colors.white.withValues(alpha: .18),
                            shadowColor: darkAccent.withValues(alpha: .22),
                            highlightColor: lightAccent.withValues(alpha: .38),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: artworkDiameter + diameter * .035,
                    height: artworkDiameter + diameter * .035,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.palette.vinylAccent,
                      boxShadow: [
                        BoxShadow(
                          color: darkAccent.withValues(alpha: .34),
                          blurRadius: diameter * .04,
                          offset: Offset(0, diameter * .018),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: SizedBox.square(
                      dimension: artworkDiameter,
                      child: AppArtwork(
                        key: const Key('player-desktop-vinyl-artwork'),
                        source: widget.source,
                        seed: widget.seed,
                        semanticLabel: widget.semanticLabel,
                        size: artworkDiameter,
                        borderRadius: artworkDiameter,
                      ),
                    ),
                  ),
                  ExcludeSemantics(
                    child: Container(
                      key: const Key('player-desktop-vinyl-spindle'),
                      width: spindleDiameter,
                      height: spindleDiameter,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTokens.of(context).background,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .62),
                        ),
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
  );
}

final class TexturedVinylPainter extends CustomPainter {
  const TexturedVinylPainter({
    required this.grooveColor,
    required this.shadowColor,
    required this.highlightColor,
  });

  final Color grooveColor;
  final Color shadowColor;
  final Color highlightColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    for (var index = 0; index < 12; index++) {
      final grooveRadius = radius * (.64 + index * .029);
      canvas.drawCircle(
        center,
        grooveRadius,
        Paint()
          ..color = index.isEven ? grooveColor : shadowColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.55, radius * .0028),
      );
    }
    final highlight = Paint()
      ..color = highlightColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, radius * .008);
    canvas
      ..drawArc(
        Rect.fromCircle(center: center, radius: radius * .91),
        math.pi * 1.10,
        math.pi * .24,
        false,
        highlight,
      )
      ..drawArc(
        Rect.fromCircle(center: center, radius: radius * .76),
        math.pi * .12,
        math.pi * .13,
        false,
        highlight..color = highlightColor.withValues(alpha: .62),
      );
  }

  @override
  bool shouldRepaint(covariant TexturedVinylPainter oldDelegate) =>
      oldDelegate.grooveColor != grooveColor ||
      oldDelegate.shadowColor != shadowColor ||
      oldDelegate.highlightColor != highlightColor;
}

final class _VinylRingClipper extends CustomClipper<Path> {
  const _VinylRingClipper({required this.innerFraction});

  final double innerFraction;

  @override
  Path getClip(Size size) {
    final outer = Rect.fromLTWH(0, 0, size.width, size.height);
    final innerSize = size.shortestSide * innerFraction;
    final inner = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: innerSize,
      height: innerSize,
    );
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(outer)
      ..addOval(inner);
  }

  @override
  bool shouldReclip(covariant _VinylRingClipper oldClipper) =>
      oldClipper.innerFraction != innerFraction;
}
