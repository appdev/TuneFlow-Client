import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

@immutable
final class MediaCacheUsage {
  const MediaCacheUsage({required this.audioBytes, required this.limitBytes});

  final int audioBytes;
  final int limitBytes;

  int get totalBytes => audioBytes;

  MediaCacheUsage copyWith({int? audioBytes, int? limitBytes}) =>
      MediaCacheUsage(
        audioBytes: audioBytes ?? this.audioBytes,
        limitBytes: limitBytes ?? this.limitBytes,
      );
}

final class MediaCacheLease {
  MediaCacheLease(this.file, Future<void> Function() release)
    : _release = release;

  final File file;
  final Future<void> Function() _release;
  bool _released = false;

  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _release();
  }
}

abstract interface class MediaCache {
  ValueListenable<MediaCacheUsage> get usage;
  Future<void> initialize({required int limitBytes});
  Future<MediaCacheLease> acquireAudio({
    required String source,
    required String trackId,
    required String quality,
  });
  Future<void> invalidate(File file);
  Future<void> reconcile();
  Future<void> setLimit(int bytes);
  Future<void> clearLocal();
  Future<void> dispose();
}

final class FileMediaCache implements MediaCache {
  FileMediaCache({required this.root, DateTime Function()? now})
    : _now = now ?? DateTime.now,
      _usage = ValueNotifier(
        const MediaCacheUsage(audioBytes: 0, limitBytes: 0),
      );

  final Directory root;
  final DateTime Function() _now;
  final ValueNotifier<MediaCacheUsage> _usage;
  final Map<String, int> _protectedPaths = {};
  final Set<String> _pendingDeletes = {};
  Future<void> _serial = Future.value();
  bool _disposed = false;

  Directory get _legacyImages =>
      Directory('${root.path}${Platform.pathSeparator}images');

  @override
  ValueListenable<MediaCacheUsage> get usage => _usage;

  @override
  Future<void> initialize({required int limitBytes}) =>
      _runSerialized(() async {
        _requirePositiveLimit(limitBytes);
        await root.create(recursive: true);
        await _removeLegacyImageCache();
        _usage.value = _usage.value.copyWith(limitBytes: limitBytes);
        await _deleteAuxiliaryFiles();
        await _maintain();
      });

  @override
  Future<MediaCacheLease> acquireAudio({
    required String source,
    required String trackId,
    required String quality,
  }) async {
    final extension = quality.toLowerCase().contains('flac') ? '.flac' : '.mp3';
    final key = '$source-$trackId-$quality'.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    final file = File('${root.path}${Platform.pathSeparator}$key$extension');
    return _acquireFile(file);
  }

  Future<MediaCacheLease> _acquireFile(File file) => _runSerialized(() async {
    await root.create(recursive: true);
    _retain(file.path);
    if (await file.exists()) await file.setLastModified(_now());
    return MediaCacheLease(file, () => _release(file));
  });

  @override
  Future<void> invalidate(File file) => _runSerialized(() async {
    if ((_protectedPaths[file.path] ?? 0) > 0) {
      _pendingDeletes.add(file.path);
    } else if (await file.exists()) {
      await file.delete();
    }
    await _publishUsage();
  });

  @override
  Future<void> reconcile() => _runSerialized(_maintain);

  @override
  Future<void> setLimit(int bytes) => _runSerialized(() async {
    _requirePositiveLimit(bytes);
    _usage.value = _usage.value.copyWith(limitBytes: bytes);
    await _maintain();
  });

  @override
  Future<void> clearLocal() => _runSerialized(() async {
    for (final entry in await _entries()) {
      if ((_protectedPaths[entry.file.path] ?? 0) > 0) {
        _pendingDeletes.add(entry.file.path);
        continue;
      }
      await _tryDelete(entry.file);
    }
    await _deleteAuxiliaryFiles();
    await _publishUsage();
  });

  Future<void> _release(File file) => _runSerialized(() async {
    final count = _protectedPaths[file.path] ?? 0;
    if (count <= 1) {
      _protectedPaths.remove(file.path);
    } else {
      _protectedPaths[file.path] = count - 1;
    }
    if ((_protectedPaths[file.path] ?? 0) == 0 &&
        _pendingDeletes.remove(file.path)) {
      await _tryDelete(file);
    } else if (await file.exists()) {
      await file.setLastModified(_now());
    }
    await _maintain();
  });

  void _retain(String path) {
    _protectedPaths[path] = (_protectedPaths[path] ?? 0) + 1;
  }

  Future<void> _maintain() async {
    final entries = await _entries();
    var total = entries.fold<int>(0, (sum, entry) => sum + entry.bytes);
    final limit = _usage.value.limitBytes;
    if (limit > 0 && total > limit) {
      final candidates =
          entries
              .where((entry) => (_protectedPaths[entry.file.path] ?? 0) == 0)
              .toList()
            ..sort((a, b) {
              final time = a.modified.compareTo(b.modified);
              return time != 0 ? time : a.file.path.compareTo(b.file.path);
            });
      for (final entry in candidates) {
        if (total <= limit) break;
        if (await _tryDelete(entry.file)) total -= entry.bytes;
      }
    }
    await _publishUsage();
  }

  Future<List<_CacheEntry>> _entries() async {
    if (!await root.exists()) return [];
    final entries = <_CacheEntry>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || !_isAudioFile(entity)) continue;
      try {
        final stat = await entity.stat();
        entries.add(
          _CacheEntry(file: entity, bytes: stat.size, modified: stat.modified),
        );
      } on FileSystemException {
        // The file may have disappeared between listing and stat.
      }
    }
    return entries;
  }

  bool _isAudioFile(File file) =>
      file.parent.path == root.path &&
      (file.path.endsWith('.mp3') || file.path.endsWith('.flac'));

  Future<void> _publishUsage() async {
    final audio = (await _entries()).fold<int>(
      0,
      (sum, entry) => sum + entry.bytes,
    );
    _usage.value = MediaCacheUsage(
      audioBytes: audio,
      limitBytes: _usage.value.limitBytes,
    );
  }

  Future<void> _removeLegacyImageCache() async {
    if (await _legacyImages.exists()) {
      await _legacyImages.delete(recursive: true);
    }
  }

  Future<void> _deleteAuxiliaryFiles() async {
    if (!await root.exists()) return;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File ||
          (!entity.path.endsWith('.part') && !entity.path.endsWith('.mime'))) {
        continue;
      }
      final target = entity.path.substring(0, entity.path.length - 5);
      if ((_protectedPaths[target] ?? 0) == 0) await _tryDelete(entity);
    }
  }

  Future<bool> _tryDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  void _requirePositiveLimit(int bytes) {
    if (bytes <= 0) throw ArgumentError.value(bytes, 'bytes');
  }

  Future<T> _runSerialized<T>(Future<T> Function() operation) {
    if (_disposed) return Future.error(StateError('Media cache is disposed'));
    final result = Completer<T>();
    _serial = _serial.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await _serial;
    _disposed = true;
    _usage.dispose();
  }
}

final class _CacheEntry {
  const _CacheEntry({
    required this.file,
    required this.bytes,
    required this.modified,
  });

  final File file;
  final int bytes;
  final DateTime modified;
}
