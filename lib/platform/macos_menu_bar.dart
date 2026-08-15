import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const macosMenuBarChannelName = 'com.musicfree.serviceclient/macos_menu_bar';

enum MacOSMenuBarCommand {
  previous,
  playPause,
  next,
  toggleFavorite,
  showWindow,
  quit,
  applicationActivated,
  windowHidden,
}

@immutable
final class MacOSMenuBarSnapshot {
  const MacOSMenuBarSnapshot({
    required this.trackId,
    required this.source,
    required this.title,
    required this.artist,
    required this.playing,
    required this.loading,
    required this.canPlayPause,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.favorite,
    required this.favoritePending,
    required this.canToggleFavorite,
  });

  static const idle = MacOSMenuBarSnapshot(
    trackId: '',
    source: '',
    title: '',
    artist: '',
    playing: false,
    loading: false,
    canPlayPause: false,
    canGoPrevious: false,
    canGoNext: false,
    favorite: false,
    favoritePending: false,
    canToggleFavorite: false,
  );

  final String trackId;
  final String source;
  final String title;
  final String artist;
  final bool playing;
  final bool loading;
  final bool canPlayPause;
  final bool canGoPrevious;
  final bool canGoNext;
  final bool favorite;
  final bool favoritePending;
  final bool canToggleFavorite;

  Map<String, Object> toMap() => {
    'trackId': trackId,
    'source': source,
    'title': title,
    'artist': artist,
    'playing': playing,
    'loading': loading,
    'canPlayPause': canPlayPause,
    'canGoPrevious': canGoPrevious,
    'canGoNext': canGoNext,
    'favorite': favorite,
    'favoritePending': favoritePending,
    'canToggleFavorite': canToggleFavorite,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MacOSMenuBarSnapshot &&
          trackId == other.trackId &&
          source == other.source &&
          title == other.title &&
          artist == other.artist &&
          playing == other.playing &&
          loading == other.loading &&
          canPlayPause == other.canPlayPause &&
          canGoPrevious == other.canGoPrevious &&
          canGoNext == other.canGoNext &&
          favorite == other.favorite &&
          favoritePending == other.favoritePending &&
          canToggleFavorite == other.canToggleFavorite;

  @override
  int get hashCode => Object.hash(
    trackId,
    source,
    title,
    artist,
    playing,
    loading,
    canPlayPause,
    canGoPrevious,
    canGoNext,
    favorite,
    favoritePending,
    canToggleFavorite,
  );
}

abstract interface class MacOSMenuBarPort {
  Stream<MacOSMenuBarCommand> get commands;
  Future<void> initialize();
  Future<void> updateState(MacOSMenuBarSnapshot state);
  Future<void> showWindow();
  Future<void> terminate();
  Future<void> dispose();
}

final class MethodChannelMacOSMenuBarPort implements MacOSMenuBarPort {
  MethodChannelMacOSMenuBarPort({
    MethodChannel channel = const MethodChannel(macosMenuBarChannelName),
  }) : _channel = channel;

  final MethodChannel _channel;
  final StreamController<MacOSMenuBarCommand> _commands =
      StreamController<MacOSMenuBarCommand>.broadcast();
  bool _initialized = false;
  bool _disposed = false;

  @override
  Stream<MacOSMenuBarCommand> get commands => _commands.stream;

  @override
  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
    await _channel.invokeMethod<void>('initialize');
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'command' || call.arguments is! String) return;
    final command = switch (call.arguments as String) {
      'previous' => MacOSMenuBarCommand.previous,
      'playPause' => MacOSMenuBarCommand.playPause,
      'next' => MacOSMenuBarCommand.next,
      'toggleFavorite' => MacOSMenuBarCommand.toggleFavorite,
      'showWindow' => MacOSMenuBarCommand.showWindow,
      'quit' => MacOSMenuBarCommand.quit,
      'applicationActivated' => MacOSMenuBarCommand.applicationActivated,
      'windowHidden' => MacOSMenuBarCommand.windowHidden,
      _ => null,
    };
    if (command == null) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: ArgumentError.value(
            call.arguments,
            'command',
            'unknown macOS menu bar command',
          ),
          library: 'macOS menu bar',
        ),
      );
      return;
    }
    if (!_disposed) _commands.add(command);
  }

  @override
  Future<void> updateState(MacOSMenuBarSnapshot state) =>
      _channel.invokeMethod<void>('updateState', state.toMap());

  @override
  Future<void> showWindow() => _channel.invokeMethod<void>('showWindow');

  @override
  Future<void> terminate() => _channel.invokeMethod<void>('terminate');

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _channel.invokeMethod<void>('dispose');
    _channel.setMethodCallHandler(null);
    await _commands.close();
  }
}

final class InactiveMacOSMenuBarPort implements MacOSMenuBarPort {
  @override
  Stream<MacOSMenuBarCommand> get commands => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showWindow() async {}

  @override
  Future<void> terminate() async {}

  @override
  Future<void> updateState(MacOSMenuBarSnapshot state) async {}
}
