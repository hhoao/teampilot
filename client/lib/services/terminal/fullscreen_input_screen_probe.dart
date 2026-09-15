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

/// Locate [needle] in the **cursor input zone**: the cursor row plus a small
/// window above it (multi-line paste tail). The cursor is the TUI's own input
/// position, so this avoids matching a stray character in a status/footer row
/// *below* the input box (e.g. a single "1" matching "17%" in the status line).
///
/// Falls back to the bottom-[scanRows] search when the grid has no cursor.
FullscreenPromptAnchor? locateNeedleInCursorZone(
  TerminalScreenGrid grid,
  String needle,
) {
  if (needle.isEmpty) return null;
  final rows = grid.rows;
  if (rows == 0 || grid.columns == 0) return null;
  final cursor = grid.cursorRow;
  if (cursor < 0) return locateFullscreenPromptNeedle(grid, needle);
  final top = _cursorZoneTop(grid, cursor);
  final runes = needle.runes.toList();
  for (var r = cursor; r >= top; r--) {
    final startCol = _findNeedleStartCol(grid, r, runes);
    if (startCol >= 0) {
      return FullscreenPromptAnchor(row: r, startCol: startCol, needle: needle);
    }
  }
  return null;
}

/// Collapsed-paste chrome (`[Pasted ~N lines]`) in the cursor input zone.
FullscreenPromptAnchor? locateCollapsedPasteInCursorZone(
  TerminalScreenGrid grid,
) {
  final rows = grid.rows;
  if (rows == 0 || grid.columns == 0) return null;
  final cursor = grid.cursorRow;
  if (cursor < 0) return locateCollapsedPasteNeedle(grid);
  final top = _cursorZoneTop(grid, cursor);
  for (var r = cursor; r >= top; r--) {
    final marker = PtyAutomationNeedle.collapsedPasteNeedle(
      _logicalRowText(grid, r),
    );
    if (marker == null) continue;
    final startCol = _findNeedleStartCol(grid, r, marker.runes.toList());
    if (startCol >= 0) {
      return FullscreenPromptAnchor(row: r, startCol: startCol, needle: marker);
    }
  }
  return null;
}

/// Top row of the cursor input zone: walk up from [cursor] through contiguous
/// non-blank rows, capped at [cursorZoneWrapSlack] rows.
int _cursorZoneTop(TerminalScreenGrid grid, int cursor) {
  var top = cursor;
  for (var i = 0; i < cursorZoneWrapSlack && top > 0; i++) {
    if (_rowIsBlank(grid, top - 1)) break;
    top -= 1;
  }
  return top;
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
  return _matchesNeedleAt(grid, anchor.row, anchor.startCol, needleRunes) >= 0;
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
/// cursor row, plus a small window above it where a multi-line paste's tail may
/// start. Rows *below* the cursor are excluded so a status/footer character
/// cannot be mistaken for staged input.
bool needleStaysInCursorZone(
  TerminalScreenGrid grid,
  String needle,
) {
  final rows = grid.rows;
  final cursor = grid.cursorRow;
  if (rows == 0 || cursor < 0) return false;
  final runes = needle.runes.toList();
  final top = _cursorZoneTop(grid, cursor);
  for (var r = top; r <= cursor; r++) {
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
  List<int> needleRunes,
) {
  for (var start = 0; start < grid.columns; start++) {
    if (_isWideSpacer(grid, row, start)) continue;
    final firstMatchedCol = _matchesNeedleAt(grid, row, start, needleRunes);
    if (firstMatchedCol >= 0) return firstMatchedCol;
  }
  return -1;
}

/// Matches [needleRunes] starting at [row]/[startCol], skipping TUI chrome on
/// mismatch. Returns the column where the needle's FIRST content cell matched
/// (so anchors point at real text, not a leading chrome glyph), or `-1`.
int _matchesNeedleAt(
  TerminalScreenGrid grid,
  int startRow,
  int startCol,
  List<int> needleRunes,
) {
  var r = startRow;
  var col = startCol;
  // After a soft wrap, leading indent is chrome and word-break spaces in the
  // needle may not appear as grid cells — collapse them until content.
  var collapseWrapSpaces = false;
  var firstRow = true;
  var rowMatched = 0;
  var firstContentCol = -1;
  for (var i = 0; i < needleRunes.length; i++) {
    final cp = needleRunes[i];
    var wrapped = false;
    while (true) {
      if (r >= grid.rows) return -1;
      col = _skipWideSpacers(grid, r, col);
      if (col < grid.columns && !_rowRemainderIsPadding(grid, r, col)) {
        break;
      }
      // Soft-wrap before comparing this rune. Padding at end of row triggers
      // wrap before comparing the current needle rune.
      r += 1;
      col = 0;
      wrapped = true;
      if (r >= grid.rows) return -1;
      // A continuation row that matched zero needle characters is chrome/
      // border (or blank); the needle must not stitch across it.
      if (!firstRow && rowMatched == 0) return -1;
      firstRow = false;
      rowMatched = 0;
      if (!_rowHasNonSpaceContent(grid, r) && cp != 0x20) return -1;
    }
    if (wrapped) collapseWrapSpaces = true;
    if (cp == 0x20 && collapseWrapSpaces) {
      final gridCp = col < grid.columns ? grid.codepointAt(r, col) : 0;
      if (gridCp != 0 && gridCp != 0x20) {
        continue;
      }
    }
    collapseWrapSpaces = false;
    // Exact match consumes the cell and counts toward the row. On a mismatch
    // a NON letter/digit grid cell (space, TUI marker, punctuation, box
    // border) is painted chrome — step over it and retry the same rune. A
    // letter/digit cell (incl. CJK) that differs from the needle fails: real
    // content is never skipped.
    while (true) {
      if (col >= grid.columns) return -1;
      final gridCp = grid.codepointAt(r, col);
      if (gridCp == cp) {
        if (firstContentCol < 0) firstContentCol = col;
        rowMatched += 1;
        col = _advancePastCell(grid, r, col);
        break;
      }
      if (!_isContentCharacter(gridCp)) {
        col = _advancePastCell(grid, r, col);
        continue;
      }
      return -1;
    }
  }
  return firstContentCol;
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

/// Letter or digit (Unicode, incl. CJK) — real paste content. Anything else
/// that mismatches the needle may be TUI-painted chrome to step over.
final RegExp _contentChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _isContentCharacter(int cp) =>
    _contentChar.hasMatch(String.fromCharCodes([cp]));

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
  int get cursorRow => (_grid.cursorRow as int?) ?? -1;

  @override
  int codepointAt(int row, int col) => _grid.codepointAt(row, col) as int;

  @override
  int flagsAt(int row, int col) => _grid.flagsAt(row, col) as int;
}
