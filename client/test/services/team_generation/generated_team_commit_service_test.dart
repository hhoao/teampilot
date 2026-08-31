import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_topology.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/expert_hub/local_expert_store.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/services/team_generation/generated_team_commit_service.dart';
import 'package:teampilot/services/team_generation/models/team_generation_job.dart';
import 'package:teampilot/services/team_generation/models/team_generation_launch.dart';
import 'package:teampilot/services/team_generation/team_generation_job_store.dart';
import 'package:teampilot/services/team_generation/team_generation_workflow_executor.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

class _RecordingProvisioner implements TeamProfileResourceProvisioner {
  final events = <String>[];
  @override
  Future<void> provision(TeamProfile team) async {
    events.add('provision:${team.id}');
  }
}

class _RecordingPublisher implements GeneratedTeamStatePublisher {
  final events = <String>[];
  @override
  Future<void> publish({
    required TeamProfile team,
    required Workspace workspace,
  }) async {
    events.add('publish:${team.id}');
  }
}

class _FakeSessionRepository extends Fake implements SessionRepository {
  final placements = <String>[];

  @override
  Future<Workspace?> updateWorkspaceMemberPlacement(
    String workspaceId,
    String teamId, {
    required MemberTargetAssignments targets,
  }) async {
    placements.add('$workspaceId/$teamId');
    return null;
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  late InMemoryFilesystem fs;
  late TeamGenerationJobStore store;
  late LocalExpertStore expertStore;
  late _RecordingProvisioner provisioner;
  late _RecordingPublisher publisher;
  late _FakeSessionRepository sessionRepository;

  Workspace workspace() => Workspace(
        workspaceId: 'ws',
        folders: const [WorkspaceFolder(path: '/proj', targetId: 'local')],
        createdAt: 1,
        updatedAt: 1,
      );

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
      workflowId: 'wf-12345678',
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
    // Seed a validated mixed plan and revision.
    final plan = {
      'team': {'name': 'Delivery Team', 'mode': 'mixed'},
      'members': [
        {
          'name': 'team-lead',
          'role': 'Delivery Lead',
          'responsibilities': 'Own integration',
          'workingMethod': 'Delegate',
          'presetId': '',
          'replicas': 1,
          'placement': {'local': 1},
        },
        {
          'name': 'worker',
          'role': 'Worker',
          'responsibilities': 'Implements tasks',
          'workingMethod': 'Test-first',
          'presetId': '',
          'replicas': 1,
          'placement': {'local': 1},
        },
      ],
      'resources': {
        'skillIds': <String>[],
        'pluginIds': <String>[],
        'mcpServerIds': <String>[],
      },
    };
    await store.mutate('ws', 'wf-12345678', (job) {
      return job.copyWith(
        normalizedPlanJson: plan,
        planRevision: 'rev',
        validatedRevision: 'valid-rev',
        validatedDestinationJson: const {
          'folderId': '/proj',
          'projectFolderPath': '/proj',
          'workingDirectoryPath': '/proj',
          'leadTargetId': 'local',
        },
      );
    });

    expertStore = LocalExpertStore(fs: fs, dirOverride: '/tp/experts');
    provisioner = _RecordingProvisioner();
    publisher = _RecordingPublisher();
    sessionRepository = _FakeSessionRepository();
  });

  GeneratedTeamCommitService service() => GeneratedTeamCommitService(
        jobStore: store,
        expertStore: expertStore,
        profileRepository: LaunchProfileRepository(),
        sessionRepository: sessionRepository,
        resourceProvisioner: provisioner,
        publisher: publisher,
      );

  test('commit persists profile, placement, provision, and publish in order',
      () async {
    final result = await service().commit(
      workspace: workspace(),
      workflowId: 'wf-12345678',
      validatedRevision: 'valid-rev',
    );

    expect(result.team.id, isNotEmpty);
    expect(sessionRepository.placements.single, contains('ws/'));
    expect(provisioner.events.single, startsWith('provision:'));
    expect(publisher.events.single, startsWith('publish:'));

    final job = await store.read('ws', 'wf-12345678');
    expect(job!.receipts['profile']!.state, TeamGenerationReceiptState.succeeded);
    expect(job.receipts['expert']!.state, TeamGenerationReceiptState.succeeded);
    expect(job.teamId, result.team.id);
  });

  test('second commit reuses receipts without duplicate placement writes',
      () async {
    final svc = service();
    final first = await svc.commit(
      workspace: workspace(),
      workflowId: 'wf-12345678',
      validatedRevision: 'valid-rev',
    );
    final placementsAfterFirst = sessionRepository.placements.length;

    final second = await svc.commit(
      workspace: workspace(),
      workflowId: 'wf-12345678',
      validatedRevision: 'valid-rev',
    );

    expect(second.team.id, first.team.id);
    expect(sessionRepository.placements.length, placementsAfterFirst + 1);
  });
}
