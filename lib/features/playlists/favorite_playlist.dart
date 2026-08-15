import '../../api/models.dart';
import 'playlist_repository.dart';

abstract interface class FavoritePlaylistPort {
  Future<bool> contains(Track track);
  Future<void> setFavorite(Track track, bool favorite);
}

final class LovePlaylistFavorites implements FavoritePlaylistPort {
  const LovePlaylistFavorites(this._repository);

  final PlaylistRepository _repository;

  @override
  Future<bool> contains(Track track) async {
    final playlist = await _repository.get('love');
    return playlist.tracks.any(
      (item) => item.source == track.source && item.id == track.id,
    );
  }

  @override
  Future<void> setFavorite(Track track, bool favorite) async {
    if (favorite) {
      await _repository.addTracks('love', [track]);
    } else {
      await _repository.removeTracks('love', [track.id]);
    }
  }
}
