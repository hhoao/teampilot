import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';

import '../support/post_frame_test_harness.dart';

String _testExecutable() => 'flashskyai';

void main() {
  test('team cubit manages teams', () async {
    final tmp = await Directory.systemTemp.createTemp('teams_cubit_');
    final appData = await Directory.systemTemp.createTemp('teams_cubit_app_');
    addTearDown(() => deleteTempDirBestEffort(tmp));
    addTearDown(() => deleteTempDirBestEffort(appData));
    final repository = testLaunchProfileRepository(tmp);
    final cubit = LaunchProfileCubit(
      repository: repository,
      sessionRepository: SessionRepository(),
      executableResolver: _testExecutable,
      appDataBasePath: appData.path,
      configProfileService: ConfigProfileService(basePath: appData.path),
    );
    await cubit.load();

    expect(cubit.state.teams.length, 2);
    expect(
      cubit.state.selectedTeam?.id,
      LaunchProfileProvisioner.defaultNativeTeamId,
    );
    expect(cubit.state.selectedTeam?.name, 'Default Native Team');
    expect(cubit.state.selectedTeam?.members.length, 3);
    expect(cubit.state.selectedTeam?.members.map((m) => m.id).toList(), [
      'team-lead',
      'developer',
      'reviewer',
    ]);

    cubit.selectTeam(LaunchProfileProvisioner.defaultMixedTeamId);
    expect(cubit.state.selectedTeam?.name, 'Default Mixed Team');

    await cubit.addExpertToTeam(
      LaunchProfileProvisioner.defaultMixedTeamId,
      'teampilot/builtin/developer',
    );
    expect(cubit.state.selectedTeam?.members.length, 4);
    expect(cubit.state.statusMessage, contains('Added'));
  });
}
