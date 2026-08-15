import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/downloads/download_repository.dart';
import 'package:musicfree_service_client/features/home/home_controller.dart';
import 'package:musicfree_service_client/features/library/library_repository.dart';
import 'package:musicfree_service_client/features/playback_history/playback_history_repository.dart';
import 'package:musicfree_service_client/features/playlists/playlist_repository.dart';

http.Response data(Object? value) =>
    http.Response(jsonEncode({'data': value}), 200);

void main() {
  test(
    'dashboard retains the successful resource when the other fails',
    () async {
      var downloadsFail = false;
      final api = ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/playlists') {
            return data([
              {'id': 'one', 'name': 'One'},
            ]);
          }
          if (downloadsFail) throw StateError('downloads offline');
          return data(<Object?>[]);
        }),
      );
      final controller = HomeController(
        playlists: PlaylistRepository(api),
        downloads: DownloadRepository(api),
        library: LibraryRepository(api),
      );

      await controller.refresh();
      downloadsFail = true;
      await controller.refresh();

      expect(controller.state.playlists.single.id, 'one');
      expect(controller.state.downloads, isEmpty);
      expect(controller.state.stale, isTrue);
      expect(controller.state.error, isNotNull);
    },
  );

  test(
    'dashboard maps valid playback history and ignores malformed entries',
    () async {
      final paths = <String>[];
      final api = ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/api/v1/playback/history') {
            return data([
              {
                'track': {
                  'id': 'history-1',
                  'name': 'Night Wind',
                  'singer': 'Artist',
                  'source': 'kw',
                },
                'startedAt': 123,
              },
              {
                'track': {'id': 'broken', 'source': 'kw'},
              },
            ]);
          }
          return data(<Object?>[]);
        }),
      );
      final controller = HomeController(
        playlists: PlaylistRepository(api),
        downloads: DownloadRepository(api),
        library: LibraryRepository(api),
        history: PlaybackHistoryRepository(api, platform: 'other'),
      );

      await controller.refresh();

      expect(controller.state.error, isNull);
      expect(controller.state.continueListening.single.id, 'history-1');
      expect(controller.state.featured.single.id, 'history-1');
      expect(controller.state.lastSyncedAt, isNotNull);
      expect(paths, contains('/api/v1/playback/history'));
      expect(paths.where((path) => path.contains('client-data')), isEmpty);
    },
  );

  test(
    'dashboard keeps only the latest occurrence of each source track',
    () async {
      final api = ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/playback/history') {
            return data([
              {
                'track': {
                  'id': 'repeat',
                  'name': 'Newest metadata',
                  'singer': 'Artist',
                  'source': 'kw',
                },
                'startedAt': 400,
              },
              {
                'track': {
                  'id': 'other',
                  'name': 'Other',
                  'singer': 'Artist',
                  'source': 'kw',
                },
                'startedAt': 300,
              },
              {
                'track': {
                  'id': 'repeat',
                  'name': 'Older metadata',
                  'singer': 'Artist',
                  'source': 'kw',
                },
                'startedAt': 200,
              },
              {
                'track': {
                  'id': 'repeat',
                  'name': 'Different source',
                  'singer': 'Artist',
                  'source': 'qq',
                },
                'startedAt': 100,
              },
            ]);
          }
          return data(<Object?>[]);
        }),
      );
      final controller = HomeController(
        playlists: PlaylistRepository(api),
        downloads: DownloadRepository(api),
        library: LibraryRepository(api),
        history: PlaybackHistoryRepository(api, platform: 'other'),
      );

      await controller.refresh();

      expect(
        controller.state.continueListening.map(
          (track) => '${track.source}:${track.id}',
        ),
        ['kw:repeat', 'kw:other', 'qq:repeat'],
      );
      expect(controller.state.continueListening.first.title, 'Newest metadata');
    },
  );

  test(
    'dashboard restores local artwork missing from playback history',
    () async {
      final api = ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/playback/history') {
            return data([
              {
                'track': {
                  'id': 'local-track',
                  'name': 'History title',
                  'singer': 'History artist',
                  'source': 'local',
                },
                'startedAt': 123,
              },
            ]);
          }
          if (request.url.path == '/api/v1/library/tracks') {
            return data([
              {
                'id': 'local-track',
                'musicInfo': {
                  'id': 'local-track',
                  'name': 'Library title',
                  'singer': 'Library artist',
                  'source': 'local',
                },
                'size': 12,
                'extension': 'flac',
                'streamUrl': '/api/v1/library/tracks/local-track/stream',
                'pictureUrl': '/api/v1/library/tracks/local-track/picture',
              },
            ]);
          }
          return data(<Object?>[]);
        }),
      );
      final controller = HomeController(
        playlists: PlaylistRepository(api),
        downloads: DownloadRepository(api),
        library: LibraryRepository(api),
        history: PlaybackHistoryRepository(api, platform: 'other'),
      );

      await controller.refresh();

      expect(
        controller.state.continueListening.single.raw['pic'],
        'http://service.local/api/v1/library/tracks/local-track/picture',
      );
    },
  );
}
