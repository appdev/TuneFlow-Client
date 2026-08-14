import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../../design/app_breakpoints.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_mobile_chrome.dart';
import '../../design/components/app_states.dart';
import '../../design/components/playlist_card.dart';
import '../../design/design_tokens.dart';
import 'playlist_discovery_controller.dart';

final class PlaylistDiscoveryView extends StatefulWidget {
  const PlaylistDiscoveryView({
    super.key,
    required this.controller,
    required this.onOpenPlaylist,
  });

  final PlaylistDiscoveryController controller;
  final ValueChanged<CatalogCollection> onOpenPlaylist;

  @override
  State<PlaylistDiscoveryView> createState() => _PlaylistDiscoveryViewState();
}

final class _PlaylistDiscoveryViewState extends State<PlaylistDiscoveryView> {
  var categoriesExpanded = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller.state.phase == DiscoveryPhase.idle) {
      unawaited(widget.controller.load());
    }
  }

  Future<void> _toggleCategories(bool mobile) async {
    final filters = widget.controller.state.filters;
    if (filters == null) return;
    if (!mobile) {
      setState(() => categoriesExpanded = !categoriesExpanded);
      return;
    }
    await showAppSheet<void>(
      context,
      title: '全部分类',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 480),
        child: SingleChildScrollView(
          child: _CategoryGroups(
            filters: filters,
            selectedTagId: widget.controller.state.tagId,
            onSelected: (id) {
              Navigator.of(context).pop();
              unawaited(widget.controller.selectTag(id));
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final mobile =
          classifyLayout(MediaQuery.sizeOf(context)) == AppLayoutClass.mobile;
      return ColoredBox(
        key: const Key('playlist-square-layout'),
        color: AppTokens.of(context).background,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            mobile ? 16 : 38,
            mobile ? 20 : 34,
            mobile ? 16 : 38,
            48,
          ),
          children: [
            if (mobile)
              const AppMobilePageHeader(
                title: '歌单广场',
                eyebrow: '动态平台 · Service API',
              )
            else ...[
              Text(
                '动态平台 · Service API',
                style: AppTypography.metadata.copyWith(
                  color: AppTokens.of(context).muted,
                ),
              ),
              const SizedBox(height: 4),
              const Text('歌单广场', style: AppTypography.display),
            ],
            const SizedBox(height: 18),
            if (state.providers.isNotEmpty)
              _ChipRow(
                children: [
                  for (final provider in state.providers)
                    AppButton(
                      variant: state.source == provider.id
                          ? ShadButtonVariant.primary
                          : ShadButtonVariant.outline,
                      onPressed: () => unawaited(
                        widget.controller.selectProvider(provider.id),
                      ),
                      child: Text(provider.name.replaceAll('音乐', '')),
                    ),
                ],
              ),
            if (state.filters case final filters?) ...[
              const SizedBox(height: 14),
              _ChipRow(
                children: [
                  for (final sort in filters.sorts)
                    AppButton(
                      variant: state.sortId == sort.id
                          ? ShadButtonVariant.primary
                          : ShadButtonVariant.outline,
                      onPressed: () =>
                          unawaited(widget.controller.selectSort(sort.id)),
                      child: Text(sort.name),
                    ),
                  AppButton(
                    key: const Key('playlist-categories-toggle'),
                    variant: ShadButtonVariant.outline,
                    onPressed: () => _toggleCategories(mobile),
                    leading: Icon(
                      !mobile && categoriesExpanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.listFilter,
                      size: 16,
                    ),
                    child: const Text('全部分类'),
                  ),
                ],
              ),
              if (filters.hotTags.isNotEmpty) ...[
                const SizedBox(height: 10),
                _ChipRow(
                  children: [
                    AppButton(
                      variant: state.tagId.isEmpty
                          ? ShadButtonVariant.secondary
                          : ShadButtonVariant.ghost,
                      onPressed: () =>
                          unawaited(widget.controller.selectTag('')),
                      child: const Text('默认'),
                    ),
                    for (final tag in filters.hotTags)
                      AppButton(
                        variant: state.tagId == tag.id
                            ? ShadButtonVariant.secondary
                            : ShadButtonVariant.ghost,
                        onPressed: () =>
                            unawaited(widget.controller.selectTag(tag.id)),
                        child: Text(tag.name),
                      ),
                  ],
                ),
              ],
              if (!mobile && categoriesExpanded) ...[
                const SizedBox(height: 14),
                _CategoryGroups(
                  filters: filters,
                  selectedTagId: state.tagId,
                  onSelected: (id) =>
                      unawaited(widget.controller.selectTag(id)),
                ),
              ],
            ],
            const SizedBox(height: 22),
            if (state.filtersError case final error?)
              _ErrorPanel(
                title: '无法读取歌单分类',
                error: error,
                onRetry: widget.controller.retryFilters,
              )
            else if (state.phase == DiscoveryPhase.loading &&
                state.items.isEmpty)
              const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (state.browseError case final error?) ...[
                _ErrorPanel(
                  title: state.stale ? '刷新失败，正在显示上次结果' : '歌单加载失败',
                  error: error,
                  onRetry: widget.controller.retryBrowse,
                ),
                const SizedBox(height: 14),
              ],
              if (state.items.isEmpty)
                const AppEmptyState(message: '当前分类没有歌单')
              else
                _PlaylistGrid(
                  items: state.items,
                  mobile: mobile,
                  onOpen: widget.onOpenPlaylist,
                ),
              if (state.items.isNotEmpty) ...[
                const SizedBox(height: 18),
                _Pager(state: state, controller: widget.controller),
              ],
            ],
          ],
        ),
      );
    },
  );
}

