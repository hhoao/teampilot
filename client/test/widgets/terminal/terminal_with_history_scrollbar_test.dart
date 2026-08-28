import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/render/mirror_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/terminal/terminal_history_scrollbar.dart';
import 'package:teampilot/widgets/terminal/terminal_with_history_scrollbar.dart';

LineCells _blankLine(int line, {int columns = 8}) {
  return LineCells(
    line: line,
    codepoints: Uint32List.fromList(List.filled(columns, 0x20)),
    fg: Uint32List.fromList(List.filled(columns, 0xD8D8D8)),
    bg: Uint32List.fromList(List.filled(columns, 0x181818)),
    flags: Uint16List.fromList(List.filled(columns, 0)),
  );
}

void _applyGrid(
  TerminalEngine engine, {
  required int historySize,
  int displayOffset = 0,
  int cursorCol = 0,
}) {
  const rows = 4;
  const columns = 8;
  engine.gridForView.apply(
    GridUpdate(
      full: true,
      rows: rows,
      columns: columns,
      lines: [for (var i = 0; i < rows; i++) _blankLine(i, columns: columns)],
      cursorRow: 0,
      cursorCol: cursorCol,
      cursorVisible: true,
      historySize: historySize,
      displayOffset: displayOffset,
    ),
  );
}

Finder _trackGesture() {
  return find.descendant(
    of: find.byType(TerminalHistoryScrollbar),
    matching: find.byType(GestureDetector),
  );
}

void main() {
  testWidgets(
    'grid cell notifies paint the thumb without rebuilding scrollbar widgets',
    (tester) async {
      final engine = TerminalEngine(config: TerminalConfig.defaults());
      addTearDown(engine.dispose);
      final controller = TerminalController()..attach(engine);
      addTearDown(controller.dispose);

      _applyGrid(engine, historySize: 80);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: TerminalWithHistoryScrollbar(
                engine: engine,
                controller: controller,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(_trackGesture(), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TerminalWithHistoryScrollbar),
          matching: find.byType(ListenableBuilder),
        ),
        findsNothing,
      );

      final scrollbarBefore = tester.widget<TerminalHistoryScrollbar>(
        find.byType(TerminalHistoryScrollbar),
      );
      final gestureBefore = tester.widget<GestureDetector>(_trackGesture());
      final paintBefore = tester.widget<CustomPaint>(
        find.descendant(
          of: _trackGesture(),
          matching: find.byType(CustomPaint),
        ),
      );

      _applyGrid(engine, historySize: 80, cursorCol: 3);
      await tester.pump();
      _applyGrid(engine, historySize: 120, displayOffset: 10);
      await tester.pump();

      expect(_trackGesture(), findsOneWidget);
      expect(
        identical(
          scrollbarBefore,
          tester.widget<TerminalHistoryScrollbar>(
            find.byType(TerminalHistoryScrollbar),
          ),
        ),
        isTrue,
        reason: 'engine.grid cell/history ticks must not reconstruct the '
            'scrollbar widget (ListenableBuilder rebuild storm)',
      );
      expect(
        identical(gestureBefore, tester.widget<GestureDetector>(_trackGesture())),
        isTrue,
        reason: 'thumb motion must paint, not rebuild GestureDetector',
      );
      expect(
        identical(
          paintBefore,
          tester.widget<CustomPaint>(
            find.descendant(
              of: _trackGesture(),
              matching: find.byType(CustomPaint),
            ),
          ),
        ),
        isTrue,
      );
    },
  );
}
