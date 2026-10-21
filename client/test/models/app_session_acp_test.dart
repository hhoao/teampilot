import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  test('claude simple defaults acp false and persists it explicitly', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.claude,
    );
    expect(s.acp, isFalse);
    // Explicit false, so a later default/inference change cannot flip a
    // persisted PTY session to ACP.
    expect(s.toJson()['acp'], isFalse);
    expect(AppSession.fromJson(s.toJson()).acp, isFalse);
  });

  test('gemini simple infers acp true when omitted', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.gemini,
    );
    expect(s.acp, isTrue);
    expect(s.toJson()['acp'], isTrue);
  });

  test('legacy JSON without acp: gemini simple is true, claude is false', () {
    expect(
      AppSession.fromJson({
        'sessionId': 's1',
        'workspaceId': 'w1',
        'createdAt': 1,
        'cli': 'gemini',
      }).acp,
      isTrue,
    );
    expect(
      AppSession.fromJson({
        'sessionId': 's1',
        'workspaceId': 'w1',
        'createdAt': 1,
        'cli': 'claude',
      }).acp,
      isFalse,
    );
  });

  test('acp true round-trips; explicit false wins over gemini inference', () {
    final on = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.claude,
      acp: true,
    );
    expect(AppSession.fromJson(on.toJson()).acp, isTrue);

    final geminiOff = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.gemini,
      acp: false,
    );
    expect(geminiOff.acp, isFalse);
    expect(geminiOff.toJson()['acp'], isFalse);
    expect(AppSession.fromJson(geminiOff.toJson()).acp, isFalse);
  });

  test('acpPermission omits fullAccess and round-trips ask only when acp', () {
    final off = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.claude,
      acp: true,
    );
    expect(off.acpPermission, LaunchSecurityPolicy.fullAccess);
    expect(off.toJson().containsKey('acpPermission'), isFalse);

    final ask = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.claude,
      acp: true,
      acpPermission: LaunchSecurityPolicy.ask,
    );
    expect(ask.toJson()['acpPermission'], 'ask');
    expect(
      AppSession.fromJson(ask.toJson()).acpPermission,
      LaunchSecurityPolicy.ask,
    );

    final team = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      sessionTeam: 'team-1',
      acpPermission: LaunchSecurityPolicy.ask,
    );
    expect(team.acp, isFalse);
    expect(team.acpPermission, LaunchSecurityPolicy.fullAccess);
    expect(team.toJson().containsKey('acpPermission'), isFalse);
  });
}
