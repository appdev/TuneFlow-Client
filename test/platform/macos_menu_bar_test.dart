import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/platform/macos_menu_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(macosMenuBarChannelName);

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('snapshot serializes the stable primitive channel contract', () {
    const snapshot = MacOSMenuBarSnapshot(
      trackId: '42',
      source: 'wy',
      title: '夜曲',
      artist: '周杰伦',
      playing: true,
      loading: false,
      canPlayPause: true,
      canGoPrevious: false,
      canGoNext: true,
      favorite: true,
      favoritePending: false,
      canToggleFavorite: true,
    );

    expect(snapshot.toMap(), {
      'trackId': '42',
      'source': 'wy',
      'title': '夜曲',
      'artist': '周杰伦',
      'playing': true,
      'loading': false,
      'canPlayPause': true,
      'canGoPrevious': false,
      'canGoNext': true,
      'favorite': true,
      'favoritePending': false,
      'canToggleFavorite': true,
    });
  });

  test('method channel port initializes and publishes state', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    final port = MethodChannelMacOSMenuBarPort(channel: channel);
    addTearDown(port.dispose);

    await port.initialize();
    await port.updateState(MacOSMenuBarSnapshot.idle);

    expect(calls.map((call) => call.method), ['initialize', 'updateState']);
    expect(calls.last.arguments, MacOSMenuBarSnapshot.idle.toMap());
  });

  test('method channel port emits typed semantic commands', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    final port = MethodChannelMacOSMenuBarPort(channel: channel);
    addTearDown(port.dispose);
    await port.initialize();
    final command = port.commands.first;

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          macosMenuBarChannelName,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('command', 'playPause'),
          ),
          (_) {},
        );

    expect(await command, MacOSMenuBarCommand.playPause);
  });

  test('method channel port emits window visibility commands', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    final port = MethodChannelMacOSMenuBarPort(channel: channel);
    addTearDown(port.dispose);
    await port.initialize();
    final command = port.commands.first;

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          macosMenuBarChannelName,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('command', 'windowHidden'),
          ),
          (_) {},
        );

    expect(await command, MacOSMenuBarCommand.windowHidden);
  });

  test('inactive port completes without platform messages', () async {
    final port = InactiveMacOSMenuBarPort();

    await port.initialize();
    await port.updateState(MacOSMenuBarSnapshot.idle);
    await port.showWindow();
    await port.terminate();
    await port.dispose();

    expect(port.commands, emitsDone);
  });
}
