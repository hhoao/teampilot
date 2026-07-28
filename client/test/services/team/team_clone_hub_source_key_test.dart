import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/services/team/team_clone_service.dart';

void main() {
  test('clone passes DiscoverableTeam.key as hubSourceKey to createTeam', () async {
    String? seenHubSourceKey;
    final service = TeamCloneService(
      installSkill: (_) async => null,
      installPlugin: (_) async => null,
      installMcp: (_) async => null,
      createTeam: ({
        required name,
        required cli,
        required teamMode,
        required roster,
        required skillIds,
        required pluginIds,
        required mcpServerIds,
        required description,
        required extraArgs,
        String? hubSourceKey,
      }) async {
        seenHubSourceKey = hubSourceKey;
        return 'local-1';
      },
    );

    const team = DiscoverableTeam(
      key: 'owner/repo/demo',
      name: 'Demo',
      description: '',
      category: 'general',
      updatedAt: 1,
    );

    final result = await service.clone(team);
    expect(result.teamId, 'local-1');
    expect(seenHubSourceKey, 'owner/repo/demo');
  });
}
