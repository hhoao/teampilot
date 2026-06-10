import '../../models/discoverable_team.dart';
import 'builtin_team_templates.dart';
import 'team_hub_source.dart';

/// Merges [builtIns] with a remote [delegate]. Built-in keys win on collision;
/// built-ins are listed first so they surface at the top of discovery.
class CompositeTeamHubSource implements TeamHubSource {
  CompositeTeamHubSource({
    required TeamHubSource delegate,
    List<DiscoverableTeam> builtIns = const [],
  })  : _delegate = delegate,
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
    final remote = await _delegate.fetchTeams(forceRefresh: forceRefresh);
    final builtinKeys = _builtIns.map((t) => t.key).toSet();
    final remoteOnly =
        remote.where((t) => !builtinKeys.contains(t.key)).toList(growable: false);
    return [..._builtIns, ...remoteOnly];
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
