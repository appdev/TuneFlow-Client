import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/features/player/artwork_palette.dart';

void main() {
  test('artwork progress track remains visible on both gradient colors', () {
    const palettes = [
      ArtworkPalette(
        backgroundBase: Color(0xFFF4EFE8),
        backgroundCompanion: Color(0xFFF8F6F1),
        vinylAccent: Color(0xFF14745F),
        foreground: Color(0xFF17191B),
      ),
      ArtworkPalette(
        backgroundBase: Color(0xFF171817),
        backgroundCompanion: Color(0xFF242724),
        vinylAccent: Color(0xFF70C7B2),
        foreground: Color(0xFFF8F7F4),
      ),
    ];

    for (final palette in palettes) {
      final track = readableArtworkInactiveTrack(palette);
      final onBase = Color.alphaBlend(track, palette.backgroundBase);
      final onCompanion = Color.alphaBlend(track, palette.backgroundCompanion);

      expect(
        contrastRatio(onBase, palette.backgroundBase),
        greaterThanOrEqualTo(3),
      );
      expect(
        contrastRatio(onCompanion, palette.backgroundCompanion),
        greaterThanOrEqualTo(3),
      );
    }
  });
}
