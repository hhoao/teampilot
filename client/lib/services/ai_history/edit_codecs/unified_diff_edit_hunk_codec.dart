import 'dart:convert';

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

  /// Codex apply_patch freeform file header, e.g.
  /// `*** Update File: lib/foo.dart` (spl@93c9991 codex-full.md:558-560).
  static final _codexFileHeader =
      RegExp(r'^\*\*\* (?:Update|Add|Delete) File:\s*(.+)$');

  @override
  bool matches(String toolName) =>
      toolNames.contains(toolName.toLowerCase());

  @override
  AiEditHunk? encode(AiToolCallPart part) {
    if (!matches(part.toolName)) return null;

    final args = toolCallArgsMap(part);
    var patch = firstNonEmptyString(args, patchKeys) ?? _freeformPatchText(part);
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

      if (rawLine.startsWith('***')) {
        path ??= _pathFromCodexHeader(rawLine);
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

  /// When the tool is FREEFORM (e.g. codex `apply_patch`), the whole
  /// `arguments` payload is the raw patch text and never parses as JSON —
  /// the adapter stores it in [AiToolCallPart.argsText].  Use it directly
  /// as the patch when no structured args were decoded.
  ///
  /// Structured args win (追加语义): when [AiToolCallPart.args] is a
  /// non-empty map, or [AiToolCallPart.argsText] parses as JSON, no freeform
  /// fallback happens — this keeps the JSON-args path untouched for every
  /// CLI that always emits structured arguments.
  static String? _freeformPatchText(AiToolCallPart part) {
    if (part.args != null && part.args!.isNotEmpty) return null;
    final text = part.argsText?.trim();
    if (text == null || text.isEmpty) return null;
    try {
      jsonDecode(text);
      return null;
    } on FormatException {
      return text;
    }
  }

  /// Extracts a file path from a codex freeform file header line
  /// (`*** Update File:` / `*** Add File:` / `*** Delete File:`).
  ///
  /// Returns null when the line is not a file header (e.g. `*** Begin Patch`,
  /// `*** End Patch`, `*** Move to:`, `*** End of File` — those are skipped).
  static String? _pathFromCodexHeader(String line) {
    final match = _codexFileHeader.firstMatch(line);
    if (match == null) return null;
    final rest = match.group(1)!.trim();
    return rest.isEmpty ? null : rest;
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
