import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_logger.dart';
import 'diagnostic_platform.dart';

/// Captures Dart/Flutter errors locally, without initializing Sentry globally.
final class DiagnosticRuntime with WidgetsBindingObserver {
  DiagnosticRuntime(this.logger);
  final AppLogger logger;
  void Function(FlutterErrorDetails)? _previousFlutterHandler;
  bool Function(Object, StackTrace)? _previousPlatformHandler;

  void install() {
    _previousFlutterHandler = FlutterError.onError;
    _previousPlatformHandler =
        WidgetsBinding.instance.platformDispatcher.onError;
    FlutterError.onError = (details) {
      logger.record(
        AppLogEvent.frameworkError,
        level: AppLogLevel.error,
        error: details.exception,
        stackTrace: details.stack,
      );
      unawaited(logger.flush());
      _previousFlutterHandler?.call(details);
    };
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      logger.record(
        AppLogEvent.asyncError,
        level: AppLogLevel.error,
        error: error,
        stackTrace: stack,
      );
      unawaited(logger.flush());
      return _previousPlatformHandler?.call(error, stack) ?? false;
    };
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> openStore() async {
    try {
      final store = await openDiagnosticLogStore();
      if (store != null) await logger.attachStore(store);
    } on Object {
      // Memory logging remains available when storage is not writable.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    logger.record(AppLogEvent.appLifecycle, fields: {'state': state.name});
    if (state != AppLifecycleState.resumed) unawaited(logger.flush());
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FlutterError.onError = _previousFlutterHandler;
    WidgetsBinding.instance.platformDispatcher.onError =
        _previousPlatformHandler;
  }
}
