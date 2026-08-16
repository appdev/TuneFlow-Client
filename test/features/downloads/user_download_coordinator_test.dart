import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_exception.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/downloads/download_repository.dart';
import 'package:musicfree_service_client/features/downloads/user_download_coordinator.dart';

void main() {
  test('creates a user download with conflict detection enabled', () async {
    final policies = <String?>[];
    final coordinator = _coordinator((request) async {
      policies.add(_policy(request));
      return _downloadResponse('normal');
    });
    var confirmationCalled = false;

    final result = await coordinator.create(
      _track,
      'flac',
      confirmReplacement: (_) async {
        confirmationCalled = true;
        return true;
      },
    );

    expect(policies, ['error']);
    expect(confirmationCalled, isFalse);
    expect(result.job?.raw['id'], 'normal');
    expect(result.replaced, isFalse);
  });

  test('confirms an existing file before retrying with replace', () async {
    final policies = <String?>[];
    final coordinator = _coordinator((request) async {
      final policy = _policy(request);
      policies.add(policy);
      return policy == 'error'
          ? _serviceError('DOWNLOAD_ALREADY_EXISTS', 409)
          : _downloadResponse('replacement');
    });
    String? message;

    final result = await coordinator.create(
      _track,
      'flac',
      confirmReplacement: (value) async {
        message = value;
        return true;
      },
    );

    expect(policies, ['error', 'replace']);
    expect(message, '重新下载成功后将替换现有文件。');
    expect(result.job?.raw['id'], 'replacement');
    expect(result.replaced, isTrue);
  });

  test(
    'cancelling an existing-file prompt does not create a replacement',
    () async {
      final policies = <String?>[];
      final coordinator = _coordinator((request) async {
        policies.add(_policy(request));
        return _serviceError('DOWNLOAD_ALREADY_EXISTS', 409);
      });

      final result = await coordinator.create(
        _track,
        'flac',
        confirmReplacement: (_) async => false,
      );

      expect(policies, ['error']);
      expect(result.job, isNull);
      expect(result.replaced, isFalse);
    },
  );

  test('does not prompt or retry for unrelated Service failures', () async {
    final policies = <String?>[];
    final coordinator = _coordinator((request) async {
      policies.add(_policy(request));
      return _serviceError('SOURCE_UNAVAILABLE', 503);
    });
    var confirmationCalled = false;

    await expectLater(
      coordinator.create(
        _track,
        'flac',
        confirmReplacement: (_) async {
          confirmationCalled = true;
          return true;
        },
      ),
      throwsA(
        isA<ServiceException>().having(
          (error) => error.code,
          'code',
          'SOURCE_UNAVAILABLE',
        ),
      ),
    );

    expect(policies, ['error']);
    expect(confirmationCalled, isFalse);
  });
}

final Track _track = Track.fromJson({
  'id': 'one',
  'name': 'One',
  'source': 'kw',
});

UserDownloadCoordinator _coordinator(
  Future<http.Response> Function(http.Request request) handler,
) => UserDownloadCoordinator(
  DownloadRepository(
    ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient(handler),
    ),
  ),
);

String? _policy(http.Request request) =>
    (jsonDecode(request.body) as Map<String, Object?>)['existingFilePolicy']
        as String?;

http.Response _serviceError(String code, int status) => http.Response(
  jsonEncode({
    'error': {'code': code, 'message': code},
  }),
  status,
);

http.Response _downloadResponse(String id) => http.Response(
  jsonEncode({
    'data': {
      'id': id,
      'status': 'waiting',
      'musicInfo': {'id': 'one', 'name': 'One', 'source': 'kw'},
      'quality': 'flac',
      'extension': 'flac',
      'fileName': 'one.flac',
      'downloaded': 0,
      'total': 0,
      'progress': 0,
      'queuePosition': 1,
      'createdAt': 1000,
      'updatedAt': 1000,
    },
  }),
  201,
);
