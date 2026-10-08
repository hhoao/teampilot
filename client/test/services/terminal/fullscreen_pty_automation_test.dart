import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cursor/capabilities/terminal_behavior.dart';
import 'package:teampilot/services/chat/runtime/pty/fullscreen_cr_ack_config.dart';
import 'package:teampilot/services/chat/runtime/pty/fullscreen_input_screen_probe.dart';
import 'package:teampilot/services/chat/runtime/pty/fullscreen_pty_automation.dart';
import 'package:teampilot/services/chat/runtime/pty/fullscreen_pty_submission_machine.dart';
import 'package:teampilot/services/chat/runtime/pty/fullscreen_pty_delivery_port.dart';
import 'package:teampilot/services/chat/team_bus/team_bus.dart';

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

    test('retries staging within budget then returns pasteNotFound', () async {
      final port = FakeFullscreenPtyDeliveryPort(pastesBeforeVisible: 5);
      const text = '和你的队员打个招呼吧';

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: text,
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.pasteNotFound);
      // instant staging budget = 2: first paste + one retry, then give up.
      expect(port.pasteCount, 2);
    });

    test(
      'single-attempt staging budget returns pasteNotFound after one paste',
      () {
        final single = FullscreenPtyAutomation(
          timing: const PtyAutomationTiming(
            afterClear: Duration.zero,
            afterPaste: Duration.zero,
            afterCr: Duration.zero,
            afterReinject: Duration.zero,
            crMaxAttempts: 2,
            reinjectMaxAttempts: 1,
            nudgeMaxAttempts: 2,
            scanRows: 24,
            pollTimeout: Duration.zero,
            pollInterval: Duration.zero,
            stagingMaxAttempts: 1,
            stagingRetryInterval: Duration.zero,
            sendAckTimeout: Duration.zero,
          ),
        );
        return () async {
          final port = FakeFullscreenPtyDeliveryPort(pastesBeforeVisible: 2);
          final outcome = await single.deliverPasteAndSubmit(
            port: port,
            text: 'never lands',
            pasteSettle: Duration.zero,
          );
          expect(outcome, FullscreenPtyDeliveryOutcome.pasteNotFound);
          expect(port.pasteCount, 1);
        }();
      },
    );

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

    test(
      'accepts cursor submit when transcript keeps the submitted text',
      () async {
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
      },
    );

    test(
      'pastes even when resume transcript already shows the same text',
      () async {
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
      },
    );

    test(
      'paste ACK proceeds on waitForPaint without waiting pollInterval',
      () async {
        final port = _PaintWakePort();
        final automation = FullscreenPtyAutomation(
          timing: const PtyAutomationTiming(
            afterClear: Duration.zero,
            afterPaste: Duration.zero,
            afterCr: Duration.zero,
            afterReinject: Duration.zero,
            crMaxAttempts: 2,
            reinjectMaxAttempts: 1,
            nudgeMaxAttempts: 2,
            scanRows: 24,
            pollTimeout: Duration(seconds: 2),
            pollInterval: Duration(milliseconds: 200),
          ),
        );
        final sw = Stopwatch()..start();
        final outcome = await automation.deliverPasteAndSubmit(
          port: port,
          text: 'needle-text',
          pasteSettle: Duration.zero,
        );
        sw.stop();
        expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
        expect(sw.elapsedMilliseconds, lessThan(150));
      },
    );

    test(
      'CR ACK proceeds on waitForPaint when submit frame arrives late',
      () async {
        final port = _LateCrAckPaintPort();
        final automation = FullscreenPtyAutomation(
          timing: const PtyAutomationTiming(
            afterClear: Duration.zero,
            afterPaste: Duration.zero,
            afterCr: Duration.zero,
            afterReinject: Duration.zero,
            crMaxAttempts: 2,
            reinjectMaxAttempts: 1,
            nudgeMaxAttempts: 2,
            scanRows: 24,
            pollTimeout: Duration(seconds: 2),
            pollInterval: Duration(milliseconds: 200),
          ),
        );
        final sw = Stopwatch()..start();
        final outcome = await automation.deliverPasteAndSubmit(
          port: port,
          text: 'inspect this',
          pasteSettle: Duration.zero,
        );
        sw.stop();
        expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
        expect(sw.elapsedMilliseconds, lessThan(150));
        expect(port.crAckPaintWaits, greaterThan(0));
      },
    );

    test(
      'composerMovesDown waits pasteSettle after needle before CR',
      () async {
        final port = _TimestampedPastePort();
        final delay = FullscreenPtyAutomation(
          timing: PtyAutomationTiming.instant(),
        );

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
      },
    );
  });

  group('continueSubmission (state-machine driven)', () {
    FullscreenPtySubmission newMachine({
      FullscreenPtySubmissionBudget? budget,
    }) => FullscreenPtySubmission(
      budget:
          budget ?? const FullscreenPtySubmissionBudget(stagingMaxAttempts: 2),
      now: DateTime.now,
    );

    test(
      're-pastes from staging when text is not visible on the grid',
      () async {
        final machine = newMachine()..begin();
        final port = FakeFullscreenPtyDeliveryPort();
        final text = TeamBus.doorbellNotice;

        final outcome = await automation.continueSubmission(
          machine,
          port: port,
          text: text,
          pasteSettle: Duration.zero,
        );

        expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
        expect(
          port.pasteCount,
          1,
          reason:
              'deferred / pasteNotFound retries must re-paste; CR-only leaves '
              'the composer empty forever',
        );
        expect(port.crCount, 1);
      },
    );

    test('locked pasted only nudges CR and never re-pastes', () async {
      final machine = newMachine()..begin();
      // Simulate the previous attempt already having staged the message.
      machine.noteNeedleFound();
      final port = FakeFullscreenPtyDeliveryPort()
        ..staged = TeamBus.doorbellNotice;

      final outcome = await automation.continueSubmission(
        machine,
        port: port,
        text: TeamBus.doorbellNotice,
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(port.pasteCount, 0);
      expect(port.clearCount, 0);
      expect(port.crCount, 1);
    });

    test(
      'hookSubmitAck: grid submit false-positive does not report submitted',
      () async {
        // Resume bug regression: even if the grid probe (composerMovesDown)
        // reports submitted on a transcript echo, hookSubmitAck must wait for
        // the real hook confirmation and end crStuck — never "running but not
        // sent".
        final machine = newMachine()..begin();
        final port = FakeFullscreenPtyDeliveryPort(
          crAckConfig: const FullscreenCrAckConfig(
            strategy: FullscreenCrAckStrategy.composerMovesDown,
            hookSubmitAck: true,
          ),
          crsToClear: 1,
        )..staged = TeamBus.doorbellNotice; // grid would ACK this

        final outcome = await automation.continueSubmission(
          machine,
          port: port,
          text: TeamBus.doorbellNotice,
          pasteSettle: Duration.zero,
          isAcked: () => false, // hook never confirms
        );

        expect(
          outcome,
          FullscreenPtyDeliveryOutcome.crStuck,
          reason:
              'without the hook confirmation the submit must stay unconfirmed, '
              'even though the grid would report submitted',
        );
      },
    );

    test(
      'hookSubmitAck: hook confirmation returns submitted immediately',
      () async {
        final machine = newMachine()..begin();
        final port = FakeFullscreenPtyDeliveryPort(
          crAckConfig: const FullscreenCrAckConfig(
            strategy: FullscreenCrAckStrategy.composerMovesDown,
            hookSubmitAck: true,
          ),
        );

        // Only confirm once CR rides — asserts the hook-only path really
        // reaches _hookOnlyCr and honors the hook (not an early staging ack).
        final outcome = await automation.continueSubmission(
          machine,
          port: port,
          text: TeamBus.doorbellNotice,
          pasteSettle: Duration.zero,
          isAcked: () => port.crCount > 0,
        );

        expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
        expect(port.crCount, greaterThanOrEqualTo(1));
      },
    );

    test('skips everything when hook already acked the submit', () async {
      final machine = newMachine()..begin();
      final port = FakeFullscreenPtyDeliveryPort();

      final outcome = await automation.continueSubmission(
        machine,
        port: port,
        text: TeamBus.doorbellNotice,
        pasteSettle: Duration.zero,
        isAcked: () => true,
      );

      expect(
        outcome,
        FullscreenPtyDeliveryOutcome.submitted,
        reason:
            'hook confirmed the prompt already committed; retry re-paste '
            'would duplicate the user row',
      );
      expect(port.pasteCount, 0);
      expect(port.crCount, 0);
    });

    test(
      'repeated identical short message ACKs the newly pasted copy, not the stale echo',
      () async {
        // Regression for "send the same short message twice": the first render
        // sits on an upper row (transcript echo); the freshly pasted copy lands
        // on a lower row in the input box. The paste-denominator baseline must
        // require the new line, otherwise the second send locks onto the first.
        final machine = newMachine()..begin();
        final text = TeamBus.doorbellNotice;
        final port = RowAwareFakeFullscreenPtyDeliveryPort(staleEcho: text);

        final outcome = await automation.continueSubmission(
          machine,
          port: port,
          text: text,
          pasteSettle: Duration.zero,
        );

        expect(
          outcome,
          FullscreenPtyDeliveryOutcome.submitted,
          reason:
              'second identical send must stage on the fresh row below the '
              'stale echo, not confuse it with the already-present line',
        );
        expect(port.pasteCount, 1);
        expect(port.crCount, greaterThanOrEqualTo(1));
      },
    );

    test(
      'failed paste with same-text echo above baseline ends pasteNotFound, not a false success',
      () async {
        // If the new paste does not land, the only match is the stale echo at
        // the baseline row. The strict (<=) baseline must reject it — otherwise
        // a dropped paste would be ACKed as staged and a stray CR sent.
        final machine = newMachine()..begin();
        final text = TeamBus.doorbellNotice;
        final port = RowAwareFakeFullscreenPtyDeliveryPort(
          pasteFailsToStage: true,
          staleEcho: text,
        );

        final outcome = await automation.continueSubmission(
          machine,
          port: port,
          text: text,
          pasteSettle: Duration.zero,
        );

        expect(
          outcome,
          FullscreenPtyDeliveryOutcome.pasteNotFound,
          reason:
              'a paste that never staged must not be ACKed by the stale echo '
              'at the baseline row (<= check) or reported as submitted',
        );
      },
    );

    test(
      'paste baseline drains the grid after clear so leftover composer text is not the baseline',
      () async {
        // Cursor: leftover "A" is still in the composer when staging starts.
        // Ctrl-U clears the live TUI, but the probe grid lags until
        // syncDisplayGrid (drainForTest). Baseline must read the post-clear
        // drain, otherwise pre and post paste both sit on the composer row
        // and stale-baseline rejects a successful paste forever.
        final machine = newMachine()..begin();
        final port = RowAwareFakeFullscreenPtyDeliveryPort(laggingProbe: true)
          ..staged = 'A';

        final outcome = await automation.continueSubmission(
          machine,
          port: port,
          text: 'A',
          pasteSettle: Duration.zero,
        );

        expect(
          outcome,
          FullscreenPtyDeliveryOutcome.submitted,
          reason:
              'clearing leftover composer text must refresh the probe grid '
              'before the paste-denominator baseline is recorded',
        );
        expect(port.clearCount, greaterThanOrEqualTo(1));
        expect(port.pasteCount, 1);
        expect(port.crCount, greaterThanOrEqualTo(1));
      },
    );

    test(
      'paste baseline polls after clear until leftover composer text leaves the probe',
      () async {
        // Production: drainForTest only applies PTY bytes already in the
        // buffer. Ctrl-U's redraw can arrive after the first post-clear
        // snapshot, so leftover "A" is still on the composer row and a
        // same-row paste is rejected as stale-baseline (real Cursor
        // AskQuestion log: needle="A" pre=34 anchor=34).
        final polling = FullscreenPtyAutomation(
          timing: const PtyAutomationTiming(
            afterClear: Duration.zero,
            afterPaste: Duration.zero,
            afterCr: Duration.zero,
            afterReinject: Duration.zero,
            crMaxAttempts: 2,
            reinjectMaxAttempts: 1,
            nudgeMaxAttempts: 2,
            scanRows: 24,
            pollTimeout: Duration(milliseconds: 50),
            pollInterval: Duration(milliseconds: 1),
            stagingMaxAttempts: 1,
            stagingRetryInterval: Duration.zero,
            sendAckTimeout: Duration.zero,
          ),
        );
        final machine = FullscreenPtySubmission(
          budget: const FullscreenPtySubmissionBudget(stagingMaxAttempts: 1),
          now: DateTime.now,
        )..begin();
        final port = RowAwareFakeFullscreenPtyDeliveryPort(
          laggingProbe: true,
          probeLagAfterClear: 1,
        )..staged = 'A';

        final outcome = await polling.continueSubmission(
          machine,
          port: port,
          text: 'A',
          pasteSettle: Duration.zero,
        );

        expect(
          outcome,
          FullscreenPtyDeliveryOutcome.submitted,
          reason:
              'baseline must wait until leftover composer text leaves the '
              'probe, not record the first post-clear snapshot',
        );
        expect(port.pasteCount, 1);
        expect(port.crCount, greaterThanOrEqualTo(1));
      },
    );
  });

  test('isTextVisible uses PtyAutomationNeedle', () {
    final port = FakeFullscreenPtyDeliveryPort()..staged = '和你的队员打个招呼吧';
    expect(automation.isTextVisible(port, '和你的队员打个招呼吧'), isTrue);
  });

  group('CR retry (swallowed during TUI startup)', () {
    // Regression (2026-09-08, real codex 0.151.0): the composer readiness gate
    // passes while codex is still starting MCP servers; the paste stages, the
    // single submit CR is swallowed by the busy TUI, and the delivery ends
    // crStuck / unconfirmed with the text stuck in the composer forever.
    const codexCrAck = FullscreenCrAckConfig(
      strategy: FullscreenCrAckStrategy.composerMovesDown,
    );

    test('re-CRs when startup overlay swallowed the first CRs', () async {
      // Two CRs swallowed (MCP boot), third submits — like a human pressing
      // Enter again.
      final port = FakeFullscreenPtyDeliveryPort(
        crsToClear: 3,
        crAckConfig: codexCrAck,
      );

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: 'hello',
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(
        port.crCount,
        3,
        reason:
            'needle still staged in composer proves the earlier CRs '
            'were swallowed — retry until the TUI accepts the submit',
      );
    });

    test(
      'bounded: never-submitting composer ends crStuck after 3 CRs',
      () async {
        final port = FakeFullscreenPtyDeliveryPort(
          crsToClear: 99,
          crAckConfig: codexCrAck,
        );

        final outcome = await automation.deliverPasteAndSubmit(
          port: port,
          text: 'hello',
          pasteSettle: Duration.zero,
        );

        expect(outcome, FullscreenPtyDeliveryOutcome.crStuck);
        expect(port.crCount, 3, reason: 'instant timing: crMaxAttempts=2');
      },
    );

    test(
      'needle moved to transcript (not composer) blocks the re-CR guard',
      () async {
        // Cursor shape: CR committed the text into transcript history; the
        // composer repaints empty and the ACK never fires. Re-CR would risk a
        // duplicate user row — the guard must refuse. The post-guard verdict
        // poll recognizes the submit (needle left the composer).
        final port = _ComposerMovesDownStuckButCommittedPort(text: 'hello');

        final outcome = await automation.deliverPasteAndSubmit(
          port: port,
          text: 'hello',
          pasteSettle: Duration.zero,
        );

        expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
        expect(
          port.crCount,
          1,
          reason:
              'needle no longer the body of a composer row — resend '
              'guard must treat it as possibly-submitted; the final verdict '
              'poll (echo above, fresh composer below) reads it as submitted',
        );
      },
    );

    test(
      'guard-break with ambiguous grid still ends crStuck (unconfirmed)',
      () async {
        // The verdict poll cannot prove a submit (e.g. composer chrome still
        // below an unchanged anchor) — the delivery must stay unconfirmed
        // rather than guess submitted.
        final port = _ComposerMovesDownStuckButCommittedPort(text: 'hello')
          ..isSubmittedVerdictOnCall = 0;

        final outcome = await automation.deliverPasteAndSubmit(
          port: port,
          text: 'hello',
          pasteSettle: Duration.zero,
        );

        expect(outcome, FullscreenPtyDeliveryOutcome.crStuck);
        expect(port.crCount, 1);
      },
    );
  });

  test(
    'hook confirmation after first CR prevents all later automated CRs',
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
    },
  );

  test(
    'hook ack checked before abort when confirmation closes the fence',
    () async {
      // Regression: the delivery fence closes when the hook confirms the
      // submit (state leaves submitIssued). The aborted() port predicate
      // consulted !canExecute() and read as "aborted" even though the message
      // was committed — isAcked must be consulted first.
      final port = _AbortedAfterHookAckPort();

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: 'A',
        pasteSettle: Duration.zero,
        isAcked: () => port.crCount > 0,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(port.crCount, 1, reason: 'no extra CR after hook confirmation');
    },
  );

  test('mention text dismisses the autocomplete popup before CR', () async {
    // Regression (2026-09-04, verified against real Claude Code 2.1.211 in
    // a PTY): pasting text containing "@path" opens the file-mention
    // autocomplete; the submit CR is consumed by the popup, the message is
    // never committed, and the CR-ack poll reports crStuck. Dismissing the
    // popup with ESC before CR lets the CR submit normally.
    final port = _MentionPopupSwallowsCrPort();

    final outcome = await automation.deliverPasteAndSubmit(
      port: port,
      text: '看下这个文件 @/etc/hostname',
      pasteSettle: Duration.zero,
      dismissMentionPopup: true,
    );

    expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
    expect(port.dismissCount, 1, reason: 'ESC sent before the CR');
    expect(port.crCount, 1);
  });

  test('plain text without @ does not send the popup dismiss ESC', () async {
    final port = _MentionPopupSwallowsCrPort();

    final outcome = await automation.deliverPasteAndSubmit(
      port: port,
      text: 'no mention here',
      pasteSettle: Duration.zero,
      dismissMentionPopup: true,
    );

    expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
    expect(port.dismissCount, 0);
  });

  test(
    'mention text without the dismiss flag keeps CR-only behavior',
    () async {
      final port = _MentionPopupSwallowsCrPort();

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: '看下这个文件 @/etc/hostname',
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.crStuck);
      expect(port.dismissCount, 0);
    },
  );

  test('waits after popup-dismiss ESC before the submit CR', () async {
    // Regression (2026-09-05, verified against real Claude Code 2.1.211 in
    // a PTY): the ESC written by dismissComposerPopup followed immediately
    // by the CR is read by the TUI as one chunk and parsed as ESC+CR =
    // Alt+Enter — insert-newline. The message stays staged in the composer
    // with a blank line below it and the submit never commits (chat UI
    // stuck "waiting"). ≥100ms between the ESC and the CR submits normally
    // (50ms still fails), so the automation must settle after the ESC.
    final port = _MentionPopupSwallowsCrPort();
    final escAware = FullscreenPtyAutomation(
      timing: const PtyAutomationTiming(
        afterClear: Duration.zero,
        afterPaste: Duration.zero,
        afterCr: Duration.zero,
        afterReinject: Duration.zero,
        crMaxAttempts: 2,
        reinjectMaxAttempts: 1,
        nudgeMaxAttempts: 2,
        scanRows: 24,
        pollTimeout: Duration.zero,
        afterDismissPopup: Duration(milliseconds: 80),
      ),
    );

    final outcome = await escAware.deliverPasteAndSubmit(
      port: port,
      text: '看下这个文件 @/etc/hostname',
      pasteSettle: Duration.zero,
      dismissMentionPopup: true,
    );

    expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
    expect(port.dismissAt, isNotNull);
    expect(port.crAt, isNotNull);
    expect(
      port.crAt!.difference(port.dismissAt!).inMilliseconds,
      greaterThanOrEqualTo(80),
      reason:
          'ESC immediately followed by CR coalesces into Alt+Enter in the '
          'Ink composer — the CR becomes a newline instead of a submit',
    );
  });
}

