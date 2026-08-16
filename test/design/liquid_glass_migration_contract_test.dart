import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('third-party glass stays behind the shared design abstraction', () {
    final imports = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => file.readAsStringSync().contains(
            "package:liquid_glass_widgets/liquid_glass_widgets.dart",
          ),
        )
        .map((file) => file.path.replaceAll('\\', '/'))
        .toSet();

    expect(imports, {
      'lib/design/components/app_glass_surface.dart',
      'lib/main.dart',
    });
  });

  test('glass dependency is exactly pinned and has no call-site opt-out', () {
    final manifest = File('pubspec.yaml').readAsStringSync();
    expect(manifest, contains('liquid_glass_widgets: 0.29.6'));
    expect(manifest, isNot(contains('liquid_glass_widgets: ^')));

    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    expect(sources, isNot(contains('liquid: true')));
    expect(sources, isNot(contains('liquid: false')));
  });

  test('legacy backdrop filter remains confined to the fallback path', () {
    final matches = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.readAsStringSync().contains('BackdropFilter'))
        .map((file) => file.path.replaceAll('\\', '/'))
        .toSet();

    expect(matches, {'lib/design/components/app_glass_surface.dart'});
  });
}
