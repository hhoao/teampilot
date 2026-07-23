import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  group('coalesceAdjacentAssistants', () {
    test('merges adjacent assistants and keeps first id/createdAt', () {
      final t0 = DateTime.utc(2026, 7, 23, 1);
      final t1 = DateTime.utc(2026, 7, 23, 2);
      final out = coalesceAdjacentAssistants([
        AiMessage(
          id: 'u1',
          role: AiRole.user,
          parts: const [AiTextPart(text: 'go')],
        ),
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          createdAt: t0,
          parts: const [AiReasoningPart(text: 'think')],
        ),
        AiMessage(
          id: 'a2',
          role: AiRole.assistant,
          createdAt: t1,
          parts: [
            AiToolCallPart(toolCallId: 'c1', toolName: 'shell_command'),
          ],
        ),
        AiMessage(
          id: 'a3',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'done')],
        ),
      ]);

      expect(out, hasLength(2));
      expect(out[1].id, 'a1');
      expect(out[1].createdAt, t0);
      expect(out[1].parts, hasLength(3));
      expect(out[1].parts[0], isA<AiReasoningPart>());
      expect(out[1].parts[1], isA<AiToolCallPart>());
      expect(out[1].parts[2], isA<AiTextPart>());
    });

    test('does not merge across user messages', () {
      final out = coalesceAdjacentAssistants([
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'one')],
        ),
        AiMessage(
          id: 'u1',
          role: AiRole.user,
          parts: const [AiTextPart(text: 'again')],
        ),
        AiMessage(
          id: 'a2',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'two')],
        ),
      ]);
      expect(out.map((m) => m.id).toList(), ['a1', 'u1', 'a2']);
    });

    test('does not merge across system messages', () {
      final out = coalesceAdjacentAssistants([
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'one')],
        ),
        AiMessage(
          id: 's1',
          role: AiRole.system,
          parts: const [AiTextPart(text: 'note')],
        ),
        AiMessage(
          id: 'a2',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'two')],
        ),
      ]);
      expect(out.map((m) => m.id).toList(), ['a1', 's1', 'a2']);
    });
  });

  test('finalizeAiMessagesForHistory coalesces then normalizes tools', () {
    final out = finalizeAiMessagesForHistory([
      AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: [
          AiToolCallPart(
            toolCallId: 't1',
            toolName: 'Bash',
            status: AiToolCallStatus.complete,
          ),
        ],
      ),
      AiMessage(
        id: 'a2',
        role: AiRole.assistant,
        parts: const [AiTextPart(text: 'ok')],
      ),
    ]);
    expect(out, hasLength(1));
    expect(out.single.id, 'a1');
    final tool = out.single.parts.first as AiToolCallPart;
    expect(tool.status, AiToolCallStatus.incomplete);
    expect(out.single.parts.last, isA<AiTextPart>());
  });
}
