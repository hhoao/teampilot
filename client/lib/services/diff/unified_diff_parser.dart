/// Parses a git unified diff into per-file aligned [DiffRow]s.
///
/// A unified diff only carries changed regions plus a few context lines, not the
/// whole file, so we cannot re-diff from scratch. Instead we trust git's +/-/
/// context classification and reuse [buildChangeRows] to add inline char edits
/// (which git does not provide) and pair edited lines.
///
/// Pure functions, no Flutter dependency.
library;

import 'diff_engine.dart';
import 'diff_model.dart';
import 'diff_options.dart';

/// One file section within a unified diff.
class UnifiedFileDiff {
  UnifiedFileDiff({
    required this.oldPath,
    required this.newPath,
    required this.rows,
    required this.blocks,
    required this.hunks,
    this.isBinary = false,
    this.isNew = false,
    this.isDeleted = false,
    this.isRename = false,
  });

  /// Old path, or null for an added file (`/dev/null`).
  final String? oldPath;

  /// New path, or null for a deleted file (`/dev/null`).
  final String? newPath;

  final List<DiffRow> rows;
  final List<DiffBlock> blocks;

  /// Markers for where each hunk begins, so the UI can render the collapsed
  /// "unchanged region" separator between hunks.
  final List<HunkMarker> hunks;

  final bool isBinary;
  final bool isNew;
  final bool isDeleted;
  final bool isRename;

  String get displayPath => newPath ?? oldPath ?? '';
}

/// Where a hunk starts within [UnifiedFileDiff.rows], plus its header section
/// text (the part after the second `@@`).
class HunkMarker {
  const HunkMarker({
    required this.rowIndex,
    required this.oldStart,
    required this.newStart,
    this.section = '',
  });

  final int rowIndex;
  final int oldStart;
  final int newStart;
  final String section;
}

final RegExp _hunkHeader =
    RegExp(r'^@@+ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@+(.*)$');

/// Parses [diff] and flattens all file sections into a single [DiffResult],
/// concatenating their rows (source control shows one file at a time, but this
/// also tolerates multi-file diffs). Returns an empty result for binary-only or
/// empty diffs.
DiffResult parseUnifiedDiffToResult(
  String diff, {
  DiffOptions options = DiffOptions.none,
}) {
  final files = parseUnifiedDiff(diff, options: options);
  final rows = <DiffRow>[for (final file in files) ...file.rows];
  return DiffResult(rows: rows, blocks: buildBlocks(rows));
}

