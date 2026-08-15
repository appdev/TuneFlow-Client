import 'package:flutter/material.dart';

import '../../design/components/artwork.dart';
import 'vinyl_record.dart';

final class DesktopVinylRecord extends StatelessWidget {
  const DesktopVinylRecord({
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
  Widget build(BuildContext context) => VinylRecord(
    key: const Key('player-desktop-vinyl'),
    turnKey: const Key('player-desktop-vinyl-turn'),
    artworkKey: const Key('player-desktop-vinyl-artwork'),
    spindleKey: const Key('player-desktop-vinyl-spindle'),
    source: source,
    seed: seed,
    semanticLabel: semanticLabel,
    rotating: rotating,
    artworkFraction: .6,
    discColor: const Color(0xFF202224),
  );
}
