import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../design/app_glass_policy.dart';
import '../../design/components/artwork.dart';
import '../../design/design_tokens.dart';
import 'artwork_palette.dart';

const _resinTextureAsset = 'assets/vinyl/qq_record_player_multi_texture.png';
const _grooveHighlightAsset =
    'assets/vinyl/qq_record_player_multi_highlight.png';

final class DesktopOrbitVinyl extends StatefulWidget {
  const DesktopOrbitVinyl({
    super.key,
    this.vinylKey = const Key('player-desktop-orbit-vinyl'),
    this.turnKey = const Key('player-desktop-orbit-turn'),
    this.artworkKey = const Key('player-desktop-vinyl-artwork'),
    this.spindleKey = const Key('player-desktop-vinyl-spindle'),
    required this.source,
    required this.palette,
    required this.seed,
    required this.semanticLabel,
    required this.rotating,
  });

  final Key vinylKey;
  final Key turnKey;
  final Key artworkKey;
  final Key spindleKey;
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
  late Widget _ambilight;
  late Widget _underlight;
  late Widget _turntable;
  late Widget _opticalGlaze;
  var _blurEnabled = true;
  var _brightness = Brightness.light;
  var _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(vsync: this);
    _rebuildVisuals();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final policy = AppGlassPolicyScope.policyOf(context);
    final brightness = Theme.of(context).brightness;
    _reduceMotion = policy.reduceMotion;
    final visualsChanged =
        _blurEnabled != policy.blurEnabled || _brightness != brightness;
    _blurEnabled = policy.blurEnabled;
    _brightness = brightness;
    if (visualsChanged) {
      _rebuildVisuals();
    }
    _syncRotation();
  }

  @override
  void didUpdateWidget(covariant DesktopOrbitVinyl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_visualsChanged(oldWidget)) _rebuildVisuals();
    if (oldWidget.rotating != widget.rotating) _syncRotation();
  }

  void _rebuildVisuals() {
    _ambilight = _buildAmbilight();
    _underlight = _buildUnderlight();
    _turntable = _buildTurntable();
    _opticalGlaze = _buildOpticalGlaze();
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
    key: widget.vinylKey,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final diameter = constraints.biggest.shortestSide;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: OverflowBox(
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: SizedBox.square(
                  key: const Key('player-desktop-vinyl-ambilight'),
                  dimension: diameter * 1.08,
                  child: _ambilight,
                ),
              ),
            ),
            Positioned.fill(child: _underlight),
            Positioned.fill(child: _turntable),
            Positioned.fill(child: _opticalGlaze),
          ],
        );
      },
    ),
  );

  Widget _buildAmbilight() {
    final paint = RepaintBoundary(
      key: const Key('player-desktop-vinyl-ambilight-raster'),
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: CustomPaint(
            key: const Key('player-desktop-vinyl-ambilight-paint'),
            painter: VinylAmbilightPainter(
              accentColor: widget.palette.vinylAccent,
              baseColor: widget.palette.backgroundBase,
              companionColor: widget.palette.backgroundCompanion,
              brightness: _brightness,
              fallback: !_blurEnabled,
            ),
          ),
        ),
      ),
    );
    if (!_blurEnabled) {
      return KeyedSubtree(
        key: const Key('player-desktop-vinyl-ambilight-fallback'),
        child: paint,
      );
    }
    return ImageFiltered(
      key: const Key('player-desktop-vinyl-ambilight-blur'),
      imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
      child: paint,
    );
  }

  Widget _buildUnderlight() => RepaintBoundary(
    key: const Key('player-desktop-vinyl-underlight'),
    child: ExcludeSemantics(
      child: IgnorePointer(
        child: CustomPaint(
          key: const Key('player-desktop-vinyl-underlight-paint'),
          painter: VinylUnderlightPainter(
            accentColor: widget.palette.vinylAccent,
            companionColor: widget.palette.backgroundCompanion,
            softened: _blurEnabled,
          ),
        ),
      ),
    ),
  );

  Widget _buildTurntable() => RotationTransition(
    key: widget.turnKey,
    turns: _rotation,
    child: RepaintBoundary(
      key: const Key('player-desktop-orbit-raster'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final diameter = constraints.biggest.shortestSide;
          final artworkDiameter = diameter * .60;
          final spindleDiameter = math.max(8.0, diameter * .022);
          return Center(
            child: SizedBox.square(
              dimension: diameter,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: const Key('player-desktop-vinyl-material'),
                          painter: PressedVinylPainter(
                            baseColor: widget.palette.vinylAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: ClipOval(
                          key: const Key('player-desktop-vinyl-resin-clip'),
                          child: Opacity(
                            opacity: .34,
                            child: Image.asset(
                              _resinTextureAsset,
                              key: const Key(
                                'player-desktop-vinyl-resin-texture',
                              ),
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.high,
                              gaplessPlayback: true,
                              color: _textureTint(widget.palette.vinylAccent),
                              colorBlendMode: BlendMode.softLight,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: ClipOval(
                          key: const Key('player-desktop-vinyl-groove-clip'),
                          child: Opacity(
                            opacity: .13,
                            child: Image.asset(
                              _grooveHighlightAsset,
                              key: const Key(
                                'player-desktop-vinyl-groove-highlight',
                              ),
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.high,
                              gaplessPlayback: true,
                              color: _grooveTint(widget.palette.vinylAccent),
                              colorBlendMode: BlendMode.modulate,
                            ),
                          ),
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
                  ExcludeSemantics(
                    child: Container(
                      key: widget.spindleKey,
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

  Widget _buildOpticalGlaze() => RepaintBoundary(
    key: const Key('player-desktop-vinyl-optical-glaze'),
    child: ExcludeSemantics(
      child: IgnorePointer(
        child: CustomPaint(
          key: const Key('player-desktop-vinyl-optical-glaze-paint'),
          painter: VinylOpticalGlazePainter(
            accentColor: widget.palette.vinylAccent,
            companionColor: widget.palette.backgroundCompanion,
            softened: _blurEnabled,
          ),
        ),
      ),
    ),
  );
}

final class VinylAmbilightPainter extends CustomPainter {
  const VinylAmbilightPainter({
    required this.accentColor,
    required this.baseColor,
    required this.companionColor,
    required this.brightness,
    required this.fallback,
  });

  final Color accentColor;
  final Color baseColor;
  final Color companionColor;
  final Brightness brightness;
  final bool fallback;

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = size.shortestSide;
    final light = brightness == Brightness.light;
    final colors = [
      _ambilightColor(accentColor, hueOffset: -18, brightness: brightness),
      _ambilightColor(companionColor, hueOffset: 12, brightness: brightness),
      _ambilightColor(baseColor, hueOffset: -34, brightness: brightness),
    ];
    final regions = [
      (const Offset(.18, .28), const Size(.42, .20)),
      (const Offset(.78, .67), const Size(.38, .18)),
      (const Offset(.46, .88), const Size(.30, .15)),
    ];
    for (var index = 0; index < regions.length; index++) {
      final region = regions[index];
      final center = Offset(
        size.width * region.$1.dx,
        size.height * region.$1.dy,
      );
      final rect = Rect.fromCenter(
        center: center,
        width: shortest * region.$2.width,
        height: shortest * region.$2.height,
      );
      final peak = fallback ? (light ? .10 : .08) : (light ? .18 : .13);
      final shader = RadialGradient(
        colors: [
          colors[index].withValues(alpha: peak),
          colors[index].withValues(alpha: peak * .68),
          colors[index].withValues(alpha: peak * .24),
          Colors.transparent,
        ],
        stops: const [0, .30, .68, 1],
      ).createShader(rect);
      canvas.drawOval(rect, Paint()..shader = shader);
    }
  }

  @override
  bool shouldRepaint(covariant VinylAmbilightPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.companionColor != companionColor ||
      oldDelegate.brightness != brightness ||
      oldDelegate.fallback != fallback;
}

final class VinylOpticalGlazePainter extends CustomPainter {
  const VinylOpticalGlazePainter({
    required this.accentColor,
    required this.companionColor,
    this.innerFraction = .60,
    required this.softened,
  }) : assert(innerFraction > 0 && innerFraction < 1);

  final Color accentColor;
  final Color companionColor;
  final double innerFraction;
  final bool softened;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final shortest = size.shortestSide;
    final innerDiameter = shortest * innerFraction;
    final inner = Rect.fromCenter(
      center: bounds.center,
      width: innerDiameter,
      height: innerDiameter,
    );
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(bounds)
      ..addOval(inner);

    canvas.save();
    canvas.clipPath(ring, doAntiAlias: true);
    _paintBand(
      canvas,
      size,
      center: const Offset(.70, .70),
      extent: const Size(.46, .075),
      angle: -.70,
      peak: .30,
      color: _opticalColor(accentColor),
    );
    canvas.restore();
  }

  void _paintBand(
    Canvas canvas,
    Size size, {
    required Offset center,
    required Size extent,
    required double angle,
    required double peak,
    required Color color,
  }) {
    final rect = Rect.fromCenter(
      center: Offset(size.width * center.dx, size.height * center.dy),
      width: size.width * extent.width,
      height: size.height * extent.height,
    );
    final halo = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          color.withValues(alpha: peak * .34),
          color.withValues(alpha: peak),
          color.withValues(alpha: peak * .38),
          Colors.transparent,
        ],
        stops: const [0, .22, .48, .70, 1],
      ).createShader(rect)
      ..blendMode = BlendMode.screen
      ..maskFilter = softened
          ? MaskFilter.blur(BlurStyle.normal, size.shortestSide * .010)
          : null;
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(angle);
    canvas.translate(-rect.center.dx, -rect.center.dy);
    canvas.drawOval(rect, halo);
    final coreRect = Rect.fromCenter(
      center: rect.center,
      width: rect.width * .84,
      height: rect.height * .26,
    );
    canvas.drawOval(
      coreRect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            color.withValues(alpha: peak * .24),
            Color.lerp(color, Colors.white, .44)!.withValues(alpha: peak * .78),
            color.withValues(alpha: peak * .20),
            Colors.transparent,
          ],
          stops: const [0, .30, .50, .70, 1],
        ).createShader(coreRect)
        ..blendMode = BlendMode.screen
        ..maskFilter = softened
            ? MaskFilter.blur(BlurStyle.normal, size.shortestSide * .0028)
            : null,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant VinylOpticalGlazePainter oldDelegate) =>
      oldDelegate.accentColor != accentColor ||
      oldDelegate.companionColor != companionColor ||
      oldDelegate.innerFraction != innerFraction ||
      oldDelegate.softened != softened;
}

final class VinylUnderlightPainter extends CustomPainter {
  const VinylUnderlightPainter({
    required this.accentColor,
    required this.companionColor,
    this.innerFraction = .60,
    required this.softened,
  }) : assert(innerFraction > 0 && innerFraction < 1);

  final Color accentColor;
  final Color companionColor;
  final double innerFraction;
  final bool softened;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final innerDiameter = size.shortestSide * innerFraction;
    final inner = Rect.fromCenter(
      center: bounds.center,
      width: innerDiameter,
      height: innerDiameter,
    );
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(bounds)
      ..addOval(inner);
    final transmission = Color.lerp(
      _opticalColor(accentColor),
      Colors.white,
      .58,
    )!;
    final companion = Color.lerp(
      _opticalColor(companionColor),
      Colors.white,
      .46,
    )!;
    final glowBounds = Rect.fromCenter(
      center: Offset(size.width * .66, size.height * .73),
      width: size.width * 1.02,
      height: size.height * .78,
    );

    canvas.save();
    canvas.clipPath(ring, doAntiAlias: true);
    canvas.drawOval(
      glowBounds,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.18, .24),
          radius: .92,
          colors: [
            transmission.withValues(alpha: .34),
            transmission.withValues(alpha: .24),
            companion.withValues(alpha: .12),
            Colors.transparent,
          ],
          stops: const [0, .34, .68, 1],
        ).createShader(glowBounds)
        ..blendMode = BlendMode.screen
        ..maskFilter = softened
            ? MaskFilter.blur(BlurStyle.normal, size.shortestSide * .018)
            : null,
    );
    canvas.drawOval(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomRight,
          end: Alignment.topLeft,
          colors: [
            transmission.withValues(alpha: .18),
            companion.withValues(alpha: .08),
            Colors.transparent,
          ],
          stops: const [0, .48, 1],
        ).createShader(bounds)
        ..blendMode = BlendMode.screen,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant VinylUnderlightPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor ||
      oldDelegate.companionColor != companionColor ||
      oldDelegate.innerFraction != innerFraction ||
      oldDelegate.softened != softened;
}

final class PressedVinylPainter extends CustomPainter {
  const PressedVinylPainter({
    required this.baseColor,
    this.materialOpacity = .54,
  }) : assert(materialOpacity > 0 && materialOpacity < 1);

  final Color baseColor;
  final double materialOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final palette = _VinylMaterialPalette.fromAccent(baseColor);

    canvas.save();
    canvas.clipPath(Path()..addOval(bounds), doAntiAlias: true);
    _paintClearBody(canvas, bounds, palette);
    _paintThickness(canvas, center, radius, bounds, palette);
    canvas.restore();
  }

  void _paintClearBody(
    Canvas canvas,
    Rect bounds,
    _VinylMaterialPalette palette,
  ) {
    final shader = RadialGradient(
      center: const Alignment(-.18, -.22),
      radius: 1.02,
      colors: [
        palette.transmission.withValues(alpha: materialOpacity * .70),
        palette.transmission.withValues(alpha: materialOpacity * .96),
        palette.absorption.withValues(alpha: materialOpacity * .98),
        palette.transmission.withValues(alpha: materialOpacity * .92),
      ],
      stops: const [0, .56, .84, 1],
    ).createShader(bounds);
    canvas.drawOval(bounds, Paint()..shader = shader);
  }

  void _paintThickness(
    Canvas canvas,
    Offset center,
    double radius,
    Rect bounds,
    _VinylMaterialPalette palette,
  ) {
    canvas.drawOval(
      bounds,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            Colors.transparent,
            palette.absorption.withValues(alpha: .16),
            palette.absorption.withValues(alpha: .27),
          ],
          stops: const [0, .80, .94, 1],
        ).createShader(bounds),
    );

    canvas.drawCircle(
      center,
      radius * .635,
      Paint()
        ..color = palette.transmission.withValues(alpha: .58)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * .070,
    );
    canvas.drawCircle(
      center,
      radius * .674,
      Paint()
        ..color = palette.scatter.withValues(alpha: .24)
        ..blendMode = BlendMode.screen
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.8, radius * .007),
    );
    canvas.drawCircle(
      center,
      radius * .982,
      Paint()
        ..color = palette.specular.withValues(alpha: .20)
        ..blendMode = BlendMode.screen
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.8, radius * .005),
    );
  }

  @override
  bool shouldRepaint(covariant PressedVinylPainter oldDelegate) =>
      oldDelegate.baseColor != baseColor ||
      oldDelegate.materialOpacity != materialOpacity;
}

