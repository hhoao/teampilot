import 'dart:convert';

import '../expert_hub/expert_hub_source.dart';
import '../team_hub/team_hub_source.dart';
import 'http_github_api_client.dart';

/// Outcome of a successful Hub registry publish (fork PR opened).
class HubPublishResult {
  const HubPublishResult({
    required this.prUrl,
    required this.registryFullName,
    required this.slug,
  });

  final String prUrl;
  final String registryFullName;
  final String slug;
}

enum HubPublishErrorCode {
  missingToken,
  slugCollision,
  publishBlocked,
  apiError,
}

class HubPublishException implements Exception {
  const HubPublishException(this.code, this.message);

  final HubPublishErrorCode code;
  final String message;

  @override
  String toString() => 'HubPublishException($code): $message';
}

class GithubRepoInfo {
  const GithubRepoInfo({
    required this.owner,
    required this.name,
    required this.defaultBranch,
  });

  final String owner;
  final String name;
  final String defaultBranch;
}

class GithubFileContent {
  const GithubFileContent({
    required this.path,
    required this.content,
    required this.sha,
  });

  final String path;
  final String content;
  final String sha;
}

class GithubUser {
  const GithubUser({required this.login});

  final String login;
}

class GithubForkInfo {
  const GithubForkInfo({required this.owner, required this.name});

  final String owner;
  final String name;
}

class GithubPullRequest {
  const GithubPullRequest({required this.htmlUrl, required this.number});

  final String htmlUrl;
  final int number;
}

/// Injectable GitHub REST surface used by [GithubRegistryPublisher].
abstract interface class GithubApiClient {
  Future<GithubRepoInfo> getRepo({
    required String owner,
    required String name,
    required String token,
  });

  Future<String> getDefaultBranchSha({
    required String owner,
    required String name,
    required String branch,
    required String token,
  });

  Future<GithubFileContent?> getFileContent({
    required String owner,
    required String name,
    required String path,
    String? ref,
    required String token,
  });

  Future<GithubUser> getAuthenticatedUser({required String token});

  Future<GithubForkInfo> ensureFork({
    required String upstreamOwner,
    required String upstreamName,
    required String token,
  });

  Future<void> createBranch({
    required String owner,
    required String name,
    required String branch,
    required String fromSha,
    required String token,
  });

  Future<void> putFile({
    required String owner,
    required String name,
    required String path,
    required String branch,
    required String content,
    required String message,
    String? sha,
    required String token,
  });

  Future<GithubPullRequest> openPullRequest({
    required String owner,
    required String name,
    required String title,
    required String head,
    required String base,
    String? body,
    required String token,
  });
}

/// Fork → branch → Contents API → upstream PR publisher for Hub registries.
class GithubRegistryPublisher {
  GithubRegistryPublisher({GithubApiClient? api})
    : _api = api ?? HttpGithubApiClient();

  final GithubApiClient _api;

  Future<HubPublishResult> publishExpert({
    required ExpertHubRegistry upstream,
    required String slug,
    required Map<String, Object?> memberJson,
    required String token,
    String? branchName,
  }) {
    return _publish(
      owner: upstream.owner,
      name: upstream.name,
      slug: slug,
      packagePath: 'members/$slug/member.json',
      packageJson: memberJson,
      indexListKey: 'members',
      indexEntryIsObject: false,
      branchName: branchName ?? 'publish-expert-$slug',
      prTitle: 'Add expert `$slug`',
      token: token,
    );
  }

  Future<HubPublishResult> publishTeam({
    required TeamHubRegistry upstream,
    required String slug,
    required Map<String, Object?> teamJson,
    required String token,
    String? branchName,
  }) {
    return _publish(
      owner: upstream.owner,
      name: upstream.name,
      slug: slug,
      packagePath: 'teams/$slug/team.json',
      packageJson: teamJson,
      indexListKey: 'teams',
      indexEntryIsObject: true,
      branchName: branchName ?? 'publish-team-$slug',
      prTitle: 'Add team `$slug`',
      token: token,
    );
  }

