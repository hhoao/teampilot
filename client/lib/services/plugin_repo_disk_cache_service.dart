import 'dart:convert';
import 'dart:io';

import '../models/plugin.dart';
import '../models/plugin_external_source.dart';
import '../utils/logger.dart';
import 'app_storage.dart';
import 'flashskyai_storage_roots.dart';
import 'plugin_exceptions.dart';
import 'plugin_repo_git_service.dart';
import 'skill_fetch_service.dart';

/// Disk-backed plugin marketplace cache.
///
/// On-disk layout under [AppPaths.pluginMarketplaceCacheDir]:
///   `{owner}/{name}@{branch}/` — extracted repo contents.
class PluginRepoDiskCacheService {
  PluginRepoDiskCacheService({
    PluginRepoGitService? gitService,
    FlashskyaiStorageRoots? storageRoots,
  }) : _git = gitService ?? PluginRepoGitService(),
       _storageRoots = storageRoots;

  final PluginRepoGitService _git;
  final FlashskyaiStorageRoots? _storageRoots;

  static String repoKey(PluginMarketplace m) =>
      '${m.owner}/${m.name}@${m.branch}';

  Future<String> _cacheRoot() async {
    if (_storageRoots != null) {
      return (await _storageRoots.resolve()).pluginMarketplaceCacheDir;
    }
    return AppStorage.paths.pluginMarketplaceCacheDir;
  }

  Future<String> _repoDirPath(PluginMarketplace m) async {
    final root = await _cacheRoot();
    // repoKey uses '/' as separator — join each segment separately so it
    // works on Windows too.
    return _fsJoin(root, m.owner, '${m.name}@${m.branch}');
  }

  static String _fsJoin(String a, String b, String c) {
    // Use dart:io Platform-aware separator.
    final sep = Platform.pathSeparator;
    return '$a$sep$b$sep$c';
  }

  /// Sync the marketplace repo via git and return the local directory path.
  Future<String> syncMarketplace(PluginMarketplace m) async {
    final dirPath = await _repoDirPath(m);
    final workDir = Directory(dirPath);

    for (final branch in skillRepoBranchCandidates(m.branch)) {
      try {
        await _git.syncCheckout(
          PluginMarketplace(
            owner: m.owner,
            name: m.name,
            branch: branch,
            enabled: m.enabled,
            displayName: m.displayName,
          ),
          workDir,
        );
        appLogger.d('[PluginRepoDiskCache] synced ${m.fullName}@$branch → $dirPath');
        return dirPath;
      } catch (e) {
        appLogger.d('[PluginRepoDiskCache] sync ${m.fullName}@$branch failed: $e');
      }
    }

    // If workDir already exists from a prior sync, fall back to it.
    if (workDir.existsSync()) {
      appLogger.w(
        '[PluginRepoDiskCache] using stale cache for ${m.fullName}',
      );
      return dirPath;
    }

    throw MarketplaceUnreachableException(
      '${m.fullName}: git sync failed for all branch candidates',
    );
  }

  /// Sync + parse → list of [DiscoverablePlugin].
  Future<List<DiscoverablePlugin>> discoverablePlugins(PluginMarketplace m) async {
    final dirPath = await syncMarketplace(m);
    return parseMarketplaceManifest(directory: dirPath, marketplace: m);
  }

  /// Pure parser — reads `<directory>/.claude-plugin/marketplace.json`.
  ///
  /// Each `plugins[]` entry produces one [DiscoverablePlugin].
  List<DiscoverablePlugin> parseMarketplaceManifest({
    required String directory,
    required PluginMarketplace marketplace,
  }) {
    final manifestFile = File(
      _fsJoin(directory, '.claude-plugin', 'marketplace.json'),
    );
    if (!manifestFile.existsSync()) {
      appLogger.w(
        '[PluginRepoDiskCache] no marketplace.json in $directory',
      );
      return const [];
    }

    final Map<String, Object?> manifest;
    try {
      manifest = (json.decode(manifestFile.readAsStringSync()) as Map)
          .cast<String, Object?>();
    } catch (e) {
      throw PluginManifestException(manifestFile.path, cause: e);
    }

    final rawPlugins = manifest['plugins'];
    if (rawPlugins is! List) return const [];

    final result = <DiscoverablePlugin>[];
    for (final raw in rawPlugins) {
      if (raw is! Map) continue;
      final entry = raw.cast<String, Object?>();

      final pluginName = entry['name'] as String? ?? '';
      if (pluginName.isEmpty) continue;

      final description = entry['description'] as String? ?? '';
      final version = entry['version'] as String? ?? '0.0.0';
      final parsedSource = _parsePluginSource(
        entry['source'],
        marketplace: marketplace,
        homepage: entry['homepage'] as String?,
      );

      // `category` may be a String or a List<String>.
      final categories = _parseStringOrList(entry['category']);
      final keywords = _parseStringOrList(entry['keywords']);

      result.add(
        DiscoverablePlugin(
          key: '${marketplace.owner}:${marketplace.name}:$pluginName',
          name: pluginName,
          description: description,
          version: version,
          source: parsedSource.relativePath,
          readmeUrl: parsedSource.readmeUrl,
          localInstall: parsedSource.localInstall,
          externalSource: parsedSource.externalSource,
          marketplaceOwner: marketplace.owner,
          marketplaceName: marketplace.name,
          marketplaceBranch: marketplace.branch,
          categories: categories,
          keywords: keywords,
        ),
      );
    }
    return result;
  }

