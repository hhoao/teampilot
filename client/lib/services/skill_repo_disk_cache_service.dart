import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/skill.dart';
import '../utils/logger.dart';
import 'app_storage.dart';
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

  static String repoKey(SkillRepo repo) => '${repo.owner}__${repo.name}';

  String get _cacheRoot => AppStorage.skillRepoCacheDir;

  Directory _repoDir(SkillRepo repo) =>
      Directory(p.join(_cacheRoot, repoKey(repo)));

  /// Reads cached discoverable skills from disk; empty if none.
  Future<List<DiscoverableSkill>> readSkillsFromDisk(SkillRepo repo) async {
    final file = File(p.join(_repoDir(repo).path, 'skills.json'));
    if (!file.existsSync()) return const [];
    try {
      final list = json.decode(await file.readAsString()) as List<dynamic>;
      return list
          .map(
            (e) => DiscoverableSkill.fromJson(
              (e as Map<String, dynamic>).cast<String, Object?>(),
            ),
          )
          .toList();
    } catch (e) {
      appLogger.w('[SkillRepoCache] corrupt skills.json for ${repo.fullName}: $e');
      return const [];
    }
  }

  Future<SkillRepoCacheMeta?> readMeta(SkillRepo repo) async {
    final file = File(p.join(_repoDir(repo).path, 'meta.json'));
    if (!file.existsSync()) return null;
    try {
      return SkillRepoCacheMeta.fromJson(
        (json.decode(await file.readAsString()) as Map<String, dynamic>)
            .cast<String, Object?>(),
      );
    } catch (e) {
      appLogger.w('[SkillRepoCache] corrupt meta.json for ${repo.fullName}: $e');
      return null;
    }
  }

  bool _hasSnapshot(Directory repoDir) {
    return File(p.join(repoDir.path, 'skills.json')).existsSync() &&
        Directory(p.join(repoDir.path, 'files')).existsSync();
  }

  /// Loads disk cache when fresh; otherwise downloads, writes files + skills, returns result.
  Future<SkillRepoSyncResult> ensureSynced(
    SkillRepo repo, {
    bool force = false,
  }) async {
    final key = repoKey(repo);
    final dir = _repoDir(repo);
    final meta = await readMeta(repo);

    if (!force &&
        meta != null &&
        meta.configuredBranch == repo.branch &&
        _hasSnapshot(dir)) {
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
        appLogger.w(
          '[SkillRepoCache] SHA check unavailable for ${repo.fullName}, using disk cache',
        );
        return SkillRepoSyncResult(
          skills: await readSkillsFromDisk(repo),
          updated: false,
          repoKey: key,
        );
      }
    }

    try {
      final downloaded = await _fetch.downloadRepoEntries(repo);
      final commitSha =
          await _fetch.fetchBranchCommitSha(
            repo.owner,
            repo.name,
            downloaded.branch,
          ) ??
          '';
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

      return SkillRepoSyncResult(
        skills: skills,
        updated: true,
        repoKey: key,
      );
    } catch (e) {
      appLogger.w('[SkillRepoCache] sync failed for ${repo.fullName}: $e');
      if (_hasSnapshot(dir)) {
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
    final repoDir = _repoDir(repo);
    final tmp = Directory('${repoDir.path}.tmp');
    if (tmp.existsSync()) {
      await tmp.delete(recursive: true);
    }
    final filesDir = Directory(p.join(tmp.path, 'files'));
    await filesDir.create(recursive: true);

    for (final entry in entries.entries) {
      final out = File(p.join(filesDir.path, entry.key));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(entry.value, flush: true);
    }

    final skillsJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(skills.map((s) => s.toJson()).toList());
    await File(p.join(tmp.path, 'skills.json')).writeAsString(skillsJson);

    final meta = SkillRepoCacheMeta(
      configuredBranch: repo.branch,
      resolvedBranch: resolvedBranch,
      commitSha: commitSha,
      syncedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await File(
      p.join(tmp.path, 'meta.json'),
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(meta.toJson()));

    await Directory(_cacheRoot).create(recursive: true);
    final backup = Directory('${repoDir.path}.bak');
    if (backup.existsSync()) {
      await backup.delete(recursive: true);
    }
    try {
      if (repoDir.existsSync()) {
        await repoDir.rename(backup.path);
      }
      await tmp.rename(repoDir.path);
      if (backup.existsSync()) {
        await backup.delete(recursive: true);
      }
    } catch (e) {
      if (backup.existsSync()) {
        if (repoDir.existsSync()) {
          await repoDir.delete(recursive: true);
        }
        await backup.rename(repoDir.path);
      }
      rethrow;
    } finally {
      if (tmp.existsSync()) {
        await tmp.delete(recursive: true);
      }
    }
  }

  /// Skill files for install/update from disk cache (`files/{directory}/**`).
  Future<Map<String, Uint8List>> readCachedSkillFiles(
    SkillRepo repo,
    String directory,
  ) async {
    final base = Directory(p.join(_repoDir(repo).path, 'files', directory));
    if (!base.existsSync()) return {};

    final out = <String, Uint8List>{};
    await for (final entity in base.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: base.path);
      if (rel.startsWith('..')) continue;
      out[rel] = await entity.readAsBytes();
    }
    return out;
  }

  Future<void> deleteRepoCache(SkillRepo repo) async {
    final dir = _repoDir(repo);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
    final tmp = Directory('${dir.path}.tmp');
    if (tmp.existsSync()) {
      await tmp.delete(recursive: true);
    }
  }

  void close() => _fetch.close();
}
