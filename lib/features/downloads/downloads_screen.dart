import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../../design/app_breakpoints.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_mobile_chrome.dart';
import '../../design/components/app_states.dart';
import '../../design/components/artwork.dart';
import '../../design/components/status_badge.dart';
import '../../design/design_tokens.dart';
import 'downloads_controller.dart';

final class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.controller});
  final DownloadsController controller;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

final class _DownloadsScreenState extends State<DownloadsScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.state.jobs.isEmpty) widget.controller.refresh();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        showAppMessage(
          context,
          title: '下载操作失败',
          message: error.toString(),
          destructive: true,
        );
      }
    }
  }

  Future<void> _pauseAll() async {
    final result = await widget.controller.pauseAll();
    if (!mounted || !result.hasFailures) return;
    showAppMessage(
      context,
      title: '部分任务未暂停',
      message:
          '已暂停 ${result.succeededIds.length} 个，失败 ${result.failures.length} 个。',
      destructive: true,
    );
  }

  Future<void> _delete(DownloadJob job) async {
    final accepted = await showAppDestructiveDialog(
      context,
      title: '删除下载任务？',
      message: job.fileName,
      cancelLabel: '取消',
      confirmLabel: '删除',
    );
    if (accepted) await _run(() => widget.controller.delete(job.id));
  }

  Future<void> _actions(DownloadJob job) => showAppSheet<void>(
    context,
    title: job.fileName,
    child: Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (job.canStart)
            AppButton(
              variant: ShadButtonVariant.ghost,
              onPressed: () => _run(() => widget.controller.start(job.id)),
              child: const Text('开始'),
            ),
          if (job.canPause)
            AppButton(
              variant: ShadButtonVariant.ghost,
              onPressed: () => _run(() => widget.controller.pause(job.id)),
              child: const Text('暂停'),
            ),
          if (job.canResume)
            AppButton(
              variant: ShadButtonVariant.ghost,
              onPressed: () => _run(() => widget.controller.resume(job.id)),
              child: const Text('继续'),
            ),
          if (job.canDelete)
            AppButton(
              variant: ShadButtonVariant.destructive,
              onPressed: () => _delete(job),
              child: const Text('删除'),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final state = widget.controller.state;
        final mobile =
            classifyLayout(constraints.maxWidth) == AppLayoutClass.mobile;
        return ColoredBox(
          key: Key(
            mobile ? 'downloads-mobile-layout' : 'downloads-wide-layout',
          ),
          color: AppTokens.of(context).background,
          child: Padding(
            key: const Key('downloads-route'),
            padding: EdgeInsets.fromLTRB(
              mobile ? 16 : 38,
              mobile ? 20 : 34,
              mobile ? 16 : 38,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mobile)
                  const AppMobilePageHeader(title: '下载', eyebrow: '离线曲库')
                else
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('离线曲库', style: AppTypography.metadata),
                            const SizedBox(height: 3),
                            Text('下载管理', style: AppTypography.display),
                          ],
                        ),
                      ),
                      if (state.jobs.any((job) => job.canPause))
                        AppButton(
                          variant: ShadButtonVariant.outline,
                          onPressed: _pauseAll,
                          child: const Text('全部暂停'),
                        ),
                      ...[
                        const SizedBox(width: 8),
                        AppButton(
                          variant: ShadButtonVariant.ghost,
                          onPressed: widget.controller.refresh,
                          leading: const Icon(LucideIcons.refreshCw, size: 18),
                          child: const Text('刷新'),
                        ),
                      ],
                    ],
                  ),
                if (state.loading) ...[
                  const SizedBox(height: AppSpacing.md),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (state.error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppNotice.error(
                    title: state.stale ? '显示的是上次数据' : '加载失败',
                    message: state.error.toString(),
                  ),
                ],
                if (state.lastBulkResult?.hasFailures ?? false) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppNotice.error(
                    title: '批量暂停部分失败',
                    message:
                        '${state.lastBulkResult!.failures.length} 个任务仍需单独处理。',
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppNotice(
                  title: mobile
                      ? 'Service 恢复后将继续排队任务。'
                      : 'Service 断开时，已完成内容仍可播放；排队任务将在恢复后继续。',
                  message: '',
                  compact: true,
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: state.jobs.isEmpty
                      ? const AppEmptyState(message: '暂无 Service 下载任务')
                      : RefreshIndicator(
                          onRefresh: widget.controller.refresh,
                          child: ListView.separated(
                            itemCount: state.jobs.length,
                            separatorBuilder: (_, _) =>
                                SizedBox(height: mobile ? 0 : AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final job = state.jobs[index];
                              return _DownloadCard(
                                job: job,
                                mobile: mobile,
                                loadPicture: widget.controller.loadPicture,
                                onActions: () => _actions(job),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

final class _DownloadCard extends StatelessWidget {
  const _DownloadCard({
    required this.job,
    required this.mobile,
    required this.loadPicture,
    required this.onActions,
  });
  final DownloadJob job;
  final bool mobile;
  final Future<Uri?> Function(Track) loadPicture;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        _DownloadArtwork(track: job.musicInfo, loadPicture: loadPicture),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                job.musicInfo.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.title,
              ),
              const SizedBox(height: 5),
              Text(
                [
                  job.musicInfo.artist,
                  if (mobile) job.quality == 'flac' ? '无损' : job.quality,
                  if (!mobile) _statusDescription(job),
                  if (job.queuePosition case final value?) '队列 $value',
                ].where((value) => value.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.metadata.copyWith(
                  color: AppTokens.of(context).foregroundSecondary,
                ),
              ),
              if (job.warning case final warning?) ...[
                const SizedBox(height: 8),
                Text(
                  _downloadIssueMessage(warning, warning: true),
                  style: TextStyle(color: AppTokens.of(context).warning),
                ),
              ],
              if (job.error case final error?) ...[
                const SizedBox(height: 8),
                Text(
                  _downloadIssueMessage(error),
                  style: TextStyle(color: AppTokens.of(context).danger),
                ),
              ],
            ],
          ),
        ),
        if (!mobile) ...[
          const SizedBox(width: AppSpacing.md),
          AppStatusBadge(
            label: _statusLabel(job.status),
            tone: _statusTone(job.status),
          ),
        ],
        IconButton(
          key: Key('download-actions-${job.id}'),
          tooltip: '下载操作',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: onActions,
          icon: const Icon(LucideIcons.ellipsisVertical),
        ),
      ],
    );
    if (mobile) {
      return Container(
        constraints: const BoxConstraints(minHeight: 70),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTokens.of(context).border),
          ),
        ),
        child: content,
      );
    }
    return ShadCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      radius: BorderRadius.circular(AppRadii.card),
      child: content,
    );
  }
}

