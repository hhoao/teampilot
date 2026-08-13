import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/terminal_composer_region.dart';
import 'package:teampilot/services/terminal/fullscreen_input_screen_probe.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_automation.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_delivery_port.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import 'support/fake_fullscreen_pty_delivery_port.dart';

void main() {
  final timing = PtyAutomationTiming.instant();
  final automation = FullscreenPtyAutomation(timing: timing);

  group('deliverPasteAndSubmit', () {
    test('pastes, submits CR, and returns submitted', () async {
      final port = FakeFullscreenPtyDeliveryPort();
      const text = '[teammate-bus] read_messages now';

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: text,
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(port.pasteCount, 1);
      expect(port.crCount, greaterThanOrEqualTo(1));
      expect(port.staged, isNull);
    });

    test('reinjects when paste is not found on grid', () async {
      final port = FakeFullscreenPtyDeliveryPort(pastesBeforeVisible: 2);
      const text = '和你的队员打个招呼吧';

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: text,
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(port.pasteCount, 2);
    });

    test('returns pasteNotFound when needle never appears', () async {
      final port = FakeFullscreenPtyDeliveryPort(visibleAfterPaste: false);
      const text = 'never lands';

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: text,
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.pasteNotFound);
    });

    test('submits when Claude collapses long paste into chrome', () async {
      final port = FakeFullscreenPtyDeliveryPort(collapseAsClaudePaste: true);
      final long = 'deploy jar\n' + ('x' * 80) + '\nxl-control.jar\n449 MB';

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: long,
        pasteSettle: Duration.zero,
      );

      expect(
        outcome,
        FullscreenPtyDeliveryOutcome.submitted,
        reason:
            'Claude Code hides long paste bodies behind '
            '[Pasted text #N +M lines]; automation must ACK that chrome '
            'and still CR-submit the staged buffer',
      );
      expect(port.pasteCount, greaterThanOrEqualTo(1));
      expect(port.crCount, greaterThanOrEqualTo(1));
    });

    test('accepts cursor submit when transcript keeps the submitted text', () async {
      final port = _CursorTranscriptAfterSubmitPort();

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: TeamBus.doorbellNotice,
        pasteSettle: Duration.zero,
      );

      expect(
        outcome,
        FullscreenPtyDeliveryOutcome.submitted,
        reason:
            'cursor keeps the submitted prompt visible as transcript history '
            'and paints a fresh composer below it',
      );
    });

    test('pastes even when resume transcript already shows the same text', () async {
      // Simulates Cursor --resume: prior user line "hello" still near composer.
      final port = FakeFullscreenPtyDeliveryPort()..staged = 'hello';

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: 'hello',
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(
        port.pasteCount,
        1,
        reason:
            'must not CR-only on a transcript false-positive; always paste '
            'on first deliver',
      );
      expect(port.clearCount, greaterThanOrEqualTo(1));
    });
  });

  group('nudgeCrUntilClear', () {
    test('submits CR when text already visible', () async {
      final port = FakeFullscreenPtyDeliveryPort()..staged = TeamBus.doorbellNotice;

      final outcome = await automation.nudgeCrUntilClear(
        port: port,
        text: TeamBus.doorbellNotice,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(port.pasteCount, 0);
      expect(port.crCount, 1);
    });

    test('returns pasteNotFound when text absent', () async {
      final port = FakeFullscreenPtyDeliveryPort();

      final outcome = await automation.nudgeCrUntilClear(
        port: port,
        text: TeamBus.doorbellNotice,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.pasteNotFound);
    });
  });

  group('retry', () {
    test('repastes when text not visible', () async {
      final port = FakeFullscreenPtyDeliveryPort();

      final outcome = await automation.retry(
        port: port,
        text: TeamBus.doorbellNotice,
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(port.pasteCount, 1);
    });

    test('repastes when text already visible', () async {
      final port = FakeFullscreenPtyDeliveryPort()
        ..staged = TeamBus.doorbellNotice;

      final outcome = await automation.retry(
        port: port,
        text: TeamBus.doorbellNotice,
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(port.pasteCount, 1);
      expect(port.clearCount, greaterThanOrEqualTo(1));
      expect(port.crCount, greaterThanOrEqualTo(1));
    });

    test('skips re-paste entirely when hook already acked the submit', () async {
      final port = FakeFullscreenPtyDeliveryPort();

      final outcome = await automation.retry(
        port: port,
        text: TeamBus.doorbellNotice,
        pasteSettle: Duration.zero,
        isAcked: () => true,
      );

      expect(
        outcome,
        FullscreenPtyDeliveryOutcome.submitted,
        reason: 'hook confirmed the prompt already committed; retry re-paste '
            'would duplicate the user row',
      );
      expect(port.pasteCount, 0);
      expect(port.crCount, 0);
    });
  });

  test('isTextVisible uses PtyAutomationNeedle', () {
    final port = FakeFullscreenPtyDeliveryPort()
      ..staged = '和你的队员打个招呼吧';
    expect(
      automation.isTextVisible(port, '和你的队员打个招呼吧'),
      isTrue,
    );
  });

  group('composerMovesDown reinject guard', () {
    test('skips reinject when crStuck but empty composer + needle', () async {
      final port = _ComposerMovesDownStuckButCommittedPort(text: 'A');

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: 'A',
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(
        port.pasteCount,
        1,
        reason: 'first CR already committed; reinject would duplicate user turn',
      );
    });

    test('reinjects when crStuck and body still staged on composer', () async {
      final port = _ComposerMovesDownStuckStagedThenAckPort(text: 'A');

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: 'A',
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(port.pasteCount, greaterThanOrEqualTo(2));
    });

    test('reinjects when composer empty but needle gone', () async {
      final port = _ComposerMovesDownEmptyNoNeedleThenAckPort(text: 'A');

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: 'A',
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(port.pasteCount, greaterThanOrEqualTo(2));
    });

    test('regionCleared never skips reinject via guard', () async {
      final port = FakeFullscreenPtyDeliveryPort(crsToClear: 999);

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: 'hello',
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.crStuck);
      expect(port.pasteCount, greaterThanOrEqualTo(2));
    });

    test(
      'hook ACK during crStuck poll cancels reinject (regionCleared)',
      () async {
        // opencode shape: first CR actually commits (composer clears) but the
        // mirror grid stays stale so the probe reports crStuck. Meanwhile the
        // prompt-submit hook ACK (authoritative) has already arrived.
        final port = _AnchorCellStuckButHookAckedPort(text: 'A');
        var acked = false;
        bool isAcked() {
          // Hook fires right after the CLI commits the prompt (first CR).
          if (port.crCount > 0) acked = true;
          return acked;
        }

        final outcome = await automation.deliverPasteAndSubmit(
          port: port,
          text: 'A',
          pasteSettle: Duration.zero,
          isAcked: isAcked,
        );

        expect(
          outcome,
          FullscreenPtyDeliveryOutcome.submitted,
          reason: 'ACK proves the message already committed; reinject would '
              'create a duplicate user row (the opencode multi-bubble bug)',
        );
        expect(
          port.pasteCount,
          1,
          reason: 'ACK arrived mid-poll — the in-loop reinject must not '
              're-paste the same text',
        );
      },
    );
  });

  group('region ACK primitives', () {
    test('regionMovedDown ACKs on bottom-pinned viewport via needle cleared',
        () async {
      // Cursor/codex on a full viewport: the composer is pinned to the last
      // grid row, so after CR the new region sits at the SAME bottom row —
      // topRow > previous.bottomRow never fires. The needle leaving the region
      // (moved to transcript) must ACK.
      final port = _BottomPinnedRegionClearedPort(text: 'A');

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: 'A',
        pasteSettle: Duration.zero,
      );

      expect(
        outcome,
        FullscreenPtyDeliveryOutcome.submitted,
        reason: 'bottom-pinned regionMovedDown must submit when the staged '
            'needle left the region even though the row comparison is stuck',
      );
      expect(port.pasteCount, 1);
    });

    test('regionCleared treats vanished region + needle gone as submitted',
        () async {
      // opencode short-text shape: the composer collapses after CR and the
      // region is transiently null; with the needle gone from the whole probe
      // window the submit must ACK instead of reinjecting.
      final port = _RegionClearedNullAfterSubmitPort(text: 'A');

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: 'A',
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(
        port.pasteCount,
        1,
        reason: 'null region + needle gone must not reinject an '
            'already-committed message',
      );
    });

    test('regionCleared keeps polling while needle still in the window',
        () async {
      // Null region is transient but the staged text is still visible: the
      // message is NOT committed — keep polling instead of false-ACKing.
      final port = _RegionClearedNullWithVisibleNeedlePort(text: 'A');

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: 'A',
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.crStuck);
      expect(port.pasteCount, greaterThanOrEqualTo(2));
    });
  });
}

