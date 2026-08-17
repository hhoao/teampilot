import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_hub/git_registry_team_hub_source.dart';
import 'package:teampilot/services/team_hub/team_hub_source.dart';

void main() {
  test(
    'reports a safe source failure when the registry index is unavailable',
    () async {
      final source = GitRegistryTeamHubSource(fetch: (_) async => null);

      final results = await (source as TeamHubSourceContributions)
          .fetchTeamSources();

      expect(results.single.items, isEmpty);
      expect(results.single.failure, isNotNull);
      expect(results.single.failure!.sourceId, 'team-registry');
      expect(results.single.failure!.message, isNot(contains('response body')));
    },
  );
}
