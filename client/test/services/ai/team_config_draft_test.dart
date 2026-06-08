import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai/team_config_draft.dart';
import 'package:teampilot/utils/team_member_naming.dart';

void main() {
  test('parses members + team fields; model/effort/cli left unset', () {
    const json = '''
{
  "teamName": "Frontend",
  "description": "Ship the UI.",
  "members": [
    {"name": "team-lead", "role": "coordinator",
     "responsibilities": "Coordinate. Do NOT implement.",
     "workingMethod": "Decompose, assign, synthesize."},
    {"name": "Worker", "role": "dev",
     "responsibilities": "Build it.", "workingMethod": "Test first."}
  ]
}
''';
    final draft = parseTeamConfigDraft(json, joinedAt: 100);

    expect(draft.teamName, 'Frontend');
    expect(draft.description, 'Ship the UI.');
    expect(draft.members, hasLength(2));
    final lead = draft.members.first;
    expect(lead.id, TeamMemberNaming.teamLeadName);
    expect(lead.prompt, 'Coordinate. Do NOT implement.');
    expect(lead.playbook, 'Decompose, assign, synthesize.');
    // model/effort/cli are never generated — the user configures them later.
    expect(lead.model, '');
    expect(lead.effort, '');
    expect(lead.cli, isNull);
    expect(draft.members[1].prompt, 'Build it.');
    expect(draft.members[1].cli, isNull);
  });

  test('ignores any model/effort/cli the model emits', () {
    const json = '{"members":[{"name":"team-lead"},'
        '{"name":"Dev","model":"opus","effort":"high","cli":"codex"}]}';
    final draft = parseTeamConfigDraft(json, joinedAt: 1);
    final dev = draft.members[1];
    expect(dev.model, '');
    expect(dev.effort, '');
    expect(dev.cli, isNull);
  });

  test('injects a default team-lead when none is emitted', () {
    const json = '{"members":[{"name":"Dev","role":"dev"}]}';
    final draft = parseTeamConfigDraft(json, joinedAt: 1);
    expect(draft.members.first.id, TeamMemberNaming.teamLeadName);
    expect(draft.members, hasLength(2));
  });

  test('keeps the first lead and demotes duplicate leads to workers', () {
    const json = '{"members":[{"name":"team-lead","role":"a"},'
        '{"name":"team-lead","role":"b"}]}';
    final draft = parseTeamConfigDraft(json, joinedAt: 1);
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
    final draft = parseTeamConfigDraft(json, joinedAt: 1);
    expect(
      draft.members.where((m) => m.id == TeamMemberNaming.teamLeadName),
      hasLength(1),
    );
    expect(draft.members[1].name, 'Second Lead');
    expect(draft.members[1].id, isNot(TeamMemberNaming.teamLeadName));
  });

  test('skips members without a name', () {
    const json = '{"members":[{"name":"team-lead"},{"role":"dev"},'
        '{"name":"Ok","role":"dev"}]}';
    final draft = parseTeamConfigDraft(json, joinedAt: 1);
    expect(draft.members.map((m) => m.name), contains('Ok'));
    expect(draft.members, hasLength(2));
  });

  test('throws TeamDraftFormatException on non-JSON', () {
    expect(
      () => parseTeamConfigDraft('not json', joinedAt: 1),
      throwsA(isA<TeamDraftFormatException>()),
    );
  });

  test('throws TeamDraftFormatException when JSON is not an object', () {
    expect(
      () => parseTeamConfigDraft('[]', joinedAt: 1),
      throwsA(isA<TeamDraftFormatException>()),
    );
  });
}
