/// Locates pasted full-screen TUI input on the visible terminal grid and tests
/// whether staged prompt text is still at that anchor after CR.
///
/// Grid reads must follow [TerminalScreenProbeController.syncDisplayGrid] — PTY damage is
/// applied on post-frame drains, so a stale mirror misses pasted CJK text even
/// when the on-screen painter already shows it.
import 'fullscreen_cr_ack_config.dart';
import 'pty_automation_needle.dart';

abstract interface class TerminalScreenGrid {
  int get rows;
  int get columns;
  int codepointAt(int row, int col);
  int flagsAt(int row, int col);
}

/// Screen position of a staged prompt substring; the [needle] may continue onto
/// following rows via soft wrap.
class FullscreenPromptAnchor {
  const FullscreenPromptAnchor({
    required this.row,
    required this.startCol,
    required this.needle,
  });

  final int row;
  final int startCol;

  /// Distinctive substring starting at [row] and [startCol]; may continue onto
  /// following rows via soft wrap.
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
/// Search tries each column start on every row; a match may consume subsequent
/// rows when the needle continues past a soft wrap.
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

/// Claude Code hides long pastes behind `[Pasted text #N +M lines]` chrome.
///
/// Body text is absent from the grid, so [locateFullscreenPromptNeedle] on the
/// original paste fails — treat this composer chrome as paste ACK instead.
FullscreenPromptAnchor? locateClaudeCollapsedPasteNeedle(
  TerminalScreenGrid grid, {
  int scanRows = 8,
  String? composerPrefix,
  int composerAboveSlack = fullscreenComposerLocateAboveSlack,
}) {
  final rows = grid.rows;
  if (rows == 0 || grid.columns == 0) return null;
  final windowStart = (rows - scanRows).clamp(0, rows - 1);
  final searchStart = _composerLocateStartRow(
    grid,
    windowStart: windowStart,
    scanRows: scanRows,
    composerPrefix: composerPrefix,
    composerAboveSlack: composerAboveSlack,
  );
  for (var r = rows - 1; r >= searchStart; r--) {
    final rowText = _logicalRowText(grid, r);
    final marker = PtyAutomationNeedle.collapsedPasteNeedle(rowText);
    if (marker == null) continue;
    final startCol = _findNeedleStartCol(grid, r, marker.runes.toList());
    if (startCol >= 0) {
      return FullscreenPromptAnchor(row: r, startCol: startCol, needle: marker);
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

/// True when the bottommost composer chrome row is prefix-only (no staged body).
///
/// Returns false when [composerPrefix] is empty or no composer row is found —
/// callers must not treat "unknown" as empty.
bool isComposerChromeEmpty(
  TerminalScreenGrid grid, {
  required String composerPrefix,
  int scanRows = 24,
}) {
  final prefix = composerPrefix.trim();
  if (prefix.isEmpty) return false;
  final row = bottomComposerChromeRow(grid, prefix, scanRows: scanRows);
  if (row == null) return false;
  final text = _logicalRowText(grid, row).trimLeft();
  if (!text.startsWith(prefix)) return false;
  return text.substring(prefix.length).trim().isEmpty;
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

/// True when [anchor.needle] still occupies the same cells starting at
/// [anchor.row]; the needle may occupy cells on [anchor.row] and following
/// soft-wrapped rows.
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
  var r = row;
  var col = startCol;
  // After a soft wrap, leading indent is chrome and word-break spaces in the
  // needle may not appear as grid cells — collapse them until content.
  var collapseWrapSpaces = false;
  for (var i = 0; i < needleRunes.length; i++) {
    final cp = needleRunes[i];
    var wrapped = false;
    while (true) {
      if (r >= grid.rows) return false;
      col = _skipWideSpacers(grid, r, col);
      if (col < grid.columns && !_rowRemainderIsPadding(grid, r, col)) {
        break;
      }
      // Soft-wrap before comparing this rune.
      // Padding at end of row triggers wrap before comparing the current
      // needle rune (trailing spaces are not consumed as needle content
      // unless the matcher is still on a content cell).
      r += 1;
      col = 0;
      if (r >= grid.rows) return false;
      if (!_rowHasNonSpaceContent(grid, r) && cp != 0x20) return false;
      // Claude / other TUIs indent wrapped composer lines past the prompt
      // prefix. Leading spaces are chrome, not paste content.
      col = _skipLeadingPadding(grid, r);
      wrapped = true;
    }
    if (wrapped) collapseWrapSpaces = true;
    if (cp == 0x20 && collapseWrapSpaces) {
      final gridCp = col < grid.columns ? grid.codepointAt(r, col) : 0;
      if (gridCp != 0 && gridCp != 0x20) {
        continue;
      }
    }
    collapseWrapSpaces = false;
    if (col >= grid.columns || grid.codepointAt(r, col) != cp) return false;
    col = _advancePastCell(grid, r, col);
  }
  return true;
}

bool _rowRemainderIsPadding(TerminalScreenGrid grid, int row, int fromCol) {
  for (var c = fromCol; c < grid.columns; c++) {
    if (_isWideSpacer(grid, row, c)) continue;
    final cp = grid.codepointAt(row, c);
    if (cp != 0 && cp != 0x20) return false;
  }
  return true;
}

bool _rowHasNonSpaceContent(TerminalScreenGrid grid, int row) {
  for (var c = 0; c < grid.columns; c++) {
    if (_isWideSpacer(grid, row, c)) continue;
    final cp = grid.codepointAt(row, c);
    if (cp != 0 && cp != 0x20) return true;
  }
  return false;
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

/// Advances past leading empty / space cells on a soft-wrapped continuation row.
int _skipLeadingPadding(TerminalScreenGrid grid, int row) {
  var col = 0;
  while (col < grid.columns) {
    col = _skipWideSpacers(grid, row, col);
    if (col >= grid.columns) break;
    final cp = grid.codepointAt(row, col);
    if (cp != 0 && cp != 0x20) break;
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
