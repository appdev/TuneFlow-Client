import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter UI has one network-image loading path', () async {
    final violations = <String>[];
    await for (final entity in Directory('lib').list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = await entity.readAsString();
      for (final forbidden in <String, RegExp>{
        'Image.network(': RegExp(r'Image\.network\('),
        'NetworkImage(': RegExp(
          r'(^|[^A-Za-z])NetworkImage\(',
          multiLine: true,
        ),
        'CachedArtworkImage': RegExp(r'CachedArtworkImage'),
      }.entries) {
        if (forbidden.value.hasMatch(source)) {
          violations.add('${entity.path}: ${forbidden.key}');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
