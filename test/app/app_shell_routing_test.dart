import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/app/app_router.dart';
import 'package:musicfree_service_client/app/app_shell.dart';

void main() {
  test('nested routes select their owning desktop destination', () {
    expect(navigationSelectionForLocation('/playlists/favorites'), 'playlists');
    expect(navigationSelectionForLocation('/library'), 'playlists');
    expect(navigationSelectionForLocation('/square/wy/list-1'), 'square');
    expect(navigationSelectionForLocation('/settings'), 'settings');
    expect(navigationSelectionForLocation('/settings/connection'), 'settings');
  });

  test('secondary mobile routes remain grouped under more', () {
    for (final location in [
      '/downloads',
      '/settings',
      '/settings/connection',
      '/more/settings/connection',
      '/sources',
      '/more',
    ]) {
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

  test('mobile primary navigation appears only on exact primary paths', () {
    for (final location in const [
      '/',
      '/search',
      '/discover',
      '/playlists',
      '/more',
    ]) {
      expect(showsMobilePrimaryNavigation(location), isTrue, reason: location);
    }

    for (final location in const [
      '/search/playlist/kw/list-1',
      '/search/album/kw/album-1',
      '/discover/playlist/kw/list-1',
      '/playlists/love',
      '/library',
      '/more/downloads',
      '/more/settings',
      '/more/sources',
      '/more/about',
      '/square',
      '/charts',
      '/downloads',
      '/settings',
      '/sources',
      '/future-secondary',
    ]) {
      expect(showsMobilePrimaryNavigation(location), isFalse, reason: location);
    }
  });

  test('source route identity changes with source invalidation version', () {
    expect(sourceRouteKey(4), isNot(sourceRouteKey(5)));
    expect(sourceRouteKey(4), sourceRouteKey(4));
  });
}
