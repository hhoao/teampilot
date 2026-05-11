# Skill Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a full skill management feature (install, uninstall, discover, toggle, update, backup/restore) with sidebar navigation, modeled after cc-switch.

**Architecture:** Models → Services → Cubit → Pages → Sidebar/Router. Filesystem SSOT at `AppStorage.flashskyaiDir/skills/` with `skills.json` manifest cache. Symlinks from `~/.flashskyai/skills/` to SSOT.

**Tech Stack:** Flutter/Dart, flutter_bloc, go_router, dart:io HttpClient, crypto, archive

---

### Task 1: Add Dependencies

**Files:**
- Modify: `client/pubspec.yaml`

- [ ] **Step 1: Add `http`, `crypto`, and `archive` packages**

```bash
cd client && flutter pub add http crypto archive
```

- [ ] **Step 2: Verify dependencies resolve**

```bash
cd client && flutter pub get
```

Expected: exits 0, no errors.

- [ ] **Step 3: Commit**

```bash
git add client/pubspec.yaml client/pubspec.lock
git commit -m "chore: add http, crypto, archive dependencies for skill management"
```

---

### Task 2: Create Skill, SkillRepo, DiscoverableSkill Models

**Files:**
- Create: `client/lib/models/skill.dart`

- [ ] **Step 1: Write the Skill model**

```dart
import 'dart:convert';

class Skill {
  const Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.directory,
    this.repoOwner,
    this.repoName,
    this.repoBranch,
    this.readmeUrl,
    this.enabled = true,
    required this.installedAt,
    this.contentHash,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final String directory;
  final String? repoOwner;
  final String? repoName;
  final String? repoBranch;
  final String? readmeUrl;
  final bool enabled;
  final int installedAt;
  final String? contentHash;
  final int updatedAt;

  String get source =>
      repoOwner != null ? '$repoOwner/$repoName' : 'local';

  Skill copyWith({
    String? id,
    String? name,
    String? description,
    String? directory,
    String? repoOwner,
    String? repoName,
    String? repoBranch,
    String? readmeUrl,
    bool? enabled,
    int? installedAt,
    String? contentHash,
    int? updatedAt,
    bool clearRepo = false,
  }) {
    return Skill(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      directory: directory ?? this.directory,
      repoOwner: clearRepo ? null : (repoOwner ?? this.repoOwner),
      repoName: clearRepo ? null : (repoName ?? this.repoName),
      repoBranch: clearRepo ? null : (repoBranch ?? this.repoBranch),
      readmeUrl: clearRepo ? null : (readmeUrl ?? this.readmeUrl),
      enabled: enabled ?? this.enabled,
      installedAt: installedAt ?? this.installedAt,
      contentHash: contentHash ?? this.contentHash,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'directory': directory,
    'repoOwner': repoOwner,
    'repoName': repoName,
    'repoBranch': repoBranch,
    'readmeUrl': readmeUrl,
    'enabled': enabled,
    'installedAt': installedAt,
    'contentHash': contentHash,
    'updatedAt': updatedAt,
  };

  factory Skill.fromJson(Map<String, dynamic> json) => Skill(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    directory: json['directory'] as String,
    repoOwner: json['repoOwner'] as String?,
    repoName: json['repoName'] as String?,
    repoBranch: json['repoBranch'] as String?,
    readmeUrl: json['readmeUrl'] as String?,
    enabled: json['enabled'] as bool? ?? true,
    installedAt: json['installedAt'] as int,
    contentHash: json['contentHash'] as String?,
    updatedAt: json['updatedAt'] as int,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Skill &&
          id == other.id &&
          name == other.name &&
          directory == other.directory &&
          enabled == other.enabled &&
          contentHash == other.contentHash;

  @override
  int get hashCode => Object.hash(id, name, directory, enabled, contentHash);
}

class SkillRepo {
  const SkillRepo({
    required this.owner,
    required this.name,
    this.branch = 'main',
    this.enabled = true,
  });

  final String owner;
  final String name;
  final String branch;
  final bool enabled;

  String get fullName => '$owner/$name';

  SkillRepo copyWith({String? owner, String? name, String? branch, bool? enabled}) =>
      SkillRepo(
        owner: owner ?? this.owner,
        name: name ?? this.name,
        branch: branch ?? this.branch,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
    'owner': owner,
    'name': name,
    'branch': branch,
    'enabled': enabled,
  };

  factory SkillRepo.fromJson(Map<String, dynamic> json) => SkillRepo(
    owner: json['owner'] as String,
    name: json['name'] as String,
    branch: json['branch'] as String? ?? 'main',
    enabled: json['enabled'] as bool? ?? true,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillRepo &&
          owner == other.owner &&
          name == other.name &&
          branch == other.branch;

  @override
  int get hashCode => Object.hash(owner, name, branch);
}

class DiscoverableSkill {
  const DiscoverableSkill({
    required this.key,
    required this.name,
    required this.description,
    required this.directory,
    this.readmeUrl,
    required this.repoOwner,
    required this.repoName,
    required this.repoBranch,
  });

  final String key;
  final String name;
  final String description;
  final String directory;
  final String? readmeUrl;
  final String repoOwner;
  final String repoName;
  final String repoBranch;

  String get source => '$repoOwner/$repoName';
}
```

- [ ] **Step 2: Verify the file compiles**

```bash
cd client && dart analyze lib/models/skill.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add client/lib/models/skill.dart
git commit -m "feat: add Skill, SkillRepo, DiscoverableSkill models"
```

---

### Task 3: Create SkillRepoService

**Files:**
- Create: `client/lib/services/skill_repo_service.dart`

- [ ] **Step 1: Write the SkillRepoService**

```dart
import 'dart:convert';
import 'dart:io';

import '../models/skill.dart';
import 'app_storage.dart';

class SkillRepoService {
  const SkillRepoService();

  static const _defaultRepos = [
    SkillRepo(owner: 'anthropics', name: 'skills', branch: 'main'),
    SkillRepo(owner: 'ComposioHQ', name: 'awesome-claude-skills', branch: 'master'),
    SkillRepo(owner: 'cexll', name: 'myclaude', branch: 'master'),
    SkillRepo(owner: 'JimLiu', name: 'baoyu-skills', branch: 'main'),
  ];

  Future<List<SkillRepo>> loadRepos() async {
    final cache = await _readManifest();
    if (cache.isEmpty) {
      await _initDefaults();
      return _defaultRepos.toList();
    }
    final reposJson = cache['repos'] as List<dynamic>?;
    if (reposJson == null) return _defaultRepos.toList();
    return reposJson
        .map((r) => SkillRepo.fromJson(r as Map<String, dynamic>))
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

  Future<void> _initDefaults() async {
    final cache = await _readManifest();
    cache['repos'] = _defaultRepos.map((r) => r.toJson()).toList();
    await _writeManifest(cache);
  }

  Future<Map<String, dynamic>> _readManifest() async {
    final file = File('${AppStorage.flashskyaiDir}/skills.json');
    if (!file.existsSync()) return {};
    try {
      return json.decode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeManifest(Map<String, dynamic> data) async {
    final dir = Directory(AppStorage.flashskyaiDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${AppStorage.flashskyaiDir}/skills.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd client && dart analyze lib/services/skill_repo_service.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add client/lib/services/skill_repo_service.dart
git commit -m "feat: add SkillRepoService with default repo seeding"
```

