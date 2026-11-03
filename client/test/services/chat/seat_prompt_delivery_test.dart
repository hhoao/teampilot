import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/session/seat_prompt_delivery.dart';

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
  final mixedAcpSession = AppSession(
    sessionId: 'sess-mixed',
    workspaceId: 'ws',
    sessionTeam: 'team-1',
    members: const [
      SessionMemberBinding(
        rosterMemberId: 'team-lead',
        taskId: 't1',
        cli: CliTool.cursor,
        acp: true,
      ),
    ],
    createdAt: 1,
  );

  test('personal ACP sends through the cubit and never the PTY seam', () async {
    final sent = <String>[];
    var ptyCalls = 0;

    final result = await deliverSeatPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'hello',
      acpSend: (text) {
        sent.add(text);
        return true;
      },
      ptySubmit: (sessionId, memberId, message) async {
        ptyCalls++;
        return 'pty-id';
      },
    );

    expect(result, SeatPromptDeliveryResult.delivered);
    expect(sent, ['hello']);
    expect(ptyCalls, 0);
  });

  test('ACP without a runtime is runtimeUnavailable, not a PTY submit', () async {
    var ptyCalls = 0;

    final result = await deliverSeatPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'hello',
      acpSend: null,
      ptySubmit: (sessionId, memberId, message) async {
        ptyCalls++;
        return 'pty-id';
      },
    );

    expect(result, SeatPromptDeliveryResult.runtimeUnavailable);
    expect(ptyCalls, 0);
  });

  test('ACP send rejected while a turn is in flight', () async {
    final result = await deliverSeatPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'hello',
      acpSend: (text) => false,
      ptySubmit: (sessionId, memberId, message) async => 'pty-id',
    );

    expect(result, SeatPromptDeliveryResult.rejected);
  });

  test('mixed ACP seat uses the cubit', () async {
    final sent = <String>[];
    var ptyCalls = 0;

    final result = await deliverSeatPrompt(
      session: mixedAcpSession,
      memberId: 'team-lead',
      message: 'hello',
      acpSend: (text) {
        sent.add(text);
        return true;
      },
      ptySubmit: (sessionId, memberId, message) async {
        ptyCalls++;
        return 'pty-id';
      },
    );

    expect(result, SeatPromptDeliveryResult.delivered);
    expect(sent, ['hello']);
    expect(ptyCalls, 0);
  });

  test('PTY session uses the submit seam', () async {
    String? seenMessage;

    final result = await deliverSeatPrompt(
      session: ptySession,
      memberId: 'sess-pty',
      message: 'via pty',
      acpSend: (text) => fail('ACP must not be used for a PTY session'),
      ptySubmit: (sessionId, memberId, message) async {
        seenMessage = message;
        return 'delivery-1';
      },
    );

    expect(result, SeatPromptDeliveryResult.delivered);
    expect(seenMessage, 'via pty');
  });

  test('PTY submit without an id is ptyUnconfirmed', () async {
    final result = await deliverSeatPrompt(
      session: ptySession,
      memberId: 'sess-pty',
      message: 'via pty',
      acpSend: (text) => fail('ACP must not be used for a PTY session'),
      ptySubmit: (sessionId, memberId, message) async => null,
    );

    expect(result, SeatPromptDeliveryResult.ptyUnconfirmed);
  });
}
