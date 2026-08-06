import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_member_resolver.dart';
import 'package:teampilot/services/expert_hub/local_expert_store.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeExpertHubSource implements ExpertHubSource {
  _FakeExpertHubSource(this.members);
  final List<DiscoverableMember> members;
  @override
  Future<List<DiscoverableMember>> fetchMembers({bool forceRefresh = false}) async =>
      members;
  @override
  Future<List<String>> categories({bool forceRefresh = false}) async => const [];
}

void main() {
  test('resolve returns builtin member by key', () {
    final builtin = builtinExpertMembers().first;
    expect(
      ExpertMemberResolver.resolve(key: builtin.key),
      builtin,
    );
  });

  test('resolve checks hub state before builtin fallback', () {
    const custom = DiscoverableMember(
      key: 'teampilot/builtin/developer',
      name: 'Custom Dev',
      description: '',
      category: 'Development',
      source: ExpertMemberSource.builtin,
      member: DiscoverableTeamMember(name: 'developer', responsibilities: 'p'),
    );

    final resolved = ExpertMemberResolver.resolve(
      key: custom.key,
      hubState: const ExpertHubState(allMembers: [custom]),
    );
    expect(resolved?.name, 'Custom Dev');
  });

  test('labelForKey falls back when key is missing', () {
    expect(
      ExpertMemberResolver.labelForKey(
        key: null,
        fallbackLabel: 'No expert',
      ),
      'No expert',
    );
  });

  test('resolveMember returns builtin default expert', () async {
    const expectedPrompt =
        'You are a helpful coding agent in TeamPilot. Follow the user\'s '
        'instructions carefully. Prefer reading the repo before editing.';

    final resolved = await ExpertMemberResolver.resolveMember(
      key: kBuiltinDefaultExpertKey,
    );

    expect(resolved, isNotNull);
    expect(resolved!.key, kBuiltinDefaultExpertKey);
    expect(resolved.name, 'Default');
    expect(resolved.member.responsibilities, expectedPrompt);
    expect(resolved.skillDeps, hasLength(1));
    expect(resolved.skillDeps.single.name, 'Using Superpowers');
    expect(resolved.pluginDeps, isEmpty);
    expect(resolved.mcpDeps, isEmpty);
  });

  test('resolveMember returns full builtin snapshot', () async {
    const member = DiscoverableMember(
      key: 'teampilot/builtin/developer',
      name: 'Developer',
      description: '',
      category: 'Development',
      source: ExpertMemberSource.builtin,
      member: DiscoverableTeamMember(
        name: 'developer',
        responsibilities: 'Build features',
        playbook: 'Use TDD',
      ),
    );
    final resolved = await ExpertMemberResolver.resolveMember(
      key: member.key,
      hubState: const ExpertHubState(allMembers: [member]),
    );
    expect(resolved?.key, member.key);
    expect(resolved?.name, 'Developer');
    expect(resolved?.member.responsibilities, 'Build features');
    expect(resolved?.member.playbook, 'Use TDD');
  });

  test('resolveMember prefers a local clone over the catalog', () async {
    final store = LocalExpertStore(
      fs: InMemoryFilesystem(),
      dirOverride: AppPaths('/tp').memberHubLocalTemplatesDir,
    );
    const catalogMember = DiscoverableMember(
      key: 'acme/experts/pm',
      name: 'Catalog PM',
      description: '',
      category: 'c',
      source: ExpertMemberSource.registry,
      member: DiscoverableTeamMember(name: 'pm'),
    );
    await store.putClone(
      catalogMember.copyWith(source: ExpertMemberSource.clone),
    );
    final source = CompositeExpertHubSource(
      builtIns: const [],
      registry: _FakeExpertHubSource([catalogMember]),
      localStore: store,
    );

    final resolved = await ExpertMemberResolver.resolveMember(
      key: 'acme/experts/pm',
      source: source,
      localStore: store,
    );
    expect(resolved, isNotNull);
    expect(resolved!.source, ExpertMemberSource.clone,
        reason: 'local clone shadows the catalog entry');
  });
}
