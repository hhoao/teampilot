# Skill Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a global Skill management surface to the FlashskyAI Flutter client with feature parity to cc-switch (install, discover, repos, updates, backups, ZIP/local import, scan-unmanaged, skills.sh search).

**Architecture:** Services for manifest IO, GitHub tarball fetch, install orchestration, skills.sh search; a `SkillRepository` facade and a single `SkillCubit`; a `SkillManagementPage` reusing the `_TitleBar + _NavPanel + content` skeleton from team_config_page; sidebar entry above the team selector.

**Tech Stack:** Flutter, flutter_bloc, go_router, `http`, `archive`, `crypto`, `file_picker`, `path_provider`.

---

## File map

**New (under `client/`):**
- `lib/services/skill_manifest_service.dart`
- `lib/services/skill_fetch_service.dart`
- `lib/services/skill_install_service.dart`
- `lib/services/skills_sh_service.dart`
- `lib/repositories/skill_repository.dart`
- `lib/cubits/skill_cubit.dart`
- `lib/pages/skill_management_page.dart`
- `test/services/skill_manifest_service_test.dart`
- `test/services/skill_fetch_service_test.dart`
- `test/services/skill_install_service_test.dart`

**Modified:**
- `lib/models/skill.dart` (add `SkillUpdateInfo`, `SkillBackup`, `UnmanagedSkill`, `SkillsShEntry`)
- `lib/services/skill_repo_service.dart` (add `setEnabled`/`updateBranch`)
- `lib/widgets/context_sidebar.dart` (add `_SkillTile` above `_TeamSelector`)
- `lib/router/app_router.dart` (add `/skills` route)
- `lib/main.dart` (register `SkillCubit`)
- `lib/l10n/app_en.arb`, `lib/l10n/app_zh.arb` (add `skills*` keys; regenerate)

---

## Task 1: Extend models

**Files:**
- Modify: `client/lib/models/skill.dart`

- [ ] Add four new classes at the end of the file: `SkillUpdateInfo`, `SkillBackup`, `UnmanagedSkill`, `SkillsShEntry`. Each must have `toJson`/`fromJson`, an `==`/`hashCode` override based on identity fields, and a `copyWith` only where mutation is realistically used (`Skill` already has it).
- [ ] Commit: `feat(models): add SkillUpdateInfo/SkillBackup/UnmanagedSkill/SkillsShEntry`

Field shapes (canonical):

```dart
class SkillUpdateInfo {
  final String id;        // Skill.id
  final String name;
  final String? currentHash;
  final String remoteHash;
}

class SkillBackup {
  final String backupId;       // "<basename>-<unixSeconds>"
  final String backupPath;     // absolute
  final int createdAt;         // unix ms
  final Skill skill;           // pre-backup Skill row
}

class UnmanagedSkill {
  final String directory;      // basename
  final String name;
  final String? description;
  final String path;           // absolute path on disk
}

class SkillsShEntry {
  final String key;
  final String name;
  final String directory;
  final String repoOwner;
  final String repoName;
  final String repoBranch;
  final String? readmeUrl;
  final int installs;
}
```

---

## Task 2: SkillManifestService (TDD)

Reads/writes `${flashskyaiDir}/skills/manifest.json`. Pure file IO, no network.

**Files:**
- Create: `client/lib/services/skill_manifest_service.dart`
- Create: `client/test/services/skill_manifest_service_test.dart`

- [ ] Write test `test/services/skill_manifest_service_test.dart` covering: empty manifest returns empty lists; `upsertSkill` then `loadSkills` round-trips; `removeSkill` removes by id; `addBackup` then `loadBackups` round-trips; `pruneBackups(keep: 2)` keeps newest 2 entries. Use a `Directory.systemTemp.createTempSync` override path injected via a constructor parameter `String rootDir` so the service does not depend on `AppStorage`.

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashskyai_client/models/skill.dart';
import 'package:flashskyai_client/services/skill_manifest_service.dart';