final class _CursorTranscriptAfterSubmitPort
    implements FullscreenPtyDeliveryPort {
  String? _staged;
  bool _submitted = false;
  int crCount = 0;

  @override
  bool get isAborted => false;

  @override
  int get viewportRows => 24;

  @override
  FullscreenComposerRegionSpec get composerRegion =>
      const FullscreenComposerRegionSpec(
        submitSemantics: ComposerSubmitSemantics.regionMovedDown,
        prefixes: ['→'],
      );

  @override
  bool get isAcked => false;

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  ComposerRegion? locateComposerRegion({int scanRows = 24}) =>
      _submitted
          ? const ComposerRegion(
              topRow: 2, bottomRow: 2, leftCol: 0, rightCol: 200,
            )
          : const ComposerRegion(
              topRow: 0, bottomRow: 0, leftCol: 0, rightCol: 200,
            );

  @override
  bool regionContainsNeedle(ComposerRegion region, String needle) =>
      _staged != null && _staged!.contains(needle);

  @override
  bool isComposerRegionEmpty(ComposerRegion region) =>
      _staged == null || _staged!.trim().isEmpty;

  @override
  bool needleAppearsOutsideRegion(
    ComposerRegion? region,
    String needle, {
    int scanRows = 24,
  }) =>
      false;

  @override
  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    if (_staged == null || !_staged!.contains(needle)) return null;
    return FullscreenPromptAnchor(
      row: 0,
      startCol: _staged!.indexOf(needle),
      needle: needle,
    );
  }

  @override
  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) {
    return _staged != null && _staged!.contains(anchor.needle);
  }

  @override
  Future<void> clearStagedInput() async {
    _staged = null;
    _submitted = false;
  }

  @override
  Future<void> pasteText(String text) async {
    _staged = text;
    _submitted = false;
  }

  @override
  Future<void> submitCr() async {
    crCount++;
    _submitted = true;
  }

  @override
  String describeProbeWindow({int scanRows = 24}) {
    return _submitted
        ? '$_staged\n→ '
        : (_staged == null ? '<empty>' : '→ $_staged');
  }
}

