import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/rewind/edit/edit_operation.dart';
import 'package:teampilot/services/chat/rewind/edit/seat_edit_coordinator.dart';

class _Harness {
  _Harness({this.watchdog = Duration.zero});

  final Duration watchdog;
  final phases = <EditPhase>[];
  Completer<void> gate = Completer<void>();
  var cancelledOnAbort = false;

  late final SeatEditCoordinator coordinator = SeatEditCoordinator(
    sessionId: 's1',
    watchdog: watchdog,
    run:
        ({
          required String sessionId,
          required String memberId,
          required String userMessageId,
          required String text,
          required void Function(EditPhase phase) onPhase,
          required bool Function() aborted,
        }) async {
          onPhase(EditPhase.restoring);
          await gate.future;
          if (aborted()) {
            cancelledOnAbort = true;
            throw const SeatEditCancelled();
          }
          onPhase(EditPhase.delivering);
        },
  );
}

void main() {
  test('submit returns before the resend and reports each phase', () async {
    final harness = _Harness();
    addTearDown(harness.coordinator.dispose);

    expect(
      await harness.coordinator.submit(
        messageId: 'u1',
        memberId: 'm1',
        text: '  edited  ',
      ),
      isTrue,
    );

    expect(harness.coordinator.operation?.phase, EditPhase.restoring);
    expect(harness.coordinator.pending?.text, 'edited');
    expect(harness.coordinator.holdsTranscript, isTrue);
    expect(harness.coordinator.isCancellable, isTrue);

    harness.gate.complete();
    await harness.coordinator.settled;

    expect(harness.coordinator.operation?.phase, EditPhase.awaitingReplay);
    // The transcript must accept runtime updates again so the new turn lands.
    expect(harness.coordinator.holdsTranscript, isFalse);
  });

  test('an empty edit is rejected without starting a transaction', () async {
    final harness = _Harness();
    addTearDown(harness.coordinator.dispose);

    expect(
      await harness.coordinator.submit(
        messageId: 'u1',
        memberId: 'm1',
        text: '   ',
      ),
      isFalse,
    );
    expect(harness.coordinator.operation, isNull);
  });

  test('a second submit while one runs is refused', () async {
    final harness = _Harness();
    addTearDown(harness.coordinator.dispose);

    await harness.coordinator.submit(
      messageId: 'u1',
      memberId: 'm1',
      text: 'edited',
    );
    expect(
      await harness.coordinator.submit(
        messageId: 'u2',
        memberId: 'm1',
        text: 'other',
      ),
      isFalse,
    );
  });

  test('cancel while queued reverts the bubble immediately', () async {
    final gate = Completer<void>();
    final coordinator = SeatEditCoordinator(
      sessionId: 's1',
      watchdog: Duration.zero,
      run:
          ({
            required String sessionId,
            required String memberId,
            required String userMessageId,
            required String text,
            required void Function(EditPhase phase) onPhase,
            required bool Function() aborted,
          }) async {
            await gate.future;
          },
    );
    addTearDown(coordinator.dispose);

    await coordinator.submit(
      messageId: 'u1',
      memberId: 'm1',
      text: 'edited',
    );
    expect(coordinator.operation?.phase, EditPhase.queued);
    coordinator.cancel();

    expect(coordinator.operation?.phase, EditPhase.cancelled);
    expect(coordinator.pending, isNull);
    expect(coordinator.isActive, isFalse);
    expect(coordinator.operation?.phase.allowsRetry, isTrue);
    gate.complete();
    await coordinator.settled;
    expect(coordinator.operation?.phase, EditPhase.cancelled);
  });

  test('cancel between phases ends as cancelled after the runner aborts', () async {
    final harness = _Harness();
    addTearDown(harness.coordinator.dispose);

    await harness.coordinator.submit(
      messageId: 'u1',
      memberId: 'm1',
      text: 'edited',
    );
    harness.coordinator.cancel();
    harness.gate.complete();
    await harness.coordinator.settled;

    expect(harness.cancelledOnAbort, isTrue);
    expect(harness.coordinator.operation?.phase, EditPhase.cancelled);
    expect(harness.coordinator.pending, isNull);
    expect(harness.coordinator.holdsTranscript, isFalse);
  });

  test('markLanded confirms a delivered edit', () async {
    final harness = _Harness();
    addTearDown(harness.coordinator.dispose);

    await harness.coordinator.submit(
      messageId: 'u1',
      memberId: 'm1',
      text: 'edited',
    );
    harness.gate.complete();
    await harness.coordinator.settled;

    harness.coordinator.markLanded();
    expect(harness.coordinator.operation?.phase, EditPhase.confirmed);
    expect(harness.coordinator.pending, isNull);
  });

  test('a failure keeps the text for a retry', () async {
    var attempts = 0;
    final coordinator = SeatEditCoordinator(
      sessionId: 's1',
      watchdog: Duration.zero,
      run:
          ({
            required String sessionId,
            required String memberId,
            required String userMessageId,
            required String text,
            required void Function(EditPhase phase) onPhase,
            required bool Function() aborted,
          }) async {
            attempts++;
            if (attempts == 1) throw StateError('delivery exploded');
          },
    );
    addTearDown(coordinator.dispose);

    await coordinator.submit(
      messageId: 'u1',
      memberId: 'm1',
      text: 'edited',
    );
    await coordinator.settled;

    expect(coordinator.operation?.phase, EditPhase.failed);
    expect(coordinator.pending, isNull);

    expect(await coordinator.retry(), isTrue);
    await coordinator.settled;
    expect(attempts, 2);
    expect(coordinator.operation?.phase, EditPhase.awaitingReplay);
  });
}
