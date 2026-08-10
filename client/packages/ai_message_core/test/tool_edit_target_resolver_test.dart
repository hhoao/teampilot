import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

/// Minimal inline resolver for testing the [AiEditToolTargetResolver]
/// interface contract.
class _TestResolver implements AiEditToolTargetResolver {
  const _TestResolver();

  @override
  AiEditToolTarget? resolve(AiToolCallPart part) {
    final name = part.toolName.toLowerCase();
    if (name == 'strreplace' || name == 'edit') {
      final path = part.args?['file_path'] as String?;
      if (path == null) return null;
      return AiEditToolTarget(
        hunk: AiEditHunk(path: path, lines: [], addedCount: 0, removedCount: 0),
      );
    }
    return null;
  }
}

void main() {
  const resolver = _TestResolver();

  test('resolver routes StrReplace; unknown tool null', () {
    final t = resolver.resolve(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'StrReplace',
        args: {'file_path': 'a.dart'},
      ),
    );
    expect(t?.hunk.path, 'a.dart');

    expect(
      resolver.resolve(
        const AiToolCallPart(toolCallId: '1', toolName: 'Grep', args: {}),
      ),
      isNull,
    );
  });

  test('case-insensitive name match', () {
    expect(
      resolver
          .resolve(
            const AiToolCallPart(
              toolCallId: '1',
              toolName: 'strreplace',
              args: {'file_path': 'b.dart'},
            ),
          )
          ?.hunk
          .path,
      'b.dart',
    );
  });

  test('missing path returns null', () {
    expect(
      resolver.resolve(
        const AiToolCallPart(
          toolCallId: '1',
          toolName: 'StrReplace',
          args: {'old_string': 'x'},
        ),
      ),
      isNull,
    );
  });
}
