import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public documentation and tools do not expose local absolute paths', () {
    final readme = File('README.md').readAsStringSync();
    final openApiTool = File('tool/verify_openapi.dart').readAsStringSync();
    final publishedText = '$readme\n$openApiTool';

    expect(publishedText, isNot(contains('/Volumes/')));
    expect(publishedText, isNot(contains('/Users/')));
    expect(readme, contains('https://github.com/appdev/TuneFlow-Client'));
    expect(readme, contains('https://github.com/appdev/TuneFlow'));
  });
}
