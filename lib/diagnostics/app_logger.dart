import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api/service_exception.dart';

enum AppLogLevel { debug, info, warning, error }

/// Fixed messages prevent arbitrary exception bodies or user data entering logs.
enum AppLogEvent {
  appStarted,
  appLifecycle,
  frameworkError,
  asyncError,
  startupFailed,
  shaderUnavailable,
  mediaCacheUnavailable,
  imageCacheMigrationFailed,
  imageCacheUnavailable,
  imageCacheFallbackFailed,
  desktopWindowFailed,
  menuBarUpdateFailed,
  menuBarCommandFailed,
  httpCompleted,
  httpFailed,
  serviceConnected,
  serviceConnectionFailed,
  serviceDisconnected,
  eventStreamConnected,
  eventStreamFailed,
  playbackStarted,
  playbackFailed,
  playbackCacheFailed,
  playbackStateFailed,
  lyricsFailed,
  radioFailed,
  uploadAccepted,
  uploadFailed,
}

abstract interface class DiagnosticLogStore {
  Future<String> read();
  Future<void> write(String jsonl);
}

/// Bounded, local-only logging. No network client is constructed here.
final class AppLogger {
  AppLogger({
    this.maxEntries = 500,
    this.maxBytes = 512 * 1024,
    this.includeDebug = kDebugMode,
    this.console = false,
    this.flushInterval = const Duration(seconds: 2),
  }) : assert(maxEntries > 0),
       assert(maxBytes >= 1024);

  static final instance = AppLogger(console: kDebugMode);
  final int maxEntries;
  final int maxBytes;
  final bool includeDebug;
  final bool console;
  final Duration flushInterval;
  final String sessionId = List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final _lines = ListQueue<String>();
  int _bytes = 0;
  int _revision = 0;
  int _savedRevision = -1;
  DiagnosticLogStore? _store;
  Timer? _flushTimer;
  Future<void>? _writing;
  bool persistenceAvailable = false;

  int get count => _lines.length;
  int get byteCount => _bytes;

  void record(
    AppLogEvent event, {
    AppLogLevel level = AppLogLevel.info,
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level == AppLogLevel.debug && !includeDebug) return;
    final data = <String, Object?>{
      'time': DateTime.now().toUtc().toIso8601String(),
      'session': sessionId,
      'level': level.name,
      'event': event.name,
      'fields': safeFields({
        ...fields,
        if (error != null) 'error_type': error.runtimeType.toString(),
        if (error is ServiceException) 'code': error.code,
        if (stackTrace != null) 'stack': safeStack(stackTrace.toString()),
      }),
    };
    final line = jsonEncode(data);
    _append(line);
    if (console) developer.log(line, name: 'TuneFlow');
    _scheduleFlush();
  }

  void _append(String line) {
    final bytes = utf8.encode(line).length + 1;
    if (bytes > maxBytes) return;
    _lines.add(line);
    _bytes += bytes;
    while (_lines.length > maxEntries || _bytes > maxBytes) {
      _bytes -= utf8.encode(_lines.removeFirst()).length + 1;
    }
    _revision++;
  }

  Future<void> attachStore(DiagnosticLogStore store) async {
    // Keep logs produced while the previous session is being read.
    String previous = '';
    try {
      previous = await store.read();
      persistenceAvailable = true;
    } on Object {
      persistenceAvailable = false;
    }
    final current = _lines.toList();
    _lines.clear();
    _bytes = 0;
    for (final line in const LineSplitter().convert(previous)) {
      final safe = sanitizeStoredLine(line);
      if (safe != null) _append(safe);
    }
    for (final line in current) {
      _append(line);
    }
    _store = store;
    _scheduleFlush();
  }

  /// Revalidate on export as well as on initial recording and disk restore.
  List<String> snapshot() =>
      List.unmodifiable(_lines.map(sanitizeStoredLine).whereType<String>());

