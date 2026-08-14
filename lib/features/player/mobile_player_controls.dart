/* Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4 */

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../design/app_theme_definition.dart';
import '../../design/components/app_glass_surface.dart';
import '../../design/components/playback_progress.dart';
import '../../design/design_tokens.dart';
import 'player_state.dart';

final class MobilePlayerControls extends StatelessWidget {
  const MobilePlayerControls({
    super.key,
    required this.state,
    required this.onSeek,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onPlaybackMode,
    required this.onQualityChanged,
    required this.onQueue,
  });

  final PlayerState state;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPlaybackMode;
  final ValueChanged<String> onQualityChanged;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    final track = state.current!;
    final tokens = AppTokens.of(context);
    return AppGlassSurface(
      key: const Key('player-mobile-controls'),
      role: AppGlassRole.clear,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title.isEmpty ? track.id : track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.section,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${track.artist} · ${state.quality == 'flac' ? '无损' : state.quality}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.metadata.copyWith(
                        color: tokens.foregroundSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                key: const Key('player-mobile-quality'),
                width: 92,
                child: ShadSelect<String>(
                  initialValue: state.quality,
                  options: const [
                    ShadOption(value: '128k', child: Text('128k')),
                    ShadOption(value: '320k', child: Text('320k')),
                    ShadOption(value: 'flac', child: Text('无损')),
                  ],
                  selectedOptionBuilder: (context, value) => Text(
                    value == 'flac' ? '无损' : value,
                    maxLines: 1,
                    softWrap: false,
                    style: AppTypography.metadata,
                  ),
                  onChanged: (value) {
                    if (value != null) onQualityChanged(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          PlaybackProgress(
            key: const Key('player-mobile-progress'),
            position: state.position,
            duration: state.duration,
            hitExtent: 44,
            onSeek: onSeek,
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            key: const Key('player-mobile-transport'),
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _TransportButton(
                    key: const Key('player-mobile-playback-mode'),
                    label: _playbackModeLabel,
                    icon: _playbackModeIcon,
                    onPressed: onPlaybackMode,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TransportButton(
                      key: const Key('player-previous'),
                      label: '上一首',
                      icon: LucideIcons.skipBack,
                      enabled: state.canPrevious,
                      onPressed: onPrevious,
                    ),
                    const SizedBox(width: 12),
                    _TransportButton(
                      key: const Key('player-play-pause'),
                      label: _playLabel,
                      icon: state.playing
                          ? LucideIcons.pause
                          : LucideIcons.play,
                      prominent: true,
                      loading:
                          state.processing == PlayerProcessing.loading ||
                          state.processing == PlayerProcessing.buffering,
                      onPressed: onPlayPause,
                    ),
                    const SizedBox(width: 12),
                    _TransportButton(
                      key: const Key('player-next'),
                      label: '下一首',
                      icon: LucideIcons.skipForward,
                      enabled: state.canNext,
                      onPressed: onNext,
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _TransportButton(
                    key: const Key('player-mobile-queue'),
                    label: '播放队列',
                    icon: LucideIcons.listMusic,
                    onPressed: onQueue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _playLabel {
    if (state.processing == PlayerProcessing.loading ||
        state.processing == PlayerProcessing.buffering) {
      return '正在加载';
    }
    return state.playing ? '暂停' : '播放';
  }

  String get _playbackModeLabel => switch (state.playbackMode) {
    PlaybackMode.sequential => '顺序播放',
    PlaybackMode.repeatOne => '单曲循环',
    PlaybackMode.shuffle => '随机播放',
  };

  IconData get _playbackModeIcon => switch (state.playbackMode) {
    PlaybackMode.sequential => LucideIcons.listOrdered,
    PlaybackMode.repeatOne => LucideIcons.repeat1,
    PlaybackMode.shuffle => LucideIcons.shuffle,
  };
}

final class _TransportButton extends StatelessWidget {
  const _TransportButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
    this.prominent = false,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;
  final bool prominent;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final button = prominent
        ? Material(
            color: tokens.foreground,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled && !loading ? onPressed : null,
              child: SizedBox.square(
                dimension: 56,
                child: Center(
                  child: loading
                      ? SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tokens.background,
                          ),
                        )
                      : Icon(icon, size: 23, color: tokens.background),
                ),
              ),
            ),
          )
        : ShadButton.ghost(
            width: 44,
            height: 44,
            padding: EdgeInsets.zero,
            enabled: enabled,
            onPressed: enabled ? onPressed : null,
            child: Icon(icon, size: 20),
          );
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: enabled && !loading,
        label: label,
        child: button,
      ),
    );
  }
}