final class _TimestampedPastePort implements FullscreenPtyDeliveryPort {
  _TimestampedPastePort()
    : _inner = FakeFullscreenPtyDeliveryPort(
        crAckConfig: const FullscreenCrAckConfig(
          strategy: FullscreenCrAckStrategy.composerMovesDown,
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
  int get cursorRow => _inner.cursorRow;

  @override
  int get pasteZoneComposerRow => _inner.pasteZoneComposerRow;

  @override
  FullscreenCrAckConfig get crAckConfig => _inner.crAckConfig;

  @override
  Future<void> syncDisplayGrid() => _inner.syncDisplayGrid();

  @override
  Future<void> waitForPaint({required Duration timeout}) =>
      _inner.waitForPaint(timeout: timeout);

  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    final anchor = _inner.locateNeedle(needle, scanRows: scanRows);
    if (anchor != null) needleSeenAt ??= DateTime.now();
    return anchor;
  }

  @override
  FullscreenPromptAnchor? locatePasteZoneNeedle(
    String needle, {
    int scanRows = 24,
  }) => locateNeedle(needle, scanRows: scanRows);

  @override
  FullscreenPromptAnchor? locateCollapsedPasteZoneNeedle({int scanRows = 24}) =>
      locateCollapsedPasteNeedle(scanRows: scanRows);

  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      _inner.locateCollapsedPasteNeedle(scanRows: scanRows);

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) => _inner.isAtAnchor(anchor);
  @override
  bool isNeedleStagedInCursorZone(String needle) =>
      isAtAnchor(FullscreenPromptAnchor(row: 0, startCol: 0, needle: needle));

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) =>
      _inner.isSubmittedAfterCr(anchor, scanRows: scanRows);

  @override
  Future<void> clearStagedInput({bool Function()? canExecute}) =>
      _inner.clearStagedInput(canExecute: canExecute);

  @override
  Future<void> pasteText(String text, {bool Function()? canExecute}) =>
      _inner.pasteText(text, canExecute: canExecute);

  @override
  Future<void> submitCr({bool Function()? canExecute}) async {
    crAt ??= DateTime.now();
    await _inner.submitCr();
  }

  @override
  Future<void> dismissComposerPopup() async {}

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
  int get cursorRow => -1;

  @override
  int get pasteZoneComposerRow => -1;

  @override
  FullscreenCrAckConfig get crAckConfig => FullscreenCrAckConfig(
    strategy: const CursorTerminalBehavior().fullscreenCrAckStrategy,
  );

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  Future<void> waitForPaint({required Duration timeout}) async {}

  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    if (_staged == null || !_staged!.contains(needle)) return null;
    return FullscreenPromptAnchor(
      row: 0,
      startCol: _staged!.indexOf(needle),
      needle: needle,
    );
  }

  @override
  FullscreenPromptAnchor? locatePasteZoneNeedle(
    String needle, {
    int scanRows = 24,
  }) => locateNeedle(needle, scanRows: scanRows);

  @override
  FullscreenPromptAnchor? locateCollapsedPasteZoneNeedle({int scanRows = 24}) =>
      locateCollapsedPasteNeedle(scanRows: scanRows);

  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) {
    return _staged != null && _staged!.contains(anchor.needle);
  }

  @override
  bool isNeedleStagedInCursorZone(String needle) =>
      _staged != null && _staged!.contains(needle);

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) {
    if (!_submitted) return false;
    return _submitted;
  }

  @override
  Future<void> clearStagedInput({bool Function()? canExecute}) async {
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
  Future<void> dismissComposerPopup() async {}

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

  /// `isSubmittedAfterCr` returns true from the Nth call onward (1-based).
  /// Models grid repaint lag: the initial post-CR poll (call 1) still sees
  /// the old frame; the verdict the post-guard check reads (call 2) sees
  /// the echo + fresh composer. 0 = never (ambiguous grid).
  int isSubmittedVerdictOnCall = 2;

  int _verdictCalls = 0;

  int pasteCount = 0;
  int crCount = 0;

  @override
  bool get isAborted => false;

  @override
  int get viewportRows => 24;

  @override
  int get cursorRow => -1;

  @override
  int get pasteZoneComposerRow => -1;

  @override
  FullscreenCrAckConfig get crAckConfig => FullscreenCrAckConfig(
    strategy: FullscreenCrAckStrategy.composerMovesDown,
  );

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  Future<void> waitForPaint({required Duration timeout}) async {}

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
  FullscreenPromptAnchor? locatePasteZoneNeedle(
    String needle, {
    int scanRows = 24,
  }) => locateNeedle(needle, scanRows: scanRows);

  @override
  FullscreenPromptAnchor? locateCollapsedPasteZoneNeedle({int scanRows = 24}) =>
      locateCollapsedPasteNeedle(scanRows: scanRows);

  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      locateNeedle(anchor.needle) != null;
  @override
  bool isNeedleStagedInCursorZone(String needle) =>
      _composerBody != null && _composerBody!.contains(needle);

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) {
    _verdictCalls++;
    return _verdictCalls >= isSubmittedVerdictOnCall &&
        isSubmittedVerdictOnCall > 0;
  }

  @override
  Future<void> clearStagedInput({bool Function()? canExecute}) async {
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
  Future<void> dismissComposerPopup() async {}

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
  int get cursorRow => -1;

  @override
  int get pasteZoneComposerRow => -1;

  @override
  FullscreenCrAckConfig get crAckConfig => FullscreenCrAckConfig(
    strategy: FullscreenCrAckStrategy.composerMovesDown,
  );

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  Future<void> waitForPaint({required Duration timeout}) async {}

  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    if (staged == null || !staged!.contains(needle)) return null;
    return FullscreenPromptAnchor(
      row: 0,
      startCol: staged!.indexOf(needle),
      needle: needle,
    );
  }

  @override
  FullscreenPromptAnchor? locatePasteZoneNeedle(
    String needle, {
    int scanRows = 24,
  }) => locateNeedle(needle, scanRows: scanRows);

  @override
  FullscreenPromptAnchor? locateCollapsedPasteZoneNeedle({int scanRows = 24}) =>
      locateCollapsedPasteNeedle(scanRows: scanRows);

  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      staged != null && staged!.contains(anchor.needle);
  @override
  bool isNeedleStagedInCursorZone(String needle) =>
      isAtAnchor(FullscreenPromptAnchor(row: 0, startCol: 0, needle: needle));

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) {
    // Round 0 (first paste): never ACK. After reinject paste, ACK on CR.
    return _round >= 1 && crCount > 0 && staged == null;
  }

  @override
  Future<void> clearStagedInput({bool Function()? canExecute}) async {
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
  Future<void> dismissComposerPopup() async {}

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      'staged=$staged round=$_round';
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
  int get cursorRow => -1;

  @override
  int get pasteZoneComposerRow => -1;

  @override
  FullscreenCrAckConfig get crAckConfig => FullscreenCrAckConfig(
    strategy: FullscreenCrAckStrategy.composerMovesDown,
  );

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  Future<void> waitForPaint({required Duration timeout}) async {}

  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    if (staged == null || !staged!.contains(needle)) return null;
    return FullscreenPromptAnchor(
      row: 0,
      startCol: staged!.indexOf(needle),
      needle: needle,
    );
  }

  @override
  FullscreenPromptAnchor? locatePasteZoneNeedle(
    String needle, {
    int scanRows = 24,
  }) => locateNeedle(needle, scanRows: scanRows);

  @override
  FullscreenPromptAnchor? locateCollapsedPasteZoneNeedle({int scanRows = 24}) =>
      locateCollapsedPasteNeedle(scanRows: scanRows);

  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      staged != null && staged!.contains(anchor.needle);
  @override
  bool isNeedleStagedInCursorZone(String needle) =>
      isAtAnchor(FullscreenPromptAnchor(row: 0, startCol: 0, needle: needle));

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) {
    // ACK only after second paste's CR (pasteCount >= 2 and cleared).
    return pasteCount >= 2 && staged == null && crCount > 0;
  }

  @override
  Future<void> clearStagedInput({bool Function()? canExecute}) async {
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
  Future<void> dismissComposerPopup() async {}

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
  int get cursorRow => -1;

  @override
  int get pasteZoneComposerRow => -1;

  @override
  FullscreenCrAckConfig get crAckConfig => const FullscreenCrAckConfig(
    strategy: FullscreenCrAckStrategy.anchorCellClears,
  );

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  Future<void> waitForPaint({required Duration timeout}) async {}

  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    if (staged == null) return null;
    return FullscreenPromptAnchor(
      row: 0,
      startCol: staged!.indexOf(needle),
      needle: needle,
    );
  }

  @override
  FullscreenPromptAnchor? locatePasteZoneNeedle(
    String needle, {
    int scanRows = 24,
  }) => locateNeedle(needle, scanRows: scanRows);

  @override
  FullscreenPromptAnchor? locateCollapsedPasteZoneNeedle({int scanRows = 24}) =>
      locateCollapsedPasteNeedle(scanRows: scanRows);

  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      staged != null && staged!.contains(anchor.needle);
  @override
  bool isNeedleStagedInCursorZone(String needle) =>
      isAtAnchor(FullscreenPromptAnchor(row: 0, startCol: 0, needle: needle));

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) =>
      // Stale mirror: never reflects the commit.
      false;

  @override
  Future<void> clearStagedInput({bool Function()? canExecute}) async {
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
  Future<void> dismissComposerPopup() async {}

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      'submitted=$submitted staged=$staged';
}

