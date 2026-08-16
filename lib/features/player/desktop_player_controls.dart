/* Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4 */

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../design/components/playback_progress.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_playback_button.dart';
import '../../design/design_tokens.dart';
import 'artwork_palette.dart';
import 'current_track_action_buttons.dart';
import 'current_track_actions_controller.dart';
import 'desktop_queue_popover.dart';
import 'player_controller.dart';

final class DesktopPlayerControls extends StatefulWidget {
  const DesktopPlayerControls({
    super.key,
    required this.controller,
    required this.palette,
    this.actions,
  });

  final PlayerController controller;
  final ArtworkPalette palette;
  final CurrentTrackActionsController? actions;

  @override
  State<DesktopPlayerControls> createState() => _DesktopPlayerControlsState();
}

final class _DesktopPlayerControlsState extends State<DesktopPlayerControls> {
  final queuePopover = ShadPopoverController();
  final qualityPopover = ShadPopoverController();
  String? failedQuality;

  Future<void> changeQuality(String quality) async {
    setState(() => failedQuality = null);
    final changed = await widget.controller.setQuality(quality);
    if (!mounted) return;
    if (changed) {
      qualityPopover.hide();
    } else {
      setState(() => failedQuality = quality);
    }
  }

  @override
  void dispose() {
    queuePopover.dispose();
    qualityPopover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final state = controller.state;
    return SizedBox(
      key: const Key('player-desktop-controls'),
      height: 116,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              widthFactor: .62,
              child: Column(
                key: const Key('player-desktop-core'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  PlaybackProgress(
                    key: const Key('player-desktop-progress'),
                    position: state.position,
                    duration: state.duration,
                    onSeek: controller.seek,
                    activeTrackColor: widget.palette.vinylAccent,
                    inactiveTrackColor: readableArtworkInactiveTrack(
                      widget.palette,
                    ),
                    labelColor: widget.palette.foreground.withValues(
                      alpha: .62,
                    ),
                  ),
                  Row(
                    key: const Key('player-desktop-transport'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ControlButton(
                        key: const Key('player-previous'),
                        label: '上一首',
                        icon: AppPlaybackIcons.previous,
                        enabled: state.canPrevious,
                        onPressed: controller.previous,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      _ControlButton(
                        key: const Key('player-play-pause'),
                        label: state.playing ? '暂停' : '播放',
                        icon: state.playing
                            ? AppPlaybackIcons.pause
                            : AppPlaybackIcons.play,
                        prominent: true,
                        onPressed: state.playing
                            ? controller.pause
                            : controller.resume,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      _ControlButton(
                        key: const Key('player-next'),
                        label: '下一首',
                        icon: AppPlaybackIcons.next,
                        enabled: state.canNext,
                        onPressed: controller.next,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.lg, bottom: 8),
              child: widget.actions == null
                  ? const SizedBox.shrink()
                  : CurrentTrackActionButtons(
                      controller: widget.actions!,
                      keyPrefix: 'desktop-full',
                      foreground: widget.palette.vinylAccent,
                      selectedForeground: widget.palette.vinylAccent,
                      selectedBackground: widget.palette.vinylAccent.withValues(
                        alpha: .18,
                      ),
                    ),
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.lg, bottom: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShadPopover(
                    controller: qualityPopover,
                    popover: (_) => SizedBox(
                      key: const Key('player-desktop-quality-popover'),
                      width: 168,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final option in const [
                            ('128k', '标准 128k'),
                            ('320k', '高品质 320k'),
                            ('flac', '无损 FLAC'),
                          ])
                            ShadButton.ghost(
                              key: Key('player-quality-${option.$1}'),
                              width: double.infinity,
                              onPressed: () => changeQuality(option.$1),
                              child: SizedBox(
                                width: 136,
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 112,
                                      child: Text(option.$2),
                                    ),
                                    if (state.quality == option.$1)
                                      const Icon(LucideIcons.check, size: 16),
                                  ],
                                ),
                              ),
                            ),
                          if (failedQuality != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                              child: Column(
                                children: [
                                  const AppNotice.error(
                                    title: '音质切换失败',
                                    message: '当前音质仍保持不变。',
                                  ),
                                  ShadButton.ghost(
                                    onPressed: () =>
                                        changeQuality(failedQuality!),
                                    child: const Text('重试'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    child: SizedBox(
                      key: const Key('player-desktop-quality'),
                      width: 72,
                      child: ShadButton.ghost(
                        onPressed: qualityPopover.toggle,
                        padding: EdgeInsets.zero,
                        child: Text(
                          state.quality == 'flac' ? '无损' : state.quality,
                          style: AppTypography.metadata,
                        ),
                      ),
                    ),
                  ),
                  ShadPopover(
                    controller: queuePopover,
                    popover: (_) => ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => DesktopQueuePopover(
                        controller: controller,
                        accentColor: widget.palette.vinylAccent,
                      ),
                    ),
                    child: _ControlButton(
                      key: const Key('player-desktop-queue'),
                      label: '播放队列',
                      icon: LucideIcons.listMusic,
                      onPressed: queuePopover.toggle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ControlButton extends StatelessWidget {
  const _ControlButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
    this.prominent = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final button = prominent
        ? Material(
            color: colors.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onPressed : null,
              child: SizedBox.square(
                dimension: 56,
                child: Icon(icon, size: 23, color: Colors.white),
              ),
            ),
          )
        : ShadButton.ghost(
            width: 48,
            height: 48,
            padding: EdgeInsets.zero,
            enabled: enabled,
            onPressed: enabled ? onPressed : null,
            child: Icon(icon, size: 20),
          );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Tooltip(message: label, child: button),
    );
  }
}
