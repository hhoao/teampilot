import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_activity.dart';

void main() {
  test('empty activity is not busy and not ready', () {
    const a = SessionActivity();
    expect(a.isBusy, isFalse);
    expect(a.isReadyToChat, isFalse);
  });

  test('delivering is busy but not ready', () {
    const a = SessionActivity(reasons: {SessionBusyReason.delivering});
    expect(a.isBusy, isTrue);
    expect(a.isReadyToChat, isFalse);
  });

  test('ready only when idle, hadTurn, completed', () {
    const a = SessionActivity(
      hadTurn: true,
      disposition: SessionTurnDisposition.completed,
    );
    expect(a.isReadyToChat, isTrue);
  });

  test('cancelled or failed is not ready', () {
    expect(
      const SessionActivity(
        hadTurn: true,
        disposition: SessionTurnDisposition.cancelled,
      ).isReadyToChat,
      isFalse,
    );
    expect(
      const SessionActivity(
        hadTurn: true,
        disposition: SessionTurnDisposition.failed,
      ).isReadyToChat,
      isFalse,
    );
  });
}