/// Claude Code @-mention popup: paste ACKs (needle visible via the popup's
/// rendering of the path), but CR is consumed selecting from the popup —
/// staged text stays in the composer and the anchor never clears. Only after
/// [dismissComposerPopup] (ESC) does CR submit.
final class _MentionPopupSwallowsCrPort implements FullscreenPtyDeliveryPort {
  String? staged;
  bool popupOpen = false;
  int pasteCount = 0;
  int crCount = 0;
  int dismissCount = 0;
  DateTime? dismissAt;
  DateTime? crAt;

  @override
  bool get isAborted => false;

  @override
  int get viewportRows => 24;

  @override
  int get cursorRow => -1;

  @override
  int get pasteZoneComposerRow => -1;

  @override
  FullscreenCrAckConfig get crAckConfig => const FullscreenCrAckConfig(
    strategy: FullscreenCrAckStrategy.anchorCellClears,
  );

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  Future<void> waitForPaint({required Duration timeout}) async {}

  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    // The popup renders the path candidates, so the needle is "visible".
    if (staged == null || !staged!.contains(needle)) return null;
    return FullscreenPromptAnchor(
      row: 0,
      startCol: staged!.indexOf(needle),
      needle: needle,
    );
  }

  @override
  FullscreenPromptAnchor? locatePasteZoneNeedle(
    String needle, {
    int scanRows = 24,
  }) => locateNeedle(needle, scanRows: scanRows);

  @override
  FullscreenPromptAnchor? locateCollapsedPasteZoneNeedle({int scanRows = 24}) =>
      locateCollapsedPasteNeedle(scanRows: scanRows);

  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      staged != null && staged!.contains(anchor.needle);
  @override
  bool isNeedleStagedInCursorZone(String needle) =>
      isAtAnchor(FullscreenPromptAnchor(row: 0, startCol: 0, needle: needle));

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) =>
      crCount > 0 && !popupOpen && staged == null;

  @override
  Future<void> clearStagedInput({bool Function()? canExecute}) async {
    staged = null;
  }

  @override
  Future<void> pasteText(String value, {bool Function()? canExecute}) async {
    pasteCount++;
    staged = value;
    popupOpen = value.contains('@');
  }

  @override
  Future<void> submitCr({bool Function()? canExecute}) async {
    crAt ??= DateTime.now();
    if (popupOpen) {
      // CR is consumed by the popup (moves its selection) — not a submit.
      return;
    }
    crCount++;
    staged = null;
  }

  @override
  Future<void> dismissComposerPopup() async {
    dismissCount++;
    dismissAt ??= DateTime.now();
    popupOpen = false;
  }

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      'staged=$staged popup=$popupOpen cr=$crCount';
}

