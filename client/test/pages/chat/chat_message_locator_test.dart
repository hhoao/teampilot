import 'package:ai_message_core/ai_message_core.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/chat_message_locator.dart';
import 'package:teampilot/pages/chat/chat_reveal_controller.dart';

AiMessage _user(String id) => AiMessage(
  id: id,
  role: AiRole.user,
  parts: const [AiTextPart(text: 'x')],
);

void main() {
  test('reveals after id is already in the runtime', () async {
    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages([_user('u0'), _user('u1')]);
    final loaded = [_user('u0'), _user('u1'), _user('u2')];
    final revealed = <int>[];
    final controller = ChatRevealController();
    String? highlight;
    final locator = ChatMessageLocator(
      loadedMessages: () => loaded,
      runtime: () => runtime,
      revealInWindow: revealed.add,
      revealController: controller,
      onHighlight: (id) => highlight = id,
      waitFrame: () async {},
    );

    await locator.locate(id: 'u1', index: 99);

    expect(revealed, [1]);
    expect(controller.targetMessageId, 'u1');
    expect(highlight, 'u1');
  });

  test('waits for runtime then reveals', () async {
    final runtime = ExternalStoreAiThreadRuntime();
    final loaded = [_user('u0')];
    final controller = ChatRevealController();
    final locator = ChatMessageLocator(
      loadedMessages: () => loaded,
      runtime: () => runtime,
      revealInWindow: (_) {},
      revealController: controller,
      onHighlight: (_) {},
      waitFrame: () async {},
    );

    final pending = locator.locate(id: 'u0');
    runtime.setMessages([_user('u0')]);
    await pending;

    expect(controller.targetMessageId, 'u0');
  });

  test('missing id does not reveal', () async {
    final runtime = ExternalStoreAiThreadRuntime()..setMessages([_user('u0')]);
    final controller = ChatRevealController();
    var highlightCalls = 0;
    final locator = ChatMessageLocator(
      loadedMessages: () => [_user('u0')],
      runtime: () => runtime,
      revealInWindow: (_) {},
      revealController: controller,
      onHighlight: (_) => highlightCalls++,
      waitFrame: () async {},
    );

    await locator.locate(id: 'missing');

    expect(controller.targetMessageId, isNull);
    expect(highlightCalls, 0);
  });

  test('timeout does not reveal', () {
    FakeAsync().run((async) {
      final runtime = ExternalStoreAiThreadRuntime();
      final controller = ChatRevealController();
      var highlightCalls = 0;
      final locator = ChatMessageLocator(
        loadedMessages: () => [_user('u0')],
        runtime: () => runtime,
        revealInWindow: (_) {},
        revealController: controller,
        onHighlight: (_) => highlightCalls++,
        timeout: const Duration(milliseconds: 450),
        waitFrame: () async {},
      );

      locator.locate(id: 'u0');
      async.elapse(const Duration(milliseconds: 451));

      expect(controller.targetMessageId, isNull);
      expect(highlightCalls, 0);
    });
  });

  test('cancel during wait does not reveal', () async {
    final runtime = ExternalStoreAiThreadRuntime();
    final loaded = [_user('u0')];
    final controller = ChatRevealController();
    var highlightCalls = 0;
    final locator = ChatMessageLocator(
      loadedMessages: () => loaded,
      runtime: () => runtime,
      revealInWindow: (_) {},
      revealController: controller,
      onHighlight: (_) => highlightCalls++,
      waitFrame: () async {},
    );

    final pending = locator.locate(id: 'u0');
    locator.cancel();
    runtime.setMessages([_user('u0')]);
    await pending;

    expect(controller.targetMessageId, isNull);
    expect(highlightCalls, 0);
  });

  test('second locate wins while first is waiting', () async {
    final runtime = ExternalStoreAiThreadRuntime()..setMessages([_user('u1')]);
    final loaded = [_user('u0'), _user('u1')];
    final controller = ChatRevealController();
    String? highlight;
    final locator = ChatMessageLocator(
      loadedMessages: () => loaded,
      runtime: () => runtime,
      revealInWindow: (_) {},
      revealController: controller,
      onHighlight: (id) => highlight = id,
      waitFrame: () async {},
    );

    final first = locator.locate(id: 'u0');
    final second = locator.locate(id: 'u1');
    runtime.setMessages([_user('u0'), _user('u1')]);
    await first;
    await second;

    expect(controller.targetMessageId, 'u1');
    expect(highlight, 'u1');
  });
}
