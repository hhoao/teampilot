import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/l10n/app_localizations_zh.dart';
import 'package:teampilot/models/launch_profile_kind.dart';
import 'package:teampilot/models/personal_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';
import 'package:teampilot/cubits/team/team_roster_editor.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test(
    'provisions exactly one default personal identity on empty store',
    () async {
      final tmp = await Directory.systemTemp.createTemp('identity_prov_');
      final repo = testLaunchProfileRepository(tmp);
      final provisioner = LaunchProfileProvisioner(repository: repo);

      final first = await provisioner.ensureDefaultPersonal();
      final again = await provisioner.ensureDefaultPersonal();

      expect(first.id, LaunchProfileProvisioner.defaultPersonalId);
      expect(first.kind, LaunchProfileKind.personal);
      expect(again.id, first.id);
      final all = await repo.loadAll();
      expect(all.where((e) => e.kind == LaunchProfileKind.personal).length, 1);
      await tmp.delete(recursive: true);
    },
  );

  test('provisions native and mixed built-in teams on empty store', () async {
    final tmp = await Directory.systemTemp.createTemp('identity_prov_teams_');
    final repo = testLaunchProfileRepository(tmp);
    final provisioner = LaunchProfileProvisioner(repository: repo);
    const roster = TeamRosterEditor();

    final first = await provisioner.ensureDefaultTeams(
      buildNative: roster.defaultNativeTeam,
      buildMixed: roster.defaultMixedTeam,
    );
    final again = await provisioner.ensureDefaultTeams(
      buildNative: roster.defaultNativeTeam,
      buildMixed: roster.defaultMixedTeam,
    );

    expect(first.native.id, LaunchProfileProvisioner.defaultNativeTeamId);
    expect(first.native.teamMode, TeamMode.native);
    expect(first.mixed.id, LaunchProfileProvisioner.defaultMixedTeamId);
    expect(first.mixed.teamMode, TeamMode.mixed);
    expect(again.native.id, first.native.id);
    expect(again.mixed.id, first.mixed.id);

    final all = await repo.loadAll();
    expect(all.where((e) => e.kind == LaunchProfileKind.team).length, 2);
    await tmp.delete(recursive: true);
  });
}
