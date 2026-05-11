import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/skill.dart';
import 'app_storage.dart';

class SkillManifestException implements Exception {
  SkillManifestException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => 'SkillManifestException: $message';
}

class SkillManifestService {
  SkillManifestService({String? rootDir}) : _rootDir = rootDir;

  final String? _rootDir;

  String get _root => _rootDir ?? AppStorage.flashskyaiDir;
  String get skillsDir => p.join(_root, 'skills');
  String get backupsDir => p.join(_root, 'skill-backups');
  String get _manifestPath => p.join(skillsDir, 'manifest.json');

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

  /// Returns pruned backups (so caller can delete their on-disk payloads).
  Future<List<SkillBackup>> pruneBackups({int keep = 20}) async {
    final m = await _read();
    final list = ((m['backups'] as List<dynamic>?) ?? <dynamic>[])
        .map((e) => SkillBackup.fromJson((e as Map).cast<String, Object?>()))
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
    final file = File(_manifestPath);
    if (!file.existsSync()) {
      return <String, Object?>{'version': 1, 'skills': [], 'backups': []};
    }
    try {
      final text = await file.readAsString();
      final parsed = json.decode(text);
      if (parsed is! Map) {
        throw SkillManifestException('manifest root is not an object');
      }
      return parsed.cast<String, Object?>();
    } on FormatException catch (e) {
      throw SkillManifestException('manifest.json is corrupt', e);
    }
  }

  Future<void> _write(Map<String, Object?> data) async {
    final dir = Directory(skillsDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    data['version'] = data['version'] ?? 1;
    final file = File(_manifestPath);
    final text = const JsonEncoder.withIndent('  ').convert(data);
    await file.writeAsString(text);
  }
}