/// Parses [diff] (the output of `git diff`) into a list of file diffs.
List<UnifiedFileDiff> parseUnifiedDiff(
  String diff, {
  DiffOptions options = DiffOptions.none,
}) {
  if (diff.trim().isEmpty) return const [];
  final lines = diff.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

  final files = <UnifiedFileDiff>[];
  _FileAccumulator? current;

  void flush() {
    if (current != null) {
      files.add(current!.build());
      current = null;
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    if (line.startsWith('diff --git ')) {
      flush();
      current = _FileAccumulator(options);
      final paths = _parseGitHeaderPaths(line);
      current!.oldPath = paths.$1;
      current!.newPath = paths.$2;
      continue;
    }

    if (current == null) {
      // Tolerate a bare `--- / +++` diff with no `diff --git` line.
      if (line.startsWith('--- ')) {
        current = _FileAccumulator(options);
      } else {
        continue;
      }
    }

    if (line.startsWith('new file mode')) {
      current!.isNew = true;
      continue;
    }
    if (line.startsWith('deleted file mode')) {
      current!.isDeleted = true;
      continue;
    }
    if (line.startsWith('rename from ') || line.startsWith('rename to ')) {
      current!.isRename = true;
      continue;
    }
    if (line.startsWith('Binary files ') || line.startsWith('GIT binary patch')) {
      current!.isBinary = true;
      continue;
    }
    if (line.startsWith('--- ')) {
      current!.oldPath = _stripPathPrefix(line.substring(4));
      continue;
    }
    if (line.startsWith('+++ ')) {
      current!.newPath = _stripPathPrefix(line.substring(4));
      continue;
    }

    final match = _hunkHeader.firstMatch(line);
    if (match != null) {
      current!.startHunk(
        oldStart: int.parse(match.group(1)!),
        newStart: int.parse(match.group(3)!),
        section: match.group(5)!.trim(),
      );
      continue;
    }

    if (current!.inHunk) {
      current!.addBodyLine(line);
    }
  }
  flush();
  return files;
}

/// A `\ No newline at end of file` marker — ignored for alignment.
bool _isNoNewline(String line) => line.startsWith(r'\ ');

(String?, String?) _parseGitHeaderPaths(String header) {
  // diff --git a/old b/new  (paths may contain spaces; best-effort split).
  final rest = header.substring('diff --git '.length);
  final aIdx = rest.indexOf('a/');
  final bIdx = rest.lastIndexOf(' b/');
  if (aIdx == 0 && bIdx > 0) {
    final old = rest.substring(2, bIdx);
    final neu = rest.substring(bIdx + 3);
    return (old, neu);
  }
  return (null, null);
}

String? _stripPathPrefix(String raw) {
  var path = raw.trim();
  // Drop a trailing tab + timestamp some tools append.
  final tab = path.indexOf('\t');
  if (tab >= 0) path = path.substring(0, tab);
  if (path == '/dev/null') return null;
  if (path.startsWith('a/') || path.startsWith('b/')) {
    return path.substring(2);
  }
  return path;
}

class _FileAccumulator {
  _FileAccumulator(this._options);

  String? oldPath;
  String? newPath;
  bool isBinary = false;
  bool isNew = false;
  bool isDeleted = false;
  bool isRename = false;

  final List<DiffRow> rows = [];
  final List<DiffBlock> blocks = [];
  final List<HunkMarker> hunks = [];

  bool inHunk = false;
  int _oldNo = 0;
  int _newNo = 0;
  final List<String> _dels = [];
  final List<String> _ins = [];
  final DiffOptions _options;

  void startHunk({
    required int oldStart,
    required int newStart,
    required String section,
  }) {
    _flushChange();
    inHunk = true;
    _oldNo = oldStart;
    _newNo = newStart;
    hunks.add(HunkMarker(
      rowIndex: rows.length,
      oldStart: oldStart,
      newStart: newStart,
      section: section,
    ));
  }

  void addBodyLine(String line) {
    if (_isNoNewline(line)) return;
    // Git prefixes every body line with a marker char; a genuinely empty line
    // is only the trailing-newline artifact, so ignore it. Empty context lines
    // arrive as a single space.
    if (line.isEmpty) return;
    final marker = line[0];
    final text = line.substring(1);
    switch (marker) {
      case '+':
        _ins.add(text);
      case '-':
        _dels.add(text);
      case ' ':
        _flushChange();
        rows.add(DiffRow(
          kind: DiffRowKind.equal,
          leftLineNo: _oldNo,
          rightLineNo: _newNo,
          leftText: text,
          rightText: text,
        ));
        _oldNo++;
        _newNo++;
      default:
        // Unknown line inside a hunk; ignore defensively.
        break;
    }
  }

  void _flushChange() {
    if (_dels.isEmpty && _ins.isEmpty) return;
    rows.addAll(buildChangeRows(
      _dels,
      _ins,
      leftStartNo: _oldNo,
      rightStartNo: _newNo,
      options: _options,
    ));
    _oldNo += _dels.length;
    _newNo += _ins.length;
    _dels.clear();
    _ins.clear();
  }

  UnifiedFileDiff build() {
    // Flush any change pending at end of file.
    _flushChange();
    return UnifiedFileDiff(
      oldPath: oldPath,
      newPath: newPath,
      rows: rows,
      blocks: buildBlocks(rows),
      hunks: hunks,
      isBinary: isBinary,
      isNew: isNew,
      isDeleted: isDeleted,
      isRename: isRename,
    );
  }
}
