import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_activity.dart';
import 'package:teampilot/services/notification/session_idle_notify_gate.dart';

void main() {
  late List<Set<String>> confirmed;
  late SessionIdleNotifyGate gate;

  const delivering = SessionActivity(reasons: {SessionBusyReason.delivering});
  const inTurn = SessionActivity(
    reasons: {SessionBusyReason.inTurn},
    hadTurn: true,
  );
  const ready = SessionActivity(
    hadTurn: true,
    disposition: SessionTurnDisposition.completed,
  );
  const failedIdle = SessionActivity(disposition: SessionTurnDisposition.failed);
  const cancelled = SessionActivity(
    hadTurn: true,
    disposition: SessionTurnDisposition.cancelled,
  );
  const ack = SessionActivity();

  SessionIdleNotifyGate makeGate() {
    confirmed = [];
    return SessionIdleNotifyGate(
      onIdleConfirmed: (ids) => confirmed.add(Set<String>.from(ids)),
    );
  }

  test('delivering drop does not notify', () {
    gate = makeGate();
    gate.handle({'s1': delivering});
    gate.handle({'s1': failedIdle});
    expect(confirmed, isEmpty);
  });

  test('completed idle notifies once', () {
    gate = makeGate();
    gate.handle({'s1': inTurn});
    gate.handle({'s1': ready});
    expect(confirmed, [
      {'s1'},
    ]);
    gate.handle({'s1': ready});
    expect(confirmed, [
      {'s1'},
    ]);
  });

  test('cancelled never notifies', () {
    gate = makeGate();
    gate.handle({'s1': inTurn});
    gate.handle({'s1': cancelled});
    expect(confirmed, isEmpty);
  });

  test('failed never notifies', () {
    gate = makeGate();
    gate.handle({'s1': delivering});
    gate.handle({'s1': failedIdle});
    expect(confirmed, isEmpty);
  });

  test('ack clears ready so a new turn can notify again', () {
    gate = makeGate();
    gate.handle({'s1': inTurn});
    gate.handle({'s1': ready});
    expect(confirmed, [
      {'s1'},
    ]);
    gate.handle({'s1': ack});
    gate.handle({'s1': inTurn});
    gate.handle({'s1': ready});
    expect(confirmed, [
      {'s1'},
      {'s1'},
    ]);
  });
}