void main() {
  late Directory tmp;
  late SkillManifestService svc;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill_manifest_test_');
    svc = SkillManifestService(rootDir: tmp.path);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Skill mkSkill(String id, {String? hash}) => Skill(
    id: id,
    name: id,
    description: '',
    directory: id,
    installedAt: 1,
    updatedAt: 1,
    contentHash: hash,
  );

  test('empty manifest returns empty lists', () async {
    expect(await svc.loadSkills(), isEmpty);
    expect(await svc.loadBackups(), isEmpty);
  });

  test('upsert then load round-trips', () async {
    await svc.upsertSkill(mkSkill('a'));
    await svc.upsertSkill(mkSkill('b'));
    final loaded = await svc.loadSkills();
    expect(loaded.map((s) => s.id), unorderedEquals(['a', 'b']));
  });

  test('upsert replaces existing id', () async {
    await svc.upsertSkill(mkSkill('a', hash: 'h1'));
    await svc.upsertSkill(mkSkill('a', hash: 'h2'));
    final loaded = await svc.loadSkills();
    expect(loaded, hasLength(1));
    expect(loaded.single.contentHash, 'h2');
  });

  test('removeSkill removes by id', () async {
    await svc.upsertSkill(mkSkill('a'));
    await svc.upsertSkill(mkSkill('b'));
    await svc.removeSkill('a');
    expect((await svc.loadSkills()).map((s) => s.id), ['b']);
  });

  test('backups round-trip and prune keeps newest', () async {
    for (var i = 0; i < 5; i++) {
      await svc.addBackup(SkillBackup(
        backupId: 'b$i',
        backupPath: '/tmp/b$i',
        createdAt: i,
        skill: mkSkill('s$i'),
      ));
    }
    await svc.pruneBackups(keep: 2);
    final backups = await svc.loadBackups();
    expect(backups.map((b) => b.backupId), unorderedEquals(['b3', 'b4']));
  });
}
```

- [ ] Run: `cd client && flutter test test/services/skill_manifest_service_test.dart`. Expected: all FAIL (service does not exist).

- [ ] Create `client/lib/services/skill_manifest_service.dart`:

```dart
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
    return list.map((e) => Skill.fromJson((e as Map).cast<String, Object?>())).toList();
  }

  Future<List<SkillBackup>> loadBackups() async {
    final m = await _read();
    final list = (m['backups'] as List<dynamic>?) ?? const [];
    return list.map((e) => SkillBackup.fromJson((e as Map).cast<String, Object?>())).toList();
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

  /// Returns the pruned (removed) backups so callers can delete payloads.
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
    if (!file.existsSync()) return {'version': 1, 'skills': [], 'backups': []};
    try {
      final text = await file.readAsString();
      final parsed = json.decode(text);
      if (parsed is! Map) throw SkillManifestException('manifest root is not an object');
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
```

- [ ] Run tests again. Expected: all PASS.

- [ ] Commit: `feat(skills): SkillManifestService for installed+backup index`

---

## Task 3: SKILL.md frontmatter parser + SkillFetchService (TDD on parser only)

The fetch service is hard to test without network mocking; we test the pure parser independently and treat the network layer as integration.

**Files:**
- Create: `client/lib/services/skill_fetch_service.dart`
- Create: `client/test/services/skill_fetch_service_test.dart`

- [ ] Write parser tests in `skill_fetch_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flashskyai_client/services/skill_fetch_service.dart';

void main() {
  group('parseFrontmatter', () {
    test('extracts name and description', () {
      const src = '---\nname: foo\ndescription: bar baz\n---\nbody';
      final fm = parseSkillFrontmatter(src);
      expect(fm.name, 'foo');
      expect(fm.description, 'bar baz');
    });

    test('handles quoted values and trailing comments', () {
      const src = '---\nname: "foo bar"\ndescription: \'hello\'\n---\n';
      final fm = parseSkillFrontmatter(src);
      expect(fm.name, 'foo bar');
      expect(fm.description, 'hello');
    });

    test('missing name throws', () {
      const src = '---\ndescription: bar\n---\n';
      expect(() => parseSkillFrontmatter(src), throwsA(isA<SkillParseException>()));
    });

    test('no frontmatter throws', () {
      expect(() => parseSkillFrontmatter('just a body'), throwsA(isA<SkillParseException>()));
    });

    test('skips webServer subtree without crashing', () {
      const src = '---\nname: foo\ndescription: bar\nwebServer:\n  command: "x"\n  port: 3000\n---\n';
      final fm = parseSkillFrontmatter(src);
      expect(fm.name, 'foo');
    });
  });
}
```

- [ ] Run: `cd client && flutter test test/services/skill_fetch_service_test.dart`. Expected: FAIL (missing service).

- [ ] Create `client/lib/services/skill_fetch_service.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/skill.dart';

class SkillFetchException implements Exception {
  SkillFetchException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => 'SkillFetchException: $message';
}

class SkillParseException implements Exception {
  SkillParseException(this.message);
  final String message;
  @override
  String toString() => 'SkillParseException: $message';
}

class SkillFrontmatter {
  SkillFrontmatter({required this.name, required this.description});
  final String name;
  final String description;
}

SkillFrontmatter parseSkillFrontmatter(String text) {
  // Normalize line endings.
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') {
    throw SkillParseException('Missing frontmatter');
  }
  // Find closing '---'.
  var end = -1;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim() == '---') {
      end = i;
      break;
    }
  }
  if (end < 0) throw SkillParseException('Unterminated frontmatter');

  String? name;
  String? description;
  var skipIndent = false;
  for (var i = 1; i < end; i++) {
    final raw = lines[i];
    if (skipIndent) {
      if (raw.startsWith(' ') || raw.startsWith('\t')) continue;
      skipIndent = false;
    }
    final line = raw.trimRight();
    if (line.isEmpty || line.startsWith('#')) continue;
    final colonIdx = line.indexOf(':');
    if (colonIdx < 0) continue;
    final key = line.substring(0, colonIdx).trim();
    final value = line.substring(colonIdx + 1).trim();
    if (value.isEmpty) {
      // Subtree (e.g. webServer:) — skip indented lines that follow.
      skipIndent = true;
      continue;
    }
    final unq = _unquote(value);
    if (key == 'name') name = unq;
    if (key == 'description') description = unq;
  }
  if (name == null || name.trim().isEmpty) {
    throw SkillParseException('Missing required "name" in frontmatter');
  }
  return SkillFrontmatter(name: name, description: description ?? '');
}

String _unquote(String v) {
  if (v.length >= 2) {
    final first = v.codeUnitAt(0);
    final last = v.codeUnitAt(v.length - 1);
    if ((first == 0x22 && last == 0x22) || (first == 0x27 && last == 0x27)) {
      return v.substring(1, v.length - 1);
    }
  }
  return v;
}

class TarballPayload {
  TarballPayload({required this.entries});
  /// Entries keyed by relative path inside the repo (top prefix stripped).
  final Map<String, Uint8List> entries;
}

class SkillFetchService {
  SkillFetchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, _CacheEntry> _cache = {};
  static const _cacheTtl = Duration(hours: 1);

  Future<TarballPayload> fetchTarball(SkillRepo repo) async {
    final key = '${repo.owner}/${repo.name}@${repo.branch}';
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      return cached.payload;
    }
    final payload = await _downloadAndDecode(repo);
    _cache[key] = _CacheEntry(payload, DateTime.now());
    return payload;
  }

  Future<TarballPayload> _downloadAndDecode(SkillRepo repo) async {
    final url = Uri.parse(
      'https://codeload.github.com/${repo.owner}/${repo.name}/tar.gz/${repo.branch}',
    );
    final resp = await _client.get(url);
    if (resp.statusCode != 200) {
      throw SkillFetchException('GitHub tarball ${resp.statusCode} for ${repo.fullName}');
    }
    try {
      final gunzipped = GZipDecoder().decodeBytes(resp.bodyBytes);
      final archive = TarDecoder().decodeBytes(gunzipped);
      final entries = <String, Uint8List>{};
      String? prefix;
      for (final file in archive) {
        if (!file.isFile) continue;
        final fullName = file.name;
        prefix ??= fullName.split('/').first + '/';
        if (!fullName.startsWith(prefix)) continue;
        final rel = fullName.substring(prefix.length);
        if (rel.isEmpty) continue;
        entries[rel] = Uint8List.fromList(file.content as List<int>);
      }
      return TarballPayload(entries: entries);
    } catch (e) {
      throw SkillFetchException('Failed to decode tarball for ${repo.fullName}', e);
    }
  }

  Future<List<DiscoverableSkill>> listSkills(SkillRepo repo) async {
    final payload = await fetchTarball(repo);
    final byDir = <String, Uint8List>{};
    for (final entry in payload.entries.entries) {
      final parts = entry.key.split('/');
      if (parts.length >= 2 && parts.last == 'SKILL.md') {
        byDir[parts.sublist(0, parts.length - 1).join('/')] = entry.value;
      }
    }
    final result = <DiscoverableSkill>[];
    for (final e in byDir.entries) {
      final dir = e.key;
      final basename = p.basename(dir);
      try {
        final fm = parseSkillFrontmatter(String.fromCharCodes(e.value));
        result.add(DiscoverableSkill(
          key: '${repo.owner}/${repo.name}:$basename',
          name: fm.name,
          description: fm.description,
          directory: dir,
          readmeUrl: 'https://github.com/${repo.owner}/${repo.name}/tree/${repo.branch}/$dir',
          repoOwner: repo.owner,
          repoName: repo.name,
          repoBranch: repo.branch,
        ));
      } on SkillParseException {
        // Skip unparseable skills silently; caller can log.
        continue;
      }
    }
    return result;
  }

  /// Returns the relative paths inside the tarball that belong to [directory]
  /// (which is the in-repo path, e.g. `web-research/find-skills`).
  Future<Map<String, Uint8List>> downloadSkillFiles(SkillRepo repo, String directory) async {
    final payload = await fetchTarball(repo);
    final prefix = '$directory/';
    final out = <String, Uint8List>{};
    for (final e in payload.entries.entries) {
      if (e.key.startsWith(prefix)) {
        out[e.key.substring(prefix.length)] = e.value;
      }
    }
    if (out.isEmpty) {
      throw SkillFetchException('Skill directory "$directory" not found in ${repo.fullName}');
    }
    return out;
  }

  /// Fetches raw SKILL.md content for update checks. Returns null on 404.
  Future<String?> fetchRawSkillMd({
    required String owner,
    required String name,
    required String branch,
    required String directory,
  }) async {
    final url = Uri.parse(
      'https://raw.githubusercontent.com/$owner/$name/$branch/$directory/SKILL.md',
    );
    final resp = await _client.get(url);
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw SkillFetchException('raw SKILL.md ${resp.statusCode} for $owner/$name');
    }
    return resp.body;
  }

  void close() => _client.close();
}

