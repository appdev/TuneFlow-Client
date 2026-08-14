import 'dart:io';

import 'package:cached_network_image_ce/cached_network_image.dart'
    hide DefaultCacheManager;
// The package's public conditional stub omits native constructor parameters.
// ignore: implementation_imports
import 'package:cached_network_image_ce/src/cache/default_cache_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

abstract interface class AppImageCache {
  BaseCacheManager get manager;
  ValueListenable<int> get usageBytes;
  Future<void> refreshUsage();
  Future<void> clear();
  Future<void> dispose();
}

final class CeAppImageCache implements AppImageCache {
  CeAppImageCache({
    required this.cacheBaseDirectory,
    required Directory metadataBaseDirectory,
    http.Client Function()? httpClientFactory,
    Future<void> Function()? clearMemoryImageCache,
  }) : _usageBytes = ValueNotifier(0),
       _clearMemoryImageCache =
           clearMemoryImageCache ?? _clearFlutterImageMemoryCache,
       _manager = DefaultCacheManager(
         stalePeriod: const Duration(days: 30),
         maxNrOfCacheObjects: 1000,
         connectionParameters: ConnectionParameters(
           connectionTimeout: const Duration(seconds: 10),
           requestTimeout: const Duration(seconds: 30),
         ),
         httpClientFactory: httpClientFactory,
         cacheDirectoryProvider: () async => cacheBaseDirectory,
         metadataDirectoryProvider: () async => metadataBaseDirectory,
         cleanupStrategy: const LruCleanupStrategy(),
       );

  final Directory cacheBaseDirectory;
  final DefaultCacheManager _manager;
  final ValueNotifier<int> _usageBytes;
  final Future<void> Function() _clearMemoryImageCache;
  bool _disposed = false;

  @override
  BaseCacheManager get manager => _manager;

  @override
  ValueListenable<int> get usageBytes => _usageBytes;

  @override
  Future<void> refreshUsage() async {
    _requireActive();
    if (await File(cacheBaseDirectory.path).exists()) {
      throw FileSystemException(
        'Image cache path is not a directory',
        cacheBaseDirectory.path,
      );
    }
    var bytes = 0;
    if (await cacheBaseDirectory.exists()) {
      await for (final entity in cacheBaseDirectory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        bytes += (await entity.stat()).size;
      }
    }
    _usageBytes.value = bytes;
  }

  @override
  Future<void> clear() async {
    _requireActive();
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    await attempt(_manager.emptyCache);
    await attempt(_clearMemoryImageCache);
    await attempt(refreshUsage);
    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _manager.dispose();
    _usageBytes.dispose();
  }

  void _requireActive() {
    if (_disposed) throw StateError('Image cache is disposed');
  }
}

Future<void> _clearFlutterImageMemoryCache() async {
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
}
