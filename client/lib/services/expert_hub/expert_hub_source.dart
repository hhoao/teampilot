import 'package:flutter/foundation.dart';

import '../../models/discoverable_member.dart';

/// Fetches raw text for a URI (injected so tests can fake the network).
typedef RawContentFetcher = Future<String?> Function(Uri uri);

/// A git repo (optionally a subdirectory) acting as an Expert Hub registry.
@immutable
class ExpertHubRegistry {
  const ExpertHubRegistry({
    required this.owner,
    required this.name,
    this.branch = 'main',
    this.rootPath = '',
  });

  final String owner;
  final String name;
  final String branch;

  /// Subdirectory inside the repo that holds `index.json` + `members/…`.
  /// Empty means the registry lives at the repo root.
  final String rootPath;

  String get fullName => '$owner/$name';

  /// Prefix stamped into discoverable keys (`owner/repo` or `owner/repo/root`).
  String get catalogPrefix {
    final root = rootPath.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    return root.isEmpty ? fullName : '$fullName/$root';
  }

  /// Raw URL for [path] under [rootPath], e.g.
  /// `https://raw.githubusercontent.com/{owner}/{name}/{branch}/{rootPath}/{path}`.
  Uri rawUri(String path) {
    final root = rootPath.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final relative = root.isEmpty ? path : '$root/$path';
    return Uri.parse(
      'https://raw.githubusercontent.com/$owner/$name/$branch/$relative',
    );
  }

  /// Repo-relative path for Contents API / publish writes.
  String repoPath(String path) {
    final root = rootPath.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    return root.isEmpty ? path : '$root/$path';
  }
}

/// Default registry: TeamPilot app repo, `member-hub/` subdirectory.
const kDefaultExpertHubRegistry = ExpertHubRegistry(
  owner: 'hhoao',
  name: 'teampilot',
  branch: 'main',
  rootPath: 'member-hub',
);

/// Abstraction over where public members come from. v1 implementation reads a git
/// registry; a future `RemoteApiExpertHubSource` can implement the same interface
/// with no change to the cubit or UI.
abstract interface class ExpertHubSource {
  Future<List<DiscoverableMember>> fetchMembers({bool forceRefresh = false});
  Future<List<String>> categories({bool forceRefresh = false});
}
