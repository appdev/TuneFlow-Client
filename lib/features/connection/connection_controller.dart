import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/service_exception.dart';
import '../../api/service_origin.dart';
import '../../app/app_providers.dart';
import '../../storage/app_preferences.dart';
import '../../storage/app_settings_controller.dart';
import 'connection_repository.dart';
import 'endpoint_selector.dart';
import 'network_type_monitor.dart';
import 'server_endpoint_probe.dart';

final connectionProvider =
    AsyncNotifierProvider<ConnectionController, ConnectedService?>(
      ConnectionController.new,
    );

final class ConnectionController extends AsyncNotifier<ConnectedService?> {
  static const _networkDebounce = Duration(milliseconds: 150);

  StreamSubscription<Set<NetworkTransport>>? _networkSubscription;
  Timer? _debounceTimer;
  Set<NetworkTransport>? _lastTransports;
  NetworkRoute _route = NetworkRoute.offline;
  var _generation = 0;

  @override
  Future<ConnectedService?> build() async {
    ref.onDispose(() {
      _generation++;
      _debounceTimer?.cancel();
      unawaited(_networkSubscription?.cancel());
    });
    final settings = await ref.read(appPreferencesProvider).read();
    final catalog = _catalogFrom(settings);
    final monitor = ref.read(networkTypeMonitorProvider);
    _networkSubscription = monitor.changes.listen(handleNetworkChange);
    if (catalog.bootstrapOrigin == null &&
        catalog.lastConnectedOrigin == null &&
        catalog.lanOrigin == null &&
        catalog.externalOrigin == null) {
      return null;
    }
    final transports = _normalizeTransports(await monitor.current());
    _lastTransports = transports;
    _route = classifyNetwork(transports);

    if (_route == NetworkRoute.offline) return null;

    Object? lastFailure;
    StackTrace? lastStackTrace;
    final lastConnected = catalog.lastConnectedOrigin;
    if (lastConnected != null) {
      try {
        final health = await ref
            .read(serverEndpointProbeProvider)
            .probe(lastConnected.uri.toString());
        final connected = await ref
            .read(connectionRepositoryProvider)
            .connectProbed(health);
        final refreshed = catalog.withHealth(health);
        await _persistEndpoints(refreshed, health.origin);
        final restored = _withDiagnostics(
          connected,
          health,
          _route,
          refreshed.roleOf(health.origin, _route),
        );
        _debounceTimer = Timer(
          Duration.zero,
          () => unawaited(_reevaluate(_route)),
        );
        return restored;
      } on Object catch (error, stackTrace) {
        lastFailure = error;
        lastStackTrace = stackTrace;
      }
    }

    final selection = await ref
        .read(endpointSelectionServiceProvider)
        .select(
          catalog: catalog,
          route: _route,
          generationIsCurrent: () => true,
        );
    if (selection != null) {
      await _persistEndpoints(selection.catalog, selection.health.origin);
      return _withDiagnostics(
        selection.connected,
        selection.health,
        _route,
        selection.role,
      );
    }
    if (catalog.candidates(_route).isNotEmpty || lastConnected != null) {
      Error.throwWithStackTrace(
        lastFailure ??
            const ServiceException(
              'NETWORK_ERROR',
              'Unable to reach any configured Service address.',
            ),
        lastStackTrace ?? StackTrace.current,
      );
    }
    return null;
  }

