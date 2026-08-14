import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/features/player/notification_artwork.dart';
import 'package:musicfree_service_client/features/player/player_state.dart';
import 'package:musicfree_service_client/features/player/service_audio_handler.dart';

import '../../support/fake_media_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cache files use a codec extension macOS can decode', () {
    expect(audioCacheExtension('128k'), '.mp3');
    expect(audioCacheExtension('320k'), '.mp3');
    expect(audioCacheExtension('flac'), '.flac');
    expect(audioCacheExtension('flac24bit'), '.flac');
  });

  test('silent audio port exposes a stable idle snapshot contract', () async {
    final audio = SilentAudioPort();
    final snapshot = await audio.snapshots.first;

    expect(snapshot.processing, PlayerProcessing.idle);
    expect(snapshot.playing, isFalse);
  });

  test('notification metadata uses the current track artwork', () {
    final track = Track.fromJson({
      'id': 'covered-song',
      'name': 'Covered song',
      'singer': 'Artist',
      'source': 'wy',
      'pic': 'https://example.test/current-cover.jpg',
    });

    final item = mediaItemForTrack(
      track,
      fallbackArtUri: Uri.file('/tmp/default-track-artwork.png'),
    );

    expect(item.artUri, Uri.parse('https://example.test/current-cover.jpg'));
    expect(item.artHeaders, containsPair('Referer', 'https://music.163.com/'));
  });

  test('notification metadata uses the placeholder for missing artwork', () {
    final track = Track.fromJson({
      'id': 'coverless-song',
      'name': 'Coverless song',
      'source': 'wy',
      'pic': '   ',
    });
    final placeholder = Uri.file('/tmp/default-track-artwork.png');

    final item = mediaItemForTrack(track, fallbackArtUri: placeholder);

    expect(item.artUri, placeholder);
    expect(item.artHeaders, isNull);
  });

  test(
    'notification placeholder is extracted to a readable local file',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tuneflow-notification-artwork-',
      );
      addTearDown(() => directory.delete(recursive: true));

      final uri = await prepareNotificationPlaceholderArtwork(
        supportDirectory: directory,
        assetBundle: _TestAssetBundle([0x89, 0x50, 0x4e, 0x47]),
      );

      expect(uri.scheme, 'file');
      expect(await File.fromUri(uri).readAsBytes(), [0x89, 0x50, 0x4e, 0x47]);
    },
  );

  test('missing cached audio releases its local cache lease', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tuneflow-audio-handler-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final cache = FakeMediaCache(
      audioFile: File('${directory.path}/missing.mp3'),
    );
    final handler = ServiceAudioHandler(
      fallbackArtUri: Uri.file('/tmp/default-track-artwork.png'),
      cache: cache,
    );
    addTearDown(handler.stop);
    final track = Track.fromJson({
      'id': 'song',
      'name': 'Song',
      'source': 'wy',
    });

    expect(await handler.playCachedTrack(track, '128k'), isFalse);

    expect(cache.audioRequests, ['wy:song:128k']);
    expect(cache.releasedLeases, 1);
  });
}

final class _TestAssetBundle extends CachingAssetBundle {
  _TestAssetBundle(this.bytes);

  final List<int> bytes;

  @override
  Future<ByteData> load(String key) async {
    expect(key, notificationPlaceholderAsset);
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}
