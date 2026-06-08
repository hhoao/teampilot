import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/team_config_draft.dart';
import 'package:teampilot/utils/team_member_naming.dart';

void main() {
  const native = TeamDraftAllowedOptions(
    clis: [
      CliModelOptions(
        cli: CliTool.claude,
        models: ['sonnet', 'opus'],
        efforts: ['low', 'high'],
        defaultModel: 'sonnet',
      ),
    ],
    skillIds: ['code-review', 'testing'],
  );

  const mixed = TeamDraftAllowedOptions(
    clis: [
      CliModelOptions(
        cli: CliTool.claude,
        models: ['sonnet', 'opus'],
        efforts: ['low', 'high'],
        defaultModel: 'sonnet',
      ),
      CliModelOptions(
        cli: CliTool.codex,
        models: ['gpt-x'],
        efforts: ['medium'],
        defaultModel: 'gpt-x',
      ),
    ],
    skillIds: ['code-review'],
  );

  test('parses rich members and team fields, clamping invalid values', () {
    const json = '''
{
  "teamName": "Frontend",
  "description": "Ship the UI.",
  "members": [
    {"name": "team-lead", "role": "coordinator", "model": "opus", "effort": "high",
     "responsibilities": "Coordinate. Do NOT implement.",
     "workingMethod": "Decompose, assign, synthesize."},
    {"name": "Bad One", "role": "dev", "model": "ghost", "effort": "ultra",
     "responsibilities": "Build it.", "workingMethod": "Test first."}
  ],
  "skillIds": ["code-review", "unknown-skill"]
}
''';
    final draft = parseTeamConfigDraft(
      json,
      allowed: native,
      mode: TeamMode.native,
      joinedAt: 100,
    );

    expect(draft.teamName, 'Frontend');
    expect(draft.description, 'Ship the UI.');
    expect(draft.members, hasLength(2));
    final lead = draft.members.first;
    expect(lead.id, TeamMemberNaming.teamLeadName);
    expect(lead.model, 'opus');
    expect(lead.effort, 'high');
    expect(lead.prompt, 'Coordinate. Do NOT implement.');
    expect(lead.playbook, 'Decompose, assign, synthesize.');
    expect(draft.members[1].model, 'sonnet');
    expect(draft.members[1].effort, '');
    expect(draft.members[1].prompt, 'Build it.');
    expect(draft.skillIds, ['code-review']);
  });

  test('native ignores any per-member cli', () {
    const json = '{"members":[{"name":"team-lead"},'
        '{"name":"Dev","cli":"codex","model":"sonnet"}]}';
    final draft = parseTeamConfigDraft(
      json,
      allowed: native,
      mode: TeamMode.native,
      joinedAt: 1,
    );
    expect(draft.members[1].cli, isNull);
  });

  test('mixed clamps cli and resolves model/effort against that cli', () {
    const json = '{"members":[{"name":"team-lead"},'
        '{"name":"Dev","cli":"codex","model":"gpt-x","effort":"medium"},'
        '{"name":"Ghost","cli":"opencode","model":"sonnet","effort":"low"}]}';
    final draft = parseTeamConfigDraft(
      json,
      allowed: mixed,
      mode: TeamMode.mixed,
      joinedAt: 1,
    );
    final dev = draft.members[1];
    expect(dev.cli, CliTool.codex);
    expect(dev.model, 'gpt-x');
    expect(dev.effort, 'medium');
    final ghost = draft.members[2];
    expect(ghost.cli, CliTool.claude);
    expect(ghost.model, 'sonnet');
  });

  test('injects a default team-lead when none is emitted', () {
    const json = '{"members":[{"name":"Dev","role":"dev"}]}';
    final draft = parseTeamConfigDraft(
      json,
      allowed: native,
      mode: TeamMode.native,
      joinedAt: 1,
    );
    expect(draft.members.first.id, TeamMemberNaming.teamLeadName);
    expect(draft.members, hasLength(2));
  });

  test('keeps the first lead and demotes duplicate leads to workers', () {
    const json = '{"members":[{"name":"team-lead","role":"a"},'
        '{"name":"team-lead","role":"b"}]}';
    final draft = parseTeamConfigDraft(
      json,
      allowed: native,
      mode: TeamMode.native,
      joinedAt: 1,
    );
    final leads = draft.members
        .where((m) => m.id == TeamMemberNaming.teamLeadName)
        .toList();
    expect(leads, hasLength(1));
    expect(draft.members, hasLength(2));
    expect(draft.members[1].id, isNot(TeamMemberNaming.teamLeadName));
  });

  test('a non-lead member keeps its own id alongside the injected lead', () {
    const json = '{"members":[{"name":"team-lead","role":"a"},'
        '{"name":"Second Lead","role":"b"}]}';
    final draft = parseTeamConfigDraft(
      json,
      allowed: native,
      mode: TeamMode.native,
      joinedAt: 1,
    );
    // Only the first member holds the reserved lead id.
    expect(
      draft.members.where((m) => m.id == TeamMemberNaming.teamLeadName),
      hasLength(1),
    );
    expect(draft.members[1].name, 'Second Lead');
    expect(draft.members[1].id, isNot(TeamMemberNaming.teamLeadName));
  });

  test('throws TeamDraftFormatException when JSON is not an object', () {
    expect(
      () => parseTeamConfigDraft(
        '[]',
        allowed: native,
        mode: TeamMode.native,
        joinedAt: 1,
      ),
      throwsA(isA<TeamDraftFormatException>()),
    );
  });

  test('skips members without a name', () {
    const json = '{"members":[{"name":"team-lead"},{"role":"dev"},'
        '{"name":"Ok","role":"dev"}]}';
    final draft = parseTeamConfigDraft(
      json,
      allowed: native,
      mode: TeamMode.native,
      joinedAt: 1,
    );
    expect(draft.members.map((m) => m.name), contains('Ok'));
    expect(draft.members, hasLength(2));
  });

  test('throws TeamDraftFormatException on non-JSON', () {
    expect(
      () => parseTeamConfigDraft(
        'not json',
        allowed: native,
        mode: TeamMode.native,
        joinedAt: 1,
      ),
      throwsA(isA<TeamDraftFormatException>()),
    );
  });
}