class _CacheEntry {
  _CacheEntry(this.payload, this.fetchedAt);
  final TarballPayload payload;
  final DateTime fetchedAt;
}
```

- [ ] Run tests. Expected: PASS.

- [ ] Commit: `feat(skills): SkillFetchService with GitHub tarball + frontmatter parser`

---

## Task 4: SkillInstallService (TDD on file ops)

Pure file operations: write payload, move to backup, restore, scan unmanaged, install-from-zip. No network.

**Files:**
- Create: `client/lib/services/skill_install_service.dart`
- Create: `client/test/services/skill_install_service_test.dart`

- [ ] Write tests for `installLocal`, `uninstall`, `restoreBackup`, `scanUnmanaged`. Mock the manifest service in-memory.

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flashskyai_client/models/skill.dart';
import 'package:flashskyai_client/services/skill_install_service.dart';
import 'package:flashskyai_client/services/skill_manifest_service.dart';

void main() {
  late Directory tmp;
  late SkillManifestService manifest;
  late SkillInstallService svc;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill_install_test_');
    manifest = SkillManifestService(rootDir: tmp.path);
    svc = SkillInstallService(manifest: manifest);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('installLocal writes files and inserts manifest entry', () async {
    final payload = <String, Uint8List>{
      'SKILL.md': Uint8List.fromList('---\nname: foo\ndescription: d\n---\nbody'.codeUnits),
      'extras/x.txt': Uint8List.fromList('hello'.codeUnits),
    };
    final s = await svc.installLocal(
      basename: 'foo',
      files: payload,
      repoOwner: null,
      repoName: null,
      repoBranch: null,
      readmeUrl: null,
      name: 'foo',
      description: 'd',
    );
    expect(s.id, 'local:foo');
    expect(File(p.join(tmp.path, 'skills/foo/SKILL.md')).existsSync(), isTrue);
    expect(File(p.join(tmp.path, 'skills/foo/extras/x.txt')).existsSync(), isTrue);
    final installed = await manifest.loadSkills();
    expect(installed.single.id, 'local:foo');
  });

  test('uninstall moves files to skill-backups and adds backup row', () async {
    final payload = <String, Uint8List>{
      'SKILL.md': Uint8List.fromList('---\nname: foo\ndescription: d\n---\n'.codeUnits),
    };
    final s = await svc.installLocal(
      basename: 'foo', files: payload, repoOwner: null, repoName: null,
      repoBranch: null, readmeUrl: null, name: 'foo', description: 'd',
    );
    final backup = await svc.uninstall(s);
    expect(Directory(p.join(tmp.path, 'skills/foo')).existsSync(), isFalse);
    expect(Directory(backup.backupPath).existsSync(), isTrue);
    final backups = await manifest.loadBackups();
    expect(backups.single.backupId, backup.backupId);
  });

  test('restoreBackup moves payload back and reinserts manifest', () async {
    final payload = <String, Uint8List>{
      'SKILL.md': Uint8List.fromList('---\nname: foo\ndescription: d\n---\n'.codeUnits),
    };
    final s = await svc.installLocal(
      basename: 'foo', files: payload, repoOwner: null, repoName: null,
      repoBranch: null, readmeUrl: null, name: 'foo', description: 'd',
    );
    final backup = await svc.uninstall(s);
    final restored = await svc.restoreBackup(backup);
    expect(restored.id, s.id);
    expect(Directory(p.join(tmp.path, 'skills/foo')).existsSync(), isTrue);
    expect(Directory(backup.backupPath).existsSync(), isFalse);
    expect((await manifest.loadBackups()), isEmpty);
  });

  test('scanUnmanaged finds skill dirs not in manifest', () async {
    Directory(p.join(tmp.path, 'skills/orphan')).createSync(recursive: true);
    File(p.join(tmp.path, 'skills/orphan/SKILL.md'))
        .writeAsStringSync('---\nname: orphan\ndescription: yes\n---\n');
    final scanned = await svc.scanUnmanaged();
    expect(scanned.single.directory, 'orphan');
    expect(scanned.single.name, 'orphan');
  });
}
```

- [ ] Run: `cd client && flutter test test/services/skill_install_service_test.dart`. Expected: FAIL.

