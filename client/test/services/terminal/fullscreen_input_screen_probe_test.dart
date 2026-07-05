import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/fullscreen_input_screen_probe.dart';

void main() {
  test('locateNeedle finds bottommost row match', () {
    final grid = _FakeGrid.fromRows([
      'agent output above',
      '> 和你的队员打个招呼吧    ',
    ]);
    final anchor = locateFullscreenPromptNeedle(grid, '和你的队员打个招呼吧');
    expect(anchor, isNotNull);
    expect(anchor!.row, 1);
    expect(anchor.startCol, 2);
  });

  test('locateNeedle matches CJK with wide-char spacer columns', () {
    final grid = _FakeGrid.wideCjkRow(
      row: 1,
      prefix: '> ',
      text: '和你的队员打个招呼吧',
    );
    final anchor = locateFullscreenPromptNeedle(grid, '和你的队员打个招呼吧');
    expect(anchor, isNotNull);
    expect(anchor!.row, 1);
    expect(anchor.startCol, 2);
    expect(isFullscreenPromptAtAnchor(grid, anchor), isTrue);
  });

  test('isAtAnchor true while staged, false after input cleared', () {
    final grid = _FakeGrid.fromRows([
      'history',
      '> 和你的队员打个招呼吧    ',
    ]);
    final anchor = locateFullscreenPromptNeedle(grid, '和你的队员打个招呼吧')!;
    expect(isFullscreenPromptAtAnchor(grid, anchor), isTrue);

    grid.rowsData[1] =
        '>                         '.padRight(grid.columns).codeUnits;
    grid.flagsData[1] = List.filled(grid.columns, 0);
    expect(isFullscreenPromptAtAnchor(grid, anchor), isFalse);
  });

  test('isAtAnchor false when same text moved to transcript row above', () {
    final grid = _FakeGrid.fromRows([
      '你和你的队员打个招呼吧',
      '>                         ',
    ]);
    final anchor = const FullscreenPromptAnchor(
      row: 1,
      startCol: 2,
      needle: '和你的队员打个招呼吧',
    );
    expect(isFullscreenPromptAtAnchor(grid, anchor), isFalse);
  });

  test('captureBottomInputAnchor spans trimmed bottom row', () {
    final grid = _FakeGrid.fromRows([
      'noise',
      '   staged doorbell text   ',
    ]);
    final anchor = captureBottomInputAnchor(grid);
    expect(anchor, isNotNull);
    expect(anchor!.needle, 'staged doorbell text');
    expect(anchor.row, 1);
    expect(anchor.startCol, 3);
  });
}

final class _FakeGrid implements TerminalScreenGrid {
  _FakeGrid(this.rowsData, this.flagsData);

  factory _FakeGrid.fromRows(List<String> lines) {
    final maxCols = lines.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    final rows = lines
        .map((l) => l.padRight(maxCols, ' ').codeUnits.toList())
        .toList();
    final flags = List.generate(
      rows.length,
      (_) => List<int>.filled(maxCols, 0),
    );
    return _FakeGrid(rows, flags);
  }

  /// One CJK glyph + one wide-spacer column (mirrors alacritty mirror grid).
  factory _FakeGrid.wideCjkRow({
    required int row,
    required String prefix,
    required String text,
  }) {
    final prefixUnits = prefix.codeUnits;
    final textRunes = text.runes.toList();
    final width = prefixUnits.length + textRunes.length * 2;
    final codepoints = List<int>.filled(width, 0x20);
    final flags = List<int>.filled(width, 0);

    for (var i = 0; i < prefixUnits.length; i++) {
      codepoints[i] = prefixUnits[i];
    }

    var col = prefixUnits.length;
    for (final cp in textRunes) {
      codepoints[col] = cp;
      flags[col + 1] = 1 << 5; // wide spacer
      col += 2;
    }

    final rows = <List<int>>[];
    final flagRows = <List<int>>[];
    for (var r = 0; r <= row; r++) {
      if (r == row) {
        rows.add(codepoints);
        flagRows.add(flags);
      } else {
        rows.add(List<int>.filled(width, 0x20));
        flagRows.add(List<int>.filled(width, 0));
      }
    }
    return _FakeGrid(rows, flagRows);
  }

  final List<List<int>> rowsData;
  final List<List<int>> flagsData;

  @override
  int get rows => rowsData.length;

  @override
  int get columns => rowsData.isEmpty ? 0 : rowsData.first.length;

  @override
  int codepointAt(int row, int col) {
    if (row < 0 || row >= rows || col < 0 || col >= columns) return 0;
    return rowsData[row][col];
  }

  @override
  int flagsAt(int row, int col) {
    if (row < 0 || row >= rows || col < 0 || col >= columns) return 0;
    return flagsData[row][col];
  }
}
