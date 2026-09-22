import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../../app/app_error.dart';
import '../../design/app_breakpoints.dart';
import '../../design/components/app_bottom_sheet.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_playback_button.dart';
import '../../design/components/app_mobile_chrome.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_form.dart';
import '../../design/components/app_states.dart';
import '../../design/components/artwork.dart';
import '../../design/components/track_actions.dart';
import '../../design/design_tokens.dart';
import '../catalog/catalog_track_list.dart';
import 'playlist_detail_controller.dart';

final class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.controller,
    required this.playTracks,
    this.onDeleted,
    this.onBack,
    this.currentTrack,
  });

  final PlaylistDetailController controller;
  final PlayTracks playTracks;
  final VoidCallback? onDeleted;
  final VoidCallback? onBack;
  final Track? Function()? currentTrack;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

final class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final _tracksScroll = ScrollController();
  final _trackListKey = GlobalKey();
  final _rowKeys = <(String, String), GlobalKey>{};
  bool _bulkBusy = false;
  @override
  void initState() {
    super.initState();
    widget.controller.refresh();
  }

  @override
  void dispose() {
    _tracksScroll.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> _bulk(bool remove) async {
    final controller = widget.controller;
    if (_bulkBusy || controller.selectedTracks.isEmpty) return;
    setState(() => _bulkBusy = true);
    try {
      if (remove) {
        final accepted = await AppBottomSheet.showDestructive(
          context,
          title: '移除所选歌曲？',
          message: '从当前歌单移除 ${controller.selectedTracks.length} 首歌曲，服务器文件会保留。',
          confirmLabel: '移除',
        );
        if (!accepted || !mounted) return;
        await controller.removeSelected();
      } else {
        final targets = await controller.moveTargets();
        if (!mounted) return;
        if (targets.isEmpty) {
          showAppMessage(context, title: '没有其他歌单');
          return;
        }
        final target = await AppBottomSheet.showSelection<String>(
          context,
          title: '添加所选歌曲到歌单',
          selectedValue: targets.first.id,
          options: [
            for (final playlist in targets)
              AppBottomSheetSelection(
                value: playlist.id,
                label: playlist.displayName,
              ),
          ],
        );
        if (!mounted || target == null) return;
        await controller.addSelectedTo(target);
      }
    } on Object catch (error) {
      if (mounted) {
        showAppMessage(
          context,
          title: '批量操作失败',
          message: appErrorMessage(error, fallback: '所选歌曲已保留，请重试。'),
          destructive: true,
        );
      }
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  void _locate() {
    final track = widget.currentTrack?.call();
    final visible = widget.controller.visibleTracks;
    final index = visible.indexWhere(
      (t) => t.source == track?.source && t.id == track?.id,
    );
    if (index < 0) {
      showAppMessage(context, title: '当前歌曲不在此列表中');
      return;
    }
    final rowContext = _rowKeys[(track!.source, track.id)]?.currentContext;
    if (rowContext != null) {
      Scrollable.ensureVisible(
        rowContext,
        alignment: .35,
        duration: const Duration(milliseconds: 250),
      );
    } else if (_tracksScroll.hasClients) {
      final width = _trackListKey.currentContext?.size?.width ?? 900;
      _tracksScroll.animateTo(
        (index * (width < 900 ? 54.0 : 58.0)).clamp(
          0,
          _tracksScroll.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget _tools() {
    final controller = widget.controller;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            key: const Key('playlist-filter'),
            placeholder: '筛选歌单中的歌曲、歌手或专辑',
            onChanged: controller.setQuery,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              AppButton(
                variant: ShadButtonVariant.ghost,
                onPressed: _bulkBusy
                    ? null
                    : () => controller.setSelecting(!controller.selecting),
                child: Text(controller.selecting ? '完成选择' : '多选'),
              ),
              if (controller.selecting) ...[
                AppButton(
                  variant: ShadButtonVariant.ghost,
                  onPressed: _bulkBusy ? null : controller.selectAllVisible,
                  child: Text('全选 / 取消（${controller.selected.length}）'),
                ),
                AppButton(
                  variant: ShadButtonVariant.outline,
                  onPressed: _bulkBusy || controller.selected.isEmpty
                      ? null
                      : () => _bulk(false),
                  child: const Text('添加到歌单'),
                ),
                AppButton(
                  variant: ShadButtonVariant.outline,
                  onPressed: _bulkBusy || controller.selected.isEmpty
                      ? null
                      : () => _bulk(true),
                  child: const Text('移除所选'),
                ),
              ],
              AppButton(
                variant: ShadButtonVariant.ghost,
                onPressed: () async {
                  final sort = await AppBottomSheet.showSelection<PlaylistSort>(
                    context,
                    title: '当前歌单排序',
                    selectedValue: controller.sort,
                    options: const [
                      AppBottomSheetSelection(
                        value: PlaylistSort.original,
                        label: '歌单原顺序（可拖动）',
                      ),
                      AppBottomSheetSelection(
                        value: PlaylistSort.title,
                        label: '歌曲名称',
                      ),
                      AppBottomSheetSelection(
                        value: PlaylistSort.artist,
                        label: '歌手',
                      ),
                      AppBottomSheetSelection(
                        value: PlaylistSort.album,
                        label: '专辑',
                      ),
                    ],
                  );
                  if (mounted && sort != null) controller.setSort(sort);
                },
                child: const Text('排序'),
              ),
              if (widget.currentTrack != null)
                AppButton(
                  variant: ShadButtonVariant.ghost,
                  onPressed: _locate,
                  child: const Text('定位当前歌曲'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _rename(String current) async {
    final name = TextEditingController(text: current);
    final accepted = await AppBottomSheet.showContent<bool>(
      context,
      title: '重命名歌单',
      message: '新名称将同步到当前 Service。',
      child: Builder(
        builder: (modalContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(controller: name, placeholder: '歌单名称'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    expands: true,
                    variant: ShadButtonVariant.outline,
                    onPressed: () => Navigator.pop(modalContext, false),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    expands: true,
                    onPressed: () => Navigator.pop(modalContext, true),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final value = name.text.trim();
    name.dispose();
    if (accepted == true && value.isNotEmpty && value != current) {
      await widget.controller.rename(value);
    }
  }

  Future<void> _delete(String name) async {
    final accepted = await AppBottomSheet.showDestructive(
      context,
      title: '删除歌单？',
      message: '“$name”及其排序将从 Service 中删除，此操作不可撤销。',
      cancelLabel: '取消',
      confirmLabel: '删除',
    );
    if (!accepted) return;
    await widget.controller.delete();
    widget.onDeleted?.call();
  }

  Future<void> _clear(String name) async {
    final accepted = await AppBottomSheet.showDestructive(
      context,
      title: '清空歌单？',
      message: '将移除“$name”中的全部歌曲，歌单本身会保留。',
      confirmLabel: '清空',
    );
    if (!accepted || !mounted) return;
    await widget.controller.clear();
  }

  Future<void> _trackActions(Track track) async {
    final action = await AppBottomSheet.showActions<String>(
      context,
      title: track.title.isEmpty ? track.id : track.title,
      actions: const [
        AppBottomSheetAction(value: 'move', label: '移动到其他歌单'),
        AppBottomSheetAction(
          value: 'remove',
          label: '从当前歌单移除',
          destructive: true,
        ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'remove') {
      await widget.controller.remove(track.id);
      return;
    }
    final targets = await widget.controller.moveTargets();
    if (!mounted) return;
    if (targets.isEmpty) {
      showAppMessage(context, title: '没有可移动到的歌单');
      return;
    }
    final target = await AppBottomSheet.showSelection<String>(
      context,
      title: '移动到歌单',
      options: [
        for (final playlist in targets)
          AppBottomSheetSelection(
            value: playlist.id,
            label: playlist.displayName,
          ),
      ],
      selectedValue: targets.first.id,
    );
    if (!mounted || target == null) return;
    await widget.controller.move(track, target);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final detail = state.detail;
      final keys = detail?.tracks.map((t) => (t.source, t.id)).toSet() ?? {};
      _rowKeys.removeWhere((key, _) => !keys.contains(key));
      if (state.loading && detail == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (detail == null) {
        return AppRetryState(
          message: state.error == null
              ? '歌单不存在'
              : appErrorMessage(state.error!, fallback: '歌单详情暂时无法加载，请稍后重试。'),
          retryLabel: '重试',
          onRetry: widget.controller.refresh,
        );
      }
      return KeyedSubtree(
        key: const Key('playlist-detail-route'),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mobile =
                classifyLayout(MediaQuery.sizeOf(context)) ==
                AppLayoutClass.mobile;
            return ColoredBox(
              key: Key(
                mobile ? 'playlist-detail-mobile' : 'playlist-detail-wide',
              ),
              color: AppTokens.of(context).background,
              child: mobile
                  ? SingleChildScrollView(
                      key: const Key('playlist-detail-mobile-scroll'),
                      child: Column(
                        children: [
                          if (widget.onBack case final onBack?) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: AppMobileBackButton(onPressed: onBack),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                          ],
                          if (state.error != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: AppNotice.error(
                                title: '显示的是上次数据',
                                message: appErrorMessage(
                                  state.error!,
                                  fallback: '歌单内容暂时无法刷新，请稍后重试。',
                                ),
                              ),
                            ),
                          _PlaylistHero(
                            detail: detail,
                            mobile: true,
                            onPlayAll: detail.tracks.isEmpty
                                ? null
                                : () => widget.controller.playAll(
                                    widget.playTracks,
                                  ),
                            onRename: () => _rename(detail.displayName),
                            onDelete: () => _delete(detail.displayName),
                            onClear: detail.tracks.isEmpty
                                ? null
                                : () => _clear(detail.displayName),
                          ),
                          _tools(),
                          if (detail.tracks.isEmpty)
                            const SizedBox(
                              height: 220,
                              child: AppEmptyState(message: '歌单中还没有歌曲'),
                            )
                          else
                            _TrackList(
                              key: _trackListKey,
                              scrollController: _tracksScroll,
                              rowKey: (track) => _rowKeys.putIfAbsent((
                                track.source,
                                track.id,
                              ), GlobalKey.new),
                              detail: detail,
                              controller: widget.controller,
                              playTracks: widget.playTracks,
                              mobile: true,
                              onTrackActions: _trackActions,
                            ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        if (state.error != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: AppNotice.error(
                              title: '显示的是上次数据',
                              message: appErrorMessage(
                                state.error!,
                                fallback: '歌单内容暂时无法刷新，请稍后重试。',
                              ),
                            ),
                          ),
                        _PlaylistHero(
                          detail: detail,
                          mobile: mobile,
                          onPlayAll: detail.tracks.isEmpty
                              ? null
                              : () => widget.controller.playAll(
                                  widget.playTracks,
                                ),
                          onRename: () => _rename(detail.displayName),
                          onDelete: () => _delete(detail.displayName),
                          onClear: detail.tracks.isEmpty
                              ? null
                              : () => _clear(detail.displayName),
                        ),
                        _tools(),
                        Expanded(
                          child: detail.tracks.isEmpty
                              ? const AppEmptyState(message: '歌单中还没有歌曲')
                              : _TrackList(
                                  key: _trackListKey,
                                  scrollController: _tracksScroll,
                                  rowKey: (track) => _rowKeys.putIfAbsent((
                                    track.source,
                                    track.id,
                                  ), GlobalKey.new),
                                  detail: detail,
                                  controller: widget.controller,
                                  playTracks: widget.playTracks,
                                  mobile: mobile,
                                  onTrackActions: _trackActions,
                                ),
                        ),
                      ],
                    ),
            );
          },
        ),
      );
    },
  );
}

final class _PlaylistHero extends StatelessWidget {
  const _PlaylistHero({
    required this.detail,
    required this.mobile,
    required this.onPlayAll,
    required this.onRename,
    required this.onDelete,
    required this.onClear,
  });

  final PlaylistDetail detail;
  final bool mobile;
  final VoidCallback? onPlayAll;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final imageUrl = detail.tracks
        .map((track) => track.raw['pic'])
        .whereType<String>()
        .firstOrNull;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '我的歌单 · ${detail.tracks.length} 首',
          style: AppTypography.metadata.copyWith(
            color: AppTokens.of(context).muted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          detail.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.display,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          detail.source?.isNotEmpty == true
              ? '来源：${detail.source}'
              : '数据与当前 Service 保持同步',
          style: AppTypography.body.copyWith(
            color: AppTokens.of(context).foregroundSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            AppButton.playback(
              key: const Key('play-all'),
              onPressed: onPlayAll,
              leading: const AppPlaybackGlyph.play(size: 18),
              child: const Text('播放全部'),
            ),
            if (!detail.isBuiltIn) ...[
              AppButton(
                key: const Key('playlist-rename'),
                variant: ShadButtonVariant.outline,
                onPressed: onRename,
                child: const Text('重命名'),
              ),
              AppButton(
                key: const Key('playlist-delete'),
                variant: ShadButtonVariant.outline,
                onPressed: onDelete,
                child: Text(
                  '删除',
                  style: TextStyle(color: AppTokens.of(context).danger),
                ),
              ),
            ],
            AppButton(
              key: const Key('playlist-clear'),
              variant: ShadButtonVariant.outline,
              onPressed: onClear,
              child: const Text('清空'),
            ),
          ],
        ),
      ],
    );
    if (mobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${detail.tracks.length} 首',
              style: AppTypography.metadata.copyWith(
                color: AppTokens.of(context).muted,
              ),
            ),
            const SizedBox(height: 3),
            Text(detail.displayName, style: AppTypography.mobilePageTitle),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  AppArtwork(
                    key: const Key('playlist-hero-artwork'),
                    imageUrl: imageUrl,
                    seed: detail.id,
                    semanticLabel: '${detail.displayName}封面',
                    size: constraints.maxWidth / 1.5,
                    width: constraints.maxWidth,
                    height: constraints.maxWidth / 1.5,
                    showFallback: false,
                  ),
                  Positioned(
                    left: 22,
                    bottom: 20,
                    child: Text(
                      detail.displayName,
                      style: AppTypography.section,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                AppButton(
                  key: const Key('play-all'),
                  onPressed: onPlayAll,
                  child: const Text('播放全部'),
                ),
                const SizedBox(width: 8),
                if (!detail.isBuiltIn) ...[
                  AppButton(
                    key: const Key('playlist-delete'),
                    variant: ShadButtonVariant.outline,
                    onPressed: onDelete,
                    child: Text(
                      '删除',
                      style: TextStyle(color: AppTokens.of(context).danger),
                    ),
                  ),
                  Offstage(
                    child: AppButton(
                      key: const Key('playlist-rename'),
                      onPressed: onRename,
                      child: const Text('重命名'),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                AppButton(
                  key: const Key('playlist-clear'),
                  variant: ShadButtonVariant.outline,
                  onPressed: onClear,
                  child: const Text('清空'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(38, 28, 38, 20),
      child: SizedBox(
        height: 240,
        child: Row(
          children: [
            Expanded(
              flex: 58,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    AppArtwork(
                      key: const Key('playlist-hero-artwork'),
                      imageUrl: imageUrl,
                      seed: detail.id,
                      semanticLabel: '${detail.displayName}封面',
                      size: 240,
                      width: constraints.maxWidth,
                      height: 240,
                      showFallback: false,
                    ),
                    Positioned(
                      left: 22,
                      bottom: 20,
                      child: Text(
                        detail.displayName,
                        style: AppTypography.section,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 34),
            Expanded(flex: 42, child: copy),
          ],
        ),
      ),
    );
  }
}

final class _TrackList extends StatelessWidget {
  const _TrackList({
    super.key,
    required this.scrollController,
    required this.rowKey,
    required this.detail,
    required this.controller,
    required this.playTracks,
    required this.mobile,
    required this.onTrackActions,
  });

  final PlaylistDetail detail;
  final ScrollController scrollController;
  final GlobalKey Function(Track) rowKey;
  final PlaylistDetailController controller;
  final PlayTracks playTracks;
  final bool mobile;
  final ValueChanged<Track> onTrackActions;

  @override
  Widget build(BuildContext context) {
    if (!mobile) return _buildDesktop(context);
    final tracks = controller.visibleTracks;
    final list = ReorderableListView.builder(
      buildDefaultDragHandles: !controller.filtered && !controller.selecting,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        mobile ? 16 : 38,
        mobile ? 10 : 0,
        mobile ? 16 : 38,
        30,
      ),
      itemCount: tracks.length,
      onReorderItem: (oldIndex, newIndex) {
        if (controller.filtered || controller.selecting) return;
        controller.reorder(position: newIndex, trackIds: [tracks[oldIndex].id]);
      },
      itemBuilder: (context, index) {
        final track = tracks[index];
        return Row(
          key: rowKey(track),
          children: [
            if (controller.selecting)
              Checkbox(
                semanticLabel: '选择 ${track.title}',
                value: controller.selected.contains((track.source, track.id)),
                onChanged: (_) => controller.toggleSelection(
                  track,
                  range: HardwareKeyboard.instance.isShiftPressed,
                ),
              ),
            Expanded(
              child: _PlaylistTrackRow(
                track: track,
                index: index,
                onPlay: () => controller.selecting
                    ? controller.toggleSelection(track)
                    : playTracks(tracks, startIndex: index),
                onRemove: () => controller.remove(track.id),
                onMore: () => onTrackActions(track),
                mobile: mobile,
              ),
            ),
          ],
        );
      },
    );
    return list;
  }

  Widget _buildDesktop(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final tracks = controller.visibleTracks;
      final compact = constraints.maxWidth < 900;
      final showAlbum = constraints.maxWidth >= 1080;
      final showDuration = constraints.maxWidth >= 720;
      return Padding(
        padding: const EdgeInsets.fromLTRB(38, 0, 38, 30),
        child: Column(
          children: [
            CatalogTrackTableHeader(
              showAlbum: showAlbum,
              showDuration: showDuration,
              compact: compact,
            ),
            Expanded(
              child: ReorderableListView.builder(
                scrollController: scrollController,
                buildDefaultDragHandles: false,
                itemCount: tracks.length,
                onReorderItem: (oldIndex, newIndex) {
                  if (controller.filtered || controller.selecting) return;
                  controller.reorder(
                    position: newIndex,
                    trackIds: [tracks[oldIndex].id],
                  );
                },
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return CatalogTrackRow(
                    key: ValueKey((track.source, track.id)),
                    index: index + 1,
                    track: track,
                    providers: const [],
                    aggregate: false,
                    showAlbum: showAlbum,
                    showDuration: showDuration,
                    compact: compact,
                    loadPicture: (value) async {
                      final embedded = value.raw['pic'];
                      return embedded is String ? Uri.tryParse(embedded) : null;
                    },
                    onPlay: () => controller.selecting
                        ? controller.toggleSelection(
                            track,
                            range: HardwareKeyboard.instance.isShiftPressed,
                          )
                        : playTracks(tracks, startIndex: index),
                    onFavorite: () => onTrackActions(track),
                    favoriteIcon: LucideIcons.ellipsis,
                    favoriteTooltip: '更多操作',
                    actions: const [],
                    trailing: controller.selecting
                        ? Checkbox(
                            semanticLabel: '选择 ${track.title}',
                            value: controller.selected.contains((
                              track.source,
                              track.id,
                            )),
                            onChanged: (_) => controller.toggleSelection(
                              track,
                              range: HardwareKeyboard.instance.isShiftPressed,
                            ),
                          )
                        : controller.filtered
                        ? const SizedBox.shrink()
                        : ReorderableDragStartListener(
                            index: index,
                            child: const Tooltip(
                              message: '拖动排序',
                              child: Icon(LucideIcons.gripVertical, size: 18),
                            ),
                          ),
                    rowKeyPrefix: 'playlist',
                    singleTap: true,
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

final class _PlaylistTrackRow extends StatelessWidget {
  const _PlaylistTrackRow({
    required this.track,
    required this.index,
    required this.onPlay,
    required this.onRemove,
    required this.onMore,
    required this.mobile,
  });

  final Track track;
  final int index;
  final VoidCallback onPlay;
  final VoidCallback onRemove;
  final VoidCallback onMore;
  final bool mobile;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadii.control),
      onTap: onPlay,
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTokens.of(context).borderSoft),
          ),
        ),
        child: Row(
          children: [
            if (!mobile)
              SizedBox(
                width: 32,
                child: Text(
                  '${index + 1}'.padLeft(2, '0'),
                  style: AppTypography.counter.copyWith(
                    color: AppTokens.of(context).muted,
                  ),
                ),
              ),
            AppArtwork(
              imageUrl: track.raw['pic'] as String?,
              seed: '${track.source}:${track.id}',
              semanticLabel: '${track.title}封面',
              size: mobile ? 38 : 38,
              borderRadius: 9,
              showFallback: false,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title.isEmpty ? track.id : track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.title,
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.metadata.copyWith(
                      color: AppTokens.of(context).foregroundSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '更多操作',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: onMore,
              icon: const Icon(LucideIcons.ellipsis, size: 19),
            ),
          ],
        ),
      ),
    ),
  );
}