/// Cursor-shaped bug: CR commits text into transcript, ACK never fires, composer empty.
final class _ComposerMovesDownStuckButCommittedPort
    implements FullscreenPtyDeliveryPort {
  _ComposerMovesDownStuckButCommittedPort({required this.text});

  final String text;
  String? _transcript;
  String? _composerBody;
  int pasteCount = 0;
  int crCount = 0;

  @override
  bool get isAborted => false;

  @override
  int get viewportRows => 24;

  @override
  FullscreenComposerRegionSpec get composerRegion =>
      const FullscreenComposerRegionSpec(
        submitSemantics: ComposerSubmitSemantics.regionMovedDown,
        prefixes: ['→'],
      );

  @override
  bool get isAcked => false;

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  ComposerRegion? locateComposerRegion({int scanRows = 24}) =>
      const ComposerRegion(
        topRow: 0, bottomRow: 0, leftCol: 0, rightCol: 200,
      );

  @override
  bool regionContainsNeedle(ComposerRegion region, String needle) =>
      _composerBody != null && _composerBody!.contains(needle);

  @override
  bool isComposerRegionEmpty(ComposerRegion region) =>
      _composerBody == null || _composerBody!.trim().isEmpty;

  @override
  bool needleAppearsOutsideRegion(
    ComposerRegion? region,
    String needle, {
    int scanRows = 24,
  }) =>
      _transcript != null && _transcript!.contains(needle);

  @override
  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    final hay = _composerBody ?? _transcript;
    if (hay == null || !hay.contains(needle)) return null;
    return FullscreenPromptAnchor(
      row: _composerBody != null ? 1 : 0,
      startCol: hay.indexOf(needle),
      needle: needle,
    );
  }

  @override
  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      locateNeedle(anchor.needle) != null;

  @override
  Future<void> clearStagedInput() async {
    _composerBody = null;
  }

  @override
  Future<void> pasteText(String value) async {
    pasteCount++;
    _composerBody = value;
  }

  @override
  Future<void> submitCr() async {
    crCount++;
    if (_composerBody != null) {
      _transcript = _composerBody;
      _composerBody = null;
    }
  }

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      'transcript=$_transcript composer=$_composerBody';
}

