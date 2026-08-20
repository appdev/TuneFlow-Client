import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/service_exception.dart';
import 'package:musicfree_service_client/features/connection/server_endpoint_probe.dart';

void main() {
  test('retries health three total times with two second gaps', () async {
    var attempts = 0;
    final waits = <Duration>[];
    final probe = ServerEndpointProbe(
      requestHealth: (origin) async {
        attempts++;
        if (attempts < 3) {
          throw const ServiceException('NETWORK_ERROR', 'down');
        }
        return {
          'status': 'ok',
          'lanOrigin': 'http://192.168.1.20:3124/',
          'externalOrigin': 'https://music.example.com/',
        };
      },
      delay: (duration) async => waits.add(duration),
    );

    final result = await probe.probe('https://bootstrap.example');

    expect(attempts, 3);
    expect(waits, [const Duration(seconds: 2), const Duration(seconds: 2)]);
    expect(result.origin.uri.toString(), 'https://bootstrap.example');
    expect(result.lanOrigin?.uri.toString(), 'http://192.168.1.20:3124');
    expect(result.externalOrigin?.uri.toString(), 'https://music.example.com');
  });

  test('stops after the first healthy response', () async {
    var attempts = 0;
    final waits = <Duration>[];
    final probe = ServerEndpointProbe(
      requestHealth: (origin) async {
        attempts++;
        return {'status': 'ok'};
      },
      delay: (duration) async => waits.add(duration),
    );

    final result = await probe.probe('http://service.local');

    expect(attempts, 1);
    expect(waits, isEmpty);
    expect(result.lanOrigin, isNull);
    expect(result.externalOrigin, isNull);
  });

  test('times out each attempt and stops after the third failure', () async {
    var attempts = 0;
    final waits = <Duration>[];
    final probe = ServerEndpointProbe(
      requestHealth: (origin) {
        attempts++;
        return Completer<Object?>().future;
      },
      timeout: const Duration(milliseconds: 5),
      delay: (duration) async => waits.add(duration),
    );

    await expectLater(
      probe.probe('http://service.local'),
      throwsA(
        isA<ServiceException>().having(
          (error) => error.code,
          'code',
          'CONNECTION_TIMEOUT',
        ),
      ),
    );
    expect(attempts, 3);
    expect(waits, [const Duration(seconds: 2), const Duration(seconds: 2)]);
  });

  test('cancels before starting another retry', () async {
    var cancelled = false;
    var attempts = 0;
    final probe = ServerEndpointProbe(
      requestHealth: (origin) async {
        attempts++;
        throw const ServiceException('NETWORK_ERROR', 'down');
      },
      delay: (duration) async => cancelled = true,
    );

    await expectLater(
      probe.probe('http://service.local', cancelled: () => cancelled),
      throwsA(isA<ProbeCancelledException>()),
    );
    expect(attempts, 1);
  });

  test('ignores malformed advertised origins from a healthy Service', () async {
    final probe = ServerEndpointProbe(
      requestHealth: (origin) async => {
        'status': 'ok',
        'lanOrigin': 'http://service.local/base',
        'externalOrigin': 'not a URL',
      },
    );

    final result = await probe.probe('http://service.local');

    expect(result.origin.uri.toString(), 'http://service.local');
    expect(result.lanOrigin, isNull);
    expect(result.externalOrigin, isNull);
  });

  test('retries responses that are not healthy', () async {
    var attempts = 0;
    final probe = ServerEndpointProbe(
      requestHealth: (origin) async {
        attempts++;
        return {'status': 'starting'};
      },
      delay: (_) async {},
    );

    await expectLater(
      probe.probe('http://service.local'),
      throwsA(
        isA<ServiceException>().having(
          (error) => error.code,
          'code',
          'SERVICE_UNHEALTHY',
        ),
      ),
    );
    expect(attempts, 3);
  });
}
