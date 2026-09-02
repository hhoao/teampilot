import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/services/team_generation/mcp/team_composer_mcp_constants.dart';
import 'package:teampilot/services/team_generation/mcp/team_composer_mcp_handler.dart';
import 'package:teampilot/services/team_generation/models/team_generation_job.dart';
import 'package:teampilot/services/team_generation/models/team_generation_launch.dart';
import 'package:teampilot/services/team_generation/team_generation_job_store.dart';
import 'package:teampilot/services/team_generation/team_generation_workflow_executor.dart';

import '../../support/in_memory_filesystem.dart';

Map<String, Object?> structured(TeamComposerMcpResult result) =>
    ((result.response['result'] as Map)['structuredContent'] as Map)
        .cast<String, Object?>();

final class _FakeComposerConversation {
  const _FakeComposerConversation({
    required this.handler,
    required this.principal,
  });

  final TeamComposerMcpHandler handler;
  final ComposerPrincipal principal;

  Future<List<TeamComposerMcpResult>> run() async => [
    await _call(TeamComposerToolName.getContext),
    await _call(TeamComposerToolName.probeTargets),
    await _call(TeamComposerToolName.validatePlan, {
      'plan': {'draft': 'rejected'},
    }),
    await _call(TeamComposerToolName.validatePlan, {
      'plan': {'draft': 'corrected'},
    }),
    await _call(TeamComposerToolName.finalize, {
      'plan': {'draft': 'corrected'},
      'validationRevision': 'good-revision',
      'idempotencyKey': 'builder-finalize-1',
    }),
  ];

  Future<TeamComposerMcpResult> _call(
    String tool, [
    Map<String, Object?> arguments = const {},
  ]) => handler.handleToolCall(
    requestId: tool,
    toolName: tool,
    arguments: arguments,
    principal: principal,
  );
}

void main() {
  test(
    'fake Builder conversation corrects a rejected plan before one accepted finalize',
    () async {
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
        originalPrompt: 'Create a release team',
        generator: TeamGenerationJobGenerator.fromSettings(settings),
        settings: settings,
        launch: const TeamGenerationLaunchSnapshot(
          projectFolderPath: '/proj',
          workingDirectoryPath: '/proj',
          launchSecurityPolicyValue: 'fullAccess',
          folderIds: ['/proj'],
          targetIds: ['local'],
          workspaceRevision: 'rev-1',
          capturedAt: 1000,
        ),
      );

      final calls = <String>[];
      final finalized = <String>[];
      final handler = TeamComposerMcpHandler(
        context: TeamComposerHandlerContext(
          jobStore: store,
          executor: TeamGenerationWorkflowExecutor(),
          contextProvider: (job) async {
            calls.add(TeamComposerToolName.getContext);
            return {
              'originalPrompt': job.originalPrompt,
              'launch': job.launch.toJson(),
            };
          },
          probeRunner: (job) async {
            calls.add(TeamComposerToolName.probeTargets);
            return {
              'targets': ['local'],
            };
          },
          planValidator: (job, plan) async {
            final draft = plan['draft'] as String;
            calls.add('${TeamComposerToolName.validatePlan}:$draft');
            if (draft == 'rejected') {
              return const PlanValidationOutcome(
                valid: false,
                issues: [
                  {'code': 'missing_team_lead'},
                ],
                normalizedPlan: {'draft': 'rejected'},
                revision: 'bad-revision',
              );
            }
            return const PlanValidationOutcome(
              valid: true,
              issues: [],
              normalizedPlan: {'draft': 'corrected'},
              revision: 'good-revision',
              destination: {
                'folderId': '/proj',
                'projectFolderPath': '/proj',
                'workingDirectoryPath': '/proj',
                'leadTargetId': 'local',
              },
            );
          },
          finalizer: (job, key) async {
            finalized.add('${job.workflowId}:$key');
          },
        ),
      );
      const principal = ComposerPrincipal(
        sessionId: 'builder',
        workspaceId: 'ws',
        workflowId: 'wf',
      );

      // The conversation, not a coordinator retry policy, makes each call.
      final transcript = await _FakeComposerConversation(
        handler: handler,
        principal: principal,
      ).run();
      final context = transcript[0];
      expect(structured(context)['originalPrompt'], 'Create a release team');

      final probe = transcript[1];
      expect(structured(probe)['status'], 'probed');

      final rejected = transcript[2];
      expect(structured(rejected), {
        'valid': false,
        'issues': [
          {'code': 'missing_team_lead'},
        ],
        'revision': 'bad-revision',
      });

      final corrected = transcript[3];
      expect(structured(corrected)['valid'], isTrue);
      expect(structured(corrected)['revision'], 'good-revision');
      expect(
        (await store.read('ws', 'wf'))!.validatedRevision,
        'good-revision',
      );

      final accepted = transcript[4];
      expect(structured(accepted)['accepted'], isTrue);
      expect(finalized, isEmpty);
      expect(calls, [
        TeamComposerToolName.getContext,
        TeamComposerToolName.probeTargets,
        '${TeamComposerToolName.validatePlan}:rejected',
        '${TeamComposerToolName.validatePlan}:corrected',
      ]);
      expect(
        calls.where(
          (call) => call.startsWith(TeamComposerToolName.validatePlan),
        ),
        hasLength(2),
      );

      await accepted.afterResponseFlushed!();
      expect(finalized, ['wf:builder-finalize-1']);
    },
  );
}
