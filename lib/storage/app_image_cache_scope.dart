import 'package:flutter/widgets.dart';

import 'app_image_cache.dart';

final class AppImageCacheScope extends InheritedWidget {
  const AppImageCacheScope({
    super.key,
    required this.cache,
    required super.child,
  });

  final AppImageCache cache;

  static AppImageCache of(BuildContext context) =>
      maybeOf(context) ??
      (throw StateError('No AppImageCacheScope found in context.'));

  static AppImageCache? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppImageCacheScope>()?.cache;

  @override
  bool updateShouldNotify(AppImageCacheScope oldWidget) =>
      !identical(cache, oldWidget.cache);
}
