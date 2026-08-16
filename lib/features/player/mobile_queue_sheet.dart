import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../../design/components/app_bottom_sheet.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/design_tokens.dart';
import 'player_controller.dart';
import 'player_state.dart';

final class MobileQueueSheet extends StatefulWidget {
  const MobileQueueSheet({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<MobileQueueSheet> createState() => _MobileQueueSheetState();
}

final class _MobileQueueSheetState extends State<MobileQueueSheet> {
  bool clearing = false;
  String? mutationError;
  VoidCallback? retryMutation;
  int? revealedIndex;

  void revealCurrent(PlayerState state, ScrollController controller) {
    if (state.currentIndex < 0 || revealedIndex == state.currentIndex) return;
    revealedIndex = state.currentIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      final target = (state.currentIndex * 56.0 - 112).clamp(
        0.0,
        controller.position.maxScrollExtent,
      );
      controller.jumpTo(target);
    });
  }

  Future<void> clearQueue() async {
    final confirmed = await AppBottomSheet.showDestructive(
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
      retryMutation = null;
    });
    final cleared = await widget.controller.clearQueue();
    if (!mounted) return;
    if (cleared) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      clearing = false;
      mutationError = '播放器未能停止，请重试。';
      retryMutation = clearQueue;
    });
  }

  Future<void> removeAt(int index) async {
    setState(() {
      mutationError = null;
      retryMutation = null;
    });
    final removed = await widget.controller.removeAt(index);
    if (!mounted) return;
    if (!removed) {
      setState(() {
        mutationError = '未能移除这首歌曲，请重试。';
        retryMutation = () => removeAt(index);
      });
      return;
    }
    if (widget.controller.state.queue.isEmpty) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('player-mobile-queue-sheet'),
    color: Colors.transparent,
    child: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final scrollController = PrimaryScrollController.of(context);
        revealCurrent(state, scrollController);
        return Column(
          children: [
            Padding(
              key: const Key('player-mobile-queue-header'),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Text(
                    '${state.queue.length} 首',
                    style: AppTypography.metadata.copyWith(
                      color: AppTokens.of(context).muted,
                    ),
                  ),
                  const Spacer(),
                  AppButton(
                    key: const Key('player-mobile-queue-clear'),
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
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppNotice.error(title: '队列操作失败', message: message),
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AppButton(
                        variant: ShadButtonVariant.outline,
                        onPressed: clearing ? null : retryMutation,
                        child: const Text('重试'),
                      ),
                    ),
                  ],
                ),
              ),
            if (state.error != null && mutationError == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    const Expanded(child: Text('当前歌曲暂时无法播放')),
                    AppButton(
                      variant: ShadButtonVariant.outline,
                      onPressed: widget.controller.resume,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                key: const Key('player-mobile-queue-list'),
                controller: scrollController,
                itemExtent: 56,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.lg,
                ),
                itemCount: state.queue.length,
                itemBuilder: (context, index) => _MobileQueueRow(
                  track: state.queue[index],
                  state: state,
                  index: index,
                  active: index == state.currentIndex,
                  onSelected: () => widget.controller.playIndex(index),
                  onRemove: () => removeAt(index),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

final class _MobileQueueRow extends StatelessWidget {
  const _MobileQueueRow({
    required this.track,
    required this.state,
    required this.index,
    required this.active,
    required this.onSelected,
    required this.onRemove,
  });

  final Track track;
  final PlayerState state;
  final int index;
  final bool active;
  final VoidCallback onSelected;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      selected: active,
      label: active
          ? '${track.title}，${track.artist}，正在播放'
          : '${track.title}，${track.artist}',
      child: InkWell(
        key: Key('mobile-queue-track-${track.id}'),
        borderRadius: BorderRadius.circular(AppRadii.control),
        onTap: active ? null : onSelected,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            color: active ? tokens.accent.withValues(alpha: .1) : null,
            border: Border(bottom: BorderSide(color: tokens.borderSoft)),
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          padding: const EdgeInsets.only(left: AppSpacing.xs),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child:
                    active &&
                        (state.processing == PlayerProcessing.loading ||
                            state.processing == PlayerProcessing.buffering)
                    ? Center(
                        child: SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tokens.accent,
                          ),
                        ),
                      )
                    : active
                    ? Icon(
                        LucideIcons.audioLines,
                        color: tokens.accent,
                        size: 18,
                      )
                    : null,
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title.isEmpty ? track.id : track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.title.copyWith(
                        fontSize: 14,
                        color: active ? tokens.accent : tokens.foreground,
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
                child: Semantics(
                  button: true,
                  label: '移除${track.title}',
                  child: ShadButton.ghost(
                    key: Key('player-mobile-queue-remove-${track.id}'),
                    width: 44,
                    height: 44,
                    padding: EdgeInsets.zero,
                    onPressed: onRemove,
                    child: const Icon(LucideIcons.x, size: 19),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
