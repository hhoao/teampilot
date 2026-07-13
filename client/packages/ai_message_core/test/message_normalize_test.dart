import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  test('normalize merges string content into AiTextPart', () {
    final messages = normalizeThreadMessages([
      const ThreadMessageLike(
        id: 'm1',
        role: AiRole.user,
        content: 'hello',
      ),
    ]);
    expect(messages, hasLength(1));
    expect(messages.single.role, AiRole.user);
    expect(messages.single.parts, hasLength(1));
    expect((messages.single.parts.single as AiTextPart).text, 'hello');
    expect(messages.single.status, AiMessageStatus.complete);
  });

  test('normalize keeps tool-call parts on assistant messages', () {
    final messages = normalizeThreadMessages([
      ThreadMessageLike(
        id: 'a1',
        role: AiRole.assistant,
        content: [
          const AiTextPart(text: 'Using tool'),
          AiToolCallPart(
            toolCallId: 't1',
            toolName: 'Bash',
            args: {'cmd': 'ls'},
          ),
        ],
      ),
    ]);
    expect(messages.single.parts, hasLength(2));
    final tool = messages.single.parts[1] as AiToolCallPart;
    expect(tool.toolName, 'Bash');
    expect(tool.result, isNull);
  });

  test('normalize skips empty string content', () {
    final messages = normalizeThreadMessages([
      const ThreadMessageLike(
        id: 'm1',
        role: AiRole.user,
        content: '',
      ),
    ]);
    expect(messages, isEmpty);
  });

  test('normalize skips empty list content', () {
    final messages = normalizeThreadMessages([
      const ThreadMessageLike(
        id: 'm1',
        role: AiRole.user,
        content: <AiMessagePart>[],
      ),
    ]);
    expect(messages, isEmpty);
  });

  test('normalize skips single empty AiTextPart', () {
    final messages = normalizeThreadMessages([
      const ThreadMessageLike(
        id: 'm1',
        role: AiRole.user,
        content: [AiTextPart(text: '')],
      ),
    ]);
    expect(messages, isEmpty);
  });

  test('normalize keeps whitespace-only string content', () {
    final messages = normalizeThreadMessages([
      const ThreadMessageLike(
        id: 'm1',
        role: AiRole.user,
        content: '   ',
      ),
    ]);
    expect(messages, hasLength(1));
    expect((messages.single.parts.single as AiTextPart).text, '   ');
  });

  test('normalize drops empty AiTextPart from list but keeps other parts', () {
    final messages = normalizeThreadMessages([
      ThreadMessageLike(
        id: 'a1',
        role: AiRole.assistant,
        content: [
          const AiTextPart(text: ''),
          AiToolCallPart(
            toolCallId: 't1',
            toolName: 'Bash',
            args: {'cmd': 'ls'},
          ),
        ],
      ),
    ]);
    expect(messages, hasLength(1));
    expect(messages.single.parts, hasLength(1));
    expect(messages.single.parts.single, isA<AiToolCallPart>());
  });

  test(r'normalize uses msg_$i when id is null', () {
    final messages = normalizeThreadMessages([
      const ThreadMessageLike(
        role: AiRole.user,
        content: 'hello',
      ),
    ]);
    expect(messages.single.id, 'msg_0');
  });

  test('normalize id uses input ordinal when earlier items skipped', () {
    final messages = normalizeThreadMessages([
      const ThreadMessageLike(
        role: AiRole.user,
        content: '',
      ),
      const ThreadMessageLike(
        role: AiRole.user,
        content: 'hello',
      ),
    ]);
    expect(messages, hasLength(1));
    expect(messages.single.id, 'msg_1');
  });

  test('normalize throws for invalid content type', () {
    expect(
      () => normalizeThreadMessages([
        ThreadMessageLike(
          role: AiRole.user,
          content: 42,
        ),
      ]),
      throwsA(isA<ArgumentError>()),
    );
  });
}
