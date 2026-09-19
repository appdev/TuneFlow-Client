import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_exception.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/settings/service_settings_repository.dart';

http.Response data(Object? value) => http.Response.bytes(
  utf8.encode(jsonEncode({'data': value})),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

ServiceSettingsRepository repositoryFor(
  Future<http.Response> Function(http.Request request) handler,
) => ServiceSettingsRepository(
  ServiceApi(
    ServiceOrigin.parse('http://service.local'),
    client: MockClient(handler),
  ),
);

void main() {
  test('round trips the complete Service function settings contract', () async {
    final initial = <String, Object?>{
      'player.autoDownloadOnPlay': false,
      'download.enable': true,
      'download.isSavePathGroupByListName': false,
      'download.fileName': '歌名 - 歌手',
      'download.maxDownloadNum': 3,
      'download.skipExistFile': true,
      'download.isUseOtherSource': true,
      'download.isDownloadLrc': true,
      'download.isDownloadTLrc': true,
      'download.isDownloadRLrc': true,
      'download.isDownloadVerbatimLyric': true,
      'download.lrcFormat': 'utf8',
      'download.isEmbedPic': true,
      'download.isEmbedLyric': true,
      'download.isEmbedLyricT': true,
      'download.isEmbedLyricR': true,
      'download.isEmbedVerbatimLyric': true,
      'recommendation.timeZone': 'system',
      'recommendation.musicBrainzBaseUrl': officialMusicBrainzBaseUrl,
    };
    late Map<String, Object?> patch;
    var patchRequests = 0;
    final repository = repositoryFor((request) async {
      if (request.method == 'GET') return data(initial);
      patchRequests++;
      patch = Map<String, Object?>.from(jsonDecode(request.body) as Map);
      return data({...initial, ...patch});
    });

    final loaded = await repository.getFunctionSettings();
    final updated = loaded.copyWith(
      maxConcurrent: 5,
      recommendationTimeZone: 'Asia/Shanghai',
    );
    final confirmed = await repository.updateFunctionSettings(updated, loaded);

    expect(patch, {
      'download.maxDownloadNum': 5,
      'recommendation.timeZone': 'Asia/Shanghai',
    });
    expect(confirmed, updated);
    expect(confirmed.maxConcurrent, 5);
    expect(confirmed.recommendationTimeZone, 'Asia/Shanghai');
    expect(confirmed.musicBrainzBaseUrl, officialMusicBrainzBaseUrl);

    expect(
      await repository.updateFunctionSettings(confirmed, confirmed),
      confirmed,
    );
    expect(patchRequests, 1);
  });

  test('preserves an explicitly empty MusicBrainz address', () async {
    final json = <String, Object?>{
      'player.autoDownloadOnPlay': false,
      'download.enable': true,
      'download.isSavePathGroupByListName': false,
      'download.fileName': '歌名 - 歌手',
      'download.maxDownloadNum': 3,
      'download.skipExistFile': true,
      'download.isUseOtherSource': true,
      'download.isDownloadLrc': true,
      'download.isDownloadTLrc': true,
      'download.isDownloadRLrc': true,
      'download.isDownloadVerbatimLyric': true,
      'download.lrcFormat': 'utf8',
      'download.isEmbedPic': true,
      'download.isEmbedLyric': true,
      'download.isEmbedLyricT': true,
      'download.isEmbedLyricR': true,
      'download.isEmbedVerbatimLyric': true,
      'recommendation.timeZone': 'system',
      'recommendation.musicBrainzBaseUrl': '',
    };
    final repository = repositoryFor((_) async => data(json));

    final loaded = await repository.getFunctionSettings();

    expect(loaded.musicBrainzBaseUrl, isEmpty);
    expect(loaded.toPatch()['recommendation.musicBrainzBaseUrl'], isEmpty);
  });

  test('tests a draft MusicBrainz endpoint without saving settings', () async {
    final repository = repositoryFor((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/recommendations/musicbrainz/test');
      expect(jsonDecode(request.body), {'baseUrl': 'https://mb.local/ws/2'});
      return data({
        'ok': true,
        'normalizedBaseUrl': 'https://mb.local/ws/2/',
        'errorCode': null,
      });
    });

    final result = await repository.testMusicBrainzConnection(
      'https://mb.local/ws/2',
    );

    expect(result.ok, isTrue);
    expect(result.normalizedBaseUrl, 'https://mb.local/ws/2/');
  });

  test('reads the Service auto-download setting', () async {
    final repository = repositoryFor((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/settings');
      return data({'player.autoDownloadOnPlay': true});
    });

    expect(await repository.getAutoDownloadOnPlay(), isTrue);
  });

  test('patches only the Service auto-download setting', () async {
    final repository = repositoryFor((request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/v1/settings');
      expect(jsonDecode(request.body), {'player.autoDownloadOnPlay': false});
      return data({'player.autoDownloadOnPlay': false});
    });

    expect(await repository.setAutoDownloadOnPlay(false), isFalse);
  });

  test('rejects a Service response missing the auto-download setting', () {
    final repository = repositoryFor((_) async => data({'player.volume': 1}));

    expect(
      repository.getAutoDownloadOnPlay(),
      throwsA(
        isA<ServiceException>().having(
          (error) => error.code,
          'code',
          'INVALID_RESPONSE',
        ),
      ),
    );
  });

  test('rejects a non-boolean auto-download setting', () {
    final repository = repositoryFor(
      (_) async => data({'player.autoDownloadOnPlay': 'true'}),
    );

    expect(
      repository.getAutoDownloadOnPlay(),
      throwsA(
        isA<ServiceException>().having(
          (error) => error.code,
          'code',
          'INVALID_RESPONSE',
        ),
      ),
    );
  });
}