/// First round: CR leaves body staged and ACK fails; reinject then ACKs.
final class _ComposerMovesDownStuckStagedThenAckPort
    implements FullscreenPtyDeliveryPort {
  _ComposerMovesDownStuckStagedThenAckPort({required this.text});

  final String text;
  String? staged;
  int pasteCount = 0;
  int crCount = 0;
  int _round = 0;

  @override
  bool get isAborted => false;

  @override
  int get viewportRows => 24;

  @override
  FullscreenComposerRegionSpec get composerRegion =>
      const FullscreenComposerRegionSpec(
        submitSemantics: ComposerSubmitSemantics.regionMovedDown,
        prefixes: ['→'],
      );

  @override
  bool get isAcked => false;

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  ComposerRegion? locateComposerRegion({int scanRows = 24}) {
    if (staged != null) {
      return const ComposerRegion(
        topRow: 0, bottomRow: 0, leftCol: 0, rightCol: 200,
      );
    }
    if (_round >= 1) {
      // Committed: composer repainted below the transcript.
      return const ComposerRegion(
        topRow: 2, bottomRow: 2, leftCol: 0, rightCol: 200,
      );
    }
    return null;
  }

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
    if (staged == null || !staged!.contains(needle)) return null;
    return FullscreenPromptAnchor(
      row: 0,
      startCol: staged!.indexOf(needle),
      needle: needle,
    );
  }

  @override
  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      staged != null && staged!.contains(anchor.needle);

  @override
  Future<void> clearStagedInput() async {
    staged = null;
  }

  @override
  Future<void> pasteText(String value) async {
    pasteCount++;
    if (pasteCount > 1) _round = 1;
    staged = value;
  }

  @override
  Future<void> submitCr() async {
    crCount++;
    if (_round >= 1) {
      staged = null;
    }
    // First round: leave staged so guard does not fire.
  }

  @override
  String describeProbeWindow({int scanRows = 24}) => 'staged=$staged round=$_round';
}

