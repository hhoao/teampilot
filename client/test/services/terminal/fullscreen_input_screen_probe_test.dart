import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/terminal_composer_region.dart';
import 'package:teampilot/services/terminal/fullscreen_cr_ack_config.dart';
import 'package:teampilot/services/terminal/fullscreen_input_screen_probe.dart';
import 'package:teampilot/services/terminal/pty_automation_needle.dart';

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

  test('locateNeedle finds teammate-bus doorbell above status chrome', () {
    final grid = _FakeGrid.fromRows([
      '[teammate-bus] You have unread teammate messages',
      '⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents',
    ]);
    final anchor = locateFullscreenPromptNeedle(grid, '[teammate-bus]');
    expect(anchor, isNotNull);
    expect(anchor!.needle, '[teammate-bus]');
    expect(anchor.row, 0);
  });

  test('locateCollapsedPasteNeedle finds Claude Code paste chrome', () {
    final lines = List<String>.filled(10, '');
    lines[7] = '❯ [Pasted text #3 +17 lines]';
    lines[9] = 'paste again to expand';
    final grid = _FakeGrid.fromRows(lines);

    final anchor = locateCollapsedPasteNeedle(
      grid,
      scanRows: 10,
      composerPrefix: '❯',
    );
    expect(anchor, isNotNull);
    expect(anchor!.needle, '[Pasted text #3 +17 lines]');
    expect(anchor.row, 7);
  });

  test('locateCollapsedPasteNeedle finds opencode paste chrome', () {
    final lines = List<String>.filled(10, '');
    lines[7] = '┃  [Pasted ~152 lines]';
    lines[9] = '';
    final grid = _FakeGrid.fromRows(lines);

    final anchor = locateCollapsedPasteNeedle(
      grid,
      scanRows: 10,
      composerPrefix: '┃',
    );
    expect(anchor, isNotNull);
    expect(anchor!.needle, '[Pasted ~152 lines]');
    expect(anchor.row, 7);
  });

  test('locateCollapsedPasteNeedle finds Codex paste chrome', () {
    final lines = List<String>.filled(10, '');
    lines[7] = '› [Pasted Content 29390 chars]';
    lines[9] = '';
    final grid = _FakeGrid.fromRows(lines);

    final anchor = locateCollapsedPasteNeedle(
      grid,
      scanRows: 10,
      composerPrefix: '›',
    );
    expect(anchor, isNotNull);
    expect(anchor!.needle, '[Pasted Content 29390 chars]');
    expect(anchor.row, 7);
  });

  test('locateNeedle ignores stale transcript above composer slack window', () {
    final lines = List<String>.filled(24, '');
    lines[2] = '[teammate-bus] stale delivery in transcript';
    lines[22] = '→ Plan, search, build anything';
    final grid = _FakeGrid.fromRows(lines);

    expect(
      locateFullscreenPromptNeedle(
        grid,
        '[teammate-bus]',
        scanRows: 24,
        composerPrefix: '→',
      ),
      isNull,
    );
    expect(
      locateFullscreenPromptNeedle(grid, '[teammate-bus]', scanRows: 24),
      isNotNull,
    );
  });

  test('locateNeedle finds wrapped paste above cursor composer chrome', () {
    final lines = List<String>.filled(24, '');
    lines[18] = '[teammate-bus] fresh doorbell paste';
    lines[22] = '→ Plan, search, build anything';
    final grid = _FakeGrid.fromRows(lines);

    final anchor = locateFullscreenPromptNeedle(
      grid,
      '[teammate-bus]',
      scanRows: 24,
      composerPrefix: '→',
    );
    expect(anchor, isNotNull);
    expect(anchor!.row, 18);
  });

  test('bottomComposerChromeRow finds lowest prefix row in scan window', () {
    final lines = List<String>.filled(8, '');
    lines[3] = '› older composer';
    lines[6] = '› active composer';
    final grid = _FakeGrid.fromRows(lines);

    expect(
      bottomComposerChromeRow(grid, '\u203a', scanRows: 8),
      6,
    );
  });

  test('isSubmitted true for composerMovesDown when prefix row appears below', () {
    final grid = _FakeGrid.fromRows([
      'codex output above',
      '› codex-probe-12345',
      'Working…',
      '› ',
    ]);
    final anchor = locateFullscreenPromptNeedle(grid, 'codex-probe-12345')!;
    expect(isFullscreenPromptAtAnchor(grid, anchor), isTrue);
    expect(
      isFullscreenPromptSubmitted(
        grid,
        anchor,
        strategy: FullscreenCrAckStrategy.composerMovesDown,
        composerPrefix: '\u203a',
        scanRows: 24,
      ),
      isTrue,
    );
  });

  test('isSubmitted false for composerMovesDown when no new composer below', () {
    final grid = _FakeGrid.fromRows([
      'codex output above',
      '› codex-probe-12345',
    ]);
    final anchor = locateFullscreenPromptNeedle(grid, 'codex-probe-12345')!;
    expect(
      isFullscreenPromptSubmitted(
        grid,
        anchor,
        strategy: FullscreenCrAckStrategy.composerMovesDown,
        composerPrefix: '\u203a',
        scanRows: 24,
      ),
      isFalse,
    );
  });

  test('isComposerChromeEmpty true for prefix-only cursor row', () {
    final grid = _FakeGrid.fromRows([
      'A',
      '→ ',
    ]);
    expect(
      isComposerChromeEmpty(grid, composerPrefix: '→', scanRows: 8),
      isTrue,
    );
  });

  test('isComposerChromeEmpty false when body follows prefix', () {
    final grid = _FakeGrid.fromRows(['→ A']);
    expect(
      isComposerChromeEmpty(grid, composerPrefix: '→', scanRows: 8),
      isFalse,
    );
  });

  test('isComposerChromeEmpty false when no composer row', () {
    final grid = _FakeGrid.fromRows(['just history']);
    expect(
      isComposerChromeEmpty(grid, composerPrefix: '→', scanRows: 8),
      isFalse,
    );
  });

  test('isComposerChromeEmpty true for codex prefix with trailing spaces', () {
    final grid = _FakeGrid.fromRows(['›     ']);
    expect(
      isComposerChromeEmpty(grid, composerPrefix: '\u203a', scanRows: 8),
      isTrue,
    );
  });

  test('locateNeedle finds soft-wrapped CJK tail across two rows', () {
    // Logical paste (no prefix in needle). Composer prefix only on first row.
    const line0 =
        '❯ 帮我估算一下这个需求的时间：分类分级系统接入银行统一身份认证体系，实现登录双因素认证（优先手机令牌方式），同时评估';
    const line1 = '是否支持 LDAP/AD 域认证作为标准登录方式，详细信息参考附件';
    const full =
        '帮我估算一下这个需求的时间：分类分级系统接入银行统一身份认证体系，实现登录双因素认证（优先手机令牌方式），同时评估是否支持 LDAP/AD 域认证作为标准登录方式，详细信息参考附件';
    final needle = full.substring(full.length - 40);
    // needle starts with "式），同时评估" which ends line0 and continues on line1.

    // columns must force the soft wrap used in fixtures: measure with wide=2.
    // Use a columns value that fits line0's cells exactly (no trailing content cell).
    final grid = _FakeGrid.wrappedWideLines(
      columns: _displayWidth(line0),
      lineTexts: [line0, line1],
    );

    final anchor = locateFullscreenPromptNeedle(grid, needle, scanRows: 8);
    expect(anchor, isNotNull, reason: 'needle spans soft wrap; single-row match misses');
    expect(anchor!.row, 0);
    expect(isFullscreenPromptAtAnchor(grid, anchor), isTrue);
  });

  test('locateNeedle does not stitch across blank row', () {
    final grid = _FakeGrid.fromRows([
      'AAAAUNIQUEPART',
      '              ', // padding-only
      'CONTINUATIONZZ',
    ]);
    expect(
      locateFullscreenPromptNeedle(grid, 'UNIQUEPARTCONTINUATIONZZ'),
      isNull,
    );
  });

  test('locateNeedle finds ASCII soft-wrapped needle across two rows', () {
    final grid = _FakeGrid.fromRows([
      '❯ hello_WORLD_PART',
      '_CONTINUES_HERE',
    ]);
    final anchor = locateFullscreenPromptNeedle(
      grid,
      'WORLD_PART_CONTINUES_HERE',
    );
    expect(anchor, isNotNull);
    expect(anchor!.row, 0);
  });

  test('locateNeedle matches flattened JSON closing braces across hard lines', () {
    // Cursor/Claude render hard newlines in pasted JSON as separate rows. The
    // automation needle flattens CR/LF to spaces; soft-wrap space collapse must
    // still locate the tail across those rows.
    final grid = _FakeGrid.fromRows([
      '→          }',
      '         }',
      '       }',
      '     }',
      '   ]',
      ' }',
    ]);
    final needle = PtyAutomationNeedle.forText('''
prefix
         }
        }
      }
    }
  ]
}''');
    expect(needle.contains('\n'), isFalse);
    final anchor = locateFullscreenPromptNeedle(grid, needle, scanRows: 8);
    expect(
      anchor,
      isNotNull,
      reason: 'flattened multiline JSON tail must ACK across hard line breaks',
    );
  });

  test('locateNeedle collapses needle spaces across indented soft wrap', () {
    // Wrap lands on the word-break space; continuation indent has MORE spaces
    // than the single space in the needle.
    final grid = _FakeGrid.fromRows([
      '❯ say hello',
      '     world_TAIL',
    ]);
    final anchor = locateFullscreenPromptNeedle(
      grid,
      'hello world_TAIL',
      scanRows: 8,
    );
    expect(
      anchor,
      isNotNull,
      reason: 'extra wrap indent must not consume needle word-break spaces',
    );
    expect(isFullscreenPromptAtAnchor(grid, anchor!), isTrue);
  });

  test('locateNeedle collapses multiple needle spaces after soft wrap', () {
    final grid = _FakeGrid.fromRows([
      '❯ say hello',
      '     world_TAIL',
    ]);
    final anchor = locateFullscreenPromptNeedle(
      grid,
      'hello   world_TAIL',
      scanRows: 8,
    );
    expect(anchor, isNotNull);
    expect(isFullscreenPromptAtAnchor(grid, anchor!), isTrue);
  });

  test('isAtAnchor false after clearing soft-wrapped staged cells', () {
    final grid = _FakeGrid.fromRows([
      '❯ hello_WORLD_PART',
      '_CONTINUES_HERE',
    ]);
    final anchor = locateFullscreenPromptNeedle(
      grid,
      'WORLD_PART_CONTINUES_HERE',
    )!;
    expect(isFullscreenPromptAtAnchor(grid, anchor), isTrue);

    grid.rowsData[0] = List.filled(grid.columns, 0x20);
    grid.rowsData[1] = List.filled(grid.columns, 0x20);
    expect(isFullscreenPromptAtAnchor(grid, anchor), isFalse);
  });

  group('locateComposerRegion', () {
    const opencodeSpec = FullscreenComposerRegionSpec(
      submitSemantics: ComposerSubmitSemantics.regionCleared,
      prefixes: ['\u2503'],
      border: ComposerBorderSpec(
        left: ['\u2503', '\u2502'],
        bottom: ['\u2580', '\u2500'],
        corner: ['\u2579', '\u2570', '\u2514'],
      ),
    );

    test('finds opencode box rectangle from left border + bottom border', () {
      final lines = List<String>.filled(10, '');
      lines[6] = '                    \u2503';
      lines[7] = '                    \u2503  1';
      lines[8] = '                    \u2503  Build \u00b7 max';
      lines[9] = '                    \u2579\u2580\u2580\u2580\u2580';
      final grid = _FakeGrid.fromRows(lines);

      final region = locateComposerRegion(grid, opencodeSpec, scanRows: 10);
      expect(region, isNotNull);
      expect(region!.leftCol, 20);
      expect(region.bottomRow, 9);
      expect(region.topRow, lessThanOrEqualTo(6));
    });

    test('finds prefix-only region for claude', () {
      final lines = List<String>.filled(8, '');
      lines[5] = '\u276f  hello';
      lines[6] = '\u276f ';
      final grid = _FakeGrid.fromRows(lines);
      const spec = FullscreenComposerRegionSpec(
        submitSemantics: ComposerSubmitSemantics.regionCleared,
        prefixes: ['\u276f'],
      );

      final region = locateComposerRegion(grid, spec, scanRows: 8);
      expect(region, isNotNull);
      expect(region!.bottomRow, 6);
    });

    test('returns null when no prefix and no border', () {
      final grid = _FakeGrid.fromRows(['just transcript', 'more text']);
      const spec = FullscreenComposerRegionSpec(
        submitSemantics: ComposerSubmitSemantics.regionCleared,
        prefixes: ['\u276f'],
      );
      expect(locateComposerRegion(grid, spec, scanRows: 8), isNull);
    });

    test('regionContainsNeedle scopes a short needle inside the box', () {
      final lines = List<String>.filled(10, '');
      lines[6] = '                    \u2503';
      lines[7] = '                    \u2503  1';
      lines[8] = '                    \u2503';
      lines[9] = '                    \u2579\u2580\u2580\u2580';
      final grid = _FakeGrid.fromRows(lines);
      final region = locateComposerRegion(grid, opencodeSpec, scanRows: 10)!;

      expect(regionContainsNeedle(grid, region, '1'), isTrue,
          reason: 'staged "1" inside the box must ACK');
      expect(regionContainsNeedle(grid, region, '99'), isFalse);
    });

    test('regionContainsNeedle ignores the same digit in transcript', () {
      final lines = List<String>.filled(12, '');
      lines[2] = '          1          '; // transcript "1" above the box
      lines[9] = '                    \u2503';
      lines[10] = '                    \u2503';
      lines[11] = '                    \u2579\u2580\u2580\u2580';
      final grid = _FakeGrid.fromRows(lines);
      final region = locateComposerRegion(grid, opencodeSpec, scanRows: 12)!;

      expect(regionContainsNeedle(grid, region, '1'), isFalse,
          reason: 'transcript "1" must not count as staged input');
      expect(needleAppearsOutsideRegion(grid, region, '1', scanRows: 12), isTrue);
    });

    test('isComposerRegionEmpty true when box interior blank', () {
      final lines = List<String>.filled(10, '');
      lines[7] = '                    \u2503';
      lines[9] = '                    \u2579\u2580\u2580\u2580\u2580';
      final grid = _FakeGrid.fromRows(lines);
      final region = locateComposerRegion(grid, opencodeSpec, scanRows: 10)!;
      expect(isComposerRegionEmpty(grid, region, opencodeSpec), isTrue);
    });

    test('isComposerRegionEmpty false when box holds staged input', () {
      final lines = List<String>.filled(10, '');
      lines[6] = '                    \u2503';
      lines[7] = '                    \u2503  1';
      lines[8] = '                    \u2503';
      lines[9] = '                    \u2579\u2580\u2580\u2580';
      final grid = _FakeGrid.fromRows(lines);
      final region = locateComposerRegion(grid, opencodeSpec, scanRows: 10)!;
      expect(isComposerRegionEmpty(grid, region, opencodeSpec), isFalse,
          reason: 'prefix followed by staged "1" is content, not chrome');
    });
  });
}

int _displayWidth(String text) {
  var w = 0;
  for (final cp in text.runes) {
    w += cp > 0x7f ? 2 : 1;
  }
  return w;
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

  /// Soft-wrapped composer lines with CJK wide spacers (alacritty mirror layout).
  /// [lineTexts] are logical strings per row (may include ASCII and CJK).
  factory _FakeGrid.wrappedWideLines({
    required int columns,
    required List<String> lineTexts,
  }) {
    final rows = <List<int>>[];
    final flagRows = <List<int>>[];
    for (final text in lineTexts) {
      final codepoints = List<int>.filled(columns, 0x20);
      final flags = List<int>.filled(columns, 0);
      var col = 0;
      for (final cp in text.runes) {
        final isWide = cp > 0x7f; // good enough for these fixtures (CJK)
        final width = isWide ? 2 : 1;
        if (col + width > columns) break;
        codepoints[col] = cp;
        if (isWide) flags[col + 1] = 1 << 5;
        col += width;
      }
      rows.add(codepoints);
      flagRows.add(flags);
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