/// First CR commits, then the delivery fence (closed by the concurrent hook
/// confirmation) makes [isAborted] read true while the mirror grid stays stale
/// and never ACKs. isAcked is the authoritative submit signal.
final class _AbortedAfterHookAckPort implements FullscreenPtyDeliveryPort {
  String? staged;
  int pasteCount = 0;
  int crCount = 0;

  @override
  bool get isAborted => crCount > 0;

  @override
  int get viewportRows => 24;

  @override
  int get cursorRow => -1;

  @override
  int get pasteZoneComposerRow => -1;

  @override
  FullscreenCrAckConfig get crAckConfig => const FullscreenCrAckConfig(
    strategy: FullscreenCrAckStrategy.anchorCellClears,
  );

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  Future<void> waitForPaint({required Duration timeout}) async {}

  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    if (staged == null || !staged!.contains(needle)) return null;
    return FullscreenPromptAnchor(
      row: 0,
      startCol: staged!.indexOf(needle),
      needle: needle,
    );
  }

  @override
  FullscreenPromptAnchor? locatePasteZoneNeedle(
    String needle, {
    int scanRows = 24,
  }) => locateNeedle(needle, scanRows: scanRows);

  @override
  FullscreenPromptAnchor? locateCollapsedPasteZoneNeedle({int scanRows = 24}) =>
      locateCollapsedPasteNeedle(scanRows: scanRows);

  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      staged != null && staged!.contains(anchor.needle);
  @override
  bool isNeedleStagedInCursorZone(String needle) =>
      isAtAnchor(FullscreenPromptAnchor(row: 0, startCol: 0, needle: needle));

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) =>
      // Stale mirror: never reflects the commit.
      false;

  @override
  Future<void> clearStagedInput({bool Function()? canExecute}) async {
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
  }

  @override
  Future<void> dismissComposerPopup() async {}

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      'staged=$staged cr=$crCount';
}

