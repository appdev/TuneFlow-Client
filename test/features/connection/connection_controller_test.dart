import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_exception.dart';
import 'package:musicfree_service_client/app/app_providers.dart';
import 'package:musicfree_service_client/app/player_providers.dart';
import 'package:musicfree_service_client/features/connection/connection_controller.dart';
import 'package:musicfree_service_client/features/connection/connection_repository.dart';
import 'package:musicfree_service_client/features/connection/network_type_monitor.dart';
import 'package:musicfree_service_client/features/connection/server_endpoint_probe.dart';
import 'package:musicfree_service_client/storage/app_preferences.dart';
import 'package:musicfree_service_client/storage/app_settings_controller.dart';

final class MemoryAppPreferences implements AppPreferences {
  AppSettings settings = const AppSettings();
  bool failWrites = false;

  @override
  Future<void> clearOrigin() async {
    settings = settings.copyWith(clearOrigin: true);
  }

  @override
  Future<AppSettings> read() async => settings;

  @override
  Future<void> write(AppSettings value) async {
    if (failWrites) throw StateError('write failed');
    settings = value;
  }
}

final class FakeNetworkTypeMonitor implements NetworkTypeMonitor {
  FakeNetworkTypeMonitor(this.transports);

  Set<NetworkTransport> transports;
  final controller = StreamController<Set<NetworkTransport>>.broadcast();
  var currentCalls = 0;

  @override
  Stream<Set<NetworkTransport>> get changes => controller.stream;

  @override
  Future<Set<NetworkTransport>> current() async {
    currentCalls++;
    return transports;
  }
}

Future<void> waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}

ConnectionRepository healthyRepository() => ConnectionRepository(
  (origin) => ServiceApi(
    origin,
    client: MockClient(
      (request) async => http.Response(
        jsonEncode({
          'data': request.url.path.endsWith('health')
              ? {'status': 'ok'}
              : {
                  'runtime': 'service',
                  'apiVersion': 'v1',
                  'features': <String, Object?>{},
                },
        }),
        200,
      ),
    ),
  ),
);

Future<HttpServer> healthyService() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'data': request.uri.path.endsWith('/health')
            ? {'status': 'ok'}
            : {
                'runtime': 'service',
                'apiVersion': 'v1',
                'features': <String, Object?>{},
              },
      }),
    );
    await request.response.close();
  });
  return server;
}

