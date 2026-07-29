import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  const codec = WriteEditHunkCodec();

  test('Write splits contents into add lines', () {
    final hunk = codec.encode(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'Write',
        args: {
          'file_path': 'lib/foo.dart',
          'contents': 'line1\nline2',
        },
      ),
    );
    expect(hunk, isNotNull);
    expect(hunk!.path, 'lib/foo.dart');
    expect(hunk.addedCount, 2);
    expect(hunk.removedCount, 0);
    expect(hunk.lines.every((l) => l.kind == AiEditLineKind.add), isTrue);
    expect(hunk.lines.map((l) => l.text).toList(), ['line1', 'line2']);
  });

  test('content key alias works', () {
    final hunk = codec.encode(
      const AiToolCallPart(
        toolCallId: '1',
        toolName: 'create_file',
        args: {
          'path': 'a.dart',
          'content': 'hello',
        },
      ),
    );
    expect(hunk!.addedCount, 1);
    expect(hunk.lines.single.text, 'hello');
  });

  test('caps encoded lines at 500 but keeps full addedCount', () {
    final contents = List.generate(600, (i) => 'line$i').join('\n');
    final hunk = codec.encode(
      AiToolCallPart(
        toolCallId: '1',
        toolName: 'Write',
        args: {
          'file_path': 'big.txt',
          'contents': contents,
        },
      ),
    );
    expect(hunk, isNotNull);
    expect(hunk!.addedCount, 600);
    expect(hunk.lines.length, 500);
    expect(hunk.lines.every((l) => l.kind == AiEditLineKind.add), isTrue);
  });

  test('missing path → null', () {
    expect(
      codec.encode(
        const AiToolCallPart(
          toolCallId: '1',
          toolName: 'Write',
          args: {'contents': 'x'},
        ),
      ),
      isNull,
    );
  });

  test('empty or missing contents → null', () {
    expect(
      codec.encode(
        const AiToolCallPart(
          toolCallId: '1',
          toolName: 'Write',
          args: {'file_path': 'a.dart', 'contents': ''},
        ),
      ),
      isNull,
    );
    expect(
      codec.encode(
        const AiToolCallPart(
          toolCallId: '1',
          toolName: 'Write',
          args: {'file_path': 'a.dart'},
        ),
      ),
      isNull,
    );
  });
}
