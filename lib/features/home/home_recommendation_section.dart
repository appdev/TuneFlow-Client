import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_playback_button.dart';
import '../../design/components/app_states.dart';
import '../../design/components/status_badge.dart';
import '../../design/design_tokens.dart';
import '../player/player_controller.dart';
import '../player/player_state.dart';
import '../recommendations/recommendation_controller.dart';
import '../recommendations/recommendation_models.dart';
import '../search/search_track_artwork.dart';

int homeRecommendationLimit(double width) {
  if (width >= 1200) return 10;
  if (width >= 720) return 8;
  return 6;
}

final class HomeRecommendationSection extends StatelessWidget {
  const HomeRecommendationSection({
    super.key,
    required this.controller,
    required this.player,
    required this.loadPicture,
    required this.onViewAll,
    required this.onSettings,
  });

  final RecommendationController controller;
  final PlayerController? player;
  final Future<Uri?> Function(RecommendationItem item) loadPicture;
  final VoidCallback onViewAll;
  final VoidCallback onSettings;

  Future<void> _play(List<RecommendationItem> items, int index) async {
    if (player == null || items.isEmpty) return;
    await player!.playTracks(
      items.map((item) => item.track).toList(growable: false),
      startIndex: index,
      contexts: items
          .map((item) => PlaybackContext(recommendationItemId: item.id))
          .toList(growable: false),
      queueKind: PlayerQueueKind.dailyRecommendation,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final state = controller.state;
    final snapshot = state.snapshot;
    if (snapshot?.status == RecommendationStatus.disabled) {
      return Column(
        key: const Key('home-recommendations-disabled'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppNotice(
            title: '每日推荐已关闭',
            message: '在 Service 功能设置中填写 MusicBrainz 地址后即可启用。',
            compact: true,
          ),
          const SizedBox(height: 10),
          AppButton(
            variant: ShadButtonVariant.outline,
            onPressed: onSettings,
            child: const Text('打开推荐设置'),
          ),
        ],
      );
    }
    if (snapshot == null && state.loading) {
      return const AppEmptyState(message: '正在读取今日推荐…');
    }
    if (snapshot == null && state.error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppNotice.error(title: '每日推荐暂时不可用', message: '首页其他内容仍可继续使用。'),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              variant: ShadButtonVariant.outline,
              onPressed: controller.load,
              child: const Text('重试推荐'),
            ),
          ),
        ],
      );
    }
    if (snapshot == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final items = snapshot.items
            .take(homeRecommendationLimit(width))
            .toList(growable: false);
        final columns = width >= 1200
            ? 5
            : width >= 720
            ? 4
            : 2;
        const spacing = 12.0;
        final itemExtent = (width - spacing * (columns - 1)) / columns;
        final cardExtent = itemExtent + (itemExtent < 250 ? 132 : 108);
        return Column(
          key: const Key('home-recommendations-section'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('每日推荐', style: AppTypography.section),
                      const SizedBox(height: 3),
                      Text(
                        snapshot.status == RecommendationStatus.stale
                            ? '正在展示 ${snapshot.snapshotLocalDate ?? '上一次'} 的完整推荐'
                            : '依据这台 Service 上的播放习惯生成',
                        style: AppTypography.metadata.copyWith(
                          color: AppTokens.of(context).muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('home-recommendations-refresh'),
                  tooltip: '刷新每日推荐',
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  onPressed: state.refreshing ? null : controller.refresh,
                  icon: state.refreshing
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.refreshCw, size: 18),
                ),
                AppButton(
                  key: const Key('home-recommendations-view-all'),
                  variant: ShadButtonVariant.ghost,
                  onPressed: onViewAll,
                  child: const Text('查看全部'),
                ),
              ],
            ),
            if (snapshot.status == RecommendationStatus.stale) ...[
              const SizedBox(height: 10),
              AppNotice(
                title: '今日推荐生成失败',
                message: snapshot.lastErrorCode == null
                    ? '暂时保留上一份完整推荐。'
                    : '暂时保留上一份完整推荐（${snapshot.lastErrorCode}）。',
                compact: true,
              ),
            ],
            if (snapshot.status == RecommendationStatus.degraded) ...[
              const SizedBox(height: 10),
              const AppNotice(
                title: '部分数据源暂不可用',
                message: '当前列表仍然可以播放，下一次生成会继续补全。',
                compact: true,
              ),
            ],
            const SizedBox(height: 14),
            if (items.isEmpty)
              AppEmptyState(
                message:
                    snapshot.status == RecommendationStatus.warming ||
                        snapshot.status == RecommendationStatus.generating
                    ? 'Service 正在生成今日推荐，完成后会自动更新。'
                    : '今天还没有可展示的推荐。',
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  mainAxisExtent: cardExtent,
                ),
                itemBuilder: (context, index) => _RecommendationCard(
                  key: const Key('home-recommendation-card'),
                  item: items[index],
                  busy: state.feedbackItemId == items[index].id,
                  interestPending:
                      state.feedbackItemId == items[index].id &&
                      state.feedbackOperation ==
                          RecommendationFeedbackOperation.interested,
                  loadPicture: loadPicture,
                  onPlay: () => _play(items, index),
                  onToggleInterest: () =>
                      controller.toggleInterest(items[index]),
                  onDislike: () => controller.dislikeTrack(items[index]),
                ),
              ),
          ],
        );
      },
    );
  }
}

