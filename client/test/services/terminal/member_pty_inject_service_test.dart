import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/terminal_composer_region.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_automation.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_delivery_port.dart';
import 'package:teampilot/services/terminal/member_pty_inject_service.dart';
import 'package:teampilot/services/terminal/prompt_submit_ack_tracker.dart';
import 'package:teampilot/services/terminal/pty_automation_retry_queue.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

/// Always reports crStuck from the probe so the inject service runs its
/// retry-scheduling path.
final class _StuckAutomation extends FullscreenPtyAutomation {
  @override
  Future<FullscreenPtyDeliveryOutcome> deliverPasteAndSubmit({
    required FullscreenPtyDeliveryPort port,
    required String text,
    required Duration pasteSettle,
    bool Function()? isAcked,
  }) async =>
      FullscreenPtyDeliveryOutcome.crStuck;
}

Future<FullscreenPtyDeliveryOutcome> _deliver(
  MemberPtyInjectService service,
  TerminalSession session,
) {
  return service.deliver(
    input: session.input,
    probe: session.probe,
    sessionId: 's1',
    memberId: 'm1',
    text: '1',
    pasteSettle: Duration.zero,
    aborted: () => false,
    composerRegion: fullscreenDefaultComposerSpec,
  );
}

void main() {
  test('tickRetries shouldSkip clears pending without onTick', () {
    var now = 0;
    final queue = PtyAutomationRetryQueue(
      retryIntervalMs: 0,
      maxAttempts: 5,
      nowMs: () => now,
    );
    final inject = MemberPtyInjectService(retryQueue: queue);
    const key = 'sess:worker';
    queue.schedule(
      key: key,
      sessionId: 'sess',
      memberId: 'worker',
      text: 'stale doorbell',
    );

    var ticked = 0;
    inject.tickRetries(
      shouldSkip: (_) => true,
      onTick: (_) => ticked++,
    );

    expect(ticked, 0);
    expect(queue.isPending(key), isFalse);
  });

  test('clearPending removes scheduled retry', () {
    final queue = PtyAutomationRetryQueue(retryIntervalMs: 0, maxAttempts: 5);
    final inject = MemberPtyInjectService(retryQueue: queue);
    const key = 'sess:worker';
    queue.schedule(
      key: key,
      sessionId: 'sess',
      memberId: 'worker',
      text: 'hello',
    );

    inject.clearPending('sess', 'worker');

    expect(queue.isPending(key), isFalse);
  });

  test('maxPtyNotifyAttempts aligns with TeamBus', () {
    expect(MemberPtyInjectService.maxPtyNotifyAttempts, TeamBus.maxPtyNotifyAttempts);
    expect(TeamBus.maxPtyNotifyAttempts, 6);
  });

  test('deferForBoot re-times without consuming retry attempts', () {
    final queue = PtyAutomationRetryQueue(retryIntervalMs: 0, maxAttempts: 1);
    final inject = MemberPtyInjectService(retryQueue: queue);
    inject.deferForBoot('sess', 'worker', TeamBus.doorbellNotice);
    inject.deferForBoot('sess', 'worker', TeamBus.doorbellNotice);
    // 若 defer 像 schedule 一样递增 attempt,第二次会因 attempt(2)>max(1) 被
    // clear → hasPendingRetry 变 false。defer 不耗预算 → 两次后仍 pending。
    expect(inject.hasPendingRetry('sess', 'worker'), isTrue);
  });

  test('acked seat crStuck outcome skips retry scheduling', () async {
    final tracker = PromptSubmitAckTracker();
    final service = MemberPtyInjectService(
      automation: _StuckAutomation(),
      ackTracker: tracker,
    );
    final session = TerminalSession(
      executable: 'unused',
      validateLaunch: false,
      parseExecutable: false,
    );
    addTearDown(session.dispose);
    // 真实时序:hook ACK 先于探针 outcome 到达 → seat 已 acked。
    tracker.register(sessionId: 's1', memberId: 'm1', text: '1');
    expect(tracker.tryAck(sessionId: 's1', memberId: 'm1', text: '1'), isTrue);
    expect(tracker.isAcked(sessionId: 's1', memberId: 'm1'), isTrue);

    final outcome = await _deliver(service, session);

    expect(outcome, FullscreenPtyDeliveryOutcome.crStuck);
    expect(service.hasPendingRetry('s1', 'm1'), isFalse);
  });

  test('without ackTracker crStuck still schedules retry (behavior preserved)',
      () async {
    final service = MemberPtyInjectService(automation: _StuckAutomation());
    final session = TerminalSession(
      executable: 'unused',
      validateLaunch: false,
      parseExecutable: false,
    );
    addTearDown(session.dispose);

    final outcome = await _deliver(service, session);

    expect(outcome, FullscreenPtyDeliveryOutcome.crStuck);
    expect(service.hasPendingRetry('s1', 'm1'), isTrue);
  });
}
