import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/app_error.dart';
import '../../design/app_breakpoints.dart';
import '../../design/components/app_bottom_sheet.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_mobile_chrome.dart';
import '../../design/components/app_playback_button.dart';
import '../../design/components/app_states.dart';
import '../../design/components/status_badge.dart';
import '../../design/design_tokens.dart';
import '../player/player_controller.dart';
import '../player/player_state.dart';
import '../search/search_track_artwork.dart';
import 'recommendation_controller.dart';
import 'recommendation_models.dart';

enum _FeedbackAction { track, artist }

final class RecommendationScreen extends StatefulWidget {
  const RecommendationScreen({
    super.key,
    required this.controller,
    required this.player,
    required this.loadPicture,
    this.onBack,
    this.embedded = false,
  });

  final RecommendationController controller;
  final PlayerController player;
  final Future<Uri?> Function(RecommendationItem item) loadPicture;
  final VoidCallback? onBack;
  final bool embedded;

  @override
  State<RecommendationScreen> createState() => _RecommendationScreenState();
}

final class _RecommendationScreenState extends State<RecommendationScreen> {
  late final RecommendationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    unawaited(_controller.load());
  }

  @override
  void didUpdateWidget(covariant RecommendationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, _controller) &&
        !identical(widget.controller, oldWidget.controller)) {
      widget.controller.dispose();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _play(int index) async {
    final items = _controller.state.snapshot?.items ?? const [];
    if (items.isEmpty) return;
    await widget.player.playTracks(
      items.map((item) => item.track).toList(growable: false),
      startIndex: index,
      contexts: items
          .map((item) => PlaybackContext(recommendationItemId: item.id))
          .toList(growable: false),
      queueKind: PlayerQueueKind.dailyRecommendation,
    );
  }

  Future<void> _feedback(RecommendationItem item) async {
    final artist = item.track.artist.trim();
    final action = await AppBottomSheet.showActions<_FeedbackAction>(
      context,
      title: '减少类似推荐',
      message: '反馈只影响推荐画像，不会删除播放历史、下载或歌单。',
      actions: [
        const AppBottomSheetAction(
          value: _FeedbackAction.track,
          label: '不再推荐这首歌',
          destructive: true,
        ),
        if (artist.isNotEmpty)
          AppBottomSheetAction(
            value: _FeedbackAction.artist,
            label: '减少推荐歌手「$artist」',
            destructive: true,
          ),
      ],
    );
    if (!mounted || action == null) return;
    final result = switch (action) {
      _FeedbackAction.track => await _controller.dislikeTrack(item),
      _FeedbackAction.artist => await _controller.dislikeArtist(item),
    };
    if (!mounted || result == null) return;
    showAppMessage(context, title: '已调整推荐', message: '下一批推荐会避开这类内容。');
  }

  Future<void> _toggleInterest(RecommendationItem item) async {
    final wasInterested = item.feedback.interested;
    final result = await _controller.toggleInterest(item);
    if (!mounted || result == null) return;
    showAppMessage(
      context,
      title: wasInterested ? '已取消感兴趣' : '已标记感兴趣',
      message: '这会影响下一批及之后的推荐。',
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final state = _controller.state;
      final snapshot = state.snapshot;
      final mobile =
          classifyLayout(MediaQuery.sizeOf(context)) == AppLayoutClass.mobile;
      return ColoredBox(
        key: Key(
          widget.embedded
              ? 'recommendations-embedded-layout'
              : mobile
              ? 'recommendations-mobile-layout'
              : 'recommendations-wide-layout',
        ),
        color: AppTokens.of(context).background,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            mobile ? 16 : 38,
            widget.embedded ? 12 : (mobile ? 20 : 34),
            mobile ? 16 : 38,
            48,
          ),
          children: [
            if (!widget.embedded)
              _Header(
                mobile: mobile,
                onBack: widget.onBack,
                snapshot: snapshot,
                refreshing: state.refreshing,
                onRefresh: _controller.refresh,
                onPlayAll: snapshot?.items.isEmpty == false
                    ? () => _play(0)
                    : null,
              )
            else
              _EmbeddedActions(
                snapshot: snapshot,
                refreshing: state.refreshing,
                onRefresh: _controller.refresh,
                onPlayAll: snapshot?.items.isEmpty == false
                    ? () => _play(0)
                    : null,
              ),
            if (state.loading) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (state.cached) ...[
              const SizedBox(height: 14),
              const AppNotice(
                title: '正在显示上次完整推荐',
                message: 'Service 暂不可用时不会生成本地替代，也不会写入新的曝光记录。',
              ),
            ],
            if (state.error case final error?) ...[
              const SizedBox(height: 14),
              AppNotice.error(
                title: snapshot == null ? '推荐加载失败' : '推荐更新失败',
                message: appErrorMessage(error, fallback: '每日推荐暂时不可用，请稍后重试。'),
              ),
            ],
            const SizedBox(height: 18),
            if (snapshot == null && !state.loading)
              AppRetryState(
                message: '还没有可显示的每日推荐',
                retryLabel: '重试',
                onRetry: _controller.load,
              )
            else if (snapshot != null) ...[
              _StatusPanel(snapshot: snapshot),
              const SizedBox(height: 16),
              if (snapshot.items.isEmpty)
                _WarmingState(status: snapshot.status)
              else
                for (var index = 0; index < snapshot.items.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RecommendationRow(
                      key: ValueKey(snapshot.items[index].id),
                      item: snapshot.items[index],
                      index: index,
                      mobile: mobile,
                      busy: state.feedbackItemId == snapshot.items[index].id,
                      interestPending:
                          state.feedbackItemId == snapshot.items[index].id &&
                          state.feedbackOperation ==
                              RecommendationFeedbackOperation.interested,
                      loadPicture: widget.loadPicture,
                      onPlay: () => _play(index),
                      onToggleInterest: () =>
                          _toggleInterest(snapshot.items[index]),
                      onFeedback: () => _feedback(snapshot.items[index]),
                    ),
                  ),
            ],
          ],
        ),
      );
    },
  );
}

