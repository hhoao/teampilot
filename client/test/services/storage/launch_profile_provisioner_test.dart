import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  late LaunchProfileRepository repo;
  late LaunchProfileProvisioner provisioner;

  setUp(() async {
    setUpTestAppStorage();
    repo = LaunchProfileRepository();
    provisioner = LaunchProfileProvisioner(repository: repo);
  });

  tearDown(() async {
    tearDownTestAppStorage();
  });

  test('ensureDefaultTeams is idempotent', () async {
    final first = await provisioner.ensureDefaultTeams(
      buildNative: () => TeamProfile(
        id: LaunchProfileProvisioner.defaultNativeTeamId,
        name: 'Native',
      ),
      buildMixed: () => TeamProfile(
        id: LaunchProfileProvisioner.defaultMixedTeamId,
        name: 'Mixed',
        teamMode: TeamMode.mixed,
      ),
    );
    final second = await provisioner.ensureDefaultTeams(
      buildNative: () => throw StateError('should not rebuild native'),
      buildMixed: () => throw StateError('should not rebuild mixed'),
    );
    expect(first.native.id, LaunchProfileProvisioner.defaultNativeTeamId);
    expect(first.mixed.id, LaunchProfileProvisioner.defaultMixedTeamId);
    expect(second.native.id, first.native.id);
    expect(second.mixed.id, first.mixed.id);
  });
}
