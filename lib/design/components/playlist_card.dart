import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../api/models.dart';
import '../design_tokens.dart';
import 'artwork.dart';

const double playlistGalleryMaxItemExtent = 220;
const double playlistGalleryMetadataExtent = 64;

int playlistGalleryColumnCount({
  required double availableWidth,
  required double spacing,
  int minimum = 2,
}) {
  if (!availableWidth.isFinite || availableWidth <= 0) return minimum;
  final columns =
      ((availableWidth + spacing) / (playlistGalleryMaxItemExtent + spacing))
          .ceil();
  return math.max(minimum, columns);
}

double playlistGalleryItemExtent({
  required double availableWidth,
  required double spacing,
  required int columns,
}) => (availableWidth - spacing * (columns - 1)) / columns;

double playlistGalleryChildAspectRatio(double itemExtent) =>
    itemExtent / (itemExtent + playlistGalleryMetadataExtent);

final class PlaylistCard extends StatelessWidget {
  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.onPressed,
    this.onDelete,
    this.imageUrl,
    this.variant = PlaylistCardVariant.row,
  }) : collectionId = null,
       collectionName = null,
       collectionMetadata = null;

  const PlaylistCard.collection({
    super.key,
    required String id,
    required String name,
    required String metadata,
    required this.onPressed,
    this.imageUrl,
    this.variant = PlaylistCardVariant.row,
  }) : playlist = null,
       collectionId = id,
       collectionName = name,
       collectionMetadata = metadata,
       onDelete = null;

  final PlaylistSummary? playlist;
  final String? collectionId;
  final String? collectionName;
  final String? collectionMetadata;
  final VoidCallback onPressed;
  final VoidCallback? onDelete;
  final Uri? imageUrl;
  final PlaylistCardVariant variant;

  String get _id => playlist?.id ?? collectionId!;
  String get _name => playlist?.displayName ?? collectionName!;
  String get _metadata =>
      collectionMetadata ??
      (playlist is PlaylistDetail
          ? '${(playlist! as PlaylistDetail).tracks.length} 首'
          : playlist!.source?.isEmpty == false
          ? playlist!.source!
          : 'Service 歌单');

  @override
  Widget build(BuildContext context) {
    if (variant == PlaylistCardVariant.gallery) {
      return Semantics(
        button: true,
        label: '打开$_name',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.compactCard),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            onTap: onPressed,
            onLongPress: onDelete,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => AppArtwork(
                    imageUrl: imageUrl?.toString(),
                    seed: _id,
                    semanticLabel: '$_name封面',
                    size: constraints.maxWidth,
                    icon: LucideIcons.listMusic,
                    borderRadius: AppRadii.compactCard,
                    showFallbackBorder: false,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.title,
                ),
                const SizedBox(height: 2),
                Text(
                  _metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.metadata.copyWith(
                    color: AppTokens.of(context).foregroundSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ShadCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      radius: BorderRadius.circular(AppRadii.card),
      backgroundColor: AppTokens.of(context).surface,
      shadows: AppShadows.panel,
      child: Row(
        children: [
          if (imageUrl != null) ...[
            AppArtwork(
              imageUrl: imageUrl.toString(),
              seed: _id,
              semanticLabel: '$_name封面',
              size: 52,
              borderRadius: AppRadii.control,
              icon: LucideIcons.listMusic,
              showFallback: false,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Semantics(
              button: true,
              label: '打开$_name',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onPressed,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.title,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: '删除歌单',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: onDelete,
              icon: const Icon(LucideIcons.trash2),
            ),
        ],
      ),
    );
  }
}

enum PlaylistCardVariant { row, gallery }
