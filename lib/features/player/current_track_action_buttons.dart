import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/app_error.dart';
import '../../design/components/app_feedback.dart';
import 'current_track_actions_controller.dart';

final class CurrentTrackActionButtons extends StatelessWidget {
  const CurrentTrackActionButtons({
    super.key,
    required this.controller,
    required this.keyPrefix,
    this.foreground,
    this.selectedForeground,
    this.selectedBackground,
  });

  final CurrentTrackActionsController controller;
  final String keyPrefix;
  final Color? foreground;
  final Color? selectedForeground;
  final Color? selectedBackground;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final favoriteLabel = controller.favorite ? '取消收藏' : '收藏当前歌曲';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            enabled: controller.canToggleFavorite,
            selected: controller.favorite,
            label: favoriteLabel,
            child: Tooltip(
              message: favoriteLabel,
              child: ShadButton.raw(
                key: Key('$keyPrefix-favorite'),
                variant: controller.favorite
                    ? ShadButtonVariant.secondary
                    : ShadButtonVariant.ghost,
                width: 44,
                height: 44,
                padding: EdgeInsets.zero,
                backgroundColor: controller.favorite
                    ? selectedBackground
                    : null,
                foregroundColor: controller.favorite
                    ? selectedForeground ?? foreground
                    : foreground,
                enabled: controller.canToggleFavorite,
                onPressed: () => _toggleFavorite(context),
                child: controller.favoritePending
                    ? _ActionProgress(key: Key('$keyPrefix-favorite-loading'))
                    : const Icon(LucideIcons.heart, size: 20),
              ),
            ),
          ),
          Semantics(
            button: true,
            enabled: controller.canDownload,
            label: '下载当前歌曲',
            child: Tooltip(
              message: '下载当前歌曲',
              child: ShadButton.raw(
                key: Key('$keyPrefix-download'),
                variant: ShadButtonVariant.ghost,
                width: 44,
                height: 44,
                padding: EdgeInsets.zero,
                foregroundColor: foreground,
                enabled: controller.canDownload,
                onPressed: () => _download(context),
                child: controller.downloadPending
                    ? _ActionProgress(key: Key('$keyPrefix-download-loading'))
                    : const Icon(LucideIcons.download, size: 20),
              ),
            ),
          ),
        ],
      );
    },
  );

  Future<void> _toggleFavorite(BuildContext context) async {
    try {
      await controller.toggleFavorite();
    } on Object catch (error) {
      if (!context.mounted) return;
      showAppMessage(
        context,
        title: '收藏失败',
        message: appErrorMessage(error, fallback: '操作未完成，请稍后重试。'),
        destructive: true,
      );
    }
  }

  Future<void> _download(BuildContext context) async {
    try {
      await controller.downloadCurrent();
      if (!context.mounted) return;
      showAppMessage(context, title: '已加入下载队列');
    } on Object catch (error) {
      if (!context.mounted) return;
      showAppMessage(
        context,
        title: '下载失败',
        message: appErrorMessage(error, fallback: '操作未完成，请稍后重试。'),
        destructive: true,
      );
    }
  }
}

final class _ActionProgress extends StatelessWidget {
  const _ActionProgress({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
