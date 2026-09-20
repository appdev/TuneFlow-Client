import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'diagnostic_reporter.dart';

/// An isolated SDK client: never installs automatic/native integrations.
/// Constructed only AFTER explicit consent, closed after a single request.
final class SentryDiagnosticUploader implements DiagnosticUploader {
  SentryDiagnosticUploader({
    this.dsn = const String.fromEnvironment('SENTRY_DSN'),
    this.timeout = const Duration(seconds: 20),
    http.Client Function()? httpClientFactory,
  }) : _httpClientFactory = httpClientFactory ?? http.Client.new;

  final String dsn;
  final Duration timeout;
  final http.Client Function() _httpClientFactory;

  @override
  bool get configured {
    final uri = Uri.tryParse(dsn);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.endsWith('.sentry.io') &&
        uri.userInfo.isNotEmpty &&
        !uri.userInfo.contains(':') &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty &&
        RegExp(r'^/\d+$').hasMatch(uri.path);
  }

  @override
  Future<String> upload(DiagnosticPackage package) async {
    if (!configured) throw StateError('Sentry is not configured');
    if (package.bytes.isEmpty ||
        package.bytes.length > DiagnosticPackage.maxCompressedBytes) {
      throw StateError('Invalid diagnostic attachment size');
    }
    final httpClient = _NoRedirectClient(_httpClientFactory());
    final options = SentryOptions(dsn: dsn)
      ..httpClient = httpClient
      ..sendDefaultPii = false
      ..sendClientReports = false
      ..attachStacktrace = false
      ..attachThreads = false
      ..debug = false
      ..maxAttachmentSize = DiagnosticPackage.maxCompressedBytes
      ..release = 'tuneflow@${package.version}';
    final client = SentryClient(options);
    try {
      final scope = Scope(options)
        ..addAttachment(
          SentryAttachment.fromUint8List(
            package.bytes,
            'diagnostics.jsonl.gz',
            contentType: 'application/gzip',
          ),
        );
      final id = await client
          .captureEvent(
            SentryEvent(
              message: SentryMessage('User submitted diagnostics'),
              level: SentryLevel.info,
              tags: {
                'report_type': 'manual_diagnostics',
                'app_platform': package.platform,
              },
            ),
            scope: scope,
          )
          .timeout(timeout);
      if (id == SentryId.empty()) {
        throw StateError('Sentry did not accept the report');
      }
      return id.toString();
    } finally {
      // Also abort an outstanding request when timeout fires.
      httpClient.close();
      await client.close();
    }
  }
}

final class _NoRedirectClient extends http.BaseClient {
  _NoRedirectClient(this.inner);
  final http.Client inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.followRedirects = false;
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}
