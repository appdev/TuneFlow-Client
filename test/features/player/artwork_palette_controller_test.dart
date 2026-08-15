import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';
import 'package:musicfree_service_client/features/player/artwork_palette.dart';
import 'package:musicfree_service_client/features/player/artwork_palette_controller.dart';
import 'package:musicfree_service_client/features/player/artwork_palette_extractor.dart';

void main() {
  test('late previous result cannot replace the current palette', () async {
    final first = Completer<Uint8List?>();
    final second = Completer<Uint8List?>();
    final controller = ArtworkPaletteController(
      loadBytes: (source) =>
          source.fallbackSeed == 'first' ? first.future : second.future,
      decoder: const _FakePaletteDecoder(),
    );

    final firstCall = controller.select(
      const AppArtworkSource.fallback(fallbackSeed: 'first'),
      brightness: Brightness.light,
    );
    final secondCall = controller.select(
      const AppArtworkSource.fallback(fallbackSeed: 'second'),
      brightness: Brightness.light,
    );
    second.complete(Uint8List.fromList(const [2]));
    await secondCall;
    final selected = controller.palette;
    first.complete(Uint8List.fromList(const [1]));
    await firstCall;

    expect(selected, paletteFor(2, Brightness.light));
    expect(controller.palette, selected);
  });

  test('reselecting a cached key avoids loading it twice', () async {
    var calls = 0;
    final controller = ArtworkPaletteController(
      loadBytes: (source) async {
        calls++;
        return Uint8List.fromList([source.fallbackSeed.codeUnitAt(0)]);
      },
      decoder: const _FakePaletteDecoder(),
    );
    const first = AppArtworkSource.fallback(fallbackSeed: 'a');
    const second = AppArtworkSource.fallback(fallbackSeed: 'b');

    await controller.select(first, brightness: Brightness.light);
    await controller.select(second, brightness: Brightness.light);
    await controller.select(first, brightness: Brightness.light);

    expect(calls, 2);
    expect(controller.palette, paletteFor('a'.codeUnitAt(0), Brightness.light));
  });

  test('bounded LRU evicts the oldest selected key', () async {
    var calls = 0;
    final controller = ArtworkPaletteController(
      capacity: 2,
      loadBytes: (source) async {
        calls++;
        return Uint8List.fromList([source.fallbackSeed.codeUnitAt(0)]);
      },
      decoder: const _FakePaletteDecoder(),
    );

    for (final seed in const ['a', 'b', 'c', 'a']) {
      await controller.select(
        AppArtworkSource.fallback(fallbackSeed: seed),
        brightness: Brightness.light,
      );
    }

    expect(calls, 4);
  });

  test('loader failure leaves a deterministic immediate fallback', () async {
    final controller = ArtworkPaletteController(
      loadBytes: (_) => Future<Uint8List?>.error(StateError('offline')),
    );
    const source = AppArtworkSource.fallback(fallbackSeed: 'offline');

    await controller.select(source, brightness: Brightness.dark);

    expect(
      controller.palette,
      fallbackArtworkPalette('offline', brightness: Brightness.dark),
    );
  });

  test('brightness participates in the cache key', () async {
    var calls = 0;
    final controller = ArtworkPaletteController(
      loadBytes: (_) async {
        calls++;
        return Uint8List.fromList(const [7]);
      },
      decoder: const _FakePaletteDecoder(),
    );
    const source = AppArtworkSource.fallback(fallbackSeed: 'same');

    await controller.select(source, brightness: Brightness.light);
    await controller.select(source, brightness: Brightness.dark);

    expect(calls, 2);
    expect(controller.palette, paletteFor(7, Brightness.dark));
  });
}

ArtworkPalette paletteFor(int value, Brightness brightness) => ArtworkPalette(
  backgroundBase: Color.fromARGB(255, value, 40, 50),
  backgroundCompanion: Color.fromARGB(255, 50, value, 60),
  vinylAccent: Color.fromARGB(255, 60, 70, value),
  foreground: brightness == Brightness.dark ? Colors.white : Colors.black,
);

final class _FakePaletteDecoder implements ArtworkPaletteDecoding {
  const _FakePaletteDecoder();

  @override
  Future<ArtworkPalette> extract(
    Uint8List encodedBytes, {
    required String fallbackSeed,
    required Brightness brightness,
  }) async => paletteFor(encodedBytes.single, brightness);
}
