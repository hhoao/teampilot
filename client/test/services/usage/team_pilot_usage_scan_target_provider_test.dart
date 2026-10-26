import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/usage/team_pilot_usage_scan_target_provider.dart';

import '../../support/in_memory_filesystem.dart';

InMemoryFilesystem _fs() =>
    InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));

void main() {
  test('simple session becomes one target', () async {
    final storage = fakeHomeStorage(filesystem: _fs());
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: '/home/me/proj')],
      cli: CliTool.claude,
      createdAt: 1,
    );
    final provider = TeamPilotUsageScanTargetProvider(
      storage: storage,
      loadSessions: () async => [session],
      loadTeams: () async => const [],
    );

    final targets = await provider.targets();

    expect(targets, hasLength(1));
    expect(targets.single.cli, CliTool.claude);
    expect(targets.single.sessionId, 's1');
    expect(targets.single.memberId, '');
    expect(targets.single.taskId, 's1');
    expect(targets.single.transcriptRoots, isNotEmpty);
  });

  test('mixed team expands bindings with member CLI and task id', () async {
    final storage = fakeHomeStorage(filesystem: _fs());
    const team = TeamProfile(
      id: 'team1',
      name: 'Team 1',
      members: [
        TeamMemberConfig(id: 'dev', name: 'Dev', cli: CliTool.codex),
      ],
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team1',
      cli: CliTool.claude,
      folders: const [WorkspaceFolder(path: '/home/me/proj')],
      members: const [
        SessionMemberBinding(
          rosterMemberId: 'dev',
          taskId: 'task-dev',
          cli: CliTool.codex,
        ),
      ],
      createdAt: 1,
    );
    final provider = TeamPilotUsageScanTargetProvider(
      storage: storage,
      loadSessions: () async => [session],
      loadTeams: () async => [team],
    );

    final targets = await provider.targets();

    expect(targets, hasLength(1));
    expect(targets.single.cli, CliTool.codex);
    expect(targets.single.memberId, 'dev');
    expect(targets.single.teamId, 'team1');
    expect(targets.single.taskId, 'task-dev');
  });

  test('native team without bindings uses session cli', () async {
    final storage = fakeHomeStorage(filesystem: _fs());
    const team = TeamProfile(id: 'team1', name: 'Team 1');
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team1',
      cli: CliTool.claude,
      folders: const [WorkspaceFolder(path: '/home/me/proj')],
      createdAt: 1,
    );
    final provider = TeamPilotUsageScanTargetProvider(
      storage: storage,
      loadSessions: () async => [session],
      loadTeams: () async => [team],
    );

    final targets = await provider.targets();

    expect(targets, hasLength(1));
    expect(targets.single.cli, CliTool.claude);
    expect(targets.single.memberId, '');
  });
}