- [ ] Create `client/lib/services/skill_install_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
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
  SkillInstallService({
    required this.manifest,
    SkillFetchService? fetch,
  }) : fetch = fetch ?? SkillFetchService();

  final SkillManifestService manifest;
  final SkillFetchService fetch;
  static const int backupRetention = 20;

  String _basename(String directory) => p.basename(directory);

  String _idFor({String? repoOwner, String? repoName, required String basename}) {
    if (repoOwner != null && repoName != null) return '$repoOwner/$repoName:$basename';
    return 'local:$basename';
  }

  String _skillPath(String basename) => p.join(manifest.skillsDir, basename);

  String _hashSkillMd(Map<String, Uint8List> files) {
    final bytes = files['SKILL.md'];
    if (bytes == null) throw SkillInstallException('payload missing SKILL.md');
    return sha256.convert(bytes).toString();
  }

  /// Installs a payload that is already in memory.
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
        throw SkillInstallException('A skill already exists at ${dir.path}');
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
    final id = _idFor(repoOwner: repoOwner, repoName: repoName, basename: basename);
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

  /// Installs from a discovered skill by re-fetching its files.
  Future<Skill> installFromDiscovery(
    DiscoverableSkill d, {
    bool overwrite = false,
  }) async {
    final repo = SkillRepo(owner: d.repoOwner, name: d.repoName, branch: d.repoBranch);
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

  /// Installs all skills found inside a ZIP file. Each top-level subdir with a
  /// SKILL.md is treated as one skill.
  Future<List<Skill>> installFromZip(File zipFile, {bool overwrite = false}) async {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final byDir = <String, Map<String, Uint8List>>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      final parts = file.name.split('/');
      if (parts.length < 2) continue;
      // Skip macOS metadata.
      if (parts.any((p) => p == '__MACOSX')) continue;
      final dir = parts.first;
      final rel = parts.sublist(1).join('/');
      (byDir[dir] ??= {})[rel] = Uint8List.fromList(file.content as List<int>);
    }
    final installed = <Skill>[];
    for (final entry in byDir.entries) {
      final files = entry.value;
      if (!files.containsKey('SKILL.md')) continue;
      try {
        final fm = parseSkillFrontmatter(String.fromCharCodes(files['SKILL.md']!));
        installed.add(await installLocal(
          basename: entry.key,
          files: files,
          repoOwner: null,
          repoName: null,
          repoBranch: null,
          readmeUrl: null,
          name: fm.name,
          description: fm.description,
          overwrite: overwrite,
        ));
      } on SkillParseException catch (e) {
        appLogger.w('[skills] zip entry ${entry.key} skipped: ${e.message}');
      }
    }
    return installed;
  }

  Future<SkillBackup> uninstall(Skill skill) async {
    final src = Directory(_skillPath(skill.directory));
    if (!src.existsSync()) {
      // Manifest had a row but no payload — still drop the row, return synthetic backup.
      await manifest.removeSkill(skill.id);
      throw SkillInstallException('Skill directory ${src.path} missing on disk');
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
        appLogger.w('[skills] failed to delete pruned backup ${d.backupPath}: $e');
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
    final installed = (await manifest.loadSkills()).map((s) => s.directory).toSet();
    final out = <UnmanagedSkill>[];
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final basename = p.basename(entity.path);
      if (installed.contains(basename)) continue;
      final skillMd = File(p.join(entity.path, 'SKILL.md'));
      if (!skillMd.existsSync()) continue;
      try {
        final fm = parseSkillFrontmatter(await skillMd.readAsString());
        out.add(UnmanagedSkill(
          directory: basename,
          name: fm.name,
          description: fm.description,
          path: entity.path,
        ));
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

  /// Computes update list for installed skills that originate from a repo.
  Future<List<SkillUpdateInfo>> checkUpdates(List<Skill> installed) async {
    final updates = <SkillUpdateInfo>[];
    for (final s in installed) {
      if (s.repoOwner == null || s.repoName == null || s.repoBranch == null) continue;
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
          updates.add(SkillUpdateInfo(
            id: s.id,
            name: s.name,
            currentHash: s.contentHash,
            remoteHash: remoteHash,
          ));
        }
      } catch (e) {
        appLogger.w('[skills] update check failed for ${s.id}: $e');
      }
    }
    return updates;
  }

  Future<Skill> updateSkill(Skill skill) async {
    if (skill.repoOwner == null || skill.repoName == null || skill.repoBranch == null) {
      throw SkillInstallException('Skill ${skill.id} has no repo origin to update from');
    }
    // Back up the current payload first.
    final backup = await uninstall(skill);
    try {
      final repo = SkillRepo(
        owner: skill.repoOwner!,
        name: skill.repoName!,
        branch: skill.repoBranch!,
      );
      // Locate the in-repo path: prefer `<basename>` at the repo root unless we
      // know a deeper path. We persist only the basename, so try common shapes:
      // first try the basename directly; if missing, search.
      final fullPayload = await fetch.fetchTarball(repo);
      String? matchPath;
      for (final key in fullPayload.entries.keys) {
        final parts = key.split('/');
        if (parts.length >= 2 && parts.last == 'SKILL.md' && parts[parts.length - 2] == skill.directory) {
          matchPath = parts.sublist(0, parts.length - 1).join('/');
          break;
        }
      }
      if (matchPath == null) {
        throw SkillInstallException('Could not locate ${skill.directory} in ${repo.fullName}');
      }
      final files = await fetch.downloadSkillFiles(repo, matchPath);
      final fm = parseSkillFrontmatter(String.fromCharCodes(files['SKILL.md']!));
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
      // Best-effort rollback.
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
    await for (final entity in src.list(recursive: true, followLinks: false)) {
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
```

- [ ] Run tests. Expected: PASS.

- [ ] Commit: `feat(skills): SkillInstallService with install/uninstall/restore/scan`

---

## Task 5: SkillsShService

Pure HTTP. No tests written here (network).

**Files:**
- Create: `client/lib/services/skills_sh_service.dart`

- [ ] Create the file:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/skill.dart';
import 'skill_fetch_service.dart';

class SkillsShResult {
  SkillsShResult({required this.skills, required this.totalCount, required this.query});
  final List<SkillsShEntry> skills;
  final int totalCount;
  final String query;
}

class SkillsShService {
  SkillsShService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<SkillsShResult> search(String query, {int limit = 20, int offset = 0}) async {
    final uri = Uri.parse('https://skills.sh/api/search').replace(queryParameters: {
      'q': query,
      'limit': '$limit',
      'offset': '$offset',
    });
    final resp = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw SkillFetchException('skills.sh HTTP ${resp.statusCode}');
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final list = (body['skills'] as List<dynamic>? ?? []);
    final entries = <SkillsShEntry>[];
    for (final raw in list) {
      final m = (raw as Map).cast<String, Object?>();
      final source = (m['source'] as String?) ?? '';
      final parts = source.split('/');
      if (parts.length != 2) continue;
      final owner = parts[0];
      final repo = parts[1];
      if (owner.contains('.') || repo.contains('.')) continue;
      entries.add(SkillsShEntry(
        key: (m['id'] as String?) ?? '$owner/$repo:${m['skillId']}',
        name: (m['name'] as String?) ?? (m['skillId'] as String? ?? ''),
        directory: (m['skillId'] as String?) ?? '',
        repoOwner: owner,
        repoName: repo,
        repoBranch: 'main',
        readmeUrl: 'https://github.com/$owner/$repo',
        installs: (m['installs'] as int?) ?? 0,
      ));
    }
    return SkillsShResult(
      skills: entries,
      totalCount: (body['count'] as int?) ?? entries.length,
      query: (body['query'] as String?) ?? query,
    );
  }

