import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  const codec = UnifiedDiffEditHunkCodec();

  const samplePatch = '''
--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -10,3 +10,4 @@
 context
-removed
+added
''';

  test('ApplyPatch parses +/- lines and context', () {
    final hunk = codec.encode(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'ApplyPatch',
        args: {
          'file_path': 'lib/foo.dart',
          'patch': samplePatch,
        },
      ),
    );
    expect(hunk, isNotNull);
    expect(hunk!.path, 'lib/foo.dart');
    expect(hunk.addedCount, 1);
    expect(hunk.removedCount, 1);
    expect(hunk.startLine, 10);
    expect(hunk.lines.map((l) => l.kind).toList(), [
      AiEditLineKind.context,
      AiEditLineKind.remove,
      AiEditLineKind.add,
    ]);
    expect(hunk.lines.map((l) => l.text).toList(), [
      'context',
      'removed',
      'added',
    ]);
  });

  test('path from +++ header when args path missing', () {
    final hunk = codec.encode(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'apply_patch',
        args: {
          'diff': '''--- a/x.dart
+++ b/x.dart
-old
+new
''',
        },
      ),
    );
    expect(hunk!.path, 'x.dart');
    expect(hunk.addedCount, 1);
    expect(hunk.removedCount, 1);
  });

  test('diff and input key aliases', () {
    expect(
      codec.encode(
        const AiToolCallPart(
          toolCallId: '1',
          toolName: 'ApplyPatch',
          args: {
            'path': 'a.dart',
            'diff': '-x\n+y',
          },
        ),
      ),
      isNotNull,
    );
    expect(
      codec.encode(
        const AiToolCallPart(
          toolCallId: '1',
          toolName: 'ApplyPatch',
          args: {
            'path': 'a.dart',
            'input': '-x\n+y',
          },
        ),
      ),
      isNotNull,
    );
  });

  test('no add/remove lines → null', () {
    expect(
      codec.encode(
        const AiToolCallPart(
          toolCallId: '1',
          toolName: 'ApplyPatch',
          args: {
            'file_path': 'a.dart',
            'patch': '''--- a/a.dart
+++ b/a.dart
 context only
''',
          },
        ),
      ),
      isNull,
    );
  });

  test('missing path and no headers → null', () {
    expect(
      codec.encode(
        const AiToolCallPart(
          toolCallId: '1',
          toolName: 'ApplyPatch',
          args: {'patch': '-x\n+y'},
        ),
      ),
      isNull,
    );
  });
}