  void _scheduleFlush() {
    if (_store == null || _flushTimer != null || _writing != null) return;
    _flushTimer = Timer(flushInterval, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    final active = _writing;
    if (active != null) {
      await active;
      return flush();
    }
    final store = _store;
    if (store == null || _savedRevision == _revision) return;
    final revision = _revision;
    final data = '${_lines.join('\n')}\n';
    final operation = () async {
      try {
        await store.write(data);
        persistenceAvailable = true;
        _savedRevision = revision;
      } on Object {
        // Logging must never interrupt playback, startup, or error handling.
        persistenceAvailable = false;
      }
    }();
    _writing = operation;
    await operation;
    _writing = null;
    if (_revision != revision) _scheduleFlush();
  }

  static String? sanitizeStoredLine(String line) {
    if (line.length > 8192) return null;
    try {
      final data = jsonDecode(line);
      if (data is! Map ||
          !AppLogEvent.values.any((e) => e.name == data['event']) ||
          !AppLogLevel.values.any((e) => e.name == data['level']) ||
          data['time'] is! String ||
          data['session'] is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(data['session'] as String)) {
        return null;
      }
      final time = DateTime.tryParse(data['time'] as String);
      // Old diagnostics are not retained indefinitely, even in rarely used apps.
      if (time == null ||
          DateTime.now().toUtc().difference(time) > const Duration(days: 7)) {
        return null;
      }
      return jsonEncode({
        'time': time.toUtc().toIso8601String(),
        'session': data['session'],
        'level': data['level'],
        'event': data['event'],
        'fields': safeFields(
          data['fields'] is Map ? data['fields'] as Map : {},
        ),
      });
    } on Object {
      return null;
    }
  }

  static Map<String, Object> safeFields(Map fields) {
    final result = <String, Object>{};
    for (final key in const [
      'status',
      'duration_ms',
      'response_bytes',
      'attempt',
      'queue_length',
    ]) {
      final value = fields[key];
      if (value is int && value >= 0 && value <= 1 << 40) result[key] = value;
    }
    for (final entry in const {
      'method': {'GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'},
      'quality': {'128k', '320k', 'flac', 'flac24bit'},
      'state': {'resumed', 'inactive', 'hidden', 'paused', 'detached'},
      'endpoint_role': {'lan', 'external', 'bootstrap'},
      'network': {'lan', 'external', 'offline'},
    }.entries) {
      final value = fields[entry.key];
      if (value is String && entry.value.contains(value)) {
        result[entry.key] = value;
      }
    }
    final errorType = fields['error_type'];
    if (errorType is String &&
        RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,95}$').hasMatch(errorType)) {
      result['error_type'] = errorType;
    }
    final code = fields['code'];
    if (code is String && RegExp(r'^[A-Z_]{1,80}$').hasMatch(code)) {
      result['code'] = code;
    }
    final route = fields['route'];
    if (route is String) result['route'] = safeRoute(route);
    final stack = fields['stack'];
    if (stack is String) result['stack'] = safeStack(stack);
    return result;
  }

  /// Preserve only code locations, never exception messages or absolute paths.
  static String safeStack(String stack) =>
      RegExp(
            r'(?:package:[a-zA-Z0-9_]+/[a-zA-Z0-9_./-]+\.dart|dart:[a-zA-Z0-9_./-]+):\d+(?::\d+)?',
          )
          .allMatches(stack.length > 32000 ? stack.substring(0, 32000) : stack)
          .take(20)
          .map((m) => m.group(0)!)
          .join('\n');

  static String safeRoute(String value) {
    final uri = Uri.tryParse(
      value.length > 4096 ? value.substring(0, 4096) : value,
    );
    if (uri == null) return '/:unknown';
    const segments = {
      'api',
      'v1',
      'health',
      'capabilities',
      'search',
      'lyrics',
      'picture',
      'sources',
      'enable',
      'disable',
      'import',
      'export',
      'playlists',
      'tracks',
      'downloads',
      'library',
      'recommendations',
      'radio',
      'sessions',
      'next',
      'feedback',
      'settings',
      'playback',
      'resolve',
      'stream',
      'events',
      'snapshot',
      'history',
      'albums',
      'artists',
      'discover',
      'daily',
      'cancel',
      'retry',
      'batch',
      'cache',
      'progress',
      'end',
      'start',
    };
    try {
      return '/${uri.pathSegments.take(12).map((s) => segments.contains(s) ? s : ':id').join('/')}';
    } on FormatException {
      return '/:unknown';
    }
  }
}
