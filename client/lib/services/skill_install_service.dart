import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/skill.dart';
import '../utils/logger.dart';
import 'app_storage.dart';
import 'skill_fetch_service.dart';
import 'skill_manifest_service.dart';
import 'skill_repo_disk_cache_service.dart';

class SkillInstallException implements Exception {
  SkillInstallException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => 'SkillInstallException: $message';
}

class SkillInstallService {
  SkillInstallService({
    required this.manifest,
    SkillFetchService? fetch,
    SkillRepoDiskCacheService? repoCache,
  }) : fetch = fetch ?? SkillFetchService(),
       repoCache = repoCache ?? SkillRepoDiskCacheService(fetch: fetch);

  final SkillManifestService manifest;
  final SkillFetchService fetch;
  final SkillRepoDiskCacheService repoCache;
  static const int backupRetention = 20;

  String _idFor({
    String? repoOwner,
    String? repoName,
    required String basename,
  }) {
    if (repoOwner != null && repoName != null) {
      return '$repoOwner/$repoName:$basename';
    }
    return 'local:$basename';
  }

  Future<void> _installFiles({
    required String basename,
    required Map<String, Uint8List> files,
    required bool overwrite,
  }) async {
    final remote = await manifest.remoteFileStore();
    final skillsDir = await manifest.resolveSkillsDir();
    if (remote != null) {
      final posix = p.Context(style: p.Style.posix);
      final base = posix.join(skillsDir, basename);
      if (!overwrite && await remote.fileExists(posix.join(base, 'SKILL.md'))) {
        throw SkillInstallException('A skill already exists at $base');
      }
      await remote.removeRecursive(base);
      await remote.ensureDirectory(base);
      for (final entry in files.entries) {
        final target = posix.join(base, entry.key);
        final parent = posix.dirname(target);
        if (parent.isNotEmpty && parent != '.' && parent != '/') {
          await remote.ensureDirectory(parent);
        }
        await remote.writeBytes(target, entry.value);
      }
      return;
    }

    final fs = AppStorage.fs;
    final ctx = fs.pathContext;
    final base = ctx.join(skillsDir, basename);
    if ((await fs.stat(base)).exists) {
      if (!overwrite) {
        throw SkillInstallException('A skill already exists at $base');
      }
      await fs.removeRecursive(base);
    }
    await fs.ensureDir(base);
    for (final entry in files.entries) {
      final target = ctx.join(base, entry.key);
      await fs.ensureDir(ctx.dirname(target));
      await fs.writeBytes(target, entry.value);
    }
  }

  String _hashSkillMd(Map<String, Uint8List> files) {
    final bytes = files['SKILL.md'];
    if (bytes == null) {
      throw SkillInstallException('payload missing SKILL.md');
    }
    return sha256.convert(bytes).toString();
  }

  Future<Skill> installLocal({
    required String basename,
    required Map<String, Uint8List> files,
    required String? repoOwner,
    required String? repoName,
    required String? repoBranch,
    required String? readmeUrl,
    required String name,
    required String description,
    bool overwrite = false,
  }) async {
    await _installFiles(basename: basename, files: files, overwrite: overwrite);

    final hash = _hashSkillMd(files);
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _idFor(
      repoOwner: repoOwner,
      repoName: repoName,
      basename: basename,
    );
    final skill = Skill(
      id: id,
      name: name,
      description: description,
      directory: basename,
      repoOwner: repoOwner,
      repoName: repoName,
      repoBranch: repoBranch,
      readmeUrl: readmeUrl,
      enabled: true,
      installedAt: now,
      contentHash: hash,
      updatedAt: now,
    );
    await manifest.upsertSkill(skill);
    return skill;
  }

  Future<Skill> installFromDiscovery(
    DiscoverableSkill d, {
    bool overwrite = false,
  }) async {
    final repo = SkillRepo(
      owner: d.repoOwner,
      name: d.repoName,
      branch: d.repoBranch,
    );
    final files = await _loadSkillFiles(repo, d.directory);
    final basename = p.basename(d.directory);
    return installLocal(
      basename: basename,
      files: files,
      repoOwner: d.repoOwner,
      repoName: d.repoName,
      repoBranch: d.repoBranch,
      readmeUrl: d.readmeUrl,
      name: d.name,
      description: d.description,
      overwrite: overwrite,
    );
  }

