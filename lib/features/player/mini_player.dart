import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../design/components/artwork.dart';
import '../../design/components/app_glass_surface.dart';
import '../../design/components/app_playback_button.dart';
import '../../design/components/playback_progress.dart';
import '../../design/app_theme_definition.dart';
import '../../design/design_tokens.dart';
import 'current_track_action_buttons.dart';
import 'current_track_actions_controller.dart';
import 'player_controller.dart';
import 'player_state.dart';

enum MiniPlayerVariant { desktop, mobile }

final class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.controller,
    required this.onOpen,
    this.variant = MiniPlayerVariant.mobile,
    this.actions,
  });

  final PlayerController controller;
  final VoidCallback onOpen;
  final MiniPlayerVariant variant;
  final CurrentTrackActionsController? actions;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.state;
      final track = state.current;
      final shellKey = variant == MiniPlayerVariant.desktop
          ? const Key('desktop-persistent-player')
          : const Key('mobile-mini-player');
      if (track == null) return SizedBox.shrink(key: shellKey);
      final imageUrl = track.raw['pic'] is String
          ? track.raw['pic']! as String
          : null;
      if (variant == MiniPlayerVariant.mobile) {
        return AppGlassSurface(
          key: shellKey,
          role: AppGlassRole.nav,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('mini-player'),
              onTap: onOpen,
              child: SizedBox(
                height: 60,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      AppArtwork(
                        imageUrl: imageUrl,
                        seed: '${track.source}:${track.id}',
                        semanticLabel: '${track.title}封面',
                        size: 42,
                        borderRadius: AppRadii.control,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: _TrackIdentity(controller: controller)),
                      _TransportButton(
                        tooltip: state.playing ? '暂停' : '播放',
                        icon: state.playing
                            ? AppPlaybackIcons.pause
                            : AppPlaybackIcons.play,
                        onPressed: state.playing
                            ? controller.pause
                            : controller.resume,
                      ),
                      _TransportButton(
                        key: const Key('mobile-player-next'),
                        tooltip: '下一首',
                        icon: AppPlaybackIcons.next,
                        enabled: state.currentIndex + 1 < state.queue.length,
                        onPressed: controller.next,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
      return _DesktopMiniPlayer(
        shellKey: shellKey,
        controller: controller,
        imageUrl: imageUrl,
        onOpen: onOpen,
        actions: actions,
      );
    },
  );
}

final class _DesktopMiniPlayer extends StatelessWidget {
  const _DesktopMiniPlayer({
    required this.shellKey,
    required this.controller,
    required this.imageUrl,
    required this.onOpen,
    required this.actions,
  });

  final Key shellKey;
  final PlayerController controller;
  final String? imageUrl;
  final VoidCallback onOpen;
  final CurrentTrackActionsController? actions;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final track = state.current!;
    final tokens = AppTokens.of(context);
    final transport = _transportPresentation(controller);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: Material(
        key: shellKey,
        color: tokens.surface,
        child: SizedBox(
          height: 96,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  flex: 7,
                  child: GestureDetector(
                    key: const Key('desktop-track-surface'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpen,
                    child: Row(
                      children: [
                        AppArtwork(
                          key: const Key('desktop-player-artwork'),
                          imageUrl: imageUrl,
                          seed: track.id,
                          semanticLabel: '${track.title}封面',
                          size: 52,
                          borderRadius: 10,
                          showFallbackBorder: false,
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: _DesktopTrackIdentity(
                            controller: controller,
                            actions: actions,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 13,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _TransportButton(
                            key: const Key('player-previous-mini'),
                            tooltip: '上一首',
                            icon: AppPlaybackIcons.previous,
                            enabled: state.currentIndex > 0,
                            onPressed: controller.previous,
                          ),
                          const SizedBox(width: 6),
                          _DesktopMainTransport(
                            key: const Key('desktop-play-pause'),
                            presentation: transport,
                          ),
                          const SizedBox(width: 6),
                          _TransportButton(
                            key: const Key('player-next-mini'),
                            tooltip: '下一首',
                            icon: AppPlaybackIcons.next,
                            enabled:
                                state.currentIndex + 1 < state.queue.length,
                            onPressed: controller.next,
                          ),
                        ],
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        excludeFromSemantics: true,
                        onTap: () {},
                        child: PlaybackProgress(
                          position: state.position,
                          duration: state.duration,
                          onSeek: controller.seek,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 7,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ShadButton.ghost(
                        key: const Key('desktop-quality'),
                        height: 44,
                        onPressed: onOpen,
                        child: Text(
                          state.quality == 'flac' ? '无损' : state.quality,
                        ),
                      ),
                      _TransportButton(
                        key: const Key('desktop-lyrics'),
                        tooltip: '歌词',
                        icon: LucideIcons.messageSquareText,
                        onPressed: () {
                          controller.setView(PlayerView.lyrics);
                          onOpen();
                        },
                      ),
                      _TransportButton(
                        key: const Key('desktop-queue'),
                        tooltip: '播放队列',
                        icon: LucideIcons.listMusic,
                        onPressed: () {
                          controller.setView(PlayerView.queue);
                          onOpen();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

typedef _TransportPresentation = ({
  String tooltip,
  IconData? icon,
  bool loading,
  VoidCallback? onPressed,
});

_TransportPresentation _transportPresentation(PlayerController controller) {
  final state = controller.state;
  if (state.processing == PlayerProcessing.loading ||
      state.processing == PlayerProcessing.buffering) {
    return (
      tooltip: '正在加载',
      icon: null,
      loading: true,
      onPressed: controller.pause,
    );
  }
  if (state.processing == PlayerProcessing.error || state.error != null) {
    return (
      tooltip: '重试播放',
      icon: LucideIcons.refreshCw,
      loading: false,
      onPressed: controller.resume,
    );
  }
  return (
    tooltip: state.playing ? '暂停' : '播放',
    icon: state.playing ? AppPlaybackIcons.pause : AppPlaybackIcons.play,
    loading: false,
    onPressed: state.playing ? controller.pause : controller.resume,
  );
}

final class _DesktopMainTransport extends StatelessWidget {
  const _DesktopMainTransport({super.key, required this.presentation});

  final _TransportPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Tooltip(
      message: presentation.tooltip,
      child: Semantics(
        button: true,
        label: presentation.tooltip,
        child: Material(
          color: tokens.playbackAction,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: presentation.onPressed ?? () {},
            child: SizedBox.square(
              dimension: 52,
              child: Center(
                child: presentation.loading
                    ? SizedBox.square(
                        key: const Key('desktop-player-loading'),
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tokens.playbackActionForeground,
                        ),
                      )
                    : Icon(
                        presentation.icon,
                        size: 22,
                        color: tokens.playbackActionForeground,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _DesktopTrackIdentity extends StatelessWidget {
  const _DesktopTrackIdentity({required this.controller, this.actions});

  final PlayerController controller;
  final CurrentTrackActionsController? actions;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final track = state.current!;
    final hasError = state.error != null;
    final metadataStyle = AppTypography.metadata.copyWith(
      color: AppTokens.of(context).foregroundSecondary,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          track.title.isEmpty ? track.id : track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.title,
        ),
        Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: metadataStyle,
        ),
        if (actions case final value?)
          SizedBox(
            height: 44,
            child: Row(
              children: [
                if (hasError)
                  Expanded(
                    child: Tooltip(
                      message: '重试播放',
                      child: Text(
                        '播放失败，点击重试',
                        key: const Key('desktop-player-error'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.metadata.copyWith(
                          fontSize: 10,
                          color: AppTokens.of(context).danger,
                        ),
                      ),
                    ),
                  ),
                CurrentTrackActionButtons(
                  controller: value,
                  keyPrefix: 'desktop-mini',
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 14,
            child: !hasError
                ? null
                : Tooltip(
                    message: '重试播放',
                    child: Text(
                      '播放失败，点击重试',
                      key: const Key('desktop-player-error'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.metadata.copyWith(
                        fontSize: 10,
                        color: AppTokens.of(context).danger,
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}

final class _TrackIdentity extends StatelessWidget {
  const _TrackIdentity({required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final track = controller.state.current!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          track.title.isEmpty ? track.id : track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.title,
        ),
        Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.metadata.copyWith(
            color: AppTokens.of(context).foregroundSecondary,
          ),
        ),
      ],
    );
  }
}

final class _TransportButton extends StatelessWidget {
  const _TransportButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final button = ShadButton.raw(
      variant: ShadButtonVariant.ghost,
      width: 44,
      height: 44,
      padding: EdgeInsets.zero,
      enabled: enabled,
      onPressed: enabled ? () => onPressed() : null,
      child: Icon(icon, size: 20),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: enabled ? null : () {},
      child: Tooltip(
        message: tooltip,
        child: Semantics(button: true, label: tooltip, child: button),
      ),
    );
  }
}
