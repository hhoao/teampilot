import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/terminal_composer_region.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_automation.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_delivery_port.dart';
import 'package:teampilot/services/terminal/member_pty_inject_service.dart';
import 'package:teampilot/services/terminal/pty_automation_retry_queue.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

final class _ControlledPasteNotFoundAutomation extends FullscreenPtyAutomation {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<FullscreenPtyDeliveryOutcome> deliverPasteAndSubmit({
    required FullscreenPtyDeliveryPort port,
    required String text,
    required Duration pasteSettle,
    bool Function()? isAcked,
  }) async {
    started.complete();
    await release.future;
    return FullscreenPtyDeliveryOutcome.pasteNotFound;
  }
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
    text: 'cancel me',
    pasteSettle: Duration.zero,
    aborted: () => false,
    composerRegion: fullscreenDefaultComposerSpec,
  );
}

void main() {
  test('requestAbort marks seat aborted and clears pending', () {
    final retryQueue = PtyAutomationRetryQueue(
      retryIntervalMs: 0,
      maxAttempts: 1,
    );
    final service = MemberPtyInjectService(retryQueue: retryQueue);
    retryQueue.schedule(
      key: 's1:m1',
      sessionId: 's1',
      memberId: 'm1',
      text: 'pending',
    );

    service.requestAbort('s1', 'm1');

    expect(service.isAbortRequested('s1', 'm1'), isTrue);
    expect(service.hasPendingRetry('s1', 'm1'), isFalse);
  });

  test(
    'abort during locked pasteNotFound run does not schedule retry',
    () async {
      final automation = _ControlledPasteNotFoundAutomation();
      final service = MemberPtyInjectService(automation: automation);
      final session = TerminalSession(
        executable: 'unused',
        validateLaunch: false,
        parseExecutable: false,
      );
      addTearDown(session.dispose);
      final delivery = _deliver(service, session);
      await automation.started.future;

      service.requestAbort('s1', 'm1');
      automation.release.complete();

      expect(await delivery, FullscreenPtyDeliveryOutcome.aborted);
      expect(service.hasPendingRetry('s1', 'm1'), isFalse);
      expect(service.isAbortRequested('s1', 'm1'), isFalse);
    },
  );

  test('clearing idle abort allows the next inject', () async {
    final automation = _ControlledPasteNotFoundAutomation();
    final service = MemberPtyInjectService(automation: automation);
    final session = TerminalSession(
      executable: 'unused',
      validateLaunch: false,
      parseExecutable: false,
    );
    addTearDown(session.dispose);
    service.requestAbort('s1', 'm1');
    expect(service.isBusy('s1', 'm1'), isFalse);

    service.clearAbort('s1', 'm1');
    final delivery = _deliver(service, session);
    await automation.started.future;
    automation.release.complete();

    expect(await delivery, FullscreenPtyDeliveryOutcome.pasteNotFound);
    expect(service.hasPendingRetry('s1', 'm1'), isTrue);
  });
}
