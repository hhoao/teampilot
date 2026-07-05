import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/pty_inject_ack_retry.dart';

void main() {
  test('ptyAckPollRetry succeeds when acked before retry budget', () async {
    var checks = 0;
    var retries = 0;
    final ok = await ptyAckPollRetry(
      settle: Duration.zero,
      maxAttempts: 3,
      aborted: () => false,
      isAcked: (_) {
        checks++;
        return checks >= 2;
      },
      onRetry: (_) async => retries++,
    );
    expect(ok, PtyAckPollOutcome.acked);
    expect(checks, 2);
    expect(retries, 1);
  });

  test('ptyAckPollRetry returns false when budget exhausted', () async {
    var retries = 0;
    final ok = await ptyAckPollRetry(
      settle: Duration.zero,
      maxAttempts: 2,
      aborted: () => false,
      isAcked: (_) => false,
      onRetry: (_) async => retries++,
    );
    expect(ok, PtyAckPollOutcome.exhausted);
    expect(retries, 2);
  });

  test('ptyAckPollRetry stops when aborted', () async {
    var checks = 0;
    final ok = await ptyAckPollRetry(
      settle: Duration.zero,
      maxAttempts: 5,
      aborted: () => checks >= 1,
      isAcked: (_) {
        checks++;
        return false;
      },
      onRetry: (_) async {},
    );
    expect(ok, PtyAckPollOutcome.aborted);
  });
}
