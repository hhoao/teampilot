import '../../models/discoverable_team.dart';
import '../../models/catalog/catalog_types.dart';
import 'builtin_team_templates.dart';
import 'team_hub_source.dart';

/// Merges [builtIns] with a remote [delegate]. Built-in keys win on collision;
/// built-ins are listed first so they surface at the top of discovery.
class CompositeTeamHubSource
    implements TeamHubSource, TeamHubSourceContributions {
  CompositeTeamHubSource({
    required TeamHubSource delegate,
    List<DiscoverableTeam> builtIns = const [],
  }) : _delegate = delegate,
       _builtIns = builtIns;

  factory CompositeTeamHubSource.withDefaults(TeamHubSource delegate) =>
      CompositeTeamHubSource(
        delegate: delegate,
        builtIns: builtInTeamTemplates(),
      );

  final TeamHubSource _delegate;
  final List<DiscoverableTeam> _builtIns;

  @override
  Future<List<DiscoverableTeam>> fetchTeams({bool forceRefresh = false}) async {
    final sources = await fetchTeamSources(forceRefresh: forceRefresh);
    final remote = sources
        .where((source) => source.sourceId != 'builtin')
        .expand((source) => source.items)
        .toList();
    final builtinKeys = _builtIns.map((t) => t.key).toSet();
    final remoteOnly = remote
        .where((t) => !builtinKeys.contains(t.key))
        .toList(growable: false);
    return [..._builtIns, ...remoteOnly];
  }

  @override
  Future<List<CatalogSourceResult<DiscoverableTeam>>> fetchTeamSources({
    bool forceRefresh = false,
  }) async {
    final delegateSources = await fetchTeamCatalogSources(
      _delegate,
      forceRefresh: forceRefresh,
    );
    final builtinKeys = _builtIns.map((team) => team.key).toSet();
    final remoteSources = delegateSources
        .map(
          (source) => CatalogSourceResult<DiscoverableTeam>(
            sourceId: source.sourceId,
            sourceLabel: source.sourceLabel,
            items: source.items
                .where((team) => !builtinKeys.contains(team.key))
                .toList(growable: false),
            hasNext: source.hasNext,
            failure: source.failure,
          ),
        )
        .toList(growable: false);
    return [
      CatalogSourceResult(
        sourceId: 'builtin',
        sourceLabel: 'Built-in',
        items: _builtIns,
      ),
      ...remoteSources,
    ];
  }

  @override
  Future<List<String>> categories({bool forceRefresh = false}) async {
    final teams = await fetchTeams(forceRefresh: forceRefresh);
    final set = <String>{
      for (final t in teams)
        if (t.category.trim().isNotEmpty) t.category.trim(),
    };
    final list = set.toList()..sort();
    return list;
  }
}
