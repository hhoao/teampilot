import 'package:ai_message_core/ai_message_core.dart';

import '../io/filesystem.dart';

/// Enriches edit hunks with workspace file context and absolute line numbers.
class WorkspaceEditContextEnricher {
  WorkspaceEditContextEnricher({
    required Filesystem fs,
    required String? sessionWorkingDirectory,
    required List<String> workspaceFolderPaths,
  }) : _fs = fs,
       _sessionWorkingDirectory = sessionWorkingDirectory,
       _workspaceFolderPaths = workspaceFolderPaths;

  final Filesystem _fs;
  final String? _sessionWorkingDirectory;
  final List<String> _workspaceFolderPaths;

  static const _maxContextLines = 2;

  Future<AiEditHunk> enrich(AiEditHunk hunk) async {
    try {
      final resolvedPath = await _resolvePath(hunk.path);
      if (resolvedPath == null) return hunk;

      final fileText = await _fs.readString(resolvedPath);
      if (fileText == null) return hunk;

      final removeLines = hunk.lines
          .where((line) => line.kind == AiEditLineKind.remove)
          .map((line) => line.text)
          .toList(growable: false);
      if (removeLines.isEmpty) return hunk;

      final addLines = hunk.lines
          .where((line) => line.kind == AiEditLineKind.add)
          .map((line) => line.text)
          .toList(growable: false);

      final anchor = removeLines.join('\n');
      final anchorIndex = fileText.indexOf(anchor);
      if (anchorIndex < 0) return hunk;

      final fileLines = _splitLines(fileText);
      final matchStartLine = _lineNumberAt(fileText, anchorIndex);
      final matchEndLine = matchStartLine + removeLines.length - 1;

      final contextBeforeStart = (matchStartLine - _maxContextLines).clamp(
        0,
        matchStartLine,
      );
      final contextAfterEnd = (matchEndLine + 1 + _maxContextLines).clamp(
        0,
        fileLines.length,
      );

      final enrichedLines = <AiEditLine>[
        for (var i = contextBeforeStart; i < matchStartLine; i++)
          AiEditLine(
            kind: AiEditLineKind.context,
            text: fileLines[i],
            lineNumber: i + 1,
          ),
        for (var i = 0; i < removeLines.length; i++)
          AiEditLine(
            kind: AiEditLineKind.remove,
            text: removeLines[i],
            lineNumber: matchStartLine + i + 1,
          ),
        for (var i = 0; i < addLines.length; i++)
          AiEditLine(
            kind: AiEditLineKind.add,
            text: addLines[i],
            lineNumber: matchStartLine + i + 1,
          ),
        for (var i = matchEndLine + 1; i < contextAfterEnd; i++)
          AiEditLine(
            kind: AiEditLineKind.context,
            text: fileLines[i],
            lineNumber: i + 1,
          ),
      ];

      return AiEditHunk(
        path: hunk.path,
        lines: enrichedLines,
        addedCount: hunk.addedCount,
        removedCount: hunk.removedCount,
        startLine: contextBeforeStart + 1,
      );
    } on Object {
      return hunk;
    }
  }

  Future<String?> _resolvePath(String rawPath) async {
    final pathContext = _fs.pathContext;
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return null;

    if (pathContext.isAbsolute(trimmed)) {
      final normalized = pathContext.normalize(trimmed);
      final stat = await _fs.stat(normalized);
      return stat.isFile ? normalized : null;
    }

    final candidates = <String>[];
    final cwd = _sessionWorkingDirectory?.trim();
    if (cwd != null && cwd.isNotEmpty) {
      candidates.add(pathContext.join(cwd, trimmed));
    }
    for (final folder in _workspaceFolderPaths) {
      final folderTrimmed = folder.trim();
      if (folderTrimmed.isEmpty) continue;
      candidates.add(pathContext.join(folderTrimmed, trimmed));
    }

    for (final candidate in candidates) {
      final normalized = pathContext.normalize(candidate);
      final stat = await _fs.stat(normalized);
      if (stat.isFile) return normalized;
    }
    return null;
  }

  static List<String> _splitLines(String text) {
    final lines = text.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return [
      for (final line in lines) line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
    ];
  }

  static int _lineNumberAt(String text, int index) {
    var line = 0;
    for (var i = 0; i < index && i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) line++;
    }
    return line;
  }
}
