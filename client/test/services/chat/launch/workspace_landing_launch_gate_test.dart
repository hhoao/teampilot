import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/cli_binary_kind.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/chat/launch/pre_send/local_binary_requirements.dart';
import 'package:teampilot/services/chat/launch/pre_send/workspace_landing_launch_gate.dart';
import 'package:teampilot/services/remote/remote_cli_readiness.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/chat/launch/session/team_config_launch_validator.dart';
import 'package:teampilot/utils/team/team_member_naming.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  final gate = WorkspaceLandingLaunchGate(
    storage: HomeStorage.forTesting(
      filesystem: InMemoryFilesystem(),
      paths: AppPaths('/test-home'),
    ),
    teamConfigValidator: _AlwaysValidTeamConfigValidator(),
  );

  group('WorkspaceLandingLaunchGate.syncBlock', () {
    test('allows personal draft', () {
      final block = gate.syncBlock(
        workspace: _mixedWorkspace(),
        draft: const LandingLaunchContext(isPersonal: true),
        team: null,
      );
      expect(block, isNull);
    });

    test('blocks mixed workspace when placement not initialized', () {
      final team = _team();
      final block = gate.syncBlock(
        workspace: _mixedWorkspace(),
        draft: LandingLaunchContext(isPersonal: false, teamId: team.id),
        team: team,
      );
      expect(block, isA<MixedMemberPlacementUninitializedLaunchBlock>());
    });

    test(
      'allows mixed when initialized even if non-lead has zero replicas',
      () {
        final team = TeamProfile(
          id: 'team-1',
          name: 'Team',
          members: const [
            TeamMemberConfig(id: 'team-lead', name: 'Lead'),
            TeamMemberConfig(id: 'dev', name: 'Dev', replicas: 0),
          ],
          createdAt: 1,
        );
        final workspace = Workspace(
          workspaceId: 'ws-1',
          folders: [
            const WorkspaceFolder(path: '/a', targetId: 'local'),
            const WorkspaceFolder(path: '/b', targetId: 'ssh:host-a'),
          ],
          createdAt: 1,
          memberTargetsByTeam: {
            team.id: {'team-lead': 'local'},
          },
          memberPlacementInitializedByTeam: {team.id: true},
        );
        expect(
          gate.syncBlock(
            workspace: workspace,
            draft: LandingLaunchContext(isPersonal: false, teamId: team.id),
            team: team,
          ),
          isNull,
        );
      },
    );

    test('blocks when lead placement is invalid', () {
      final team = _singleMemberTeam();
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: [
          const WorkspaceFolder(path: '/a', targetId: 'local'),
          const WorkspaceFolder(path: '/b', targetId: 'ssh:host-a'),
        ],
        createdAt: 1,
        memberTargetsByTeam: {
          team.id: {'team-lead': 'ssh:host-a'},
        },
        memberPlacementInitializedByTeam: {team.id: true},
      );
      final block = gate.syncBlock(
        workspace: workspace,
        draft: LandingLaunchContext(isPersonal: false, teamId: team.id),
        team: team,
      );
      expect(block, isA<LeadPlacementInvalidLaunchBlock>());
    });
  });

  group('WorkspaceLandingLaunchGate.asyncRemoteCliBlock', () {
    const sshTarget = RuntimeTarget(
      id: 'ssh:host-a',
      label: 'Remote',
      kind: RuntimeKind.ssh,
      sshProfileId: 'host-a',
    );

    test('allows when all required remote CLIs are ready', () async {
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        cli: CliTool.codex,
        members: const [TeamMemberConfig(id: 'dev', name: 'Dev')],
        createdAt: 1,
      );
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: [
          const WorkspaceFolder(path: '/remote', targetId: 'ssh:host-a'),
        ],
        createdAt: 1,
        memberTargetsByTeam: {
          team.id: {'dev': 'ssh:host-a'},
        },
        memberPlacementInitializedByTeam: {team.id: true},
      );

      final block = await gate.asyncRemoteCliBlock(
        workspace: workspace,
        team: team,
        globalPresets: const [],
        selectableTargets: const [sshTarget],
        readiness: _FakeRemoteCliReadiness(alwaysReady: true),
      );
      expect(block, isNull);
    });

    test('blocks when a required remote CLI is missing', () async {
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        cli: CliTool.codex,
        members: const [TeamMemberConfig(id: 'dev', name: 'Dev')],
        createdAt: 1,
      );
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: [
          const WorkspaceFolder(path: '/remote', targetId: 'ssh:host-a'),
        ],
        createdAt: 1,
        memberTargetsByTeam: {
          team.id: {'dev': 'ssh:host-a'},
        },
        memberPlacementInitializedByTeam: {team.id: true},
      );

      final block = await gate.asyncRemoteCliBlock(
        workspace: workspace,
        team: team,
        globalPresets: const [],
        selectableTargets: const [sshTarget],
        readiness: _FakeRemoteCliReadiness(alwaysReady: false),
      );
      expect(block, isA<RemoteCliMissingLaunchBlock>());
      final missing = (block! as RemoteCliMissingLaunchBlock).missing;
      expect(missing, hasLength(1));
      expect(missing.single.cli, CliTool.codex);
    });
  });

  group('WorkspaceLandingLaunchGate.asyncRemoteCliBlockForSimple', () {
    const sshTarget = RuntimeTarget(
      id: 'ssh:host-a',
      label: 'Remote',
      kind: RuntimeKind.ssh,
      sshProfileId: 'host-a',
    );
    final localHome = RuntimeTarget.local();

    test('blocks when remote CLI is missing on SSH project folder', () async {
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: [
          const WorkspaceFolder(path: '/remote', targetId: 'ssh:host-a'),
        ],
        createdAt: 1,
      );

      final block = await gate.asyncRemoteCliBlockForSimple(
        workspace: workspace,
        draft: const LandingLaunchContext(isPersonal: true),
        projectFolderPath: '/remote',
        globalPresets: const [],
        selectableTargets: const [sshTarget],
        readiness: _FakeRemoteCliReadiness(alwaysReady: false),
        home: localHome,
      );

      expect(block, isA<RemoteCliMissingLaunchBlock>());
    });

    test('allows when remote CLI is ready', () async {
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: [
          const WorkspaceFolder(path: '/remote', targetId: 'ssh:host-a'),
        ],
        createdAt: 1,
      );

      final block = await gate.asyncRemoteCliBlockForSimple(
        workspace: workspace,
        draft: const LandingLaunchContext(isPersonal: true),
        projectFolderPath: '/remote',
        globalPresets: const [],
        selectableTargets: const [sshTarget],
        readiness: _FakeRemoteCliReadiness(alwaysReady: true),
        home: localHome,
      );

      expect(block, isNull);
    });

    test('probes an adapter requirement when the draft requested ACP', () async {
      final probed = <(String, CliBinaryKind)>[];
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: [
          const WorkspaceFolder(path: '/remote', targetId: 'ssh:host-a'),
        ],
        createdAt: 1,
      );

      final block = await gate.asyncRemoteCliBlockForSimple(
        workspace: workspace,
        draft: const LandingLaunchContext(
          isPersonal: true,
          acp: true,
          cli: CliTool.claude,
        ),
        projectFolderPath: '/remote',
        globalPresets: const [],
        selectableTargets: const [sshTarget],
        readiness: _FakeRemoteCliReadiness(
          onProbe: (target, cli, kind) async {
            probed.add((cli.value, kind));
            if (kind == CliBinaryKind.adapter) {
              return RemoteCliMissing(targetId: target.id, cli: cli);
            }
            return RemoteCliReady(
              targetId: target.id,
              cli: cli,
              path: '/home/u/.local/bin/claude',
            );
          },
        ),
        home: localHome,
      );

      expect(probed, [
        ('claude', CliBinaryKind.cli),
        ('claude', CliBinaryKind.adapter),
      ]);
      expect(block, isA<RemoteCliMissingLaunchBlock>());
      expect(
        (block! as RemoteCliMissingLaunchBlock).missing.single.kind,
        CliBinaryKind.adapter,
      );
    });
  });

  group('WorkspaceLandingLaunchGate.localBlock', () {
    WorkspaceLandingLaunchGate gateWithKnown(
      Set<String> known, {
      MemberAcpSeed? acpSeed,
    }) {
      return WorkspaceLandingLaunchGate(
        storage: HomeStorage.forTesting(
          filesystem: InMemoryFilesystem(),
          paths: AppPaths('/test-home'),
        ),
        teamConfigValidator: _AlwaysValidTeamConfigValidator(),
        homeTargetResolver: RuntimeTarget.local,
        localBinaryKnown: (cli, kind) =>
            known.contains('${kind.name}|${cli.value}'),
        localMemberAcpSeed: acpSeed,
      );
    }

    Workspace localWorkspace() => Workspace(
      workspaceId: 'ws-1',
      folders: const [WorkspaceFolder(path: '/local', targetId: 'local')],
      createdAt: 1,
    );

    test('blocks a personal draft when the local CLI is unknown', () {
      final block = gateWithKnown({}).localBlock(
        workspace: localWorkspace(),
        draft: const LandingLaunchContext(
          isPersonal: true,
          cli: CliTool.codex,
          projectFolderPath: '/local',
        ),
      );

      expect(block, isA<LocalCliMissingLaunchBlock>());
      expect(block!.missing.single.cli, CliTool.codex);
      expect(block.missing.single.kind, CliBinaryKind.cli);
    });

    test('allows when the local CLI is known', () {
      final block = gateWithKnown({'cli|codex'}).localBlock(
        workspace: localWorkspace(),
        draft: const LandingLaunchContext(
          isPersonal: true,
          cli: CliTool.codex,
          projectFolderPath: '/local',
        ),
      );

      expect(block, isNull);
    });

    test('requires the ACP adapter for a personal ACP launch', () {
      final block = gateWithKnown({'cli|claude'}).localBlock(
        workspace: localWorkspace(),
        draft: const LandingLaunchContext(
          isPersonal: true,
          cli: CliTool.claude,
          projectFolderPath: '/local',
          acp: true,
        ),
      );

      expect(block, isA<LocalCliMissingLaunchBlock>());
      expect(block!.missing.single.cli, CliTool.claude);
      expect(block.missing.single.kind, CliBinaryKind.adapter);
    });

    test('ignores folders that live on an SSH host', () {
      final block = gateWithKnown({}).localBlock(
        workspace: Workspace(
          workspaceId: 'ws-1',
          folders: [
            const WorkspaceFolder(path: '/remote', targetId: 'ssh:host-a'),
          ],
          createdAt: 1,
        ),
        draft: const LandingLaunchContext(
          isPersonal: true,
          cli: CliTool.codex,
          projectFolderPath: '/remote',
        ),
      );

      expect(block, isNull);
    });

    test('blocks team members placed on the local host', () {
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        cli: CliTool.codex,
        members: const [TeamMemberConfig(id: 'dev', name: 'Dev')],
        createdAt: 1,
      );
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: [
          const WorkspaceFolder(path: '/local', targetId: 'local'),
        ],
        createdAt: 1,
        memberTargetsByTeam: {
          team.id: {'dev': 'local'},
        },
        memberPlacementInitializedByTeam: {team.id: true},
      );

      final block = gateWithKnown({}).localBlock(
        workspace: workspace,
        draft: LandingLaunchContext(isPersonal: false, teamId: team.id),
        team: team,
      );

      expect(block, isA<LocalCliMissingLaunchBlock>());
      expect(block!.missing.single.cli, CliTool.codex);
    });

    test('adds the ACP adapter for a mixed-team local member', () {
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
        members: const [TeamMemberConfig(id: 'dev', name: 'Dev')],
        createdAt: 1,
      );
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: [
          const WorkspaceFolder(path: '/local', targetId: 'local'),
        ],
        createdAt: 1,
        memberTargetsByTeam: {
          team.id: {'dev': 'local'},
        },
        memberPlacementInitializedByTeam: {team.id: true},
      );

      final block = gateWithKnown(
        {'cli|claude'},
        acpSeed: (_) => true,
      ).localBlock(
        workspace: workspace,
        draft: LandingLaunchContext(isPersonal: false, teamId: team.id),
        team: team,
      );

      expect(block, isA<LocalCliMissingLaunchBlock>());
      expect(block!.missing.single.cli, CliTool.claude);
      expect(block.missing.single.kind, CliBinaryKind.adapter);
    });

    test('native teams never require the ACP adapter', () {
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        cli: CliTool.claude,
        members: const [TeamMemberConfig(id: 'dev', name: 'Dev')],
        createdAt: 1,
      );
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: [
          const WorkspaceFolder(path: '/local', targetId: 'local'),
        ],
        createdAt: 1,
        memberTargetsByTeam: {
          team.id: {'dev': 'local'},
        },
        memberPlacementInitializedByTeam: {team.id: true},
      );

      final block = gateWithKnown(
        {'cli|claude'},
        acpSeed: (_) => true,
      ).localBlock(
        workspace: workspace,
        draft: LandingLaunchContext(isPersonal: false, teamId: team.id),
        team: team,
      );

      expect(block, isNull);
    });

    test('syncBlock surfaces the local block for personal drafts', () {
      final block = gateWithKnown({}).syncBlock(
        workspace: localWorkspace(),
        draft: const LandingLaunchContext(
          isPersonal: true,
          cli: CliTool.codex,
          projectFolderPath: '/local',
        ),
      );

      expect(block, isA<LocalCliMissingLaunchBlock>());
    });

    test('stays disabled when no local probe is injected', () {
      final block = gate.syncBlock(
        workspace: localWorkspace(),
        draft: const LandingLaunchContext(
          isPersonal: true,
          cli: CliTool.codex,
          projectFolderPath: '/local',
        ),
      );

      expect(block, isNull);
    });
  });
}

