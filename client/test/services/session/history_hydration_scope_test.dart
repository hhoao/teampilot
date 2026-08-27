import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/history_hydration_scope.dart';

void main() {
  test('rapid A to B switch rejects A load continuation for B seat', () {
    final seatA = Object();
    final seatB = Object();
    final scope = HistoryHydrationScope(
      seat: seatA,
      sessionId: 'session-a',
      memberId: 'member-a',
    );

    expect(
      scope.isCurrent(
        seat: seatB,
        sessionId: 'session-b',
        memberId: 'member-b',
      ),
      isFalse,
    );
  });
}
