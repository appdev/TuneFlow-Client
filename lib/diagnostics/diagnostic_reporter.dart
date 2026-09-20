import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'app_logger.dart';
import 'diagnostic_platform.dart';

typedef DiagnosticCompressor = Future<Uint8List> Function(String jsonl);
typedef DiagnosticConsent = Future<bool> Function(DiagnosticPackage package);

abstract interface class DiagnosticUploader {
  bool get configured;
  Future<String> upload(DiagnosticPackage package);
}

final class DiagnosticPackage {
  DiagnosticPackage({
    required Uint8List bytes,
    required this.entryCount,
    required this.version,
    required this.platform,
    required this.serviceHost,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  static const maxCompressedBytes = 1024 * 1024;
  final Uint8List bytes;
  final int entryCount;
  final String version;
  final String platform;
  final String? serviceHost;
}

/// Coordinates prepare -> consent -> one upload. No automatic retry or queue.
final class DiagnosticReporter extends ChangeNotifier {
  DiagnosticReporter({
    required this.logger,
    required this.uploader,
    required this.loadVersion,
    this.supported = !kIsWeb,
    DiagnosticCompressor? compress,
  }) : _compress = compress ?? compressDiagnosticPackage;

  final AppLogger logger;
  final DiagnosticUploader uploader;
  final Future<String> Function() loadVersion;
  final bool supported;
  final DiagnosticCompressor _compress;
  bool busy = false;
  bool _disposed = false;
  String? eventId;
  String? errorMessage;
  bool get available => supported && uploader.configured;

  Future<void> submit({
    required DiagnosticConsent confirm,
    String? serviceOrigin,
  }) async {
    if (busy || _disposed) return;
    eventId = null;
    errorMessage = null;
    if (!available) {
      errorMessage = '此版本暂未启用日志上传。';
      _notify();
      return;
    }
    busy = true;
    _notify();
    try {
      String version;
      try {
        version = await loadVersion().timeout(const Duration(seconds: 3));
      } on Object {
        version = 'unknown';
      }
      if (!RegExp(r'^[a-zA-Z0-9.+_-]{1,80}$').hasMatch(version)) {
        version = 'unknown';
      }
      final platform = defaultTargetPlatform.name;
      final host = _serviceHost(serviceOrigin);
      // Freeze the exact snapshot shown in the consent dialog.
      final lines = logger.snapshot();
      final metadata = jsonEncode({
        'schema': 1,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'app': 'TuneFlow',
        'version': version,
        'platform': platform,
        'service_host': host,
        'entries': lines.length,
        'persistence_available': logger.persistenceAvailable,
      });
      final bytes = await _compress('$metadata\n${lines.join('\n')}\n');
      if (bytes.length > DiagnosticPackage.maxCompressedBytes) {
        throw StateError('Diagnostic package exceeds the size limit');
      }
      final package = DiagnosticPackage(
        bytes: bytes,
        entryCount: lines.length,
        version: version,
        platform: platform,
        serviceHost: host,
      );
      if (_disposed || !await confirm(package) || _disposed) return;
      final id = await uploader.upload(package);
      eventId = id;
      logger.record(AppLogEvent.uploadAccepted);
    } on Object catch (error) {
      errorMessage = '日志未确认上传成功，请检查网络或稍后重试。不会自动重试。';
      logger.record(
        AppLogEvent.uploadFailed,
        level: AppLogLevel.warning,
        error: error,
      );
    } finally {
      busy = false;
      _notify();
    }
  }

  static String? _serviceHost(String? value) {
    if (value == null || value.length > 2048) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return null;
    }
    // Never include user-info, paths, query values, or fragments.
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
