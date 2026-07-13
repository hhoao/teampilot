import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  group('finalizeAiMessagesForHistory', () {
    test('marks complete tools without result as incomplete', () {
      final messages = finalizeAiMessagesForHistory([
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
      ]);
      final tool = messages.single.parts.single as AiToolCallPart;
      expect(tool.status, AiToolCallStatus.incomplete);
      expect(tool.isError, isFalse);
    });

    test('keeps complete+isError orthogonal', () {
      final messages = finalizeAiMessagesForHistory([
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: [
            AiToolCallPart(
              toolCallId: 't1',
              toolName: 'Bash',
              result: 'boom',
              status: AiToolCallStatus.complete,
              isError: true,
            ),
          ],
        ),
      ]);
      final tool = messages.single.parts.single as AiToolCallPart;
      expect(tool.status, AiToolCallStatus.complete);
      expect(tool.isError, isTrue);
    });
  });

  group('applyAiToolResult', () {
    test('sets result complete and isError', () {
      final messages = [
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: [
            AiToolCallPart(toolCallId: 't1', toolName: 'Bash'),
          ],
        ),
      ];
      expect(
        applyAiToolResult(
          messages,
          toolUseId: 't1',
          result: 'out',
          isError: true,
        ),
        isTrue,
      );
      final tool = messages.single.parts.single as AiToolCallPart;
      expect(tool.result, 'out');
      expect(tool.status, AiToolCallStatus.complete);
      expect(tool.isError, isTrue);
    });
  });

  group('markdownForExport', () {
    test('json-encodes map args and marks errors', () {
      final md = markdownForExport(
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: [
            AiToolCallPart(
              toolCallId: 't1',
              toolName: 'Read',
              args: const {'path': '/tmp/a'},
              result: 'ok',
              status: AiToolCallStatus.complete,
              isError: true,
            ),
          ],
        ),
      );
      expect(md, contains('_(error)_'));
      expect(md, contains('"path"'));
      expect(md, contains('/tmp/a'));
    });
  });
}
