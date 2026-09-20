import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/diagnostics/diagnostic_reporter.dart';
import 'package:musicfree_service_client/diagnostics/sentry_diagnostic_uploader.dart';

const _dsn = 'https://public@o0.ingest.sentry.io/0';
const _id = '0123456789abcdef0123456789abcdef';

void main() {
  DiagnosticPackage package() => DiagnosticPackage(
    bytes: Uint8List.fromList(gzip.encode(utf8.encode('{"safe":true}\n'))),
    entryCount: 0,
    version: '1.0.8+9',
    platform: 'android',
    serviceHost: null,
  );

  test(
    'SDK sends exactly one envelope with a gzip attachment and returns remote ID',
    () async {
      var calls = 0;
      final uploader = SentryDiagnosticUploader(
        dsn: _dsn,
        httpClientFactory: () => MockClient((request) async {
          calls++;
          expect(
            request.url.toString(),
            'https://o0.ingest.sentry.io/api/0/envelope/',
          );
          expect(request.followRedirects, isFalse);
          final bytes = request.headers['content-encoding'] == 'gzip'
              ? gzip.decode(request.bodyBytes)
              : request.bodyBytes;
          var offset = 0;
          Map<String, dynamic> readLine() {
            final end = bytes.indexOf(10, offset);
            final result =
                jsonDecode(utf8.decode(bytes.sublist(offset, end)))
                    as Map<String, dynamic>;
            offset = end + 1;
            return result;
          }

          final envelope = readLine();
          expect(envelope['event_id'], isNotEmpty);
          final eventHeader = readLine();
          expect(eventHeader['type'], 'event');
          final eventLength = eventHeader['length'] as int;
          final event =
              jsonDecode(
                    utf8.decode(bytes.sublist(offset, offset + eventLength)),
                  )
                  as Map;
          offset += eventLength + 1;
          expect(event['message']['formatted'], 'User submitted diagnostics');
          expect(event['release'], 'tuneflow@1.0.8+9');
          expect(event['user'], isNull);
          expect(event['request'], isNull);
          expect(event['threads'], isNull);
          final attachmentHeader = readLine();
          expect(attachmentHeader['type'], 'attachment');
          expect(attachmentHeader['filename'], 'diagnostics.jsonl.gz');
          expect(attachmentHeader['content_type'], 'application/gzip');
          final attachment = bytes.sublist(
            offset,
            offset + (attachmentHeader['length'] as int),
          );
          expect(utf8.decode(gzip.decode(attachment)), '{"safe":true}\n');
          expect(
            bytes.length - offset - attachment.length,
            lessThanOrEqualTo(1),
          );
          return http.Response('{"id":"$_id"}', 200);
        }),
      );
      expect(calls, 0);
      expect(await uploader.upload(package()), _id);
      expect(calls, 1);
    },
  );

  for (final status in [302, 413, 429, 500]) {
    test('HTTP $status fails without claiming success or retrying', () async {
      var calls = 0;
      final uploader = SentryDiagnosticUploader(
        dsn: _dsn,
        httpClientFactory: () => MockClient((_) async {
          calls++;
          return http.Response('{}', status);
        }),
      );
      await expectLater(uploader.upload(package()), throwsStateError);
      expect(calls, 1);
    });
  }

  test('network errors and malformed success responses are failures', () async {
    for (final client in [
      MockClient((_) async => throw const SocketException('private host')),
      MockClient((_) async => http.Response('{}', 200)),
    ]) {
      final uploader = SentryDiagnosticUploader(
        dsn: _dsn,
        httpClientFactory: () => client,
      );
      await expectLater(uploader.upload(package()), throwsStateError);
    }
  });

  test('timeout closes active client and does not retry', () async {
    final client = _HangingClient();
    final uploader = SentryDiagnosticUploader(
      dsn: _dsn,
      timeout: const Duration(milliseconds: 20),
      httpClientFactory: () => client,
    );
    await expectLater(
      uploader.upload(package()),
      throwsA(isA<TimeoutException>()),
    );
    expect(client.closed, isTrue);
    expect(client.calls, 1);
  });

  test(
    'missing, secret-bearing or non-Sentry DSN never creates a network client',
    () async {
      for (final dsn in [
        '',
        'not a dsn',
        'http://public@o0.ingest.sentry.io/0',
        'https://public:secret@o0.ingest.sentry.io/0',
        'https://public@untrusted.example/0',
      ]) {
        final uploader = SentryDiagnosticUploader(
          dsn: dsn,
          httpClientFactory: () => throw StateError('Must not create client'),
        );
        expect(uploader.configured, isFalse);
        await expectLater(uploader.upload(package()), throwsStateError);
      }
    },
  );
}

final class _HangingClient extends http.BaseClient {
  bool closed = false;
  int calls = 0;
  final response = Completer<http.StreamedResponse>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    await request.finalize().drain<void>();
    return response.future;
  }

  @override
  void close() {
    closed = true;
    if (!response.isCompleted) {
      response.completeError(const SocketException('closed'));
    }
  }
}
