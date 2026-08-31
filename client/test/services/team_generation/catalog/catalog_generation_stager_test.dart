import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/services/team_generation/catalog/catalog_generation_stager.dart';
import 'package:teampilot/services/team_generation/models/team_generation_job.dart';
import 'package:teampilot/services/team_generation/models/team_generation_launch.dart';
import 'package:teampilot/services/team_generation/team_generation_job_store.dart';
import 'package:teampilot/services/team_generation/team_generation_workflow_executor.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late TeamGenerationJobStore store;
  late CatalogGenerationStager stager;

  setUp(() async {
    fs = InMemoryFilesystem();
    store = TeamGenerationJobStore(
      fs: fs,
      layout: WorkspaceLayout(teampilotRoot: '/tp', fs: fs),
    );
    final settings = resolveTeamGenerationSettingsSnapshot(
      settings: TeamGenerationSettings(teamMode: TeamMode.mixed),
      presets: const [],
      registry: CliToolRegistry.builtIn(),
      capturedAt: 42,
    );
    await store.create(
      workspaceId: 'ws',
      workflowId: 'wf',
      builderSessionId: 'builder',
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
    stager = CatalogGenerationStager(
      jobStore: store,
      executor: TeamGenerationWorkflowExecutor(),
      layout: WorkspaceLayout(teampilotRoot: '/tp', fs: fs),
      fs: fs,
    );
  });

  CatalogRequest request(Map<String, Object?> arguments) => CatalogRequest(
        sessionId: 'builder',
        workspaceId: 'ws',
        bindTo: CatalogBindTo.generation,
        arguments: arguments,
        workFs: fs,
        allowedRoots: const [],
        workflowId: 'wf',
      );

  test('generation install stages without global install or workspace bind',
      () async {
    final result = await stager.handleMcpMutation(
      kind: 'skill',
      op: CatalogOp.install,
      request: request({'id': 'new-skill'}),
    );

    expect(result.boundTo, CatalogBindTo.generation);
    final job = await store.read('ws', 'wf');
    expect(job!.stagedResources, hasLength(1));
    expect(job.stagedResources.single.kind, 'skill');
    expect(job.stagedResources.single.refId, 'new-skill');
  });

  test('references existing installed resources without copying', () async {
    await stager.reference(
      workspaceId: 'ws',
      workflowId: 'wf',
      kind: 'skill',
      id: 'shared',
    );
    await stager.reference(
      workspaceId: 'ws',
      workflowId: 'wf',
      kind: 'skill',
      id: 'shared',
    );
    final job = await store.read('ws', 'wf');
    expect(job!.stagedResources, hasLength(1));
    expect(job.stagedResources.single.stagedPath, isEmpty);
  });

  test('compensation removes staged payloads and keeps references clean',
      () async {
    await stager.handleMcpMutation(
      kind: 'skill',
      op: CatalogOp.install,
      request: request({'id': 'new-skill'}),
    );
    await stager.compensate(workspaceId: 'ws', workflowId: 'wf');

    final job = await store.read('ws', 'wf');
    expect(job!.stagedResources, isEmpty);
  });

  test('inactive workflow rejects staging', () async {
    await store.beginCancel('ws', 'wf');
    await expectLater(
      stager.handleMcpMutation(
        kind: 'skill',
        op: CatalogOp.install,
        request: request({'id': 'new-skill'}),
      ),
      throwsA(isA<CatalogException>()),
    );
  });
}
