import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/chat/launch/session/session_provisional_builder.dart';

void main() {
  final workspace = Workspace(
    workspaceId: 'ws-1',
    createdAt: 0,
    folders: [WorkspaceFolder(path: '/repo/main')],
  );

  test('personal Claude acp true persists true', () {
    final session = buildProvisionalSession(
      sessionId: 's1',
      workspace: workspace,
      isPersonal: true,
      usesPosixPaths: true,
      cli: CliTool.claude,
      acp: true,
    );
    expect(session.acp, isTrue);
  });

  test('personal Claude default is false', () {
    final session = buildProvisionalSession(
      sessionId: 's1',
      workspace: workspace,
      isPersonal: true,
      usesPosixPaths: true,
      cli: CliTool.claude,
    );
    expect(session.acp, isFalse);
  });

  test('personal Gemini is always acp true', () {
    final session = buildProvisionalSession(
      sessionId: 's1',
      workspace: workspace,
      isPersonal: true,
      usesPosixPaths: true,
      cli: CliTool.gemini,
      acp: false,
    );
    expect(session.acp, isTrue);
  });

  test('team session is always acp false, even when requested', () {
    final requested = buildProvisionalSession(
      sessionId: 's1',
      workspace: workspace,
      isPersonal: false,
      usesPosixPaths: true,
      cli: CliTool.claude,
      sessionTeamId: 'team-1',
      acp: true,
    );
    expect(requested.acp, isFalse);

    final defaulted = buildProvisionalSession(
      sessionId: 's2',
      workspace: workspace,
      isPersonal: false,
      usesPosixPaths: true,
      cli: CliTool.claude,
      sessionTeamId: 'team-1',
    );
    expect(defaulted.acp, isFalse);
  });

  test('team session stays acp false for an ACP-only CLI', () {
    final session = buildProvisionalSession(
      sessionId: 's1',
      workspace: workspace,
      isPersonal: false,
      usesPosixPaths: true,
      cli: CliTool.gemini,
      sessionTeamId: 'team-1',
    );
    expect(session.acp, isFalse);
  });
}
