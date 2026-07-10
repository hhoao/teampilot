import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_route.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/expert_hub/expert_capability_pack.dart';
import 'package:teampilot/services/expert_hub/expert_capability_resolver.dart';
import 'package:teampilot/services/expert_hub/expert_landing_deep_link.dart';
import 'package:teampilot/services/expert_hub/expert_member_resolver.dart';
import 'package:teampilot/services/home_workspace/landing_prefs_store.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/team/team_clone_service.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  group('HomeWorkspaceRoute.expert', () {
    test('decodes expert query param', () {
      expect(
        HomeWorkspaceRoute.expert(
          '/home-v2/workspace/ws-1?expert=teampilot%2Fbuiltin%2Fdeveloper',
        ),
        'teampilot/builtin/developer',
      );
      expect(HomeWorkspaceRoute.expert('/home-v2/workspace/ws-1'), isNull);
    });
  });

  group('ExpertMemberResolver.resolveMember', () {
    test('resolves builtin member by key', () async {
      final builtin = builtinExpertMembers().first;
      final member = await ExpertMemberResolver.resolveMember(
        key: builtin.key,
      );
      expect(member, isNotNull);
      expect(member!.key, builtin.key);
      expect(member.name, builtin.name);
      expect(member.member.prompt, builtin.member.prompt);
      expect(member.member.playbook, builtin.member.playbook);
    });

    test('returns null for unknown key without source', () async {
      expect(
        await ExpertMemberResolver.resolveMember(key: 'missing/expert'),
        isNull,
      );
    });

    test('prefers hub state over builtin defaults', () async {
      const custom = DiscoverableMember(
        key: 'teampilot/builtin/developer',
        name: 'Custom Dev',
        description: '',
        category: 'Development',
        source: ExpertMemberSource.builtin,
        member: DiscoverableTeamMember(
          name: 'developer',
          prompt: 'Custom prompt',
          playbook: 'Custom playbook',
        ),
      );

      final member = await ExpertMemberResolver.resolveMember(
        key: custom.key,
        hubState: const ExpertHubState(allMembers: [custom]),
      );

      expect(member?.name, 'Custom Dev');
      expect(member?.member.prompt, 'Custom prompt');
      expect(member?.member.playbook, 'Custom playbook');
    });
  });

  group('applyExpertDeepLink', () {
    late InMemoryFilesystem fs;
    late LandingPrefsStore store;

    setUp(() {
      fs = InMemoryFilesystem();
      final paths = AppPaths('/tp');
      store = LandingPrefsStore(
        fs: fs,
        pathOverride: paths.homeWorkspaceWorkspaceLaunchPrefsJson,
      );
    });

    final workspace = Workspace(
      workspaceId: 'ws-1',
      display: 'Demo',
      createdAt: 1,
    );

    test('persists expertKey on simple-mode draft and runs preflight', () async {
      final builtin = builtinExpertMembers().first;
      final preflightKeys = <String>[];
      final resolver = _RecordingResolver(
        onPreflight: (key) async {
          preflightKeys.add(key);
          return ExpertCapabilityPack(
            member: const TeamMemberConfig(
              id: 'm1',
              name: 'Dev',
              prompt: 'p',
              joinedAt: 1,
            ),
            bundle: const ConfigBundle(),
            failedDeps: const [
              DependencyFailure(DependencyKind.skill, 'broken'),
            ],
          );
        },
      );

      final result = await applyExpertDeepLink(
        expertKey: builtin.key,
        workspaceId: workspace.workspaceId,
        workspace: workspace,
        routeProfileIsTeam: false,
        hubState: ExpertHubState(allMembers: [builtin]),
        store: store,
        resolver: resolver,
      );

      expect(result.outcome, ExpertDeepLinkOutcome.applied);
      expect(preflightKeys, [builtin.key]);
      expect(result.pack?.hasFailures, isTrue);
      final prefs = await store.prefsFor(workspace.workspaceId);
      expect(prefs?.expertKey, builtin.key);
      expect(prefs?.isPersonal, isTrue);
    });

    test('forces Simple when draft was team mode', () async {
      await store.save(
        workspace.workspaceId,
        const LandingPrefs(isPersonal: false, teamId: 'team-1'),
      );

      final builtin = builtinExpertMembers().first;
      final preflightKeys = <String>[];
      final resolver = _RecordingResolver(
        onPreflight: (key) async {
          preflightKeys.add(key);
          return ExpertCapabilityPack(
            member: const TeamMemberConfig(
              id: 'm1',
              name: 'Dev',
              prompt: 'p',
              joinedAt: 1,
            ),
            bundle: const ConfigBundle(),
          );
        },
      );

      final result = await applyExpertDeepLink(
        expertKey: builtin.key,
        workspaceId: workspace.workspaceId,
        workspace: workspace,
        routeProfileIsTeam: false,
        hubState: ExpertHubState(allMembers: [builtin]),
        store: store,
        resolver: resolver,
      );

      expect(result.outcome, ExpertDeepLinkOutcome.applied);
      expect(preflightKeys, [builtin.key]);
      final prefs = await store.prefsFor(workspace.workspaceId);
      expect(prefs?.isPersonal, isTrue);
      expect(prefs?.expertKey, builtin.key);
    });

    test('ignores expert when route profile is team', () async {
      final outcome = await applyExpertDeepLink(
        expertKey: 'teampilot/builtin/developer',
        workspaceId: workspace.workspaceId,
        workspace: workspace,
        routeProfileIsTeam: true,
        store: store,
      );

      expect(outcome.outcome, ExpertDeepLinkOutcome.ignoredTeamMode);
      final prefs = await store.prefsFor(workspace.workspaceId);
      expect(prefs?.expertKey, isNull);
    });

    test('clears expert when key is unknown', () async {
      final result = await applyExpertDeepLink(
        expertKey: 'missing/expert',
        workspaceId: workspace.workspaceId,
        workspace: workspace,
        routeProfileIsTeam: false,
        store: store,
      );

      expect(result.outcome, ExpertDeepLinkOutcome.notFound);
      final prefs = await store.prefsFor(workspace.workspaceId);
      expect(prefs?.expertKey, isNull);
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
    String expertKey, {
    TeamRosterSlotOverrides? overrides,
    TeamProfile? team,
    String? slotId,
    int? joinedAt,
  }) => onPreflight(expertKey);
}
