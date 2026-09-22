/* Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4 */

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../design/app_theme_definition.dart';
import '../../design/components/app_glass_surface.dart';
import '../../design/components/app_playback_button.dart';
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
    this.onVolumeChanged,
    this.onMuteChanged,
    this.onPlaybackRateChanged,
  });

  final PlayerState state;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPlaybackMode;
  final ValueChanged<String> onQualityChanged;
  final VoidCallback onQueue;
  final ValueChanged<double>? onVolumeChanged;
  final ValueChanged<bool>? onMuteChanged;
  final ValueChanged<double>? onPlaybackRateChanged;

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
                  decoration: ShadDecoration.none,
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
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              SizedBox(
                width: 84,
                child: ShadSelect<double>(
                  key: const Key('player-mobile-speed'),
                  initialValue: state.playbackRate,
                  decoration: ShadDecoration.none,
                  options: const [
                    ShadOption<double>(value: .5, child: Text('0.5x')),
                    ShadOption<double>(value: .75, child: Text('0.75x')),
                    ShadOption<double>(value: 1, child: Text('1.0x')),
                    ShadOption<double>(value: 1.25, child: Text('1.25x')),
                    ShadOption<double>(value: 1.5, child: Text('1.5x')),
                    ShadOption<double>(value: 2, child: Text('2.0x')),
                  ],
                  selectedOptionBuilder: (context, value) => Text('${value}x'),
                  onChanged: (value) {
                    if (value != null) onPlaybackRateChanged?.call(value);
                  },
                ),
              ),
              IconButton(
                key: const Key('player-mobile-mute'),
                tooltip: state.muted ? '取消静音' : '静音',
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                onPressed: onMuteChanged == null
                    ? null
                    : () => onMuteChanged!.call(!state.muted),
                icon: Icon(
                  state.muted || state.volume == 0
                      ? LucideIcons.volumeX
                      : LucideIcons.volume2,
                  size: 18,
                ),
              ),
              Expanded(
                child: Slider(
                  key: const Key('player-mobile-volume'),
                  value: state.muted ? 0 : state.volume,
                  onChanged: onVolumeChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          PlaybackProgress(
            key: const Key('player-mobile-progress'),
            trackIdentity: (track.source, track.id),
            position: state.position,
            duration: state.duration,
            hitExtent: 44,
            onSeek: onSeek,
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            key: const Key('player-mobile-transport'),
            height: 64,
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
                      icon: AppPlaybackIcons.previous,
                      iconSize: 28,
                      enabled: state.canPrevious,
                      onPressed: onPrevious,
                    ),
                    const SizedBox(width: 8),
                    _TransportButton(
                      key: const Key('player-play-pause'),
                      label: _playLabel,
                      icon: state.isPlaybackActive
                          ? AppPlaybackIcons.pause
                          : AppPlaybackIcons.play,
                      iconSize: 36,
                      prominent: true,
                      loading: state.isPlaybackLoading,
                      onPressed: onPlayPause,
                    ),
                    const SizedBox(width: 8),
                    _TransportButton(
                      key: const Key('player-next'),
                      label: '下一首',
                      icon: AppPlaybackIcons.next,
                      iconSize: 28,
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
    if (state.isPlaybackLoading) {
      return '正在加载';
    }
    return state.isPlaybackActive ? '暂停' : '播放';
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
    this.iconSize = 20,
    this.enabled = true,
    this.prominent = false,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final bool enabled;
  final bool prominent;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final button = prominent
        ? Material(
            color: tokens.playbackAction,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onPressed : null,
              child: SizedBox.square(
                dimension: 64,
                child: Center(
                  child: loading
                      ? SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tokens.playbackActionForeground,
                          ),
                        )
                      : Icon(
                          icon,
                          size: iconSize,
                          color: tokens.playbackActionForeground,
                        ),
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
            child: Icon(icon, size: iconSize),
          );
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: button,
      ),
    );
  }
}
