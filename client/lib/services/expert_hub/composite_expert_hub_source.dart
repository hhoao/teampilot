import '../../models/discoverable_member.dart';
import '../../models/discoverable_team.dart';
import 'builtin_member_templates.dart';
import 'team_member_index_source.dart';

/// Stable hash of member prompt + playbook for deduping team-extracted entries
/// against builtin/registry catalog entries.
String memberContentHash(DiscoverableTeamMember member) =>
    Object.hash(member.prompt, member.playbook).toString();

/// Merges builtin, registry, team-extracted, and local member templates.
/// Built-ins are listed first; team-extracted entries whose content hash
/// matches a builtin or registry entry are omitted (prefer catalog entry).
class CompositeExpertHubSource {
  CompositeExpertHubSource({
    List<DiscoverableMember> builtIns = const [],
    Future<List<DiscoverableMember>> Function({bool forceRefresh})?
    fetchRegistry,
    List<DiscoverableTeam> teams = const [],
    Future<List<DiscoverableMember>> Function()? fetchLocal,
  }) : _builtIns = builtIns,
       _fetchRegistry = fetchRegistry,
       _teams = teams,
       _fetchLocal = fetchLocal;

  factory CompositeExpertHubSource.withDefaults({
    Future<List<DiscoverableMember>> Function({bool forceRefresh})?
    fetchRegistry,
    List<DiscoverableTeam> teams = const [],
    Future<List<DiscoverableMember>> Function()? fetchLocal,
  }) => CompositeExpertHubSource(
    builtIns: builtinExpertMembers(),
    fetchRegistry: fetchRegistry,
    teams: teams,
    fetchLocal: fetchLocal,
  );

  final List<DiscoverableMember> _builtIns;
  final Future<List<DiscoverableMember>> Function({bool forceRefresh})?
  _fetchRegistry;
  final List<DiscoverableTeam> _teams;
  final Future<List<DiscoverableMember>> Function()? _fetchLocal;

  Future<List<DiscoverableMember>> fetchMembers({
    bool forceRefresh = false,
  }) async {
    final builtIns = _builtIns;
    final registry =
        await (_fetchRegistry?.call(forceRefresh: forceRefresh) ??
            Future.value(const <DiscoverableMember>[]));
    final teamExtract = indexMembersFromTeams(_teams);
    final local =
        await (_fetchLocal?.call() ?? Future.value(const <DiscoverableMember>[]));

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
