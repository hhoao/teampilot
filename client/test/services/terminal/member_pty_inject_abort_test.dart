import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/fullscreen_cr_ack_config.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_automation.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_delivery_port.dart';
import 'package:teampilot/services/terminal/member_pty_inject_service.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

final class _PausedAutomation extends FullscreenPtyAutomation {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<FullscreenPtyDeliveryOutcome> deliverPasteAndSubmit({
    required FullscreenPtyDeliveryPort port,
    required String text,
    required Duration pasteSettle,
    bool Function()? isAcked,
    bool dismissMentionPopup = false,
  }) async {
    started.complete();
    await release.future;
    return port.isAborted
        ? FullscreenPtyDeliveryOutcome.aborted
        : FullscreenPtyDeliveryOutcome.submitted;
  }
}

void main() {
  test('an abort requested before delivery prevents the mailbox paste', () async {
    final service = MemberPtyInjectService();
    final session = TerminalSession(
      executable: 'unused',
      validateLaunch: false,
      parseExecutable: false,
    );
    addTearDown(session.dispose);
    service.requestAbort('s1', 'm1');

    final outcome = await service.deliver(
      input: session.input,
      probe: session.probe,
      sessionId: 's1',
      memberId: 'm1',
      text: 'cancel me',
      pasteSettle: Duration.zero,
      aborted: () => false,
      crAckConfig: const FullscreenCrAckConfig.productionDefault(),
    );

    expect(outcome, FullscreenPtyDeliveryOutcome.aborted);
  });

  test('an active mailbox delivery retains an interrupt until it observes it',
      () async {
    final automation = _PausedAutomation();
    final service = MemberPtyInjectService(automation: automation);
    final session = TerminalSession(
      executable: 'unused',
      validateLaunch: false,
      parseExecutable: false,
    );
    addTearDown(session.dispose);

    final delivery = service.deliver(
      input: session.input,
      probe: session.probe,
      sessionId: 's1',
      memberId: 'm1',
      text: 'cancel me',
      pasteSettle: Duration.zero,
      aborted: () => false,
      crAckConfig: const FullscreenCrAckConfig.productionDefault(),
    );
    await automation.started.future;
    service.requestAbort('s1', 'm1');
    automation.release.complete();

    expect(await delivery, FullscreenPtyDeliveryOutcome.aborted);
    expect(service.isAbortRequested('s1', 'm1'), isFalse);
  });
}
