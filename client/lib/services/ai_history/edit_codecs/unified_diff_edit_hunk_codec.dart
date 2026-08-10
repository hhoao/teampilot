import 'package:ai_message_core/ai_message_core.dart';

import 'tool_args.dart';

/// Configurable [AiEditHunkCodec] for unified-diff apply-patch tools.
///
/// Accepts tool names and argument key lists via constructor so each CLI / tool
/// variant can supply its own mappings without hardcoding them in the shared
/// package.
class UnifiedDiffEditHunkCodec implements AiEditHunkCodec {
  const UnifiedDiffEditHunkCodec({
    required this.toolNames,
    required this.pathKeys,
    this.patchKeys = const ['patch', 'diff', 'input'],
  });

  /// Tool names to match, case-insensitive.
  final Set<String> toolNames;

  /// Argument keys for the file path (searched in order; first non-empty wins).
  final List<String> pathKeys;

  /// Argument keys for the patch / diff content.
  final List<String> patchKeys;

  static final _hunkHeader = RegExp(r'@@\s*-\d+(?:,\d+)?\s*\+(\d+)');

  @override
  bool matches(String toolName) =>
      toolNames.contains(toolName.toLowerCase());

  @override
  AiEditHunk? encode(AiToolCallPart part) {
    if (!matches(part.toolName)) return null;

    final args = toolCallArgsMap(part);
    final patch = firstNonEmptyString(args, patchKeys);
    if (patch == null) return null;

    var path = firstNonEmptyString(args, pathKeys);
    int? startLine;
    final lines = <AiEditLine>[];
    var addedCount = 0;
    var removedCount = 0;

    for (final rawLine in splitLines(patch)) {
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

  /// Extracts a file path from a unified-diff header line.
  ///
  /// Strips the `--- ` / `+++ ` prefix and the optional `a/` / `b/` directory
  /// prefix.  Returns `null` when the line does not match a diff header or the
  /// resulting path is empty.
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
