import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/services/team_generation/models/team_generation_job.dart';
import 'package:teampilot/services/team_generation/models/team_generation_launch.dart';
import 'package:teampilot/services/team_generation/team_generation_authorizer.dart';
import 'package:teampilot/services/team_generation/team_generation_job_store.dart';

import '../../support/in_memory_filesystem.dart';

class _StaticSessionLookup implements TeamGenerationSessionLookup {
  _StaticSessionLookup(this.sessions);

  final Map<String, AppSession> sessions;

  @override
  Future<AppSession?> findById(String sessionId) async => sessions[sessionId];
}

TeamGenerationJobStore buildStore(InMemoryFilesystem fs) => TeamGenerationJobStore(
  fs: fs,
  layout: WorkspaceLayout(teampilotRoot: '/tp', fs: fs),
  clock: () => DateTime.utc(2026, 8, 31),
);

Future<TeamGenerationJob> seedBuilderJob(
  TeamGenerationJobStore store, {
  String builderSessionId = 'builder',
}) {
  final settings = resolveTeamGenerationSettingsSnapshot(
    settings: TeamGenerationSettings(teamMode: TeamMode.mixed),
    presets: const [],
    registry: CliToolRegistry.builtIn(),
    capturedAt: 42,
  );
  return store.create(
    workspaceId: 'ws',
    workflowId: 'wf',
    builderSessionId: builderSessionId,
    originalPrompt: 'task',
    generator: TeamGenerationJobGenerator.fromSettings(settings),
    settings: settings,
    launch: const TeamGenerationLaunchSnapshot(
      projectFolderPath: '/proj',
      workingDirectoryPath: '/proj',
      launchSecurityPolicyValue: 'fullAccess',
      folderIds: [],
      targetIds: ['local'],
      workspaceRevision: 'rev-1',
      capturedAt: 1000,
    ),
  );
}

void main() {
  test('authorization fails for cancelled jobs and unknown sessions',
      () async {
    final fs = InMemoryFilesystem();
    final store = buildStore(fs);
    await seedBuilderJob(store);
    final sessions = <String, AppSession>{
      'builder': AppSession(
        sessionId: 'builder',
        workspaceId: 'ws',
        purpose: SessionPurpose.teamGeneration,
        workflowId: 'wf',
        createdAt: 1,
      ),
    };
    final auth = TeamGenerationAuthorizer(
      sessionLookup: _StaticSessionLookup(sessions),
      jobStore: store,
      tokenFactory: () => 'token-1',
    );
    const principal = TeamGenerationPrincipal(
      sessionId: 'builder',
      workspaceId: 'ws',
      workflowId: 'wf',
    );

    final token = await auth.issue(principal);
    expect(await auth.authorize(principal: principal, token: token), isTrue);

    // Cancel the workflow: authorization must fail immediately.
    await store.beginCancel('ws', 'wf');
    expect(
      await auth.authorize(principal: principal, token: token),
      isFalse,
    );
    auth.revoke('wf');

    // Unknown session: no authorization.
    expect(
      await auth.authorize(
        principal: const TeamGenerationPrincipal(
          sessionId: 'ghost',
          workspaceId: 'ws',
          workflowId: 'wf',
        ),
        token: token,
      ),
      isFalse,
    );
  });

  test('issued token never appears in job.json', () async {
    final fs = InMemoryFilesystem();
    final store = buildStore(fs);
    await seedBuilderJob(store);
    final sessions = <String, AppSession>{
      'builder': AppSession(
        sessionId: 'builder',
        workspaceId: 'ws',
        purpose: SessionPurpose.teamGeneration,
        workflowId: 'wf',
        createdAt: 1,
      ),
    };
    final auth = TeamGenerationAuthorizer(
      sessionLookup: _StaticSessionLookup(sessions),
      jobStore: store,
      tokenFactory: () => 'super-secret-token',
    );
    await auth.issue(
      const TeamGenerationPrincipal(
        sessionId: 'builder',
        workspaceId: 'ws',
        workflowId: 'wf',
      ),
    );

    final raw = await fs.readString(
      '/tp/workspace/workspaces/ws/team-generation/wf/job.json',
    );
    expect(raw, isNotNull);
    expect(raw, isNot(contains('super-secret-token')));
  });
}