Workspace _mixedWorkspace() {
  return Workspace(
    workspaceId: 'ws-1',
    folders: [
      const WorkspaceFolder(path: '/a', targetId: 'local'),
      const WorkspaceFolder(path: '/b', targetId: 'ssh:host-a'),
    ],
    createdAt: 1,
  );
}

TeamProfile _team() {
  return TeamProfile(
    id: 'team-1',
    name: 'Team',
    roster: TeamMemberNaming.defaultRoster(),
    members: const [
      TeamMemberConfig(id: 'team-lead', name: 'Team Lead'),
      TeamMemberConfig(id: 'developer', name: 'Developer'),
      TeamMemberConfig(id: 'reviewer', name: 'Reviewer'),
    ],
    createdAt: 1,
  );
}

TeamProfile _singleMemberTeam() {
  return TeamProfile(
    id: 'team-1',
    name: 'Team',
    members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
    createdAt: 1,
  );
}

class _AlwaysValidTeamConfigValidator extends TeamConfigLaunchValidator {
  _AlwaysValidTeamConfigValidator() : super(storage: fakeHomeStorage());

  @override
  Future<TeamConfigValidation> validate(
    TeamProfile team, {
    List<CliPreset> globalPresets = const [],
  }) async {
    return TeamConfigValidation(
      teamId: team.id,
      teamName: team.name,
      mode: team.teamMode,
      issues: const [],
    );
  }
}

class _FakeRemoteCliReadiness extends RemoteCliReadinessService {
  _FakeRemoteCliReadiness({this.alwaysReady = false, this.onProbe})
    : super(
        registry: CliToolRegistry.builtIn(),
        sshClientFactory: _ThrowingSshClientFactory(),
        profileById: (_) => null,
        cliPathOverride: (_, __) async => null,
        setCliPathOverride: (_, __, ___) async {},
      );

  final bool alwaysReady;
  final Future<RemoteCliReadiness> Function(
    RuntimeTarget target,
    CliTool cli,
    CliBinaryKind kind,
  )?
  onProbe;

  @override
  Future<RemoteCliReadiness> probe({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
  }) async {
    final custom = onProbe;
    if (custom != null) return custom(target, cli, kind);
    if (alwaysReady) {
      return RemoteCliReady(
        targetId: target.id,
        cli: cli,
        path: '/bin/${cli.value}',
      );
    }
    return RemoteCliMissing(targetId: target.id, cli: cli);
  }
}

class _ThrowingSshClientFactory implements SshClientFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
