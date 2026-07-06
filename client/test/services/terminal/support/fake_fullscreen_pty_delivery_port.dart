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
  });

  bool aborted;
  int crsToClear;
  final int pastesBeforeVisible;
  final bool visibleAfterPaste;

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
      staged = text;
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
