final class AppNavigationEntry {
  const AppNavigationEntry(this.uri, this.extra);

  final Uri uri;
  final Object? extra;
}

final class AppNavigationHistory {
  final List<AppNavigationEntry> _entries = [];
  var _index = -1;

  bool get canGoBack => _index > 0;
  bool get canGoForward => _index >= 0 && _index < _entries.length - 1;

  void record(Uri uri, {Object? extra}) {
    final entry = AppNavigationEntry(uri, extra);
    if (_index >= 0 && _entries[_index].uri == uri) {
      _entries[_index] = entry;
      return;
    }
    if (_index < _entries.length - 1) {
      _entries.removeRange(_index + 1, _entries.length);
    }
    _entries.add(entry);
    _index = _entries.length - 1;
  }

  AppNavigationEntry? goBack() {
    if (!canGoBack) return null;
    _index--;
    return _entries[_index];
  }

  AppNavigationEntry? goForward() {
    if (!canGoForward) return null;
    _index++;
    return _entries[_index];
  }
}
