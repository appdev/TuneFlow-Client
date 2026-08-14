import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:musicfree_service_client/storage/media_cache.dart';

final class FakeMediaCache implements MediaCache {
  FakeMediaCache({
    MediaCacheUsage usage = const MediaCacheUsage(
      audioBytes: 0,
      limitBytes: 5 * 1024 * 1024 * 1024,
    ),
    this.audioFile,
  }) : _usage = ValueNotifier(usage);

  final ValueNotifier<MediaCacheUsage> _usage;
  File? audioFile;
  final List<int> initializedLimits = [];
  final List<int> setLimits = [];
  final List<String> audioRequests = [];
  final List<File> invalidatedFiles = [];
  int reconcileCalls = 0;
  int clearCalls = 0;
  int releasedLeases = 0;
  Object? error;

  @override
  ValueListenable<MediaCacheUsage> get usage => _usage;

  void publish(MediaCacheUsage value) => _usage.value = value;

  @override
  Future<void> initialize({required int limitBytes}) async {
    initializedLimits.add(limitBytes);
    _throwIfNeeded();
    _usage.value = _usage.value.copyWith(limitBytes: limitBytes);
  }

  @override
  Future<MediaCacheLease> acquireAudio({
    required String source,
    required String trackId,
    required String quality,
  }) async {
    audioRequests.add('$source:$trackId:$quality');
    _throwIfNeeded();
    final file = audioFile;
    if (file == null) throw StateError('Fake audio file is not configured');
    return _lease(file);
  }

  MediaCacheLease _lease(File file) => MediaCacheLease(file, () async {
    releasedLeases++;
  });

  @override
  Future<void> invalidate(File file) async {
    invalidatedFiles.add(file);
    _throwIfNeeded();
  }

  @override
  Future<void> reconcile() async {
    reconcileCalls++;
    _throwIfNeeded();
  }

  @override
  Future<void> setLimit(int bytes) async {
    setLimits.add(bytes);
    _throwIfNeeded();
    _usage.value = _usage.value.copyWith(limitBytes: bytes);
  }

  @override
  Future<void> clearLocal() async {
    clearCalls++;
    _throwIfNeeded();
    _usage.value = MediaCacheUsage(
      audioBytes: 0,
      limitBytes: _usage.value.limitBytes,
    );
  }

  @override
  Future<void> dispose() async {
    _usage.dispose();
  }

  void _throwIfNeeded() {
    final value = error;
    if (value != null) throw value;
  }
}
