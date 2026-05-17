import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/skill.dart';
import '../utils/logger.dart';
import 'app_storage.dart';
import 'flashskyai_storage_roots.dart';
import 'remote_file_store.dart';

class SkillRepoService {
  SkillRepoService({FlashskyaiStorageRoots? storageRoots})
    : _storageRoots = storageRoots;

  final FlashskyaiStorageRoots? _storageRoots;

  static const _defaultRepos = [
    SkillRepo(owner: 'anthropics', name: 'skills', branch: 'main'),
    SkillRepo(
      owner: 'ComposioHQ',
      name: 'awesome-claude-skills',
      branch: 'master',
    ),
    SkillRepo(owner: 'cexll', name: 'myclaude', branch: 'master'),
    SkillRepo(owner: 'JimLiu', name: 'baoyu-skills', branch: 'main'),
  ];

  Future<String> _configPath() async {
    if (_storageRoots != null) {
      return (await _storageRoots!.resolve()).skillReposConfigPath;
    }
    return AppStorage.skillReposConfigPath;
  }

  Future<List<SkillRepo>> loadRepos() async {
    final cache = await _readManifest();
    if (cache.isEmpty) {
      await _initDefaults();
      return _defaultRepos.toList();
    }
    final reposJson = cache['repos'] as List<dynamic>?;
    if (reposJson == null) return _defaultRepos.toList();
    return reposJson
        .map((r) => SkillRepo.fromJson(r as Map<String, Object?>))
        .toList();
  }

  Future<void> saveRepos(List<SkillRepo> repos) async {
    final cache = await _readManifest();
    cache['repos'] = repos.map((r) => r.toJson()).toList();
    await _writeManifest(cache);
  }

  Future<void> addRepo(SkillRepo repo) async {
    final repos = await loadRepos();
    if (repos.any((r) => r.owner == repo.owner && r.name == repo.name)) return;
    repos.add(repo);
    await saveRepos(repos);
  }

  Future<void> removeRepo(String owner, String name) async {
    final repos = await loadRepos();
    repos.removeWhere((r) => r.owner == owner && r.name == name);
    await saveRepos(repos);
  }

  Future<void> setEnabled(String owner, String name, bool enabled) async {
    final repos = await loadRepos();
    final idx = repos.indexWhere((r) => r.owner == owner && r.name == name);
    if (idx < 0) return;
    repos[idx] = repos[idx].copyWith(enabled: enabled);
    await saveRepos(repos);
  }

  Future<void> updateBranch(String owner, String name, String branch) async {
    final repos = await loadRepos();
    final idx = repos.indexWhere((r) => r.owner == owner && r.name == name);
    if (idx < 0) return;
    repos[idx] = repos[idx].copyWith(branch: branch);
    await saveRepos(repos);
  }

  Future<void> _initDefaults() async {
    final cache = await _readManifest();
    cache['repos'] = _defaultRepos.map((r) => r.toJson()).toList();
    await _writeManifest(cache);
  }

  Future<RemoteFileStore?> _remote() async {
    if (_storageRoots == null) return null;
    final snap = await _storageRoots!.resolve();
    return snap.storageIsRemote ? snap.remoteFileStore : null;
  }

  Future<Map<String, Object?>> _readManifest() async {
    final path = await _configPath();
    final remote = await _remote();
    if (remote != null) {
      final text = await remote.readFile(path);
      if (text == null || text.isEmpty) return {};
      try {
        return (json.decode(text) as Map<String, dynamic>)
            .cast<String, Object?>();
      } on FormatException catch (e) {
        appLogger.w('[SkillRepoService] Corrupt skills.json, resetting: $e');
        return {};
      }
    }

    final file = File(path);
    if (!file.existsSync()) return {};
    try {
      final content = await file.readAsString();
      return (json.decode(content) as Map<String, dynamic>)
          .cast<String, Object?>();
    } on FormatException catch (e) {
      appLogger.w('[SkillRepoService] Corrupt skills.json, resetting: $e');
      return {};
    } on FileSystemException catch (e) {
      appLogger.w('[SkillRepoService] Cannot read skills.json: $e');
      return {};
    }
  }

  Future<void> _writeManifest(Map<String, Object?> data) async {
    final path = await _configPath();
    final text = const JsonEncoder.withIndent('  ').convert(data);
    final remote = await _remote();
    if (remote != null) {
      final posix = p.Context(style: p.Style.posix);
      final parent = posix.dirname(path);
      if (parent.isNotEmpty && parent != '.') {
        await remote.ensureDirectory(parent);
      }
      await remote.writeFile(path, text);
      return;
    }
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }
}
