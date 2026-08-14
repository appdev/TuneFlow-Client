import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:musicfree_service_client/storage/app_image_cache.dart';

final class FakeAppImageCache implements AppImageCache {
  FakeAppImageCache({required this.manager, int usageBytes = 0})
    : _usage = ValueNotifier(usageBytes);

  @override
  final BaseCacheManager manager;
  final ValueNotifier<int> _usage;
  int clearCalls = 0;
  int refreshCalls = 0;
  int disposeCalls = 0;
  Object? error;

  @override
  ValueListenable<int> get usageBytes => _usage;

  @override
  Future<void> refreshUsage() async => refreshCalls++;

  @override
  Future<void> clear() async {
    clearCalls++;
    if (error case final value?) throw value;
    _usage.value = 0;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    _usage.dispose();
  }
}