---

### Task 4: Create SkillService

**Files:**
- Create: `client/lib/services/skill_service.dart`

- [ ] **Step 1: Write the SkillService**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/skill.dart';
import 'app_storage.dart';
import 'skill_repo_service.dart';

class SkillService {
  const SkillService({required this.repoService});

  final SkillRepoService repoService;

  String get _ssotDir => '${AppStorage.flashskyaiDir}/skills';
  String get _pluginSkillsDir => '${p.dirname(p.dirname(AppStorage.flashskyaiDir))}/.flashskyai/skills';
  String get _backupDir => '${AppStorage.flashskyaiDir}/skill-backups';

  // -- Manifest cache --------------------------------------------------------

  Future<Map<String, dynamic>> _readManifest() async {
    final file = File('${AppStorage.flashskyaiDir}/skills.json');
    if (!file.existsSync()) return {};
    try {
      return json.decode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeManifest(Map<String, dynamic> data) async {
    final dir = Directory(AppStorage.flashskyaiDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${AppStorage.flashskyaiDir}/skills.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  // -- Skills CRUD from cache ------------------------------------------------

  Future<List<Skill>> loadInstalled() async {
    final cache = await _readManifest();
    final skillsJson = cache['skills'] as List<dynamic>?;
    if (skillsJson == null) return [];
    return skillsJson
        .map((s) => Skill.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveSkills(List<Skill> skills) async {
    final cache = await _readManifest();
    cache['skills'] = skills.map((s) => s.toJson()).toList();
    await _writeManifest(cache);
  }

  Future<void> _addSkill(Skill skill) async {
    final skills = await loadInstalled();
    skills.removeWhere((s) => s.id == skill.id);
    skills.add(skill);
    await _saveSkills(skills);
  }

  Future<void> _removeSkill(String id) async {
    final skills = await loadInstalled();
    skills.removeWhere((s) => s.id == id);
    await _saveSkills(skills);
  }

  // -- Install ---------------------------------------------------------------

  Future<Skill> install(DiscoverableSkill d) async {
    final id = '${d.repoOwner}/${d.repoName}:${d.directory}';
    // Check already installed
    final existing = await loadInstalled();
    if (existing.any((s) => s.id == id)) {
      throw SkillAlreadyInstalledException(id);
    }

    // Download repo ZIP
    final zipBytes = await _downloadRepo(d.repoOwner, d.repoName, d.repoBranch);
    // Extract the skill directory
    final extracted = await _extractSkillDir(zipBytes, d.directory);
    // Copy to SSOT
    final ssotPath = p.join(_ssotDir, d.directory);
    await _copyDir(extracted, ssotPath);
    // Parse SKILL.md for name/description
    final skillMd = File(p.join(ssotPath, 'SKILL.md'));
    final (name, desc) = _parseSkillMd(skillMd.existsSync() ? skillMd.readAsStringSync() : '');
    // Compute hash
    final hash = await _computeDirHash(ssotPath);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final skill = Skill(
      id: id,
      name: name.isNotEmpty ? name : d.name,
      description: desc.isNotEmpty ? desc : d.description,
      directory: d.directory,
      repoOwner: d.repoOwner,
      repoName: d.repoName,
      repoBranch: d.repoBranch,
      readmeUrl: d.readmeUrl,
      enabled: true,
      installedAt: now,
      contentHash: hash,
      updatedAt: now,
    );
    await _addSkill(skill);
    await _createSymlink(skill);
    // Clean up temp
    await Directory(extracted).parent.delete(recursive: true);
    return skill;
  }

  // -- Uninstall -------------------------------------------------------------

  Future<void> uninstall(String id) async {
    final skills = await loadInstalled();
    final skill = skills.firstWhere((s) => s.id == id);
    await _createBackup(skill);
    await _removeSymlink(skill);
    final ssotPath = p.join(_ssotDir, skill.directory);
    if (Directory(ssotPath).existsSync()) {
      Directory(ssotPath).deleteSync(recursive: true);
    }
    await _removeSkill(id);
  }

  // -- Toggle ----------------------------------------------------------------

  Future<Skill> toggle(String id, bool enabled) async {
    final skills = await loadInstalled();
    final skill = skills.firstWhere((s) => s.id == id);
    final updated = skill.copyWith(enabled: enabled);
    if (enabled) {
      await _createSymlink(updated);
    } else {
      await _removeSymlink(updated);
    }
    final list = skills.map((s) => s.id == id ? updated : s).toList();
    await _saveSkills(list);
    return updated;
  }

  // -- Discover --------------------------------------------------------------

  Future<List<DiscoverableSkill>> discoverAvailable() async {
    final repos = await repoService.loadRepos();
    final enabledRepos = repos.where((r) => r.enabled).toList();
    final results = <DiscoverableSkill>[];
    // Parallel fetch
    final futures = enabledRepos.map((repo) => _discoverRepo(repo));
    final lists = await Future.wait(futures);
    for (final list in lists) {
      results.addAll(list);
    }
    return results;
  }

  Future<List<DiscoverableSkill>> _discoverRepo(SkillRepo repo) async {
    try {
      final zipBytes = await _downloadRepo(repo.owner, repo.name, repo.branch);
      final archive = ZipDecoder().decodeBytes(zipBytes);
      // Find all SKILL.md files in the archive
      final skillDirs = <String>{};
      for (final file in archive) {
        if (file.isFile && file.name.endsWith('/SKILL.md')) {
          // Skill directory is the parent dir of SKILL.md
          final parts = file.name.split('/');
          if (parts.length >= 2) {
            final dirParts = parts.sublist(1, parts.length - 1);
            if (dirParts.isNotEmpty) {
              skillDirs.add(dirParts.join('/'));
            }
          }
        }
      }
      return skillDirs.map((dir) {
        final simpleName = dir.split('/').last;
        // Try to parse SKILL.md for name/description
        final skillMdFile = archive.firstWhere(
          (f) => f.name == '${repo.name}-${repo.branch}/$dir/SKILL.md',
          orElse: () {
            // Try without prefix
            for (final f in archive) {
              if (f.isFile && f.name.endsWith('/$dir/SKILL.md')) return f;
            }
            throw StateError('SKILL.md not found');
          },
        );
        String content = '';
        if (skillMdFile is ArchiveFile) {
          content = utf8.decode(skillMdFile.content as List<int>);
        }
        final (name, desc) = _parseSkillMd(content);
        return DiscoverableSkill(
          key: '${repo.owner}/${repo.name}:$dir',
          name: name.isNotEmpty ? name : simpleName,
          description: desc,
          directory: dir,
          readmeUrl: 'https://github.com/${repo.owner}/${repo.name}/blob/${repo.branch}/$dir/README.md',
          repoOwner: repo.owner,
          repoName: repo.name,
          repoBranch: repo.branch,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // -- Updates ---------------------------------------------------------------

  Future<Map<String, String?>> checkUpdates() async {
    final skills = await loadInstalled();
    final results = <String, String?>{};
    for (final skill in skills) {
      if (skill.repoOwner == null || skill.repoName == null) continue;
      try {
        final zipBytes = await _downloadRepo(skill.repoOwner!, skill.repoName!, skill.repoBranch ?? 'main');
        final extracted = await _extractSkillDir(zipBytes, skill.directory);
        final newHash = await _computeDirHash(extracted);
        await Directory(extracted).parent.delete(recursive: true);
        if (newHash != skill.contentHash) {
          results[skill.id] = newHash;
        }
      } catch (_) {
        results[skill.id] = null; // null = error checking
      }
    }
    return results;
  }

  Future<Skill> updateSkill(String id) async {
    final skills = await loadInstalled();
    final skill = skills.firstWhere((s) => s.id == id);
    if (skill.repoOwner == null || skill.repoName == null) {
      throw Exception('Cannot update local skill');
    }
    await _createBackup(skill);
    final zipBytes = await _downloadRepo(skill.repoOwner!, skill.repoName!, skill.repoBranch ?? 'main');
    final extracted = await _extractSkillDir(zipBytes, skill.directory);
    // Remove old SSOT
    final ssotPath = p.join(_ssotDir, skill.directory);
    if (Directory(ssotPath).existsSync()) {
      Directory(ssotPath).deleteSync(recursive: true);
    }
    // Copy new
    await _copyDir(extracted, ssotPath);
    final hash = await _computeDirHash(ssotPath);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final updated = skill.copyWith(contentHash: hash, updatedAt: now);
    await _addSkill(updated);
    if (updated.enabled) {
      await _removeSymlink(skill);
      await _createSymlink(updated);
    }
    await Directory(extracted).parent.delete(recursive: true);
    return updated;
  }

  // -- Scan unmanaged --------------------------------------------------------

  Future<List<String>> scanUnmanaged() async {
    final installed = await loadInstalled();
    final managedDirs = installed.map((s) => s.directory).toSet();
    final pluginDir = Directory(_pluginSkillsDir);
    if (!pluginDir.existsSync()) return [];
    final unmanaged = <String>[];
    for (final entry in pluginDir.listSync()) {
      if (entry is Directory) {
        final name = p.basename(entry.path);
        if (!managedDirs.contains(name)) {
          unmanaged.add(name);
        }
      }
    }
    return unmanaged;
  }

  Future<List<Skill>> importUnmanaged(List<String> dirs) async {
    final imported = <Skill>[];
    final pluginDir = Directory(_pluginSkillsDir);
    for (final dir in dirs) {
      final srcPath = p.join(pluginDir.path, dir);
      final dstPath = p.join(_ssotDir, dir);
      await _copyDir(srcPath, dstPath);
      final skillMd = File(p.join(dstPath, 'SKILL.md'));
      final (name, desc) = _parseSkillMd(
        skillMd.existsSync() ? skillMd.readAsStringSync() : '',
      );
      final hash = await _computeDirHash(dstPath);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final skill = Skill(
        id: 'local:$dir',
        name: name.isNotEmpty ? name : dir,
        description: desc,
        directory: dir,
        enabled: true,
        installedAt: now,
        contentHash: hash,
        updatedAt: now,
      );
      await _addSkill(skill);
      await _createSymlink(skill);
      imported.add(skill);
    }
    return imported;
  }

  // -- ZIP install -----------------------------------------------------------

  Future<List<Skill>> installFromZip(String zipPath) async {
    final file = File(zipPath);
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    // Find all SKILL.md files
    final skillDirs = <String>{};
    for (final f in archive) {
      if (f.isFile && f.name.contains('SKILL.md')) {
        final parts = f.name.split('/');
        parts.removeLast(); // remove SKILL.md
        // Remove the root prefix (e.g. repo-branch/)
        if (parts.length >= 2) {
          skillDirs.add(parts.sublist(1).join('/'));
        } else if (parts.length == 1 && parts[0].isNotEmpty) {
          skillDirs.add(parts[0]);
        }
      }
    }
    final installed = <Skill>[];
    for (final dir in skillDirs) {
      final simpleName = dir.split('/').last;
      // Extract the directory from archive
      final tmpDir = Directory.systemTemp.createTempSync('skill_zip_');
      try {
        for (final f in archive) {
          if (f.isFile && f.name.contains('$dir/')) {
            final relPath = f.name.substring(f.name.indexOf(dir) + dir.length + 1);
            final outPath = p.join(tmpDir.path, simpleName, relPath);
            final outFile = File(outPath);
            outFile.parent.createSync(recursive: true);
            outFile.writeAsBytesSync(f.content as List<int>);
          }
        }
        final srcPath = p.join(tmpDir.path, simpleName);
        if (!Directory(srcPath).existsSync()) continue;
        final dstPath = p.join(_ssotDir, simpleName);
        await _copyDir(srcPath, dstPath);
        final skillMd = File(p.join(dstPath, 'SKILL.md'));
        final (name, desc) = _parseSkillMd(
          skillMd.existsSync() ? skillMd.readAsStringSync() : '',
        );
        final hash = await _computeDirHash(dstPath);
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final skill = Skill(
          id: 'local:$simpleName',
          name: name.isNotEmpty ? name : simpleName,
          description: desc,
          directory: simpleName,
          enabled: true,
          installedAt: now,
          contentHash: hash,
          updatedAt: now,
        );
        await _addSkill(skill);
        await _createSymlink(skill);
        installed.add(skill);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    }
    return installed;
  }

  // -- Backup / Restore ------------------------------------------------------

  Future<List<Map<String, dynamic>>> listBackups() async {
    final dir = Directory(_backupDir);
    if (!dir.existsSync()) return [];
    final backups = <Map<String, dynamic>>[];
    for (final entry in dir.listSync()) {
      if (entry is File && entry.path.endsWith('.zip')) {
        final stat = entry.statSync();
        backups.add({
          'path': entry.path,
          'name': p.basenameWithoutExtension(entry.path),
          'size': stat.size,
          'modified': stat.modified.millisecondsSinceEpoch ~/ 1000,
        });
      }
    }
    backups.sort((a, b) => (b['modified'] as int).compareTo(a['modified'] as int));
    return backups;
  }

  Future<void> deleteBackup(String path) async {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  Future<Skill> restoreBackup(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    // Extract skill info from meta
    ArchiveFile? metaFile;
    for (final f in archive) {
      if (f.name == 'meta.json') {
        metaFile = f;
        break;
      }
    }
    if (metaFile == null) throw Exception('Invalid backup: missing meta.json');
    final meta = json.decode(utf8.decode(metaFile.content as List<int>)) as Map<String, dynamic>;
    final dir = meta['directory'] as String;
    // Extract skill files
    final ssotPath = p.join(_ssotDir, dir);
    if (Directory(ssotPath).existsSync()) {
      Directory(ssotPath).deleteSync(recursive: true);
    }
    for (final f in archive) {
      if (f.isFile && f.name.startsWith('skill/')) {
        final relPath = f.name.substring(6);
        final outPath = p.join(ssotPath, relPath);
        final outFile = File(outPath);
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(f.content as List<int>);
      }
    }
    final skill = Skill.fromJson(meta);
    await _addSkill(skill);
    if (skill.enabled) {
      await _createSymlink(skill);
    }
    return skill;
  }

  // -- Helpers ---------------------------------------------------------------

  Future<Uint8List> _downloadRepo(String owner, String name, String branch) async {
    final url = 'https://github.com/$owner/$name/archive/refs/heads/$branch.zip';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw DownloadFailedException(url, response.statusCode);
    }
    return response.bodyBytes;
  }

  Future<String> _extractSkillDir(Uint8List zipBytes, String targetDir) async {
    final tmpRoot = Directory.systemTemp.createTempSync('skill_extract_');
    final archive = ZipDecoder().decodeBytes(zipBytes);
    // Find the root prefix (usually repo-branch/)
    String rootPrefix = '';
    for (final f in archive) {
      if (f.isFile && f.name.contains(targetDir)) {
        final idx = f.name.indexOf(targetDir);
        rootPrefix = f.name.substring(0, idx);
        break;
      }
    }
    if (rootPrefix.isEmpty) {
      tmpRoot.deleteSync(recursive: true);
      throw Exception('Skill directory $targetDir not found in archive');
    }
    // Extract only files under the target dir
    for (final f in archive) {
      if (f.isFile && f.name.startsWith('$rootPrefix$targetDir/')) {
        // Also include files at root level (not in any skill dir) just those in targetDir
        final relPath = f.name.substring(rootPrefix.length);
        final outPath = p.join(tmpRoot.path, relPath);
        final outFile = File(outPath);
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(f.content as List<int>);
      }
    }
    return p.join(tmpRoot.path, targetDir);
  }

  Future<void> _copyDir(String src, String dst) async {
    final dstDir = Directory(dst);
    if (dstDir.existsSync()) dstDir.deleteSync(recursive: true);
    final result = await Process.run('cp', ['-a', src, dst]);
    if (result.exitCode != 0) {
      // Fallback: recursive copy
      await _copyDirDart(Directory(src), dstDir);
    }
  }

  Future<void> _copyDirDart(Directory src, Directory dst) async {
    if (!dst.existsSync()) dst.createSync(recursive: true);
    for (final entry in src.listSync()) {
      if (entry is File) {
        entry.copySync(p.join(dst.path, p.basename(entry.path)));
      } else if (entry is Directory) {
        await _copyDirDart(entry, Directory(p.join(dst.path, p.basename(entry.path))));
      }
    }
  }

  (String, String) _parseSkillMd(String content) {
    String name = '';
    String desc = '';
    final lines = content.split('\n');
    var inFrontmatter = false;
    for (final line in lines) {
      if (line.trim() == '---') {
        if (!inFrontmatter) {
          inFrontmatter = true;
          continue;
        } else {
          break;
        }
      }
      if (inFrontmatter) {
        if (line.startsWith('name:')) {
          name = line.substring(5).trim();
        } else if (line.startsWith('description:')) {
          desc = line.substring(12).trim();
        }
      }
    }
    return (name, desc);
  }

  Future<String> _computeDirHash(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) return '';
    final files = <String>[];
    for (final entry in dir.listSync(recursive: true)) {
      if (entry is File && !p.basename(entry.path).startsWith('.')) {
        files.add(entry.path);
      }
    }
    files.sort();
    final sink = sha256.start();
    for (final filePath in files) {
      final bytes = await File(filePath).readAsBytes();
      sink.add(bytes);
    }
    return sink.close().toString();
  }

  Future<void> _createSymlink(Skill skill) async {
    final linkDir = Directory(_pluginSkillsDir);
    if (!linkDir.existsSync()) linkDir.createSync(recursive: true);
    final linkPath = p.join(_pluginSkillsDir, skill.directory);
    final targetPath = p.join(_ssotDir, skill.directory);
    final link = Link(linkPath);
    if (link.existsSync()) link.deleteSync();
    await link.create(targetPath);
  }

  Future<void> _removeSymlink(Skill skill) async {
    final link = Link(p.join(_pluginSkillsDir, skill.directory));
    if (link.existsSync()) link.deleteSync();
  }

  Future<void> _createBackup(Skill skill) async {
    final dir = Directory(_backupDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final meta = json.encode(skill.toJson());
    final archive = Archive();
    archive.addFile(ArchiveFile.string('meta.json', meta));
    final ssotPath = p.join(_ssotDir, skill.directory);
    if (Directory(ssotPath).existsSync()) {
      for (final entry in Directory(ssotPath).listSync(recursive: true)) {
        if (entry is File) {
          final relPath = p.relative(entry.path, from: _ssotDir);
          archive.addFile(ArchiveFile('skill/$relPath', entry.lengthSync(), entry.readAsBytesSync()));
        }
      }
    }
    final encoder = ZipEncoder();
    final bytes = encoder.encode(archive)!;
    final backupPath = p.join(_backupDir, '${skill.id.replaceAll('/', '_').replaceAll(':', '_')}-${skill.updatedAt}.zip');
    await File(backupPath).writeAsBytes(bytes);
    await _cleanupOldBackups();
  }

  Future<void> _cleanupOldBackups() async {
    final dir = Directory(_backupDir);
    if (!dir.existsSync()) return;
    final files = dir.listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.zip'))
        .toList();
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    for (var i = 20; i < files.length; i++) {
      files[i].deleteSync();
    }
  }

  /// Search skills.sh public API
  Future<List<DiscoverableSkill>> searchSkillsSh(String query) async {
    final url = Uri.parse('https://skills.sh/api/search?q=${Uri.encodeComponent(query)}');
    try {
      final response = await http.get(url);
      if (response.statusCode != 200) return [];
      final data = json.decode(response.body) as List<dynamic>;
      return data.map((item) {
        final m = item as Map<String, dynamic>;
        return DiscoverableSkill(
          key: 'skills.sh:${m['name'] as String}',
          name: m['name'] as String,
          description: m['description'] as String? ?? '',
          directory: m['directory'] as String? ?? m['name'] as String,
          repoOwner: m['repo_owner'] as String? ?? '',
          repoName: m['repo_name'] as String? ?? '',
          repoBranch: m['repo_branch'] as String? ?? 'main',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}

class SkillAlreadyInstalledException implements Exception {
  SkillAlreadyInstalledException(this.skillId);
  final String skillId;
  @override
  String toString() => 'Skill already installed: $skillId';
}

class DownloadFailedException implements Exception {
  DownloadFailedException(this.url, this.statusCode);
  final String url;
  final int statusCode;
  @override
  String toString() => 'Download failed ($statusCode): $url';
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd client && dart analyze lib/services/skill_service.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add client/lib/services/skill_service.dart
git commit -m "feat: add SkillService with install, uninstall, discover, update, backup"
```

---

### Task 5: Create SkillCubit

**Files:**
- Create: `client/lib/cubits/skill_cubit.dart`

- [ ] **Step 1: Write the SkillCubit**

```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/skill.dart';
import '../services/skill_repo_service.dart';
import '../services/skill_service.dart';

class SkillState {
  const SkillState({
    this.installedSkills = const [],
    this.discoverableSkills = const [],
    this.repos = const [],
    this.updates = const {},
    this.isLoading = false,
    this.isDiscovering = false,
    this.error,
  });

  final List<Skill> installedSkills;
  final List<DiscoverableSkill> discoverableSkills;
  final List<SkillRepo> repos;
  final Map<String, String?> updates; // skillId -> newHash (null = error)
  final bool isLoading;
  final bool isDiscovering;
  final String? error;

  SkillState copyWith({
    List<Skill>? installedSkills,
    List<DiscoverableSkill>? discoverableSkills,
    List<SkillRepo>? repos,
    Map<String, String?>? updates,
    bool? isLoading,
    bool? isDiscovering,
    String? error,
    bool clearError = false,
  }) {
    return SkillState(
      installedSkills: installedSkills ?? this.installedSkills,
      discoverableSkills: discoverableSkills ?? this.discoverableSkills,
      repos: repos ?? this.repos,
      updates: updates ?? this.updates,
      isLoading: isLoading ?? this.isLoading,
      isDiscovering: isDiscovering ?? this.isDiscovering,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class SkillCubit extends Cubit<SkillState> {
  SkillCubit({
    required this.skillService,
    required this.repoService,
  }) : super(const SkillState()) {
    _init();
  }

  final SkillService skillService;
  final SkillRepoService repoService;

  Future<void> _init() async {
    emit(state.copyWith(isLoading: true));
    try {
      final [skills, repos] = await Future.wait([
        skillService.loadInstalled(),
        repoService.loadRepos(),
      ]);
      emit(state.copyWith(
        installedSkills: skills,
        repos: repos,
        isLoading: false,
        clearError: true,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> refresh() => _init();

  Future<void> install(DiscoverableSkill d) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final skill = await skillService.install(d);
      emit(state.copyWith(
        installedSkills: [...state.installedSkills, skill],
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> uninstall(String id) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      await skillService.uninstall(id);
      emit(state.copyWith(
        installedSkills: state.installedSkills.where((s) => s.id != id).toList(),
        updates: Map.of(state.updates)..remove(id),
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> toggle(String id, bool enabled) async {
    try {
      final updated = await skillService.toggle(id, enabled);
      emit(state.copyWith(
        installedSkills: state.installedSkills.map((s) => s.id == id ? updated : s).toList(),
      ));
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> discover() async {
    emit(state.copyWith(isDiscovering: true, clearError: true));
    try {
      final skills = await skillService.discoverAvailable();
      emit(state.copyWith(
        discoverableSkills: skills,
        isDiscovering: false,
      ));
    } catch (e) {
      emit(state.copyWith(isDiscovering: false, error: e.toString()));
    }
  }

  Future<void> checkUpdates() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final updates = await skillService.checkUpdates();
      emit(state.copyWith(updates: updates, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> updateSkill(String id) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final updated = await skillService.updateSkill(id);
      emit(state.copyWith(
        installedSkills: state.installedSkills.map((s) => s.id == id ? updated : s).toList(),
        updates: Map.of(state.updates)..remove(id),
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> installFromZip(String zipPath) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final installed = await skillService.installFromZip(zipPath);
      emit(state.copyWith(
        installedSkills: [...state.installedSkills, ...installed],
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<List<Skill>> importUnmanaged(List<String> dirs) async {
    final imported = await skillService.importUnmanaged(dirs);
    emit(state.copyWith(
      installedSkills: [...state.installedSkills, ...imported],
    ));
    return imported;
  }

  Future<void> addRepo(SkillRepo repo) async {
    await repoService.addRepo(repo);
    final repos = await repoService.loadRepos();
    emit(state.copyWith(repos: repos));
  }

  Future<void> removeRepo(String owner, String name) async {
    await repoService.removeRepo(owner, name);
    final repos = await repoService.loadRepos();
    emit(state.copyWith(repos: repos));
  }

  Future<List<String>> scanUnmanaged() async {
    return skillService.scanUnmanaged();
  }

  Future<List<Map<String, dynamic>>> listBackups() async {
    return skillService.listBackups();
  }

  Future<void> deleteBackup(String path) async {
    await skillService.deleteBackup(path);
  }

  Future<Skill> restoreBackup(String path) async {
    final skill = await skillService.restoreBackup(path);
    final filtered = state.installedSkills.where((s) => s.id != skill.id).toList();
    emit(state.copyWith(installedSkills: [...filtered, skill]));
    return skill;
  }

  Future<List<DiscoverableSkill>> searchSkillsSh(String query) async {
    return skillService.searchSkillsSh(query);
  }

  bool isInstalled(String key) {
    return state.installedSkills.any((s) =>
        '${s.repoOwner}/${s.repoName}:${s.directory}' == key);
  }
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd client && dart analyze lib/cubits/skill_cubit.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add client/lib/cubits/skill_cubit.dart
git commit -m "feat: add SkillCubit for skill state management"
```

---

### Task 6: Add Localization Strings

**Files:**
- Modify: `client/lib/l10n/app_localizations.dart`

- [ ] **Step 1: Add skill management localization getters**

Add these getters to the `AppLocalizations` class (after the existing getters):

```dart
  String get skills => _strings['skills']!;
  String get skillManagement => _strings['skillManagement']!;
  String get skillManagementSubtitle => _strings['skillManagementSubtitle']!;
  String get discoverSkills => _strings['discoverSkills']!;
  String get installSkill => _strings['installSkill']!;
  String get installing => _strings['installing']!;
  String get uninstallSkill => _strings['uninstallSkill']!;
  String get uninstallSkillConfirm(String name) =>
      _strings['uninstallSkillConfirm']!.replaceFirst('{name}', name);
  String get updateAvailable => _strings['updateAvailable']!;
  String get checkUpdates => _strings['checkUpdates']!;
  String get updateAll => _strings['updateAll']!;
  String get importSkills => _strings['importSkills']!;
  String get installFromZip => _strings['installFromZip']!;
  String get restoreBackup => _strings['restoreBackup']!;
  String get noSkillsInstalled => _strings['noSkillsInstalled']!;
  String get skillRepos => _strings['skillRepos']!;
  String get addRepo => _strings['addRepo']!;
  String get removeRepo => _strings['removeRepo']!;
  String get repoUrl => _strings['repoUrl']!;
  String get branch => _strings['branch']!;
  String get viewOnGithub => _strings['viewOnGithub']!;
  String get scanUnmanaged => _strings['scanUnmanaged']!;
  String get noUnmanagedSkills => _strings['noUnmanagedSkills']!;
  String get importSelected => _strings['importSelected']!;
  String get searchSkills => _strings['searchSkills']!;
  String get filterByRepo => _strings['filterByRepo']!;
  String get allRepos => _strings['allRepos']!;
  String get skillAlreadyInstalled => _strings['skillAlreadyInstalled']!;
  String get downloadFailed => _strings['downloadFailed']!;
  String get skillDirNotFound => _strings['skillDirNotFound']!;
  String get enableSkill => _strings['enableSkill']!;
  String get backupRestore => _strings['backupRestore']!;
```

- [ ] **Step 2: Add localization strings to the `_strings` map**

Add these entries to the `_strings` map in `_AppLocalizationsDelegate`:

```dart
    'skills': {'en': 'Skills', 'zh': '技能'},
    'skillManagement': {'en': 'Skill Management', 'zh': '技能管理'},
    'skillManagementSubtitle': {'en': 'Install and manage Claude skills', 'zh': '安装和管理 Claude 技能'},
    'discoverSkills': {'en': 'Discover Skills', 'zh': '发现技能'},
    'installSkill': {'en': 'Install', 'zh': '安装'},
    'installing': {'en': 'Installing...', 'zh': '安装中...'},
    'uninstallSkill': {'en': 'Uninstall', 'zh': '卸载'},
    'uninstallSkillConfirm': {
      'en': 'Uninstall skill "{name}"? This cannot be undone.',
      'zh': '卸载技能 "{name}"？此操作不可撤销。',
    },
    'updateAvailable': {'en': 'Update available', 'zh': '有更新'},
    'checkUpdates': {'en': 'Check Updates', 'zh': '检查更新'},
    'updateAll': {'en': 'Update All', 'zh': '全部更新'},
    'importSkills': {'en': 'Import', 'zh': '导入'},
    'installFromZip': {'en': 'Install from ZIP', 'zh': '从ZIP安装'},
    'restoreBackup': {'en': 'Restore Backup', 'zh': '恢复备份'},
    'noSkillsInstalled': {'en': 'No skills installed yet', 'zh': '暂未安装技能'},
    'skillRepos': {'en': 'Skill Repos', 'zh': '技能仓库'},
    'addRepo': {'en': 'Add Repo', 'zh': '添加仓库'},
    'removeRepo': {'en': 'Remove', 'zh': '移除'},
    'repoUrl': {'en': 'GitHub URL (owner/name)', 'zh': 'GitHub 地址 (owner/name)'},
    'branch': {'en': 'Branch', 'zh': '分支'},
    'viewOnGithub': {'en': 'View on GitHub', 'zh': '在 GitHub 上查看'},
    'scanUnmanaged': {'en': 'Scan Unmanaged', 'zh': '扫描未管理'},
    'noUnmanagedSkills': {'en': 'No unmanaged skills found', 'zh': '未找到未管理的技能'},
    'importSelected': {'en': 'Import Selected', 'zh': '导入所选'},
    'searchSkills': {'en': 'Search skills...', 'zh': '搜索技能...'},
    'filterByRepo': {'en': 'Filter by repo', 'zh': '按仓库筛选'},
    'allRepos': {'en': 'All Repos', 'zh': '所有仓库'},
    'skillAlreadyInstalled': {'en': 'Skill already installed', 'zh': '技能已安装'},
    'downloadFailed': {'en': 'Download failed', 'zh': '下载失败'},
    'skillDirNotFound': {'en': 'Skill directory not found', 'zh': '技能目录未找到'},
    'enableSkill': {'en': 'Enabled', 'zh': '启用'},
    'backupRestore': {'en': 'Backup & Restore', 'zh': '备份和恢复'},
```

- [ ] **Step 3: Verify compilation**

```bash
cd client && dart analyze lib/l10n/app_localizations.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add client/lib/l10n/app_localizations.dart
git commit -m "feat: add skill management localization strings"
```

---

### Task 7: Create SkillManagementPage

**Files:**
- Create: `client/lib/pages/skill_management_page.dart`

- [ ] **Step 1: Write the SkillManagementPage**

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/skill_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/skill.dart';
import '../theme/app_theme.dart';

class SkillManagementPage extends StatelessWidget {
  const SkillManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final cubit = context.watch<SkillCubit>();
    final state = cubit.state;

    return Container(
      color: colors.workspaceBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TitleBar(
            title: l10n.skillManagement,
            subtitle: l10n.skillManagementSubtitle,
            actions: [
              _ActionButton(
                icon: Icons.search,
                label: l10n.discoverSkills,
                onTap: () => context.go('/skills/discover'),
              ),
              _ActionButton(
                icon: Icons.download,
                label: l10n.importSkills,
                onTap: () => _showImportDialog(context, cubit, l10n),
              ),
              _ActionButton(
                icon: Icons.folder_zip_outlined,
                label: l10n.installFromZip,
                onTap: () => _installFromZip(context, cubit),
              ),
              _ActionButton(
                icon: Icons.history,
                label: l10n.backupRestore,
                onTap: () => _showRestoreDialog(context, cubit, l10n),
              ),
              _ActionButton(
                icon: Icons.refresh,
                label: l10n.checkUpdates,
                onTap: () => cubit.checkUpdates(),
              ),
            ],
          ),
          Expanded(
            child: state.isLoading && state.installedSkills.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : state.installedSkills.isEmpty
                    ? Center(
                        child: Text(
                          l10n.noSkillsInstalled,
                          style: TextStyle(color: colors.emptyMessageText, fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(40, 24, 40, 24),
                        itemCount: state.installedSkills.length,
                        itemBuilder: (context, index) {
                          final skill = state.installedSkills[index];
                          return _SkillListTile(
                            skill: skill,
                            hasUpdate: state.updates.containsKey(skill.id),
                            onToggle: (v) => cubit.toggle(skill.id, v),
                            onUninstall: () => _confirmUninstall(context, cubit, skill, l10n),
                            onUpdate: state.updates.containsKey(skill.id)
                                ? () => cubit.updateSkill(skill.id)
                                : null,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportDialog(
    BuildContext context,
    SkillCubit cubit,
    AppLocalizations l10n,
  ) async {
    final unmanaged = await cubit.scanUnmanaged();
    if (!context.mounted) return;
    if (unmanaged.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.noUnmanagedSkills)),
      );
      return;
    }
    final selected = <String>{};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text(l10n.importSkills),
          content: SizedBox(
            width: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: unmanaged.length,
              itemBuilder: (ctx, i) => CheckboxListTile(
                title: Text(unmanaged[i]),
                value: selected.contains(unmanaged[i]),
                onChanged: (v) {
                  setLocalState(() {
                    if (v == true) {
                      selected.add(unmanaged[i]);
                    } else {
                      selected.remove(unmanaged[i]);
                    }
                  });
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(ctx).pop(selected.toList()),
              child: Text(l10n.importSelected),
            ),
          ],
        ),
      ),
    );
    if (result != null && result.isNotEmpty && context.mounted) {
      await cubit.importUnmanaged(result);
    }
  }

  Future<void> _installFromZip(BuildContext context, SkillCubit cubit) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.isEmpty) return;
    await cubit.installFromZip(result.files.single.path!);
  }

  Future<void> _showRestoreDialog(
    BuildContext context,
    SkillCubit cubit,
    AppLocalizations l10n,
  ) async {
    final backups = await cubit.listBackups();
    if (!context.mounted) return;
    if (backups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No backups found')),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.backupRestore),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: backups.length,
            itemBuilder: (ctx, i) {
              final b = backups[i];
              return ListTile(
                title: Text(b['name'] as String),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore, size: 18),
                      tooltip: 'Restore',
                      onPressed: () async {
                        await cubit.restoreBackup(b['path'] as String);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: l10n.delete,
                      onPressed: () async {
                        await cubit.deleteBackup(b['path'] as String);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _confirmUninstall(
    BuildContext context,
    SkillCubit cubit,
    Skill skill,
    AppLocalizations l10n,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.uninstallSkill),
        content: Text(l10n.uninstallSkillConfirm(skill.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              cubit.uninstall(skill.id);
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 42, 40, 28),
      decoration: BoxDecoration(
        color: colors.workspaceBackground,
        border: Border(bottom: BorderSide(color: colors.subtleBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textBase,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textBase.withValues(alpha: 0.66),
                    fontSize: 14,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ...actions,
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _SkillListTile extends StatelessWidget {
  const _SkillListTile({
    required this.skill,
    required this.hasUpdate,
    required this.onToggle,
    required this.onUninstall,
    this.onUpdate,
  });

  final Skill skill;
  final bool hasUpdate;
  final ValueChanged<bool> onToggle;
  final VoidCallback onUninstall;
  final VoidCallback? onUpdate;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.typeBadgeApiBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.bolt, size: 22, color: colors.typeBadgeApiText),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  skill.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textBase,
                  ),
                ),
                if (skill.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    skill.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: textBase.withValues(alpha: 0.6),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  skill.source,
                  style: TextStyle(
                    fontSize: 11,
                    color: textBase.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          if (hasUpdate && onUpdate != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OutlinedButton(
                onPressed: onUpdate,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  side: BorderSide(color: colors.accentGreen),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  'Update',
                  style: TextStyle(fontSize: 12, color: colors.accentGreen),
                ),
              ),
            ),
          Switch(value: skill.enabled, onChanged: onToggle),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Uninstall',
            onPressed: onUninstall,
            icon: const Icon(Icons.delete_outline, size: 18),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd client && dart analyze lib/pages/skill_management_page.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/skill_management_page.dart
git commit -m "feat: add SkillManagementPage with install, import, backup controls"
```

---

### Task 8: Create SkillDiscoveryPage

**Files:**
- Create: `client/lib/pages/skill_discovery_page.dart`

- [ ] **Step 1: Write the SkillDiscoveryPage**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cubits/skill_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/skill.dart';
import '../theme/app_theme.dart';

class SkillDiscoveryPage extends StatefulWidget {
  const SkillDiscoveryPage({super.key});

  @override
  State<SkillDiscoveryPage> createState() => _SkillDiscoveryPageState();
}

class _SkillDiscoveryPageState extends State<SkillDiscoveryPage> {
  String _search = '';
  String _filterRepo = '';
  var _source = 'repos'; // 'repos' or 'skills.sh'
  List<DiscoverableSkill> _searchResults = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SkillCubit>().discover();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final state = context.watch<SkillCubit>().state;
    final cubit = context.read<SkillCubit>();

    final skills = _source == 'repos'
        ? state.discoverableSkills
        : _searchResults;
    final repoOptions = <String>{};
    for (final s in state.discoverableSkills) {
      repoOptions.add(s.source);
    }

    var filtered = skills.where((s) {
      if (_filterRepo.isNotEmpty && s.source != _filterRepo) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        return s.name.toLowerCase().contains(q) ||
            s.description.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    return Container(
      color: colors.workspaceBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DiscoveryTitleBar(
            l10n: l10n,
            onBack: () => context.go('/skills'),
            onRepoManager: () => context.go('/skills/repos'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 16, 40, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: l10n.searchSkills,
                      prefixIcon: const Icon(Icons.search, size: 20),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                const SizedBox(width: 12),
                if (_source == 'repos') ...[
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filterRepo.isEmpty ? null : _filterRepo,
                      hint: Text(l10n.filterByRepo),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(l10n.allRepos),
                        ),
                        for (final r in repoOptions)
                          DropdownMenuItem(value: r, child: Text(r)),
                      ],
                      onChanged: (v) => setState(() => _filterRepo = v ?? ''),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'repos', label: Text('Repos')),
                    ButtonSegment(value: 'skills.sh', label: Text('skills.sh')),
                  ],
                  selected: {_source},
                  onSelectionChanged: (v) => setState(() => _source = v.first),
                ),
              ],
            ),
          ),
          Expanded(
            child: state.isDiscovering
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No skills found',
                          style: TextStyle(color: colors.emptyMessageText),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(40, 16, 40, 24),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final skill = filtered[index];
                          return _SkillCard(
                            skill: skill,
                            installed: cubit.isInstalled(skill.key),
                            onInstall: () => cubit.install(skill),
                            onUninstall: () {
                              final id = state.installedSkills
                                  .firstWhere((s) =>
                                      '${s.repoOwner}/${s.repoName}:${s.directory}' == skill.key)
                                  .id;
                              cubit.uninstall(id);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryTitleBar extends StatelessWidget {
  const _DiscoveryTitleBar({
    required this.l10n,
    required this.onBack,
    required this.onRepoManager,
  });

  final AppLocalizations l10n;
  final VoidCallback onBack;
  final VoidCallback onRepoManager;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 42, 40, 28),
      decoration: BoxDecoration(
        color: colors.workspaceBackground,
        border: Border(bottom: BorderSide(color: colors.subtleBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.discoverSkills,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textBase,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onRepoManager,
            icon: const Icon(Icons.settings, size: 16),
            label: Text(l10n.skillRepos),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.skill,
    required this.installed,
    required this.onInstall,
    required this.onUninstall,
  });

  final DiscoverableSkill skill;
  final bool installed;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: installed ? colors.accentGreen : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.typeBadgeApiBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.bolt, size: 18, color: colors.typeBadgeApiText),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  skill.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textBase,
                  ),
                ),
              ),
              if (installed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.successBackground,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.successBorder),
                  ),
                  child: Text(
                    'Installed',
                    style: TextStyle(fontSize: 10, color: colors.successText),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Text(
              skill.description.isNotEmpty ? skill.description : 'No description',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: textBase.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            skill.source,
            style: TextStyle(fontSize: 11, color: textBase.withValues(alpha: 0.4)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: installed
                    ? OutlinedButton(
                        onPressed: onUninstall,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          side: BorderSide(color: Theme.of(context).colorScheme.error),
                        ),
                        child: Text(
                          'Uninstall',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: onInstall,
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('Install', style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
              ),
              if (skill.repoOwner.isNotEmpty)
                IconButton(
                  tooltip: 'View on GitHub',
                  onPressed: () => launchUrl(
                    Uri.parse('https://github.com/${skill.repoOwner}/${skill.repoName}'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd client && dart analyze lib/pages/skill_discovery_page.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/skill_discovery_page.dart
git commit -m "feat: add SkillDiscoveryPage with repo and skills.sh search"
```

---

### Task 9: Create RepoManagementPage

**Files:**
- Create: `client/lib/pages/skill_repo_page.dart`

- [ ] **Step 1: Write the RepoManagementPage**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/skill_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/skill.dart';
import '../theme/app_theme.dart';

class RepoManagementPage extends StatefulWidget {
  const RepoManagementPage({super.key});

  @override
  State<RepoManagementPage> createState() => _RepoManagementPageState();
}

class _RepoManagementPageState extends State<RepoManagementPage> {
  final _ownerCtl = TextEditingController();
  final _branchCtl = TextEditingController(text: 'main');

  @override
  void dispose() {
    _ownerCtl.dispose();
    _branchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final state = context.watch<SkillCubit>().state;
    final cubit = context.read<SkillCubit>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);

    return Container(
      color: colors.workspaceBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RepoTitleBar(l10n: l10n, onBack: () => context.go('/skills/discover')),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 24, 40, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Add repo form
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: colors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.addRepo,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: textBase,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _ownerCtl,
                                decoration: InputDecoration(
                                  hintText: l10n.repoUrl,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 1,
                              child: TextField(
                                controller: _branchCtl,
                                decoration: InputDecoration(hintText: l10n.branch),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              onPressed: () {
                                final parts = _ownerCtl.text.trim().split('/');
                                if (parts.length != 2) return;
                                cubit.addRepo(SkillRepo(
                                  owner: parts[0],
                                  name: parts[1],
                                  branch: _branchCtl.text.trim().isEmpty
                                      ? 'main'
                                      : _branchCtl.text.trim(),
                                ));
                                _ownerCtl.clear();
                                _branchCtl.text = 'main';
                              },
                              child: Text(l10n.add),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Repo list
                  Expanded(
                    child: ListView.builder(
                      itemCount: state.repos.length,
                      itemBuilder: (context, index) {
                        final repo = state.repos[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colors.cardBackground,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colors.border),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.code, size: 20, color: textBase.withValues(alpha: 0.6)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      repo.fullName,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: textBase,
                                      ),
                                    ),
                                    Text(
                                      repo.branch,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: textBase.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: l10n.removeRepo,
                                onPressed: () => cubit.removeRepo(repo.owner, repo.name),
                                icon: const Icon(Icons.delete_outline, size: 18),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RepoTitleBar extends StatelessWidget {
  const _RepoTitleBar({required this.l10n, required this.onBack});

  final AppLocalizations l10n;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 42, 40, 28),
      decoration: BoxDecoration(
        color: colors.workspaceBackground,
        border: Border(bottom: BorderSide(color: colors.subtleBorder)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.skillRepos,
            style: TextStyle(
              color: textBase,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd client && dart analyze lib/pages/skill_repo_page.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/skill_repo_page.dart
git commit -m "feat: add RepoManagementPage for skill repo CRUD"
```

---

### Task 10: Add Navigation Tile to ContextSidebar

**Files:**
- Modify: `client/lib/widgets/context_sidebar.dart`

- [ ] **Step 1: Add _SkillManagerTile above _TeamSelector**

In the `build` method of `_ContextSidebarState`, add the `_SkillManagerTile` as the first child in the `Column` children list, before `_TeamSelector`. Also add the import for `skill_cubit.dart` and the widget class at the bottom of the file.

Add import near the top:

```dart
import '../cubits/skill_cubit.dart';
```

In the Column children (line 59), insert before `_TeamSelector`:

```dart
                  _SkillManagerTile(
                    onTap: () {
                      FramePerf.mark('nav skills');
                      context.go('/skills');
                    },
                  ),
                  const SizedBox(height: 14),
```

Add the widget class at the bottom of the file (before the final closing brace):

```dart
class _SkillManagerTile extends StatelessWidget {
  const _SkillManagerTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Material(
      key: AppKeys.sidebarSkillsButton,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(Icons.bolt, size: 18, color: textBase),
              const SizedBox(width: 10),
              Text(
                'Skills',
                style: TextStyle(fontWeight: FontWeight.w700, color: textBase),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Also add a key constant in `client/lib/utils/app_keys.dart`:

```dart
  static const sidebarSkillsButton = Key('sidebar_skills_button');
```

- [ ] **Step 2: Verify compilation**

```bash
cd client && dart analyze lib/widgets/context_sidebar.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add client/lib/widgets/context_sidebar.dart client/lib/utils/app_keys.dart
git commit -m "feat: add Skills navigation tile to sidebar above team selector"
```

---

### Task 11: Add Skill Routes to Router

**Files:**
- Modify: `client/lib/router/app_router.dart`

- [ ] **Step 1: Add skill routes**

Add imports:

```dart
import '../cubits/skill_cubit.dart';
import '../pages/skill_discovery_page.dart';
import '../pages/skill_management_page.dart';
import '../pages/skill_repo_page.dart';
import '../services/skill_repo_service.dart';
import '../services/skill_service.dart';
```

Add routes inside the `ShellRoute` routes list (after the existing routes):

```dart
        GoRoute(
          path: '/skills',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SkillManagementPage(),
          ),
        ),
        GoRoute(
          path: '/skills/discover',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SkillDiscoveryPage(),
          ),
        ),
        GoRoute(
          path: '/skills/repos',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: RepoManagementPage(),
          ),
        ),
```

- [ ] **Step 2: Register SkillCubit in main.dart**

The `SkillCubit` needs to be provided at the app level in `main.dart`. Add these imports near the top (line 15 area):

```dart
import 'cubits/skill_cubit.dart';
import 'services/skill_repo_service.dart';
import 'services/skill_service.dart';
```

After `llmConfigCubit.load()` (around line 73), create the `SkillCubit`:

```dart
  final skillCubit = SkillCubit(
    skillService: const SkillService(repoService: const SkillRepoService()),
    repoService: const SkillRepoService(),
  );
```

In the `MultiBlocProvider` providers list (around line 78), add:

```dart
        BlocProvider.value(value: skillCubit),
```

- [ ] **Step 3: Verify compilation**

```bash
cd client && dart analyze lib/router/app_router.dart lib/main.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add client/lib/router/app_router.dart client/lib/main.dart
git commit -m "feat: add skill management routes and SkillCubit provider"
```

---

### Task 12: Integration Verification

- [ ] **Step 1: Run full analysis**

```bash
cd client && dart analyze
```

Expected: no errors.

- [ ] **Step 2: Run existing tests**

```bash
cd client && flutter test
```

Expected: all tests pass.

- [ ] **Step 3: Verify the app compiles**

```bash
cd client && flutter build linux --debug 2>&1 | tail -5
```

Expected: build succeeds.

- [ ] **Step 4: Commit any final fixes**