  Future<HubPublishResult> _publish({
    required String owner,
    required String name,
    required String slug,
    required String packagePath,
    required Map<String, Object?> packageJson,
    required String indexListKey,
    required bool indexEntryIsObject,
    required String branchName,
    required String prTitle,
    required String token,
  }) async {
    final trimmedSlug = slug.trim();
    if (trimmedSlug.isEmpty) {
      throw const HubPublishException(
        HubPublishErrorCode.apiError,
        'Slug must not be empty',
      );
    }

    final repo = await _api.getRepo(owner: owner, name: name, token: token);
    final defaultBranch = repo.defaultBranch;

    final upstreamIndex = await _api.getFileContent(
      owner: owner,
      name: name,
      path: 'index.json',
      ref: defaultBranch,
      token: token,
    );
    final indexRaw = upstreamIndex?.content ?? '{"$indexListKey":[]}';
    final existingSlugs = _parseIndexSlugs(
      indexRaw,
      listKey: indexListKey,
      entryIsObject: indexEntryIsObject,
    );
    if (existingSlugs.contains(trimmedSlug)) {
      throw HubPublishException(
        HubPublishErrorCode.slugCollision,
        'Slug "$trimmedSlug" already exists in $owner/$name index.json',
      );
    }

    // Collision checked before any fork/write.
    final defaultSha = await _api.getDefaultBranchSha(
      owner: owner,
      name: name,
      branch: defaultBranch,
      token: token,
    );
    final fork = await _api.ensureFork(
      upstreamOwner: owner,
      upstreamName: name,
      token: token,
    );
    await _api.createBranch(
      owner: fork.owner,
      name: fork.name,
      branch: branchName,
      fromSha: defaultSha,
      token: token,
    );

    await _api.putFile(
      owner: fork.owner,
      name: fork.name,
      path: packagePath,
      branch: branchName,
      content: _encodePrettyJson(packageJson),
      message: 'Add $packagePath',
      token: token,
    );

    final updatedIndex = _addSlugToIndex(
      indexRaw,
      slug: trimmedSlug,
      listKey: indexListKey,
      entryIsObject: indexEntryIsObject,
    );
    final forkIndex = await _api.getFileContent(
      owner: fork.owner,
      name: fork.name,
      path: 'index.json',
      ref: branchName,
      token: token,
    );
    await _api.putFile(
      owner: fork.owner,
      name: fork.name,
      path: 'index.json',
      branch: branchName,
      content: updatedIndex,
      message: 'Update index.json for $trimmedSlug',
      sha: forkIndex?.sha,
      token: token,
    );

    final pr = await _api.openPullRequest(
      owner: owner,
      name: name,
      title: prTitle,
      head: '${fork.owner}:$branchName',
      base: defaultBranch,
      body: 'Published via TeamPilot Hub upload.',
      token: token,
    );

    return HubPublishResult(
      prUrl: pr.htmlUrl,
      registryFullName: '$owner/$name',
      slug: trimmedSlug,
    );
  }

  static List<String> _parseIndexSlugs(
    String indexRaw, {
    required String listKey,
    required bool entryIsObject,
  }) {
    try {
      final root = (jsonDecode(indexRaw) as Map).cast<String, Object?>();
      final list = root[listKey];
      if (list is! List) return const [];
      if (entryIsObject) {
        return list
            .whereType<Map>()
            .map((m) => (m['slug'] as String?)?.trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList(growable: false);
      }
      return list
          .map((s) => s is String ? s.trim() : '')
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  static String _addSlugToIndex(
    String indexRaw, {
    required String slug,
    required String listKey,
    required bool entryIsObject,
  }) {
    Map<String, Object?> root;
    try {
      root = (jsonDecode(indexRaw) as Map).cast<String, Object?>();
    } on FormatException {
      root = {};
    }
    final existing = root[listKey];
    final list = <Object?>[
      if (existing is List) ...existing,
    ];
    final already = _parseIndexSlugs(
      indexRaw,
      listKey: listKey,
      entryIsObject: entryIsObject,
    );
    if (!already.contains(slug)) {
      list.add(entryIsObject ? {'slug': slug} : slug);
    }
    root[listKey] = list;
    return _encodePrettyJson(root);
  }

  static String _encodePrettyJson(Map<String, Object?> json) {
    return const JsonEncoder.withIndent('  ').convert(json);
  }
}
