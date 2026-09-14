import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_generation/models/generated_team_plan.dart';

Map<String, Object?> validPlanJson({
  int replicas = 1,
  String? memberPreset = 'claude-strong',
  Map<String, int>? placement,
}) =>
    {
      'schemaVersion': 1,
      'team': {
        'name': 'Delivery Team',
        'description': 'Ships the request',
        'mode': 'mixed',
      },
      'members': [
        {
          'name': 'team-lead',
          'role': 'Delivery Lead',
          'responsibilities': 'Own decomposition and integration',
          'workingMethod': 'Delegate, review evidence, integrate',
          if (memberPreset != null) 'presetId': memberPreset,
          'replicas': replicas,
          if (placement != null) 'placement': placement,
        },
        {
          'name': 'worker',
          'role': 'Worker',
          'responsibilities': 'Implements tasks',
          'workingMethod': 'Test-first small diffs',
          'presetId': 'codex-fast',
          'replicas': 1,
        },
      ],
      'resources': {
        'skillIds': ['existing/skill'],
        'pluginIds': <String>[],
        'mcpServerIds': ['existing-mcp'],
      },
    };

void main() {
  group('parser', () {
    test('accepts the canonical mixed plan', () {
      final plan = GeneratedTeamPlan.fromJson(validPlanJson());
      expect(plan.teamName, 'Delivery Team');
      expect(plan.members, hasLength(2));
      expect(plan.members.first.name, 'team-lead');
      expect(plan.skillIds, ['existing/skill']);
      expect(plan.hasLead, isTrue);
    });

    test('accepts plans with more than five members', () {
      final plan = GeneratedTeamPlan.fromJson({
        ...validPlanJson(),
        'members': [
          ...(validPlanJson()['members'] as List),
          {
            'name': 'reviewer',
            'role': 'Reviewer',
            'responsibilities': 'Reviews the implementation',
            'workingMethod': 'Review diffs and report risks',
            'presetId': 'codex-fast',
            'replicas': 1,
          },
          {
            'name': 'tester',
            'role': 'Tester',
            'responsibilities': 'Validates behavior',
            'workingMethod': 'Run focused regression tests',
            'presetId': 'codex-fast',
            'replicas': 1,
          },
          {
            'name': 'documenter',
            'role': 'Documenter',
            'responsibilities': 'Documents the delivered change',
            'workingMethod': 'Summarize verified behavior',
            'presetId': 'codex-fast',
            'replicas': 1,
          },
          {
            'name': 'release-manager',
            'role': 'Release Manager',
            'responsibilities': 'Coordinates release readiness',
            'workingMethod': 'Review evidence and hand off',
            'presetId': 'codex-fast',
            'replicas': 1,
          },
        ],
      });

      expect(plan.members, hasLength(6));
    });

    test('wire schema leaves member count unbounded', () {
      expect(GeneratedTeamPlan.wireSchema, isNot(contains('memberCount')));
    });

    test('strict parser rejects unknown keys and non-integer replica counts',
        () {
      expect(
        () => GeneratedTeamPlan.fromJson({
          ...validPlanJson(),
          'provider': 'secret',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => GeneratedTeamPlan.fromJson({
          ...validPlanJson(),
          'members': [
            {
              ...(validPlanJson()['members'] as List).first as Map,
              'replicas': 1.5,
            },
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects replicas out of range', () {
      final members = [
        for (final raw in (validPlanJson()['members'] as List))
          Map<String, Object?>.from(raw as Map),
      ];
      members[0]['replicas'] = 9;
      expect(
        () => GeneratedTeamPlan.fromJson({
          ...validPlanJson(),
          'members': members,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects missing required text fields', () {
      final members = [
        for (final raw in (validPlanJson()['members'] as List))
          Map<String, Object?>.from(raw as Map),
      ];
      members[0]['role'] = '';
      expect(
        () => GeneratedTeamPlan.fromJson({
          ...validPlanJson(),
          'members': members,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('canonical revision ignores map insertion order', () {
      final a = GeneratedTeamPlan.fromJson(validPlanJson());
      final resources = (validPlanJson()['resources'] as Map).cast<String, Object?>();
      final reordered = validPlanJson();
      reordered['resources'] = {
        'mcpServerIds': resources['mcpServerIds'],
        'skillIds': resources['skillIds'],
        'pluginIds': resources['pluginIds'],
      };
      final b = GeneratedTeamPlan.fromJson(reordered);
      expect(a.computeRevision(), b.computeRevision());
    });

    test('missing presetId is allowed (inherits default)', () {
      final plan = GeneratedTeamPlan.fromJson(validPlanJson(memberPreset: null));
      expect(plan.members.first.presetId, isEmpty);
    });
  });
}
