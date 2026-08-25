import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_reclaim_policy.dart';

TerminalReclaimSnapshot _snap({
  bool shellRunning = true,
  bool shellConnecting = false,
  bool isTeamLead = false,
  bool isDisplayed = false,
  bool inTurn = false,
  bool hasUnread = false,
  bool isSessionPinned = false,
}) => TerminalReclaimSnapshot(
  sessionId: 's',
  memberId: 'm',
  shellRunning: shellRunning,
  shellConnecting: shellConnecting,
  isTeamLead: isTeamLead,
  isDisplayed: isDisplayed,
  inTurn: inTurn,
  hasUnread: hasUnread,
  isSessionPinned: isSessionPinned,
);

void main() {
  final policy = TerminalReclaimPolicy(idleAfter: const Duration(minutes: 3));
  final now = DateTime(2026, 8, 9, 12, 0, 0);

  test('reclaimable when idle past threshold and nothing protects', () {
    final idleSince = now.subtract(const Duration(minutes: 4));
    expect(policy.shouldReclaim(_snap(), idleSince, now), isTrue);
  });

  test('not reclaimable before threshold', () {
    final idleSince = now.subtract(const Duration(minutes: 2));
    expect(policy.shouldReclaim(_snap(), idleSince, now), isFalse);
  });

  test('idleSince null means never reclaimable (not yet seeded)', () {
    expect(policy.shouldReclaim(_snap(), null, now), isFalse);
  });

  test('each guard blocks reclaim regardless of idle duration', () {
    final idleSince = now.subtract(const Duration(hours: 1));
    for (final s in [
      _snap(shellConnecting: true),
      _snap(isTeamLead: true),
      _snap(isDisplayed: true),
      _snap(inTurn: true),
      _snap(hasUnread: true),
      _snap(isSessionPinned: true),
    ]) {
      expect(
        policy.shouldReclaim(s, idleSince, now),
        isFalse,
        reason: 'guard failed for $s',
      );
    }
  });

  test('shell not running is not reclaimable (nothing live to reclaim)', () {
    expect(policy.shouldReclaim(_snap(shellRunning: false), now, now), isFalse);
  });
}
