import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../storage/app_image_cache_scope.dart';
import '../design_tokens.dart';

const artworkRequestHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0 Safari/537.36',
};

@immutable
final class AppArtworkSource {
  AppArtworkSource.network(String url, {required this.fallbackSeed})
    : url = _normalizeArtworkUrl(url);

  const AppArtworkSource.fallback({required this.fallbackSeed}) : url = null;

  factory AppArtworkSource.fromUrl(
    String? url, {
    required String fallbackSeed,
  }) => url == null || url.isEmpty
      ? AppArtworkSource.fallback(fallbackSeed: fallbackSeed)
      : AppArtworkSource.network(url, fallbackSeed: fallbackSeed);

  final String? url;
  final String fallbackSeed;
}

String _normalizeArtworkUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      (uri.host != 'p1.music.126.net' && uri.host != 'p2.music.126.net')) {
    return url;
  }
  return uri.replace(host: 'p3.music.126.net').toString();
}

final class AppArtwork extends StatelessWidget {
  const AppArtwork({
    super.key,
    this.imageUrl,
    this.source,
    required this.seed,
    required this.semanticLabel,
    required this.size,
    this.width,
    this.height,
    this.borderRadius = AppRadii.card,
    this.icon = LucideIcons.music2,
    this.showFallback = true,
    this.showFallbackBorder = true,
    this.fallback,
  });

  final String? imageUrl;
  final AppArtworkSource? source;
  final String seed;
  final String semanticLabel;
  final double size;
  final double? width;
  final double? height;
  final double borderRadius;
  final IconData icon;
  final bool showFallback;
  final bool showFallbackBorder;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final resolved =
        source ?? AppArtworkSource.fromUrl(imageUrl, fallbackSeed: seed);
    final resolvedFallback = showFallback
        ? fallback ??
              _ArtworkFallback(
                seed: resolved.fallbackSeed,
                icon: icon,
                showBorder: showFallbackBorder,
              )
        : const SizedBox.shrink();
    final cacheManager = AppImageCacheScope.maybeOf(context)?.manager;
    return Semantics(
      image: true,
      label: semanticLabel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: SizedBox(
          width: width ?? size,
          height: height ?? size,
          child: resolved.url == null || cacheManager == null
              ? resolvedFallback
              : CachedNetworkImage(
                  key: ValueKey(resolved.url),
                  imageUrl: resolved.url!,
                  cacheKey: resolved.url!,
                  httpHeaders: artworkRequestHeaders,
                  cacheManager: cacheManager,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  disablePlaceholderOnCacheHit: true,
                  useOldImageOnUrlChange: false,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholderFadeInDuration: Duration.zero,
                  placeholder: (_, _) => resolvedFallback,
                  errorBuilder: (_, _, _) => resolvedFallback,
                ),
        ),
      ),
    );
  }
}

final class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({
    required this.seed,
    required this.icon,
    required this.showBorder,
  });

  final String seed;
  final IconData icon;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.maybeOf(context);
    final dark =
        (shadTheme?.brightness ?? Theme.of(context).brightness) ==
        Brightness.dark;
    final tokens = shadTheme == null
        ? (dark ? AppTokens.dark : AppTokens.light)
        : AppTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return DecoratedBox(
          key: Key('artwork-fallback-$seed'),
          decoration: BoxDecoration(
            color: dark ? tokens.surface : tokens.surfaceWarm,
            border: showBorder ? Border.all(color: tokens.border) : null,
          ),
          child: _RecordFallback(
            seed: seed,
            icon: icon,
            tokens: tokens,
            dark: dark,
          ),
        );
      },
    );
  }
}

final class _RecordFallback extends StatelessWidget {
  const _RecordFallback({
    required this.seed,
    required this.icon,
    required this.tokens,
    required this.dark,
  });

  final String seed;
  final IconData icon;
  final AppTokens tokens;
  final bool dark;

  @override
  Widget build(BuildContext context) => CustomPaint(
    key: Key('artwork-fallback-record-$seed'),
    painter: _VinylArtworkPainter(
      recordColor: dark ? tokens.accentForeground : tokens.foreground,
      grooveColor: dark ? tokens.foreground : tokens.accentForeground,
    ),
    child: Center(
      child: FractionallySizedBox(
        widthFactor: .24,
        heightFactor: .24,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tokens.accent,
          ),
          child: SizedBox.expand(
            key: Key('artwork-fallback-symbol-$seed'),
            child: icon == LucideIcons.music2
                ? CustomPaint(
                    key: Key('artwork-fallback-filled-note-$seed'),
                    painter: _FilledMusicNotePainter(tokens.accentForeground),
                  )
                : Padding(
                    padding: const EdgeInsets.all(2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Icon(icon, color: tokens.accentForeground),
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
}

final class _VinylArtworkPainter extends CustomPainter {
  const _VinylArtworkPainter({
    required this.recordColor,
    required this.grooveColor,
  });

  final Color recordColor;
  final Color grooveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .36;
    canvas.drawCircle(center, radius, Paint()..color = recordColor);
    for (final factor in const [.78, .58, .38]) {
      canvas.drawCircle(
        center,
        radius * factor,
        Paint()
          ..color = grooveColor.withValues(alpha: .13)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (size.shortestSide * .008).clamp(.5, 2).toDouble(),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VinylArtworkPainter oldDelegate) =>
      oldDelegate.recordColor != recordColor ||
      oldDelegate.grooveColor != grooveColor;
}

final class _FilledMusicNotePainter extends CustomPainter {
  const _FilledMusicNotePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addOval(
        Rect.fromLTWH(
          size.width * .18,
          size.height * .57,
          size.width * .38,
          size.height * .27,
        ),
      )
      ..addRect(
        Rect.fromLTWH(
          size.width * .50,
          size.height * .20,
          size.width * .10,
          size.height * .52,
        ),
      )
      ..moveTo(size.width * .50, size.height * .20)
      ..lineTo(size.width * .82, size.height * .30)
      ..lineTo(size.width * .82, size.height * .43)
      ..lineTo(size.width * .60, size.height * .35)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _FilledMusicNotePainter oldDelegate) =>
      oldDelegate.color != color;
}