/// First CR clears composer without leaving a needle (swallowed); reinject recovers.
final class _ComposerMovesDownEmptyNoNeedleThenAckPort
    implements FullscreenPtyDeliveryPort {
  _ComposerMovesDownEmptyNoNeedleThenAckPort({required this.text});

  final String text;
  String? staged;
  int pasteCount = 0;
  int crCount = 0;

  @override
  bool get isAborted => false;

  @override
  int get viewportRows => 24;

  @override
  FullscreenComposerRegionSpec get composerRegion =>
      const FullscreenComposerRegionSpec(
        submitSemantics: ComposerSubmitSemantics.regionMovedDown,
        prefixes: ['→'],
      );

  @override
  bool get isAcked => false;

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  ComposerRegion? locateComposerRegion({int scanRows = 24}) {
    if (staged == null && pasteCount >= 2 && crCount > 0) {
      // Committed on the reinject round: composer repainted below.
      return const ComposerRegion(
        topRow: 2, bottomRow: 2, leftCol: 0, rightCol: 200,
      );
    }
    if (staged == null && crCount > 0) {
      // Swallowed: the composer collapsed without committing; nothing to ACK —
      // regionMovedDown needs the repainted composer (or the staged needle).
      return null;
    }
    return const ComposerRegion(
      topRow: 0, bottomRow: 0, leftCol: 0, rightCol: 200,
    );
  }

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
    if (staged == null || !staged!.contains(needle)) return null;
    return FullscreenPromptAnchor(
      row: 0,
      startCol: staged!.indexOf(needle),
      needle: needle,
    );
  }

  @override
  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      staged != null && staged!.contains(anchor.needle);

  @override
  Future<void> clearStagedInput() async {
    staged = null;
  }

  @override
  Future<void> pasteText(String value) async {
    pasteCount++;
    staged = value;
  }

  @override
  Future<void> submitCr() async {
    crCount++;
    if (pasteCount == 1) {
      // Swallowed: clear without transcript residual.
      staged = null;
      return;
    }
    staged = null;
  }

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      'staged=$staged paste=$pasteCount';
}

/// First CR commits (opencode regionCleared) but the mirror grid stays
/// stale, so the probe keeps reporting crStuck; the prompt-submit hook ACK
/// ([isAcked] predicate) arrives right after the CR — the authoritative
/// "message already submitted" signal.
final class _AnchorCellStuckButHookAckedPort
    implements FullscreenPtyDeliveryPort {
  _AnchorCellStuckButHookAckedPort({required this.text});

  final String text;
  bool submitted = false;
  int pasteCount = 0;
  int crCount = 0;
  String? staged;

  @override
  bool get isAborted => false;

  @override
  int get viewportRows => 24;

  @override
  FullscreenComposerRegionSpec get composerRegion =>
      const FullscreenComposerRegionSpec(
        submitSemantics: ComposerSubmitSemantics.regionCleared,
        prefixes: ['\u2503'],
      );

  @override
  bool get isAcked => false;

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  ComposerRegion? locateComposerRegion({int scanRows = 24}) =>
      staged == null
          ? null
          : const ComposerRegion(
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
    return FullscreenPromptAnchor(
      row: 0,
      startCol: staged!.indexOf(needle),
      needle: needle,
    );
  }

  @override
  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      staged != null && staged!.contains(anchor.needle);

  @override
  Future<void> clearStagedInput() async {
    staged = null;
  }

  @override
  Future<void> pasteText(String value) async {
    pasteCount++;
    staged = value;
  }

  @override
  Future<void> submitCr() async {
    crCount++;
    // The CLI really did commit the message.
    submitted = true;
  }

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      'submitted=$submitted staged=$staged';
}

/// regionMovedDown on a full viewport: the composer is pinned to the last
/// grid row and repaints at the SAME bottom row after CR — the row comparison
/// can never ACK; only the needle leaving the region proves the submit.
final class _BottomPinnedRegionClearedPort implements FullscreenPtyDeliveryPort {
  _BottomPinnedRegionClearedPort({required this.text});

  final String text;
  String? staged;
  String? transcript;
  int pasteCount = 0;
  int crCount = 0;

  @override
  bool get isAborted => false;

  @override
  int get viewportRows => 24;

  @override
  FullscreenComposerRegionSpec get composerRegion =>
      const FullscreenComposerRegionSpec(
        submitSemantics: ComposerSubmitSemantics.regionMovedDown,
        prefixes: ['→'],
      );

