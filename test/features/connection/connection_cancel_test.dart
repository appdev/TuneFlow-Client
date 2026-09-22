import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/app/app_providers.dart';
import 'package:musicfree_service_client/features/connection/connection_controller.dart';
import 'package:musicfree_service_client/features/connection/connection_repository.dart';
import 'package:musicfree_service_client/features/connection/network_type_monitor.dart';
import 'package:musicfree_service_client/storage/app_settings_controller.dart';
import 'connection_controller_test.dart'
    show MemoryAppPreferences, FakeNetworkTypeMonitor;

void main() {
  test(
    'cancelled manual connection cannot persist or publish a late result',
    () async {
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      final preferences = MemoryAppPreferences();
      final monitor = FakeNetworkTypeMonitor({NetworkTransport.wifi});
      final repository = ConnectionRepository(
        (origin) => ServiceApi(
          origin,
          client: MockClient((request) async {
            if (request.url.path.endsWith('health')) {
              if (!started.isCompleted) started.complete();
              return pending.future;
            }
            return http.Response(
              jsonEncode({
                'data': {
                  'apiVersion': 'v1',
                  'runtime': 'service',
                  'features': {},
                },
              }),
              200,
            );
          }),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          appPreferencesProvider.overrideWithValue(preferences),
          networkTypeMonitorProvider.overrideWithValue(monitor),
          connectionRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(monitor.controller.close);
      await container.read(connectionProvider.future);
      await container.read(appSettingsProvider.future);
      final connection = container.read(connectionProvider.notifier);
      final attempt = connection.connect('http://service.local');
      await started.future;
      connection.cancelConnection();
      pending.complete(
        http.Response(
          jsonEncode({
            'data': {'status': 'ok'},
          }),
          200,
        ),
      );
      await attempt;
      expect(container.read(connectionProvider).value, isNull);
      expect(container.read(connectionProvider).isLoading, isFalse);
      expect(preferences.settings.origin, isNull);
    },
  );
}
