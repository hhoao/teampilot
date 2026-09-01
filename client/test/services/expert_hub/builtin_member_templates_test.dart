import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';

void main() {
  test('builtin catalog keeps default trio and Superpowers quartet only', () {
    final keys = builtinExpertMembers().map((m) => m.key).toSet();
    expect(
      keys,
      {
        kBuiltinDefaultExpertKey,
        kBuiltinTeamBuilderExpertKey,
        'teampilot/builtin/team-lead',
        'teampilot/builtin/developer',
        'teampilot/builtin/reviewer',
        'teampilot/builtin/superpowers-lead',
        'teampilot/builtin/superpowers-architect',
        'teampilot/builtin/superpowers-builder',
        'teampilot/builtin/superpowers-reviewer',
      },
    );
  });

  test('role experts ship Superpowers skillDeps matching their playbooks', () {
    final byKey = {for (final m in builtinExpertMembers()) m.key: m};

    expect(
      byKey[kBuiltinDefaultExpertKey]!.skillDeps.map((d) => d.name),
      contains('Using Superpowers'),
    );

    expect(
      byKey['teampilot/builtin/developer']!.skillDeps.map((d) => d.name),
      containsAll(['Test-Driven Development', 'Executing Plans']),
    );
    expect(
      byKey['teampilot/builtin/reviewer']!.skillDeps.map((d) => d.name),
      containsAll([
        'Requesting Code Review',
        'Verification Before Completion',
      ]),
    );

    expect(
      byKey['teampilot/builtin/superpowers-architect']!.skillDeps
          .map((d) => d.name),
      containsAll(['Brainstorming', 'Writing Plans']),
    );
    expect(
      byKey['teampilot/builtin/superpowers-builder']!.skillDeps
          .map((d) => d.name),
      containsAll([
        'Executing Plans',
        'Test-Driven Development',
        'Dispatching Parallel Agents',
      ]),
    );
    expect(
      byKey['teampilot/builtin/superpowers-reviewer']!.skillDeps
          .map((d) => d.name),
      containsAll([
        'Requesting Code Review',
        'Verification Before Completion',
      ]),
    );
  });

  test('builtin skillDeps use obra/superpowers portable refs', () {
    for (final member in builtinExpertMembers()) {
      for (final dep in member.skillDeps) {
        if (member.key == kBuiltinTeamBuilderExpertKey) continue;
        expect(dep.repoOwner, 'obra');
        expect(dep.repoName, 'superpowers');
        expect(dep.directory, startsWith('skills/'));
        expect(dep.expectedLocalId, startsWith('obra/superpowers:'));
      }
    }
  });

  test('Team Builder uses its managed skill identity', () {
    final builder = builtinExpertMembers().firstWhere(
      (member) => member.key == kBuiltinTeamBuilderExpertKey,
    );

    expect(builder.skillDeps, hasLength(1));
    final dependency = builder.skillDeps.single;
    expect(dependency.expectedLocalId, kManagedTeamBuilderSkillId);
    expect(dependency.repoOwner, isEmpty);
    expect(dependency.repoName, isEmpty);
    expect(dependency.repoBranch, isEmpty);
    expect(dependency.directory, isEmpty);
  });

  test('default expert retains the Superpowers catalog identity', () {
    final defaultExpert = builtinExpertMembers().firstWhere(
      (member) => member.key == kBuiltinDefaultExpertKey,
    );

    expect(
      defaultExpert.skillDeps.single.expectedLocalId,
      'obra/superpowers:using-superpowers',
    );
  });
}
