import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CI builds five downloadable client artifacts with approved signing', () {
    final workflow = File(
      '.github/workflows/build-clients.yml',
    ).readAsStringSync();
    final androidBuild = File('android/app/build.gradle.kts').readAsStringSync();
    final linuxRunnerBuild = File(
      'linux/runner/CMakeLists.txt',
    ).readAsStringSync();

    expect(workflow, contains('flutter build apk --release'));
    expect(workflow, isNot(contains('flutter build appbundle')));
    expect(workflow, contains('ANDROID_KEYSTORE_BASE64'));
    expect(workflow, contains('flutter build ios --release --no-codesign'));
    expect(workflow, contains('CODE_SIGNING_ALLOWED=NO'));
    expect(
      'codesign --remove-signature'.allMatches(workflow),
      hasLength(2),
    );
    expect(
      'Verify Apple binaries are unsigned'.allMatches(workflow),
      hasLength(2),
    );
    expect(workflow, contains('runs-on: windows-2022'));
    expect(workflow, contains('flutter build windows --release'));
    expect(workflow, contains('runs-on: ubuntu-22.04'));
    expect(workflow, contains('flutter build linux --release'));
    expect('uses: actions/upload-artifact@v4'.allMatches(workflow), hasLength(5));
    expect(androidBuild, contains('signingConfigs'));
    expect(androidBuild, contains('key.properties'));
    expect(androidBuild, isNot(contains('getByName("debug")')));
    expect(
      linuxRunnerBuild,
      contains(r'"--sourcedir=${CMAKE_CURRENT_SOURCE_DIR}/resources"'),
    );
    expect(
      linuxRunnerBuild,
      contains(r'"--target=${TUNEFLOW_RESOURCE_SOURCE}"'),
    );
  });
}
