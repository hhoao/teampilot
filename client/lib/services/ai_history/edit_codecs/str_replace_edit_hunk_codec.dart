import 'package:ai_message_core/ai_message_core.dart';

import 'tool_args.dart';

/// Configurable [AiEditHunkCodec] for str-replace / edit / notebook-edit tools.
///
/// Accepts tool names and argument key lists via constructor so each CLI / tool
/// variant can supply its own mappings without hardcoding them in the shared
/// package.
class StrReplaceEditHunkCodec implements AiEditHunkCodec {
  const StrReplaceEditHunkCodec({
    required this.toolNames,
    required this.pathKeys,
    required this.oldStringKeys,
    required this.newStringKeys,
    this.startLineKeys = const [],
  });

  /// Tool names to match, case-insensitive.
  final Set<String> toolNames;

  /// Argument keys for the file path.
  final List<String> pathKeys;

  /// Argument keys for the old / search string.
  final List<String> oldStringKeys;

  /// Argument keys for the new / replacement string.
  final List<String> newStringKeys;

  /// Optional argument keys for the starting line number.
  final List<String> startLineKeys;

  @override
  bool matches(String toolName) =>
      toolNames.contains(toolName.toLowerCase());

  @override
  AiEditHunk? encode(AiToolCallPart part) {
    if (!matches(part.toolName)) return null;

    final args = toolCallArgsMap(part);

    final path = firstNonEmptyString(args, pathKeys);
    if (path == null) return null;

    final oldString = optionalString(args, oldStringKeys);
    final newString = optionalString(args, newStringKeys);
    if (oldString == null && newString == null) return null;

    final oldCount = oldString == null ? 0 : countSplitLines(oldString);
    final newCount = newString == null ? 0 : countSplitLines(newString);
    if (oldCount == 0 && newCount == 0) return null;

    final oldBudget = oldCount < kAiEditHunkMaxEncodedLines
        ? oldCount
        : kAiEditHunkMaxEncodedLines;
    final newBudget = kAiEditHunkMaxEncodedLines - oldBudget;
    final oldLines = oldString == null || oldBudget == 0
        ? const <String>[]
        : takeSplitLines(oldString, oldBudget);
    final newLines = newString == null || newBudget == 0
        ? const <String>[]
        : takeSplitLines(newString, newBudget);

    final startLine = firstPositiveInt(args, startLineKeys);
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
      addedCount: newCount,
      removedCount: oldCount,
      startLine: startLine,
    );
  }
}
