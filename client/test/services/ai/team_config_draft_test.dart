import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/team_config_draft.dart';

void main() {
  const allowed = TeamDraftAllowedOptions(
    models: ['sonnet', 'opus'],
    efforts: ['low', 'high'],
    skillIds: ['code-review', 'testing'],
    defaultModel: 'sonnet',
  );

  test('parses members, clamping invalid model and effort', () {
    const json = '''
{
  "teamName": "Frontend",
  "mode": "native",
  "members": [
    {"name": "Lead Dev", "role": "lead", "model": "opus", "effort": "high"},
    {"name": "Bad One", "role": "dev", "model": "ghost-model", "effort": "ultra"}
  ],
  "skillIds": ["code-review", "unknown-skill"]
}
''';
    final draft = parseTeamConfigDraft(
      json,
      allowed: allowed,
      granularity: TeamGenGranularity.fullTeam,
      joinedAt: 100,
    );

    expect(draft.teamName, 'Frontend');
    expect(draft.mode, TeamMode.native);
    expect(draft.members, hasLength(2));
    expect(draft.members[0].model, 'opus');
    expect(draft.members[0].effort, 'high');
    // invalid model clamps to default, invalid effort clears
    expect(draft.members[1].model, 'sonnet');
    expect(draft.members[1].effort, '');
    // unknown skill dropped
    expect(draft.skillIds, ['code-review']);
  });

  test('roster-only ignores team name, mode, and skills', () {
    const json = '{"teamName":"X","members":[{"name":"Dev","role":"dev"}]}';
    final draft = parseTeamConfigDraft(
      json,
      allowed: allowed,
      granularity: TeamGenGranularity.rosterOnly,
      joinedAt: 1,
    );
    expect(draft.teamName, isNull);
    expect(draft.mode, isNull);
    expect(draft.skillIds, isEmpty);
    expect(draft.members.single.name, 'Dev');
  });

  test('skips members without a name', () {
    const json = '{"members":[{"role":"dev"},{"name":"Ok","role":"dev"}]}';
    final draft = parseTeamConfigDraft(
      json,
      allowed: allowed,
      granularity: TeamGenGranularity.rosterOnly,
      joinedAt: 1,
    );
    expect(draft.members.single.name, 'Ok');
  });

  test('throws TeamDraftFormatException on non-JSON', () {
    expect(
      () => parseTeamConfigDraft(
        'not json',
        allowed: allowed,
        granularity: TeamGenGranularity.rosterOnly,
        joinedAt: 1,
      ),
      throwsA(isA<TeamDraftFormatException>()),
    );
  });
}
