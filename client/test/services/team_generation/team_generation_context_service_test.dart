import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/services/team_generation/mcp/team_composer_mcp_handler.dart';
import 'package:teampilot/services/team_generation/models/team_generation_job.dart';
import 'package:teampilot/services/team_generation/models/team_generation_launch.dart';
import 'package:teampilot/services/team_generation/team_generation_context_payload.dart';
import 'package:teampilot/services/team_generation/team_generation_job_store.dart';
import 'package:teampilot/services/team_generation/team_generation_workflow_executor.dart';
import 'package:teampilot/utils/team/team_member_naming.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

ComposerPrincipal principal() => const ComposerPrincipal(
  sessionId: 'builder',
  workspaceId: 'ws',
  workflowId: 'wf',
);

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('context is derived from the frozen job and omits secrets', () async {
    final fs = InMemoryFilesystem();
    final store = TeamGenerationJobStore(
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
      originalPrompt: 'exact task',
      generator: TeamGenerationJobGenerator.fromSettings(settings),
      settings: settings,
      launch: const TeamGenerationLaunchSnapshot(
        projectFolderPath: '/proj',
        workingDirectoryPath: '/proj',
        launchSecurityPolicyValue: 'fullAccess',
        folderIds: ['f1'],
        targetIds: ['local'],
        workspaceRevision: 'rev-1',
        capturedAt: 1000,
      ),
    );

    final handler = TeamComposerMcpHandler(
      context: TeamComposerHandlerContext(
        jobStore: store,
        executor: TeamGenerationWorkflowExecutor(),
        contextProvider: (job) async => teamGenerationContextPayload(job),
        probeRunner: (job) async => const {},
        planValidator: (job, plan) async => const PlanValidationOutcome(
          valid: true,
          issues: [],
          normalizedPlan: {},
          revision: 'rev',
        ),
        finalizer: (job, key) async {},
      ),
    );

    final result = await handler.handleToolCall(
      requestId: 1,
      toolName: 'get_generation_context',
      arguments: const {},
      principal: principal(),
    );
    final structured =
        (result.response['result'] as Map)['structuredContent']
            as Map<String, Object?>;
    expect(structured['originalPrompt'], 'exact task');
    expect(structured['settingsRevision'], settings.revision);
    expect(structured['requestedMode'], TeamMode.mixed.value);
    expect(structured['planSchema'], isA<Map>());
    expect(
      (structured['constraints'] as Map)['leadMemberName'],
      TeamMemberNaming.teamLeadName,
    );
    expect(jsonEncode(result.response), isNot(contains('apiKey')));
    expect(jsonEncode(result.response), isNot(contains('token-1')));
  });

  test('context exposes frozen pool entry ids and four-tuples', () {
    final source = GenerateModelPoolEntry(
      id: 'pool-1',
      cli: CliTool.codex,
      provider: 'openai',
      model: 'gpt-5',
      effort: 'high',
      description: 'strong reasoning',
      tags: const ['reasoning'],
    );
    final job = TeamGenerationJob(
      workflowId: 'wf',
      workspaceId: 'ws',
      builderSessionId: 'builder',
      destinationSessionId: '',
      teamId: '',
      originalPrompt: 'task',
      generator: const TeamGenerationJobGenerator(
        generatorPresetId: 'generator',
        settingsRevision: 'rev',
        teamModeValue: 'mixed',
        nativeCliValue: 'claude',
      ),
      settings: TeamGenerationSettingsSnapshot(
        revision: 'rev',
        capturedAt: 1,
        teamMode: TeamMode.mixed,
        nativeCli: CliTool.claude,
        modelPool: [
          EffectiveGenerateModelPoolEntry(
            rank: 1,
            source: source,
            preset: syntheticPoolPreset(source),
          ),
        ],
      ),
      launch: const TeamGenerationLaunchSnapshot(
        projectFolderPath: '/proj',
        workingDirectoryPath: '/proj',
        launchSecurityPolicyValue: 'sandbox',
        folderIds: ['/proj'],
        targetIds: ['local'],
        workspaceRevision: 'workspace-rev',
        capturedAt: 1,
      ),
      phase: TeamGenerationPhase.created,
      resumePhase: TeamGenerationPhase.created,
      attempt: 0,
      probeSnapshotJson: null,
      normalizedPlanJson: null,
      planRevision: '',
      validatedRevision: '',
      validatedDestinationJson: null,
      finalizeIdempotencyKey: '',
      receipts: const {},
      stagedResources: const [],
      teamReservation: null,
      error: null,
      createdAt: 1,
      updatedAt: 1,
    );

    final pool = teamGenerationContextPayload(job)['modelPool'] as List;
    final row = pool.single as Map<String, Object?>;
    expect(row['id'], 'pool-1');
    expect(row['presetId'], row['id']);
    expect(row, containsPair('cli', 'codex'));
    expect(row, containsPair('provider', 'openai'));
    expect(row, containsPair('model', 'gpt-5'));
    expect(row, containsPair('effort', 'high'));
  });
}
