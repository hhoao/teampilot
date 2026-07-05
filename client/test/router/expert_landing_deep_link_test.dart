import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_route.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/expert_hub/expert_landing_deep_link.dart';
import 'package:teampilot/services/expert_hub/expert_member_resolver.dart';
import 'package:teampilot/services/home_workspace/landing_prefs_store.dart';
import 'package:teampilot/services/storage/app_storage.dart';

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

  group('ExpertMemberResolver.resolveOverlay', () {
    test('builds overlay from builtin member', () async {
      final builtin = builtinExpertMembers().first;
      final overlay = await ExpertMemberResolver.resolveOverlay(builtin.key);
      expect(overlay, isNotNull);
      expect(overlay!.expertKey, builtin.key);
      expect(overlay.displayName, builtin.name);
      expect(overlay.prompt, builtin.member.prompt);
      expect(overlay.playbook, builtin.member.playbook);
    });

    test('returns null for unknown key without source', () async {
      expect(
        await ExpertMemberResolver.resolveOverlay('missing/expert'),
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
      final overlay = member == null
          ? null
          : ExpertMemberResolver.overlayFromMember(member);

      expect(overlay?.displayName, 'Custom Dev');
      expect(overlay?.prompt, 'Custom prompt');
      expect(overlay?.playbook, 'Custom playbook');
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

    test('persists expertKey on simple-mode draft', () async {
      final builtin = builtinExpertMembers().first;
      final outcome = await applyExpertDeepLink(
        expertKey: builtin.key,
        workspaceId: workspace.workspaceId,
        workspace: workspace,
        routeProfileIsTeam: false,
        hubState: ExpertHubState(allMembers: [builtin]),
        store: store,
      );

      expect(outcome, ExpertDeepLinkOutcome.applied);
      final prefs = await store.prefsFor(workspace.workspaceId);
      expect(prefs?.expertKey, builtin.key);
      expect(prefs?.isPersonal, isTrue);
    });

    test('ignores expert in team-mode draft', () async {
      await store.save(
        workspace.workspaceId,
        const LandingPrefs(isPersonal: false, teamId: 'team-1'),
      );

      final outcome = await applyExpertDeepLink(
        expertKey: 'teampilot/builtin/developer',
        workspaceId: workspace.workspaceId,
        workspace: workspace,
        routeProfileIsTeam: false,
        store: store,
      );

      expect(outcome, ExpertDeepLinkOutcome.ignoredTeamMode);
      final prefs = await store.prefsFor(workspace.workspaceId);
      expect(prefs?.expertKey, isNull);
    });

    test('clears expert when key is unknown', () async {
      final outcome = await applyExpertDeepLink(
        expertKey: 'missing/expert',
        workspaceId: workspace.workspaceId,
        workspace: workspace,
        routeProfileIsTeam: false,
        store: store,
      );

      expect(outcome, ExpertDeepLinkOutcome.notFound);
      final prefs = await store.prefsFor(workspace.workspaceId);
      expect(prefs?.expertKey, isNull);
    });
  });
}
