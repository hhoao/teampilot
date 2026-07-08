/// Locates pasted full-screen TUI input on the visible terminal grid and tests
/// whether staged prompt text is still at that anchor after CR.
///
/// Grid reads must follow [TerminalScreenProbeController.syncDisplayGrid] — PTY damage is
/// applied on post-frame drains, so a stale mirror misses pasted CJK text even
/// when the on-screen painter already shows it.
import 'fullscreen_cr_ack_config.dart';

abstract interface class TerminalScreenGrid {
  int get rows;
  int get columns;
  int codepointAt(int row, int col);
  int flagsAt(int row, int col);
}

/// Screen position of a staged prompt substring (one row, column-aligned).
class FullscreenPromptAnchor {
  const FullscreenPromptAnchor({
    required this.row,
    required this.startCol,
    required this.needle,
  });

  final int row;
  final int startCol;

  /// Distinctive substring located on [row] at [startCol].
  final String needle;

  @override
  String toString() =>
      'FullscreenPromptAnchor(row=$row, col=$startCol, needle=$needle)';
}

// Mirror flutter_alacritty `cell_flags.dart` / rust `engine.rs`.
const int _flagWideSpacer = 1 << 5;

/// Rows above the bottom composer chrome to search for wrapped multi-line paste
/// (cursor doorbell above `→`, etc.).
const int fullscreenComposerLocateAboveSlack = 12;

/// Bottom-up search for [needle] in the last [scanRows] visible rows.
///
/// When [composerPrefix] is set, only rows at or above the bottommost composer
/// chrome row (within [composerAboveSlack]) are searched so stale transcript
/// higher on a tall viewport is not mistaken for staged input.
FullscreenPromptAnchor? locateFullscreenPromptNeedle(
  TerminalScreenGrid grid,
  String needle, {
  int scanRows = 8,
  String? composerPrefix,
  int composerAboveSlack = fullscreenComposerLocateAboveSlack,
}) {
  if (needle.isEmpty) return null;
  final rows = grid.rows;
  if (rows == 0 || grid.columns == 0) return null;

  final needleRunes = needle.runes.toList();
  final windowStart = (rows - scanRows).clamp(0, rows - 1);
  final searchStart = _composerLocateStartRow(
    grid,
    windowStart: windowStart,
    scanRows: scanRows,
    composerPrefix: composerPrefix,
    composerAboveSlack: composerAboveSlack,
  );
  for (var r = rows - 1; r >= searchStart; r--) {
    final startCol = _findNeedleStartCol(grid, r, needleRunes);
    if (startCol >= 0) {
      return FullscreenPromptAnchor(row: r, startCol: startCol, needle: needle);
    }
  }
  return null;
}

/// Bottom-most mirror row whose trimmed text starts with [composerPrefix].
int? bottomComposerChromeRow(
  TerminalScreenGrid grid,
  String composerPrefix, {
  int scanRows = 8,
}) {
  final prefix = composerPrefix.trim();
  if (prefix.isEmpty) return null;
  final rows = grid.rows;
  if (rows == 0) return null;
  final startRow = (rows - scanRows).clamp(0, rows - 1);
  for (var r = rows - 1; r >= startRow; r--) {
    if (_rowStartsWith(grid, r, prefix)) return r;
  }
  return null;
}

int _composerLocateStartRow(
  TerminalScreenGrid grid, {
  required int windowStart,
  required int scanRows,
  String? composerPrefix,
  required int composerAboveSlack,
}) {
  final prefix = composerPrefix?.trim();
  if (prefix == null || prefix.isEmpty) return windowStart;
  final composerRow = bottomComposerChromeRow(
    grid,
    prefix,
    scanRows: scanRows,
  );
  if (composerRow == null) return windowStart;
  return (composerRow - composerAboveSlack).clamp(windowStart, grid.rows - 1);
}

/// True when [anchor.needle] still occupies the same cells on [anchor.row].
bool isFullscreenPromptAtAnchor(
  TerminalScreenGrid grid,
  FullscreenPromptAnchor anchor,
) {
  final needleRunes = anchor.needle.runes.toList();
  return _matchesNeedleAt(grid, anchor.row, anchor.startCol, needleRunes);
}

/// Whether a CR submit is complete per [config].
bool isFullscreenPromptSubmitted(
  TerminalScreenGrid grid,
  FullscreenPromptAnchor anchor, {
  required FullscreenCrAckStrategy strategy,
  String? composerPrefix,
  int scanRows = 24,
}) {
  switch (strategy) {
    case FullscreenCrAckStrategy.timed:
      return true;
    case FullscreenCrAckStrategy.anchorCellClears:
      return !isFullscreenPromptAtAnchor(grid, anchor);
    case FullscreenCrAckStrategy.composerMovesDown:
      if (!isFullscreenPromptAtAnchor(grid, anchor)) return true;
      final prefix = composerPrefix?.trim();
      if (prefix == null || prefix.isEmpty) return false;
      return _hasComposerRowBelow(
        grid,
        anchor.row,
        composerPrefix: prefix,
        scanRows: scanRows,
      );
  }
}

