import 'package:teampilot/services/chat/terminal/fullscreen_cr_ack_config.dart';
import 'package:teampilot/services/chat/terminal/fullscreen_input_screen_probe.dart';
import 'package:teampilot/services/chat/terminal/fullscreen_pty_delivery_port.dart';
import 'package:teampilot/services/chat/terminal/pty_automation_needle.dart';

/// In-memory [FullscreenPtyDeliveryPort] for automation unit tests.
final class FakeFullscreenPtyDeliveryPort implements FullscreenPtyDeliveryPort {
  FakeFullscreenPtyDeliveryPort({
    this.aborted = false,
    this.crsToClear = 1,
    this.pastesBeforeVisible = 1,
    this.visibleAfterPaste = true,
    this.collapseAsClaudePaste = false,
    this.crAckConfig = const FullscreenCrAckConfig.productionDefault(),
    this.composerChromeEmptyOverride,
    this.composerStagedOverride,
  });

  bool aborted;
  int crsToClear;
  final int pastesBeforeVisible;
  final bool visibleAfterPaste;
  final bool collapseAsClaudePaste;
  @override
  final FullscreenCrAckConfig crAckConfig;

  /// When set, [isComposerChromeEmpty] returns this value instead of inferring.
  final bool? composerChromeEmptyOverride;

  /// When set, [isNeedleStagedInComposer] returns this value instead of
  /// inferring from [staged]. Simulates a resumed session where the needle
  /// exists on the grid (old transcript echo) but the live composer is empty.
  final bool? composerStagedOverride;

  String? staged;
  int pasteCount = 0;
  int crCount = 0;
  int clearCount = 0;

  @override
  bool get isAborted => aborted;

  @override
  int get viewportRows => 24;

  @override
  int get cursorRow => -1;

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  Future<void> waitForPaint({required Duration timeout}) async {}

  @override
  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    if (staged == null) return null;
    if (!staged!.contains(needle)) return null;
    final start = staged!.indexOf(needle);
    return FullscreenPromptAnchor(row: 0, startCol: start, needle: needle);
  }

  @override
  FullscreenPromptAnchor? locatePasteZoneNeedle(
    String needle, {
    int scanRows = 24,
  }) => locateNeedle(needle, scanRows: scanRows);

  @override
  FullscreenPromptAnchor? locateCollapsedPasteZoneNeedle({int scanRows = 24}) =>
      locateCollapsedPasteNeedle(scanRows: scanRows);

  @override
  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) {
    if (staged == null) return null;
    final marker = PtyAutomationNeedle.collapsedPasteNeedle(staged!);
    if (marker == null) return null;
    return locateNeedle(marker, scanRows: scanRows);
  }

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) {
    if (staged == null) return false;
    return staged!.contains(anchor.needle);
  }

  @override
  bool isNeedleStagedInCursorZone(String needle) {
    if (staged == null || needle.isEmpty) return false;
    return staged!.contains(needle);
  }

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) {
    if (crCount < crsToClear) return false;
    if (staged == null) return true;
    return !staged!.contains(anchor.needle);
  }

  @override
  Future<void> clearStagedInput({bool Function()? canExecute}) async {
    clearCount++;
    staged = null;
  }

  @override
  Future<void> pasteText(String text, {bool Function()? canExecute}) async {
    pasteCount++;
    if (visibleAfterPaste && pasteCount >= pastesBeforeVisible) {
      staged = collapseAsClaudePaste ? '❯ [Pasted text #3 +17 lines]' : text;
    }
  }

  @override
  Future<void> submitCr({bool Function()? canExecute}) async {
    crCount++;
    if (crCount >= crsToClear) {
      staged = null;
    }
  }

  /// Tests that care override this; default no-op like a bare ESC.
  int dismissCount = 0;

  @override
  Future<void> dismissComposerPopup() async {
    dismissCount++;
  }

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      staged == null ? '<empty staged>' : 'staged="$staged"';
}

