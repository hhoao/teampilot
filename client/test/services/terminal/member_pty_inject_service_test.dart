import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/fullscreen_cr_ack_config.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_automation.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_delivery_port.dart';
import 'package:teampilot/services/terminal/member_pty_inject_service.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

final class _CrStuckAutomation extends FullscreenPtyAutomation {
  var retryCalls = 0;

  @override
  Future<FullscreenPtyDeliveryOutcome> retry({
    required FullscreenPtyDeliveryPort port,
    required String text,
    required Duration pasteSettle,
    bool Function()? isAcked,
  }) async {
    retryCalls++;
    return FullscreenPtyDeliveryOutcome.crStuck;
  }
}

void main() {
  test('mailbox retry delegates one attempt to automation', () async {
    final automation = _CrStuckAutomation();
    final service = MemberPtyInjectService(automation: automation);
    final session = TerminalSession(
      executable: 'unused',
      validateLaunch: false,
      parseExecutable: false,
    );
    addTearDown(session.dispose);

    final outcome = await service.retry(
      input: session.input,
      probe: session.probe,
      sessionId: 's1',
      memberId: 'm1',
      text: 'mail',
      pasteSettle: Duration.zero,
      aborted: () => false,
      crAckConfig: const FullscreenCrAckConfig.productionDefault(),
    );

    expect(outcome, FullscreenPtyDeliveryOutcome.crStuck);
    expect(automation.retryCalls, 1);
  });

  test('abort state is explicit and can be cleared by the caller', () {
    final service = MemberPtyInjectService();

    service.requestAbort('s1', 'm1');
    expect(service.isAbortRequested('s1', 'm1'), isTrue);

    service.clearAbort('s1', 'm1');
    expect(service.isAbortRequested('s1', 'm1'), isFalse);
  });
}