final class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    super.key,
    required this.item,
    required this.busy,
    required this.interestPending,
    required this.loadPicture,
    required this.onPlay,
    required this.onToggleInterest,
    required this.onDislike,
  });

  final RecommendationItem item;
  final bool busy;
  final bool interestPending;
  final Future<Uri?> Function(RecommendationItem item) loadPicture;
  final VoidCallback onPlay;
  final VoidCallback onToggleInterest;
  final VoidCallback onDislike;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '播放${item.track.title}',
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPlay,
        child: ShadCard(
          padding: const EdgeInsets.all(10),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SearchTrackArtwork(
                  track: item.track,
                  loadPicture: (_) => loadPicture(item),
                  size: constraints.maxWidth,
                  borderRadius: 12,
                ),
                const SizedBox(height: 9),
                Text(
                  item.track.title.isEmpty ? '未知歌曲' : item.track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.title,
                ),
                const SizedBox(height: 2),
                Text(
                  item.track.artist.isEmpty
                      ? item.track.source
                      : item.track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.metadata.copyWith(
                    color: AppTokens.of(context).muted,
                  ),
                ),
                const Spacer(),
                if (constraints.maxWidth < 230) ...[
                  AppStatusBadge(
                    label: item.bucket == RecommendationBucket.newTrack
                        ? '新发现'
                        : '熟悉',
                    tone: item.bucket == RecommendationBucket.newTrack
                        ? StatusTone.success
                        : StatusTone.neutral,
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _RecommendationActions(
                      item: item,
                      busy: busy,
                      interestPending: interestPending,
                      onToggleInterest: onToggleInterest,
                      onDislike: onDislike,
                      onPlay: onPlay,
                    ),
                  ),
                ] else
                  Row(
                    children: [
                      AppStatusBadge(
                        label: item.bucket == RecommendationBucket.newTrack
                            ? '新发现'
                            : '熟悉',
                        tone: item.bucket == RecommendationBucket.newTrack
                            ? StatusTone.success
                            : StatusTone.neutral,
                      ),
                      const Spacer(),
                      _RecommendationActions(
                        item: item,
                        busy: busy,
                        interestPending: interestPending,
                        onToggleInterest: onToggleInterest,
                        onDislike: onDislike,
                        onPlay: onPlay,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final class _RecommendationActions extends StatelessWidget {
  const _RecommendationActions({
    required this.item,
    required this.busy,
    required this.interestPending,
    required this.onToggleInterest,
    required this.onDislike,
    required this.onPlay,
  });

  final RecommendationItem item;
  final bool busy;
  final bool interestPending;
  final VoidCallback onToggleInterest;
  final VoidCallback onDislike;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: Key('home-recommendation-interest-${item.id}'),
        tooltip: item.feedback.interested ? '取消感兴趣' : '感兴趣',
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        style: item.feedback.interested
            ? IconButton.styleFrom(
                foregroundColor: AppTokens.of(context).success,
                backgroundColor: AppTokens.of(
                  context,
                ).success.withValues(alpha: 0.14),
              )
            : null,
        onPressed: busy ? null : onToggleInterest,
        icon: interestPending
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(LucideIcons.thumbsUp, size: 17),
      ),
      IconButton(
        tooltip: '不再推荐这首歌',
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        onPressed: busy ? null : onDislike,
        icon: const Icon(LucideIcons.thumbsDown, size: 17),
      ),
      AppPlaybackIconButton(
        tooltip: '播放${item.track.title}',
        onPressed: onPlay,
        child: const AppPlaybackGlyph.play(size: 20),
      ),
    ],
  );
}
