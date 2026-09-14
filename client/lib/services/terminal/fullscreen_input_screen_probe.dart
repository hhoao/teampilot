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

  /// Row of the terminal cursor (the live input position for a full-screen
  /// TUI). This is the most reliable "where is the composer" signal — it does
  /// not depend on a per-CLI prefix character and is not confused by status
  /// rows that reuse the same glyph (opencode's `┃ Build`). `-1` when unknown.
  int get cursorRow;
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

/// Bottom-up search for [needle] in the last [scanRows] visible rows.
///
/// Bottom-up search for [needle] in the last [scanRows] visible rows (the
/// bottom input zone). Search tries each column start on every row; a match may
/// consume subsequent rows when the needle continues past a soft wrap.
///
/// The input box is pinned at the bottom of full-screen TUIs, so restricting the
/// search to the bottom [scanRows] rows separates staged input from higher
/// transcript — no per-CLI prefix character is needed.
FullscreenPromptAnchor? locateFullscreenPromptNeedle(
  TerminalScreenGrid grid,
  String needle, {
  int scanRows = 8,
}) {
  if (needle.isEmpty) return null;
  final rows = grid.rows;
  if (rows == 0 || grid.columns == 0) return null;

  final needleRunes = needle.runes.toList();
  final windowStart = (rows - scanRows).clamp(0, rows - 1);
  final searchStart = windowStart;
  for (var r = rows - 1; r >= searchStart; r--) {
    final startCol = _findNeedleStartCol(grid, r, needleRunes);
    if (startCol >= 0) {
      return FullscreenPromptAnchor(row: r, startCol: startCol, needle: needle);
    }
  }
  return null;
}

/// Full-screen TUIs (Claude Code, opencode, etc.) hide long pastes behind
/// `[Pasted text #N +M lines]` or `[Pasted ~N lines]` chrome.
///
/// Body text is absent from the grid, so [locateFullscreenPromptNeedle] on the
/// original paste fails — treat this composer chrome as paste ACK instead,
/// searched in the same bottom [scanRows] input zone.
FullscreenPromptAnchor? locateCollapsedPasteNeedle(
  TerminalScreenGrid grid, {
  int scanRows = 8,
}) {
  final rows = grid.rows;
  if (rows == 0 || grid.columns == 0) return null;
  final windowStart = (rows - scanRows).clamp(0, rows - 1);
  final searchStart = windowStart;
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

bool isFullscreenPromptSubmitted(
  TerminalScreenGrid grid,
  FullscreenPromptAnchor anchor, {
  required FullscreenCrAckStrategy strategy,
  int scanRows = 24,
}) {
  switch (strategy) {
    case FullscreenCrAckStrategy.timed:
      return true;
    case FullscreenCrAckStrategy.anchorCellClears:
    case FullscreenCrAckStrategy.composerMovesDown:
      // Cursor-based verdict: submitted iff the needle is no longer held by the
      // input box (cursor row and its soft-wrap continuation rows). The cursor
      // is the TUI's own input position — no per-CLI prefix, and not confused
      // by status rows that reuse the composer glyph (`┃ Build`).
      return !needleStaysInCursorZone(grid, anchor.needle);
  }
}

/// Rows above the cursor still counted as part of the input box: a multi-line
/// paste ends with the cursor on the last line, and the needle is the paste's
/// trailing 40 chars, which may start one or more rows above the cursor.
const int cursorZoneWrapSlack = 4;

/// True while [needle] still occupies the input box around the cursor: the
/// cursor row, any row below it forming the box (wrap continuation), or a small
/// window above the cursor where a multi-line paste's tail may start.
///
/// The box is bounded by blank rows: above, the contiguous non-blank run is
/// walked up to [cursorZoneWrapSlack] rows; below, the run ends at the first
/// blank row.
bool needleStaysInCursorZone(
  TerminalScreenGrid grid,
  String needle,
) {
  final rows = grid.rows;
  final cursor = grid.cursorRow;
  if (rows == 0 || cursor < 0) return false;
  final runes = needle.runes.toList();

  var top = cursor;
  for (var i = 0; i < cursorZoneWrapSlack && top > 0; i++) {
    if (_rowIsBlank(grid, top - 1)) break;
    top -= 1;
  }
  var bottom = cursor;
  for (var r = cursor + 1; r < rows; r++) {
    if (_rowIsBlank(grid, r)) break;
    bottom = r;
  }

  for (var r = top; r <= bottom; r++) {
    if (_findNeedleStartCol(grid, r, runes) >= 0) return true;
  }
  return false;
}

bool _rowIsBlank(TerminalScreenGrid grid, int row) {
  if (row < 0 || row >= grid.rows) return true;
  for (var c = 0; c < grid.columns; c++) {
    if (_isWideSpacer(grid, row, c)) continue;
    final cp = grid.codepointAt(row, c);
    if (cp != 0 && cp != 0x20) return false;
  }
  return true;
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
  List<int> needleRunes, {
  String? composerPrefix,
}) {
  for (var start = 0; start < grid.columns; start++) {
    if (_isWideSpacer(grid, row, start)) continue;
    if (_matchesNeedleAt(
      grid,
      row,
      start,
      needleRunes,
      composerPrefix: composerPrefix,
    ))
      return start;
  }
  return -1;
}

bool _matchesNeedleAt(
  TerminalScreenGrid grid,
  int row,
  int startCol,
  List<int> needleRunes, {
  String? composerPrefix,
}) {
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
      col = _skipLeadingPadding(grid, r, composerPrefix: composerPrefix);
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
int _skipLeadingPadding(
  TerminalScreenGrid grid,
  int row, {
  String? composerPrefix,
}) {
  var col = 0;
  // OpenCode (and potentially other TUIs) repeats its composer prefix char on
  // every wrapped continuation line — skip it just like space/null padding.
  final prefixCp = (composerPrefix != null && composerPrefix.trim().isNotEmpty)
      ? composerPrefix.trim().runes.first
      : null;
  while (col < grid.columns) {
    col = _skipWideSpacers(grid, row, col);
    if (col >= grid.columns) break;
    final cp = grid.codepointAt(row, col);
    if (cp != 0 && cp != 0x20 && (prefixCp == null || cp != prefixCp)) break;
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
  int get cursorRow => (_grid.cursorRow as int?) ?? -1;

  @override
  int codepointAt(int row, int col) => _grid.codepointAt(row, col) as int;

  @override
  int flagsAt(int row, int col) => _grid.flagsAt(row, col) as int;
}
