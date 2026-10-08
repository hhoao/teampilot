import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/expert_hub/expert_hub_catalog.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/chat/launch/config_profile_service.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';

import '../support/post_frame_test_harness.dart';

String _testExecutable() => 'flashskyai';

/// Offline source returning only the built-in experts so roster slots
/// (`teampilot/builtin/*`) materialize without touching the network.
class _BuiltinExpertSource implements ExpertHubSource {
  @override
  Future<List<DiscoverableMember>> fetchMembers({
    bool forceRefresh = false,
  }) async => builtinExpertMembers();

  @override
  Future<List<String>> categories({bool forceRefresh = false}) async =>
      const [];
}

void main() {
  // This group binds its own AppStorage-backed home (no per-test rootDirs), so
  // the migrated constructors need the harness storage rather than a bare
  // fallback.
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('team cubit manages teams', () async {
    final tmp = await Directory.systemTemp.createTemp('teams_cubit_');
    final appData = await Directory.systemTemp.createTemp('teams_cubit_app_');
    addTearDown(() => deleteTempDirBestEffort(tmp));
    addTearDown(() => deleteTempDirBestEffort(appData));
    final repository = testLaunchProfileRepository(tmp);
    final cubit = LaunchProfileCubit(
      repository: repository,
      sessionRepository: SessionRepository(storage: testHomeStorage),
      storage: testHomeStorage,
      executableResolver: _testExecutable,
      appDataBasePath: appData.path,
      configProfileService: ConfigProfileService(
        basePath: appData.path,
        storage: testHomeStorage,
      ),
    );
    cubit.attachCatalog(ExpertHubCatalog(source: _BuiltinExpertSource()));
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
