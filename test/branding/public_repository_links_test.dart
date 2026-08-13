import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

({int width, int height}) _pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  expect(bytes.length, greaterThanOrEqualTo(24));
  expect(
    bytes.sublist(0, 8),
    equals(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
  );

  final data = ByteData.sublistView(bytes);
  return (
    width: data.getUint32(16, Endian.big),
    height: data.getUint32(20, Endian.big),
  );
}

void main() {
  test('public README is product-first and contains only public links', () {
    final readme = File('README.md').readAsStringSync();
    final openApiTool = File('tool/verify_openapi.dart').readAsStringSync();
    final publishedText = '$readme\n$openApiTool';

    expect(publishedText, isNot(contains('/Volumes/')));
    expect(publishedText, isNot(contains('/Users/')));
    expect(readme, contains('TuneFlow · 音流'));
    expect(
      readme,
      contains(
        'https://github.com/appdev/TuneFlow-Client/actions/workflows/'
        'build-clients.yml',
      ),
    );
    expect(readme, contains('https://github.com/appdev/TuneFlow-Client'));
    expect(readme, contains('https://github.com/appdev/TuneFlow'));
    expect(
      readme,
      contains('docs/images/readme/tuneflow-desktop-home.png'),
    );
    expect(
      readme,
      contains('docs/images/readme/tuneflow-mobile-player.png'),
    );
    expect(
      readme,
      contains('docs/images/readme/tuneflow-mobile-library.png'),
    );

    for (final forbiddenText in <String>[
      '192.168.',
      '127.0.0.1',
      '/api/v1',
      'flowchart',
      'flutter test',
      'QQ',
      '网易',
      '酷我',
      '酷狗',
      '咪咕',
    ]) {
      expect(
        readme,
        isNot(contains(forbiddenText)),
        reason: 'README should not contain $forbiddenText',
      );
    }
  });

  test('README screenshots are stable product assets', () {
    expect(
      _pngSize('docs/images/readme/tuneflow-desktop-home.png'),
      (width: 1440, height: 960),
    );
    expect(
      _pngSize('docs/images/readme/tuneflow-mobile-player.png'),
      (width: 390, height: 844),
    );
    expect(
      _pngSize('docs/images/readme/tuneflow-mobile-library.png'),
      (width: 390, height: 844),
    );
  });
}
