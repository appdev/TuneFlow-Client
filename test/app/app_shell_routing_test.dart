import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/app/app_router.dart';
import 'package:musicfree_service_client/app/app_shell.dart';

void main() {
  test('nested routes select their owning desktop destination', () {
    expect(navigationSelectionForLocation('/playlists/favorites'), 'playlists');
    expect(navigationSelectionForLocation('/library'), 'playlists');
    expect(navigationSelectionForLocation('/square/wy/list-1'), 'square');
    expect(navigationSelectionForLocation('/settings'), 'settings');
  });

  test('secondary mobile routes remain grouped under more', () {
    for (final location in ['/downloads', '/settings', '/sources', '/more']) {
      expect(
        navigationSelectionForLocation(location, mobile: true),
        'more',
        reason: location,
      );
    }
    expect(
      navigationSelectionForLocation('/discover', mobile: true),
      'discover',
    );
    expect(navigationSelectionForLocation('/square', mobile: true), 'discover');
    expect(navigationSelectionForLocation('/charts', mobile: true), 'discover');
    expect(
      navigationSelectionForLocation('/library', mobile: true),
      'playlists',
    );
  });

  test('source route identity changes with source invalidation version', () {
    expect(sourceRouteKey(4), isNot(sourceRouteKey(5)));
    expect(sourceRouteKey(4), sourceRouteKey(4));
  });
}
