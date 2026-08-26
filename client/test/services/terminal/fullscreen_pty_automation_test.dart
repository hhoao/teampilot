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

    test('returns pasteNotFound without internally re-pasting', () async {
      final port = FakeFullscreenPtyDeliveryPort(pastesBeforeVisible: 2);
      const text = '和你的队员打个招呼吧';

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: text,
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.pasteNotFound);
      expect(port.pasteCount, 1);
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
      final long = 'deploy jar\n${'x' * 80}\nxl-control.jar\n449 MB';

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

    test('composerMovesDown waits pasteSettle after needle before CR', () async {
      final port = _TimestampedPastePort();
      final delay = FullscreenPtyAutomation(timing: PtyAutomationTiming.instant());

      await delay.deliverPasteAndSubmit(
        port: port,
        text: 'hello',
        pasteSettle: const Duration(milliseconds: 80),
      );

      expect(port.needleSeenAt, isNotNull);
      expect(port.crAt, isNotNull);
      expect(
        port.crAt!.difference(port.needleSeenAt!).inMilliseconds,
        greaterThanOrEqualTo(80),
        reason:
            'Codex/Cursor still in bracketed-paste when the needle first '
            'paints; CR before paste-end becomes a newline, not submit',
      );
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
    test('does not re-paste when text is not visible', () async {
      final port = FakeFullscreenPtyDeliveryPort();

      final outcome = await automation.retry(
        port: port,
        text: TeamBus.doorbellNotice,
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.pasteNotFound);
      expect(port.pasteCount, 0);
    });

    test('only nudges CR when text is already visible', () async {
      final port = FakeFullscreenPtyDeliveryPort()
        ..staged = TeamBus.doorbellNotice;

      final outcome = await automation.retry(
        port: port,
        text: TeamBus.doorbellNotice,
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(port.pasteCount, 0);
      expect(port.clearCount, 0);
      expect(port.crCount, 1);
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

  test('hook confirmation after first CR prevents all later automated CRs',
      () async {
    final port = _AnchorCellStuckButHookAckedPort(text: 'A');
    var confirmed = false;
    bool canExecute() {
      if (port.crCount > 0) confirmed = true;
      return !confirmed;
    }

    final outcome = await automation.deliverPasteAndSubmit(
      port: port,
      text: 'A',
      pasteSettle: Duration.zero,
      isAcked: () => !canExecute(),
    );

    expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
    expect(port.crCount, 1);
  });
}

final class _TimestampedPastePort implements FullscreenPtyDeliveryPort {
  _TimestampedPastePort()
    : _inner = FakeFullscreenPtyDeliveryPort(
        crAckConfig: const FullscreenCrAckConfig(
          strategy: FullscreenCrAckStrategy.composerMovesDown,
          composerPrefix: '\u203a',
        ),
      );

  final FakeFullscreenPtyDeliveryPort _inner;
  DateTime? needleSeenAt;
  DateTime? crAt;

  @override
  bool get isAborted => _inner.isAborted;

  @override
  int get viewportRows => _inner.viewportRows;

  @override
  FullscreenCrAckConfig get crAckConfig => _inner.crAckConfig;

  @override
  Future<void> syncDisplayGrid() => _inner.syncDisplayGrid();

  @override
  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    final anchor = _inner.locateNeedle(needle, scanRows: scanRows);
    if (anchor != null) needleSeenAt ??= DateTime.now();
    return anchor;
  }

  @override
  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      _inner.locateCollapsedPasteNeedle(scanRows: scanRows);

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) => _inner.isAtAnchor(anchor);

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) =>
      _inner.isSubmittedAfterCr(anchor, scanRows: scanRows);

  @override
  bool isComposerChromeEmpty({int scanRows = 24}) =>
      _inner.isComposerChromeEmpty(scanRows: scanRows);

  @override
  bool isNeedleStagedInComposer(String needle, {int scanRows = 24}) =>
      _inner.isNeedleStagedInComposer(needle, scanRows: scanRows);

  @override
  Future<void> clearStagedInput() => _inner.clearStagedInput();

  @override
  Future<void> pasteText(String text, {bool Function()? canExecute}) =>
      _inner.pasteText(text, canExecute: canExecute);

  @override
  Future<void> submitCr({bool Function()? canExecute}) async {
    crAt ??= DateTime.now();
    await _inner.submitCr();
  }

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      _inner.describeProbeWindow(scanRows: scanRows);
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
  bool isNeedleStagedInComposer(String needle, {int scanRows = 24}) =>
      !_submitted && _staged != null && _staged!.contains(needle);

  @override
  Future<void> clearStagedInput() async {
    _staged = null;
    _submitted = false;
  }

  @override
  Future<void> pasteText(String text, {bool Function()? canExecute}) async {
    _staged = text;
    _submitted = false;
  }

  @override
  Future<void> submitCr({bool Function()? canExecute}) async {
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
// ignore: unused_element
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
  bool isNeedleStagedInComposer(String needle, {int scanRows = 24}) =>
      _composerBody != null && _composerBody!.contains(needle);

  @override
  Future<void> clearStagedInput() async {
    _composerBody = null;
  }

  @override
  Future<void> pasteText(String value, {bool Function()? canExecute}) async {
    pasteCount++;
    _composerBody = value;
  }

  @override
  Future<void> submitCr({bool Function()? canExecute}) async {
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
// ignore: unused_element
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
  bool isNeedleStagedInComposer(String needle, {int scanRows = 24}) =>
      staged != null && staged!.contains(needle);

  @override
  Future<void> clearStagedInput() async {
    staged = null;
  }

  @override
  Future<void> pasteText(String value, {bool Function()? canExecute}) async {
    pasteCount++;
    if (pasteCount > 1) _round = 1;
    staged = value;
  }

  @override
  Future<void> submitCr({bool Function()? canExecute}) async {
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
// ignore: unused_element
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
  bool isNeedleStagedInComposer(String needle, {int scanRows = 24}) =>
      staged != null && staged!.contains(needle);

  @override
  Future<void> clearStagedInput() async {
    staged = null;
  }

  @override
  Future<void> pasteText(String value, {bool Function()? canExecute}) async {
    pasteCount++;
    staged = value;
  }

  @override
  Future<void> submitCr({bool Function()? canExecute}) async {
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

/// First CR commits (opencode anchorCellClears) but the mirror grid stays
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
  FullscreenCrAckConfig get crAckConfig => const FullscreenCrAckConfig(
    strategy: FullscreenCrAckStrategy.anchorCellClears,
    composerPrefix: '\u2503',
  );

  @override
  Future<void> syncDisplayGrid() async {}

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
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) =>
      // Stale mirror: never reflects the commit.
      false;

  @override
  bool isComposerChromeEmpty({int scanRows = 24}) => !submitted;

  @override
  bool isNeedleStagedInComposer(String needle, {int scanRows = 24}) =>
      !submitted && staged != null && staged!.contains(needle);

  @override
  Future<void> clearStagedInput() async {
    staged = null;
  }

  @override
  Future<void> pasteText(String value, {bool Function()? canExecute}) async {
    pasteCount++;
    staged = value;
  }

  @override
  Future<void> submitCr({bool Function()? canExecute}) async {
    crCount++;
    // The CLI really did commit the message.
    submitted = true;
  }

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      'submitted=$submitted staged=$staged';
}
