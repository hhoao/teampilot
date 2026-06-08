import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai/team_config_draft.dart';
import 'package:teampilot/services/ai/team_config_prompt.dart';

void main() {
  const allowed = TeamDraftAllowedOptions(
    models: ['sonnet', 'opus'],
    efforts: ['low', 'high'],
    skillIds: ['code-review'],
    defaultModel: 'sonnet',
  );

  test('roster prompt lists allowed models/efforts and the description', () {
    final p = buildTeamConfigPrompt(
      description: 'Flutter frontend team',
      allowed: allowed,
      granularity: TeamGenGranularity.rosterOnly,
    );
    expect(p, contains('Flutter frontend team'));
    expect(p, contains('sonnet'));
    expect(p, contains('high'));
    expect(p, contains('"members"'));
    // roster-only must not ask for team-level fields
    expect(p.contains('"skillIds"'), isFalse);
  });

  test('full prompt asks for team name, mode and skills', () {
    final p = buildTeamConfigPrompt(
      description: 'x',
      allowed: allowed,
      granularity: TeamGenGranularity.fullTeam,
    );
    expect(p, contains('"teamName"'));
    expect(p, contains('"mode"'));
    expect(p, contains('"skillIds"'));
    expect(p, contains('code-review'));
  });
}
