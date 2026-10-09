import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';

void main() {
  AppSession session({
    CliTool? cli,
    String team = '',
    bool? acp,
  }) => AppSession(
    sessionId: 's1',
    workspaceId: 'w1',
    createdAt: 1,
    cli: cli,
    sessionTeam: team,
    acp: acp,
  );

  test('gemini simple is ACP', () {
    expect(isAcpChatSession(session(cli: CliTool.gemini)), isTrue);
  });

  test('claude simple default is not ACP', () {
    expect(isAcpChatSession(session(cli: CliTool.claude)), isFalse);
  });

  test('claude simple with acp is ACP', () {
    expect(
      isAcpChatSession(session(cli: CliTool.claude, acp: true)),
      isTrue,
    );
  });

  test('teamed claude with acp true is not ACP', () {
    expect(
      isAcpChatSession(
        session(cli: CliTool.claude, team: 't1', acp: true),
      ),
      isFalse,
    );
  });
}
