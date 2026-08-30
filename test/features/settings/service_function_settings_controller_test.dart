import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/settings/service_function_settings_controller.dart';
import 'package:musicfree_service_client/features/settings/service_settings_repository.dart';

Map<String, Object?> settingsJson() => {
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

http.Response data(Object? value) => http.Response.bytes(
  utf8.encode(jsonEncode({'data': value})),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('loads, edits, resets and saves an authoritative snapshot', () async {
    late Map<String, Object?> savedPatch;
    final repository = ServiceSettingsRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          if (request.method == 'GET') return data(settingsJson());
          savedPatch = Map<String, Object?>.from(
            jsonDecode(request.body) as Map,
          );
          return data(savedPatch);
        }),
      ),
    );
    final controller = ServiceFunctionSettingsController(repository);

    await controller.load();
    controller.update(controller.state.draft!.copyWith(maxConcurrent: 6));
    expect(controller.state.dirty, isTrue);
    controller.reset();
    expect(controller.state.dirty, isFalse);
    controller.update(
      controller.state.draft!.copyWith(
        maxConcurrent: 6,
        recommendationTimeZone: 'Asia/Shanghai',
      ),
    );

    expect(await controller.save(), isTrue);
    expect(savedPatch['download.maxDownloadNum'], 6);
    expect(savedPatch['recommendation.timeZone'], 'Asia/Shanghai');
    expect(controller.state.dirty, isFalse);
  });

  test('successful MusicBrainz test normalizes the editable draft', () async {
    final repository = ServiceSettingsRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          if (request.method == 'GET') return data(settingsJson());
          expect(request.url.path, '/api/v1/recommendations/musicbrainz/test');
          return data({
            'ok': true,
            'normalizedBaseUrl': 'https://mb.local/ws/2/',
            'errorCode': null,
          });
        }),
      ),
    );
    final controller = ServiceFunctionSettingsController(repository);
    await controller.load();

    final result = await controller.testMusicBrainzConnection(
      'https://mb.local/ws/2',
    );

    expect(result?.ok, isTrue);
    expect(
      controller.state.draft?.musicBrainzBaseUrl,
      'https://mb.local/ws/2/',
    );
    expect(controller.state.musicBrainzTest, same(result));
    expect(controller.state.dirty, isTrue);
  });
}
