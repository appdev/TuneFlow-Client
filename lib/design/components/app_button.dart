import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../design_tokens.dart';

final class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.loading = false,
    this.variant = ShadButtonVariant.primary,
    this.leading,
    this.expands = false,
  }) : playback = false;

  const AppButton.playback({
    super.key,
    required this.child,
    required this.onPressed,
    this.loading = false,
    this.leading,
    this.expands = false,
  }) : variant = ShadButtonVariant.primary,
       playback = true;

  final Widget child;
  final VoidCallback? onPressed;
  final bool loading;
  final ShadButtonVariant variant;
  final Widget? leading;
  final bool expands;
  final bool playback;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final foreground = playback ? tokens.playbackActionForeground : null;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      child: ShadButton.raw(
        variant: variant,
        height: 48,
        expands: expands,
        enabled: !loading && onPressed != null,
        onPressed: loading ? null : onPressed,
        backgroundColor: playback ? tokens.playbackAction : null,
        foregroundColor: foreground,
        hoverBackgroundColor: playback
            ? Color.lerp(
                tokens.playbackAction,
                tokens.playbackActionForeground,
                .08,
              )
            : null,
        pressedBackgroundColor: playback
            ? Color.lerp(
                tokens.playbackAction,
                tokens.playbackActionForeground,
                .16,
              )
            : null,
        pressedForegroundColor: foreground,
        hoverForegroundColor: foreground,
        leading: loading
            ? SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color:
                      foreground ??
                      ShadTheme.of(context).colorScheme.primaryForeground,
                ),
              )
            : leading,
        child: child,
      ),
    );
  }
}