/// First locate after paste misses; [waitForPaint] reveals the needle immediately.
final class _PaintWakePort implements FullscreenPtyDeliveryPort {
  var _visible = false;
  String? staged;
  int pasteCount = 0;
  int crCount = 0;

  @override
  bool get isAborted => false;

  @override
  int get viewportRows => 24;

  @override
  int get cursorRow => -1;

  @override
  int get pasteZoneComposerRow => -1;

  @override
  FullscreenCrAckConfig get crAckConfig =>
      const FullscreenCrAckConfig.productionDefault();

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  Future<void> waitForPaint({required Duration timeout}) async {
    _visible = true;
  }

  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    if (!_visible || staged == null || !staged!.contains(needle)) return null;
    return FullscreenPromptAnchor(
      row: 0,
      startCol: staged!.indexOf(needle),
      needle: needle,
    );
  }

  @override
  FullscreenPromptAnchor? locatePasteZoneNeedle(
    String needle, {
    int scanRows = 24,
  }) => locateNeedle(needle, scanRows: scanRows);

  @override
  FullscreenPromptAnchor? locateCollapsedPasteZoneNeedle({int scanRows = 24}) =>
      locateCollapsedPasteNeedle(scanRows: scanRows);

  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      _visible && staged != null && staged!.contains(anchor.needle);
  @override
  bool isNeedleStagedInCursorZone(String needle) =>
      isAtAnchor(FullscreenPromptAnchor(row: 0, startCol: 0, needle: needle));

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) =>
      crCount > 0 && (staged == null || !staged!.contains(anchor.needle));

  @override
  Future<void> clearStagedInput({bool Function()? canExecute}) async {
    staged = null;
    _visible = false;
  }

  @override
  Future<void> pasteText(String text, {bool Function()? canExecute}) async {
    pasteCount++;
    staged = text;
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
      'visible=$_visible staged=$staged';
}

