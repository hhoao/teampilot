import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  test('ExternalStore transitions loading → messages → idle', () async {
    final store = ExternalStoreAiThreadRuntime();
    expect(store.status, AiThreadStatus.empty);

    final events = <AiThreadStatus>[];
    final sub = store.changes.listen((_) => events.add(store.status));

    store.setLoading();
    expect(store.status, AiThreadStatus.loading);

    store.setMessages([
      AiMessage(
        id: '1',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'hi')],
        status: AiMessageStatus.complete,
      ),
    ]);
    expect(store.status, AiThreadStatus.idle);
    expect(store.messages, hasLength(1));

    store.setEmpty();
    expect(store.status, AiThreadStatus.empty);
    expect(store.messages, isEmpty);

    store.setError('boom');
    expect(store.status, AiThreadStatus.error);
    expect(store.errorMessage, 'boom');
    expect(store.messages, isEmpty);

    await sub.cancel();
    expect(events, isNotEmpty);
  });

  test('setLoading clears prior messages', () {
    final store = ExternalStoreAiThreadRuntime();
    store.setMessages([
      AiMessage(
        id: '1',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'hi')],
      ),
    ]);
    store.setLoading();
    expect(store.status, AiThreadStatus.loading);
    expect(store.messages, isEmpty);
  });

  test('setMessages([]) sets status to empty', () {
    final store = ExternalStoreAiThreadRuntime();
    store.setMessages([
      AiMessage(
        id: '1',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'hi')],
        status: AiMessageStatus.complete,
      ),
    ]);
    expect(store.status, AiThreadStatus.idle);

    store.setMessages([]);
    expect(store.status, AiThreadStatus.empty);
    expect(store.messages, isEmpty);
  });

  test('setMessages reuses unchanged instances and skips notify', () async {
    final store = ExternalStoreAiThreadRuntime();
    final first = AiMessage(
      id: 'a',
      role: AiRole.user,
      parts: const [AiTextPart(text: 'keep')],
    );
    final tip = AiMessage(
      id: 'b',
      role: AiRole.assistant,
      parts: const [AiTextPart(text: 'v1')],
    );
    store.setMessages([first, tip]);

    var notifies = 0;
    final sub = store.changes.listen((_) => notifies++);

    store.setMessages([
      AiMessage(
        id: 'a',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'keep')],
      ),
      AiMessage(
        id: 'b',
        role: AiRole.assistant,
        parts: const [AiTextPart(text: 'v1')],
      ),
    ]);
    expect(notifies, 0);
    expect(identical(store.messages[0], first), isTrue);
    expect(identical(store.messages[1], tip), isTrue);

    store.setMessages([
      AiMessage(
        id: 'a',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'keep')],
      ),
      AiMessage(
        id: 'b',
        role: AiRole.assistant,
        parts: const [AiTextPart(text: 'v2')],
      ),
    ]);
    expect(notifies, 1);
    expect(identical(store.messages[0], first), isTrue);
    expect(identical(store.messages[1], tip), isFalse);
    expect((store.messages[1].parts.first as AiTextPart).text, 'v2');

    await sub.cancel();
  });
}