final class _DownloadArtwork extends StatelessWidget {
  const _DownloadArtwork({required this.track, required this.loadPicture});

  final Track track;
  final Future<Uri?> Function(Track) loadPicture;

  @override
  Widget build(BuildContext context) {
    final persisted = Uri.tryParse(track.raw['pic'] as String? ?? '');
    if (persisted?.scheme == 'https') return _artwork(persisted);
    return FutureBuilder<Uri?>(
      future: loadPicture(track),
      builder: (context, snapshot) => _artwork(snapshot.data),
    );
  }

  Widget _artwork(Uri? picture) => AppArtwork(
    imageUrl: picture?.toString(),
    seed: '${track.source}:${track.id}',
    semanticLabel: '${track.title}封面',
    size: 38,
    borderRadius: AppRadii.control,
    showFallback: false,
  );
}

String _downloadIssueMessage(String value, {bool warning = false}) {
  final normalized = value.toLowerCase();
  if (normalized.contains('completed download file is missing') ||
      normalized.contains('file is missing')) {
    return '已下载文件缺失，请重新下载';
  }
  if (normalized.contains('unsupported source action') ||
      normalized.contains('source unavailable')) {
    return '当前音源不支持该下载操作，请切换音源';
  }
  if (normalized.contains('network') || normalized.contains('timeout')) {
    return '网络连接异常，恢复后可重试';
  }
  return warning ? '下载任务需要注意，请稍后重试' : '下载失败，请重试或切换音源';
}

String _statusDescription(DownloadJob job) => switch (job.status) {
  DownloadStatus.running => '运行中 ${(job.progress * 100).round()}%',
  DownloadStatus.waiting => '等待中',
  DownloadStatus.paused => '已暂停 ${(job.progress * 100).round()}%',
  DownloadStatus.error => '失败 · 来源不可用',
  DownloadStatus.completed => '已完成',
};

String _statusLabel(DownloadStatus status) => switch (status) {
  DownloadStatus.waiting => '等待',
  DownloadStatus.running => '下载中',
  DownloadStatus.paused => '已暂停',
  DownloadStatus.error => '失败',
  DownloadStatus.completed => '完成',
};

StatusTone _statusTone(DownloadStatus status) => switch (status) {
  DownloadStatus.waiting => StatusTone.neutral,
  DownloadStatus.running => StatusTone.warning,
  DownloadStatus.paused => StatusTone.neutral,
  DownloadStatus.error => StatusTone.danger,
  DownloadStatus.completed => StatusTone.success,
};
