import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_exception.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/library/library_repository.dart';
import 'package:musicfree_service_client/features/library/local_library_controller.dart';

http.Response data(Object? value) =>
    http.Response(jsonEncode({'data': value}), 200);

Map<String, Object?> libraryJson(String fileId, String trackId, String name) =>
    {
      'id': fileId,
      'musicInfo': {'id': trackId, 'name': name, 'source': 'kw'},
      'size': 12,
      'extension': 'mp3',
      'streamUrl': '/api/v1/library/tracks/$fileId/stream',
    };

LibraryRepository repositoryWith(
  Future<http.Response> Function(http.Request request) handler,
) => LibraryRepository(
  ServiceApi(
    ServiceOrigin.parse('http://service.local'),
    client: MockClient(handler),
  ),
);

void main() {
  test(
    'library repository resolves same-origin picture and lyrics resources',
    () async {
      final repository = repositoryWith(
        (_) async => data([
          {
            ...libraryJson('file-a', 'track-a', 'A'),
            'pictureUrl': '/api/v1/library/tracks/file-a/picture',
            'lyricsUrl': '/api/v1/library/tracks/file-a/lyrics',
          },
        ]),
      );

      final item = (await repository.list()).single;

      expect(
        item.pictureUrl,
        Uri.parse('http://service.local/api/v1/library/tracks/file-a/picture'),
      );
      expect(item.lyricsPath, '/api/v1/library/tracks/file-a/lyrics');
      expect(
        item.track.raw['pic'],
        'http://service.local/api/v1/library/tracks/file-a/picture',
      );
      expect(
        (item.track.raw['meta'] as Map)['lyricsUrl'],
        '/api/v1/library/tracks/file-a/lyrics',
      );
    },
  );

  test(
    'library repository rejects external and filesystem resource values',
    () async {
      for (final invalid in [
        'https://other.example/cover.jpg',
        'file:///tmp/cover.jpg',
        '/api/v1/library/tracks/file-a/picture?token=secret',
      ]) {
        final repository = repositoryWith(
          (_) async => data([
            {...libraryJson('file-a', 'track-a', 'A'), 'pictureUrl': invalid},
          ]),
        );

        await expectLater(
          repository.list(),
          throwsA(
            isA<ServiceException>().having(
              (error) => error.code,
              'code',
              'INVALID_RESPONSE',
            ),
          ),
        );
      }
    },
  );

  test('playOne keeps the complete local queue and selected index', () async {
    final controller = LocalLibraryController(
      repositoryWith(
        (_) async => data([
          libraryJson('file-a', 'a', 'A'),
          libraryJson('file-b', 'b', 'B'),
          libraryJson('file-c', 'c', 'C'),
        ]),
      ),
    );
    List<String> queued = const [];
    var selectedIndex = -1;

    await controller.refresh();
    await controller.playOne((tracks, {startIndex = 0}) async {
      queued = tracks.map((track) => track.id).toList(growable: false);
      selectedIndex = startIndex;
    }, 1);

    expect(queued, ['a', 'b', 'c']);
    expect(selectedIndex, 1);
  });

  test('empty local library never starts playback', () async {
    final controller = LocalLibraryController(
      repositoryWith((_) async => data(<Object?>[])),
    );
    var playCalls = 0;

    await controller.refresh();
    await controller.playAll((_, {startIndex = 0}) async => playCalls++);
    await controller.playOne((_, {startIndex = 0}) async => playCalls++, 0);

    expect(playCalls, 0);
  });

  test('failed refresh retains the last usable local library', () async {
    var fail = false;
    final controller = LocalLibraryController(
      repositoryWith((_) async {
        if (fail) throw StateError('offline');
        return data([libraryJson('file-a', 'a', 'A')]);
      }),
    );

    await controller.refresh();
    fail = true;
    await controller.refresh();

    expect(controller.state.items.single.track.id, 'a');
    expect(controller.state.stale, isTrue);
    expect(controller.state.error, isNotNull);
  });

  test('refresh completes quietly when disposed while loading', () async {
    final response = Completer<http.Response>();
    final controller = LocalLibraryController(
      repositoryWith((_) => response.future),
    );

    final refresh = controller.refresh();
    controller.dispose();
    response.complete(data(<Object?>[]));

    await expectLater(refresh, completes);
  });

  test(
    'delete uses the library file id and removes the item after success',
    () async {
      final calls = <http.Request>[];
      final controller = LocalLibraryController(
        repositoryWith((request) async {
          calls.add(request);
          if (request.method == 'DELETE') return http.Response('', 204);
          return data([
            libraryJson('file/a', 'track-a', 'A'),
            libraryJson('file-b', 'track-b', 'B'),
          ]);
        }),
      );

      await controller.refresh();
      await controller.delete('file/a');

      expect(calls.last.method, 'DELETE');
      expect(calls.last.url.path, '/api/v1/library/tracks/file%2Fa');
      expect(controller.state.items.map((item) => item.id), ['file-b']);
      expect(controller.state.deletingIds, isEmpty);
    },
  );

  test('failed delete retains the item and clears its pending state', () async {
    final controller = LocalLibraryController(
      repositoryWith((request) async {
        if (request.method == 'DELETE') {
          return http.Response(
            jsonEncode({
              'error': {'code': 'DELETE_FAILED', 'message': 'Delete failed'},
            }),
            500,
          );
        }
        return data([libraryJson('file-a', 'track-a', 'A')]);
      }),
    );

    await controller.refresh();

    await expectLater(
      controller.delete('file-a'),
      throwsA(isA<ServiceException>()),
    );
    expect(controller.state.items.single.id, 'file-a');
    expect(controller.state.deletingIds, isEmpty);
  });

  test('loadPicture accepts only network artwork', () async {
    final controller = LocalLibraryController(
      repositoryWith((_) async => data(<Object?>[])),
    );

    expect(
      await controller.loadPicture(
        musicTrack('https://cdn.example.test/cover.jpg'),
      ),
      Uri.parse('https://cdn.example.test/cover.jpg'),
    );
    expect(
      await controller.loadPicture(musicTrack('file:///tmp/cover.jpg')),
      isNull,
    );
  });
}

Track musicTrack(String picture) => Track.fromJson({
  'id': 'track',
  'name': 'Track',
  'source': 'kw',
  'pic': picture,
});
