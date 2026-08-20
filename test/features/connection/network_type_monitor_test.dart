import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/features/connection/network_type_monitor.dart';

void main() {
  test('classifies Wi-Fi and Ethernet as LAN-capable', () {
    expect(classifyNetwork({NetworkTransport.wifi}), NetworkRoute.lan);
    expect(classifyNetwork({NetworkTransport.ethernet}), NetworkRoute.lan);
    expect(
      classifyNetwork({NetworkTransport.mobile, NetworkTransport.wifi}),
      NetworkRoute.lan,
    );
  });

  test('classifies available non-LAN transports as external', () {
    expect(classifyNetwork({NetworkTransport.mobile}), NetworkRoute.external);
    expect(classifyNetwork({NetworkTransport.vpn}), NetworkRoute.external);
    expect(classifyNetwork({NetworkTransport.other}), NetworkRoute.external);
  });

  test('classifies empty and none-only transport sets as offline', () {
    expect(classifyNetwork({}), NetworkRoute.offline);
    expect(classifyNetwork({NetworkTransport.none}), NetworkRoute.offline);
    expect(
      classifyNetwork({NetworkTransport.none, NetworkTransport.mobile}),
      NetworkRoute.external,
    );
  });
}
