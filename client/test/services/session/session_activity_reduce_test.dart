import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_activity.dart';
import 'package:teampilot/services/session/session_activity_reduce.dart';

void main() {
  test('delivering only is busy, not ready', () {
    final next = reduceSessionActivity(
      previous: const SessionActivity(),
      reasons: {SessionBusyReason.delivering},
    );
    expect(next.isBusy, isTrue);
    expect(next.hadTurn, isFalse);
    expect(next.isReadyToChat, isFalse);
  });

  test('dropping delivering without a turn is failed, not ready', () {
    final next = reduceSessionActivity(
      previous: const SessionActivity(reasons: {SessionBusyReason.delivering}),
      reasons: {},
    );
    expect(next.disposition, SessionTurnDisposition.failed);
    expect(next.isReadyToChat, isFalse);
  });

  test('inTurn then empty is completed ready', () {
    final mid = reduceSessionActivity(
      previous: const SessionActivity(reasons: {SessionBusyReason.delivering}),
      reasons: {SessionBusyReason.inTurn},
    );
    expect(mid.hadTurn, isTrue);
    final done = reduceSessionActivity(previous: mid, reasons: {});
    expect(done.isReadyToChat, isTrue);
  });

  test('Stop forced cancelled is not ready', () {
    final next = reduceSessionActivity(
      previous: const SessionActivity(
        reasons: {SessionBusyReason.inTurn},
        hadTurn: true,
      ),
      reasons: {},
      forced: SessionTurnDisposition.cancelled,
    );
    expect(next.isReadyToChat, isFalse);
    expect(next.disposition, SessionTurnDisposition.cancelled);
  });

  test('completed stays ready across repeated empty reduces', () {
    final mid = reduceSessionActivity(
      previous: const SessionActivity(reasons: {SessionBusyReason.delivering}),
      reasons: {SessionBusyReason.inTurn},
    );
    final done = reduceSessionActivity(previous: mid, reasons: {});
    expect(done.isReadyToChat, isTrue);

    final again = reduceSessionActivity(previous: done, reasons: {});
    expect(again.disposition, SessionTurnDisposition.completed);
    expect(again.isReadyToChat, isTrue);
  });

  test('cancelled and failed stay sticky on second empty reduce', () {
    final cancelled = reduceSessionActivity(
      previous: const SessionActivity(
        reasons: {SessionBusyReason.inTurn},
        hadTurn: true,
      ),
      reasons: {},
      forced: SessionTurnDisposition.cancelled,
    );
    final cancelledAgain = reduceSessionActivity(
      previous: cancelled,
      reasons: {},
    );
    expect(cancelledAgain.disposition, SessionTurnDisposition.cancelled);
    expect(cancelledAgain.isReadyToChat, isFalse);

    final failed = reduceSessionActivity(
      previous: const SessionActivity(reasons: {SessionBusyReason.delivering}),
      reasons: {},
    );
    final failedAgain = reduceSessionActivity(previous: failed, reasons: {});
    expect(failedAgain.disposition, SessionTurnDisposition.failed);
    expect(failedAgain.isReadyToChat, isFalse);
  });

  test('idle to idle from empty snapshot stays none', () {
    final again = reduceSessionActivity(
      previous: const SessionActivity(),
      reasons: {},
    );
    expect(again.disposition, SessionTurnDisposition.none);
    expect(again.isReadyToChat, isFalse);
  });
}
