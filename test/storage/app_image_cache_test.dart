import 'dart:io';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/storage/app_image_cache.dart';

void main() {
  late Directory root;
  late Directory cacheBase;
  late Directory metadataBase;
  late File outsideSentinel;
  late List<int> pngBytes;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tuneflow-image-cache-');
    cacheBase = Directory('${root.path}/cache');
    metadataBase = Directory('${root.path}/metadata');
    outsideSentinel = File('${root.path}/keep.txt');
    await outsideSentinel.writeAsString('keep');
    pngBytes = await File('assets/branding/TuneFlow.png').readAsBytes();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('uses the approved CE cache policy', () async {
    final service = CeAppImageCache(
      cacheBaseDirectory: cacheBase,
      metadataBaseDirectory: metadataBase,
    );
    addTearDown(service.dispose);

    final manager = service.manager as dynamic;
    expect(manager.stalePeriod, const Duration(days: 30));
    expect(manager.maxNrOfCacheObjects, 1000);
    expect(
      manager.connectionParameters,
      ConnectionParameters(
        connectionTimeout: const Duration(seconds: 10),
        requestTimeout: const Duration(seconds: 30),
      ),
    );
  });

  test(
    'stores files only below the dedicated cache base and reports bytes',
    () async {
      final service = CeAppImageCache(
        cacheBaseDirectory: cacheBase,
        metadataBaseDirectory: metadataBase,
        httpClientFactory: () => MockClient((request) async {
          expect(request.headers['user-agent'], 'TuneFlow Test');
          return http.Response.bytes(
            pngBytes,
            200,
            headers: const {'content-type': 'image/png'},
          );
        }),
      );
      addTearDown(service.dispose);

      await service.manager
          .getFileStream(
            'https://example.test/cover.png',
            withProgress: false,
            headers: const {'User-Agent': 'TuneFlow Test'},
          )
          .firstWhere((response) => response is FileInfo);
      await service.refreshUsage();

      expect(service.usageBytes.value, greaterThan(0));
      expect(
        await cacheBase
            .list(recursive: true, followLinks: false)
            .where((entity) => entity is File)
            .isEmpty,
        isFalse,
      );
      expect(await outsideSentinel.exists(), isTrue);
    },
  );

  test('clear removes CE data, clears memory, and refreshes usage', () async {
    var memoryClears = 0;
    final service = CeAppImageCache(
      cacheBaseDirectory: cacheBase,
      metadataBaseDirectory: metadataBase,
      httpClientFactory: () => MockClient(
        (_) async => http.Response.bytes(
          pngBytes,
          200,
          headers: const {'content-type': 'image/png'},
        ),
      ),
      clearMemoryImageCache: () async => memoryClears++,
    );
    addTearDown(service.dispose);
    await service.manager
        .getFileStream('https://example.test/cover.png', withProgress: false)
        .firstWhere((response) => response is FileInfo);
    await service.refreshUsage();
    expect(service.usageBytes.value, greaterThan(0));

    await service.clear();

    expect(memoryClears, 1);
    expect(service.usageBytes.value, 0);
    expect(await outsideSentinel.exists(), isTrue);
  });

  test('a failed usage scan preserves the last confirmed bytes', () async {
    final service = CeAppImageCache(
      cacheBaseDirectory: cacheBase,
      metadataBaseDirectory: metadataBase,
      httpClientFactory: () => MockClient(
        (_) async => http.Response.bytes(
          pngBytes,
          200,
          headers: const {'content-type': 'image/png'},
        ),
      ),
    );
    addTearDown(service.dispose);
    await service.manager
        .getFileStream('https://example.test/cover.png', withProgress: false)
        .firstWhere((response) => response is FileInfo);
    await service.refreshUsage();
    final confirmed = service.usageBytes.value;
    await cacheBase.delete(recursive: true);
    await File(cacheBase.path).writeAsString('not a directory');

    await expectLater(
      service.refreshUsage(),
      throwsA(isA<FileSystemException>()),
    );
    expect(service.usageBytes.value, confirmed);
  });
}
