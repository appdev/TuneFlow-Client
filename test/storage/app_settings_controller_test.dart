import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/app/app_providers.dart';
import 'package:musicfree_service_client/storage/app_preferences.dart';
import 'package:musicfree_service_client/storage/app_settings_controller.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('updates every endpoint role without changing UI preferences', () async {
    final preferences = SharedAppPreferences();
    await preferences.write(
      const AppSettings(themeMode: ThemeMode.dark, language: AppLanguage.zh),
    );
    final container = ProviderContainer(
      overrides: [appPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    await container.read(appSettingsProvider.future);

    await container
        .read(appSettingsProvider.notifier)
        .setServiceEndpoints(
          bootstrapOrigin: 'https://bootstrap.example',
          lastConnectedOrigin: 'http://192.168.1.20:3124',
          lanOrigin: 'http://192.168.1.20:3124',
          externalOrigin: 'https://music.example.com',
        );

    final settings = container.read(appSettingsProvider).requireValue;
    expect(settings.origin, 'https://bootstrap.example');
    expect(settings.lastConnectedOrigin, 'http://192.168.1.20:3124');
    expect(settings.lanOrigin, 'http://192.168.1.20:3124');
    expect(settings.externalOrigin, 'https://music.example.com');
    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.language, AppLanguage.zh);
    expect(await preferences.read(), settings);
  });
}
