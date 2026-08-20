import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/features/more/app_update.dart';

void main() {
  group('AppVersion', () {
    test('parses release labels with optional v prefix and build', () {
      expect(AppVersion.parse('v1.2.3').label, '1.2.3');
      expect(AppVersion.parse('1.2.3+4').label, '1.2.3+4');
    });

    test('orders core versions before build numbers', () {
      expect(
        AppVersion.parse('v1.2.4').isNewerThan(AppVersion.parse('1.2.3+9')),
        isTrue,
      );
      expect(
        AppVersion.parse('1.2.3+5').isNewerThan(AppVersion.parse('1.2.3+4')),
        isTrue,
      );
    });

    test('missing candidate build does not create a same-core update', () {
      expect(
        AppVersion.parse('1.2.3').isNewerThan(AppVersion.parse('1.2.3+9')),
        isFalse,
      );
      expect(
        AppVersion.parse('1.2.3+5').isNewerThan(AppVersion.parse('1.2.3')),
        isTrue,
      );
    });

    test('combines package version and build without duplicating build', () {
      expect(
        AppVersion.fromPackage(version: '1.0.4', buildNumber: '5').label,
        '1.0.4+5',
      );
      expect(
        AppVersion.fromPackage(version: '1.0.4+6', buildNumber: '5').label,
        '1.0.4+6',
      );
    });

    test('rejects unsupported release labels', () {
      expect(() => AppVersion.parse('release-latest'), throwsFormatException);
    });
  });
}
