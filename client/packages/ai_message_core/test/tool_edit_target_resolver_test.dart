import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  const resolver = DefaultAiEditToolTargetResolver();

  test('resolver routes StrReplace; unknown tool → null', () {
    expect(
      resolver
          .resolve(
            const AiToolCallPart(
              toolCallId: '1',
              toolName: 'StrReplace',
              args: {
                'file_path': 'a.dart',
                'old_string': 'x',
                'new_string': 'y',
              },
            ),
          )
          ?.hunk
          .path,
      'a.dart',
    );
    expect(
      resolver.resolve(
        const AiToolCallPart(toolCallId: '1', toolName: 'Grep', args: {}),
      ),
      isNull,
    );
  });

  test('argsText JSON fallback', () {
    final t = resolver.resolve(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'strreplace',
        argsText:
            '{"file_path":"b.dart","old_string":"o","new_string":"n"}',
      ),
    );
    expect(t?.hunk.path, 'b.dart');
  });

  test('resolver routes Write and ApplyPatch', () {
    expect(
      resolver
          .resolve(
            const AiToolCallPart(
              toolCallId: '1',
              toolName: 'Write',
              args: {
                'file_path': 'a.dart',
                'contents': 'hello',
              },
            ),
          )
          ?.hunk
          .addedCount,
      1,
    );
    expect(
      resolver
          .resolve(
            const AiToolCallPart(
              toolCallId: '1',
              toolName: 'ApplyPatch',
              args: {
                'path': 'b.dart',
                'patch': '-old\n+new',
              },
            ),
          )
          ?.hunk
          .path,
      'b.dart',
    );
  });
}
