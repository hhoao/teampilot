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
}