final class _VinylMaterialPalette {
  const _VinylMaterialPalette({
    required this.transmission,
    required this.absorption,
    required this.scatter,
    required this.specular,
  });

  factory _VinylMaterialPalette.fromAccent(Color accent) {
    final display = _resinDisplayHsv(accent);
    final transmission = display.toColor();
    final absorption = display
        .withSaturation((display.saturation * 1.02).clamp(.74, .98))
        .withValue((display.value * .72).clamp(.38, .68))
        .toColor();
    final scatter = display
        .withSaturation((display.saturation * .90).clamp(.72, .90))
        .withValue((display.value * 1.08).clamp(.84, .96))
        .toColor();
    final specular = Color.lerp(Colors.white, scatter, .16)!;
    return _VinylMaterialPalette(
      transmission: transmission,
      absorption: absorption,
      scatter: scatter,
      specular: specular,
    );
  }

  final Color transmission;
  final Color absorption;
  final Color scatter;
  final Color specular;
}

Color _ambilightColor(
  Color color, {
  required double hueOffset,
  required Brightness brightness,
}) {
  final hsv = HSVColor.fromColor(color);
  final light = brightness == Brightness.light;
  return hsv
      .withHue((hsv.hue + hueOffset) % 360)
      .withSaturation(
        hsv.saturation.clamp(light ? .52 : .34, light ? .86 : .72),
      )
      .withValue(hsv.value.clamp(light ? .48 : .64, light ? .78 : .96))
      .toColor();
}

Color _opticalColor(Color color) {
  final hsv = HSVColor.fromColor(color);
  return hsv
      .withSaturation(hsv.saturation.clamp(.18, .52))
      .withValue(hsv.value.clamp(.82, 1))
      .toColor();
}

HSVColor _resinDisplayHsv(Color color) {
  final source = HSVColor.fromColor(color);
  final blueBias = (1 - ((source.hue - 205).abs() / 30)).clamp(0.0, 1.0) * 8;
  return source
      .withHue((source.hue + blueBias) % 360)
      .withSaturation((source.saturation * 1.12).clamp(.82, .98))
      .withValue((source.value * 1.28).clamp(.86, .96));
}

Color _textureTint(Color color) => _resinDisplayHsv(color).toColor();

Color _grooveTint(Color color) => Color.lerp(color, Colors.white, .72)!;
