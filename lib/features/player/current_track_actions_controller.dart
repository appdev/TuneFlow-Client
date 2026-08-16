import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import '../downloads/user_download_coordinator.dart';
import '../playlists/favorite_playlist.dart';
import 'player_controller.dart';

typedef DownloadCurrentTrack =
    Future<UserDownloadResult> Function(
      Track track,
      String quality, {
      required ConfirmRedownload confirmReplacement,
    });

final class CurrentTrackActionsController extends ChangeNotifier {
  CurrentTrackActionsController({
    required PlayerController player,
    required FavoritePlaylistPort favorites,
    required DownloadCurrentTrack download,
  }) : _player = player,
       _favorites = favorites,
       _download = download {
    _player.addListener(_syncTrack);
    _syncTrack();
  }

  final PlayerController _player;
  final FavoritePlaylistPort _favorites;
  final DownloadCurrentTrack _download;

  Track? _track;
  String? _identity;
  bool _favorite = false;
  bool _favoriteKnown = false;
  bool _favoritePending = false;
  bool _downloadPending = false;
  int _generation = 0;
  bool _disposed = false;

  Track? get track => _track;
  bool get favorite => _favorite;
  bool get favoriteKnown => _favoriteKnown;
  bool get favoritePending => _favoritePending;
  bool get downloadPending => _downloadPending;
  bool get canToggleFavorite =>
      _track != null && _favoriteKnown && !_favoritePending;
  bool get canDownload => _track != null && !_downloadPending;

  void _syncTrack() {
    if (_disposed) return;
    final next = _player.state.current;
    final identity = _trackIdentity(next);
    if (identity == _identity) return;

    _track = next;
    _identity = identity;
    _favorite = false;
    _favoriteKnown = false;
    _favoritePending = false;
    _downloadPending = false;
    final generation = ++_generation;
    notifyListeners();
    if (next != null) unawaited(_loadFavorite(next, generation));
  }

  Future<void> _loadFavorite(Track value, int generation) async {
    try {
      final result = await _favorites.contains(value);
      if (!_isCurrent(value, generation)) return;
      _favorite = result;
      _favoriteKnown = true;
      notifyListeners();
    } on Object {
      if (!_isCurrent(value, generation)) return;
      _favorite = false;
      _favoriteKnown = false;
      notifyListeners();
    }
  }

  Future<void> toggleFavorite() async {
    if (!canToggleFavorite) return;
    final value = _track!;
    final generation = _generation;
    final previous = _favorite;
    final next = !previous;
    _favorite = next;
    _favoritePending = true;
    notifyListeners();
    try {
      await _favorites.setFavorite(value, next);
      if (!_isCurrent(value, generation)) return;
      _favoritePending = false;
      notifyListeners();
    } on Object {
      if (_isCurrent(value, generation)) {
        _favorite = previous;
        _favoritePending = false;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<UserDownloadResult?> downloadCurrent({
    required ConfirmRedownload confirmReplacement,
  }) async {
    if (!canDownload) return null;
    final value = _track!;
    final generation = _generation;
    final quality = _player.state.quality;
    _downloadPending = true;
    notifyListeners();
    try {
      return await _download(
        value,
        quality,
        confirmReplacement: confirmReplacement,
      );
    } finally {
      if (_isCurrent(value, generation)) {
        _downloadPending = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrent(Track value, int generation) =>
      !_disposed &&
      generation == _generation &&
      _identity == _trackIdentity(value);

  String? _trackIdentity(Track? value) =>
      value == null ? null : '${value.source}:${value.id}';

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _player.removeListener(_syncTrack);
    super.dispose();
  }
}