final class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Wrap(spacing: 8, runSpacing: 8, children: children),
  );
}

final class _CategoryGroups extends StatelessWidget {
  const _CategoryGroups({
    required this.filters,
    required this.selectedTagId,
    required this.onSelected,
  });

  final PlaylistDiscoveryFilters filters;
  final String selectedTagId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTokens.of(context).surface,
      border: Border.all(color: AppTokens.of(context).borderSoft),
      borderRadius: BorderRadius.circular(AppRadii.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in filters.groups) ...[
          Text(group.name, style: AppTypography.metadata),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final tag in group.tags)
                AppButton(
                  variant: selectedTagId == tag.id
                      ? ShadButtonVariant.secondary
                      : ShadButtonVariant.ghost,
                  onPressed: () => onSelected(tag.id),
                  child: Text(tag.name),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    ),
  );
}

final class _PlaylistGrid extends StatelessWidget {
  const _PlaylistGrid({
    required this.items,
    required this.mobile,
    required this.onOpen,
  });

  final List<CatalogCollection> items;
  final bool mobile;
  final ValueChanged<CatalogCollection> onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gap = mobile ? 14.0 : 16.0;
      final columns = playlistGalleryColumnCount(
        availableWidth: constraints.maxWidth,
        spacing: gap,
      );
      final width = playlistGalleryItemExtent(
        availableWidth: constraints.maxWidth,
        spacing: gap,
        columns: columns,
      );
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final collection in items)
            SizedBox(
              key: Key('playlist-card-${collection.source}-${collection.id}'),
              width: width,
              child: PlaylistCard(
                playlist: PlaylistSummary(
                  id: collection.id,
                  name: collection.name,
                  source: [
                    if (collection.author.isNotEmpty) collection.author,
                    if (collection.total != null) '${collection.total} 首',
                    if (collection.playCount case final count?) '$count 播放',
                  ].join(' · '),
                ),
                imageUrl: collection.imageUrl,
                onPressed: () => onOpen(collection),
                variant: PlaylistCardVariant.gallery,
              ),
            ),
        ],
      );
    },
  );
}

final class _Pager extends StatelessWidget {
  const _Pager({required this.state, required this.controller});
  final PlaylistDiscoveryState state;
  final PlaylistDiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final pages = state.total == null || state.limit <= 0
        ? null
        : (state.total! / state.limit).ceil().clamp(1, 999999);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          state.total == null
              ? '${state.items.length} 个'
              : '共 ${state.total} 个',
        ),
        const SizedBox(width: 16),
        IconButton(
          tooltip: '上一页',
          onPressed: state.page > 1
              ? () => unawaited(controller.goToPage(state.page - 1))
              : null,
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        Text(pages == null ? '第 ${state.page} 页' : '${state.page} / $pages'),
        IconButton(
          tooltip: '下一页',
          onPressed: state.hasMore || (pages != null && state.page < pages)
              ? () => unawaited(controller.goToPage(state.page + 1))
              : null,
          icon: const Icon(LucideIcons.chevronRight),
        ),
      ],
    );
  }
}

final class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.title,
    required this.error,
    required this.onRetry,
  });

  final String title;
  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppNotice.error(title: title, message: _discoveryErrorMessage(error)),
      const SizedBox(height: 10),
      AppButton(
        variant: ShadButtonVariant.outline,
        onPressed: () => unawaited(onRetry()),
        child: const Text('重试'),
      ),
    ],
  );
}

String _discoveryErrorMessage(Object error) {
  final message = error.toString();
  if (message.contains('没有可用的歌单发现平台')) {
    return '当前 Service 没有可用的歌单发现平台，请检查 Service 版本或音源状态。';
  }
  return '歌单数据暂时无法读取，请稍后重试。';
}