void main() {
  test('connection probe times out instead of loading forever', () async {
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient((request) => Completer<http.Response>().future),
      ),
      const Duration(milliseconds: 10),
    );

    await expectLater(
      repository.connect('http://service.local'),
      throwsA(
        isA<ServiceException>().having(
          (error) => error.code,
          'code',
          'CONNECTION_TIMEOUT',
        ),
      ),
    );
  });

  test('restores a persisted Service connection', () async {
    final preferences = MemoryAppPreferences()
      ..settings = const AppSettings(origin: 'http://service.local');
    final container = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        connectionRepositoryProvider.overrideWithValue(healthyRepository()),
      ],
    );
    addTearDown(container.dispose);

    final connected = await container.read(connectionProvider.future);

    expect(connected?.origin.uri.toString(), 'http://service.local');
  });

  test(
    'connect persists the normalized origin and disconnect preserves UI settings',
    () async {
      final preferences = MemoryAppPreferences()
        ..settings = const AppSettings(
          themeMode: ThemeMode.dark,
          language: AppLanguage.zh,
        );
      final container = ProviderContainer(
        overrides: [
          appPreferencesProvider.overrideWithValue(preferences),
          connectionRepositoryProvider.overrideWithValue(healthyRepository()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(connectionProvider.future);
      await container.read(appSettingsProvider.future);

      await container
          .read(connectionProvider.notifier)
          .connect('http://service.local/');
      expect(preferences.settings.origin, 'http://service.local');
      expect(
        container.read(appSettingsProvider).requireValue.origin,
        'http://service.local',
      );

      await container.read(connectionProvider.notifier).disconnect();
      expect(container.read(connectionProvider).value, isNull);
      expect(preferences.settings.origin, isNull);
      expect(preferences.settings.lastConnectedOrigin, isNull);
      expect(preferences.settings.lanOrigin, isNull);
      expect(preferences.settings.externalOrigin, isNull);
      expect(container.read(appSettingsProvider).requireValue.origin, isNull);
      expect(preferences.settings.themeMode, ThemeMode.dark);
      expect(preferences.settings.language, AppLanguage.zh);
    },
  );

  test('replacing the Service closes the previous API client', () async {
    final first = await healthyService();
    final second = await healthyService();
    addTearDown(() => first.close(force: true));
    addTearDown(() => second.close(force: true));
    final preferences = MemoryAppPreferences();
    final container = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        connectionRepositoryProvider.overrideWithValue(ConnectionRepository()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(connectionProvider.future);

    String origin(HttpServer server) =>
        'http://${server.address.address}:${server.port}';
    await container.read(connectionProvider.notifier).connect(origin(first));
    final previousApi = container.read(connectionProvider).requireValue!.api;

    await container.read(connectionProvider.notifier).connect(origin(second));

    await expectLater(
      previousApi.request('GET', '/api/v1/health'),
      throwsA(
        isA<ServiceException>().having(
          (error) => error.code,
          'code',
          'NETWORK_ERROR',
        ),
      ),
    );
  });

  test('cold start restores last origin before preferring LAN', () async {
    final preferences = MemoryAppPreferences()
      ..settings = const AppSettings(
        origin: 'https://bootstrap.example',
        lastConnectedOrigin: 'https://external.example',
        lanOrigin: 'http://lan.local',
        externalOrigin: 'https://external.example',
      );
    final monitor = FakeNetworkTypeMonitor({NetworkTransport.wifi});
    final calls = <String>[];
    final probe = ServerEndpointProbe(
      requestHealth: (origin) async {
        calls.add(origin.uri.toString());
        return {'status': 'ok'};
      },
      delay: (_) async {},
    );
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'runtime': 'service',
                'apiVersion': 'v1',
                'features': <String, Object?>{},
              },
            }),
            200,
          ),
        ),
      ),
      const Duration(seconds: 3),
      probe,
    );
    final container = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        networkTypeMonitorProvider.overrideWithValue(monitor),
        connectionRepositoryProvider.overrideWithValue(repository),
        serverEndpointProbeProvider.overrideWithValue(probe),
      ],
    );
    addTearDown(container.dispose);

    final restored = await container.read(connectionProvider.future);
    final initialOrigin = restored?.origin.uri.toString();
    final stableApi = restored?.api;
    await waitUntil(
      () =>
          container.read(connectionProvider).value?.origin.uri.toString() ==
          'http://lan.local',
    );

    expect(initialOrigin, 'https://external.example');
    expect(calls.take(2), ['https://external.example', 'http://lan.local']);
    expect(container.read(connectionProvider).value?.api, same(stableApi));
    expect(preferences.settings.lastConnectedOrigin, 'http://lan.local');
  });

  test('automatic failure preserves API and marks it unreachable', () async {
    var fail = false;
    final preferences = MemoryAppPreferences()
      ..settings = const AppSettings(
        origin: 'https://external.example',
        lastConnectedOrigin: 'https://external.example',
        externalOrigin: 'https://external.example',
      );
    final monitor = FakeNetworkTypeMonitor({NetworkTransport.mobile});
    final probe = ServerEndpointProbe(
      requestHealth: (_) async {
        if (fail) throw const ServiceException('NETWORK_ERROR', 'down');
        return {'status': 'ok'};
      },
      delay: (_) async {},
    );
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'runtime': 'service',
                'apiVersion': 'v1',
                'features': <String, Object?>{},
              },
            }),
            200,
          ),
        ),
      ),
      const Duration(seconds: 3),
      probe,
    );
    final container = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        networkTypeMonitorProvider.overrideWithValue(monitor),
        connectionRepositoryProvider.overrideWithValue(repository),
        serverEndpointProbeProvider.overrideWithValue(probe),
      ],
    );
    addTearDown(container.dispose);
    final connected = await container.read(connectionProvider.future);
    final stableApi = connected?.api;
    fail = true;

    container.read(connectionProvider.notifier).handleNetworkChange({
      NetworkTransport.wifi,
    });
    await waitUntil(
      () =>
          container.read(connectionProvider).value?.diagnostics?.connected ==
          false,
    );

    final current = container.read(connectionProvider).value;
    expect(current?.api, same(stableApi));
    expect(current?.diagnostics?.connected, isFalse);
  });

  test('manual failure preserves all persisted endpoint roles', () async {
    const original = AppSettings(
      origin: 'https://bootstrap.example',
      lastConnectedOrigin: 'https://last.example',
      lanOrigin: 'http://lan.local',
      externalOrigin: 'https://external.example',
    );
    final preferences = MemoryAppPreferences()..settings = original;
    final monitor = FakeNetworkTypeMonitor({NetworkTransport.mobile});
    final probe = ServerEndpointProbe(
      requestHealth: (_) async =>
          throw const ServiceException('NETWORK_ERROR', 'down'),
      delay: (_) async {},
    );
    final repository = ConnectionRepository(null, null, probe);
    final container = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        networkTypeMonitorProvider.overrideWithValue(monitor),
        connectionRepositoryProvider.overrideWithValue(repository),
        serverEndpointProbeProvider.overrideWithValue(probe),
      ],
    );
    addTearDown(container.dispose);
    await waitUntil(() => container.read(connectionProvider).hasError);

    await container
        .read(connectionProvider.notifier)
        .connect('https://new.example');

    expect(preferences.settings, original);
  });

  test('automatic origin switch retains the player controller', () async {
    final preferences = MemoryAppPreferences()
      ..settings = const AppSettings(
        origin: 'https://bootstrap.example',
        lastConnectedOrigin: 'https://external.example',
        lanOrigin: 'http://lan.local',
        externalOrigin: 'https://external.example',
      );
    final monitor = FakeNetworkTypeMonitor({NetworkTransport.mobile});
    final probe = ServerEndpointProbe(
      requestHealth: (_) async => {'status': 'ok'},
      delay: (_) async {},
    );
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'runtime': 'service',
                'apiVersion': 'v1',
                'features': <String, Object?>{},
              },
            }),
            200,
          ),
        ),
      ),
      const Duration(seconds: 3),
      probe,
    );
    final container = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        networkTypeMonitorProvider.overrideWithValue(monitor),
        connectionRepositoryProvider.overrideWithValue(repository),
        serverEndpointProbeProvider.overrideWithValue(probe),
      ],
    );
    addTearDown(container.dispose);
    await container.read(connectionProvider.future);
    final before = container.read(playerControllerProvider);

    monitor.transports = {NetworkTransport.wifi};
    container.read(connectionProvider.notifier).handleNetworkChange({
      NetworkTransport.wifi,
    });
    await waitUntil(
      () =>
          container.read(connectionProvider).value?.origin.uri.toString() ==
          'http://lan.local',
    );

    expect(container.read(playerControllerProvider), same(before));
    expect(
      container.read(connectionProvider).value?.origin.uri.toString(),
      'http://lan.local',
    );
  });

  test('endpoint persistence failure preserves the live API origin', () async {
    final preferences = MemoryAppPreferences()
      ..settings = const AppSettings(
        origin: 'https://bootstrap.example',
        lastConnectedOrigin: 'https://old.example',
        externalOrigin: 'https://old.example',
      );
    final monitor = FakeNetworkTypeMonitor({NetworkTransport.mobile});
    final probe = ServerEndpointProbe(
      requestHealth: (_) async => {'status': 'ok'},
      delay: (_) async {},
    );
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'runtime': 'service',
                'apiVersion': 'v1',
                'features': <String, Object?>{},
              },
            }),
            200,
          ),
        ),
      ),
      const Duration(seconds: 3),
      probe,
    );
    final container = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        networkTypeMonitorProvider.overrideWithValue(monitor),
        connectionRepositoryProvider.overrideWithValue(repository),
        serverEndpointProbeProvider.overrideWithValue(probe),
      ],
    );
    addTearDown(container.dispose);
    final connected = await container.read(connectionProvider.future);
    final api = connected!.api;
    preferences.failWrites = true;

    await expectLater(
      container
          .read(connectionProvider.notifier)
          .applyEndpoints(
            bootstrapOrigin: 'https://bootstrap.example',
            lanOrigin: '',
            externalOrigin: 'https://new.example',
          ),
      throwsStateError,
    );

    expect(api.origin.uri.toString(), 'https://old.example');
    expect(container.read(connectionProvider).requireValue!.api, same(api));
    expect(
      container.read(connectionProvider).requireValue!.origin.uri.toString(),
      'https://old.example',
    );
  });

  test('connected manual failure never publishes loading state', () async {
    var failNew = false;
    final preferences = MemoryAppPreferences()
      ..settings = const AppSettings(origin: 'https://old.example');
    final monitor = FakeNetworkTypeMonitor({NetworkTransport.mobile});
    final probe = ServerEndpointProbe(
      requestHealth: (origin) async {
        if (failNew && origin.uri.host == 'new.example') {
          throw const ServiceException('NETWORK_ERROR', 'down');
        }
        return {'status': 'ok'};
      },
      delay: (_) async {},
    );
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'runtime': 'service',
                'apiVersion': 'v1',
                'features': <String, Object?>{},
              },
            }),
            200,
          ),
        ),
      ),
      const Duration(seconds: 3),
      probe,
    );
    final container = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        networkTypeMonitorProvider.overrideWithValue(monitor),
        connectionRepositoryProvider.overrideWithValue(repository),
        serverEndpointProbeProvider.overrideWithValue(probe),
      ],
    );
    addTearDown(container.dispose);
    await container.read(connectionProvider.future);
    final states = <AsyncValue<ConnectedService?>>[];
    final subscription = container.listen(
      connectionProvider,
      (_, next) => states.add(next),
    );
    addTearDown(subscription.close);
    failNew = true;

    await expectLater(
      container
          .read(connectionProvider.notifier)
          .connect('https://new.example'),
      throwsA(isA<ServiceException>()),
    );

    expect(states.where((value) => value.isLoading), isEmpty);
    expect(
      container.read(connectionProvider).requireValue!.origin.uri.toString(),
      'https://old.example',
    );
  });

  test('an obsolete network generation cannot commit', () async {
    final preferences = MemoryAppPreferences()
      ..settings = const AppSettings(
        origin: 'https://bootstrap.example',
        lastConnectedOrigin: 'https://external.example',
        lanOrigin: 'http://lan.local',
        externalOrigin: 'https://external.example',
      );
    final monitor = FakeNetworkTypeMonitor({NetworkTransport.mobile});
    final lanHealth = Completer<Object?>();
    final calls = <String>[];
    final probe = ServerEndpointProbe(
      requestHealth: (origin) {
        final value = origin.uri.toString();
        calls.add(value);
        if (value == 'http://lan.local') return lanHealth.future;
        return Future.value({'status': 'ok'});
      },
      delay: (_) async {},
    );
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'runtime': 'service',
                'apiVersion': 'v1',
                'features': <String, Object?>{},
              },
            }),
            200,
          ),
        ),
      ),
      const Duration(seconds: 3),
      probe,
    );
    final container = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        networkTypeMonitorProvider.overrideWithValue(monitor),
        connectionRepositoryProvider.overrideWithValue(repository),
        serverEndpointProbeProvider.overrideWithValue(probe),
      ],
    );
    addTearDown(container.dispose);
    await container.read(connectionProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    calls.clear();

    container.read(connectionProvider.notifier).handleNetworkChange({
      NetworkTransport.wifi,
    });
    await waitUntil(() => calls.contains('http://lan.local'));
    container.read(connectionProvider.notifier).handleNetworkChange({
      NetworkTransport.mobile,
    });
    await waitUntil(() => calls.contains('https://external.example'));
    lanHealth.complete({'status': 'ok'});
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      container.read(connectionProvider).value?.origin.uri.toString(),
      'https://external.example',
    );
  });

  test('manual server replacement creates a new player controller', () async {
    final preferences = MemoryAppPreferences();
    final monitor = FakeNetworkTypeMonitor({NetworkTransport.mobile});
    final probe = ServerEndpointProbe(
      requestHealth: (_) async => {'status': 'ok'},
      delay: (_) async {},
    );
    final repository = ConnectionRepository(
      (origin) => ServiceApi(
        origin,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'runtime': 'service',
                'apiVersion': 'v1',
                'features': <String, Object?>{},
              },
            }),
            200,
          ),
        ),
      ),
      const Duration(seconds: 3),
      probe,
    );
    final container = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        networkTypeMonitorProvider.overrideWithValue(monitor),
        connectionRepositoryProvider.overrideWithValue(repository),
        serverEndpointProbeProvider.overrideWithValue(probe),
      ],
    );
    addTearDown(container.dispose);
    await container.read(connectionProvider.future);
    await container
        .read(connectionProvider.notifier)
        .connect('https://first.example');
    final before = container.read(playerControllerProvider);

    await container
        .read(connectionProvider.notifier)
        .connect('https://second.example');

    expect(container.read(playerControllerProvider), isNot(same(before)));
  });
}
