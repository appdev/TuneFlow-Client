import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/downloads/download_repository.dart';

void main() {
  test('clears download history through the collection endpoint', () async {
    late http.Request captured;
    final repository = DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'data': {'cleared': 2},
            }),
            200,
          );
        }),
      ),
    );

    expect(await repository.clearHistory(), 2);
    expect(captured.method, 'DELETE');
    expect(captured.url.path, '/api/v1/downloads/history/records');
  });

  test(
    'serializes every existing-file policy with its exact wire value',
    () async {
      final bodies = <Map<String, Object?>>[];
      final repository = DownloadRepository(
        ServiceApi(
          ServiceOrigin.parse('http://service.local'),
          client: MockClient((request) async {
            bodies.add(jsonDecode(request.body) as Map<String, Object?>);
            return _downloadResponse();
          }),
        ),
      );
      final track = Track.fromJson({'id': 'one', 'source': 'kw'});

      for (final policy in ExistingFilePolicy.values) {
        await repository.create(track, 'flac', existingFilePolicy: policy);
      }

      expect(bodies.map((body) => body['existingFilePolicy']), [
        'reuse',
        'error',
        'replace',
        'duplicate',
      ]);
    },
  );

  test('keeps the legacy request shape when no policy is supplied', () async {
    late Map<String, Object?> body;
    final repository = DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, Object?>;
          return _downloadResponse();
        }),
      ),
    );

    await repository.create(
      Track.fromJson({'id': 'one', 'source': 'kw'}),
      '128k',
    );

    expect(body, isNot(contains('existingFilePolicy')));
    expect(
      body['musicInfo'],
      containsPair('meta', containsPair('songId', 'one')),
    );
  });
}

http.Response _downloadResponse() => http.Response(
  jsonEncode({
    'data': {
      'id': 'download-one',
      'status': 'waiting',
      'musicInfo': {'id': 'one', 'source': 'kw'},
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
