import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/runtime/pty/fullscreen_pty_submission_machine.dart';

void main() {
  var current = DateTime(2026, 9, 12, 10, 0, 0);
  FullscreenPtySubmission newMachine({FullscreenPtySubmissionBudget? budget}) =>
      FullscreenPtySubmission(
        budget:
            budget ??
            const FullscreenPtySubmissionBudget(stagingMaxAttempts: 3),
        now: () => current,
      );

  group('FullscreenPtySubmission staging', () {
    test('starts idle and begin enters staging', () {
      final machine = newMachine();
      expect(machine.phase, FullscreenPtySubmissionPhase.idle);
      machine.begin();
      expect(machine.phase, FullscreenPtySubmissionPhase.staging);
    });

    test('staging miss stays in staging while budget remains', () {
      final machine = newMachine();
      machine.begin();
      machine.noteStagingAttempt();
      machine.noteStagingMiss();
      expect(machine.phase, FullscreenPtySubmissionPhase.staging);
      expect(machine.canRetryStaging, isTrue);
      expect(machine.stagingAttemptsRemaining, 2);
    });

    test('staging exhausts budget into failed (pasteNotFound)', () {
      final machine = newMachine();
      machine.begin();
      while (machine.canRetryStaging) {
        machine.noteStagingAttempt();
        machine.noteStagingMiss();
      }
      expect(machine.phase, FullscreenPtySubmissionPhase.failed);
      expect(machine.isTerminal, isTrue);
    });

    test('needle found locks pasted and never returns to staging', () {
      final machine = newMachine();
      machine.begin();
      machine.noteStagingAttempt();
      machine.noteNeedleFound();
      expect(machine.phase, FullscreenPtySubmissionPhase.pasted);
      expect(machine.lockedPasted, isTrue);
      // A staging miss after the latch must not demote to staging.
      machine.noteStagingMiss();
      expect(machine.phase, FullscreenPtySubmissionPhase.pasted);
    });

    test('noteAckedWhileStaging completes without needing the needle', () {
      final machine = newMachine();
      machine.begin();
      machine.noteAckedWhileStaging();
      expect(machine.phase, FullscreenPtySubmissionPhase.done);
    });
  });

  group('FullscreenPtySubmission send', () {
    test('CR issues enter awaitingAck then clears to done', () {
      final machine = newMachine();
      machine.begin();
      machine.noteStagingAttempt();
      machine.noteNeedleFound();
      machine.noteCrIssued();
      expect(machine.phase, FullscreenPtySubmissionPhase.awaitingAck);
      expect(machine.lockedPasted, isTrue);
      machine.noteSubmitted();
      expect(machine.phase, FullscreenPtySubmissionPhase.done);
    });

    test(
      'send exhaustion while awaitingAck fails as crStuck, never re-pastes',
      () {
        final machine = FullscreenPtySubmission(
          budget: const FullscreenPtySubmissionBudget(
            stagingMaxAttempts: 3,
            sendMaxCrAttempts: 2,
          ),
          now: () => current,
        );
        machine.begin();
        machine.noteStagingAttempt();
        machine.noteNeedleFound();
        machine.noteCrIssued();
        expect(machine.canRetryCr, isTrue);
        machine.noteCrRetry();
        machine.noteCrRetry();
        expect(machine.canRetryCr, isFalse);
        machine.noteSendExhausted();
        expect(machine.phase, FullscreenPtySubmissionPhase.failed);
        expect(machine.isTerminal, isTrue);
      },
    );

    test('awaitingAck expires after sendAckTimeout', () {
      final machine = newMachine(
        budget: const FullscreenPtySubmissionBudget(
          stagingMaxAttempts: 3,
          sendAckTimeout: Duration(seconds: 12),
        ),
      );
      machine.begin();
      machine.noteStagingAttempt();
      machine.noteNeedleFound();
      current = DateTime(2026, 9, 12, 10, 0, 0);
      machine.noteCrIssued();
      expect(machine.awaitingAckExpired, isFalse);
      current = DateTime(2026, 9, 12, 10, 0, 13);
      expect(machine.awaitingAckExpired, isTrue);
    });

    test('abort mid-send ends aborted', () {
      final machine = newMachine();
      machine.begin();
      machine.noteStagingAttempt();
      machine.noteNeedleFound();
      machine.noteCrIssued();
      machine.abort();
      expect(machine.phase, FullscreenPtySubmissionPhase.aborted);
      expect(machine.isTerminal, isTrue);
    });
  });
}
