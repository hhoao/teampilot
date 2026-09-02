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
  final placementTargets = <MemberTargetAssignments>[];

  @override
  Future<Workspace?> updateWorkspaceMemberPlacement(
    String workspaceId,
    String teamId, {
    required MemberTargetAssignments targets,
  }) async {
    placements.add('$workspaceId/$teamId');
    placementTargets.add(Map<String, String>.from(targets));
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
  late LaunchProfileRepository profileRepository;

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
    profileRepository = LaunchProfileRepository();
  });

  GeneratedTeamCommitService service() => GeneratedTeamCommitService(
        jobStore: store,
        expertStore: expertStore,
        profileRepository: profileRepository,
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

  test('persists one stable unique expert per normalized roster role', () async {
    final result = await service().commit(
      workspace: workspace(),
      workflowId: 'wf-12345678',
      validatedRevision: 'valid-rev',
    );

    final experts = await expertStore.loadAll();
    final expertKeys = experts.map((expert) => expert.key).toSet();
    final rosterKeys = result.team.roster.map((slot) => slot.expertKey).toSet();
    expect(experts, hasLength(2));
    expect(rosterKeys, hasLength(2));
    expect(rosterKeys, expertKeys);
    expect(rosterKeys.any((key) => key.endsWith('/team-lead')), isTrue);
    expect(rosterKeys.any((key) => key.endsWith('/worker')), isTrue);
  });

  test('persists validated per-role replicas and placement targets', () async {
    final original = (await store.read('ws', 'wf-12345678'))!;
    final plan = Map<String, Object?>.from(original.normalizedPlanJson!);
    plan['members'] = [
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
        'replicas': 2,
        'placement': {'local': 1, 'ssh-1': 1},
      },
    ];
    await store.mutate(
      'ws',
      'wf-12345678',
      (job) => job.copyWith(normalizedPlanJson: plan),
    );
    final mixedWorkspace = Workspace(
      workspaceId: 'ws',
      folders: const [
        WorkspaceFolder(path: '/proj', targetId: 'local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh-1'),
      ],
      createdAt: 1,
      updatedAt: 1,
    );

    final result = await service().commit(
      workspace: mixedWorkspace,
      workflowId: 'wf-12345678',
      validatedRevision: 'valid-rev',
    );

    final worker = result.team.roster.singleWhere((slot) => slot.id == 'worker');
    expect(worker.overrides.replicas, 2);
    expect(sessionRepository.placementTargets.single, {
      'team-lead': 'local',
      'worker-0': 'local',
      'worker-1': 'ssh-1',
    });
    final persisted = (await profileRepository.loadTeamProfiles()).singleWhere(
      (profile) => profile.id == result.team.id,
    );
    expect(
      persisted.roster.singleWhere((slot) => slot.id == 'worker').overrides.replicas,
      2,
    );
  });
}
