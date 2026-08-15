import 'package:flutter/material.dart';

import '../design_tokens.dart';

abstract final class AppPlaybackIcons {
  static const previous = Icons.skip_previous_rounded;
  static const play = Icons.play_arrow_rounded;
  static const pause = Icons.pause_rounded;
  static const next = Icons.skip_next_rounded;
}

final class AppPlaybackGlyph extends Icon {
  const AppPlaybackGlyph.play({
    super.key,
    super.size,
    super.color,
    super.shadows,
  }) : super(AppPlaybackIcons.play);

  const AppPlaybackGlyph.pause({
    super.key,
    super.size,
    super.color,
    super.shadows,
  }) : super(AppPlaybackIcons.pause);
}

final class AppPlaybackIconButton extends StatelessWidget {
  const AppPlaybackIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.dimension = 44,
    this.loading = false,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;
  final double dimension;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: loading ? null : onPressed,
      constraints: BoxConstraints.tightFor(
        width: dimension < 44 ? 44 : dimension,
        height: dimension < 44 ? 44 : dimension,
      ),
      style: IconButton.styleFrom(
        backgroundColor: tokens.playbackAction,
        foregroundColor: tokens.playbackActionForeground,
        disabledBackgroundColor: tokens.playbackAction.withValues(alpha: .48),
        disabledForegroundColor: tokens.playbackActionForeground.withValues(
          alpha: .72,
        ),
      ),
      icon: loading
          ? SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tokens.playbackActionForeground,
              ),
            )
          : child,
    );
  }
}