// Row-aware fake for the paste-denominator baseline (cursor): simulates a
// repeated identical short message where the earlier render sits on an upper
// row and the freshly pasted copy lands on a lower row (TUI input box pinned
// at the bottom). `locatePasteZoneNeedle` returns the row that currently
// represents staged content (stale echo in the transcript, new copy below).
final class RowAwareFakeFullscreenPtyDeliveryPort
    implements FullscreenPtyDeliveryPort {
  RowAwareFakeFullscreenPtyDeliveryPort({
    this.crAckConfig = const FullscreenCrAckConfig(
      strategy: FullscreenCrAckStrategy.composerMovesDown,
      pasteBaseline: true,
      pasteZoneBottomPad: 3,
    ),
    this.pasteFailsToStage = false,
    this.staleEcho,
    this.staleRow = 3,
    this.laggingProbe = false,
  });

  @override
  final FullscreenCrAckConfig crAckConfig;
  final bool pasteFailsToStage;
  String? staleEcho; // pre-render text sitting on an upper row
  int staleRow;

  /// When true, [locatePasteZoneNeedle] reads a snapshot updated only by
  /// [syncDisplayGrid] — the live TUI (clear/paste) can move ahead of the
  /// probe grid, matching production `drainForTest` lag.
  final bool laggingProbe;
  String? staged; // freshly pasted text
  int stagedRow = 5;
  int pasteCount = 0;
  int crCount = 0;
  int clearCount = 0;
  String? _probeStaged;
  int _probeStagedRow = 5;
  String? _probeEcho;
  int _probeEchoRow = 3;

  @override
  bool get isAborted => false;

  @override
  int get viewportRows => 24;

  @override
  int get cursorRow => -1;

  @override
  Future<void> syncDisplayGrid() async {
    if (!laggingProbe) return;
    _probeStaged = staged;
    _probeStagedRow = stagedRow;
    _probeEcho = staleEcho;
    _probeEchoRow = staleRow;
  }

  @override
  Future<void> waitForPaint({required Duration timeout}) async {}

  @override
  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    if (laggingProbe) {
      return _anchorOn(
        staged: _probeStaged,
        stagedRow: _probeStagedRow,
        echo: _probeEcho,
        echoRow: _probeEchoRow,
        needle: needle,
      );
    }
    return _anchorOn(
      staged: staged,
      stagedRow: stagedRow,
      echo: staleEcho,
      echoRow: staleRow,
      needle: needle,
    );
  }

  FullscreenPromptAnchor? _anchorOn({
    required String? staged,
    required int stagedRow,
    required String? echo,
    required int echoRow,
    required String needle,
  }) {
    if (staged != null && staged.contains(needle)) {
      return FullscreenPromptAnchor(
        row: stagedRow,
        startCol: 0,
        needle: needle,
      );
    }
    if (echo != null && echo.contains(needle)) {
      return FullscreenPromptAnchor(row: echoRow, startCol: 0, needle: needle);
    }
    return null;
  }

  @override
  FullscreenPromptAnchor? locatePasteZoneNeedle(
    String needle, {
    int scanRows = 24,
  }) {
    // Bottom input zone: the live staged body first (row 5), else the stale
    // transcript echo (row 3) — the baseline flow rejects anchors at/above the
    // post-clear baseline.
    return locateNeedle(needle, scanRows: scanRows);
  }

  @override
  FullscreenPromptAnchor? locateCollapsedPasteZoneNeedle({int scanRows = 24}) =>
      null;

  @override
  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) {
    if (staged != null && staged!.contains(anchor.needle)) return true;
    return staleEcho != null && staleEcho!.contains(anchor.needle);
  }

  @override
  bool isNeedleStagedInCursorZone(String needle) =>
      staged != null && staged!.contains(needle);

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) {
    if (crCount < 1) return false;
    return staged == null;
  }

  @override
  Future<void> clearStagedInput({bool Function()? canExecute}) async {
    clearCount++;
    staged = null;
  }

  @override
  Future<void> pasteText(String text, {bool Function()? canExecute}) async {
    pasteCount++;
    if (pasteFailsToStage) {
      staged = null; // paste dropped; grid still shows only the stale echo
      return;
    }
    staged = text;
    stagedRow = 5;
  }

  @override
  Future<void> submitCr({bool Function()? canExecute}) async {
    crCount++;
    staged = null;
  }

  @override
  Future<void> dismissComposerPopup() async {}

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      'stale=$staleEcho@$staleRow staged=$staged@$stagedRow';
}
