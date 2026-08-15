import 'package:flutter/material.dart';

@immutable
final class ArtworkPalette {
  const ArtworkPalette({
    required this.backgroundBase,
    required this.backgroundCompanion,
    required this.vinylAccent,
    required this.foreground,
  });

  final Color backgroundBase;
  final Color backgroundCompanion;
  final Color vinylAccent;
  final Color foreground;

  static ArtworkPalette lerp(
    ArtworkPalette first,
    ArtworkPalette second,
    double amount,
  ) => ArtworkPalette(
    backgroundBase: Color.lerp(
      first.backgroundBase,
      second.backgroundBase,
      amount,
    )!,
    backgroundCompanion: Color.lerp(
      first.backgroundCompanion,
      second.backgroundCompanion,
      amount,
    )!,
    vinylAccent: Color.lerp(first.vinylAccent, second.vinylAccent, amount)!,
    foreground: Color.lerp(first.foreground, second.foreground, amount)!,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtworkPalette &&
          backgroundBase == other.backgroundBase &&
          backgroundCompanion == other.backgroundCompanion &&
          vinylAccent == other.vinylAccent &&
          foreground == other.foreground;

  @override
  int get hashCode =>
      Object.hash(backgroundBase, backgroundCompanion, vinylAccent, foreground);
}

double contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + .05) / (darker + .05);
}

ArtworkPalette fallbackArtworkPalette(
  String seed, {
  required Brightness brightness,
}) {
  var hash = 0x811C9DC5;
  for (final unit in seed.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  final hue = (hash % 360).toDouble();
  final dark = brightness == Brightness.dark;
  final base = HSVColor.fromAHSV(
    1,
    hue,
    dark ? .24 : .18,
    dark ? .17 : .93,
  ).toColor();
  final companion = HSVColor.fromAHSV(
    1,
    (hue + 52) % 360,
    dark ? .28 : .16,
    dark ? .21 : .96,
  ).toColor();
  final accent = HSVColor.fromAHSV(1, hue, .58, dark ? .72 : .76).toColor();
  return ArtworkPalette(
    backgroundBase: base,
    backgroundCompanion: companion,
    vinylAccent: accent,
    foreground: _readableForeground(base, companion),
  );
}

Color readableArtworkForeground(Color base, Color companion) =>
    _readableForeground(base, companion);

Color readableArtworkInactiveTrack(ArtworkPalette palette) {
  for (final opacity in const [.32, .40, .48, .56, .64, .72, .80, .88, 1.0]) {
    final candidate = palette.foreground.withValues(alpha: opacity);
    final onBase = Color.alphaBlend(candidate, palette.backgroundBase);
    final onCompanion = Color.alphaBlend(
      candidate,
      palette.backgroundCompanion,
    );
    if (contrastRatio(onBase, palette.backgroundBase) >= 3 &&
        contrastRatio(onCompanion, palette.backgroundCompanion) >= 3) {
      return candidate;
    }
  }
  return palette.foreground;
}

Color _readableForeground(Color base, Color companion) {
  const dark = Color(0xFF17191B);
  const light = Color(0xFFF8F7F4);
  final darkScore = contrastRatio(dark, base) < contrastRatio(dark, companion)
      ? contrastRatio(dark, base)
      : contrastRatio(dark, companion);
  final lightScore =
      contrastRatio(light, base) < contrastRatio(light, companion)
      ? contrastRatio(light, base)
      : contrastRatio(light, companion);
  return darkScore >= lightScore ? dark : light;
}
