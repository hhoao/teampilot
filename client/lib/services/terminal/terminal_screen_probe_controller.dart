import 'package:flutter_alacritty/flutter_alacritty.dart';

import 'fullscreen_cr_ack_config.dart';
import 'fullscreen_input_screen_probe.dart' as probe;

/// Read-only screen-grid probes for full-screen TUI automation ACK loops.
///
/// SRP: observation of the mirror grid is separate from PTY writes.
final class TerminalScreenProbeController {
  TerminalScreenProbeController({required this.engine});

  final TerminalEngine engine;

  int get viewportRows => engine.grid.rows;

  /// Mirror-grid cursor row (`-1` when unknown); diagnostic aid for paste ACK
  /// misses — a paste sitting outside the [locateNeedleInCursorZone] window
  /// (stale/misplaced cursor) never ACKs.
  int get cursorRow => probe.terminalScreenGrid(engine.grid).cursorRow;

  Future<void> syncDisplayGrid() => engine.drainForTest();

  probe.FullscreenPromptAnchor? locateFullscreenPromptNeedle(
    String needle, {
    int scanRows = 8,
  }) =>
      probe.locateFullscreenPromptNeedle(
        _screenGrid,
        needle,
        scanRows: scanRows,
      );

  probe.FullscreenPromptAnchor? locateCollapsedPasteNeedle({
    int scanRows = 8,
  }) =>
      probe.locateCollapsedPasteNeedle(
        _screenGrid,
        scanRows: scanRows,
      );

  probe.FullscreenPromptAnchor? locateNeedleInCursorZone(String needle) =>
      probe.locateNeedleInCursorZone(_screenGrid, needle);

  probe.FullscreenPromptAnchor? locateCollapsedPasteInCursorZone() =>
      probe.locateCollapsedPasteInCursorZone(_screenGrid);

  bool isFullscreenPromptAtAnchor(probe.FullscreenPromptAnchor anchor) =>
      probe.isFullscreenPromptAtAnchor(_screenGrid, anchor);

  bool isFullscreenPromptSubmitted(
    probe.FullscreenPromptAnchor anchor, {
    required FullscreenCrAckStrategy strategy,
    int scanRows = 24,
  }) =>
      probe.isFullscreenPromptSubmitted(
        _screenGrid,
        anchor,
        strategy: strategy,
        scanRows: scanRows,
      );

  bool needleStaysInCursorZone(String needle) =>
      probe.needleStaysInCursorZone(_screenGrid, needle);

  String describeProbeWindow({int scanRows = 8}) =>
      probe.describeProbeWindow(_screenGrid, scanRows: scanRows);

  bool screenContainsText(String needle, {int scanRows = 5}) =>
      locateFullscreenPromptNeedle(needle, scanRows: scanRows) != null;

  bool hasInputBoxContent({int scanRows = 3}) {
    final grid = engine.grid;
    final rows = grid.rows;
    final cols = grid.columns;
    if (rows == 0 || cols == 0) return false;

    final startRow = (rows - scanRows).clamp(0, rows - 1);
    for (var r = startRow; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final cp = grid.codepointAt(r, c);
        if (cp != 0 && cp != 32) return true;
      }
    }
    return false;
  }

  probe.TerminalScreenGrid get _screenGrid =>
      probe.terminalScreenGrid(engine.grid);
}
