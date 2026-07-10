import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/launch/session_runtime_plan.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/post_frame_test_harness.dart';
import '../../support/test_runtime_context.dart';

RuntimeContext _roots(String basePath) => testRuntimeContext(basePath);

void main() {
  late Directory base;
  late RuntimeLayout layout;

  setUp(() async {
    setUpTestAppStorage();
    base = await Directory.systemTemp.createTemp('session_lifecycle_standalone_');
    layout = RuntimeLayout(teampilotRoot: base.path);
  });

  tearDown(() async {
    if (await base.exists()) {
      await base.delete(recursive: true);
    }
    tearDownTestAppStorage();
  });

  SessionLifecycleService service() => SessionLifecycleService(
        appDataBasePath: base.path,
        storageRootsResolver: () async => _roots(base.path),
      );

  SessionRuntimePlan simplePlan({
    required String workspaceId,
    required String sessionId,
    TeamMemberConfig? member,
  }) {
    return SessionRuntimePlan(
      mode: SessionRuntimeMode.simple,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: member?.id ?? 'seat-1',
      expertKey: 'teampilot/builtin/default',
      runtimeBundle: const ConfigBundle(),
      member: member ??
          const TeamMemberConfig(
            id: 'default',
            name: 'Default',
            agent: 'default',
          ),
    );
  }

  test('prepareShellLaunchFromRuntimePlan includes CliLaunchContext', () async {
    const workspaceId = 'ws-simple';
    const sessionId = 'sess-simple';
    final workspace = Workspace(
      workspaceId: workspaceId,
      folders: const [WorkspaceFolder(path: '/work/simple')],
      createdAt: 1,
    );
    final session = AppSession(
      sessionId: sessionId,
      workspaceId: workspaceId,
      folders: const [WorkspaceFolder(path: '/work/simple')],
      sessionTeam: '',
      createdAt: 1,
    );

    final shellLaunch = await service().prepareShellLaunchFromRuntimePlan(
      session: session,
      workspace: workspace,
      plan: simplePlan(
        workspaceId: workspaceId,
        sessionId: sessionId,
        member: const TeamMemberConfig(
          id: 'solo',
          name: 'solo',
          agent: 'solo',
          provider: 'anthropic',
          model: 'sonnet',
          cli: CliTool.claude,
        ),
      ),
    );

    expect(shellLaunch.sessionTeam, sessionId);
    expect(shellLaunch.launchContext.member.model, 'sonnet');
    expect(shellLaunch.launchContext.member.agent, 'solo');
    expect(shellLaunch.launchContext.team.cli, CliTool.claude);
    expect(shellLaunch.plan.env['CLAUDE_CONFIG_DIR'], isNotEmpty);
  });

  test(
    'prepareShellLaunch throws without team and member for non-simple sessions',
    () async {
      final session = AppSession(
        sessionId: 'team-sess',
        workspaceId: 'proj',
        folders: const [WorkspaceFolder(path: '/work/team')],
        sessionTeam: 'tid',
        cliTeamName: 'tid-1',
        createdAt: 1,
      );

      expect(
        () => service().prepareShellLaunch(session: session, team: null),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('destroyStandaloneCliState removes session runtime tree', () async {
    const workspaceId = 'ws-simple';
    const sessionId = 'sess-simple';
    final sessionRoot = p.dirname(
      layout.sessionRuntimeToolDir(workspaceId, sessionId, 'claude'),
    );
    await File(
      p.join(sessionRoot, 'claude', 'workspaces', 'bucket', '$sessionId.jsonl'),
    ).create(recursive: true);

    expect(await Directory(sessionRoot).exists(), isTrue);
    await service().destroyStandaloneCliState(
      workspaceId: workspaceId,
      sessionId: sessionId,
    );
    expect(await Directory(sessionRoot).exists(), isFalse);
  });
}
