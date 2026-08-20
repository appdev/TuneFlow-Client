import '../../api/models.dart';
import '../../api/service_api.dart';
import '../../api/service_exception.dart';
import '../../api/service_origin.dart';
import 'network_type_monitor.dart';
import 'server_endpoint_probe.dart';

enum EndpointRole { lan, external, bootstrap }

typedef ServiceApiFactory = ServiceApi Function(ServiceOrigin origin);

final class ConnectedService {
  const ConnectedService({
    required this.api,
    required this.capabilities,
    this.diagnostics,
  });
  final ServiceApi api;
  final Capabilities capabilities;
  final ConnectionDiagnostics? diagnostics;

  ServiceOrigin get origin => api.origin;

  ConnectedService copyWith({
    Capabilities? capabilities,
    ConnectionDiagnostics? diagnostics,
  }) {
    return ConnectedService(
      api: api,
      capabilities: capabilities ?? this.capabilities,
      diagnostics: diagnostics ?? this.diagnostics,
    );
  }
}

final class ConnectionDiagnostics {
  const ConnectionDiagnostics({
    required this.origin,
    required this.connected,
    required this.latency,
    required this.apiVersion,
    required this.networkRoute,
    this.endpointRole = EndpointRole.bootstrap,
    required this.checkedAt,
  });

  final String origin;
  final bool connected;
  final Duration? latency;
  final String? apiVersion;
  final NetworkRoute networkRoute;
  final EndpointRole endpointRole;
  final DateTime checkedAt;
}

final class ConnectionRepository {
  ConnectionRepository([
    ServiceApiFactory? apiFactory,
    Duration? connectionTimeout,
    ServerEndpointProbe? endpointProbe,
  ]) : _apiFactory = apiFactory ?? ((origin) => ServiceApi(origin)),
       timeout = connectionTimeout ?? const Duration(seconds: 3) {
    _endpointProbe =
        endpointProbe ??
        ServerEndpointProbe(requestHealth: _requestHealth, timeout: timeout);
  }
  final ServiceApiFactory _apiFactory;
  late final ServerEndpointProbe _endpointProbe;
  final Duration timeout;

  ServerEndpointProbe get endpointProbe => _endpointProbe;

  Future<ConnectedService> connect(String value) async {
    final health = await _endpointProbe.probe(value);
    return connectProbed(health);
  }

  Future<ConnectedService> connectProbed(HealthSnapshot health) async {
    final api = _apiFactory(health.origin);
    try {
      final capabilities = Capabilities.fromJson(
        await api
            .request('GET', '/api/v1/capabilities')
            .timeout(timeout, onTimeout: _timeout),
      );
      if (capabilities.apiVersion != 'v1') {
        throw ServiceException(
          'UNSUPPORTED_API_VERSION',
          'This client requires Service API v1, received ${capabilities.apiVersion}.',
        );
      }
      return ConnectedService(api: api, capabilities: capabilities);
    } on Object {
      api.close();
      rethrow;
    }
  }

  Future<Object?> _requestHealth(ServiceOrigin origin) async {
    final api = _apiFactory(origin);
    try {
      return await api.request('GET', '/api/v1/health');
    } finally {
      api.close();
    }
  }

  Never _timeout() => throw const ServiceException(
    'CONNECTION_TIMEOUT',
    'The Service did not respond in time. Check the address and port.',
  );
}
