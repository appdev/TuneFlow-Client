import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicfree_service_client/api/models.dart';
import 'package:musicfree_service_client/api/service_api.dart';
import 'package:musicfree_service_client/api/service_origin.dart';
import 'package:musicfree_service_client/api/sse_transport.dart';

void main() {
  test('parses fragmented comments and multi-line SSE data exactly once', () {
    final parser = SseParser();
    final bytes = utf8.encode(
      ': connected\n\n'
      'event: downloads.updated\n'
      'data: {"type":"downloads.updated",\n'
      'data: "data":[],"sequence":9}\n\n',
    );

    final events = <DomainEvent>[];
    events.addAll(parser.add(bytes.sublist(0, 11)));
    events.addAll(parser.add(bytes.sublist(11, 37)));
    events.addAll(parser.add(bytes.sublist(37)));

    expect(events, hasLength(1));
    expect(events.single.type, 'downloads.updated');
    expect(events.single.sequence, 9);
  });

  test('ignores an older sequence', () {
    final parser = SseParser(initialSequence: 9);
    final events = parser.add(
      utf8.encode(
        'data: {"type":"old","data":null,"sequence":8}\n\n'
        'data: {"type":"new","data":null,"sequence":10}\n\n',
      ),
    );

    expect(events.map((event) => event.type), ['new']);
    expect(parser.sequence, 10);
  });

  test('revalidates current state after an SSE connection succeeds', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/snapshot')) {
        return http.Response(
          jsonEncode({
            'data': {'sequence': 0, 'events': <Object?>[]},
          }),
          200,
        );
      }
      return http.Response(
        '',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final origin = ServiceOrigin.parse('http://service.local:18080');
    final api = ServiceApi(origin, client: client);
    final connected = Completer<void>();
    final transport = SseTransport(
      api,
      client: client,
      delay: (_) async {},
      onConnected: () {
        if (!connected.isCompleted) connected.complete();
      },
    );

    final subscription = transport.events().listen((_) {});
    await connected.future;
    transport.close();
    await subscription.cancel();

    api.close();
  });

  test('reconnects snapshot and stream against a switched origin', () async {
    final urls = <String>[];
    final client = MockClient((request) async {
      urls.add(request.url.toString());
      if (request.url.path.endsWith('/snapshot')) {
        return http.Response(
          jsonEncode({
            'data': {'sequence': 0, 'events': <Object?>[]},
          }),
          200,
        );
      }
      return http.Response(
        '',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final api = ServiceApi(
      ServiceOrigin.parse('https://external.example'),
      client: client,
    );
    var reconnects = 0;
    var connections = 0;
    final connectedTwice = Completer<void>();
    late final SseTransport transport;
    transport = SseTransport(
      api,
      client: client,
      delay: (_) async {
        reconnects++;
        if (reconnects == 1) {
          api.switchOrigin(ServiceOrigin.parse('http://192.168.1.20:3124'));
        }
      },
      onConnected: () {
        connections++;
        if (connections == 2 && !connectedTwice.isCompleted) {
          connectedTwice.complete();
          transport.close();
        }
      },
    );

    final subscription = transport.events().listen((_) {});
    await connectedTwice.future;
    await subscription.cancel();

    expect(urls.take(4), [
      'https://external.example/api/v1/events/snapshot',
      'https://external.example/api/v1/events',
      'http://192.168.1.20:3124/api/v1/events/snapshot',
      'http://192.168.1.20:3124/api/v1/events',
    ]);
    api.close();
  });
}