bool _hasComposerRowBelow(
  TerminalScreenGrid grid,
  int aboveRow, {
  required String composerPrefix,
  int scanRows = 24,
}) {
  final rows = grid.rows;
  if (rows == 0 || aboveRow >= rows - 1) return false;
  final startRow = (rows - scanRows).clamp(0, rows - 1);
  for (var r = rows - 1; r > aboveRow; r--) {
    if (r < startRow) break;
    if (_rowStartsWith(grid, r, composerPrefix)) return true;
  }
  return false;
}

bool _rowStartsWith(TerminalScreenGrid grid, int row, String prefix) {
  final text = _logicalRowText(grid, row).trimLeft();
  return text.startsWith(prefix);
}

/// Debug helper: logical text of the bottom [scanRows] (for ACK miss logs).
String describeProbeWindow(TerminalScreenGrid grid, {int scanRows = 8}) {
  final rows = grid.rows;
  if (rows == 0) return '<empty grid>';
  final startRow = (rows - scanRows).clamp(0, rows - 1);
  final sb = StringBuffer();
  for (var r = startRow; r < rows; r++) {
    sb.writeln('r$r: "${_logicalRowText(grid, r)}"');
  }
  return sb.toString().trimRight();
}

int _findNeedleStartCol(
  TerminalScreenGrid grid,
  int row,
  List<int> needleRunes,
) {
  for (var start = 0; start < grid.columns; start++) {
    if (_isWideSpacer(grid, row, start)) continue;
    if (_matchesNeedleAt(grid, row, start, needleRunes)) return start;
  }
  return -1;
}

bool _matchesNeedleAt(
  TerminalScreenGrid grid,
  int row,
  int startCol,
  List<int> needleRunes,
) {
  var col = startCol;
  for (final cp in needleRunes) {
    col = _skipWideSpacers(grid, row, col);
    if (col >= grid.columns) return false;
    if (grid.codepointAt(row, col) != cp) return false;
    col = _advancePastCell(grid, row, col);
  }
  return true;
}

(int start, int endCol)? _trimmedLogicalBounds(
  TerminalScreenGrid grid,
  int row,
) {
  int? start;
  var end = -1;
  for (var col = 0; col < grid.columns; col++) {
    if (_isWideSpacer(grid, row, col)) continue;
    final cp = grid.codepointAt(row, col);
    if (cp == 0 || cp == 0x20) continue;
    start ??= col;
    end = col;
    if (col + 1 < grid.columns && _isWideSpacer(grid, row, col + 1)) {
      end = col + 1;
    }
  }
  if (start == null || end < start) return null;
  return (start, end);
}

String _logicalText(
  TerminalScreenGrid grid,
  int row,
  int startCol,
  int endCol,
) {
  final sb = StringBuffer();
  for (var col = startCol; col <= endCol; col++) {
    if (_isWideSpacer(grid, row, col)) continue;
    final cp = grid.codepointAt(row, col);
    if (cp == 0) continue;
    sb.writeCharCode(cp);
  }
  return sb.toString();
}

String _logicalRowText(TerminalScreenGrid grid, int row) {
  final bounds = _trimmedLogicalBounds(grid, row);
  if (bounds == null) return '';
  return _logicalText(grid, row, bounds.$1, bounds.$2);
}

bool _isWideSpacer(TerminalScreenGrid grid, int row, int col) =>
    (grid.flagsAt(row, col) & _flagWideSpacer) != 0;

int _skipWideSpacers(TerminalScreenGrid grid, int row, int col) {
  while (col < grid.columns && _isWideSpacer(grid, row, col)) {
    col++;
  }
  return col;
}

int _advancePastCell(TerminalScreenGrid grid, int row, int col) {
  var next = col + 1;
  if (next < grid.columns && _isWideSpacer(grid, row, next)) {
    next++;
  }
  return next;
}

/// Wraps flutter_alacritty's grid view for [TerminalScreenGrid] probes.
TerminalScreenGrid terminalScreenGrid(dynamic grid) => _GridViewAdapter(grid);

final class _GridViewAdapter implements TerminalScreenGrid {
  _GridViewAdapter(this._grid);
  final dynamic _grid;

  @override
  int get rows => _grid.rows as int;

  @override
  int get columns => _grid.columns as int;

  @override
  int codepointAt(int row, int col) => _grid.codepointAt(row, col) as int;

  @override
  int flagsAt(int row, int col) => _grid.flagsAt(row, col) as int;
}
