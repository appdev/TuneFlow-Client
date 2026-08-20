import '../../api/service_origin.dart';
import '../../api/service_exception.dart';
import 'connection_repository.dart';
import 'network_type_monitor.dart';
import 'server_endpoint_probe.dart';

final class EndpointCatalog {
  const EndpointCatalog({
    this.bootstrapOrigin,
    this.lastConnectedOrigin,
    this.lanOrigin,
    this.externalOrigin,
  });

  final ServiceOrigin? bootstrapOrigin;
  final ServiceOrigin? lastConnectedOrigin;
  final ServiceOrigin? lanOrigin;
  final ServiceOrigin? externalOrigin;

  List<(EndpointRole, ServiceOrigin?)> _ordered(NetworkRoute route) =>
      switch (route) {
        NetworkRoute.lan => [
          (EndpointRole.lan, lanOrigin),
          (EndpointRole.external, externalOrigin),
          (EndpointRole.bootstrap, bootstrapOrigin),
        ],
        NetworkRoute.external => [
          (EndpointRole.external, externalOrigin),
          (EndpointRole.bootstrap, bootstrapOrigin),
        ],
        NetworkRoute.offline => const <(EndpointRole, ServiceOrigin?)>[],
      };

  List<ServiceOrigin> candidates(NetworkRoute route) {
    final seen = <String>{};
    return [
      for (final (_, candidate) in _ordered(route))
        if (candidate != null && seen.add(candidate.uri.toString())) candidate,
    ];
  }

  EndpointRole roleOf(ServiceOrigin origin, NetworkRoute route) {
    final value = origin.uri.toString();
    for (final (role, candidate) in _ordered(route)) {
      if (candidate?.uri.toString() == value) return role;
    }
    return EndpointRole.bootstrap;
  }

  EndpointCatalog withHealth(HealthSnapshot health) {
    return EndpointCatalog(
      bootstrapOrigin: bootstrapOrigin,
      lastConnectedOrigin: lastConnectedOrigin,
      lanOrigin: health.lanOrigin ?? lanOrigin,
      externalOrigin: health.externalOrigin ?? externalOrigin,
    );
  }
}

final class EndpointSelection {
  const EndpointSelection({
    required this.connected,
    required this.health,
    required this.catalog,
    required this.role,
  });

  final ConnectedService connected;
  final HealthSnapshot health;
  final EndpointCatalog catalog;
  final EndpointRole role;
}

final class EndpointSelectionService {
  const EndpointSelectionService({
    required ServerEndpointProbe probe,
    required ConnectionRepository connections,
  }) : _probe = probe,
       _connections = connections;

  static const maxVisitedOrigins = 8;

  final ServerEndpointProbe _probe;
  final ConnectionRepository _connections;

  Future<EndpointSelection?> select({
    required EndpointCatalog catalog,
    required NetworkRoute route,
    required bool Function() generationIsCurrent,
  }) async {
    if (route == NetworkRoute.offline || !generationIsCurrent()) return null;

    var workingCatalog = catalog;
    final visited = <String>{};

    Future<EndpointSelection?> evaluate(ServiceOrigin candidate) async {
      if (!generationIsCurrent() ||
          visited.length >= maxVisitedOrigins ||
          !visited.add(candidate.uri.toString())) {
        return null;
      }

      late final HealthSnapshot health;
      try {
        health = await _probe.probe(
          candidate.uri.toString(),
          cancelled: () => !generationIsCurrent(),
        );
      } on ProbeCancelledException {
        return null;
      } on ServiceException catch (error) {
        if (error.code == 'UNSUPPORTED_API_VERSION') rethrow;
        return null;
      } on Object {
        return null;
      }
      if (!generationIsCurrent()) return null;

      workingCatalog = workingCatalog.withHealth(health);
      final preferred = workingCatalog.candidates(route);
      final currentIndex = preferred.indexWhere(
        (item) => item.uri.toString() == candidate.uri.toString(),
      );
      final higherPriority = currentIndex < 0
          ? preferred
          : preferred.take(currentIndex);
      for (final promoted in higherPriority) {
        final selection = await evaluate(promoted);
        if (selection != null) return selection;
        if (!generationIsCurrent()) return null;
      }

      try {
        final connected = await _connections.connectProbed(health);
        if (!generationIsCurrent()) {
          connected.api.close();
          return null;
        }
        return EndpointSelection(
          connected: connected,
          health: health,
          catalog: workingCatalog,
          role: workingCatalog.roleOf(health.origin, route),
        );
      } on ServiceException catch (error) {
        if (error.code == 'UNSUPPORTED_API_VERSION') rethrow;
        return null;
      } on Object {
        return null;
      }
    }

    while (generationIsCurrent() && visited.length < maxVisitedOrigins) {
      ServiceOrigin? next;
      for (final candidate in workingCatalog.candidates(route)) {
        if (!visited.contains(candidate.uri.toString())) {
          next = candidate;
          break;
        }
      }
      if (next == null) return null;
      final selection = await evaluate(next);
      if (selection != null) return selection;
    }
    return null;
  }
}