  void close() => _client.close();
}
```

- [ ] Commit: `feat(skills): skills.sh search service`

---

## Task 6: Extend SkillRepoService

**Files:**
- Modify: `client/lib/services/skill_repo_service.dart`

- [ ] Add two methods to the existing class:

```dart
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
```

- [ ] Commit: `feat(skills): SkillRepoService setEnabled/updateBranch`

---

## Task 7: SkillRepository facade

**Files:**
- Create: `client/lib/repositories/skill_repository.dart`

- [ ] Create the facade (no tests — pure passthrough):

```dart
import 'dart:io';

import '../models/skill.dart';
import '../services/skill_fetch_service.dart';
import '../services/skill_install_service.dart';
import '../services/skill_manifest_service.dart';
import '../services/skill_repo_service.dart';
import '../services/skills_sh_service.dart';

class SkillRepository {
  SkillRepository({
    SkillManifestService? manifest,
    SkillFetchService? fetch,
    SkillInstallService? install,
    SkillRepoService? repos,
    SkillsShService? skillsSh,
  })  : manifest = manifest ?? SkillManifestService(),
        fetch = fetch ?? SkillFetchService(),
        repos = repos ?? const SkillRepoService(),
        skillsSh = skillsSh ?? SkillsShService(),
        install = install ??
            SkillInstallService(
              manifest: manifest ?? SkillManifestService(),
              fetch: fetch,
            );

  final SkillManifestService manifest;
  final SkillFetchService fetch;
  final SkillInstallService install;
  final SkillRepoService repos;
  final SkillsShService skillsSh;

  Future<List<Skill>> loadInstalled() => manifest.loadSkills();
  Future<List<SkillBackup>> loadBackups() => manifest.loadBackups();
  Future<List<SkillRepo>> loadRepos() => repos.loadRepos();

  Future<List<DiscoverableSkill>> discover(List<SkillRepo> enabledRepos) async {
    final futures = enabledRepos
        .where((r) => r.enabled)
        .map((r) async {
          try {
            return await fetch.listSkills(r);
          } catch (_) {
            return const <DiscoverableSkill>[];
          }
        })
        .toList();
    final results = await Future.wait(futures);
    return results.expand((e) => e).toList();
  }

  Future<List<SkillUpdateInfo>> checkUpdates(List<Skill> installed) =>
      install.checkUpdates(installed);

  Future<Skill> installFromDiscovery(DiscoverableSkill d, {bool overwrite = false}) =>
      install.installFromDiscovery(d, overwrite: overwrite);

  Future<List<Skill>> installFromZip(File zip, {bool overwrite = false}) =>
      install.installFromZip(zip, overwrite: overwrite);

  Future<SkillBackup> uninstall(Skill s) => install.uninstall(s);
  Future<Skill> restoreBackup(SkillBackup b) => install.restoreBackup(b);
  Future<void> deleteBackup(SkillBackup b) => install.deleteBackup(b);
  Future<Skill> updateSkill(Skill s) => install.updateSkill(s);

  Future<List<UnmanagedSkill>> scanUnmanaged() => install.scanUnmanaged();
  Future<List<Skill>> importUnmanaged(List<UnmanagedSkill> us) => install.importUnmanaged(us);

  Future<SkillsShResult> searchSkillsSh(String q, {int limit = 20, int offset = 0}) =>
      skillsSh.search(q, limit: limit, offset: offset);

  Future<void> toggleSkillEnabled(Skill s, bool enabled) =>
      manifest.upsertSkill(s.copyWith(enabled: enabled, updatedAt: DateTime.now().millisecondsSinceEpoch));
}
```

- [ ] Commit: `feat(skills): SkillRepository facade`

---

## Task 8: SkillCubit + state

**Files:**
- Create: `client/lib/cubits/skill_cubit.dart`

- [ ] Create the cubit:

```dart
import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/skill.dart';
import '../repositories/skill_repository.dart';
import '../services/skill_fetch_service.dart';
import '../services/skill_install_service.dart';
import '../services/skill_manifest_service.dart';
import '../services/skills_sh_service.dart';
import '../utils/logger.dart';

enum SkillLoadStatus { idle, loading, ready, error }

class SkillsShSearchState extends Equatable {
  const SkillsShSearchState({
    this.query = '',
    this.entries = const [],
    this.totalCount = 0,
    this.offset = 0,
    this.loading = false,
  });
  final String query;
  final List<SkillsShEntry> entries;
  final int totalCount;
  final int offset;
  final bool loading;

  SkillsShSearchState copyWith({
    String? query,
    List<SkillsShEntry>? entries,
    int? totalCount,
    int? offset,
    bool? loading,
  }) =>
      SkillsShSearchState(
        query: query ?? this.query,
        entries: entries ?? this.entries,
        totalCount: totalCount ?? this.totalCount,
        offset: offset ?? this.offset,
        loading: loading ?? this.loading,
      );

  @override
  List<Object?> get props => [query, entries, totalCount, offset, loading];
}

class SkillState extends Equatable {
  const SkillState({
    this.installed = const [],
    this.repos = const [],
    this.discoverable = const [],
    this.updates = const [],
    this.backups = const [],
    this.skillsSh = const SkillsShSearchState(),
    this.status = SkillLoadStatus.idle,
    this.errorMessage,
    this.busyIds = const {},
  });

  final List<Skill> installed;
  final List<SkillRepo> repos;
  final List<DiscoverableSkill> discoverable;
  final List<SkillUpdateInfo> updates;
  final List<SkillBackup> backups;
  final SkillsShSearchState skillsSh;
  final SkillLoadStatus status;
  final String? errorMessage;
  final Set<String> busyIds;

  SkillState copyWith({
    List<Skill>? installed,
    List<SkillRepo>? repos,
    List<DiscoverableSkill>? discoverable,
    List<SkillUpdateInfo>? updates,
    List<SkillBackup>? backups,
    SkillsShSearchState? skillsSh,
    SkillLoadStatus? status,
    String? errorMessage,
    bool clearError = false,
    Set<String>? busyIds,
  }) =>
      SkillState(
        installed: installed ?? this.installed,
        repos: repos ?? this.repos,
        discoverable: discoverable ?? this.discoverable,
        updates: updates ?? this.updates,
        backups: backups ?? this.backups,
        skillsSh: skillsSh ?? this.skillsSh,
        status: status ?? this.status,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        busyIds: busyIds ?? this.busyIds,
      );

  @override
  List<Object?> get props =>
      [installed, repos, discoverable, updates, backups, skillsSh, status, errorMessage, busyIds];
}

class SkillCubit extends Cubit<SkillState> {
  SkillCubit(this._repo) : super(const SkillState());

  final SkillRepository _repo;

