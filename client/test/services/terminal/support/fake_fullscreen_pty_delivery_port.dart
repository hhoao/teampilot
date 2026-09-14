import 'package:teampilot/services/terminal/fullscreen_cr_ack_config.dart';
import 'package:teampilot/services/terminal/fullscreen_input_screen_probe.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_delivery_port.dart';
import 'package:teampilot/services/terminal/pty_automation_needle.dart';

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
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) {
    if (crCount < crsToClear) return false;
    if (staged == null) return true;
    return !staged!.contains(anchor.needle);
  }

  @override
  bool isComposerChromeEmpty({int scanRows = 24}) {
    if (composerChromeEmptyOverride != null) {
      return composerChromeEmptyOverride!;
    }
    final prefix = crAckConfig.composerPrefix?.trim();
    if (prefix == null || prefix.isEmpty) {
      return staged == null || staged!.trim().isEmpty;
    }
    if (staged == null) return true;
    final trimmed = staged!.trimLeft();
    if (!trimmed.startsWith(prefix)) {
      // Staged body without prefix chrome — treat as non-empty composer body.
      return staged!.trim().isEmpty;
    }
    return trimmed.substring(prefix.length).trim().isEmpty;
  }

  @override
  bool isNeedleStagedInComposer(String needle, {int scanRows = 24}) {
    if (staged == null || needle.isEmpty) return false;
    if (composerStagedOverride != null) return composerStagedOverride!;
    return staged!.contains(needle);
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

// Row-aware fake for the paste-denominator baseline regression:
// simulates a repeated identical short message where the earlier render sits
// on an upper row and the freshly pasted copy lands on a lower row (TUI input
// box pinned at the bottom). `locateNeedle` returns the row that currently
// represents staged content.
final class RowAwareFakeFullscreenPtyDeliveryPort
    implements FullscreenPtyDeliveryPort {
  RowAwareFakeFullscreenPtyDeliveryPort({
    this.crAckConfig =
        const FullscreenCrAckConfig(
          strategy: FullscreenCrAckStrategy.composerMovesDown,
          composerPrefix: '\u203a',
        ),
  });

  @override
  final FullscreenCrAckConfig crAckConfig;
  String? staleEcho; // pre-render text sitting on an upper row
  int staleRow = 3;
  String? staged; // freshly pasted text
  int stagedRow = 5;
  int pasteCount = 0;
  int crCount = 0;
  int clearCount = 0;

  @override
  bool get isAborted => false;

  @override
  int get viewportRows => 24;

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  Future<void> waitForPaint({required Duration timeout}) async {}

  @override
  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    if (staged != null && staged!.contains(needle)) {
      return FullscreenPromptAnchor(
          row: stagedRow, startCol: 0, needle: needle);
    }
    if (staleEcho != null && staleEcho!.contains(needle)) {
      return FullscreenPromptAnchor(
          row: staleRow, startCol: 0, needle: needle);
    }
    return null;
  }

  @override
  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) {
    if (staged != null && staged!.contains(anchor.needle)) return true;
    return staleEcho != null && staleEcho!.contains(anchor.needle);
  }

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) {
    if (crCount < 1) return false;
    return staged == null;
  }

  @override
  bool isComposerChromeEmpty({int scanRows = 24}) =>
      staged == null || staged!.trim().isEmpty;

  @override
  bool isNeedleStagedInComposer(String needle, {int scanRows = 24}) =>
      staged != null && staged!.contains(needle);

  @override
  Future<void> clearStagedInput({bool Function()? canExecute}) async {
    clearCount++;
    staged = null;
  }

  @override
  Future<void> pasteText(String text, {bool Function()? canExecute}) async {
    pasteCount++;
    // First paste: only the stale echo exists (row 3). Real TUI renders the
    // pasted copy below it (row 5) — approximate with stagedRow.
    if (staleEcho == null) {
      staleEcho = text;
      staleRow = 3;
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
