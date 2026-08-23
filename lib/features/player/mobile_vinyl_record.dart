import 'package:flutter/material.dart';

import '../../design/components/artwork.dart';
import 'artwork_palette.dart';
import 'desktop_orbit_vinyl.dart';

/// The mobile entry point for the shared translucent resin record.
///
/// Mobile owns the centered layout and supplies its existing rotation state;
/// the material, masks, artwork ratio, and optical layers stay identical to
/// the desktop record.
final class MobileVinylRecord extends StatelessWidget {
  const MobileVinylRecord({
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
  Widget build(BuildContext context) => DesktopOrbitVinyl(
    vinylKey: const Key('player-mobile-vinyl'),
    turnKey: const Key('player-mobile-vinyl-turn'),
    artworkKey: const Key('player-mobile-vinyl-artwork'),
    spindleKey: const Key('player-mobile-vinyl-spindle'),
    source: source,
    palette: palette,
    seed: seed,
    semanticLabel: semanticLabel,
    rotating: rotating,
  );
}
