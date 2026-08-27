import 'package:flutter/foundation.dart';

import '../../models/skill_pack.dart';

/// Fetches raw text for a URI (injected so tests can fake the network).
typedef SkillPackRawContentFetcher = Future<String?> Function(Uri uri);

/// A git repository (optionally a subdirectory) acting as a Skill Pack registry.
@immutable
class SkillPackRegistryConfig {
  const SkillPackRegistryConfig({
    required this.owner,
    required this.name,
    this.branch = 'main',
    this.rootPath = '',
  });

  final String owner;
  final String name;
  final String branch;
  final String rootPath;

  String get fullName => '$owner/$name';

  String get catalogPrefix {
    final root = _normalizedRootPath;
    return root.isEmpty ? fullName : '$fullName/$root';
  }

  Uri rawUri(String path) {
    final root = _normalizedRootPath;
    final relative = root.isEmpty ? path : '$root/$path';
    return Uri.parse(
      'https://raw.githubusercontent.com/$owner/$name/$branch/$relative',
    );
  }

  String repoPath(String path) {
    final root = _normalizedRootPath;
    return root.isEmpty ? path : '$root/$path';
  }

  String get _normalizedRootPath =>
      rootPath.trim().replaceAll(RegExp(r'^/+|/+$'), '');
}

const kDefaultSkillPackRegistry = SkillPackRegistryConfig(
  owner: 'hhoao',
  name: 'teampilot-resources',
  branch: 'main',
  rootPath: 'skill-packs',
);

abstract interface class SkillPackSource {
  Future<List<SkillPack>> fetchPacks({bool forceRefresh = false});
}
