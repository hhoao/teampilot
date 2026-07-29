import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  const codec = StrReplaceEditHunkCodec();

  test('StrReplace splits old/new into remove+add lines (no LCS)', () {
    final hunk = codec.encode(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'StrReplace',
        args: {
          'file_path': 'lib/foo.dart',
          'old_string': 'a\nb',
          'new_string': 'a\nc',
        },
      ),
    );
    expect(hunk, isNotNull);
    expect(hunk!.path, 'lib/foo.dart');
    expect(hunk.removedCount, 2);
    expect(hunk.addedCount, 2);
    expect(hunk.lines.map((l) => l.kind).toList(), [
      AiEditLineKind.remove,
      AiEditLineKind.remove,
      AiEditLineKind.add,
      AiEditLineKind.add,
    ]);
    expect(hunk.lines.map((l) => l.text).toList(), ['a', 'b', 'a', 'c']);
  });

  test('start_line numbers consecutive lines', () {
    final hunk = codec.encode(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'Edit',
        args: {
          'path': 'a.dart',
          'old_string': 'x',
          'new_string': 'y',
          'start_line': 10,
        },
      ),
    );
    expect(hunk!.startLine, 10);
    expect(hunk.lines[0].lineNumber, 10);
    expect(hunk.lines[1].lineNumber, 11);
  });

  test('missing new_string → null', () {
    expect(
      codec.encode(
        const AiToolCallPart(
          toolCallId: '1',
          toolName: 'StrReplace',
          args: {'file_path': 'a.dart', 'old_string': 'x'},
        ),
      ),
      isNull,
    );
  });

  test('empty new_string → remove-only hunk', () {
    final hunk = codec.encode(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'StrReplace',
        args: {
          'file_path': 'a.dart',
          'old_string': 'delete me',
          'new_string': '',
        },
      ),
    );
    expect(hunk, isNotNull);
    expect(hunk!.removedCount, 1);
    expect(hunk.addedCount, 0);
    expect(hunk.lines.map((l) => l.kind).toList(), [AiEditLineKind.remove]);
    expect(hunk.lines.single.text, 'delete me');
  });

  test('empty old_string → add-only hunk', () {
    final hunk = codec.encode(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'StrReplace',
        args: {
          'file_path': 'a.dart',
          'old_string': '',
          'new_string': 'insert me',
        },
      ),
    );
    expect(hunk, isNotNull);
    expect(hunk!.removedCount, 0);
    expect(hunk.addedCount, 1);
    expect(hunk.lines.map((l) => l.kind).toList(), [AiEditLineKind.add]);
    expect(hunk.lines.single.text, 'insert me');
  });

  test('both old and new empty → null', () {
    expect(
      codec.encode(
        const AiToolCallPart(
          toolCallId: '1',
          toolName: 'StrReplace',
          args: {
            'file_path': 'a.dart',
            'old_string': '',
            'new_string': '',
          },
        ),
      ),
      isNull,
    );
  });
}
