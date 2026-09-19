import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/terminal/fullscreen_cr_ack_config.dart';
import 'package:teampilot/services/chat/terminal/fullscreen_pty_automation.dart';
import 'package:teampilot/services/chat/terminal/fullscreen_pty_delivery_port.dart';
import 'package:teampilot/services/chat/terminal/fullscreen_pty_submission_machine.dart';
import 'package:teampilot/services/chat/terminal/member_pty_inject_service.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import '../../support/in_memory_filesystem.dart';

final class _CrStuckAutomation extends FullscreenPtyAutomation {
  var continueCalls = 0;

  @override
  Future<FullscreenPtyDeliveryOutcome> continueSubmission(
    FullscreenPtySubmission machine, {
    required FullscreenPtyDeliveryPort port,
    required String text,
    required Duration pasteSettle,
    bool Function()? isAcked,
    bool dismissMentionPopup = false,
  }) async {
    continueCalls++;
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
      fs: InMemoryFilesystem(),
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
    expect(automation.continueCalls, 1);
  });

  test('abort state is explicit and can be cleared by the caller', () {
    final service = MemberPtyInjectService();

    service.requestAbort('s1', 'm1');
    expect(service.isAbortRequested('s1', 'm1'), isTrue);

    service.clearAbort('s1', 'm1');
    expect(service.isAbortRequested('s1', 'm1'), isFalse);
  });
}
