import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/expert_hub/expert_capability_pack.dart';
import 'package:teampilot/services/expert_hub/expert_capability_resolver.dart';
import 'package:teampilot/services/expert_hub/expert_landing_preflight.dart';
import 'package:teampilot/services/team/team_clone_service.dart';

void main() {
  group('resolveLandingSessionExpertKey', () {
    test('uses draft key when non-empty', () {
      expect(
        resolveLandingSessionExpertKey('teampilot/builtin/developer'),
        'teampilot/builtin/developer',
      );
      expect(
        resolveLandingSessionExpertKey('  teampilot/builtin/developer  '),
        'teampilot/builtin/developer',
      );
    });

    test('falls back to builtin default when missing or blank', () {
      expect(resolveLandingSessionExpertKey(null), kBuiltinDefaultExpertKey);
      expect(resolveLandingSessionExpertKey(''), kBuiltinDefaultExpertKey);
      expect(resolveLandingSessionExpertKey('   '), kBuiltinDefaultExpertKey);
    });
  });

  group('preflightLandingExpert', () {
    test('invokes resolver.preflight and returns pack', () async {
      final calls = <String>[];
      final resolver = _RecordingResolver(
        onPreflight: (key) async {
          calls.add(key);
          return ExpertCapabilityPack(
            member: const TeamMemberConfig(
              id: 'm1',
              name: 'Dev',
              prompt: 'p',
              joinedAt: 1,
            ),
            bundle: const ConfigBundle(skillIds: ['s1']),
            failedDeps: const [
              DependencyFailure(DependencyKind.skill, 'broken-skill'),
            ],
          );
        },
      );

      final result = await preflightLandingExpert(
        resolver: resolver,
        expertKey: 'teampilot/builtin/developer',
      );

      expect(calls, ['teampilot/builtin/developer']);
      expect(result.pack, isNotNull);
      expect(result.pack!.hasFailures, isTrue);
      expect(result.notFound, isFalse);
    });

    test('marks notFound when preflight returns null', () async {
      final resolver = _RecordingResolver(onPreflight: (_) async => null);

      final result = await preflightLandingExpert(
        resolver: resolver,
        expertKey: 'missing/expert',
      );

      expect(result.notFound, isTrue);
      expect(result.pack, isNull);
    });
  });

  group('selectLandingExpert', () {
    test('chip-select path invokes resolver.preflight', () async {
      final calls = <String>[];
      final resolver = _RecordingResolver(
        onPreflight: (key) async {
          calls.add(key);
          return ExpertCapabilityPack(
            member: const TeamMemberConfig(
              id: 'm1',
              name: 'Dev',
              prompt: 'p',
              joinedAt: 1,
            ),
            bundle: const ConfigBundle(skillIds: ['s1']),
          );
        },
      );

      final result = await selectLandingExpert(
        resolver: resolver,
        expertKey: 'teampilot/builtin/developer',
      );

      expect(calls, ['teampilot/builtin/developer']);
      expect(result.cleared, isFalse);
      expect(result.selectedKey, 'teampilot/builtin/developer');
      expect(result.preflight?.pack, isNotNull);
      expect(result.preflight?.notFound, isFalse);
    });

    test('clears selection for blank key without preflight', () async {
      var preflightCalled = false;
      final resolver = _RecordingResolver(
        onPreflight: (_) async {
          preflightCalled = true;
          return null;
        },
      );

      final result = await selectLandingExpert(
        resolver: resolver,
        expertKey: '   ',
      );

      expect(result.cleared, isTrue);
      expect(result.selectedKey, isNull);
      expect(result.preflight, isNull);
      expect(preflightCalled, isFalse);
    });
  });
}

class _RecordingResolver extends ExpertCapabilityResolver {
  _RecordingResolver({required this.onPreflight})
    : super(
        installSkill: (_) async => null,
        installPlugin: (_) async => null,
        installMcp: (_) async => null,
      );

  final Future<ExpertCapabilityPack?> Function(String key) onPreflight;

  @override
  Future<ExpertCapabilityPack?> preflight(String expertKey) =>
      onPreflight(expertKey);

  @override
  Future<ExpertCapabilityPack?> resolveKey(
    String expertKey, {void Function(String)? onDepProgress, 
    TeamRosterSlotOverrides? overrides,
    TeamProfile? team,
    String? slotId,
    int? joinedAt,
  }) => onPreflight(expertKey);
}
