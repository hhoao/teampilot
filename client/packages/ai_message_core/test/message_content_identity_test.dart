import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  test('messageContentIdentity changes with deliveryChannel', () {
    const base = AiMessage(
      id: 'm-1',
      role: AiRole.user,
      parts: [AiTextPart(text: 'hi')],
    );
    final mailbox = base.copyWith(deliveryChannel: 'mailbox');

    expect(
      messageContentIdentity(base),
      isNot(equals(messageContentIdentity(mailbox))),
    );
  });

  test('category is excluded from content identity', () {
    const base = AiToolCallPart(toolCallId: '1', toolName: 'bash');
    final other = base.copyWith(category: AiToolCallCategory.command);
    const m1 = AiMessage(id: 'm', role: AiRole.assistant, parts: [base]);
    final m2 = AiMessage(id: 'm', role: AiRole.assistant, parts: [other]);
    expect(messageContentIdentity(m1), messageContentIdentity(m2));
  });

  test('cheapStringEqual uses full compare at or under 128 chars', () {
    expect(cheapStringEqual('a' * 64 + 'MID' + 'b' * 61, 'a' * 64 + 'XXX' + 'b' * 61),
        isFalse);
  });

  test('cheapStringEqual ignores middle of strings longer than 128', () {
    final a = 'h' * 64 + 'AAAA' + 't' * 64;
    final b = 'h' * 64 + 'BBBB' + 't' * 64;
    expect(a.length, greaterThan(128));
    expect(cheapStringEqual(a, b), isTrue);
  });

  test('messagesCheapEqual matches large tool results by length and head/tail', () {
    final result = 'HEAD'.padRight(64, 'H') + ('x' * 8000) + 'TAIL'.padLeft(64, 'T');
    final a = AiMessage(
      id: 'm',
      role: AiRole.assistant,
      parts: [
        AiToolCallPart(
          toolCallId: 't1',
          toolName: 'Bash',
          result: result,
          status: AiToolCallStatus.complete,
        ),
      ],
    );
    final b = AiMessage(
      id: 'm',
      role: AiRole.assistant,
      parts: [
        AiToolCallPart(
          toolCallId: 't1',
          toolName: 'Bash',
          result: StringBuffer(result).toString(),
          status: AiToolCallStatus.complete,
        ),
      ],
    );
    expect(identical(a, b), isFalse);
    expect(messagesCheapEqual(a, b), isTrue);
    expect(
      messagesCheapEqual(
        a,
        AiMessage(
          id: 'm',
          role: AiRole.assistant,
          parts: [
            AiToolCallPart(
              toolCallId: 't1',
              toolName: 'Bash',
              result: '${result}!',
              status: AiToolCallStatus.complete,
            ),
          ],
        ),
      ),
      isFalse,
    );
  });

  test('messagesCheapEqual treats streaming text append as different', () {
    const a = AiMessage(
      id: 'm',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'hello')],
    );
    const b = AiMessage(
      id: 'm',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'hello world')],
    );
    expect(messagesCheapEqual(a, b), isFalse);
  });

  test('messagesCheapEqual ignores tool category', () {
    const base = AiToolCallPart(toolCallId: '1', toolName: 'bash');
    final other = base.copyWith(category: AiToolCallCategory.command);
    const m1 = AiMessage(id: 'm', role: AiRole.assistant, parts: [base]);
    final m2 = AiMessage(id: 'm', role: AiRole.assistant, parts: [other]);
    expect(messagesCheapEqual(m1, m2), isTrue);
  });
}
