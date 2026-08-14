import 'package:teampilot/services/cli/registry/capabilities/terminal_composer_region.dart';
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
    this.composerRegion = fullscreenDefaultComposerSpec,
    this.isAckedOverride,
  });

  bool aborted;
  int crsToClear;
  final int pastesBeforeVisible;
  final bool visibleAfterPaste;
  final bool collapseAsClaudePaste;
  @override
  final FullscreenComposerRegionSpec composerRegion;

  final bool? isAckedOverride;

  String? staged;
  int pasteCount = 0;
  int crCount = 0;
  int clearCount = 0;

  @override
  bool get isAborted => aborted;

  @override
  bool get isAcked => isAckedOverride ?? false;

  @override
  int get viewportRows => 24;

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  ComposerRegion? locateComposerRegion({int scanRows = 24}) =>
      const ComposerRegion(
        topRow: 0, bottomRow: 0, leftCol: 0, rightCol: 200,
      );

  @override
  bool regionContainsNeedle(ComposerRegion region, String needle) =>
      staged != null && staged!.contains(needle);

  @override
  bool isComposerRegionEmpty(ComposerRegion region) =>
      staged == null || staged!.trim().isEmpty;

  @override
  bool needleAppearsOutsideRegion(
    ComposerRegion? region,
    String needle, {
    int scanRows = 24,
  }) =>
      false;

  @override
  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    if (staged == null) return null;
    if (!staged!.contains(needle)) return null;
    final start = staged!.indexOf(needle);
    return FullscreenPromptAnchor(
      row: 0,
      startCol: start,
      needle: needle,
    );
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
  Future<void> clearStagedInput() async {
    clearCount++;
    staged = null;
  }

  @override
  Future<void> pasteText(String text) async {
    pasteCount++;
    if (visibleAfterPaste && pasteCount >= pastesBeforeVisible) {
      staged = collapseAsClaudePaste
          ? '❯ [Pasted text #3 +17 lines]'
          : text;
    }
  }

  @override
  Future<void> submitCr() async {
    crCount++;
    if (crCount >= crsToClear) {
      staged = null;
    }
  }

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      staged == null ? '<empty staged>' : 'staged="$staged"';
}
