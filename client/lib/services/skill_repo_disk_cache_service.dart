import 'dart:convert';
import 'dart:typed_data';

import '../models/skill.dart';
import '../utils/logger.dart';
import 'app_storage.dart';
import 'io/filesystem.dart';
import 'skill_fetch_service.dart';

/// On-disk layout under [AppStorage.skillRepoCacheDir]:
/// `{owner}__{name}/meta.json`, `skills.json`, `files/**`.
class SkillRepoCacheMeta {
  const SkillRepoCacheMeta({
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

  factory SkillRepoCacheMeta.fromJson(Map<String, Object?> json) =>
      SkillRepoCacheMeta(
        configuredBranch: json['configuredBranch'] as String,
        resolvedBranch: json['resolvedBranch'] as String,
        commitSha: json['commitSha'] as String,
        syncedAtMs: json['syncedAtMs'] as int,
      );
}

class SkillRepoSyncResult {
  const SkillRepoSyncResult({
    required this.skills,
    required this.updated,
    required this.repoKey,
  });

  final List<DiscoverableSkill> skills;
  final bool updated;
  final String repoKey;
}

/// Disk-backed skill repo cache (no in-memory tarball cache).
class SkillRepoDiskCacheService {
  SkillRepoDiskCacheService({SkillFetchService? fetch})
    : _fetch = fetch ?? SkillFetchService();

  final SkillFetchService _fetch;

  Filesystem get _fs => AppStorage.fs;

  static String repoKey(SkillRepo repo) => '${repo.owner}__${repo.name}';

  String get _cacheRoot => AppStorage.paths.skillRepoCacheDir;

  String _repoDirPath(SkillRepo repo) =>
      _fs.pathContext.join(_cacheRoot, repoKey(repo));

  /// Reads cached discoverable skills from disk; empty if none.
  Future<List<DiscoverableSkill>> readSkillsFromDisk(SkillRepo repo) async {
    final path = _fs.pathContext.join(_repoDirPath(repo), 'skills.json');
    final stat = await _fs.stat(path);
    if (!stat.isFile) return const [];
    try {
      final text = await _fs.readString(path);
      if (text == null) return const [];
      final list = json.decode(text) as List<dynamic>;
      final skills = list
          .map(
            (e) => DiscoverableSkill.fromJson(
              (e as Map<String, dynamic>).cast<String, Object?>(),
            ),
          )
          .toList();
      if (skills.isNotEmpty) return skills;
      return _recoverSkillsFromCachedFiles(repo, path);
    } catch (e) {
      appLogger.w(
        '[SkillRepoCache] corrupt skills.json for ${repo.fullName}: $e',
      );
      return const [];
    }
  }

  /// Rebuilds skills.json when git sync wrote files but discovery missed paths.
  Future<List<DiscoverableSkill>> _recoverSkillsFromCachedFiles(
    SkillRepo repo,
    String skillsPath,
  ) async {
    final entries = await _collectSkillMdEntriesFromDisk(repo);
    if (entries.isEmpty) return const [];

    final meta = await readMeta(repo);
    final skills = discoverSkillsInTarballEntries(
      entries: entries,
      repo: repo,
      resolvedBranch: meta?.resolvedBranch ?? repo.branch,
    );
    if (skills.isEmpty) return const [];

    appLogger.i(
      '[SkillRepoCache] recovered ${skills.length} skills for ${repo.fullName} from cached files',
    );
    await _fs.writeString(
      skillsPath,
      const JsonEncoder.withIndent('  ').convert(
        skills.map((s) => s.toJson()).toList(),
      ),
    );
    return skills;
  }

  Future<Map<String, Uint8List>> _collectSkillMdEntriesFromDisk(
    SkillRepo repo,
  ) async {
    final filesDir = _fs.pathContext.join(_repoDirPath(repo), 'files');
    final filesStat = await _fs.stat(filesDir);
    if (!filesStat.isDirectory) return const {};

    final out = <String, Uint8List>{};
    await _collectSkillMdEntriesRecursive(filesDir, filesDir, out);
    return out;
  }

  Future<void> _collectSkillMdEntriesRecursive(
    String root,
    String dir,
    Map<String, Uint8List> out,
  ) async {
    for (final entry in await _fs.listDir(dir)) {
      final fullPath = _fs.pathContext.join(dir, entry.name);
      if (entry.isDirectory) {
        await _collectSkillMdEntriesRecursive(root, fullPath, out);
        continue;
      }
      if (entry.name != 'SKILL.md') continue;
      final rel = _fs.pathContext
          .relative(fullPath, from: root)
          .replaceAll('\\', '/');
      if (rel.startsWith('..')) continue;
      final bytes = await _fs.readBytes(fullPath);
      if (bytes != null) {
        out[rel] = Uint8List.fromList(bytes);
      }
    }
  }

  Future<SkillRepoCacheMeta?> readMeta(SkillRepo repo) async {
    final path = _fs.pathContext.join(_repoDirPath(repo), 'meta.json');
    final stat = await _fs.stat(path);
    if (!stat.isFile) return null;
    try {
      final text = await _fs.readString(path);
      if (text == null) return null;
      return SkillRepoCacheMeta.fromJson(
        (json.decode(text) as Map<String, dynamic>).cast<String, Object?>(),
      );
    } catch (e) {
      appLogger.w(
        '[SkillRepoCache] corrupt meta.json for ${repo.fullName}: $e',
      );
      return null;
    }
  }

  Future<bool> _hasSnapshot(String repoDirPath) async {
    final skillsPath = _fs.pathContext.join(repoDirPath, 'skills.json');
    final filesPath = _fs.pathContext.join(repoDirPath, 'files');
    final skillsStat = await _fs.stat(skillsPath);
    final filesStat = await _fs.stat(filesPath);
    return skillsStat.isFile && filesStat.isDirectory;
  }

  /// Loads disk cache when fresh; otherwise downloads, writes files + skills, returns result.
  Future<SkillRepoSyncResult> ensureSynced(
    SkillRepo repo, {
    bool force = false,
  }) async {
    final key = repoKey(repo);
    final dirPath = _repoDirPath(repo);
    final meta = await readMeta(repo);

    if (!force &&
        meta != null &&
        meta.configuredBranch == repo.branch &&
        await _hasSnapshot(dirPath)) {
      final remoteSha = await _fetch.fetchBranchCommitSha(
        repo.owner,
        repo.name,
        meta.resolvedBranch,
      );
      if (remoteSha != null && remoteSha == meta.commitSha) {
        return SkillRepoSyncResult(
          skills: await readSkillsFromDisk(repo),
          updated: false,
          repoKey: key,
        );
      }
      if (remoteSha == null) {
        appLogger.d(
          '[SkillRepoCache] remote SHA unavailable for ${repo.fullName}, using disk cache',
        );
        return SkillRepoSyncResult(
          skills: await readSkillsFromDisk(repo),
          updated: false,
          repoKey: key,
        );
      }
    }

    try {
      final sourceDirPath = _fs.pathContext.join(dirPath, 'source');
      final downloaded = await _fetch.downloadRepoEntries(
        repo,
        fs: _fs,
        persistentGitPath: AppStorage.usesPosixPaths
            ? null
            : sourceDirPath,
      );
      final commitSha = downloaded.commitSha;
      final skills = discoverSkillsInTarballEntries(
        entries: downloaded.entries,
        repo: repo,
        resolvedBranch: downloaded.branch,
      );

      await _writeSnapshot(
        repo: repo,
        entries: downloaded.entries,
        skills: skills,
        resolvedBranch: downloaded.branch,
        commitSha: commitSha,
      );

      return SkillRepoSyncResult(skills: skills, updated: true, repoKey: key);
    } catch (e) {
      appLogger.w('[SkillRepoCache] sync failed for ${repo.fullName}: $e');
      if (await _hasSnapshot(dirPath)) {
        return SkillRepoSyncResult(
          skills: await readSkillsFromDisk(repo),
          updated: false,
          repoKey: key,
        );
      }
      rethrow;
    }
  }

  Future<void> _writeSnapshot({
    required SkillRepo repo,
    required Map<String, Uint8List> entries,
    required List<DiscoverableSkill> skills,
    required String resolvedBranch,
    required String commitSha,
  }) async {
    final repoDirPath = _repoDirPath(repo);
    final tmpPath = '$repoDirPath.tmp';
    await _fs.removeRecursive(tmpPath);
    final filesDirPath = _fs.pathContext.join(tmpPath, 'files');
    await _fs.ensureDir(filesDirPath);

    for (final entry in entries.entries) {
      final outPath = _fs.pathContext.join(filesDirPath, entry.key);
      await _fs.ensureDir(_fs.pathContext.dirname(outPath));
      await _fs.writeBytes(outPath, entry.value);
    }

    final skillsJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(skills.map((s) => s.toJson()).toList());
    await _fs.writeString(
      _fs.pathContext.join(tmpPath, 'skills.json'),
      skillsJson,
    );

    final meta = SkillRepoCacheMeta(
      configuredBranch: repo.branch,
      resolvedBranch: resolvedBranch,
      commitSha: commitSha,
      syncedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _fs.writeString(
      _fs.pathContext.join(tmpPath, 'meta.json'),
      const JsonEncoder.withIndent('  ').convert(meta.toJson()),
    );

    await _fs.ensureDir(_cacheRoot);
    final backupPath = '$repoDirPath.bak';
    await _fs.removeRecursive(backupPath);
    try {
      final repoStat = await _fs.stat(repoDirPath);
      if (repoStat.exists) {
        await _fs.rename(repoDirPath, backupPath);
      }
      await _fs.rename(tmpPath, repoDirPath);
      await _fs.removeRecursive(backupPath);
    } catch (e) {
      final backupStat = await _fs.stat(backupPath);
      if (backupStat.exists) {
        await _fs.removeRecursive(repoDirPath);
        await _fs.rename(backupPath, repoDirPath);
      }
      rethrow;
    } finally {
      await _fs.removeRecursive(tmpPath);
    }
  }

  /// Skill files for install/update from disk cache (`files/{directory}/**`).
  Future<Map<String, Uint8List>> readCachedSkillFiles(
    SkillRepo repo,
    String directory,
  ) async {
    final base = _fs.pathContext.join(_repoDirPath(repo), 'files', directory);
    final baseStat = await _fs.stat(base);
    if (!baseStat.isDirectory) return {};

    final out = <String, Uint8List>{};
    await _collectFilesRecursive(base, base, out);
    return out;
  }

  Future<void> _collectFilesRecursive(
    String root,
    String dir,
    Map<String, Uint8List> out,
  ) async {
    for (final entry in await _fs.listDir(dir)) {
      final fullPath = _fs.pathContext.join(dir, entry.name);
      if (entry.isDirectory) {
        await _collectFilesRecursive(root, fullPath, out);
        continue;
      }
      final rel = _fs.pathContext.relative(fullPath, from: root);
      if (rel.startsWith('..')) continue;
      final bytes = await _fs.readBytes(fullPath);
      if (bytes != null) {
        out[rel] = Uint8List.fromList(bytes);
      }
    }
  }

  Future<void> deleteRepoCache(SkillRepo repo) async {
    final dirPath = _repoDirPath(repo);
    final dirStat = await _fs.stat(dirPath);
    if (dirStat.exists) {
      await _fs.removeRecursive(dirPath);
    }
    await _fs.removeRecursive('$dirPath.tmp');
  }

  void close() => _fetch.close();
}
