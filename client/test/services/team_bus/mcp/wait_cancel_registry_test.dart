import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/cancellation.dart';
import 'package:teampilot/services/team_bus/mcp/wait_cancel_registry.dart';

void main() {
  test('registering a second wait for the same member supersedes the first', () {
    final reg = WaitCancelRegistry();
    final older = CancellationToken();
    final newer = CancellationToken();

    reg.register(1, older, memberId: 'worker');
    reg.register(2, newer, memberId: 'worker');

    expect(older.isCancelled, isTrue);
    expect(older.cancelReason, WaitCancelReason.superseded);
    expect(newer.isCancelled, isFalse);
  });

  test('unregister only clears member flight when token still current', () {
    final reg = WaitCancelRegistry();
    final older = CancellationToken();
    final newer = CancellationToken();

    reg.register(1, older, memberId: 'worker');
    reg.register(2, newer, memberId: 'worker');
    reg.unregister(1, memberId: 'worker', cancel: older);

    expect(newer.isCancelled, isFalse);
    // Newer is still the active flight; a third wait should supersede newer.
    final third = CancellationToken();
    reg.register(3, third, memberId: 'worker');
    expect(newer.isCancelled, isTrue);
    expect(newer.cancelReason, WaitCancelReason.superseded);
  });
}
