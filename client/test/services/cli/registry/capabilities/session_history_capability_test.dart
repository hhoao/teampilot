import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_history_capability.dart';

void main() {
  test('SessionHistorySnapshot.ready holds turns', () {
    const turn = SessionHistoryTurn(
      role: SessionHistoryRole.user,
      markdown: 'hello',
    );
    const snap = SessionHistorySnapshot(
      turns: [turn],
      status: SessionHistoryLoadStatus.ready,
    );
    expect(snap.turns.single.markdown, 'hello');
    expect(snap.status, SessionHistoryLoadStatus.ready);
  });
}
