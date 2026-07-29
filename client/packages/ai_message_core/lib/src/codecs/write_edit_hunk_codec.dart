import '../message.dart';
import '../tool_edit_args.dart';
import '../tool_edit_hunk.dart';
import '../tool_edit_hunk_codec.dart';

class WriteEditHunkCodec implements AiEditHunkCodec {
  const WriteEditHunkCodec();

  static const _toolNames = {
    'write',
    'writefile',
    'write_file',
    'create',
    'create_file',
  };

  static const _contentKeys = ['contents', 'content'];

  static const _maxEncodedLines = 500;

  @override
  bool matches(String toolName) => _toolNames.contains(toolName.toLowerCase());

  @override
  AiEditHunk? encode(AiToolCallPart part) {
    if (!matches(part.toolName)) return null;

    final args = editArgsMap(part);
    final path = editFirstNonEmptyString(args, editPathKeys);
    if (path == null) return null;

    final contents = editFirstNonEmptyString(args, _contentKeys);
    if (contents == null) return null;

    final contentLines = splitEditLines(contents);
    if (contentLines.isEmpty) return null;

    final encodedLines = <AiEditLine>[];
    final limit = contentLines.length < _maxEncodedLines
        ? contentLines.length
        : _maxEncodedLines;
    for (var i = 0; i < limit; i++) {
      encodedLines.add(AiEditLine(
        kind: AiEditLineKind.add,
        text: contentLines[i],
      ));
    }

    return AiEditHunk(
      path: path,
      lines: encodedLines,
      addedCount: contentLines.length,
      removedCount: 0,
    );
  }
}
