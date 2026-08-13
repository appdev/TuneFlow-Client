import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';

void main() {
  test('artwork source owns one provider for sharp and blurred consumers', () {
    final source = AppArtworkSource.network(
      'https://example.com/cover.jpg',
      fallbackSeed: 'source:track',
    );

    expect(source.provider, isNotNull);
    expect(identical(source.provider, source.provider), isTrue);
    expect(source.fallbackSeed, 'source:track');
  });

  test('missing artwork source retains its deterministic fallback seed', () {
    final source = AppArtworkSource.fromUrl(null, fallbackSeed: 'fallback');

    expect(source.provider, isNull);
    expect(source.fallbackSeed, 'fallback');
  });

  test('NetEase artwork replaces CDN nodes that reject Flutter requests', () {
    final source = AppArtworkSource.network(
      'https://p2.music.126.net/example.jpg',
      fallbackSeed: 'wy:track',
    );

    final provider = source.provider! as NetworkImage;
    expect(provider.url, 'https://p3.music.126.net/example.jpg');
    expect(provider.headers?['User-Agent'], startsWith('Mozilla/5.0'));
  });
}