  /// Each top-level subdirectory containing SKILL.md is installed as a
  /// separate `local` skill.
  Future<List<Skill>> installFromZip(
    File zipFile, {
    bool overwrite = false,
  }) async {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final byDir = <String, Map<String, Uint8List>>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      final parts = file.name.split('/');
      if (parts.length < 2) continue;
      if (parts.any((s) => s == '__MACOSX')) continue;
      final dir = parts.first;
      final rel = parts.sublist(1).join('/');
      (byDir[dir] ??= {})[rel] = Uint8List.fromList(file.content as List<int>);
    }
    final installed = <Skill>[];
    for (final entry in byDir.entries) {
      final files = entry.value;
      if (!files.containsKey('SKILL.md')) continue;
      try {
        final fm = parseSkillFrontmatter(
          String.fromCharCodes(files['SKILL.md']!),
        );
        installed.add(
          await installLocal(
            basename: entry.key,
            files: files,
            repoOwner: null,
            repoName: null,
            repoBranch: null,
            readmeUrl: null,
            name: fm.name,
            description: fm.description,
            overwrite: overwrite,
          ),
        );
      } on SkillParseException catch (e) {
        appLogger.w('[skills] zip entry ${entry.key} skipped: ${e.message}');
      }
    }
    return installed;
  }

  Future<SkillBackup> uninstall(Skill skill) async {
    final remote = await manifest.remoteFileStore();
    final skillsDir = await manifest.resolveSkillsDir();
    final backupsDirPath = await manifest.resolveBackupsDir();
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final backupId = '${skill.directory}-$ts';
    final targetPath = p.join(backupsDirPath, backupId);

    if (remote != null) {
      final posix = p.Context(style: p.Style.posix);
      final src = posix.join(skillsDir, skill.directory);
      if (!await remote.fileExists(posix.join(src, 'SKILL.md'))) {
        await manifest.removeSkill(skill.id);
        throw SkillInstallException('Skill directory $src missing on disk');
      }
      await remote.ensureDirectory(backupsDirPath);
      await remote.removeRecursive(targetPath);
      await remote.movePath(src, targetPath);
    } else {
      final fs = AppStorage.fs;
      final ctx = fs.pathContext;
      final src = ctx.join(skillsDir, skill.directory);
      if (!(await fs.stat(ctx.join(src, 'SKILL.md'))).isFile) {
        await manifest.removeSkill(skill.id);
        throw SkillInstallException('Skill directory $src missing on disk');
      }
      await fs.ensureDir(backupsDirPath);
      await fs.removeRecursive(targetPath);
      await _movePath(src, targetPath);
    }
    final backup = SkillBackup(
      backupId: backupId,
      backupPath: targetPath,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      skill: skill,
    );
    await manifest.removeSkill(skill.id);
    await manifest.addBackup(backup);
    final dropped = await manifest.pruneBackups(keep: backupRetention);
    for (final d in dropped) {
      try {
        if (remote != null) {
          await remote.removeRecursive(d.backupPath);
        } else {
          await AppStorage.fs.removeRecursive(d.backupPath);
        }
      } catch (e) {
        appLogger.w(
          '[skills] failed to delete pruned backup ${d.backupPath}: $e',
        );
      }
    }
    return backup;
  }

  Future<Skill> restoreBackup(SkillBackup backup) async {
    final remote = await manifest.remoteFileStore();
    final skillsDir = await manifest.resolveSkillsDir();
    final targetPath = p.join(skillsDir, backup.skill.directory);

    if (remote != null) {
      final posix = p.Context(style: p.Style.posix);
      if (!await remote.fileExists(posix.join(backup.backupPath, 'SKILL.md'))) {
        throw SkillInstallException(
          'Backup payload missing at ${backup.backupPath}',
        );
      }
      if (await remote.fileExists(posix.join(targetPath, 'SKILL.md'))) {
        throw SkillInstallException('Target $targetPath already exists');
      }
      await remote.movePath(backup.backupPath, targetPath);
    } else {
      final fs = AppStorage.fs;
      final ctx = fs.pathContext;
      if (!(await fs.stat(ctx.join(backup.backupPath, 'SKILL.md'))).isFile) {
        throw SkillInstallException(
          'Backup payload missing at ${backup.backupPath}',
        );
      }
      if ((await fs.stat(ctx.join(targetPath, 'SKILL.md'))).isFile) {
        throw SkillInstallException('Target $targetPath already exists');
      }
      await _movePath(backup.backupPath, targetPath);
    }
    final restored = backup.skill.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await manifest.upsertSkill(restored);
    await manifest.removeBackup(backup.backupId);
    return restored;
  }

  Future<void> deleteBackup(SkillBackup backup) async {
    final remote = await manifest.remoteFileStore();
    if (remote != null) {
      await remote.removeRecursive(backup.backupPath);
    } else {
      await AppStorage.fs.removeRecursive(backup.backupPath);
    }
    await manifest.removeBackup(backup.backupId);
  }

  Future<List<UnmanagedSkill>> scanUnmanaged() async {
    final fs = AppStorage.fs;
    final ctx = fs.pathContext;
    final skillsDir = manifest.skillsDir;
    if (!(await fs.stat(skillsDir)).isDirectory) return const [];

    final installed = (await manifest.loadSkills())
        .map((s) => s.directory)
        .toSet();
    final out = <UnmanagedSkill>[];
    for (final entry in await fs.listDir(skillsDir)) {
      if (!entry.isDirectory) continue;
      if (installed.contains(entry.name)) continue;
      final dirPath = ctx.join(skillsDir, entry.name);
      final skillMdPath = ctx.join(dirPath, 'SKILL.md');
      if (!(await fs.stat(skillMdPath)).isFile) continue;
      try {
        final text = await fs.readString(skillMdPath);
        if (text == null) continue;
        final fm = parseSkillFrontmatter(text);
        out.add(
          UnmanagedSkill(
            directory: entry.name,
            name: fm.name,
            description: fm.description,
            path: dirPath,
          ),
        );
      } on SkillParseException {
        continue;
      }
    }
    return out;
  }

  Future<List<Skill>> importUnmanaged(List<UnmanagedSkill> skills) async {
    final added = <Skill>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    final fs = AppStorage.fs;
    final ctx = fs.pathContext;
    for (final u in skills) {
      final skillMdPath = ctx.join(u.path, 'SKILL.md');
      final bytes = await fs.readBytes(skillMdPath);
      if (bytes == null) continue;
      final hash = sha256.convert(bytes).toString();
      final skill = Skill(
        id: 'local:${u.directory}',
        name: u.name,
        description: u.description ?? '',
        directory: u.directory,
        enabled: true,
        installedAt: now,
        updatedAt: now,
        contentHash: hash,
      );
      await manifest.upsertSkill(skill);
      added.add(skill);
    }
    return added;
  }

  Future<List<SkillUpdateInfo>> checkUpdates(List<Skill> installed) async {
    final updates = <SkillUpdateInfo>[];
    for (final s in installed) {
      if (s.repoOwner == null || s.repoName == null || s.repoBranch == null) {
        continue;
      }
      try {
        final remote = await fetch.fetchRawSkillMd(
          owner: s.repoOwner!,
          name: s.repoName!,
          branch: s.repoBranch!,
          directory: s.directory,
        );
        if (remote == null) continue;
        final remoteHash = sha256.convert(utf8.encode(remote)).toString();
        if (remoteHash != s.contentHash) {
          updates.add(
            SkillUpdateInfo(
              id: s.id,
              name: s.name,
              currentHash: s.contentHash,
              remoteHash: remoteHash,
            ),
          );
        }
      } catch (e) {
        appLogger.w('[skills] update check failed for ${s.id}: $e');
      }
    }
    return updates;
  }

  Future<Skill> updateSkill(Skill skill) async {
    if (skill.repoOwner == null ||
        skill.repoName == null ||
        skill.repoBranch == null) {
      throw SkillInstallException(
        'Skill ${skill.id} has no repo origin to update from',
      );
    }
    final backup = await uninstall(skill);
    try {
      final repo = SkillRepo(
        owner: skill.repoOwner!,
        name: skill.repoName!,
        branch: skill.repoBranch!,
      );
      await repoCache.ensureSynced(repo, force: true);
      final cached = await repoCache.readSkillsFromDisk(repo);
      DiscoverableSkill? match;
      for (final d in cached) {
        if (p.basename(d.directory) == skill.directory) {
          match = d;
          break;
        }
      }
      if (match == null) {
        throw SkillInstallException(
          'Could not locate ${skill.directory} in ${repo.fullName}',
        );
      }
      final files = await _loadSkillFiles(repo, match.directory);
      final fm = parseSkillFrontmatter(
        String.fromCharCodes(files['SKILL.md']!),
      );
      final updated = await installLocal(
        basename: skill.directory,
        files: files,
        repoOwner: skill.repoOwner,
        repoName: skill.repoName,
        repoBranch: skill.repoBranch,
        readmeUrl: skill.readmeUrl,
        name: fm.name,
        description: fm.description,
        overwrite: true,
      );
      return updated;
    } catch (e) {
      try {
        await restoreBackup(backup);
      } catch (_) {}
      rethrow;
    }
  }

  Future<Map<String, Uint8List>> _loadSkillFiles(
    SkillRepo repo,
    String directory,
  ) async {
    var files = await repoCache.readCachedSkillFiles(repo, directory);
    if (files.isNotEmpty) return files;
    await repoCache.ensureSynced(repo);
    files = await repoCache.readCachedSkillFiles(repo, directory);
    if (files.isNotEmpty) return files;
    return fetch.downloadSkillFilesFromNetwork(repo, directory);
  }

  Future<void> _movePath(String src, String dest) async {
    final fs = AppStorage.fs;
    try {
      await fs.rename(src, dest);
    } on Object {
      await fs.copyTree(source: src, destination: dest);
      await fs.removeRecursive(src);
    }
  }
}
