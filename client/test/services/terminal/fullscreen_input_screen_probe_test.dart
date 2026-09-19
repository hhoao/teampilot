import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/runtime/pty/fullscreen_cr_ack_config.dart';
import 'package:teampilot/services/chat/runtime/pty/fullscreen_input_screen_probe.dart';
import 'package:teampilot/services/chat/runtime/pty/pty_automation_needle.dart';

void main() {
  test('locateNeedle finds bottommost row match', () {
    final grid = _FakeGrid.fromRows(['agent output above', '> 和你的队员打个招呼吧    ']);
    final anchor = locateFullscreenPromptNeedle(grid, '和你的队员打个招呼吧');
    expect(anchor, isNotNull);
    expect(anchor!.row, 1);
    expect(anchor.startCol, 2);
  });

  test('bottomPad excludes the screen footer from the bottom scan', () {
    // cursor-agent draws its footer (model / cwd) BELOW the input box. A needle
    // that duplicates that footer text must not be ACKed as staged input (nor
    // set the paste baseline below the box).
    final grid = _FakeGrid.fromRows([
      'Plan, search, build anything', // input-box line
      'Composer 2.5 Fast',
      '~/agent · main',
    ]);

    // Footer row 2 (~/agent · main) holds the needle: excluded → not found.
    expect(
      locateFullscreenPromptNeedle(grid, '~/agent', scanRows: 8, bottomPad: 2),
      isNull,
      reason: 'needle only in the bottom-padded footer must not be found',
    );
    // Footer row 1 holds the needle: still excluded → not found.
    expect(
      locateFullscreenPromptNeedle(
        grid,
        'Composer 2.5 Fast',
        scanRows: 8,
        bottomPad: 2,
      ),
      isNull,
    );
    // Without the pad the footer is reachable.
    expect(
      locateFullscreenPromptNeedle(grid, '~/agent', scanRows: 8),
      isNotNull,
    );

    // Needle in the input-box line stays reachable with the pad.
    final anchor = locateFullscreenPromptNeedle(
      grid,
      'Plan, search',
      scanRows: 8,
      bottomPad: 2,
    );
    expect(anchor, isNotNull);
    expect(anchor!.row, 0);
  });

  test(
    'bottomPad counts from the last text row, so a high footer never becomes baseline',
    () {
      // Real cursor grid: the composer box (r8 paste) sits ABOVE a tall blank
      // tail (r12..r38 empty). Sending "teampilot" collides with the cwd footer
      // at r11. Excluding the last N PHYSICAL rows skips empty rows and still
      // lets the footer drive expensive baseline/anchor — the pad must be
      // measured from the last NON-BLANK row.
      final rows = List<String>.filled(39, '');
      rows[8] = '  → teampilot';
      rows[9] = '▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀';
      rows[10] =
          'Cursor Grok 4.6 High                                 Run Everything';
      rows[11] = '/home/hhoa/git/hhoa/teampilot · main';
      final grid = _FakeGrid.wrappedWideLines(columns: 120, lineTexts: rows);

      // Without the pad the footer at r11 (last text row) wins the bottom-up scan.
      expect(
        locateFullscreenPromptNeedle(grid, 'teampilot', scanRows: 39)?.row,
        11,
      );

      // With pad=2 the cwd footer is excluded from the baseline/ACK scan.
      final anchor = locateFullscreenPromptNeedle(
        grid,
        'teampilot',
        scanRows: 39,
        bottomPad: 2,
      );
      expect(anchor, isNotNull);
      expect(
        anchor!.row,
        8,
        reason: 'baseline/ACK must hit the real paste, not the cwd footer',
      );

      // pad=3 (box bottom border + 2 footer lines, cursor's value) keeps the
      // paste at r8 reachable while the footer stays excluded.
      final anchor3 = locateFullscreenPromptNeedle(
        grid,
        'teampilot',
        scanRows: 39,
        bottomPad: 3,
      );
      expect(anchor3, isNotNull);
      expect(anchor3!.row, 8);
    },
  );

  test('locateNeedle matches CJK with wide-char spacer columns', () {
    final grid = _FakeGrid.wideCjkRow(row: 1, prefix: '> ', text: '和你的队员打个招呼吧');
    final anchor = locateFullscreenPromptNeedle(grid, '和你的队员打个招呼吧');
    expect(anchor, isNotNull);
    expect(anchor!.row, 1);
    expect(anchor.startCol, 2);
    expect(isFullscreenPromptAtAnchor(grid, anchor), isTrue);
  });

  test('isAtAnchor true while staged, false after input cleared', () {
    final grid = _FakeGrid.fromRows(['history', '> 和你的队员打个招呼吧    ']);
    final anchor = locateFullscreenPromptNeedle(grid, '和你的队员打个招呼吧')!;
    expect(isFullscreenPromptAtAnchor(grid, anchor), isTrue);

    grid.rowsData[1] = '>                         '
        .padRight(grid.columns)
        .codeUnits;
    grid.flagsData[1] = List.filled(grid.columns, 0);
    expect(isFullscreenPromptAtAnchor(grid, anchor), isFalse);
  });

  test(
    'needleStaysInCursorZone finds a multi-line paste tail starting above cursor',
    () {
      // Multi-line composer: the staged tail sits on r19 while the cursor is on
      // the last line (r20). Without the wrap slack the scan would start at the
      // cursor and miss the r19 start.
      final rows = List<String>.filled(24, '');
      rows[19] = 'staged tail continues here';
      rows[20] = 'and the final line';
      final grid = _FakeGrid.fromRows(rows)..cursorRow = 20;

      expect(
        needleStaysInCursorZone(grid, 'staged tail continues here'),
        isTrue,
        reason: 'needle starting above the cursor is still staged input',
      );
    },
  );

  test('cursor-zone needle wraps past a per-line composer chrome border', () {
    // opencode's input box paints a left border (`│` + 2 padding) on every
    // visual row. A long staged paste wraps across those rows, so the
    // continuation chrome must be skipped — nothing is sent when the flattened
    // needle stops matching at the first wrapped border glyph.
    final grid = _FakeGrid.fromRows([
      '│  0123456789ABCDEFG',
      '│  HIJKLMNOPQRSTUVWX',
      '│  YZ',
    ])..cursorRow = 2;
    final needle = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

    final anchor = locateNeedleInCursorZone(grid, needle);
    expect(anchor, isNotNull, reason: 'wrapped needle must ACK across chrome');
    expect(anchor!.row, 0);
    expect(needleStaysInCursorZone(grid, needle), isTrue);
  });

  test('cursor-zone needle wraps past ANY unknown chrome glyph', () {
    // No allowlist: a TUI painting an out-of-scope glyph (◆ here) to lead its
    // composer rows must still ACK a wrapped paste.
    final grid = _FakeGrid.fromRows([
      '◆  0123456789ABCDEFG',
      '◆  HIJKLMNOPQRSTUVWX',
      '◆  YZ',
    ])..cursorRow = 2;
    final needle = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

    final anchor = locateNeedleInCursorZone(grid, needle);
    expect(
      anchor,
      isNotNull,
      reason: 'wrapped needle must ACK across an unknown chrome glyph',
    );
    expect(anchor!.row, 0);
  });

  test('CJK content at wrap start is not consumed as chrome', () {
    // Only a non-letter/digit is chrome. A continuation row that begins with a
    // real content glyph (CJK letter 中) must match as content, not be skipped.
    final grid = _FakeGrid.fromRows(['│  ABCDEFG', '│  中XYZWQ'])..cursorRow = 1;
    final needle = 'ABCDEFG中XYZWQ';

    final anchor = locateNeedleInCursorZone(grid, needle);
    expect(anchor, isNotNull, reason: 'CJK after wrap must match as content');
    expect(anchor!.row, 0);
  });

  test('non-alphanumeric chrome cells are skipped on mismatch anywhere', () {
    // Mismatch tolerance is global, not just at a row start: a grid that
    // inserts punctuation/symbols/spaces (TUI chrome or padding) still matches
    // an otherwise-exact needle.
    for (final row in ['a#bc', 'a→bc', 'a bc', 'a==b']) {
      final grid = _FakeGrid.fromRows([row]);
      final needle = row.contains('==') ? 'a=b' : 'abc';
      expect(
        locateFullscreenPromptNeedle(grid, needle),
        isNotNull,
        reason: 'inserted chrome "$row" must still ACK "$needle"',
      );
    }
  });

  test('letter/digit mismatch fails — content is never skipped', () {
    // Only non-alphanumerics are chrome. A differing letter, digit or CJK
    // must not be stepped over.
    for (final row in ['aXbc', 'a 3bc']) {
      final grid = _FakeGrid.fromRows([row]);
      final needle = row.contains('3') ? 'a2bc' : 'abc';
      expect(
        locateFullscreenPromptNeedle(grid, needle),
        isNull,
        reason: 'content difference in "$row" must not ACK',
      );
    }
    final cjkGrid = _FakeGrid.fromRows(['中X文']);
    expect(locateFullscreenPromptNeedle(cjkGrid, '中文'), isNull);
    expect(locateFullscreenPromptNeedle(cjkGrid, '中X文'), isNotNull);
  });

  test('needle does not bridge a border-only row with zero matches', () {
    // A continuation row that is pure chrome (border + padding) matches zero
    // needle characters — the needle must fail, not stitch across it.
    final grid = _FakeGrid.fromRows(['ABC', '│  ', 'DEF']);
    expect(locateFullscreenPromptNeedle(grid, 'ABCDEF'), isNull);
    expect(locateFullscreenPromptNeedle(grid, 'ABCDEF', scanRows: 8), isNull);
  });

  test('cursor attachment paste ACKs across path + CJK tail rows', () {
    // Real cursor-agent layout seen when delivering "@path\n消息": the composer
    // row 0 holds the `→ ` prompt + file mention, and the CJK message tail
    // wraps to the row below (3-space indent). The flattened 40-char needle
    // spans BOTH rows (.png on row 0, the CJK on row 1).
    const line0 =
        '  → @/home/hhoa/Documents/TeamPilot/Attachments/'
        '4b059105-a81f-45af-b649-ab7b1ceefa64.png';
    const line1 = '    目前发送到邮箱的消息顺序气泡还是很奇怪，它不是出现在当前工具调用的下面';
    final grid = _FakeGrid.wrappedWideLines(
      columns: 120,
      lineTexts: [line0, line1],
    )..cursorRow = 1;
    const text =
        '@/home/hhoa/Documents/TeamPilot/Attachments/'
        '4b059105-a81f-45af-b649-ab7b1ceefa64.png\n'
        '目前发送到邮箱的消息顺序气泡还是很奇怪，它不是出现在当前工具调用的下面';
    final needle = PtyAutomationNeedle.forText(text);
    expect(needle, '.png 目前发送到邮箱的消息顺序气泡还是很奇怪，它不是出现在当前工具调用的下面');

    final anchor = locateNeedleInCursorZone(grid, needle);
    expect(
      anchor,
      isNotNull,
      reason: 'cursor attachment paste tail must ACK across both rows',
    );
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

    final anchor = locateCollapsedPasteNeedle(grid, scanRows: 10);
    expect(anchor, isNotNull);
    expect(anchor!.needle, '[Pasted text #3 +17 lines]');
    expect(anchor.row, 7);
  });

  test('locateNeedleInCursorZone ignores a same-char status line below', () {
    // Real opencode dump: the single-char reply "1" is staged at r33 (cursor),
    // while the status row r37 contains "17%". Bottom-up search would match the
    // status row; the cursor zone must match only the input line.
    final rows = List<String>.filled(40, '');
    rows[32] = '┃';
    rows[33] = '┃  1';
    rows[34] = '┃';
    rows[35] = '┃  Build · deepseek-v4-flash OpenCode Go';
    rows[37] = '/home/hhoa/git/hhoa/teampilot  app_shell.dart  170.0K (17%)';
    final grid = _FakeGrid.fromRows(rows)..cursorRow = 33;

    final anchor = locateNeedleInCursorZone(grid, '1');
    expect(anchor, isNotNull);
    expect(anchor!.row, 33);

    expect(needleStaysInCursorZone(grid, '1'), isTrue);
  });

  test('locateCollapsedPasteNeedle finds opencode paste chrome', () {
    final lines = List<String>.filled(10, '');
    lines[7] = '┃  [Pasted ~152 lines]';
    lines[9] = '';
    final grid = _FakeGrid.fromRows(lines);

    final anchor = locateCollapsedPasteNeedle(grid, scanRows: 10);
    expect(anchor, isNotNull);
    expect(anchor!.needle, '[Pasted ~152 lines]');
    expect(anchor.row, 7);
  });

  test('locateCollapsedPasteNeedle finds Codex paste chrome', () {
    final lines = List<String>.filled(10, '');
    lines[7] = '› [Pasted Content 29390 chars]';
    lines[9] = '';
    final grid = _FakeGrid.fromRows(lines);

    final anchor = locateCollapsedPasteNeedle(grid, scanRows: 10);
    expect(anchor, isNotNull);
    expect(anchor!.needle, '[Pasted Content 29390 chars]');
    expect(anchor.row, 7);
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
    );
    expect(anchor, isNotNull);
    expect(anchor!.row, 18);
  });

  test(
    'locateNeedle ACKs opencode staged paste in its real landing layout',
    () {
      // Real opencode 1.18 landing grid (captured): "┃ Build" status line also
      // starts with the composer prefix, and staged text soft-wraps onto a
      // non-prefixed row. The paste ACK must still resolve the staged line.
      final lines = List<String>.filled(24, '');
      lines[11] = '   \u2503';
      lines[12] =
          '   \u2503  \u76ee\u524d\u6211\u670d\u52a1\u5668\u4e0a\u90e8\u7f72';
      lines[13] = 'inio\uff0c';
      lines[14] = '   \u2503  Build \u00b7 deepseek-v4-flash';
      final grid = _FakeGrid.fromRows(lines);

      final anchor = locateFullscreenPromptNeedle(
        grid,
        '\u76ee\u524d\u6211\u670d\u52a1\u5668\u4e0a\u90e8\u7f72',
        scanRows: 24,
      );
      expect(
        anchor,
        isNotNull,
        reason: 'opencode staged paste must be locatable for paste ACK',
      );
      expect(anchor!.row, 12);
    },
  );

  test(
    'isSubmitted false for composerMovesDown when original composer still holds needle',
    () {
      final grid = _FakeGrid.fromRows([
        'codex output above',
        '› codex-probe-12345',
        '› ',
      ]);
      grid.cursorRow = 1; // input box holds the staged needle
      final anchor = locateFullscreenPromptNeedle(grid, 'codex-probe-12345')!;
      expect(isFullscreenPromptAtAnchor(grid, anchor), isTrue);
      expect(
        isFullscreenPromptSubmitted(
          grid,
          anchor,
          strategy: FullscreenCrAckStrategy.composerMovesDown,
          scanRows: 24,
        ),
        isFalse,
        reason:
            'empty › below a still-staged composer is a relayout, not submit',
      );
    },
  );

  test(
    'isSubmitted false for composerMovesDown when needle moved with live composer',
    () {
      final grid = _FakeGrid.fromRows([
        'codex output above',
        'status footer default · /tmp',
        '› codex-probe-12345',
      ]);
      grid.cursorRow = 2; // needle moved down WITH the live composer
      const anchor = FullscreenPromptAnchor(
        row: 1,
        startCol: 2,
        needle: 'codex-probe-12345',
      );
      expect(isFullscreenPromptAtAnchor(grid, anchor), isFalse);
      expect(
        isFullscreenPromptSubmitted(
          grid,
          anchor,
          strategy: FullscreenCrAckStrategy.composerMovesDown,
          scanRows: 24,
        ),
        isFalse,
        reason:
            'composer shifted down with the staged body still in the input box',
      );
    },
  );

  test('isSubmitted true for composerMovesDown when needle left composer', () {
    // Real codex renders the submitted user message in the transcript with
    // the same › glyph as the composer — model the echo row prefixed.
    final grid = _FakeGrid.fromRows([
      'codex output above',
      '› codex-probe-12345',
      'Working…',
      '› Ask Codex to do anything',
    ]);
    const anchor = FullscreenPromptAnchor(
      row: 1,
      startCol: 2,
      needle: 'codex-probe-12345',
    );
    expect(
      isFullscreenPromptSubmitted(
        grid,
        anchor,
        strategy: FullscreenCrAckStrategy.composerMovesDown,
        scanRows: 24,
      ),
      isTrue,
    );
  });

  test(
    'isSubmitted false for composerMovesDown when no new composer below',
    () {
      final grid = _FakeGrid.fromRows([
        'codex output above',
        '› codex-probe-12345',
      ]);
      grid.cursorRow = 1; // staged needle still at the live composer
      final anchor = locateFullscreenPromptNeedle(grid, 'codex-probe-12345')!;
      expect(
        isFullscreenPromptSubmitted(
          grid,
          anchor,
          strategy: FullscreenCrAckStrategy.composerMovesDown,
          scanRows: 24,
        ),
        isFalse,
      );
    },
  );

  test('locateNeedle finds soft-wrapped CJK tail across two rows', () {
    // Logical paste (no prefix in needle). Composer prefix only on first row.
    const line0 = '❯ 帮我估算一下这个需求的时间：分类分级系统接入银行统一身份认证体系，实现登录双因素认证（优先手机令牌方式），同时评估';
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
    expect(
      anchor,
      isNotNull,
      reason: 'needle spans soft wrap; single-row match misses',
    );
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
    final grid = _FakeGrid.fromRows(['❯ hello_WORLD_PART', '_CONTINUES_HERE']);
    final anchor = locateFullscreenPromptNeedle(
      grid,
      'WORLD_PART_CONTINUES_HERE',
    );
    expect(anchor, isNotNull);
    expect(anchor!.row, 0);
  });

  test(
    'locateNeedle matches flattened JSON closing braces across hard lines',
    () {
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
        reason:
            'flattened multiline JSON tail must ACK across hard line breaks',
      );
    },
  );

  test('locateNeedle collapses needle spaces across indented soft wrap', () {
    // Wrap lands on the word-break space; continuation indent has MORE spaces
    // than the single space in the needle.
    final grid = _FakeGrid.fromRows(['❯ say hello', '     world_TAIL']);
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
    final grid = _FakeGrid.fromRows(['❯ say hello', '     world_TAIL']);
    final anchor = locateFullscreenPromptNeedle(
      grid,
      'hello   world_TAIL',
      scanRows: 8,
    );
    expect(anchor, isNotNull);
    expect(isFullscreenPromptAtAnchor(grid, anchor!), isTrue);
  });

  test('isAtAnchor false after clearing soft-wrapped staged cells', () {
    final grid = _FakeGrid.fromRows(['❯ hello_WORLD_PART', '_CONTINUES_HERE']);
    final anchor = locateFullscreenPromptNeedle(
      grid,
      'WORLD_PART_CONTINUES_HERE',
    )!;
    expect(isFullscreenPromptAtAnchor(grid, anchor), isTrue);

    grid.rowsData[0] = List.filled(grid.columns, 0x20);
    grid.rowsData[1] = List.filled(grid.columns, 0x20);
    expect(isFullscreenPromptAtAnchor(grid, anchor), isFalse);
  });

  // Regression (2026-09-09, real codex dump in logs/app_2026-09-09.log):
  // codex renders the submitted user message in the transcript with the SAME
  // `›` prefix as the composer. r13 = "› hello" transcript echo, r21 =
  // "› Ask Codex to do anything" live (now placeholder) input box. The echo
  // must not read as staged composer input.
  List<String> realCodexEchoDumpRows() {
    final rows = List<String>.filled(24, '');
    rows[1] = '│ model:       gpt-5.6-luna high   /model to change │';
    rows[2] = '│ directory:   ~/Documents/TeamPilot                │';
    rows[3] = '│ permissions: YOLO mode                         │';
    rows[9] =
        '⚠ `--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run';
    rows[13] = '› hello';
    rows[16] =
        '• You have 2 usage limit resets available. Run /usage to use one.';
    rows[18] = '• Working (17s • esc to interrupt)';
    rows[21] = '› Ask Codex to do anything';
    rows[23] = 'gpt-5.6-luna high · ~/Documents/TeamPilot';
    return rows;
  }

  test('composerMovesDown verdict submitted for real codex echo layout', () {
    final grid = _FakeGrid.fromRows(realCodexEchoDumpRows());
    // Anchor from paste time: the composer row that held "hello" pre-submit.
    const anchor = FullscreenPromptAnchor(
      row: 13,
      startCol: 2,
      needle: 'hello',
    );

    expect(
      isFullscreenPromptSubmitted(
        grid,
        anchor,
        strategy: FullscreenCrAckStrategy.composerMovesDown,
        scanRows: 24,
      ),
      isTrue,
      reason:
          'echo above + fresh placeholder composer below = submitted '
          '(codex was Working 17s at dump time — the CR was accepted)',
    );
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

  /// Cursor row (composer position) — tests set this to model a live input box.
  @override
  int cursorRow = -1;

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
