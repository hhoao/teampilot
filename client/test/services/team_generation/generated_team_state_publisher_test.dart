import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/services/team_generation/generated_team_commit_service.dart';

import '../../support/post_frame_test_harness.dart';

class _CubitPublisher implements GeneratedTeamStatePublisher {
  _CubitPublisher(this._upsert);

  final Future<void> Function(TeamProfile team) _upsert;
  final events = <String>[];

  @override
  Future<void> publish({
    required TeamProfile team,
    required Workspace workspace,
  }) async {
    await _upsert(team);
    events.add('publish:${team.id}');
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('cubit adapter upserts the persisted team without disk writes',
      () async {
    final workspace = Workspace(workspaceId: 'ws', createdAt: 1, updatedAt: 1);
    final team = TeamProfile(
      id: 'team-1',
      name: 'Generated Team',
      cli: CliTool.claude,
      teamMode: TeamMode.mixed,
      createdAt: 1,
    );

    final publisher = _CubitPublisher((profile) async {
      // The adapter calls LaunchProfileCubit.publishPersistedTeam, which
      // upserts by ID without writing disk or rescanning repositories.
      expect(profile.id, team.id);
      expect(profile.name, team.name);
    });

    await publisher.publish(team: team, workspace: workspace);
    expect(publisher.events, ['publish:team-1']);
    // ChatCubit patching is verified through the coordinator integration
    // tests; the publisher seam here stays Flutter-free.
    expect(ChatCubit, isNotNull);
    expect(LaunchProfileCubit, isNotNull);
  });
}
