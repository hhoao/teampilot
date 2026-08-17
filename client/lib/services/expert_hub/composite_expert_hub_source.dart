import '../../models/discoverable_member.dart';
import '../../models/discoverable_team.dart';
import '../../models/catalog/catalog_types.dart';
import 'builtin_member_templates.dart';
import 'expert_hub_source.dart';
import 'git_registry_expert_hub_source.dart';
import 'local_expert_store.dart';
import 'team_member_index_source.dart';
import '../catalog/catalog_error_sanitizer.dart';

/// Stable hash of member prompt + playbook for deduping team-extracted entries
/// against builtin/registry catalog entries.
String memberContentHash(DiscoverableTeamMember member) =>
    Object.hash(member.responsibilities, member.playbook).toString();

/// Loads team templates for team-extracted member indexing (e.g. Team Hub source).
typedef TeamIndexLoader =
    Future<List<DiscoverableTeam>> Function({bool forceRefresh});

/// Merges builtin, registry, team-extracted, and local member templates.
/// Built-ins are listed first; team-extracted entries whose content hash
/// matches a builtin or registry entry are omitted (prefer catalog entry).
class CompositeExpertHubSource implements ExpertHubSourceContributions {
  CompositeExpertHubSource({
    List<DiscoverableMember> builtIns = const [],
    ExpertHubSource? registry,
    List<DiscoverableTeam> teams = const [],
    TeamIndexLoader? teamIndex,
    LocalExpertStore? localStore,
  }) : _builtIns = builtIns,
       _registry = registry ?? GitRegistryExpertHubSource(),
       _teams = teams,
       _teamIndex = teamIndex,
       _localStore = localStore ?? LocalExpertStore();

  factory CompositeExpertHubSource.withDefaults({
    ExpertHubSource? registry,
    List<DiscoverableTeam> teams = const [],
    TeamIndexLoader? teamIndex,
    LocalExpertStore? localStore,
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
  final LocalExpertStore _localStore;

  /// The local store this source reads clones / user-created experts from.
  /// Threaded into resolution so the loaded singleton shadows the catalog.
  LocalExpertStore get localStore => _localStore;

  Future<List<DiscoverableMember>> fetchMembers({
    bool forceRefresh = false,
  }) async => (await fetchMemberSources(
    forceRefresh: forceRefresh,
  )).expand((source) => source.items).toList(growable: false);

  @override
  Future<List<CatalogSourceResult<DiscoverableMember>>> fetchMemberSources({
    bool forceRefresh = false,
  }) async {
    final builtIns = _builtIns;
    final registrySources = await fetchExpertCatalogSources(
      _registry,
      forceRefresh: forceRefresh,
    );
    final registry = registrySources.expand((source) => source.items).toList();
    final teamIndex = _teamIndex;
    List<DiscoverableTeam> teams;
    CatalogSourceFailure? teamFailure;
    try {
      teams = teamIndex != null
          ? await teamIndex(forceRefresh: forceRefresh)
          : _teams;
    } catch (error) {
      teams = const [];
      teamFailure = CatalogSourceFailure(
        sourceId: 'team-extract',
        sourceLabel: 'Team templates',
        message: CatalogErrorSanitizer.sanitize(error.toString()),
      );
    }
    final teamExtract = indexMembersFromTeams(teams);
    List<DiscoverableMember> local;
    CatalogSourceFailure? localFailure;
    try {
      local = await _localStore.loadAll();
    } catch (error) {
      local = const [];
      localFailure = CatalogSourceFailure(
        sourceId: 'local',
        sourceLabel: 'Local experts',
        message: CatalogErrorSanitizer.sanitize(error.toString()),
      );
    }

    // A local clone (or user-created expert) shadows the catalog/builtin
    // entry with the same key, so a cloned team resolves to its clone.
    final localKeys = local.map((m) => m.key).toSet();
    final builtinKeys = builtIns.map((m) => m.key).toSet();
    final builtins = _builtIns
        .where((m) => !localKeys.contains(m.key))
        .toList(growable: false);
    final registryOnly = registry
        .where(
          (m) => !builtinKeys.contains(m.key) && !localKeys.contains(m.key),
        )
        .toList(growable: false);

    final preferredHashes = {
      for (final m in [...builtins, ...registryOnly])
        memberContentHash(m.member),
    };

    final teamExtractOnly = teamExtract
        .where(
          (m) =>
              !localKeys.contains(m.key) &&
              !preferredHashes.contains(memberContentHash(m.member)),
        )
        .toList(growable: false);

    return [
      CatalogSourceResult(
        sourceId: 'builtin',
        sourceLabel: 'Built-in',
        items: builtins,
      ),
      ...registrySources.map(
        (source) => CatalogSourceResult<DiscoverableMember>(
          sourceId: source.sourceId,
          sourceLabel: source.sourceLabel,
          items: source.items
              .where(
                (member) =>
                    !builtinKeys.contains(member.key) &&
                    !localKeys.contains(member.key),
              )
              .toList(growable: false),
          hasNext: source.hasNext,
          failure: source.failure,
        ),
      ),
      CatalogSourceResult(
        sourceId: 'team-extract',
        sourceLabel: 'Team templates',
        items: teamExtractOnly,
        failure: teamFailure,
      ),
      CatalogSourceResult(
        sourceId: 'local',
        sourceLabel: 'Local experts',
        items: local,
        failure: localFailure,
      ),
    ];
  }
}