  Future<void> loadAll() async {
    emit(state.copyWith(status: SkillLoadStatus.loading, clearError: true));
    try {
      final installed = await _repo.loadInstalled();
      final repos = await _repo.loadRepos();
      final backups = await _repo.loadBackups();
      emit(state.copyWith(
        installed: installed,
        repos: repos,
        backups: backups,
        status: SkillLoadStatus.ready,
      ));
      // Kick off discovery in background.
      unawaited(refreshDiscoverable());
    } catch (e) {
      appLogger.e('[skills] loadAll failed: $e');
      emit(state.copyWith(status: SkillLoadStatus.error, errorMessage: '$e'));
    }
  }

  Future<void> refreshDiscoverable() async {
    try {
      final list = await _repo.discover(state.repos);
      emit(state.copyWith(discoverable: list, clearError: true));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Discovery failed: $e'));
    }
  }

  Future<void> addRepo(SkillRepo repo) async {
    await _repo.repos.addRepo(repo);
    final repos = await _repo.loadRepos();
    emit(state.copyWith(repos: repos));
    unawaited(refreshDiscoverable());
  }

  Future<void> removeRepo(String owner, String name) async {
    await _repo.repos.removeRepo(owner, name);
    final repos = await _repo.loadRepos();
    emit(state.copyWith(repos: repos));
    unawaited(refreshDiscoverable());
  }

  Future<void> toggleRepoEnabled(SkillRepo repo, bool enabled) async {
    await _repo.repos.setEnabled(repo.owner, repo.name, enabled);
    final repos = await _repo.loadRepos();
    emit(state.copyWith(repos: repos));
    unawaited(refreshDiscoverable());
  }

