import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/skill.dart';
import '../utils/logger.dart';
import 'skill_fetch_service.dart';
import 'skill_manifest_service.dart';

class SkillInstallException implements Exception {
  SkillInstallException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => 'SkillInstallException: $message';
}

class SkillInstallService {
  SkillInstallService({required this.manifest, SkillFetchService? fetch})
    : fetch = fetch ?? SkillFetchService();

  final SkillManifestService manifest;
  final SkillFetchService fetch;
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

  String _skillPath(String basename) => p.join(manifest.skillsDir, basename);

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
    final dir = Directory(_skillPath(basename));
    if (dir.existsSync()) {
      if (!overwrite) {
        throw SkillInstallException(
          'A skill already exists at ${dir.path}',
        );
      }
      await dir.delete(recursive: true);
    }
    dir.createSync(recursive: true);

    for (final entry in files.entries) {
      final target = File(p.join(dir.path, entry.key));
      target.parent.createSync(recursive: true);
      await target.writeAsBytes(entry.value, flush: true);
    }

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
    final files = await fetch.downloadSkillFiles(repo, d.directory);
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
    final src = Directory(_skillPath(skill.directory));
    if (!src.existsSync()) {
      await manifest.removeSkill(skill.id);
      throw SkillInstallException(
        'Skill directory ${src.path} missing on disk',
      );
    }
    final backupsDir = Directory(manifest.backupsDir);
    if (!backupsDir.existsSync()) backupsDir.createSync(recursive: true);
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final backupId = '${skill.directory}-$ts';
    final target = Directory(p.join(backupsDir.path, backupId));
    await _moveDir(src, target);
    final backup = SkillBackup(
      backupId: backupId,
      backupPath: target.path,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      skill: skill,
    );
    await manifest.removeSkill(skill.id);
    await manifest.addBackup(backup);
    final dropped = await manifest.pruneBackups(keep: backupRetention);
    for (final d in dropped) {
      try {
        final dir = Directory(d.backupPath);
        if (dir.existsSync()) await dir.delete(recursive: true);
      } catch (e) {
        appLogger.w(
          '[skills] failed to delete pruned backup ${d.backupPath}: $e',
        );
      }
    }
    return backup;
  }

  Future<Skill> restoreBackup(SkillBackup backup) async {
    final src = Directory(backup.backupPath);
    if (!src.existsSync()) {
      throw SkillInstallException('Backup payload missing at ${src.path}');
    }
    final target = Directory(_skillPath(backup.skill.directory));
    if (target.existsSync()) {
      throw SkillInstallException('Target ${target.path} already exists');
    }
    await _moveDir(src, target);
    final restored = backup.skill.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await manifest.upsertSkill(restored);
    await manifest.removeBackup(backup.backupId);
    return restored;
  }

  Future<void> deleteBackup(SkillBackup backup) async {
    final dir = Directory(backup.backupPath);
    if (dir.existsSync()) await dir.delete(recursive: true);
    await manifest.removeBackup(backup.backupId);
  }

  Future<List<UnmanagedSkill>> scanUnmanaged() async {
    final dir = Directory(manifest.skillsDir);
    if (!dir.existsSync()) return const [];
    final installed = (await manifest.loadSkills())
        .map((s) => s.directory)
        .toSet();
    final out = <UnmanagedSkill>[];
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final basename = p.basename(entity.path);
      if (installed.contains(basename)) continue;
      final skillMd = File(p.join(entity.path, 'SKILL.md'));
      if (!skillMd.existsSync()) continue;
      try {
        final fm = parseSkillFrontmatter(await skillMd.readAsString());
        out.add(
          UnmanagedSkill(
            directory: basename,
            name: fm.name,
            description: fm.description,
            path: entity.path,
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
    for (final u in skills) {
      final skillMd = File(p.join(u.path, 'SKILL.md'));
      final bytes = await skillMd.readAsBytes();
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
      if (s.repoOwner == null ||
          s.repoName == null ||
          s.repoBranch == null) {
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
      final fullPayload = await fetch.fetchTarball(repo);
      String? matchPath;
      for (final key in fullPayload.entries.keys) {
        final parts = key.split('/');
        if (parts.length >= 2 &&
            parts.last == 'SKILL.md' &&
            parts[parts.length - 2] == skill.directory) {
          matchPath = parts.sublist(0, parts.length - 1).join('/');
          break;
        }
      }
      if (matchPath == null) {
        throw SkillInstallException(
          'Could not locate ${skill.directory} in ${repo.fullName}',
        );
      }
      final files = await fetch.downloadSkillFiles(repo, matchPath);
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

  Future<void> _moveDir(Directory src, Directory target) async {
    try {
      await src.rename(target.path);
    } on FileSystemException {
      await _copyDir(src, target);
      await src.delete(recursive: true);
    }
  }

  Future<void> _copyDir(Directory src, Directory target) async {
    if (!target.existsSync()) target.createSync(recursive: true);
    await for (final entity in src.list(
      recursive: true,
      followLinks: false,
    )) {
      final rel = p.relative(entity.path, from: src.path);
      final to = p.join(target.path, rel);
      if (entity is Directory) {
        Directory(to).createSync(recursive: true);
      } else if (entity is File) {
        Directory(p.dirname(to)).createSync(recursive: true);
        await entity.copy(to);
      }
    }
  }
}
