import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/skill.dart';
import 'app_storage.dart';
import 'flashskyai_storage_roots.dart';
import 'remote_file_store.dart';

class SkillManifestException implements Exception {
  SkillManifestException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => 'SkillManifestException: $message';
}

class _SkillPaths {
  const _SkillPaths({
    required this.skillsDir,
    required this.backupsDir,
    required this.manifestPath,
    this.remote,
  });

  final String skillsDir;
  final String backupsDir;
  final String manifestPath;
  final RemoteFileStore? remote;

  bool get isRemote => remote != null;
}

class SkillManifestService {
  SkillManifestService({String? rootDir, FlashskyaiStorageRoots? storageRoots})
    : _rootDir = rootDir,
      _storageRoots = storageRoots;

  final String? _rootDir;
  final FlashskyaiStorageRoots? _storageRoots;

  Future<_SkillPaths> _paths() async {
    if (_storageRoots != null) {
      final snap = await _storageRoots.resolve();
      if (snap.storageIsRemote && snap.remoteFileStore != null) {
        final posix = p.Context(style: p.Style.posix);
        return _SkillPaths(
          skillsDir: snap.skillsRoot,
          backupsDir: snap.skillBackupsDir,
          manifestPath: posix.join(snap.skillsRoot, 'manifest.json'),
          remote: snap.remoteFileStore,
        );
      }
    }
    final root = _rootDir ?? AppStorage.paths.basePath;
    final ctx = AppStorage.fs.pathContext;
    final skillsDir = ctx.join(root, 'skills');
    return _SkillPaths(
      skillsDir: skillsDir,
      backupsDir: ctx.join(root, 'skill-backups'),
      manifestPath: ctx.join(skillsDir, 'manifest.json'),
    );
  }

  String get skillsDir {
    final root = _rootDir ?? AppStorage.paths.basePath;
    return AppStorage.fs.pathContext.join(root, 'skills');
  }

  String get backupsDir {
    final root = _rootDir ?? AppStorage.paths.basePath;
    return AppStorage.fs.pathContext.join(root, 'skill-backups');
  }

  Future<List<Skill>> loadSkills() async {
    final m = await _read();
    final list = (m['skills'] as List<dynamic>?) ?? const [];
    return list
        .map((e) => Skill.fromJson((e as Map).cast<String, Object?>()))
        .toList();
  }

  Future<List<SkillBackup>> loadBackups() async {
    final m = await _read();
    final list = (m['backups'] as List<dynamic>?) ?? const [];
    return list
        .map((e) => SkillBackup.fromJson((e as Map).cast<String, Object?>()))
        .toList();
  }

  Future<void> upsertSkill(Skill s) async {
    final m = await _read();
    final list = ((m['skills'] as List<dynamic>?) ?? <dynamic>[]).toList();
    final idx = list.indexWhere((e) => (e as Map)['id'] == s.id);
    if (idx >= 0) {
      list[idx] = s.toJson();
    } else {
      list.add(s.toJson());
    }
    m['skills'] = list;
    await _write(m);
  }

  Future<void> removeSkill(String id) async {
    final m = await _read();
    final list = ((m['skills'] as List<dynamic>?) ?? <dynamic>[]).toList();
    list.removeWhere((e) => (e as Map)['id'] == id);
    m['skills'] = list;
    await _write(m);
  }

  Future<void> addBackup(SkillBackup b) async {
    final m = await _read();
    final list = ((m['backups'] as List<dynamic>?) ?? <dynamic>[]).toList();
    list.add(b.toJson());
    m['backups'] = list;
    await _write(m);
  }

  Future<void> removeBackup(String backupId) async {
    final m = await _read();
    final list = ((m['backups'] as List<dynamic>?) ?? <dynamic>[]).toList();
    list.removeWhere((e) => (e as Map)['backupId'] == backupId);
    m['backups'] = list;
    await _write(m);
  }

  Future<List<SkillBackup>> pruneBackups({int keep = 20}) async {
    final m = await _read();
    final list =
        ((m['backups'] as List<dynamic>?) ?? <dynamic>[])
            .map(
              (e) => SkillBackup.fromJson((e as Map).cast<String, Object?>()),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (list.length <= keep) return const [];
    final dropped = list.sublist(keep);
    final kept = list.take(keep).toList();
    m['backups'] = kept.map((b) => b.toJson()).toList();
    await _write(m);
    return dropped;
  }

  Future<Map<String, Object?>> _read() async {
    final paths = await _paths();
    if (paths.isRemote) {
      final text = await paths.remote!.readFile(paths.manifestPath);
      if (text == null || text.isEmpty) {
        return <String, Object?>{'version': 1, 'skills': [], 'backups': []};
      }
      try {
        final parsed = json.decode(text);
        if (parsed is! Map) {
          throw SkillManifestException('manifest root is not an object');
        }
        return parsed.cast<String, Object?>();
      } on FormatException catch (e) {
        throw SkillManifestException('manifest.json is corrupt', e);
      }
    }

    final raw = await AppStorage.fs.readString(paths.manifestPath);
    if (raw == null || raw.isEmpty) {
      return <String, Object?>{'version': 1, 'skills': [], 'backups': []};
    }
    try {
      final parsed = json.decode(raw);
      if (parsed is! Map) {
        throw SkillManifestException('manifest root is not an object');
      }
      return parsed.cast<String, Object?>();
    } on FormatException catch (e) {
      throw SkillManifestException('manifest.json is corrupt', e);
    }
  }

  Future<void> _write(Map<String, Object?> data) async {
    final paths = await _paths();
    data['version'] = data['version'] ?? 1;
    final text = const JsonEncoder.withIndent('  ').convert(data);
    if (paths.isRemote) {
      final store = paths.remote!;
      await store.ensureDirectory(paths.skillsDir);
      await store.writeFile(paths.manifestPath, text);
      return;
    }
    await AppStorage.fs.ensureDir(paths.skillsDir);
    await AppStorage.fs.atomicWrite(paths.manifestPath, text);
  }

  Future<String> resolveSkillsDir() async => (await _paths()).skillsDir;

  Future<String> resolveBackupsDir() async => (await _paths()).backupsDir;

  Future<RemoteFileStore?> remoteFileStore() async => (await _paths()).remote;
}