final class _Header extends StatelessWidget {
  const _Header({
    required this.mobile,
    required this.snapshot,
    required this.refreshing,
    required this.onRefresh,
    required this.onPlayAll,
    this.onBack,
  });

  final bool mobile;
  final DailyRecommendations? snapshot;
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback? onPlayAll;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppMobilePageHeader(
            title: '每日推荐',
            eyebrow: '根据你的收听持续更新',
            onBack: onBack,
          ),
          const SizedBox(height: 14),
          _ActionRow(
            refreshing: refreshing,
            onRefresh: onRefresh,
            onPlayAll: onPlayAll,
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('根据你的收听持续更新', style: AppTypography.metadata),
              SizedBox(height: 4),
              Text('每日推荐', style: AppTypography.display),
            ],
          ),
        ),
        _ActionRow(
          refreshing: refreshing,
          onRefresh: onRefresh,
          onPlayAll: onPlayAll,
        ),
      ],
    );
  }
}

final class _EmbeddedActions extends StatelessWidget {
  const _EmbeddedActions({
    required this.snapshot,
    required this.refreshing,
    required this.onRefresh,
    required this.onPlayAll,
  });

  final DailyRecommendations? snapshot;
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback? onPlayAll;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: _ActionRow(
      refreshing: refreshing,
      onRefresh: onRefresh,
      onPlayAll: onPlayAll,
    ),
  );
}

final class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.refreshing,
    required this.onRefresh,
    required this.onPlayAll,
  });

  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback? onPlayAll;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      AppButton(
        key: const Key('recommendations-refresh'),
        variant: ShadButtonVariant.outline,
        loading: refreshing,
        onPressed: onRefresh,
        leading: const Icon(LucideIcons.refreshCw, size: 16),
        child: Text(refreshing ? '生成中' : '换一批'),
      ),
      AppButton.playback(
        key: const Key('recommendations-play-all'),
        onPressed: onPlayAll,
        leading: const AppPlaybackGlyph.play(size: 18),
        child: const Text('播放全部'),
      ),
    ],
  );
}

final class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.snapshot});

  final DailyRecommendations snapshot;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      AppStatusBadge(
        label: switch (snapshot.status) {
          RecommendationStatus.warming => '正在建立推荐画像',
          RecommendationStatus.generating => '正在生成新推荐',
          RecommendationStatus.ready => '今日推荐',
          RecommendationStatus.degraded => '部分音源可用',
          RecommendationStatus.stale => '上次完整推荐',
          RecommendationStatus.disabled => '推荐已关闭',
        },
        tone: switch (snapshot.status) {
          RecommendationStatus.ready => StatusTone.success,
          RecommendationStatus.degraded => StatusTone.warning,
          RecommendationStatus.stale => StatusTone.warning,
          RecommendationStatus.disabled => StatusTone.neutral,
          _ => StatusTone.neutral,
        },
      ),
      AppStatusBadge(label: '${snapshot.items.length} 首'),
      if (snapshot.sourceCoverage.isNotEmpty)
        AppStatusBadge(label: snapshot.sourceCoverage.join(' / ')),
    ],
  );
}

