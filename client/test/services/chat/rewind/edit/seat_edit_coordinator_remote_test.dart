import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/rewind/edit/edit_operation.dart';
import 'package:teampilot/services/chat/rewind/edit/edit_transport.dart';
import 'package:teampilot/services/chat/rewind/edit/seat_edit_coordinator.dart';

final class _FakeTransport implements SeatEditTransport {
  final _controller = StreamController<EditOperation>.broadcast();
  final cancelled = <String>[];
  final submitted = <(String, String, String)>[];
  bool accept = true;
  Object? submitError;

  @override
  Stream<EditOperation> get operations => _controller.stream;

  @override
  Future<bool> submit({
    required String operationId,
    required String messageId,
    required String text,
  }) async {
    submitted.add((operationId, messageId, text));
    final error = submitError;
    if (error != null) throw error;
    return accept;
  }

  @override
  Future<void> cancel(String operationId) async {
    cancelled.add(operationId);
  }

  void emit(EditPhase phase, {EditFailure? failure}) {
    final id = submitted.isEmpty ? 'op' : submitted.last.$1;
    _controller.add(
      EditOperation(
        id: id,
        sessionId: 's1',
        memberId: 'm1',
        messageId: 'u1',
        text: '',
        phase: phase,
        startedAt: DateTime(2026),
        failure: failure,
      ),
    );
  }

  Future<void> close() => _controller.close();
}

SeatEditCoordinator _coordinator(_FakeTransport transport) => SeatEditCoordinator(
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
        fail('the local runner must not run for a delegated edit');
      },
  transportFor: (_) => transport,
);

void main() {
  test('a delegated edit follows the phases the authority publishes', () async {
    final transport = _FakeTransport();
    final coordinator = _coordinator(transport);
    addTearDown(coordinator.dispose);
    addTearDown(transport.close);

    expect(
      await coordinator.submit(
        messageId: 'u1',
        memberId: 'm1',
        text: 'edited',
      ),
      isTrue,
    );
    expect(coordinator.operation?.phase, EditPhase.queued);
    expect(transport.submitted.single.$2, 'u1');
    expect(transport.submitted.single.$3, 'edited');

    transport.emit(EditPhase.restoring);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.operation?.phase, EditPhase.restoring);

    transport.emit(EditPhase.delivering);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.operation?.phase, EditPhase.delivering);
    expect(coordinator.pending?.text, 'edited');

    transport.emit(EditPhase.confirmed);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.operation?.phase, EditPhase.confirmed);
    expect(coordinator.pending, isNull);
    expect(coordinator.isActive, isFalse);
  });

  test('a refused intent settles as failed and can be retried', () async {
    final transport = _FakeTransport()..accept = false;
    final coordinator = _coordinator(transport);
    addTearDown(coordinator.dispose);
    addTearDown(transport.close);

    await coordinator.submit(messageId: 'u1', memberId: 'm1', text: 'edited');
    await coordinator.settled;
    expect(coordinator.operation?.phase, EditPhase.failed);
    expect(coordinator.operation?.detail, 'intent_rejected');
    expect(coordinator.operation?.phase.allowsRetry, isTrue);

    transport.accept = true;
    expect(await coordinator.retry(), isTrue);
    expect(transport.submitted, hasLength(2));
  });

  test('a thrown submit settles as failed', () async {
    final transport = _FakeTransport()..submitError = StateError('offline');
    final coordinator = _coordinator(transport);
    addTearDown(coordinator.dispose);
    addTearDown(transport.close);

    await coordinator.submit(messageId: 'u1', memberId: 'm1', text: 'edited');
    await coordinator.settled;
    expect(coordinator.operation?.phase, EditPhase.failed);
  });

  test('Stop cancels through the transport instead of the local runner', () async {
    final transport = _FakeTransport();
    final coordinator = _coordinator(transport);
    addTearDown(coordinator.dispose);
    addTearDown(transport.close);

    await coordinator.submit(messageId: 'u1', memberId: 'm1', text: 'edited');
    coordinator.cancel();
    await Future<void>.delayed(Duration.zero);

    expect(transport.cancelled, hasLength(1));
  });

  test('a cancelled phase settles without keeping the optimistic text', () async {
    final transport = _FakeTransport();
    final coordinator = _coordinator(transport);
    addTearDown(coordinator.dispose);
    addTearDown(transport.close);

    await coordinator.submit(messageId: 'u1', memberId: 'm1', text: 'edited');
    transport.emit(EditPhase.restoring);
    await Future<void>.delayed(Duration.zero);
    transport.emit(EditPhase.cancelled, failure: EditFailure.cancelled);
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.operation?.phase, EditPhase.cancelled);
    expect(coordinator.pending, isNull);
    expect(coordinator.holdsTranscript, isFalse);
  });
}
