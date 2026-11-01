import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/automation/automation_prompt_delivery.dart';

void main() {
  final acpSession = AppSession(
    sessionId: 'sess-acp',
    workspaceId: 'ws',
    cli: CliTool.claude,
    acp: true,
    createdAt: 1,
  );
  final ptySession = AppSession(
    sessionId: 'sess-pty',
    workspaceId: 'ws',
    cli: CliTool.claude,
    createdAt: 1,
  );

  test('activates a missing ACP runtime and then delivers', () async {
    bool? sender;
    var activations = 0;

    final outcome = await deliverAutomationPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'run',
      acpSend: () => sender == null ? null : (text) => true,
      activateAcp: () async {
        activations++;
        sender = true;
      },
      ptySubmit: (sessionId, memberId, message) async => 'pty-id',
      pollInterval: const Duration(milliseconds: 1),
      activationTimeout: const Duration(milliseconds: 50),
    );

    expect(outcome.delivered, isTrue);
    expect(outcome.reason, isNull);
    expect(activations, 1);
  });

  test('reports acp_runtime_unavailable when activation never attaches', () async {
    final outcome = await deliverAutomationPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'run',
      acpSend: () => null,
      activateAcp: () async {},
      ptySubmit: (sessionId, memberId, message) async => 'pty-id',
      pollInterval: const Duration(milliseconds: 1),
      activationTimeout: const Duration(milliseconds: 5),
    );

    expect(outcome.delivered, isFalse);
    expect(outcome.reason, 'acp_runtime_unavailable');
  });

  test('reports acp_prompt_rejected when the runtime refuses', () async {
    final outcome = await deliverAutomationPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'run',
      acpSend: () => (text) => false,
      activateAcp: () async {},
      ptySubmit: (sessionId, memberId, message) async => 'pty-id',
    );

    expect(outcome.delivered, isFalse);
    expect(outcome.reason, 'acp_prompt_rejected');
  });

  test('PTY seats report pty_submit_failed without an id', () async {
    final outcome = await deliverAutomationPrompt(
      session: ptySession,
      memberId: 'sess-pty',
      message: 'run',
      acpSend: () => null,
      activateAcp: () async => fail('PTY seats must not activate ACP'),
      ptySubmit: (sessionId, memberId, message) async => null,
    );

    expect(outcome.delivered, isFalse);
    expect(outcome.reason, 'pty_submit_failed');
  });

  test('PTY seats deliver on a submitted id', () async {
    final outcome = await deliverAutomationPrompt(
      session: ptySession,
      memberId: 'sess-pty',
      message: 'run',
      acpSend: () => null,
      activateAcp: () async => fail('PTY seats must not activate ACP'),
      ptySubmit: (sessionId, memberId, message) async => 'delivery-1',
    );

    expect(outcome.delivered, isTrue);
  });
}
