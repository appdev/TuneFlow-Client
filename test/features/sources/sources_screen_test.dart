import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/features/sources/sources_screen.dart';

void main() {
  test('source version label never duplicates the v prefix', () {
    expect(sourceVersionLabel('1.2.0'), 'v1.2.0');
    expect(sourceVersionLabel('v1.2.0'), 'v1.2.0');
    expect(sourceVersionLabel('vv1.2.0'), 'v1.2.0');
    expect(sourceVersionLabel(''), '版本未知');
  });
}
