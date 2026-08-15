/* Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4 */

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../../design/app_theme_definition.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_glass_surface.dart';
import '../../design/design_tokens.dart';
import 'player_controller.dart';

final class DesktopQueuePopover extends StatefulWidget {
  const DesktopQueuePopover({
    super.key,
    required this.controller,
    this.accentColor,
  });

  final PlayerController controller;
  final Color? accentColor;

  @override
  State<DesktopQueuePopover> createState() => _DesktopQueuePopoverState();
}

final class _DesktopQueuePopoverState extends State<DesktopQueuePopover> {
  late final ScrollController scrollController;
  String? mutationError;
  bool clearing = false;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(
      initialScrollOffset: math.max(
        0,
        widget.controller.state.currentIndex * 56 - 224,
      ),
    );
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  Future<void> clearQueue() async {
    final confirmed = await showAppDestructiveDialog(
      context,
      title: '清空播放队列？',
      message: '当前播放将停止，此操作无法撤销。',
      cancelLabel: '取消',
      confirmLabel: '清空',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      clearing = true;
      mutationError = null;
    });
    final cleared = await widget.controller.clearQueue();
    if (!mounted || cleared) return;
    setState(() {
      clearing = false;
      mutationError = '播放器未能停止，请重试。';
    });
  }

  Future<void> removeAt(int index) async {
    setState(() => mutationError = null);
    if (await widget.controller.removeAt(index) || !mounted) return;
    setState(() => mutationError = '未能移除这首歌曲，请重试。');
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final maxHeight = math.min(MediaQuery.sizeOf(context).height * .68, 544.0);
    final height = (72.0 + state.queue.length * 56.0).clamp(140.0, maxHeight);
    return AppGlassSurface(
      key: const Key('player-desktop-queue-popover'),
      role: AppGlassRole.sheet,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: 360,
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Text('播放队列', style: AppTypography.title),
                  const Spacer(),
                  Text(
                    '${state.queue.length} 首',
                    style: AppTypography.metadata.copyWith(
                      color: AppTokens.of(context).muted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AppButton(
                    key: const Key('player-desktop-queue-clear'),
                    variant: ShadButtonVariant.ghost,
                    loading: clearing,
                    onPressed: state.queue.isEmpty || clearing
                        ? null
                        : clearQueue,
                    child: Text(
                      '清空',
                      style: TextStyle(color: AppTokens.of(context).danger),
                    ),
                  ),
                ],
              ),
            ),
            if (mutationError case final message?)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: AppNotice.error(title: '队列操作失败', message: message),
              ),
            Expanded(
              child: ListView.builder(
                key: const Key('player-desktop-queue-list'),
                controller: scrollController,
                itemExtent: 56,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                itemCount: state.queue.length,
                itemBuilder: (context, index) => _DesktopQueueRow(
                  key: Key('desktop-queue-track-${state.queue[index].id}'),
                  track: state.queue[index],
                  active: index == state.currentIndex,
                  onPressed: () => widget.controller.playIndex(index),
                  onRemove: () => removeAt(index),
                  accentColor: widget.accentColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _DesktopQueueRow extends StatelessWidget {
  const _DesktopQueueRow({
    super.key,
    required this.track,
    required this.active,
    required this.onPressed,
    required this.onRemove,
    required this.accentColor,
  });

  final Track track;
  final bool active;
  final VoidCallback onPressed;
  final VoidCallback onRemove;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final accent = accentColor ?? tokens.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.control),
        onTap: active ? null : onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: active
                    ? Icon(LucideIcons.audioLines, size: 17, color: accent)
                    : null,
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title.isEmpty ? track.id : track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.title.copyWith(
                        fontSize: 14,
                        color: active ? accent : tokens.foreground,
                      ),
                    ),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.metadata.copyWith(
                        color: tokens.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: '从队列移除',
                child: ShadButton.ghost(
                  key: Key('player-desktop-queue-remove-${track.id}'),
                  width: 36,
                  height: 36,
                  padding: EdgeInsets.zero,
                  onPressed: onRemove,
                  child: const Icon(LucideIcons.x, size: 17),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
