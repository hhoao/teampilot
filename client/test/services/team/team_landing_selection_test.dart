import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/team_clone_service.dart';
import 'package:teampilot/services/team/team_landing_selection.dart';

DiscoverableTeam hub(String key) => DiscoverableTeam(
  key: key,
  name: 'Hub',
  description: '',
  category: 'general',
  updatedAt: 1,
);

void main() {
  test('resolveLocal returns id and touches recent', () async {
    final touched = <String>[];
    final selection = TeamLandingSelection(
      cloneTeam: (_) async => throw StateError('should not clone'),
      touchRecent: (id) async => touched.add(id),
    );
    final teams = [
      const TeamProfile(id: 'a', name: 'A'),
      const TeamProfile(id: 'b', name: 'B'),
    ];
    final ok = await selection.resolveLocal(teamId: 'b', teams: teams);
    expect(ok.teamId, 'b');
    expect(ok.cloneResult, isNull);
    expect(touched, ['b']);
  });

  test('resolveLocal throws when team missing', () async {
    final selection = TeamLandingSelection(
      cloneTeam: (_) async => throw StateError('no'),
      touchRecent: (_) async {},
    );
    expect(
      () => selection.resolveLocal(teamId: 'missing', teams: const []),
      throwsA(isA<TeamLandingSelectionException>()),
    );
  });

  test('resolveHub reuses earliest hubSourceKey match without cloning', () async {
    var clones = 0;
    final selection = TeamLandingSelection(
      cloneTeam: (_) async {
        clones++;
        return const CloneResult(
          teamId: 'new',
          installed: CloneDepInstallSummary(),
          failedDeps: [],
        );
      },
      touchRecent: (_) async {},
    );
    final teams = [
      const TeamProfile(
        id: 'newer',
        name: 'N',
        hubSourceKey: 'o/r/s',
        createdAt: 200,
        sortOrder: 0,
      ),
      const TeamProfile(
        id: 'older',
        name: 'O',
        hubSourceKey: 'o/r/s',
        createdAt: 100,
        sortOrder: 0,
      ),
    ];
    final ok = await selection.resolveHub(team: hub('o/r/s'), teams: teams);
    expect(ok.teamId, 'older');
    expect(ok.cloneResult, isNull);
    expect(clones, 0);
  });

  test('resolveHub clones when no match and touches new id', () async {
    final touched = <String>[];
    final selection = TeamLandingSelection(
      cloneTeam: (t) async => CloneResult(
        teamId: 'cloned-${t.key}',
        installed: const CloneDepInstallSummary(),
        failedDeps: const [],
      ),
      touchRecent: (id) async => touched.add(id),
    );
    final ok = await selection.resolveHub(
      team: hub('o/r/s'),
      teams: const [TeamProfile(id: 'other', name: 'X')],
    );
    expect(ok.teamId, 'cloned-o/r/s');
    expect(ok.cloneResult, isNotNull);
    expect(touched, ['cloned-o/r/s']);
  });
}