  /// Claude Code marketplace schema: `source` may be a repo-relative path string
  /// or an object (`git-subdir`, `url`, `github`, …). See anthropics/claude-plugins-official.
  static _ParsedMarketplaceSource _parsePluginSource(
    Object? raw, {
    required PluginMarketplace marketplace,
    String? homepage,
  }) {
    if (raw is String) {
      final path = raw.trim();
      final relative = path.isEmpty ? '.' : path;
      final readmeUrl = relative == '.'
          ? homepage
          : (homepage ??
                'https://github.com/${marketplace.owner}/${marketplace.name}'
                '/tree/${marketplace.branch}/$relative');
      return _ParsedMarketplaceSource(
        relativePath: relative,
        readmeUrl: readmeUrl,
        localInstall: true,
      );
    }

    if (raw is Map) {
      final map = raw.cast<String, Object?>();
      final kind = map['source'] as String? ?? '';
      switch (kind) {
        case 'git-subdir':
          final url = map['url'] as String? ?? '';
          final path = (map['path'] as String? ?? '').trim();
          if (path.isNotEmpty && _repoUrlMatchesMarketplace(url, marketplace)) {
            final relative = path.startsWith('./') ? path : './$path';
            return _ParsedMarketplaceSource(
              relativePath: relative,
              readmeUrl: homepage ?? _githubTreeUrl(url, map['ref'] as String?, path),
              localInstall: true,
            );
          }
          final external = PluginExternalSource.fromMarketplaceObject(map);
          return _ParsedMarketplaceSource(
            relativePath: '',
            readmeUrl: homepage ?? (url.isEmpty ? null : url),
            localInstall: false,
            externalSource: external,
          );
        case 'url':
        case 'github':
          final external = PluginExternalSource.fromMarketplaceObject(map);
          final readme = homepage ??
              (map['url'] as String?) ??
              (map['repo'] != null ? 'https://github.com/${map['repo']}' : null);
          return _ParsedMarketplaceSource(
            relativePath: '',
            readmeUrl: readme,
            localInstall: false,
            externalSource: external,
          );
        default:
          return _ParsedMarketplaceSource(
            relativePath: '',
            readmeUrl: homepage,
            localInstall: false,
          );
      }
    }

    return _ParsedMarketplaceSource(
      relativePath: '.',
      readmeUrl: homepage,
      localInstall: true,
    );
  }

  static bool _repoUrlMatchesMarketplace(String url, PluginMarketplace m) {
    final normalized = url.toLowerCase().replaceAll(RegExp(r'\.git$'), '');
    return normalized.contains('github.com/${m.owner}/${m.name}') ||
        normalized.endsWith('/${m.name}');
  }

  static String? _githubTreeUrl(String repoUrl, String? ref, String path) {
    final match = RegExp(
      r'github\.com/([^/]+)/([^/]+)',
      caseSensitive: false,
    ).firstMatch(repoUrl);
    if (match == null) return repoUrl.isEmpty ? null : repoUrl;
    final owner = match.group(1);
    final name = match.group(2)?.replaceAll(RegExp(r'\.git$'), '');
    if (owner == null || name == null) return repoUrl;
    final branch = (ref == null || ref.isEmpty) ? 'main' : ref;
    final cleanPath = path.startsWith('./') ? path.substring(2) : path;
    return 'https://github.com/$owner/$name/tree/$branch/$cleanPath';
  }

  static List<String> _parseStringOrList(Object? value) {
    if (value == null) return const [];
    if (value is String) return value.isEmpty ? const [] : [value];
    if (value is List) return value.whereType<String>().toList();
    return const [];
  }
}

class _ParsedMarketplaceSource {
  const _ParsedMarketplaceSource({
    required this.relativePath,
    this.readmeUrl,
    required this.localInstall,
    this.externalSource,
  });

  final String relativePath;
  final String? readmeUrl;
  final bool localInstall;
  final PluginExternalSource? externalSource;
}