  Future<void> installFromDiscovery(DiscoverableSkill d, {bool overwrite = false}) async {
    final busy = {...state.busyIds, d.key};
    emit(state.copyWith(busyIds: busy, clearError: true));
    try {
      await _repo.installFromDiscovery(d, overwrite: overwrite);
      final installed = await _repo.loadInstalled();
      emit(state.copyWith(installed: installed));
    } on SkillInstallException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    } on SkillFetchException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    } finally {
      final next = {...state.busyIds}..remove(d.key);
      emit(state.copyWith(busyIds: next));
    }
  }

  Future<void> installFromZip(File zip) async {
    emit(state.copyWith(clearError: true));
    try {
      await _repo.installFromZip(zip);
      final installed = await _repo.loadInstalled();
      emit(state.copyWith(installed: installed));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    }
  }

  Future<void> installSkillsShEntry(SkillsShEntry e, {bool overwrite = false}) async {
    final d = DiscoverableSkill(
      key: e.key,
      name: e.name,
      description: '',
      directory: e.directory,
      readmeUrl: e.readmeUrl,
      repoOwner: e.repoOwner,
      repoName: e.repoName,
      repoBranch: e.repoBranch,
    );
    await installFromDiscovery(d, overwrite: overwrite);
  }

  Future<void> uninstall(Skill s) async {
    emit(state.copyWith(clearError: true));
    try {
      await _repo.uninstall(s);
      final installed = await _repo.loadInstalled();
      final backups = await _repo.loadBackups();
      emit(state.copyWith(installed: installed, backups: backups));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    }
  }

  Future<void> toggleSkillEnabled(Skill s, bool enabled) async {
    try {
      await _repo.toggleSkillEnabled(s, enabled);
      final installed = await _repo.loadInstalled();
      emit(state.copyWith(installed: installed));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    }
  }

  Future<void> checkUpdates() async {
    try {
      final updates = await _repo.checkUpdates(state.installed);
      emit(state.copyWith(updates: updates));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    }
  }

  Future<void> updateSkill(Skill s) async {
    emit(state.copyWith(busyIds: {...state.busyIds, s.id}, clearError: true));
    try {
      await _repo.updateSkill(s);
      final installed = await _repo.loadInstalled();
      final backups = await _repo.loadBackups();
      final updates = state.updates.where((u) => u.id != s.id).toList();
      emit(state.copyWith(installed: installed, backups: backups, updates: updates));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    } finally {
      final next = {...state.busyIds}..remove(s.id);
      emit(state.copyWith(busyIds: next));
    }
  }

  Future<void> updateAll() async {
    for (final u in List<SkillUpdateInfo>.from(state.updates)) {
      final match = state.installed.firstWhere(
        (s) => s.id == u.id,
        orElse: () => Skill(
          id: u.id, name: u.name, description: '', directory: '',
          installedAt: 0, updatedAt: 0,
        ),
      );
      if (match.repoOwner == null) continue;
      await updateSkill(match);
    }
  }

  Future<void> restoreBackup(SkillBackup b) async {
    try {
      await _repo.restoreBackup(b);
      final installed = await _repo.loadInstalled();
      final backups = await _repo.loadBackups();
      emit(state.copyWith(installed: installed, backups: backups));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    }
  }

  Future<void> deleteBackup(SkillBackup b) async {
    try {
      await _repo.deleteBackup(b);
      final backups = await _repo.loadBackups();
      emit(state.copyWith(backups: backups));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    }
  }

  Future<List<UnmanagedSkill>> scanUnmanaged() async {
    try {
      return await _repo.scanUnmanaged();
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
      return const [];
    }
  }

  Future<void> importUnmanaged(List<UnmanagedSkill> sel) async {
    try {
      await _repo.importUnmanaged(sel);
      final installed = await _repo.loadInstalled();
      emit(state.copyWith(installed: installed));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    }
  }

  Future<void> searchSkillsSh(String query) async {
    if (query.trim().length < 2) return;
    emit(state.copyWith(
      skillsSh: state.skillsSh.copyWith(loading: true, query: query, offset: 0, entries: const []),
      clearError: true,
    ));
    try {
      final res = await _repo.searchSkillsSh(query, offset: 0);
      emit(state.copyWith(
        skillsSh: SkillsShSearchState(
          query: query,
          entries: res.skills,
          totalCount: res.totalCount,
          offset: res.skills.length,
          loading: false,
        ),
      ));
    } catch (e) {
      emit(state.copyWith(
        skillsSh: state.skillsSh.copyWith(loading: false),
        errorMessage: '$e',
      ));
    }
  }

  Future<void> loadMoreSkillsSh() async {
    if (state.skillsSh.loading) return;
    if (state.skillsSh.entries.length >= state.skillsSh.totalCount) return;
    emit(state.copyWith(skillsSh: state.skillsSh.copyWith(loading: true)));
    try {
      final res = await _repo.searchSkillsSh(state.skillsSh.query, offset: state.skillsSh.offset);
      final merged = [...state.skillsSh.entries, ...res.skills];
      emit(state.copyWith(
        skillsSh: state.skillsSh.copyWith(
          entries: merged,
          offset: merged.length,
          totalCount: res.totalCount,
          loading: false,
        ),
      ));
    } catch (e) {
      emit(state.copyWith(
        skillsSh: state.skillsSh.copyWith(loading: false),
        errorMessage: '$e',
      ));
    }
  }

  void clearError() => emit(state.copyWith(clearError: true));
}
```

- [ ] Commit: `feat(skills): SkillCubit state + ops`

---

## Task 9: i18n keys

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Regenerate: `client/lib/l10n/app_localizations*.dart` (run `flutter gen-l10n`)

- [ ] Read existing arb files to learn shape and prefix conventions.
- [ ] Add the following keys to both arb files (English first, then Chinese translations):

```
skillsTitle: "Skills" / "Skills"
skillsSubtitle: "Manage installable skills" / "管理可安装的 Skill"
skillsSidebarLabel: "Skills" / "Skills"
skillsNavInstalled: "Installed" / "已安装"
skillsNavDiscovery: "Discovery" / "发现"
skillsNavRepos: "Repos" / "仓库"
skillsNavBackups: "Backups" / "备份"
skillsInstalledCount({count}): "{count} installed" / "已安装 {count}"
skillsCheckUpdates: "Check updates" / "检查更新"
skillsCheckingUpdates: "Checking…" / "检查中…"
skillsUpdateAll({count}): "Update all ({count})" / "全部更新 ({count})"
skillsImportFromDisk: "Import from disk" / "从磁盘导入"
skillsInstallFromZip: "Install from ZIP" / "从 ZIP 安装"
skillsNoInstalled: "No skills installed yet" / "还没有安装 Skill"
skillsNoInstalledHint: "Open Discovery to install your first skill." / "打开发现页安装你的第一个 Skill。"
skillsSourceRepos: "Repos" / "仓库"
skillsSourceSkillsSh: "skills.sh" / "skills.sh"
skillsSearchPlaceholder: "Search skills…" / "搜索 Skill…"
skillsSkillsShPlaceholder: "Search skills.sh (≥ 2 chars)…" / "搜索 skills.sh (≥2 字)…"
skillsFilterRepoAll: "All repos" / "所有仓库"
skillsFilterAll: "All" / "全部"
skillsFilterInstalled: "Installed" / "已安装"
skillsFilterUninstalled: "Not installed" / "未安装"
skillsCardInstall: "Install" / "安装"
skillsCardInstalled: "Installed" / "已安装"
skillsCardUpdate: "Update" / "更新"
skillsCardUninstall: "Uninstall" / "卸载"
skillsLocal: "local" / "本地"
skillsReposEmpty: "No repos yet" / "暂无仓库"
skillsRepoAdd: "Add repo" / "添加仓库"
skillsRepoOwner: "Owner" / "Owner"
skillsRepoName: "Name" / "Name"
skillsRepoBranch: "Branch" / "分支"
skillsRepoRemove: "Remove" / "移除"
skillsRepoRemoveConfirm({name}): "Remove repo {name}?" / "确认移除仓库 {name}？"
skillsBackupsEmpty: "No backups yet" / "暂无备份"
skillsBackupRestore: "Restore" / "恢复"
skillsBackupDelete: "Delete" / "删除"
skillsBackupDeleteConfirm({name}): "Delete backup {name}? This cannot be undone." / "删除备份 {name}？此操作不可撤销。"
skillsBackupCreatedAt: "Created at" / "创建时间"
skillsUninstallConfirm({name}): "Uninstall {name}? Files will be moved to backups." / "卸载 {name}？文件会移入备份目录。"
skillsOverwriteConfirm({name}): "{name} already installed. Overwrite?" / "{name} 已安装。是否覆盖？"
skillsInstallSuccess({name}): "Installed {name}" / "已安装 {name}"
skillsUninstallSuccess({name}): "Uninstalled {name}" / "已卸载 {name}"
skillsUpdateSuccess({name}): "Updated {name}" / "已更新 {name}"
skillsNoUpdates: "All skills are up to date" / "所有 Skill 均为最新"
skillsImportTitle: "Import unmanaged skills" / "导入未管理的 Skill"
skillsImportNothing: "No unmanaged skills found." / "未发现未管理的 Skill。"
skillsImportSelected({count}): "Import {count} selected" / "导入选中 {count} 个"
skillsZipNoSkills: "No SKILL.md found in the archive." / "压缩包中未发现 SKILL.md。"
skillsSkillsShLoadMore: "Load more" / "加载更多"
skillsSkillsShPoweredBy: "Powered by skills.sh" / "由 skills.sh 提供"
```

- [ ] Run from `client/`:

```bash
flutter gen-l10n
```

- [ ] Commit: `feat(skills): localization keys`

---

## Task 10: Sidebar entry

**Files:**
- Modify: `client/lib/widgets/context_sidebar.dart`

- [ ] At the top of the `Column` children in `_ContextSidebarState.build`, before `_TeamSelector`, insert:

```dart
_SkillTile(
  onTap: () {
    FramePerf.mark('nav skills');
    context.go('/skills');
  },
),
const SizedBox(height: 14),
```

- [ ] Add a new private widget at the bottom of the file, modeled on `_TeamConfigTile` but with `Icons.auto_awesome_outlined` and `l10n.skillsSidebarLabel`:

```dart
class _SkillTile extends StatelessWidget {
  const _SkillTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 18, color: textBase),
              const SizedBox(width: 10),
              Text(
                context.l10n.skillsSidebarLabel,
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

- [ ] Commit: `feat(skills): sidebar entry above team selector`

---

## Task 11: Route + cubit registration

**Files:**
- Modify: `client/lib/router/app_router.dart`
- Modify: `client/lib/main.dart`

- [ ] Add to `app_router.dart` routes (next to `/team-config`):

```dart
GoRoute(
  path: '/skills',
  pageBuilder: (context, state) => const NoTransitionPage(
    child: SkillManagementPage(),
  ),
),
```

Also add the import `import '../pages/skill_management_page.dart';`.

- [ ] In `main.dart`, register `SkillCubit` in the existing `MultiBlocProvider` (or whatever Bloc container is used). Look at `team_cubit.dart`'s wiring and mirror it. Construct with `SkillRepository()` defaults. Call `..loadAll()` on instantiation.

- [ ] Commit: `feat(skills): /skills route + cubit provider`

---

## Task 12: SkillManagementPage skeleton

**Files:**
- Create: `client/lib/pages/skill_management_page.dart`

- [ ] Implement the page. Reuse `_TitleBar`, `_NavPanel`, `_Card`, `_CardHeader`, `_FieldLabel` styles from `team_config_page.dart`; for brevity, copy the small private widgets verbatim (rename to avoid clashes if necessary, e.g. `_SkillsCard`).

Section enum and shell:

```dart
enum SkillSection { installed, discovery, repos, backups }

class SkillManagementPage extends StatefulWidget {
  const SkillManagementPage({super.key});
  @override
  State<SkillManagementPage> createState() => _SkillManagementPageState();
}

class _SkillManagementPageState extends State<SkillManagementPage> {
  SkillSection _section = SkillSection.installed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    return BlocConsumer<SkillCubit, SkillState>(
      listenWhen: (a, b) => a.errorMessage != b.errorMessage && b.errorMessage != null,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.errorMessage!), duration: const Duration(seconds: 4)),
        );
        context.read<SkillCubit>().clearError();
      },
      builder: (context, state) {
        return Container(
          color: colors.workspaceBackground,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TitleBar(title: l10n.skillsTitle, subtitle: l10n.skillsSubtitle),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 820;
                    final navWidth = compact ? 220.0 : 280.0;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: navWidth,
                          child: _NavPanel(
                            section: _section,
                            compact: compact,
                            l10n: l10n,
                            onSelect: (s) => setState(() => _section = s),
                          ),
                        ),
                        Container(width: 1, color: colors.subtleBorder),
                        Expanded(
                          child: Padding(
                            padding: compact
                                ? const EdgeInsets.fromLTRB(20, 24, 20, 20)
                                : const EdgeInsets.fromLTRB(36, 32, 44, 28),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 1120),
                                child: switch (_section) {
                                  SkillSection.installed => InstalledSection(state: state),
                                  SkillSection.discovery => DiscoverySection(state: state),
                                  SkillSection.repos => ReposSection(state: state),
                                  SkillSection.backups => BackupsSection(state: state),
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] Implement `_TitleBar`, `_NavPanel`, `_NavItem`, `_Card`, `_CardHeader`, `_FieldLabel` — copy from `team_config_page.dart` (or factor into a shared file under `lib/widgets/`, but for now duplication is acceptable to stay scoped).

- [ ] Commit: `feat(skills): SkillManagementPage shell`

---

## Task 13: Installed section

Inside `skill_management_page.dart`:

- [ ] Implement `InstalledSection`:
  - Top row: count text on the left, buttons `Import from disk` / `Install from ZIP` / `Check updates` on the right; `Update all (N)` button appears when `state.updates.isNotEmpty`.
  - Empty state when `state.installed.isEmpty` — icon + heading + hint, plus a `TextButton` that switches to `SkillSection.discovery`.
  - List view of `_InstalledSkillRow` widgets rendering: name, optional external link, source badge (`repoOwner/repoName` or `skillsLocal`), update badge, description (truncated), enable `Switch`, hover actions (`Update`, `Uninstall`).
  - Buttons call cubit methods. Confirm dialogs use `AlertDialog` like `_confirmDeleteProject`.
  - `Import from disk`: calls `cubit.scanUnmanaged()` → if empty, shows snackbar; else opens `ImportUnmanagedDialog`.
  - `Install from ZIP`: `file_picker.pickFiles(type: FileType.custom, allowedExtensions: ['zip'])` → if selected, call `cubit.installFromZip(File(path))`.

- [ ] Implement `ImportUnmanagedDialog`: stateful, list with checkboxes, `Import selected` button. On submit calls `cubit.importUnmanaged(selected)`.

- [ ] Commit: `feat(skills): installed section + import dialog`

---

## Task 14: Discovery section

- [ ] Implement `DiscoverySection`:
  - Top: segmented control `Repos` / `skills.sh`. Track local state `searchSource` and `searchQuery` in the section's `State`.
  - Repos mode:
    - Filter: `searchQuery` (`TextField`), `filterRepo` (`DropdownButtonFormField<String>`) with options derived from `state.discoverable`, `filterStatus` (`DropdownButtonFormField<String>`) — all/installed/uninstalled.
    - Grid of `_SkillCard` widgets (3 columns ≥ 1100, 2 columns ≥ 700, else 1).
    - Each card: name, description (truncated), source, `Install` / `Installed` button. `Install` is disabled when `state.busyIds.contains(card.key)`.
  - skills.sh mode:
    - Input field with submit button; calls `cubit.searchSkillsSh(q)`; on Enter triggers same.
    - Renders `state.skillsSh.entries` as cards; `Load more` button when `entries.length < totalCount`.
  - If `state.discoverable.isEmpty && !loading` and source is repos, render an inline hint linking to Repos section.

- [ ] Commit: `feat(skills): discovery section (repos + skills.sh)`

---

## Task 15: Repos section

- [ ] Implement `ReposSection`:
  - Top: `_Card` with title `Repos`, body containing the list of `state.repos` rows.
    - Each row: `owner/name` text, branch chip, enable `Switch`, `Remove` `IconButton`. Confirm-on-remove dialog.
  - Below: `_Card` with title `Add repo`, three `TextField`s (`owner`, `name`, `branch`) and a `FilledButton(Add)`. On submit: validate non-empty owner & name; default branch to `main` if empty; call `cubit.addRepo`.

- [ ] Commit: `feat(skills): repos section`

---

## Task 16: Backups section

- [ ] Implement `BackupsSection`:
  - Empty state when `state.backups.isEmpty`.
  - Otherwise list `_BackupRow`s: name, directory chip, description (if any), `Created at` row (localized using `MaterialLocalizations`), full path (truncated with tooltip), `Restore` / `Delete` buttons. Confirm-on-delete dialog.

- [ ] Commit: `feat(skills): backups section`

---

## Task 17: Final wiring & verification

- [ ] Run `cd client && flutter analyze`. Fix any errors/warnings introduced.
- [ ] Run `cd client && flutter test`. Expected: all new tests PASS; pre-existing tests still PASS.
- [ ] Build smoke test: `cd client && flutter build linux --debug` (or whichever platform is set up). If the build environment isn't available, skip but note in the final summary.
- [ ] Manual check (developer responsibility, listed for completeness): launch the app, click the new sidebar entry, navigate through all four sections. Expected: page renders, lists load, Add repo / Discovery → Install / Uninstall / Backup restore all work end-to-end against a real GitHub repo.
- [ ] Commit any analyzer fix-ups: `chore(skills): analyzer cleanup`

---

## Self-Review

- **Spec coverage:** §2 disk layout (T2), §3 model (T1), §4 services (T2–T5), §5 cubit (T7–T8), §6 UI sections (T12–T16), §7 i18n (T9), §8.1–8.8 operations (T2–T8), §9 error model (named exceptions in T2–T4).
- **Placeholder scan:** No "TBD" / "TODO" / "implement later". The only deferred items are the developer-side manual smoke test (T17 step 4) and the optional platform build (T17 step 3), which are documented as such.
- **Type consistency:** `Skill.id` shape and dedup key match across T1 spec, T4 install code, and T8 cubit. `SkillBackup.backupId` shape `<basename>-<unixSeconds>` consistent across T2/T4. Service constructor signatures (`rootDir`, `manifest`, `fetch`) consistent between T2/T4/T7.
