import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../../design/app_breakpoints.dart';
import '../../design/components/app_button.dart';
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
  });

  final PlaylistDetailController controller;
  final PlayTracks playTracks;
  final VoidCallback? onDeleted;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

final class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.refresh();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> _rename(String current) async {
    final name = TextEditingController(text: current);
    final accepted = await showShadDialog<bool>(
      context: context,
      builder: (dialogContext) => ShadDialog(
        title: const Text('重命名歌单'),
        description: const Text('新名称将同步到当前 Service。'),
        actions: [
          AppButton(
            variant: ShadButtonVariant.outline,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          AppButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('保存'),
          ),
        ],
        child: AppTextField(controller: name, placeholder: '歌单名称'),
      ),
    );
    final value = name.text.trim();
    name.dispose();
    if (accepted == true && value.isNotEmpty && value != current) {
      await widget.controller.rename(value);
    }
  }

  Future<void> _delete(String name) async {
    final accepted = await showAppDestructiveDialog(
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final detail = state.detail;
      if (state.loading && detail == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (detail == null) {
        return AppRetryState(
          message: state.error?.toString() ?? '歌单不存在',
          retryLabel: '重试',
          onRetry: widget.controller.refresh,
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final mobile =
              classifyLayout(constraints.maxWidth) == AppLayoutClass.mobile;
          return ColoredBox(
            key: Key(
              mobile ? 'playlist-detail-mobile' : 'playlist-detail-wide',
            ),
            color: AppTokens.of(context).background,
            child: Column(
              children: [
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: AppNotice.error(
                      title: '显示的是上次数据',
                      message: state.error.toString(),
                    ),
                  ),
                _PlaylistHero(
                  detail: detail,
                  mobile: mobile,
                  onPlayAll: detail.tracks.isEmpty
                      ? null
                      : () => widget.controller.playAll(widget.playTracks),
                  onRename: () => _rename(detail.displayName),
                  onDelete: () => _delete(detail.displayName),
                ),
                Expanded(
                  child: detail.tracks.isEmpty
                      ? const AppEmptyState(message: '歌单中还没有歌曲')
                      : _TrackList(
                          detail: detail,
                          controller: widget.controller,
                          playTracks: widget.playTracks,
                          mobile: mobile,
                        ),
                ),
              ],
            ),
          );
        },
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
  });

  final PlaylistDetail detail;
  final bool mobile;
  final VoidCallback? onPlayAll;
  final VoidCallback onRename;
  final VoidCallback onDelete;

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
            AppButton(
              key: const Key('play-all'),
              onPressed: onPlayAll,
              leading: const Icon(LucideIcons.play, size: 18),
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
    required this.detail,
    required this.controller,
    required this.playTracks,
    required this.mobile,
  });

  final PlaylistDetail detail;
  final PlaylistDetailController controller;
  final PlayTracks playTracks;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    if (!mobile) return _buildDesktop(context);
    final list = ReorderableListView.builder(
      padding: EdgeInsets.fromLTRB(
        mobile ? 16 : 38,
        mobile ? 10 : 0,
        mobile ? 16 : 38,
        30,
      ),
      itemCount: detail.tracks.length,
      onReorder: (oldIndex, newIndex) {
        var position = newIndex;
        if (newIndex > oldIndex) position--;
        controller.reorder(
          position: position,
          trackIds: [detail.tracks[oldIndex].id],
        );
      },
      itemBuilder: (context, index) {
        final track = detail.tracks[index];
        return _PlaylistTrackRow(
          key: ValueKey(track.id),
          track: track,
          index: index,
          onPlay: () => controller.playOne(playTracks, index),
          onRemove: () => controller.remove(track.id),
          mobile: mobile,
        );
      },
    );
    return list;
  }

  Widget _buildDesktop(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
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
                buildDefaultDragHandles: false,
                itemCount: detail.tracks.length,
                onReorder: (oldIndex, newIndex) {
                  var position = newIndex;
                  if (newIndex > oldIndex) position--;
                  controller.reorder(
                    position: position,
                    trackIds: [detail.tracks[oldIndex].id],
                  );
                },
                itemBuilder: (context, index) {
                  final track = detail.tracks[index];
                  return CatalogTrackRow(
                    key: ValueKey('${track.id}-$index'),
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
                    onPlay: () => controller.playOne(playTracks, index),
                    onFavorite: () => controller.remove(track.id),
                    favoriteIcon: LucideIcons.heartMinus,
                    favoriteTooltip: '从歌单移除',
                    actions: const [],
                    trailing: ReorderableDragStartListener(
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
    super.key,
    required this.track,
    required this.index,
    required this.onPlay,
    required this.onRemove,
    required this.mobile,
  });

  final Track track;
  final int index;
  final VoidCallback onPlay;
  final VoidCallback onRemove;
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
              onPressed: onRemove,
              icon: const Icon(LucideIcons.ellipsis, size: 19),
            ),
          ],
        ),
      ),
    ),
  );
}
