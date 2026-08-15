import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/app/app_message_center.dart';

void main() {
  test('queues messages while hidden and reveals them once in order', () async {
    final center = AppMessageCenter();
    addTearDown(center.dispose);
    final messages = <AppMessage>[];
    final subscription = center.messages.listen(messages.add);
    addTearDown(subscription.cancel);

    center.enqueue('第一条', '详情一');
    center.enqueue('第二条', '详情二');
    await Future<void>.delayed(Duration.zero);
    expect(messages, isEmpty);

    center.revealPending();
    await Future<void>.delayed(Duration.zero);
    expect(messages.map((item) => item.title), ['第一条', '第二条']);

    center.revealPending();
    await Future<void>.delayed(Duration.zero);
    expect(messages, hasLength(2));
  });

  test('emits immediately while visible and queues again after hide', () async {
    final center = AppMessageCenter();
    addTearDown(center.dispose);
    final messages = <AppMessage>[];
    final subscription = center.messages.listen(messages.add);
    addTearDown(subscription.cancel);

    center.revealPending();
    center.enqueue('可见', '立即显示');
    await Future<void>.delayed(Duration.zero);
    expect(messages.single.title, '可见');

    center.hide();
    center.enqueue('隐藏', '稍后显示');
    await Future<void>.delayed(Duration.zero);
    expect(messages, hasLength(1));

    center.revealPending();
    await Future<void>.delayed(Duration.zero);
    expect(messages.last.title, '隐藏');
  });
}
