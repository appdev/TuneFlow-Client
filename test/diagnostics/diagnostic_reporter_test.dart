import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/diagnostics/app_logger.dart';
import 'package:musicfree_service_client/diagnostics/diagnostic_reporter.dart';

void main() {
  test(
    'compresses a frozen redacted snapshot, only sends after consent',
    () async {
      final logger = AppLogger()..record(AppLogEvent.appStarted);
      final uploader = _Uploader();
      final reporter = DiagnosticReporter(
        logger: logger,
        uploader: uploader,
        loadVersion: () async => '1.0.8+9',
      );
      addTearDown(reporter.dispose);
      final consent = Completer<bool>();
      final prepared = Completer<DiagnosticPackage>();
      final pending = reporter.submit(
        serviceOrigin:
            'https://name:password@service.example:443/private?token=hidden#secret',
        confirm: (package) {
          prepared.complete(package);
          return consent.future;
        },
      );
      final package = await prepared.future;
      expect(uploader.packages, isEmpty);
      expect(reporter.busy, isTrue);
      logger.record(AppLogEvent.playbackStarted);
      final lines = const LineSplitter().convert(
        utf8.decode(gzip.decode(package.bytes)),
      );
      final metadata = jsonDecode(lines.first);
      expect(metadata['version'], '1.0.8+9');
      expect(metadata['service_host'], 'https://service.example');
      expect(package.entryCount, 1);
      expect(lines.length, 2);
      for (final forbidden in [
        'name:',
        'password',
        'private',
        'token',
        'hidden',
        'secret',
        'playbackStarted',
      ]) {
        expect(lines.join(), isNot(contains(forbidden)));
      }
      consent.complete(true);
      await pending;
      expect(uploader.packages.single, same(package));
      expect(reporter.eventId, '0123456789abcdef0123456789abcdef');
      expect(reporter.busy, isFalse);
    },
  );

  test(
    'cancel, missing configuration and unsupported platform never upload',
    () async {
      for (final configured in [true, false]) {
        for (final supported in [true, false]) {
          final uploader = _Uploader()..configured = configured;
          final reporter = DiagnosticReporter(
            logger: AppLogger(),
            uploader: uploader,
            loadVersion: () async => '1.0',
            supported: supported,
          );
          var confirmations = 0;
          await reporter.submit(
            confirm: (_) async {
              confirmations++;
              return false;
            },
          );
          expect(uploader.packages, isEmpty);
          expect(confirmations, configured && supported ? 1 : 0);
          reporter.dispose();
        }
      }
    },
  );

  test(
    'concurrent submission is suppressed across preparation, consent and upload',
    () async {
      final uploader = _Uploader()..gate = Completer<void>();
      final reporter = DiagnosticReporter(
        logger: AppLogger(),
        uploader: uploader,
        loadVersion: () async => '1.0',
      );
      addTearDown(reporter.dispose);
      final consent = Completer<bool>();
      final prepared = Completer<void>();
      final pending = reporter.submit(
        confirm: (_) {
          prepared.complete();
          return consent.future;
        },
      );
      await prepared.future;
      await reporter.submit(
        confirm: (_) async => throw StateError('Must not confirm twice'),
      );
      consent.complete(true);
      await Future<void>.delayed(Duration.zero);
      await reporter.submit(confirm: (_) async => true);
      expect(uploader.packages, hasLength(1));
      uploader.gate!.complete();
      await pending;
    },
  );

  test(
    'failure is sanitized, stays local, and permits an explicit retry',
    () async {
      final uploader = _Uploader()..fail = true;
      final logger = AppLogger();
      final reporter = DiagnosticReporter(
        logger: logger,
        uploader: uploader,
        loadVersion: () async => '1.0',
      );
      addTearDown(reporter.dispose);
      await reporter.submit(confirm: (_) async => true);
      expect(reporter.eventId, isNull);
      expect(reporter.errorMessage, isNotNull);
      expect(logger.snapshot().join(), isNot(contains('private-upload-error')));
      expect(uploader.packages, hasLength(1));
      uploader.fail = false;
      await reporter.submit(confirm: (_) async => true);
      expect(reporter.errorMessage, isNull);
      expect(uploader.packages, hasLength(2));
    },
  );

  test('oversized package is rejected before consent or upload', () async {
    final uploader = _Uploader();
    final reporter = DiagnosticReporter(
      logger: AppLogger(),
      uploader: uploader,
      loadVersion: () async => '1.0',
      compress: (_) async =>
          Uint8List(DiagnosticPackage.maxCompressedBytes + 1),
    );
    addTearDown(reporter.dispose);
    await reporter.submit(
      confirm: (_) async => throw StateError('Must not confirm'),
    );
    expect(uploader.packages, isEmpty);
    expect(reporter.errorMessage, isNotNull);
  });

  test('disposing during confirmation cancels the pending upload', () async {
    final uploader = _Uploader();
    final reporter = DiagnosticReporter(
      logger: AppLogger(),
      uploader: uploader,
      loadVersion: () async => '1.0',
    );
    final pending = reporter.submit(
      confirm: (_) async {
        reporter.dispose();
        return true;
      },
    );
    await pending;
    expect(uploader.packages, isEmpty);
  });
}

final class _Uploader implements DiagnosticUploader {
  @override
  bool configured = true;
  bool fail = false;
  Completer<void>? gate;
  final packages = <DiagnosticPackage>[];
  @override
  Future<String> upload(DiagnosticPackage package) async {
    packages.add(package);
    await gate?.future;
    if (fail) throw StateError('private-upload-error');
    return '0123456789abcdef0123456789abcdef';
  }
}
