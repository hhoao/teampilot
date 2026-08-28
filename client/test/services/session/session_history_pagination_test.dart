import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/session_history_pagination.dart';

void main() {
  AiMessage msg(String id, String text) => AiMessage(
        id: id,
        role: AiRole.assistant,
        parts: [AiTextPart(text: text)],
      );

  test('reuseHistoryMessageIdentity keeps previous when content matches', () {
    final previous = [msg('a', 'hello')];
    final next = [msg('a', 'hello')];
    final reused = reuseHistoryMessageIdentity(
      previous: previous,
      next: next,
    );
    expect(identical(reused.single, previous.single), isTrue);
  });

  test('reuseHistoryMessageIdentity keeps next when same id streamed', () {
    final previous = [msg('a', 'hello')];
    final next = [msg('a', 'hello world')];
    final reused = reuseHistoryMessageIdentity(
      previous: previous,
      next: next,
    );
    expect(identical(reused.single, next.single), isTrue);
    expect(
      (reused.single.parts.single as AiTextPart).text,
      'hello world',
    );
  });

  test('reuseHistoryMessageIdentity uses cheap equality for large tool results', () {
    final result = 'HEAD'.padRight(64, 'H') + ('x' * 4000) + 'TAIL'.padLeft(64, 'T');
    AiMessage tool(String payload) => AiMessage(
          id: 'a',
          role: AiRole.assistant,
          parts: [
            AiToolCallPart(
              toolCallId: 't1',
              toolName: 'Bash',
              result: payload,
              status: AiToolCallStatus.complete,
            ),
          ],
        );
    final previous = [tool(result)];
    final next = [tool(StringBuffer(result).toString())];
    final reused = reuseHistoryMessageIdentity(previous: previous, next: next);
    expect(identical(reused.single, previous.single), isTrue);
  });
}
