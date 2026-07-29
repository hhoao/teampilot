import '../message.dart';
import '../tool_edit_args.dart';
import '../tool_edit_hunk.dart';
import '../tool_edit_hunk_codec.dart';

class UnifiedDiffEditHunkCodec implements AiEditHunkCodec {
  const UnifiedDiffEditHunkCodec();

  static const _toolNames = {'applypatch', 'apply_patch'};

  static const _patchKeys = ['patch', 'diff', 'input'];

  static final _hunkHeader = RegExp(r'@@\s*-\d+(?:,\d+)?\s*\+(\d+)');

  @override
  bool matches(String toolName) => _toolNames.contains(toolName.toLowerCase());

  @override
  AiEditHunk? encode(AiToolCallPart part) {
    if (!matches(part.toolName)) return null;

    final args = editArgsMap(part);
    final patch = editFirstNonEmptyString(args, _patchKeys);
    if (patch == null) return null;

    var path = editFirstNonEmptyString(args, editPathKeys);
    int? startLine;
    final lines = <AiEditLine>[];
    var addedCount = 0;
    var removedCount = 0;

    for (final rawLine in splitEditLines(patch)) {
      if (rawLine.startsWith('@@')) {
        if (startLine == null) {
          final match = _hunkHeader.firstMatch(rawLine);
          if (match != null) {
            startLine = int.tryParse(match.group(1)!);
          }
        }
        continue;
      }

      if (rawLine.startsWith('---')) {
        path ??= _pathFromDiffHeader(rawLine);
        continue;
      }

      if (rawLine.startsWith('+++')) {
        final headerPath = _pathFromDiffHeader(rawLine);
        if (headerPath != null) path = path ?? headerPath;
        continue;
      }

      if (rawLine.isEmpty) continue;

      final prefix = rawLine[0];
      if (prefix == '+') {
        lines.add(AiEditLine(
          kind: AiEditLineKind.add,
          text: rawLine.substring(1),
        ));
        addedCount++;
      } else if (prefix == '-') {
        lines.add(AiEditLine(
          kind: AiEditLineKind.remove,
          text: rawLine.substring(1),
        ));
        removedCount++;
      } else if (prefix == ' ') {
        lines.add(AiEditLine(
          kind: AiEditLineKind.context,
          text: rawLine.substring(1),
        ));
      } else {
        lines.add(AiEditLine(
          kind: AiEditLineKind.context,
          text: rawLine,
        ));
      }
    }

    if (path == null || (addedCount == 0 && removedCount == 0)) return null;

    return AiEditHunk(
      path: path,
      lines: lines,
      addedCount: addedCount,
      removedCount: removedCount,
      startLine: startLine,
    );
  }

  static String? _pathFromDiffHeader(String line) {
    String rest;
    if (line.startsWith('--- ')) {
      rest = line.substring(4).trim();
    } else if (line.startsWith('+++ ')) {
      rest = line.substring(4).trim();
    } else {
      return null;
    }

    if (rest.startsWith('a/')) rest = rest.substring(2);
    if (rest.startsWith('b/')) rest = rest.substring(2);
    return rest.isEmpty ? null : rest;
  }
}
