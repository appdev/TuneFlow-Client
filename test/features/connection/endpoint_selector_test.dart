import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_exception.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/features/connection/connection_repository.dart';
import 'package:musicfree_service_client/features/connection/endpoint_selector.dart';
import 'package:musicfree_service_client/features/connection/network_type_monitor.dart';
import 'package:musicfree_service_client/features/connection/server_endpoint_probe.dart';

ServiceOrigin origin(String value) => ServiceOrigin.parse(value);

ConnectionRepository healthyConnections() => ConnectionRepository(
  (serviceOrigin) => ServiceApi(
    serviceOrigin,
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
);

void main() {
  test('orders and de-duplicates candidates by network route', () {
    final catalog = EndpointCatalog(
      bootstrapOrigin: origin('https://bootstrap.example/'),
      lastConnectedOrigin: origin('https://last.example'),
      lanOrigin: origin('http://lan.local'),
      externalOrigin: origin('https://external.example'),
    );

    expect(
      catalog.candidates(NetworkRoute.lan).map((item) => item.uri.toString()),
      [
        'http://lan.local',
        'https://external.example',
        'https://bootstrap.example',
      ],
    );
    expect(
      catalog
          .candidates(NetworkRoute.external)
          .map((item) => item.uri.toString()),
      ['https://external.example', 'https://bootstrap.example'],
    );

    final duplicate = EndpointCatalog(
      bootstrapOrigin: origin('https://same.example/'),
      externalOrigin: origin('https://same.example'),
    );
    expect(duplicate.candidates(NetworkRoute.external), hasLength(1));
    expect(
      catalog.roleOf(origin('http://lan.local'), NetworkRoute.lan),
      EndpointRole.lan,
    );
    expect(
      catalog.roleOf(origin('https://external.example'), NetworkRoute.external),
      EndpointRole.external,
    );
    expect(
      catalog.roleOf(
        origin('https://bootstrap.example'),
        NetworkRoute.external,
      ),
      EndpointRole.bootstrap,
    );
    expect(
      duplicate.roleOf(origin('https://same.example'), NetworkRoute.external),
      EndpointRole.external,
    );
  });

  test(
    'promotes newly advertised LAN origin before external fallback',
    () async {
      final calls = <String>[];
      final probe = ServerEndpointProbe(
        requestHealth: (candidate) async {
          final value = candidate.uri.toString();
          calls.add(value);
          if (value == 'https://external.example') {
            return {'status': 'ok', 'lanOrigin': 'http://lan.local/'};
          }
          return {'status': 'ok'};
        },
      );
      final selector = EndpointSelectionService(
        probe: probe,
        connections: healthyConnections(),
      );

      final selection = await selector.select(
        catalog: EndpointCatalog(
          bootstrapOrigin: origin('https://bootstrap.example'),
          externalOrigin: origin('https://external.example'),
        ),
        route: NetworkRoute.lan,
        generationIsCurrent: () => true,
      );

      expect(calls, ['https://external.example', 'http://lan.local']);
      expect(selection?.connected.origin.uri.toString(), 'http://lan.local');
      expect(selection?.catalog.lanOrigin?.uri.toString(), 'http://lan.local');
      expect(selection?.role, EndpointRole.lan);
      selection?.connected.api.close();
    },
  );

  test('accepts a status-only response and visits duplicates once', () async {
    final calls = <String>[];
    final selector = EndpointSelectionService(
      probe: ServerEndpointProbe(
        requestHealth: (candidate) async {
          calls.add(candidate.uri.toString());
          return {'status': 'ok'};
        },
      ),
      connections: healthyConnections(),
    );
    final selection = await selector.select(
      catalog: EndpointCatalog(
        bootstrapOrigin: origin('https://same.example/'),
        externalOrigin: origin('https://same.example'),
      ),
      route: NetworkRoute.external,
      generationIsCurrent: () => true,
    );

    expect(calls, ['https://same.example']);
    expect(selection, isNotNull);
    expect(selection?.role, EndpointRole.external);
    selection?.connected.api.close();
  });

  test('offline and cancelled selections do not probe', () async {
    var calls = 0;
    final selector = EndpointSelectionService(
      probe: ServerEndpointProbe(
        requestHealth: (_) async {
          calls++;
          return {'status': 'ok'};
        },
      ),
      connections: healthyConnections(),
    );
    final catalog = EndpointCatalog(
      bootstrapOrigin: origin('https://bootstrap.example'),
    );

    expect(
      await selector.select(
        catalog: catalog,
        route: NetworkRoute.offline,
        generationIsCurrent: () => true,
      ),
      isNull,
    );
    expect(
      await selector.select(
        catalog: catalog,
        route: NetworkRoute.external,
        generationIsCurrent: () => false,
      ),
      isNull,
    );
    expect(calls, 0);
  });

  test('falls back after a preferred candidate fails capabilities', () async {
    final capabilities = <String>[];
    final connections = ConnectionRepository(
      (serviceOrigin) => ServiceApi(
        serviceOrigin,
        client: MockClient((_) async {
          final value = serviceOrigin.uri.toString();
          capabilities.add(value);
          if (value == 'http://lan.local') {
            throw const ServiceException('NETWORK_ERROR', 'down');
          }
          return http.Response(
            jsonEncode({
              'data': {
                'runtime': 'service',
                'apiVersion': 'v1',
                'features': <String, Object?>{},
              },
            }),
            200,
          );
        }),
      ),
      const Duration(milliseconds: 5),
    );
    final selector = EndpointSelectionService(
      probe: ServerEndpointProbe(requestHealth: (_) async => {'status': 'ok'}),
      connections: connections,
    );

    final selection = await selector.select(
      catalog: EndpointCatalog(
        lanOrigin: origin('http://lan.local'),
        externalOrigin: origin('https://external.example'),
      ),
      route: NetworkRoute.lan,
      generationIsCurrent: () => true,
    );

    expect(capabilities, ['http://lan.local', 'https://external.example']);
    expect(
      selection?.connected.origin.uri.toString(),
      'https://external.example',
    );
    expect(selection?.role, EndpointRole.external);
    selection?.connected.api.close();
  });

  test('visits at most eight dynamically discovered origins', () async {
    final calls = <String>[];
    final selector = EndpointSelectionService(
      probe: ServerEndpointProbe(
        requestHealth: (candidate) async {
          final value = candidate.uri.toString();
          calls.add(value);
          final number = int.parse(candidate.uri.host.split('-').last);
          return {'status': 'ok', 'lanOrigin': 'http://lan-${number + 1}'};
        },
      ),
      connections: healthyConnections(),
    );

    final selection = await selector.select(
      catalog: EndpointCatalog(lanOrigin: origin('http://lan-1')),
      route: NetworkRoute.lan,
      generationIsCurrent: () => true,
    );

    expect(calls, hasLength(8));
    expect(calls.toSet(), hasLength(8));
    expect(selection?.connected.origin.uri.toString(), 'http://lan-8');
    selection?.connected.api.close();
  });
}
