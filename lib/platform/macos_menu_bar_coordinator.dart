import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/models.dart';
import '../app/app_error.dart';
import '../features/player/player_controller.dart';
import '../features/player/player_state.dart';
import '../features/playlists/favorite_playlist.dart';
import 'macos_menu_bar.dart';

export '../features/playlists/favorite_playlist.dart';

final class MacOSMenuBarCoordinator {
  MacOSMenuBarCoordinator({
    required PlayerController? player,
    required FavoritePlaylistPort? favorites,
    required MacOSMenuBarPort menuBar,
    required void Function(String title, String message) reportFailure,
    required VoidCallback revealPendingMessages,
    VoidCallback? hidePendingMessages,
  }) : _player = player,
       _favorites = favorites,
       _menuBar = menuBar,
       _reportFailure = reportFailure,
       _revealPendingMessages = revealPendingMessages,
       _hidePendingMessages = hidePendingMessages;

  final PlayerController? _player;
  final FavoritePlaylistPort? _favorites;
  final MacOSMenuBarPort _menuBar;
  final void Function(String title, String message) _reportFailure;
  final VoidCallback _revealPendingMessages;
  final VoidCallback? _hidePendingMessages;

  StreamSubscription<MacOSMenuBarCommand>? _commands;
  MacOSMenuBarSnapshot? _lastSnapshot;
  String? _favoriteIdentity;
  bool _favorite = false;
  bool _favoritePending = false;
  int _favoriteGeneration = 0;
  Future<void> _commandTail = Future.value();
  bool _started = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    await _menuBar.initialize();
    _commands = _menuBar.commands.listen(_enqueueCommand);
    _player?.addListener(_syncPlayer);
    _syncPlayer();
  }

  void _syncPlayer() {
    if (_disposed) return;
    final track = _player?.state.current;
    final identity = track == null ? null : '${track.source}:${track.id}';
    if (identity != _favoriteIdentity) {
      _favoriteIdentity = identity;
      _favorite = false;
      _favoritePending = false;
      _favoriteGeneration++;
      if (track != null && _favorites != null) {
        unawaited(_loadFavorite(track, _favoriteGeneration));
      }
    }
    _publish();
  }

  Future<void> _loadFavorite(Track track, int generation) async {
    try {
      final favorite = await _favorites!.contains(track);
      if (!_isCurrent(track, generation)) return;
      _favorite = favorite;
      _publish();
    } on Object {
      if (!_isCurrent(track, generation)) return;
      _favorite = false;
      _publish();
    }
  }

  bool _isCurrent(Track track, int generation) =>
      !_disposed &&
      generation == _favoriteGeneration &&
      _favoriteIdentity == '${track.source}:${track.id}';

  void _publish() {
    final player = _player;
    final state = player?.state;
    final track = state?.current;
    final loading =
        state?.processing == PlayerProcessing.loading ||
        state?.processing == PlayerProcessing.buffering;
    final snapshot = track == null
        ? MacOSMenuBarSnapshot.idle
        : MacOSMenuBarSnapshot(
            trackId: track.id,
            source: track.source,
            title: track.title.isEmpty ? track.id : track.title,
            artist: track.artist,
            playing: state!.playing,
            loading: loading,
            canPlayPause: !loading,
            canGoPrevious: state.canPrevious,
            canGoNext: state.canNext,
            favorite: _favorite,
            favoritePending: _favoritePending,
            canToggleFavorite: _favorites != null && !_favoritePending,
          );
    if (snapshot == _lastSnapshot) return;
    _lastSnapshot = snapshot;
    unawaited(
      _menuBar.updateState(snapshot).catchError((Object error) {
        debugPrint('macOS menu bar state update failed: $error');
      }),
    );
  }

  void _enqueueCommand(MacOSMenuBarCommand command) {
    _commandTail = _commandTail.then((_) => _handleCommand(command)).catchError(
      (Object error) {
        debugPrint('macOS menu bar command failed: $error');
      },
    );
  }

  Future<void> _handleCommand(MacOSMenuBarCommand command) async {
    if (_disposed) return;
    final player = _player;
    switch (command) {
      case MacOSMenuBarCommand.previous:
        await player?.previous();
      case MacOSMenuBarCommand.playPause:
        if (player == null || player.state.current == null) return;
        if (player.state.playing) {
          await player.pause();
        } else {
          await player.resume();
        }
      case MacOSMenuBarCommand.next:
        await player?.next();
      case MacOSMenuBarCommand.toggleFavorite:
        await _toggleFavorite();
      case MacOSMenuBarCommand.showWindow:
        await _menuBar.showWindow();
      case MacOSMenuBarCommand.quit:
        await _menuBar.terminate();
      case MacOSMenuBarCommand.applicationActivated:
        _revealPendingMessages();
      case MacOSMenuBarCommand.windowHidden:
        _hidePendingMessages?.call();
    }
  }

  Future<void> _toggleFavorite() async {
    final track = _player?.state.current;
    final favorites = _favorites;
    if (track == null || favorites == null || _favoritePending) return;
    final generation = _favoriteGeneration;
    final previous = _favorite;
    final next = !previous;
    _favorite = next;
    _favoritePending = true;
    _publish();
    try {
      await favorites.setFavorite(track, next);
      if (!_isCurrent(track, generation)) return;
      _favoritePending = false;
      _publish();
    } on Object catch (error) {
      if (!_isCurrent(track, generation)) return;
      _favorite = previous;
      _favoritePending = false;
      _publish();
      _reportFailure('收藏失败', appErrorMessage(error, fallback: '操作未完成，请稍后重试。'));
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _favoriteGeneration++;
    _player?.removeListener(_syncPlayer);
    await _commands?.cancel();
    await _commandTail;
  }
}
