import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../design/components/artwork.dart';
import '../../design/design_tokens.dart';
import 'search_track_metadata.dart';

final class SearchTrackArtwork extends StatefulWidget {
  const SearchTrackArtwork({
    super.key,
    required this.track,
    required this.loadPicture,
    this.size = 44,
    this.borderRadius = 10,
  });

  final Track track;
  final Future<Uri?> Function(Track) loadPicture;
  final double size;
  final double borderRadius;

  @override
  State<SearchTrackArtwork> createState() => _SearchTrackArtworkState();
}

final class _SearchTrackArtworkState extends State<SearchTrackArtwork> {
  late Future<Uri?> picture;

  @override
  void initState() {
    super.initState();
    final response = _responsePicture(widget.track);
    picture = response == null
        ? widget.loadPicture(widget.track)
        : Future.value(response);
  }

  @override
  void didUpdateWidget(covariant SearchTrackArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldResponse = _responsePicture(oldWidget.track);
    final response = _responsePicture(widget.track);
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.track.source != widget.track.source ||
        oldResponse != response ||
        (response == null && oldWidget.loadPicture != widget.loadPicture)) {
      picture = response == null
          ? widget.loadPicture(widget.track)
          : Future.value(response);
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    key: Key('search-artwork-frame-${widget.track.source}-${widget.track.id}'),
    borderRadius: BorderRadius.circular(widget.borderRadius),
    child: SizedBox.square(
      dimension: widget.size,
      child: FutureBuilder<Uri?>(
        future: picture,
        builder: (context, snapshot) => _ArtworkImage(
          uri: snapshot.data,
          track: widget.track,
          size: widget.size,
          borderRadius: widget.borderRadius,
        ),
      ),
    ),
  );
}

final class _ArtworkImage extends StatelessWidget {
  const _ArtworkImage({
    required this.uri,
    required this.track,
    required this.size,
    required this.borderRadius,
  });
  final Uri? uri;
  final Track track;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final fallback = Container(
      key: Key('search-artwork-fallback-${track.source}-${track.id}'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.surfaceWarm.withValues(alpha: .55),
        border: Border.all(color: tokens.borderSoft),
      ),
      child: Text(
        trackInitial(track),
        style: AppTypography.title.copyWith(color: tokens.muted),
      ),
    );
    if (uri == null) return fallback;
    return AppArtwork(
      key: Key('search-artwork-${track.source}-${track.id}'),
      imageUrl: uri.toString(),
      seed: '${track.source}:${track.id}',
      semanticLabel: '${track.title} 封面',
      size: size,
      width: size,
      height: size,
      borderRadius: 0,
      fallback: fallback,
    );
  }
}

Uri? _responsePicture(Track track) {
  final value = track.raw['pic'];
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https')
      ? uri
      : null;
}
