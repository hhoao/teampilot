/// Pure left→right hunk apply for editable unstaged diffs.
///
/// No Flutter dependency so it can be unit-tested in isolation.
library;

import 'diff_model.dart';

/// Non-filler lines from one diff side, joined with `\n`.
///
/// When [preferTrailingNewline] is true, appends a final newline even for a
/// single-line body (empty input still yields `''`).
String canonicalSideText(
  List<DiffRow> rows, {
  required bool right,
  bool preferTrailingNewline = false,
}) {
  final lines = <String>[
    for (final row in rows)
      if (right ? row.hasRight : row.hasLeft)
        (right ? row.rightText : row.leftText)!,
  ];
  if (lines.isEmpty) return '';
  final body = lines.join('\n');
  return preferTrailingNewline ? '$body\n' : body;
}

/// Applies a single [DiffBlock] from the left (HEAD/index) side onto
/// [rightFileText] (working tree).
class DiffHunkApplier {
  DiffHunkApplier._();

  /// Replace the right-file span covered by [block] with the block's left lines.
  static String applyLeftToRight({
    required DiffResult result,
    required DiffBlock block,
    required String rightFileText,
  }) {
    if (block.startRow < 0 ||
        block.endRow > result.rows.length ||
        block.startRow >= block.endRow) {
      throw StateError('DiffBlock out of range: $block');
    }

    final slice = result.rows.sublist(block.startRow, block.endRow);
    final leftLines = <String>[
      for (final row in slice)
        if (row.hasLeft) row.leftText!,
    ];

    final rightNos = [
      for (final row in slice)
        if (row.hasRight) row.rightLineNo!,
    ];

    final normalized = rightFileText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final rightLines = _splitLines(normalized);
    final hadTrailingNl =
        normalized.isNotEmpty && normalized.endsWith('\n');

    final int startIdx;
    final int endIdx;
    if (rightNos.isEmpty) {
      startIdx = _insertionIndex(result.rows, block.startRow);
      endIdx = startIdx;
    } else {
      startIdx = rightNos.reduce((a, b) => a < b ? a : b) - 1;
      endIdx = rightNos.reduce((a, b) => a > b ? a : b);
    }

    final out = <String>[
      ...rightLines.sublist(0, startIdx),
      ...leftLines,
      ...rightLines.sublist(endIdx),
    ];
    if (out.isEmpty) return '';
    final body = out.join('\n');
    return hadTrailingNl ? '$body\n' : body;
  }
}

/// 0-based index into right file lines where a pure-delete block inserts.
int _insertionIndex(List<DiffRow> rows, int blockStart) {
  for (var i = blockStart - 1; i >= 0; i--) {
    final row = rows[i];
    if (row.hasRight) return row.rightLineNo!;
  }
  return 0;
}

/// Matches [diff_engine.dart] line splitting so apply aligns with diff rows.
List<String> _splitLines(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  if (lines.length > 1 && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}