  @override
  bool get isAcked => false;

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  ComposerRegion? locateComposerRegion({int scanRows = 24}) =>
      const ComposerRegion(
        topRow: 0,
        bottomRow: 23, // grid rows - 1: bottom-pinned on a full viewport
        leftCol: 0,
        rightCol: 200,
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
      transcript != null && transcript!.contains(needle);

  @override
  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    // Transcript text is NOT visible to the needle probe (transcript above the
    // probe window) — only staged input anchors.
    if (staged == null || !staged!.contains(needle)) return null;
    return FullscreenPromptAnchor(
      row: 0,
      startCol: staged!.indexOf(needle),
      needle: needle,
    );
  }

  @override
  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      staged != null && staged!.contains(anchor.needle);

  @override
  Future<void> clearStagedInput() async {
    staged = null;
  }

  @override
  Future<void> pasteText(String value) async {
    pasteCount++;
    staged = value;
  }

  @override
  Future<void> submitCr() async {
    crCount++;
    if (staged != null) {
      transcript = staged;
      staged = null;
    }
  }

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      'staged=$staged transcript=$transcript';
}

/// regionCleared where the composer collapses after CR (region null) and the
/// message leaves the probe window entirely — must ACK, not reinject.
final class _RegionClearedNullAfterSubmitPort
    implements FullscreenPtyDeliveryPort {
  _RegionClearedNullAfterSubmitPort({required this.text});

  final String text;
  String? staged;
  int pasteCount = 0;
  int crCount = 0;

  @override
  bool get isAborted => false;

  @override
  int get viewportRows => 24;

  @override
  FullscreenComposerRegionSpec get composerRegion =>
      const FullscreenComposerRegionSpec(
        submitSemantics: ComposerSubmitSemantics.regionCleared,
        prefixes: ['\u2503'],
      );

  @override
  bool get isAcked => false;

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  ComposerRegion? locateComposerRegion({int scanRows = 24}) =>
      staged == null
          ? null
          : const ComposerRegion(
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
    if (staged == null || !staged!.contains(needle)) return null;
    return FullscreenPromptAnchor(
      row: 0,
      startCol: staged!.indexOf(needle),
      needle: needle,
    );
  }

  @override
  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      staged != null && staged!.contains(anchor.needle);

  @override
  Future<void> clearStagedInput() async {
    staged = null;
  }

  @override
  Future<void> pasteText(String value) async {
    pasteCount++;
    staged = value;
  }

  @override
  Future<void> submitCr() async {
    crCount++;
    staged = null;
  }

  @override
  String describeProbeWindow({int scanRows = 24}) => 'staged=$staged';
}

/// regionCleared where the region is transiently null after CR but the staged
/// needle is still visible — the message is NOT committed; must keep polling
/// (and eventually reinject) instead of false-ACKing.
final class _RegionClearedNullWithVisibleNeedlePort
    implements FullscreenPtyDeliveryPort {
  _RegionClearedNullWithVisibleNeedlePort({required this.text});

  final String text;
  String? staged;
  int pasteCount = 0;
  int crCount = 0;

  @override
  bool get isAborted => false;

  @override
  int get viewportRows => 24;

  @override
  FullscreenComposerRegionSpec get composerRegion =>
      const FullscreenComposerRegionSpec(
        submitSemantics: ComposerSubmitSemantics.regionCleared,
        prefixes: ['\u2503'],
      );

  @override
  bool get isAcked => false;

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  ComposerRegion? locateComposerRegion({int scanRows = 24}) =>
      crCount > 0 ? null : const ComposerRegion(
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
      staged != null && staged!.contains(needle);

  @override
  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    if (staged == null || !staged!.contains(needle)) return null;
    return FullscreenPromptAnchor(
      row: 0,
      startCol: staged!.indexOf(needle),
      needle: needle,
    );
  }

  @override
  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      staged != null && staged!.contains(anchor.needle);

  @override
  Future<void> clearStagedInput() async {
    staged = null;
  }

  @override
  Future<void> pasteText(String value) async {
    pasteCount++;
    staged = value;
  }

  @override
  Future<void> submitCr() async {
    crCount++;
    // CR never commits: staged text stays in the window.
  }

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      'staged=$staged crCount=$crCount';
}