final class _WarmingState extends StatelessWidget {
  const _WarmingState({required this.status});

  final RecommendationStatus status;

  @override
  Widget build(BuildContext context) => AppEmptyState(
    message: switch (status) {
      RecommendationStatus.generating => '正在生成完整推荐，完成后会自动更新',
      RecommendationStatus.disabled =>
        '推荐已关闭，请在 Service 功能设置中填写 MusicBrainz 地址。',
      RecommendationStatus.stale => '上一份完整推荐目前没有可显示的歌曲。',
      _ => 'Service 正在采样公开歌单并建立你的推荐画像',
    },
  );
}

final class _RecommendationRow extends StatelessWidget {
  const _RecommendationRow({
    super.key,
    required this.item,
    required this.index,
    required this.mobile,
    required this.busy,
    required this.interestPending,
    required this.loadPicture,
    required this.onPlay,
    required this.onToggleInterest,
    required this.onFeedback,
  });

  final RecommendationItem item;
  final int index;
  final bool mobile;
  final bool busy;
  final bool interestPending;
  final Future<Uri?> Function(RecommendationItem item) loadPicture;
  final VoidCallback onPlay;
  final VoidCallback onToggleInterest;
  final VoidCallback onFeedback;

  @override
  Widget build(BuildContext context) {
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.track.title.isEmpty ? '未知歌曲' : item.track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.title,
        ),
        const SizedBox(height: 3),
        Text(
          item.track.artist.isEmpty ? item.track.source : item.track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.metadata.copyWith(
            color: AppTokens.of(context).foregroundSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          recommendationReasonLabel(item.reason),
          maxLines: mobile ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.metadata.copyWith(
            color: AppTokens.of(context).muted,
          ),
        ),
      ],
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppStatusBadge(
          label: item.bucket == RecommendationBucket.newTrack ? '新发现' : '熟悉',
          tone: item.bucket == RecommendationBucket.newTrack
              ? StatusTone.success
              : StatusTone.neutral,
        ),
        const SizedBox(width: 6),
        IconButton(
          key: Key('recommendation-interest-${item.id}'),
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
              : const Icon(LucideIcons.thumbsUp, size: 18),
        ),
        IconButton(
          key: Key('recommendation-feedback-${item.id}'),
          tooltip: '不感兴趣',
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          onPressed: busy ? null : onFeedback,
          icon: busy && !interestPending
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.thumbsDown, size: 18),
        ),
        AppPlaybackIconButton(
          tooltip: '播放${item.track.title}',
          onPressed: onPlay,
          child: const AppPlaybackGlyph.play(size: 22),
        ),
      ],
    );
    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: mobile
          ? Column(
              children: [
                Row(
                  children: [
                    SearchTrackArtwork(
                      track: item.track,
                      loadPicture: (_) => loadPicture(item),
                      size: 54,
                      borderRadius: 10,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: details),
                  ],
                ),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: controls),
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    '${index + 1}'.padLeft(2, '0'),
                    style: AppTypography.counter.copyWith(
                      color: AppTokens.of(context).muted,
                    ),
                  ),
                ),
                SearchTrackArtwork(
                  track: item.track,
                  loadPicture: (_) => loadPicture(item),
                  size: 48,
                  borderRadius: 9,
                ),
                const SizedBox(width: 14),
                Expanded(child: details),
                const SizedBox(width: 12),
                controls,
              ],
            ),
    );
  }
}

String recommendationReasonLabel(RecommendationReason reason) {
  final seed = reason.seedTrackName?.trim();
  final labels = reason.labels
      .where((label) => label.trim().isNotEmpty)
      .join(' · ');
  return switch (reason.type) {
    RecommendationReasonType.playlistCooccurrence =>
      seed == null || seed.isEmpty ? '与你喜欢的歌曲经常一起出现' : '因为你听过《$seed》',
    RecommendationReasonType.artistAffinity =>
      labels.isEmpty ? '来自你常听的歌手' : '你常听的歌手 · $labels',
    RecommendationReasonType.albumAffinity =>
      labels.isEmpty ? '来自你喜欢的专辑方向' : '相似专辑 · $labels',
    RecommendationReasonType.tagAffinity =>
      labels.isEmpty ? '符合你最近的音乐偏好' : labels,
    RecommendationReasonType.familiarReplay => '值得再次播放',
    RecommendationReasonType.exploration => '为你拓展新的音乐方向',
  };
}
