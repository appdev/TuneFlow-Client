import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/app_error.dart';
import '../../design/components/app_bottom_sheet.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_mobile_chrome.dart';
import '../../design/components/app_form.dart';
import '../../design/components/playlist_card.dart';
import '../../design/app_breakpoints.dart';
import '../../design/design_tokens.dart';
import 'playlists_controller.dart';

final class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onOpenLocal,
  });

  final PlaylistsController controller;
  final ValueChanged<String> onOpen;
  final VoidCallback onOpenLocal;

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

final class _PlaylistsScreenState extends State<PlaylistsScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.state.items.isEmpty) widget.controller.refresh();
  }

  @override
  void didUpdateWidget(covariant PlaylistsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.dispose();
    if (widget.controller.state.items.isEmpty) widget.controller.refresh();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = TextEditingController();
    String? validation;
    final accepted = await AppBottomSheet.showContent<bool>(
      context,
      title: '新建歌单',
      message: '歌单将保存在当前 Service。',
      child: StatefulBuilder(
        builder: (modalContext, setModalState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              key: const Key('playlist-name-field'),
              controller: name,
              placeholder: '歌单名称',
            ),
            if (validation != null) ...[
              const SizedBox(height: 8),
              Text(
                validation!,
                style: TextStyle(color: AppTokens.of(modalContext).danger),
              ),
            ],
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
                    onPressed: () {
                      if (name.text.trim().isEmpty) {
                        setModalState(() => validation = '请输入歌单名称');
                        return;
                      }
                      Navigator.pop(modalContext, true);
                    },
                    child: const Text('创建'),
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
    if (accepted != true || value.isEmpty) return;
    try {
      await widget.controller.create(name: value);
    } on Object catch (error) {
      if (mounted) {
        showAppMessage(
          context,
          title: '创建失败',
          message: appErrorMessage(error, fallback: '无法创建歌单，请稍后重试。'),
          destructive: true,
        );
      }
    }
  }

  Future<void> _delete(String id, String name) async {
    final accepted = await AppBottomSheet.showDestructive(
      context,
      title: '删除歌单？',
      message: '“$name”将从 Service 中删除。',
      cancelLabel: '取消',
      confirmLabel: '删除',
    );
    if (accepted) await widget.controller.delete(id);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      return LayoutBuilder(
        builder: (context, constraints) {
          final mobile =
              classifyLayout(MediaQuery.sizeOf(context)) ==
              AppLayoutClass.mobile;
          return ColoredBox(
            key: Key(
              mobile ? 'playlists-gallery-mobile' : 'playlists-gallery-wide',
            ),
            color: AppTokens.of(context).background,
            child: Padding(
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
                    AppMobilePageHeader(
                      title: '我的音乐',
                      eyebrow: '当前 Service',
                      actions: [
                        AppButton(
                          key: const Key('create-playlist'),
                          onPressed: _create,
                          leading: const Icon(LucideIcons.plus, size: 18),
                          child: const Text('新建'),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '当前 Service',
                                style: AppTypography.metadata,
                              ),
                              const SizedBox(height: 3),
                              const Text('我的歌单', style: AppTypography.display),
                            ],
                          ),
                        ),
                        AppButton(
                          key: const Key('create-playlist'),
                          onPressed: _create,
                          leading: const Icon(LucideIcons.plus, size: 18),
                          child: const Text('新建歌单'),
                        ),
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
                      message: appErrorMessage(
                        state.error!,
                        fallback: '歌单暂时无法加载，请稍后重试。',
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, gridConstraints) {
                        final columns = playlistGalleryColumnCount(
                          availableWidth: gridConstraints.maxWidth,
                          spacing: AppSpacing.md,
                        );
                        final itemExtent = playlistGalleryItemExtent(
                          availableWidth: gridConstraints.maxWidth,
                          spacing: AppSpacing.md,
                          columns: columns,
                        );
                        return GridView.builder(
                          key: const Key('playlists-screen'),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: AppSpacing.md,
                                mainAxisSpacing: AppSpacing.md,
                                childAspectRatio:
                                    playlistGalleryChildAspectRatio(itemExtent),
                              ),
                          itemCount: state.items.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              final picture = state.library
                                  .map((item) => item.pictureUrl)
                                  .whereType<Uri>()
                                  .where(
                                    (uri) =>
                                        (uri.scheme == 'http' ||
                                            uri.scheme == 'https') &&
                                        uri.host.isNotEmpty,
                                  )
                                  .firstOrNull;
                              return PlaylistCard.collection(
                                key: const Key('local-library-card'),
                                id: 'local-library',
                                name: '本地音乐',
                                metadata:
                                    state.libraryError != null &&
                                        state.library.isEmpty
                                    ? '暂不可用'
                                    : '${state.library.length} 首',
                                imageUrl: picture,
                                variant: PlaylistCardVariant.gallery,
                                onPressed: widget.onOpenLocal,
                              );
                            }
                            final playlist = state.items[index - 1];
                            final picture = playlist.tracks
                                .map((track) => track.raw['pic'])
                                .whereType<String>()
                                .firstOrNull;
                            return PlaylistCard(
                              key: Key('playlist-${playlist.id}'),
                              playlist: playlist,
                              imageUrl: picture == null
                                  ? null
                                  : Uri.tryParse(picture),
                              variant: PlaylistCardVariant.gallery,
                              onPressed: () => widget.onOpen(playlist.id),
                              onDelete: playlist.isBuiltIn
                                  ? null
                                  : () => _delete(
                                      playlist.id,
                                      playlist.displayName,
                                    ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