/// Staged text is visible immediately after paste, but the CR submit frame only
/// appears on the first [waitForPaint] — mirrors ConnectedRecordingShell tests
/// that paint the composerMovesDown ACK asynchronously after CR.
final class _LateCrAckPaintPort implements FullscreenPtyDeliveryPort {
  String? staged;
  var _crAckVisible = false;
  int pasteCount = 0;
  int crCount = 0;
  int crAckPaintWaits = 0;

  @override
  bool get isAborted => false;

  @override
  int get viewportRows => 24;

  @override
  int get cursorRow => -1;

  @override
  int get pasteZoneComposerRow => -1;

  @override
  FullscreenCrAckConfig get crAckConfig => const FullscreenCrAckConfig(
    strategy: FullscreenCrAckStrategy.composerMovesDown,
  );

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  Future<void> waitForPaint({required Duration timeout}) async {
    if (crCount > 0 && !_crAckVisible) {
      crAckPaintWaits++;
      _crAckVisible = true;
      staged = null;
    }
  }

  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    if (staged == null || !staged!.contains(needle)) return null;
    return FullscreenPromptAnchor(
      row: 0,
      startCol: staged!.indexOf(needle),
      needle: needle,
    );
  }

  @override
  FullscreenPromptAnchor? locatePasteZoneNeedle(
    String needle, {
    int scanRows = 24,
  }) => locateNeedle(needle, scanRows: scanRows);

  @override
  FullscreenPromptAnchor? locateCollapsedPasteZoneNeedle({int scanRows = 24}) =>
      locateCollapsedPasteNeedle(scanRows: scanRows);

  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24}) =>
      null;

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) =>
      staged != null && staged!.contains(anchor.needle);
  @override
  bool isNeedleStagedInCursorZone(String needle) =>
      isAtAnchor(FullscreenPromptAnchor(row: 0, startCol: 0, needle: needle));

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) =>
      _crAckVisible;

  @override
  Future<void> clearStagedInput({bool Function()? canExecute}) async {
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
  }

  @override
  Future<void> dismissComposerPopup() async {}

  @override
  String describeProbeWindow({int scanRows = 24}) =>
      'staged=$staged cr=$crCount crAck=$_crAckVisible';
}
