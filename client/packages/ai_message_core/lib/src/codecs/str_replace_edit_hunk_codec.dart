import '../message.dart';
import '../tool_edit_args.dart';
import '../tool_edit_hunk.dart';
import '../tool_edit_hunk_codec.dart';

class StrReplaceEditHunkCodec implements AiEditHunkCodec {
  const StrReplaceEditHunkCodec();

  static const _toolNames = {
    'strreplace',
    'edit',
    'editnotebook',
    'notebookedit',
  };

  @override
  bool matches(String toolName) => _toolNames.contains(toolName.toLowerCase());

  @override
  AiEditHunk? encode(AiToolCallPart part) {
    if (!matches(part.toolName)) return null;

    final args = editArgsMap(part);
    final path = editFirstNonEmptyString(args, editPathKeys);
    if (path == null) return null;

    final oldString = editOptionalString(args, editOldStringKeys);
    if (oldString == null) return null;

    final newString = editOptionalString(args, editNewStringKeys);
    if (newString == null) return null;

    final oldLines = splitEditLines(oldString);
    final newLines = splitEditLines(newString);
    if (oldLines.isEmpty && newLines.isEmpty) return null;

    final startLine = editFirstPositiveInt(args, editStartLineKeys);
    final lines = <AiEditLine>[];
    var lineNumber = startLine;

    for (final text in oldLines) {
      lines.add(AiEditLine(
        kind: AiEditLineKind.remove,
        text: text,
        lineNumber: lineNumber,
      ));
      if (lineNumber != null) lineNumber++;
    }

    for (final text in newLines) {
      lines.add(AiEditLine(
        kind: AiEditLineKind.add,
        text: text,
        lineNumber: lineNumber,
      ));
      if (lineNumber != null) lineNumber++;
    }

    return AiEditHunk(
      path: path,
      lines: lines,
      addedCount: newLines.length,
      removedCount: oldLines.length,
      startLine: startLine,
    );
  }
}