  Future<void> connect(String value) async {
    final previous = state.value;
    final generation = ++_generation;
    _debounceTimer?.cancel();
    if (previous == null) state = const AsyncLoading();
    try {
      final bootstrap = ServiceOrigin.parse(value);
      final settings = await ref.read(appPreferencesProvider).read();
      var route = _route;
      if (route == NetworkRoute.offline) {
        final transports = _normalizeTransports(
          await ref.read(networkTypeMonitorProvider).current(),
        );
        route = classifyNetwork(transports);
        _lastTransports = transports;
        _route = route;
      }
      final selection = await ref
          .read(endpointSelectionServiceProvider)
          .select(
            catalog: _catalogFrom(settings, bootstrapOrigin: bootstrap),
            route: route,
            generationIsCurrent: () => generation == _generation,
          );
      if (selection == null) {
        throw const ServiceException(
          'NETWORK_ERROR',
          'Unable to reach any configured Service address.',
        );
      }
      await _persistEndpoints(selection.catalog, selection.health.origin);
      previous?.api.close();
      state = AsyncData(
        _withDiagnostics(
          selection.connected,
          selection.health,
          route,
          selection.role,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (previous == null) {
        state = AsyncError(error, stackTrace);
      } else {
        state = AsyncData(previous);
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  Future<void> applyEndpoints({
    required String bootstrapOrigin,
    required String lanOrigin,
    required String externalOrigin,
  }) async {
    final current = state.value;
    if (current == null) {
      throw const ServiceException(
        'NETWORK_ERROR',
        'A live Service connection is required to update endpoints.',
      );
    }
    final generation = ++_generation;
    _debounceTimer?.cancel();
    final previousSettings = await ref.read(appPreferencesProvider).read();
    ServiceOrigin? optional(String value) =>
        value.isEmpty ? null : ServiceOrigin.parse(value);
    final catalog = EndpointCatalog(
      bootstrapOrigin: ServiceOrigin.parse(bootstrapOrigin),
      lastConnectedOrigin: current.origin,
      lanOrigin: optional(lanOrigin),
      externalOrigin: optional(externalOrigin),
    );
    var route = _route;
    if (route == NetworkRoute.offline) {
      final transports = _normalizeTransports(
        await ref.read(networkTypeMonitorProvider).current(),
      );
      route = classifyNetwork(transports);
      _lastTransports = transports;
      _route = route;
    }
    final selection = await ref
        .read(endpointSelectionServiceProvider)
        .select(
          catalog: catalog,
          route: route,
          generationIsCurrent: () => generation == _generation,
        );
    if (selection == null) {
      throw const ServiceException(
        'NETWORK_ERROR',
        'Unable to reach any configured Service address.',
      );
    }
    final stableApi = current.api;
    if (!identical(stableApi, selection.connected.api)) {
      selection.connected.api.close();
    }
    try {
      await _persistEndpoints(selection.catalog, selection.health.origin);
    } on Object {
      try {
        await ref
            .read(appSettingsProvider.notifier)
            .saveSettings(previousSettings);
      } on Object {
        // Preserve the original persistence failure.
      }
      rethrow;
    }
    stableApi.switchOrigin(selection.health.origin);
    state = AsyncData(
      current.copyWith(
        capabilities: selection.connected.capabilities,
        diagnostics: ConnectionDiagnostics(
          origin: selection.health.origin.uri.toString(),
          connected: true,
          latency: selection.health.latency,
          apiVersion: selection.connected.capabilities.apiVersion,
          networkRoute: route,
          endpointRole: selection.role,
          checkedAt: DateTime.now(),
        ),
      ),
    );
  }

  void handleNetworkChange(Set<NetworkTransport> transports) {
    final normalized = _normalizeTransports(transports);
    if (_lastTransports != null && setEquals(_lastTransports, normalized)) {
      return;
    }
    _lastTransports = normalized;
    _route = classifyNetwork(normalized);
    _generation++;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      _networkDebounce,
      () => unawaited(_reevaluate(_route)),
    );
  }

  Future<void> disconnect() async {
    _generation++;
    _debounceTimer?.cancel();
    state.value?.api.close();
    await ref
        .read(appSettingsProvider.notifier)
        .setServiceEndpoints(
          bootstrapOrigin: null,
          lastConnectedOrigin: null,
          lanOrigin: null,
          externalOrigin: null,
        );
    state = const AsyncData(null);
  }

  Future<void> _reevaluate(NetworkRoute route) async {
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null) return;
    final generation = ++_generation;
    final settings = await ref.read(appPreferencesProvider).read();
    if (!ref.mounted || generation != _generation) return;
    EndpointSelection? selection;
    try {
      selection = await ref
          .read(endpointSelectionServiceProvider)
          .select(
            catalog: _catalogFrom(settings),
            route: route,
            generationIsCurrent: () => generation == _generation,
          );
    } on Object {
      selection = null;
    }
    if (!ref.mounted || generation != _generation) {
      selection?.connected.api.close();
      return;
    }
    if (selection == null) {
      state = AsyncData(
        current.copyWith(
          diagnostics: ConnectionDiagnostics(
            origin: current.origin.uri.toString(),
            connected: false,
            latency: null,
            apiVersion: null,
            networkRoute: route,
            endpointRole:
                current.diagnostics?.endpointRole ?? EndpointRole.bootstrap,
            checkedAt: DateTime.now(),
          ),
        ),
      );
      return;
    }

    final stableApi = current.api;
    if (!identical(stableApi, selection.connected.api)) {
      selection.connected.api.close();
    }
    stableApi.switchOrigin(selection.health.origin);
    state = AsyncData(
      current.copyWith(
        capabilities: selection.connected.capabilities,
        diagnostics: ConnectionDiagnostics(
          origin: selection.health.origin.uri.toString(),
          connected: true,
          latency: selection.health.latency,
          apiVersion: selection.connected.capabilities.apiVersion,
          networkRoute: route,
          endpointRole: selection.role,
          checkedAt: DateTime.now(),
        ),
      ),
    );
    try {
      await _persistEndpoints(selection.catalog, selection.health.origin);
    } on Object {
      // Keep the verified live endpoint active if local persistence fails.
    }
  }

  ConnectedService _withDiagnostics(
    ConnectedService connected,
    HealthSnapshot health,
    NetworkRoute route,
    EndpointRole role,
  ) {
    return connected.copyWith(
      diagnostics: ConnectionDiagnostics(
        origin: health.origin.uri.toString(),
        connected: true,
        latency: health.latency,
        apiVersion: connected.capabilities.apiVersion,
        networkRoute: route,
        endpointRole: role,
        checkedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _persistEndpoints(
    EndpointCatalog catalog,
    ServiceOrigin active,
  ) {
    return ref
        .read(appSettingsProvider.notifier)
        .setServiceEndpoints(
          bootstrapOrigin: catalog.bootstrapOrigin?.uri.toString(),
          lastConnectedOrigin: active.uri.toString(),
          lanOrigin: catalog.lanOrigin?.uri.toString(),
          externalOrigin: catalog.externalOrigin?.uri.toString(),
        );
  }

  static EndpointCatalog _catalogFrom(
    AppSettings settings, {
    ServiceOrigin? bootstrapOrigin,
  }) {
    return EndpointCatalog(
      bootstrapOrigin: bootstrapOrigin ?? _tryOrigin(settings.origin),
      lastConnectedOrigin: _tryOrigin(settings.lastConnectedOrigin),
      lanOrigin: _tryOrigin(settings.lanOrigin),
      externalOrigin: _tryOrigin(settings.externalOrigin),
    );
  }

  static ServiceOrigin? _tryOrigin(String? value) {
    if (value == null) return null;
    try {
      return ServiceOrigin.parse(value);
    } on ServiceException {
      return null;
    }
  }

  static Set<NetworkTransport> _normalizeTransports(
    Set<NetworkTransport> transports,
  ) {
    final normalized = {...transports};
    if (normalized.length > 1) normalized.remove(NetworkTransport.none);
    return Set.unmodifiable(normalized);
  }
}
