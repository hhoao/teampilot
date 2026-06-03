import 'package:flutter/foundation.dart';

import '../../models/discoverable_team.dart';

/// Fetches raw text for a URI (injected so tests can fake the network).
typedef RawContentFetcher = Future<String?> Function(Uri uri);

/// A git repo acting as a TeamHub registry.
@immutable
class TeamHubRegistry {
  const TeamHubRegistry({
    required this.owner,
    required this.name,
    this.branch = 'main',
  });

  final String owner;
  final String name;
  final String branch;

  String get fullName => '$owner/$name';

  /// Raw URL for [path], e.g.
  /// `https://raw.githubusercontent.com/{owner}/{name}/{branch}/{path}`.
  Uri rawUri(String path) => Uri.parse(
        'https://raw.githubusercontent.com/$owner/$name/$branch/$path',
      );
}

/// v1 built-in default registry (mirrors Skills' hardcoded default repos).
const kDefaultTeamHubRegistry = TeamHubRegistry(
  owner: 'flashskyai',
  name: 'team-hub',
  branch: 'main',
);

/// Abstraction over where public teams come from. v1 implementation reads a git
/// registry; a future `RemoteApiTeamHubSource` can implement the same interface
/// with no change to the cubit or UI.
abstract interface class TeamHubSource {
  Future<List<DiscoverableTeam>> fetchTeams({bool forceRefresh = false});
  Future<List<String>> categories({bool forceRefresh = false});
}
