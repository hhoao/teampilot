import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cursor/capabilities/terminal_behavior.dart';
import 'package:teampilot/services/terminal/fullscreen_cr_ack_config.dart';
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

    test('anchorCellClears never skips reinject via guard', () async {
      final port = FakeFullscreenPtyDeliveryPort(
        crsToClear: 999,
        composerChromeEmptyOverride: true,
      );

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: 'hello',
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
  FullscreenCrAckConfig get crAckConfig => FullscreenCrAckConfig(
    strategy: const CursorTerminalBehavior().fullscreenCrAckStrategy,
    composerPrefix: const CursorTerminalBehavior().fullscreenComposerPrefix,
  );

  @override
  Future<void> syncDisplayGrid() async {}

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
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) {
    if (!_submitted) return false;
    return switch (crAckConfig.strategy) {
      FullscreenCrAckStrategy.timed => true,
      FullscreenCrAckStrategy.anchorCellClears => !isAtAnchor(anchor),
      FullscreenCrAckStrategy.composerMovesDown =>
        crAckConfig.composerPrefix == '→',
    };
  }

  @override
  bool isComposerChromeEmpty({int scanRows = 24}) => _submitted;

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
  FullscreenCrAckConfig get crAckConfig => FullscreenCrAckConfig(
    strategy: FullscreenCrAckStrategy.composerMovesDown,
    composerPrefix: '→',
  );

  @override
  Future<void> syncDisplayGrid() async {}

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
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) =>
      false;

  @override
  bool isComposerChromeEmpty({int scanRows = 24}) =>
      _composerBody == null || _composerBody!.trim().isEmpty;

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
  FullscreenCrAckConfig get crAckConfig => FullscreenCrAckConfig(
    strategy: FullscreenCrAckStrategy.composerMovesDown,
    composerPrefix: '→',
  );

  @override
  Future<void> syncDisplayGrid() async {}

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
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) {
    // Round 0 (first paste): never ACK. After reinject paste, ACK on CR.
    return _round >= 1 && crCount > 0 && staged == null;
  }

  @override
  bool isComposerChromeEmpty({int scanRows = 24}) =>
      staged == null || staged!.trim().isEmpty;

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
  FullscreenCrAckConfig get crAckConfig => FullscreenCrAckConfig(
    strategy: FullscreenCrAckStrategy.composerMovesDown,
    composerPrefix: '→',
  );

  @override
  Future<void> syncDisplayGrid() async {}

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
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) {
    // ACK only after second paste's CR (pasteCount >= 2 and cleared).
    return pasteCount >= 2 && staged == null && crCount > 0;
  }

  @override
  bool isComposerChromeEmpty({int scanRows = 24}) =>
      staged == null || staged!.trim().isEmpty;

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
