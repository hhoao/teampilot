import '../../models/discoverable_member.dart';
import '../../models/discoverable_team.dart';
import 'builtin_member_templates.dart';
import 'expert_hub_source.dart';
import 'git_registry_expert_hub_source.dart';
import 'local_member_template_store.dart';
import 'team_member_index_source.dart';

/// Stable hash of member prompt + playbook for deduping team-extracted entries
/// against builtin/registry catalog entries.
String memberContentHash(DiscoverableTeamMember member) =>
    Object.hash(member.responsibilities, member.playbook).toString();

/// Loads team templates for team-extracted member indexing (e.g. Team Hub source).
typedef TeamIndexLoader = Future<List<DiscoverableTeam>> Function({
  bool forceRefresh,
});

/// Merges builtin, registry, team-extracted, and local member templates.
/// Built-ins are listed first; team-extracted entries whose content hash
/// matches a builtin or registry entry are omitted (prefer catalog entry).
class CompositeExpertHubSource {
  CompositeExpertHubSource({
    List<DiscoverableMember> builtIns = const [],
    ExpertHubSource? registry,
    List<DiscoverableTeam> teams = const [],
    TeamIndexLoader? teamIndex,
    LocalMemberTemplateStore? localStore,
  }) : _builtIns = builtIns,
       _registry = registry ?? GitRegistryExpertHubSource(),
       _teams = teams,
       _teamIndex = teamIndex,
       _localStore = localStore ?? LocalMemberTemplateStore();

  factory CompositeExpertHubSource.withDefaults({
    ExpertHubSource? registry,
    List<DiscoverableTeam> teams = const [],
    TeamIndexLoader? teamIndex,
    LocalMemberTemplateStore? localStore,
  }) => CompositeExpertHubSource(
    builtIns: builtinExpertMembers(),
    registry: registry,
    teams: teams,
    teamIndex: teamIndex,
    localStore: localStore,
  );

  final List<DiscoverableMember> _builtIns;
  final ExpertHubSource _registry;
  final List<DiscoverableTeam> _teams;
  final TeamIndexLoader? _teamIndex;
  final LocalMemberTemplateStore _localStore;

  Future<List<DiscoverableMember>> fetchMembers({
    bool forceRefresh = false,
  }) async {
    final builtIns = _builtIns;
    final registry = await _registry.fetchMembers(forceRefresh: forceRefresh);
    final teamIndex = _teamIndex;
    final teams = teamIndex != null
        ? await teamIndex(forceRefresh: forceRefresh)
        : _teams;
    final teamExtract = indexMembersFromTeams(teams);
    final local = await _localStore.loadAll();

    final builtinKeys = builtIns.map((m) => m.key).toSet();
    final registryOnly = registry
        .where((m) => !builtinKeys.contains(m.key))
        .toList(growable: false);

    final preferredHashes = {
      for (final m in [...builtIns, ...registryOnly])
        memberContentHash(m.member),
    };

    final teamExtractOnly = teamExtract
        .where((m) => !preferredHashes.contains(memberContentHash(m.member)))
        .toList(growable: false);

    return [...builtIns, ...registryOnly, ...teamExtractOnly, ...local];
  }
}
