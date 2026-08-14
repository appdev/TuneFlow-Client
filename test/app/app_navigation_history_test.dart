import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/app/app_navigation_history.dart';

void main() {
  test('moves backward and forward through recorded routes', () {
    final history = AppNavigationHistory()
      ..record(Uri.parse('/'))
      ..record(Uri.parse('/downloads'))
      ..record(Uri.parse('/settings'));

    expect(history.canGoBack, isTrue);
    expect(history.canGoForward, isFalse);
    expect(history.goBack()!.uri.path, '/downloads');
    expect(history.canGoForward, isTrue);
    expect(history.goForward()!.uri.path, '/settings');
  });

  test('new navigation after going back discards the forward branch', () {
    final history = AppNavigationHistory()
      ..record(Uri.parse('/'))
      ..record(Uri.parse('/downloads'))
      ..record(Uri.parse('/settings'))
      ..goBack()
      ..record(Uri.parse('/search'));

    expect(history.canGoForward, isFalse);
    expect(history.goBack()!.uri.path, '/downloads');
  });

  test('retains route extra data when revisiting a detail page', () {
    final extra = Object();
    final history = AppNavigationHistory()
      ..record(Uri.parse('/'))
      ..record(Uri.parse('/square/source/list'), extra: extra);

    history.goBack();

    expect(history.goForward()!.extra, same(extra));
  });
}
