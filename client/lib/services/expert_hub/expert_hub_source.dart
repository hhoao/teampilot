import 'package:flutter/foundation.dart';

import '../../models/discoverable_member.dart';

/// Fetches raw text for a URI (injected so tests can fake the network).
typedef RawContentFetcher = Future<String?> Function(Uri uri);

/// A git repo acting as an Expert Hub registry.
@immutable
class ExpertHubRegistry {
  const ExpertHubRegistry({
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
  Uri rawUri(String path) =>
      Uri.parse('https://raw.githubusercontent.com/$owner/$name/$branch/$path');
}

/// v1 built-in default registry (mirrors Team Hub's hardcoded default repos).
const kDefaultExpertHubRegistry = ExpertHubRegistry(
  owner: 'flashskyai',
  name: 'member-hub',
  branch: 'main',
);

/// Abstraction over where public members come from. v1 implementation reads a git
/// registry; a future `RemoteApiExpertHubSource` can implement the same interface
/// with no change to the cubit or UI.
abstract interface class ExpertHubSource {
  Future<List<DiscoverableMember>> fetchMembers({bool forceRefresh = false});
  Future<List<String>> categories({bool forceRefresh = false});
}
