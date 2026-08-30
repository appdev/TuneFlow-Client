import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/features/radio/radio_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test('defaults off and persists both values locally', () async {
    final preferences = RadioPreferences();
    expect(await preferences.readAutoContinuation(), isFalse);
    await preferences.writeAutoContinuation(true);
    expect(await RadioPreferences().readAutoContinuation(), isTrue);
    await preferences.writeAutoContinuation(false);
    expect(await RadioPreferences().readAutoContinuation(), isFalse);
  });
}
