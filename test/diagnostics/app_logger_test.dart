import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/service_exception.dart';
import 'package:musicfree_service_client/diagnostics/app_logger.dart';
import 'package:musicfree_service_client/diagnostics/diagnostic_platform_io.dart';

void main() {
  test('records only allowed diagnostic fields, never arbitrary user content', () {
    final logger = AppLogger();
    logger.record(
      AppLogEvent.httpFailed,
      fields: {
        'method': 'GET',
        'route':
            'https://name:password@private.host/api/v1/tracks/private-song?token=hidden#secret',
        'authorization': 'Bearer secret',
        'cookie': 'session=private',
        'path': '/Users/person/private.mp3',
        'title': 'private-song',
        'body': {'nested': 'private-body'},
        'status': 401,
      },
      error: const ServiceException(
        'NETWORK_ERROR',
        'private-error',
        details: 'private-details',
      ),
      stackTrace: StackTrace.fromString(
        '#0 f (package:musicfree_service_client/api/service_api.dart:99:1)\n/Users/person/private.dart:1\nAuthorization: secret',
      ),
    );
    final text = logger.snapshot().single;
    final data = jsonDecode(text) as Map;
    expect(data['fields'], {
      'status': 401,
      'method': 'GET',
      'error_type': 'ServiceException',
      'code': 'NETWORK_ERROR',
      'route': '/api/v1/tracks/:id',
      'stack': 'package:musicfree_service_client/api/service_api.dart:99:1',
    });
    for (final forbidden in [
      'private',
      'hidden',
      'secret',
      'password',
      'Bearer',
      'Users',
      'cookie',
    ]) {
      expect(text, isNot(contains(forbidden)));
    }
    expect(
      () => logger.record(
        AppLogEvent.httpFailed,
        fields: {'route': '/api/v1/%FF'},
      ),
      returnsNormally,
    );
  });

  test('evicts old records by both count and bytes, and suppresses debug', () {
    final logger = AppLogger(
      maxEntries: 3,
      maxBytes: 1024,
      includeDebug: false,
    );
    logger.record(AppLogEvent.appStarted, level: AppLogLevel.debug);
    expect(logger.count, 0);
    for (var i = 0; i < 10; i++) {
      logger.record(AppLogEvent.httpCompleted, fields: {'status': i});
    }
    expect(logger.count, 3);
    expect(jsonDecode(logger.snapshot().first)['fields']['status'], 7);
    logger.record(
      AppLogEvent.frameworkError,
      stackTrace: StackTrace.fromString(
        List.filled(
          20,
          'package:musicfree_service_client/long_code_location.dart:123:45',
        ).join('\n'),
      ),
    );
    expect(logger.byteCount, lessThanOrEqualTo(1024));
  });

  test('revalidates restored files, drops old or malformed records', () async {
    final logger = AppLogger();
    logger.record(AppLogEvent.appStarted);
    final original =
        jsonDecode(logger.snapshot().single) as Map<String, dynamic>;
    final contaminated = {
      ...original,
      'unexpected': 'private-data',
      'fields': {'token': 'secret', 'status': 204},
    };
    final old = {
      ...original,
      'time': DateTime.now()
          .subtract(const Duration(days: 8))
          .toIso8601String(),
    };
    final store = _MemoryStore(
      '${jsonEncode(contaminated)}\n${jsonEncode(old)}\nnot-json\n',
    );
    await logger.attachStore(store);
    await logger.flush();
    expect(logger.count, 2);
    expect(store.value, isNot(contains('secret')));
    expect(store.value, isNot(contains('private-data')));
    expect(store.value, isNot(contains('not-json')));
  });

  test(
    'storage failure degrades to memory and later flush can recover',
    () async {
      final store = _MemoryStore('')..fail = true;
      final logger = AppLogger();
      await logger.attachStore(store);
      logger.record(AppLogEvent.appStarted);
      await logger.flush();
      expect(logger.persistenceAvailable, isFalse);
      expect(logger.count, 1);
      store.fail = false;
      await logger.flush();
      expect(logger.persistenceAvailable, isTrue);
      expect(store.value, contains('appStarted'));
    },
  );

  test(
    'concurrent flushes serialize and include logs arriving during IO',
    () async {
      final store = _MemoryStore('')..gate = Completer<void>();
      final logger = AppLogger();
      await logger.attachStore(store);
      logger.record(AppLogEvent.appStarted);
      final first = logger.flush();
      logger.record(AppLogEvent.httpCompleted);
      final second = logger.flush();
      expect(store.maxActive, 1);
      store.gate!.complete();
      await Future.wait([first, second]);
      expect(store.maxActive, 1);
      expect(store.value, contains('httpCompleted'));
    },
  );

  test(
    'native store replaces bounded snapshots and reloads across launches',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tuneflow-log-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileDiagnosticLogStore(directory);
      final first = AppLogger();
      await first.attachStore(store);
      first.record(AppLogEvent.appStarted);
      await first.flush();
      first.record(AppLogEvent.httpCompleted);
      await first.flush();
      expect(await File('${directory.path}/recent.pending').exists(), isFalse);
      final second = AppLogger();
      await second.attachStore(store);
      await second.flush();
      expect(second.count, 2);
      await expectLater(
        store.write('x' * (FileDiagnosticLogStore.maxFileBytes + 1)),
        throwsStateError,
      );
      expect(
        (await store.read()).split('\n').where((l) => l.isNotEmpty),
        hasLength(2),
      );
    },
  );
}

final class _MemoryStore implements DiagnosticLogStore {
  _MemoryStore(this.value);
  String value;
  bool fail = false;
  Completer<void>? gate;
  int active = 0;
  int maxActive = 0;
  @override
  Future<String> read() async {
    if (fail) throw FileSystemException('private path');
    return value;
  }

  @override
  Future<void> write(String jsonl) async {
    if (fail) throw FileSystemException('private path');
    active++;
    if (active > maxActive) maxActive = active;
    await gate?.future;
    value = jsonl;
    active--;
  }
}
