import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../design/app_glass_policy.dart';
import '../../design/design_tokens.dart';
import 'artwork_palette.dart';

final class MeshPlayerBackdrop extends StatefulWidget {
  const MeshPlayerBackdrop({
    super.key,
    required this.palette,
    required this.playing,
  });
  final ArtworkPalette palette;
  final bool playing;

  @override
  State<MeshPlayerBackdrop> createState() => _MeshPlayerBackdropState();
}

final class _MeshPlayerBackdropState extends State<MeshPlayerBackdrop>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static Future<ui.FragmentProgram>? _program;
  final _seconds = ValueNotifier(0.0);
  late final Ticker _ticker;
  ui.FragmentShader? _shader;
  Duration _lastFrame = Duration.zero;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker((elapsed) {
      final delta = elapsed - _lastFrame;
      if (delta.inMilliseconds < 42) return;
      _lastFrame = elapsed;
      _seconds.value += delta.inMicroseconds / Duration.microsecondsPerSecond;
    });
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = await (_program ??= ui.FragmentProgram.fromAsset(
        'assets/shaders/soft_mesh_gradient.frag',
      ));
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
      _sync();
    } on Object {
      // 未支持的渲染器继续显示现有封面背景。
    }
  }

  void _sync() {
    final policy = AppGlassPolicyScope.policyOf(context);
    final running =
        _shader != null &&
        widget.playing &&
        _foreground &&
        policy.blurEnabled &&
        !policy.reduceMotion &&
        TickerMode.valuesOf(context).enabled;
    if (running && !_ticker.isActive) {
      _lastFrame = Duration.zero;
      _ticker.start();
    } else if (!running && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant MeshPlayerBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _seconds.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_shader == null || !AppGlassPolicyScope.policyOf(context).blurEnabled) {
      return const SizedBox.expand();
    }
    final neutral = AppTokens.of(context).background;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            if (size.isEmpty) return const SizedBox.shrink();
            final render = size.width >= size.height
                ? Size(360, 360 / size.aspectRatio)
                : Size(360 * size.aspectRatio, 360);
            return RepaintBoundary(
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox.fromSize(
                  size: render,
                  child: CustomPaint(
                    painter: _MeshPainter(
                      _shader!,
                      _seconds,
                      widget.palette,
                      neutral,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

final class _MeshPainter extends CustomPainter {
  _MeshPainter(this.shader, this.seconds, this.palette, this.neutral)
    : super(repaint: seconds);
  final ui.FragmentShader shader;
  final ValueNotifier<double> seconds;
  final ArtworkPalette palette;
  final Color neutral;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, seconds.value);
    final colors = [
      palette.backgroundBase,
      palette.backgroundCompanion,
      Color.lerp(palette.backgroundBase, palette.vinylAccent, .12)!,
      neutral,
    ];
    for (var i = 0; i < colors.length; i++) {
      shader.setFloat(3 + i * 3, colors[i].r);
      shader.setFloat(4 + i * 3, colors[i].g);
      shader.setFloat(5 + i * 3, colors[i].b);
    }
    _paint.shader = shader;
    canvas.drawRect(Offset.zero & size, _paint);
  }

  @override
  bool shouldRepaint(covariant _MeshPainter old) =>
      old.palette != palette || old.neutral != neutral || old.shader != shader;
}
