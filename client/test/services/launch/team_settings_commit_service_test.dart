import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/team/model/launch_profile_state.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_topology.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/launch/member_placement_save.dart';
import 'package:teampilot/services/launch/team_settings_commit_service.dart';

import '../../support/post_frame_test_harness.dart';

TeamProfile _team() {
  final members = [
    TeamMemberConfig(id: 'team-lead', name: 'Lead'),
    TeamMemberConfig(id: 'worker', name: 'Worker'),
  ];
  return TeamProfile(
    id: 'team-1',
    name: 'Alpha',
    members: members,
    roster: [
      TeamRosterSlot(
        id: 'team-lead',
        expertKey: 'teampilot/builtin/team-lead',
        joinedAt: 1,
      ),
      TeamRosterSlot(
        id: 'worker',
        expertKey: 'teampilot/builtin/developer',
        joinedAt: 1,
      ),
    ],
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('commit persists profile + placement and patches the chat snapshot',
      () async {
    final launch = LaunchProfileCubit(
      repository: testLaunchProfileRepository(
        Directory.systemTemp.createTempSync('commit_svc_'),
      ),
      sessionRepository: SessionRepository(),
      executableResolver: () => 'claude',
    );
    addTearDown(launch.close);
    final team = _team();
    launch.applyState(
      LaunchProfileState(
        isLoading: false,
        identities: [team],
        selectedTeamId: team.id,
      ),
    );

    final repo = SessionRepository();
    final workspace = await repo.createWorkspace(
      const [WorkspaceFolder(path: '/repo')],
      display: 'ws-1',
    );
    final chat = testChatCubit(
      executableResolver: () => 'claude',
      sessionRepository: repo,
    );
    addTearDown(chat.close);
    chat.ingestWorkspaceSessionSnapshot(
      workspaces: [workspace],
      sessions: const [],
    );

    final placement = defaultMemberPlacement(
      folders: workspace.folders,
      members: team.members,
    );
    final prepared = prepareMemberPlacementSave(
      team: team,
      folders: workspace.folders,
      placement: placement,
    );
    expect(prepared.leadValid, isTrue);

    final service = TeamSettingsCommitService(
      launchProfileCubit: launch,
      sessionRepository: repo,
      chatCubit: chat,
    );
    final ok = await service.commit(
      workspaceId: workspace.workspaceId,
      teamId: team.id,
      prepared: prepared,
    );
    expect(ok, isTrue);

    // Snapshot patched in memory (no reload needed).
    final patched = chat.state.workspaces.single;
    expect(patched.workspaceId, workspace.workspaceId);
    expect(patched.memberTargetsByTeam[team.id], prepared.targets);
    expect(patched.memberPlacementInitializedByTeam[team.id], isTrue);

    // Placement persisted to the workspace manifest on disk.
    final fromDisk = await repo.loadWorkspaces();
    final diskWorkspace = fromDisk.single;
    expect(diskWorkspace.memberTargetsByTeam[team.id], prepared.targets);

    // Roster replicas persisted through the launch profile.
    final saved = launch.state.teams.singleWhere((t) => t.id == team.id);
    expect(saved.roster, prepared.team.roster);
  });

  test('commit returns false and persists nothing when lead placement invalid',
      () async {
    final launch = LaunchProfileCubit(
      repository: testLaunchProfileRepository(
        Directory.systemTemp.createTempSync('commit_svc_invalid_'),
      ),
      sessionRepository: SessionRepository(),
      executableResolver: () => 'claude',
    );
    addTearDown(launch.close);
    final team = _team();
    launch.applyState(
      LaunchProfileState(
        isLoading: false,
        identities: [team],
        selectedTeamId: team.id,
      ),
    );

    final repo = SessionRepository();
    final workspace = await repo.createWorkspace(
      const [WorkspaceFolder(path: '/repo')],
      display: 'ws-1',
    );
    final chat = testChatCubit(
      executableResolver: () => 'claude',
      sessionRepository: repo,
    );
    addTearDown(chat.close);
    chat.ingestWorkspaceSessionSnapshot(
      workspaces: [workspace],
      sessions: const [],
    );

    // Lead pinned to a target that is not backed by any folder → invalid.
    final placement = <String, Map<String, int>>{
      'ssh-ghost': {'team-lead': 1, 'worker': 1},
    };
    final prepared = prepareMemberPlacementSave(
      team: team,
      folders: workspace.folders,
      placement: placement,
    );
    expect(prepared.leadValid, isFalse);

    final service = TeamSettingsCommitService(
      launchProfileCubit: launch,
      sessionRepository: repo,
      chatCubit: chat,
    );
    final ok = await service.commit(
      workspaceId: workspace.workspaceId,
      teamId: team.id,
      prepared: prepared,
    );
    expect(ok, isFalse);

    // Nothing persisted: no workspace manifest change, no profile save.
    final fromDisk = await repo.loadWorkspaces();
    expect(fromDisk.single.memberTargetsByTeam, isEmpty);
    final saved = launch.state.teams.singleWhere((t) => t.id == team.id);
    expect(saved.roster, team.roster);
  });
}
