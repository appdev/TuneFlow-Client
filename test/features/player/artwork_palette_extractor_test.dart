import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/features/player/artwork_palette.dart';
import 'package:musicfree_service_client/features/player/artwork_palette_extractor.dart';

void main() {
  const extractor = ArtworkPaletteExtractor();

  test('warm artwork produces a saturated accent and readable foreground', () {
    final palette = extractor.extractRgba(
      rgbaPixels(const [
        Color(0xFFE67E3A),
        Color(0xFFF2C5A8),
        Color(0xFF2A6C72),
      ]),
      width: 3,
      height: 1,
      fallbackSeed: 'warm',
      brightness: Brightness.light,
    );

    expect(
      HSVColor.fromColor(palette.vinylAccent).saturation,
      greaterThanOrEqualTo(.48),
    );
    expect(
      contrastRatio(palette.foreground, palette.backgroundBase),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('cool artwork remains cool and deterministic', () {
    final pixels = rgbaPixels(const [
      Color(0xFF2856A8),
      Color(0xFF6EA7D8),
      Color(0xFF8CCBC3),
      Color(0xFF2856A8),
    ]);
    final first = extractor.extractRgba(
      pixels,
      width: 2,
      height: 2,
      fallbackSeed: 'cool',
      brightness: Brightness.light,
    );
    final second = extractor.extractRgba(
      pixels,
      width: 2,
      height: 2,
      fallbackSeed: 'cool',
      brightness: Brightness.light,
    );

    expect(first, second);
    expect(
      HSVColor.fromColor(first.vinylAccent).hue,
      inInclusiveRange(160, 250),
    );
  });

  test('neutral and transparent inputs use stable seeded fallback', () {
    final neutral = extractor.extractRgba(
      rgbaPixels(const [Color(0xFF222222), Color(0xFFECECEC)]),
      width: 2,
      height: 1,
      fallbackSeed: 'neutral',
      brightness: Brightness.dark,
    );
    final transparent = extractor.extractRgba(
      Uint8List.fromList(const [0, 0, 0, 0]),
      width: 1,
      height: 1,
      fallbackSeed: 'neutral',
      brightness: Brightness.dark,
    );

    expect(neutral, transparent);
    expect(
      neutral,
      fallbackArtworkPalette('neutral', brightness: Brightness.dark),
    );
  });

  test('malformed encoded data returns fallback instead of throwing', () async {
    final palette = await extractor.extract(
      Uint8List.fromList(const [1, 2, 3]),
      fallbackSeed: 'broken',
      brightness: Brightness.light,
    );

    expect(
      palette,
      fallbackArtworkPalette('broken', brightness: Brightness.light),
    );
  });

  test('encoded artwork is downsampled and produces a real palette', () async {
    final bytes = await File(
      'assets/artwork/default_track_artwork.png',
    ).readAsBytes();

    final palette = await extractor.extract(
      bytes,
      fallbackSeed: 'encoded',
      brightness: Brightness.light,
    );

    expect(
      palette,
      isNot(fallbackArtworkPalette('encoded', brightness: Brightness.light)),
    );
    expect(
      contrastRatio(palette.foreground, palette.backgroundBase),
      greaterThanOrEqualTo(4.5),
    );
  });
}

Uint8List rgbaPixels(List<Color> colors) => Uint8List.fromList([
  for (final color in colors) ...[
    (color.r * 255).round(),
    (color.g * 255).round(),
    (color.b * 255).round(),
    (color.a * 255).round(),
  ],
]);
