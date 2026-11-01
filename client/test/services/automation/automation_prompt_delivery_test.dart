import 'dart:async';

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
    var readiness = AutomationAcpReadiness.missing;
    var activations = 0;
    var acpSendCalls = 0;

    final outcome = await deliverAutomationPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'run',
      acpSend: () {
        acpSendCalls++;
        return readiness == AutomationAcpReadiness.ready
            ? (text) => true
            : null;
      },
      acpReadiness: () => readiness,
      activateAcp: () async {
        activations++;
        // The runtime attaches 5ms after activation returns — longer than
        // pollInterval — so the activation wait must observe at least one
        // poll tick before the sender appears.
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 5), () {
            readiness = AutomationAcpReadiness.ready;
          }),
        );
      },
      ptySubmit: (sessionId, memberId, message) async => 'pty-id',
      pollInterval: const Duration(milliseconds: 1),
      // Generous relative to the 5ms attach so an event-loop stall during the
      // poll cannot expire the deadline before the sender appears.
      activationTimeout: const Duration(milliseconds: 500),
    );

    expect(outcome.delivered, isTrue);
    expect(outcome.reason, isNull);
    expect(activations, 1);
    // The sender is resolved once, only after readiness is observed.
    expect(acpSendCalls, 1);
  });

  test('reports acp_runtime_unavailable when activation never attaches', () async {
    final outcome = await deliverAutomationPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'run',
      acpSend: () => null,
      acpReadiness: () => AutomationAcpReadiness.missing,
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
      acpReadiness: () => AutomationAcpReadiness.ready,
      activateAcp: () async {},
      ptySubmit: (sessionId, memberId, message) async => 'pty-id',
    );

    expect(outcome.delivered, isFalse);
    expect(outcome.reason, 'acp_prompt_rejected');
  });

  test('waits for a launching runtime to become ready, then delivers', () async {
    var readiness = AutomationAcpReadiness.launching;
    final sent = <String>[];
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 5), () {
        readiness = AutomationAcpReadiness.ready;
      }),
    );

    final outcome = await deliverAutomationPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'run',
      acpSend: () => (text) {
        sent.add(text);
        return true;
      },
      acpReadiness: () => readiness,
      activateAcp: () async => fail('runtime is already attached'),
      ptySubmit: (sessionId, memberId, message) async => 'pty-id',
      pollInterval: const Duration(milliseconds: 1),
      activationTimeout: const Duration(milliseconds: 500),
    );

    expect(outcome.delivered, isTrue);
    expect(sent, ['run']);
  });

  test('a runtime that ends during launch fails without sending', () async {
    var readiness = AutomationAcpReadiness.launching;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 5), () {
        readiness = AutomationAcpReadiness.ended;
      }),
    );

    final outcome = await deliverAutomationPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'run',
      acpSend: () => (text) => fail('an ended runtime must not be sent to'),
      acpReadiness: () => readiness,
      activateAcp: () async => fail('runtime is already attached'),
      ptySubmit: (sessionId, memberId, message) async => 'pty-id',
      pollInterval: const Duration(milliseconds: 1),
      activationTimeout: const Duration(milliseconds: 500),
    );

    expect(outcome.delivered, isFalse);
    expect(outcome.reason, 'acp_prompt_rejected');
  });

  test('a hung activation is bounded and fails with acp_activation_failed', () async {
    final outcome = await deliverAutomationPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'run',
      acpSend: () => null,
      acpReadiness: () => AutomationAcpReadiness.missing,
      activateAcp: () => Completer<void>().future,
      ptySubmit: (sessionId, memberId, message) async => 'pty-id',
      pollInterval: const Duration(milliseconds: 1),
      activationTimeout: const Duration(milliseconds: 10),
    );

    expect(outcome.delivered, isFalse);
    expect(outcome.reason, 'acp_activation_failed');
  });

  test('a throwing activation maps to acp_activation_failed', () async {
    final outcome = await deliverAutomationPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'run',
      acpSend: () => null,
      acpReadiness: () => AutomationAcpReadiness.missing,
      activateAcp: () async => throw StateError('boom'),
      ptySubmit: (sessionId, memberId, message) async => 'pty-id',
    );

    expect(outcome.delivered, isFalse);
    expect(outcome.reason, 'acp_activation_failed');
  });

  test('PTY seats report pty_submit_failed without an id', () async {
    final outcome = await deliverAutomationPrompt(
      session: ptySession,
      memberId: 'sess-pty',
      message: 'run',
      acpSend: () => null,
      acpReadiness: () => fail('PTY seats must not read ACP readiness'),
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
      acpReadiness: () => fail('PTY seats must not read ACP readiness'),
      activateAcp: () async => fail('PTY seats must not activate ACP'),
      ptySubmit: (sessionId, memberId, message) async => 'delivery-1',
    );

    expect(outcome.delivered, isTrue);
  });
}
