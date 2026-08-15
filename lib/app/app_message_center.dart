import 'dart:async';

final class AppMessage {
  const AppMessage({required this.title, required this.message});

  final String title;
  final String message;
}

final class AppMessageCenter {
  final StreamController<AppMessage> _messages =
      StreamController<AppMessage>.broadcast();
  final List<AppMessage> _pending = [];
  bool _visible = false;

  Stream<AppMessage> get messages => _messages.stream;

  void enqueue(String title, String message) {
    final item = AppMessage(title: title, message: message);
    if (_visible) {
      _messages.add(item);
    } else {
      _pending.add(item);
    }
  }

  void revealPending() {
    _visible = true;
    if (_pending.isEmpty) return;
    final queued = List<AppMessage>.of(_pending);
    _pending.clear();
    for (final item in queued) {
      _messages.add(item);
    }
  }

  void hide() => _visible = false;

  Future<void> dispose() => _messages.close();
}
