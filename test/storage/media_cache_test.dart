import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/storage/media_cache.dart';

void main() {
  late Directory root;
  late DateTime now;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tuneflow-media-cache-');
    now = DateTime.utc(2026, 8, 14, 8);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('initialization removes only the legacy image directory', () async {
    await root.create(recursive: true);
    final audio = File('${root.path}/wy-song-128k.mp3');
    await audio.writeAsBytes(List.filled(7, 1));
    final legacyImages = Directory('${root.path}/images');
    await legacyImages.create();
    await File('${legacyImages.path}/cover.image').writeAsBytes([1, 2, 3]);
    final unrelated = File('${root.path}/keep.txt');
    await unrelated.writeAsString('keep');

    final cache = FileMediaCache(root: root, now: () => now);
    await cache.initialize(limitBytes: 100);

    expect(await legacyImages.exists(), isFalse);
    expect(await audio.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
    expect(cache.usage.value.audioBytes, 7);
    expect(cache.usage.value.totalBytes, 7);
    await cache.dispose();
  });

  test('audio limit ignores files outside the audio contract', () async {
    await root.create(recursive: true);
    final audio = File('${root.path}/wy-small-128k.mp3');
    await audio.writeAsBytes(List.filled(8, 1));
    final unrelated = File('${root.path}/keep.txt');
    await unrelated.writeAsBytes(List.filled(100, 2));

    final cache = FileMediaCache(root: root, now: () => now);
    await cache.initialize(limitBytes: 10);

    expect(await audio.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
    expect(cache.usage.value.audioBytes, 8);
    expect(cache.usage.value.totalBytes, 8);
    await cache.dispose();
  });

  test(
    'defers a local clear until a protected audio file is released',
    () async {
      final cache = FileMediaCache(root: root, now: () => now);
      await cache.initialize(limitBytes: 100);
      final audio = await cache.acquireAudio(
        source: 'tx',
        trackId: 'playing',
        quality: '320k',
      );
      await audio.file.writeAsBytes(List.filled(8, 1));
      await cache.reconcile();

      await cache.clearLocal();
      expect(await audio.file.exists(), isTrue);
      expect(cache.usage.value.audioBytes, 8);

      await audio.release();
      expect(await audio.file.exists(), isFalse);
      expect(cache.usage.value.totalBytes, 0);
      await cache.dispose();
    },
  );

  test('removes abandoned partial files during initialization', () async {
    await root.create(recursive: true);
    final partial = File('${root.path}/abandoned.mp3.part');
    await partial.writeAsBytes([1, 2, 3]);
    final cache = FileMediaCache(root: root, now: () => now);

    await cache.initialize(limitBytes: 100);

    expect(await partial.exists(), isFalse);
    await cache.dispose();
  });

  test('audio cache hits refresh LRU order', () async {
    final cache = FileMediaCache(root: root, now: () => now);
    await cache.initialize(limitBytes: 12);
    final first = await cache.acquireAudio(
      source: 'wy',
      trackId: 'first',
      quality: '128k',
    );
    await first.file.writeAsBytes(List.filled(4, 1));
    await first.release();
    now = now.add(const Duration(minutes: 1));
    final second = await cache.acquireAudio(
      source: 'wy',
      trackId: 'second',
      quality: '128k',
    );
    await second.file.writeAsBytes(List.filled(4, 2));
    await second.release();
    now = now.add(const Duration(minutes: 1));
    final touched = await cache.acquireAudio(
      source: 'wy',
      trackId: 'first',
      quality: '128k',
    );
    await touched.release();
    now = now.add(const Duration(minutes: 1));
    final third = await cache.acquireAudio(
      source: 'wy',
      trackId: 'third',
      quality: '128k',
    );
    await third.file.writeAsBytes(List.filled(6, 3));
    await third.release();

    expect(await first.file.exists(), isTrue);
    expect(await second.file.exists(), isFalse);
    expect(await third.file.exists(), isTrue);
    expect(cache.usage.value.totalBytes, 10);
    await cache.dispose();
  });
}
