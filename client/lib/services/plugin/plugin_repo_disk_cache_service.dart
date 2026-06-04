import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../../models/plugin.dart';
import '../../models/plugin_external_source.dart';
import '../../utils/logger.dart';
import '../storage/app_storage.dart';
import '../storage/storage_resolver.dart';
import '../io/filesystem.dart';
import 'plugin_exceptions.dart';
import 'plugin_repo_git_service.dart';
import '../skill/skill_fetch_service.dart';

/// Disk-backed plugin marketplace cache.
///
/// On-disk layout under [AppPaths.pluginMarketplaceCacheDir]:
///   `{owner}/{name}@{branch}/` — extracted repo contents.
///   `.teampilot-plugin-cache-meta.json` — last synced branch + commit sha.
class PluginRepoDiskCacheService {
  PluginRepoDiskCacheService({
    PluginRepoGitService? gitService,
    StorageRoots? storageRoots,
    Filesystem? filesystem,
  }) : _git = gitService ?? PluginRepoGitService(),
       _storageRoots = storageRoots,
       _fsOverride = filesystem;

  final PluginRepoGitService _git;
  final StorageRoots? _storageRoots;
  final Filesystem? _fsOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;

  static final Map<String, Future<String>> _syncInflight = {};

  static const _metaFileName = '.teampilot-plugin-cache-meta.json';

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
    return p.join(root, m.owner, '${m.name}@${m.branch}');
  }

  /// Sync the marketplace repo via git and return the local directory path.
  Future<String> syncMarketplace(
    PluginMarketplace m, {
    bool force = false,
  }) async {
    final key = repoKey(m);
    final existing = _syncInflight[key];
    if (existing != null) return existing;

    final future = _syncMarketplaceOnce(m, force: force);
    _syncInflight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_syncInflight[key], future)) {
        _syncInflight.remove(key);
      }
    }
  }

  Future<String> _syncMarketplaceOnce(
    PluginMarketplace m, {
    required bool force,
  }) async {
    final dirPath = await _repoDirPath(m);

    if (!force && (await _fs.stat(dirPath)).exists) {
      final meta = await _readMeta(dirPath);
      if (meta != null && meta.configuredBranch == m.branch) {
        final remote = await _git.resolveRemoteShaWithFallback(
          m.owner,
          m.name,
          meta.resolvedBranch,
        );
        if (remote != null && remote.sha == meta.commitSha) {
          appLogger.d(
            '[PluginRepoDiskCache] skipped ${m.fullName}@'
            '${meta.resolvedBranch} (up to date)',
          );
          return dirPath;
        }
        if (remote == null && await _hasCheckout(dirPath)) {
          appLogger.d(
            '[PluginRepoDiskCache] remote SHA unavailable for ${m.fullName}, '
            'using disk cache',
          );
          return dirPath;
        }
      }
    }

    Object? lastError;
    for (final branch in skillRepoBranchCandidates(m.branch)) {
      try {
        final synced = await _git.syncCheckout(
          PluginMarketplace(
            owner: m.owner,
            name: m.name,
            branch: branch,
            enabled: m.enabled,
            displayName: m.displayName,
          ),
          _fs,
          dirPath,
        );
        await _writeMeta(
          workDirPath: dirPath,
          configuredBranch: m.branch,
          resolvedBranch: synced.branch,
          commitSha: synced.commitSha,
        );
        appLogger.d(
          '[PluginRepoDiskCache] synced ${m.fullName}@${synced.branch} → $dirPath',
        );
        return dirPath;
      } catch (e) {
        lastError = e;
        appLogger.d(
          '[PluginRepoDiskCache] sync ${m.fullName}@$branch failed: $e',
        );
      }
    }

    if ((await _fs.stat(dirPath)).exists) {
      appLogger.w('[PluginRepoDiskCache] using stale cache for ${m.fullName}');
      return dirPath;
    }

    throw MarketplaceUnreachableException(
      '${m.fullName}: git sync failed for all branch candidates',
      cause: lastError,
    );
  }

  Future<bool> _hasCheckout(String workDirPath) async {
    final manifestStat = await _fs.stat(
      _fs.pathContext.join(workDirPath, '.claude-plugin', 'marketplace.json'),
    );
    if (manifestStat.exists) return true;
    return (await _fs.stat(
      _fs.pathContext.join(workDirPath, '.git'),
    )).isDirectory;
  }

  Future<_PluginCacheMeta?> _readMeta(String workDirPath) async {
    final metaPath = _fs.pathContext.join(workDirPath, _metaFileName);
    final stat = await _fs.stat(metaPath);
    if (!stat.exists) return null;
    try {
      final content = await _fs.readString(metaPath);
      if (content == null) return null;
      final decoded = jsonDecode(content);
      if (decoded is! Map) return null;
      return _PluginCacheMeta.fromJson(decoded.cast<String, Object?>());
    } on Object {
      return null;
    }
  }

  Future<void> _writeMeta({
    required String workDirPath,
    required String configuredBranch,
    required String resolvedBranch,
    required String commitSha,
  }) async {
    final meta = _PluginCacheMeta(
      configuredBranch: configuredBranch,
      resolvedBranch: resolvedBranch,
      commitSha: commitSha,
      syncedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _fs.writeString(
      _fs.pathContext.join(workDirPath, _metaFileName),
      const JsonEncoder.withIndent('  ').convert(meta.toJson()),
    );
  }

  /// Reads cached marketplace manifest without triggering git sync.
  Future<List<DiscoverablePlugin>> discoverablePluginsCached(
    PluginMarketplace m,
  ) async {
    final dirPath = await _repoDirPath(m);
    if (!(await _fs.stat(dirPath)).exists) return const [];
    return parseMarketplaceManifest(directory: dirPath, marketplace: m);
  }

  /// Sync + parse → list of [DiscoverablePlugin].
  Future<List<DiscoverablePlugin>> discoverablePlugins(
    PluginMarketplace m,
  ) async {
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
      p.join(directory, '.claude-plugin', 'marketplace.json'),
    );
    if (!manifestFile.existsSync()) {
      appLogger.w('[PluginRepoDiskCache] no marketplace.json in $directory');
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
              readmeUrl:
                  homepage ?? _githubTreeUrl(url, map['ref'] as String?, path),
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
          final readme =
              homepage ??
              (map['url'] as String?) ??
              (map['repo'] != null
                  ? 'https://github.com/${map['repo']}'
                  : null);
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

class _PluginCacheMeta {
  const _PluginCacheMeta({
    required this.configuredBranch,
    required this.resolvedBranch,
    required this.commitSha,
    required this.syncedAtMs,
  });

  final String configuredBranch;
  final String resolvedBranch;
  final String commitSha;
  final int syncedAtMs;

  Map<String, Object?> toJson() => {
    'configuredBranch': configuredBranch,
    'resolvedBranch': resolvedBranch,
    'commitSha': commitSha,
    'syncedAtMs': syncedAtMs,
  };

  factory _PluginCacheMeta.fromJson(Map<String, Object?> json) =>
      _PluginCacheMeta(
        configuredBranch: json['configuredBranch'] as String? ?? 'main',
        resolvedBranch: json['resolvedBranch'] as String? ?? 'main',
        commitSha: json['commitSha'] as String? ?? '',
        syncedAtMs: json['syncedAtMs'] as int? ?? 0,
      );
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
