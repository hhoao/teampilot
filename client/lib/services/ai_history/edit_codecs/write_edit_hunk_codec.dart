import 'package:ai_message_core/ai_message_core.dart';

import 'tool_args.dart';

/// Configurable [AiEditHunkCodec] for write / create-file tools.
///
/// Accepts tool names and argument key lists via constructor so each CLI / tool
/// variant can supply its own mappings without hardcoding them in the shared
/// package.
class WriteEditHunkCodec implements AiEditHunkCodec {
  const WriteEditHunkCodec({
    required this.toolNames,
    required this.pathKeys,
    this.contentKeys = const ['content', 'contents'],
  });

  /// Tool names to match, case-insensitive.
  final Set<String> toolNames;

  /// Argument keys for the file path.
  final List<String> pathKeys;

  /// Argument keys for the file content.
  final List<String> contentKeys;

  static const _maxEncodedLines = 500;

  @override
  bool matches(String toolName) =>
      toolNames.contains(toolName.toLowerCase());

  @override
  AiEditHunk? encode(AiToolCallPart part) {
    if (!matches(part.toolName)) return null;

    final args = toolCallArgsMap(part);

    final path = firstNonEmptyString(args, pathKeys);
    if (path == null) return null;

    final contents = firstNonEmptyString(args, contentKeys);
    if (contents == null) return null;

    final contentLines = splitLines(contents);
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
