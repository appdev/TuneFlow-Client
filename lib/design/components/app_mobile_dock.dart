import 'package:flutter/material.dart';

import '../../features/player/mini_player.dart';
import '../../features/player/player_controller.dart';
import '../design_tokens.dart';
import 'app_navigation.dart';

final class AppMobileDock extends StatelessWidget {
  const AppMobileDock({
    required this.player,
    required this.destinations,
    required this.selectedId,
    required this.onSelected,
    required this.onOpenPlayer,
    this.showNavigation = true,
    super.key,
  });

  final PlayerController player;
  final List<AppDestination> destinations;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final VoidCallback onOpenPlayer;
  final bool showNavigation;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: player,
    builder: (context, _) {
      final hasTrack = player.state.current != null;
      if (!hasTrack && !showNavigation) return const SizedBox.shrink();
      return BackdropGroup(
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            key: const Key('mobile-player-dock'),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasTrack)
                MiniPlayer(
                  controller: player,
                  onOpen: onOpenPlayer,
                  variant: MiniPlayerVariant.mobile,
                ),
              if (hasTrack && showNavigation)
                const SizedBox(height: AppSpacing.xs),
              if (showNavigation)
                AppMobileNavigation(
                  destinations: destinations,
                  selectedId: selectedId,
                  onSelected: onSelected,
                ),
            ],
          ),
        ),
      );
    },
  );
}
