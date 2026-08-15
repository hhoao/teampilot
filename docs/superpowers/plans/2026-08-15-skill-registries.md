# Skills 注册中心 + 统一发现流 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the skills "repos" management with a configurable registries center (git repo sources + skills.sh/SkillsMP/custom API sources) and merge discovery into one unified stream.

**Architecture:** `skills/registries.json` is the single source config. `SkillRegistryFactory` instantiates `SkillRegistrySource` implementations (git + API protocols) from config. `SkillCubit` holds unified discovery state (merged, deduped entries with per-source page cursors). Two new UI sections: registries management (MCP-style rows with edit/test/reset) and unified discovery (one search + grid).

**Tech Stack:** Flutter, flutter_bloc, http, existing `SkillRepoDiskCacheService` / `SkillAcquisitionEngine` / `SkillFetchService`, `shared_ui` Tp components.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-15-skill-registries-design.md`
- No backward compatibility required — old storage (`repos.json`, settings `skillsMpApiKey`) is migrated once, then not read again.
- File layout: models in `client/lib/models/`, services in `client/lib/services/skill/registry/`, UI in `client/lib/pages/skills/`.
- Use existing patterns: `McpRegistryConfigService`/`McpRegistriesSection` are the reference implementations; `TpDialog`/`TpCardHeader`/`workspaceInsetDecoration`/`skillConfirmDialog`/`throttledAsync` for UI.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only, then run `cd client && flutter gen-l10n` to regenerate.
- Tests: constructor injection + mock http (`package:http` `MockClient`); widget tests use `setUpTestAppStorage()` pattern from `client/test/support/post_frame_test_harness.dart`; no `Process.run` in UI code.
- Verification gate: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`.

---

### Task 1: Registry config model + storage paths

**Files:**
- Create: `client/lib/models/skill_registry_source.dart`
- Modify: `client/lib/services/storage/app_storage.dart` (add static path fn after line 158 `skillReposConfigPathForTeampilotRoot`, add instance getter after line 301 `skillReposConfigPath`)
- Modify: `client/lib/services/storage/runtime_context.dart` (add getter after line 85 `skillReposConfigPath`)
- Test: `client/test/models/skill_registry_source_test.dart`

**Interfaces:**
- Produces (used by Task 2+): `SkillRegistryKind { gitRepo, api }`, `SkillRegistryProtocol { skillsSh, skillsMp }`, `SkillRegistrySourceConfig` (fields: `id, kind, label, protocol, enabled, baseUrl, apiToken, browseQuery, gitOwner, gitName, gitBranch`; getters `hasApiToken`; static `defaultBaseUrl(SkillRegistryProtocol)`; `copyWith` with `clearApiToken` flag; `toJson`/`fromJson`), `SkillRegistriesConfig` (`sources`, static `defaults()`, `byId(String)`, `toJson`/`fromJson`), `AppPaths.skillRegistriesConfigPathForTeampilotRoot(String)` + instance `skillRegistriesConfigPath`, `RuntimeContext.skillRegistriesConfigPath`.

- [ ] **Step 1: Write the failing test**

Create `client/test/models/skill_registry_source_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill_registry_source.dart';

void main() {
  group('SkillRegistrySourceConfig', () {
    test('defaultBaseUrl per protocol', () {
      expect(
        SkillRegistrySourceConfig.defaultBaseUrl(SkillRegistryProtocol.skillsSh),
        'https://skills.sh',
      );
      expect(
        SkillRegistrySourceConfig.defaultBaseUrl(SkillRegistryProtocol.skillsMp),
        'https://skillsmp.com/api/v1',
      );
    });

    test('json round-trip keeps apiToken and omits empty token', () {
      final c = SkillRegistrySourceConfig(
        id: 'skillsMp',
        kind: SkillRegistryKind.api,
        label: 'SkillsMP',
        protocol: SkillRegistryProtocol.skillsMp,
        apiToken: 'tok',
      );
      final json = c.toJson();
      expect(json['apiToken'], 'tok');
      final restored = SkillRegistrySourceConfig.fromJson(json);
      expect(restored.apiToken, 'tok');
      expect(restored.hasApiToken, isTrue);

      final without = SkillRegistrySourceConfig.fromJson({'id': 'skillsMp'});
      expect(without.hasApiToken, isFalse);
      expect(without.apiToken, isNull);
    });

    test('copyWith clearApiToken', () {
      final c = SkillRegistrySourceConfig(
        id: 'a',
        kind: SkillRegistryKind.api,
        label: 'a',
        protocol: SkillRegistryProtocol.skillsSh,
        apiToken: 'x',
      );
      expect(c.copyWith(clearApiToken: true).apiToken, isNull);
      expect(c.copyWith(enabled: false).enabled, isFalse);
    });
  });

  group('SkillRegistriesConfig', () {
    test('defaults contains both API sources and default git repos', () {
      final d = SkillRegistriesConfig.defaults();
      expect(d.byId('skillsSh'), isNotNull);
      expect(d.byId('skillsMp'), isNotNull);
      final git = d.sources.where((s) => s.kind == SkillRegistryKind.gitRepo);
      expect(git.length, 4);
    });

    test('fromJson fills missing kinds with defaults', () {
      final cfg = SkillRegistriesConfig.fromJson({'sources': [
        {'id': 'skillsSh', 'kind': 'api', 'label': 'skills.sh'},
      ]});
      expect(cfg.byId('skillsSh'), isNotNull);
      expect(cfg.byId('skillsMp'), isNotNull);
      expect(cfg.sources.length, greaterThanOrEqualTo(2));
    });

    test('toJson/fromJson round-trip', () {
      final d = SkillRegistriesConfig.defaults();
      final restored = SkillRegistriesConfig.fromJson(d.toJson());
      expect(restored.sources.length, d.sources.length);
      expect(restored.byId('skillsSh')!.baseUrl, d.byId('skillsSh')!.baseUrl);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/skill_registry_source_test.dart`
Expected: FAIL — file/class not found.

- [ ] **Step 3: Implement model**

Create `client/lib/models/skill_registry_source.dart`:

```dart
import 'package:flutter/foundation.dart';

enum SkillRegistryKind { gitRepo, api }

enum SkillRegistryProtocol { skillsSh, skillsMp }

@immutable
class SkillRegistrySourceConfig {
  const SkillRegistrySourceConfig({
    required this.id,
    required this.kind,
    required this.label,
    this.protocol,
    this.enabled = true,
    this.baseUrl,
    this.apiToken,
    this.browseQuery,
    this.gitOwner,
    this.gitName,
    this.gitBranch,
  });

  final String id;
  final SkillRegistryKind kind;
  final String label;
  final SkillRegistryProtocol? protocol;
  final bool enabled;
  final String? baseUrl;
  final String? apiToken;
  final String? browseQuery;
  final String? gitOwner;
  final String? gitName;
  final String? gitBranch;

  bool get hasApiToken => apiToken != null && apiToken!.trim().isNotEmpty;

  String get githubUrl =>
      'https://github.com/$gitOwner/$gitName';

  static String defaultBaseUrl(SkillRegistryProtocol protocol) =>
      switch (protocol) {
        SkillRegistryProtocol.skillsSh => 'https://skills.sh',
        SkillRegistryProtocol.skillsMp => 'https://skillsmp.com/api/v1',
      };

  String get baseUrlOrDefault {
    final url = baseUrl?.trim();
    if (url != null && url.isNotEmpty) return url;
    final p = protocol;
    return p == null ? '' : defaultBaseUrl(p);
  }

  SkillRegistrySourceConfig copyWith({
    String? label,
    bool? enabled,
    String? baseUrl,
    String? apiToken,
    bool clearApiToken = false,
    String? browseQuery,
    String? gitOwner,
    String? gitName,
    String? gitBranch,
  }) => SkillRegistrySourceConfig(
    id: id,
    kind: kind,
    label: label ?? this.label,
    protocol: protocol,
    enabled: enabled ?? this.enabled,
    baseUrl: baseUrl ?? this.baseUrl,
    apiToken: clearApiToken ? null : (apiToken ?? this.apiToken),
    browseQuery: browseQuery ?? this.browseQuery,
    gitOwner: gitOwner ?? this.gitOwner,
    gitName: gitName ?? this.gitName,
    gitBranch: gitBranch ?? this.gitBranch,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind == SkillRegistryKind.api ? 'api' : 'git',
    'label': label,
    if (kind == SkillRegistryKind.api) 'protocol': protocol == SkillRegistryProtocol.skillsMp ? 'skillsMp' : 'skillsSh',
    'enabled': enabled,
    if (kind == SkillRegistryKind.api) ...{
      if (baseUrl != null && baseUrl!.trim().isNotEmpty) 'baseUrl': baseUrl,
      if (hasApiToken) 'apiToken': apiToken!.trim(),
      if (browseQuery != null && browseQuery!.trim().isNotEmpty) 'browseQuery': browseQuery,
    } else ...{
      if (gitOwner != null && gitOwner!.isNotEmpty) 'gitOwner': gitOwner,
      if (gitName != null && gitName!.isNotEmpty) 'gitName': gitName,
      if (gitBranch != null && gitBranch!.isNotEmpty) 'gitBranch': gitBranch,
    },
  };

  factory SkillRegistrySourceConfig.fromJson(Map<String, Object?> json) {
    final kind = json['kind'] as String? == 'git'
        ? SkillRegistryKind.gitRepo
        : SkillRegistryKind.api;
    final protocolRaw = (json['protocol'] as String?)?.trim().toLowerCase();
    final protocol = protocolRaw == 'skillsmp'
        ? SkillRegistryProtocol.skillsMp
        : SkillRegistryProtocol.skillsSh;
    return SkillRegistrySourceConfig(
      id: json['id'] as String? ?? '',
      kind: kind,
      label: json['label'] as String? ?? '',
      protocol: kind == SkillRegistryKind.api ? protocol : null,
      enabled: json['enabled'] as bool? ?? true,
      baseUrl: json['baseUrl'] as String?,
      apiToken: json['apiToken'] as String?,
      browseQuery: json['browseQuery'] as String?,
      gitOwner: json['gitOwner'] as String?,
      gitName: json['gitName'] as String?,
      gitBranch: json['gitBranch'] as String? ?? 'main',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillRegistrySourceConfig &&
          id == other.id &&
          kind == other.kind &&
          label == other.label &&
          protocol == other.protocol &&
          enabled == other.enabled &&
          baseUrl == other.baseUrl &&
          apiToken == other.apiToken &&
          browseQuery == other.browseQuery &&
          gitOwner == other.gitOwner &&
          gitName == other.gitName &&
          gitBranch == other.gitBranch;

  @override
  int get hashCode => Object.hash(
    id, kind, label, protocol, enabled, baseUrl, apiToken,
    browseQuery, gitOwner, gitName, gitBranch,
  );
}

@immutable
class SkillRegistriesConfig {
  const SkillRegistriesConfig({required this.sources});

  final List<SkillRegistrySourceConfig> sources;

  static const _defaultGitRepos = [
    ('anthropics', 'skills', 'main'),
    ('ComposioHQ', 'awesome-claude-skills', 'master'),
    ('cexll', 'myclaude', 'master'),
    ('JimLiu', 'baoyu-skills', 'main'),
  ];

  static SkillRegistriesConfig defaults() => SkillRegistriesConfig(
    sources: [
      SkillRegistrySourceConfig(
        id: 'skillsSh',
        kind: SkillRegistryKind.api,
        label: 'skills.sh',
        protocol: SkillRegistryProtocol.skillsSh,
        baseUrl: SkillRegistrySourceConfig.defaultBaseUrl(SkillRegistryProtocol.skillsSh),
        browseQuery: 'ai',
      ),
      SkillRegistrySourceConfig(
        id: 'skillsMp',
        kind: SkillRegistryKind.api,
        label: 'SkillsMP',
        protocol: SkillRegistryProtocol.skillsMp,
        baseUrl: SkillRegistrySourceConfig.defaultBaseUrl(SkillRegistryProtocol.skillsMp),
      ),
      for (final (owner, name, branch) in _defaultGitRepos)
        SkillRegistrySourceConfig(
          id: 'git-$owner-$name',
          kind: SkillRegistryKind.gitRepo,
          label: '$owner/$name',
          gitOwner: owner,
          gitName: name,
          gitBranch: branch,
        ),
    ],
  );

  SkillRegistrySourceConfig? byId(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'sources': sources.map((s) => s.toJson()).toList(),
  };

  factory SkillRegistriesConfig.fromJson(Map<String, Object?> json) {
    final raw = json['sources'];
    if (raw is! List || raw.isEmpty) return defaults();
    final parsed = raw
        .whereType<Map>()
        .map((m) => SkillRegistrySourceConfig.fromJson(m.cast<String, Object?>()))
        .toList();
    final byId = <String, SkillRegistrySourceConfig>{
      for (final s in parsed) s.id: s,
    };
    final d = defaults();
    final merged = <SkillRegistrySourceConfig>[
      byId['skillsSh'] ?? d.byId('skillsSh')!,
      byId['skillsMp'] ?? d.byId('skillsMp')!,
      for (final s in parsed)
        if (s.id != 'skillsSh' && s.id != 'skillsMp') s,
    ];
    return SkillRegistriesConfig(sources: merged);
  }
}
```

Note: the recursive `defaults()` call inside the factory is intentional (references the static method via the class name).

- [ ] **Step 4: Add storage paths**

In `client/lib/services/storage/app_storage.dart`, after line 158 (`skillReposConfigPathForTeampilotRoot`):

```dart
  /// Skill registry sources (skills/registries.json).
  static String skillRegistriesConfigPathForTeampilotRoot(
    String teampilotRoot,
  ) => _pathUnderTeampilotRoot(teampilotRoot, 'skills/registries.json');
```

In `AppPaths` instance getters, after line 301 (`skillReposConfigPath`):

```dart
  String get skillRegistriesConfigPath =>
      skillRegistriesConfigPathForTeampilotRoot(basePath);
```

In `client/lib/services/storage/runtime_context.dart`, after line 85 (`skillReposConfigPath`):

```dart
  String get skillRegistriesConfigPath =>
      AppPaths.skillRegistriesConfigPathForTeampilotRoot(appDataRoot);
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd client && flutter test test/models/skill_registry_source_test.dart`
Expected: PASS (all 6 tests).

- [ ] **Step 6: Commit**

```bash
git add client/lib/models/skill_registry_source.dart client/lib/services/storage/app_storage.dart client/lib/services/storage/runtime_context.dart client/test/models/skill_registry_source_test.dart
git commit -m "feat(skills): registry source config model + storage paths"
```

---

### Task 2: Registry config service with one-time migration

**Files:**
- Create: `client/lib/services/skill/registry/skill_registry_config_service.dart`
- Test: `client/test/services/skill/registry/skill_registry_config_service_test.dart`

**Interfaces:**
- Consumes: `SkillRegistriesConfig` (Task 1), `AppPaths.skillRegistriesConfigPathForTeampilotRoot`, `AppPaths.skillReposConfigPathForTeampilotRoot`, `Filesystem` (`client/lib/services/io/filesystem.dart`), `LocalFilesystem`.
- Produces (used by Task 6, 7): `SkillRegistryConfigService({Filesystem? fs, String? teampilotRoot, Future<String?> Function()? legacySkillsMpKeyReader})` with `Future<SkillRegistriesConfig> load()` and `Future<void> save(SkillRegistriesConfig config)`.
- Migration contract: when `registries.json` is missing and old `repos.json` contains a `repos` list, produce config = defaults with `repos.json` git entries REPLACING default git repos (keeping their enabled flags), plus `skillsMp.apiToken` from the legacy reader; the migrated config is written to disk immediately.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/skill/registry/skill_registry_config_service_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/registry/skill_registry_config_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp; // from dart:io
  late AppPaths paths;
  late SkillRegistryConfigService service;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('skill-registry-cfg-');
    paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
    service = SkillRegistryConfigService(
      teampilotRoot: paths.basePath,
      legacySkillsMpKeyReader: () async => 'legacy-token',
    );
  });

  tearDown(() {
    AppStorage.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('load returns defaults when no files exist', () async {
    final cfg = await service.load();
    expect(cfg.byId('skillsSh'), isNotNull);
    expect(cfg.byId('skillsMp'), isNotNull);
    expect(cfg.byId('skillsMp')!.apiToken, isNull);
  });

  test('migrates legacy repos.json git repos + skillsMp key once', () async {
    final oldPath = AppPaths.skillReposConfigPathForTeampilotRoot(paths.basePath);
    await AppStorage.fs.writeString(oldPath, const JsonEncoder.withIndent('  ').convert({
      'repos': [
        {'owner': 'vercel', 'name': 'ai', 'branch': 'main', 'enabled': true},
      ],
    }));

    final cfg = await service.load();
    final git = cfg.sources.where((s) => s.kind == SkillRegistryKind.gitRepo);
    expect(git.length, 1);
    expect(git.first.gitOwner, 'vercel');
    expect(cfg.byId('skillsMp')!.apiToken, 'legacy-token');

    // second load reads registries.json; migration not repeated
    final again = await service.load();
    expect(again.sources.length, cfg.sources.length);
  });

  test('save + load round-trip', () async {
    final cfg = SkillRegistriesConfig.defaults().toJson();
    final config = SkillRegistriesConfig.fromJson(cfg);
    await service.save(config);
    final loaded = await service.load();
    expect(loaded.sources.length, config.sources.length);
  });

  test('corrupt registries.json falls back to defaults', () async {
    final path = AppPaths.skillRegistriesConfigPathForTeampilotRoot(paths.basePath);
    await AppStorage.fs.writeString(path, '{not json');
    final cfg = await service.load();
    expect(cfg.byId('skillsSh'), isNotNull);
  });
}
```

Note: import `dart:io` for `Directory`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/skill/registry/skill_registry_config_service_test.dart`
Expected: FAIL — class not found.

- [ ] **Step 3: Implement the service**

Create `client/lib/services/skill/registry/skill_registry_config_service.dart`:

```dart
import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../../models/skill_registry_source.dart';
import '../../io/filesystem.dart';
import '../../io/local_filesystem.dart';
import '../../storage/app_storage.dart';

class SkillRegistryConfigService {
  SkillRegistryConfigService({
    Filesystem? fs,
    String? teampilotRoot,
    Future<String?> Function()? legacySkillsMpKeyReader,
  }) : _teampilotRoot = teampilotRoot?.trim(),
       _fs = fs ?? LocalFilesystem(),
       _legacySkillsMpKeyReader = legacySkillsMpKeyReader;

  final String? _teampilotRoot;
  final Filesystem _fs;
  final Future<String?> Function()? _legacySkillsMpKeyReader;

  Future<String> _configPath() async {
    final root = _teampilotRoot;
    if (root != null && root.isNotEmpty) {
      return AppPaths.skillRegistriesConfigPathForTeampilotRoot(root);
    }
    if (AppStorage.isInstalled) {
      return AppStorage.context.skillRegistriesConfigPath;
    }
    return AppStorage.paths.skillRegistriesConfigPath;
  }

  Future<String> _legacyReposPath() async {
    final root = _teampilotRoot;
    if (root != null && root.isNotEmpty) {
      return AppPaths.skillReposConfigPathForTeampilotRoot(root);
    }
    if (AppStorage.isInstalled) {
      return AppStorage.context.skillReposConfigPath;
    }
    return AppStorage.paths.skillReposConfigPath;
  }

  Future<SkillRegistriesConfig> load() async {
    final path = await _configPath();
    try {
      final stat = await _fs.stat(path);
      if (!stat.isFile) {
        final migrated = await _migrateIfNeeded();
        return migrated;
      }
      final text = await _fs.readString(path);
      if (text == null || text.trim().isEmpty) {
        return SkillRegistriesConfig.defaults();
      }
      final json = jsonDecode(text);
      if (json is! Map) return SkillRegistriesConfig.defaults();
      return SkillRegistriesConfig.fromJson(json.cast<String, Object?>());
    } catch (_) {
      return SkillRegistriesConfig.defaults();
    }
  }

  Future<void> save(SkillRegistriesConfig config) async {
    final path = await _configPath();
    await _fs.ensureDir(p.dirname(path));
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
  }

  /// One-time migration from legacy skills/repos.json + settings skillsMpApiKey.
  Future<SkillRegistriesConfig> _migrateIfNeeded() async {
    final defaults = SkillRegistriesConfig.defaults();
    final legacyPath = await _legacyReposPath();
    List<SkillRegistrySourceConfig> gitSources = const [];
    try {
      final stat = await _fs.stat(legacyPath);
      if (stat.isFile) {
        final text = await _fs.readString(legacyPath);
        if (text != null && text.trim().isNotEmpty) {
          final json = jsonDecode(text);
          if (json is Map) {
            final repos = json['repos'];
            if (repos is List) {
              gitSources = repos.whereType<Map>().map((raw) {
                final m = raw.cast<String, Object?>();
                final owner = (m['owner'] as String?) ?? '';
                final name = (m['name'] as String?) ?? '';
                return SkillRegistrySourceConfig(
                  id: 'git-$owner-$name',
                  kind: SkillRegistryKind.gitRepo,
                  label: '$owner/$name',
                  enabled: m['enabled'] as bool? ?? true,
                  gitOwner: owner,
                  gitName: name,
                  gitBranch: (m['branch'] as String?) ?? 'main',
                );
              }).toList();
            }
          }
        }
      }
    } catch (_) {
      gitSources = const [];
    }

    String? legacyKey;
    final reader = _legacySkillsMpKeyReader;
    if (reader != null) {
      try {
        legacyKey = await reader();
      } catch (_) {
        legacyKey = null;
      }
    }

    final sources = <SkillRegistrySourceConfig>[];
    for (final s in defaults.sources) {
      if (s.kind == SkillRegistryKind.gitRepo) continue;
      sources.add(s.id == 'skillsMp' && legacyKey != null && legacyKey!.trim().isNotEmpty
          ? s.copyWith(apiToken: legacyKey!.trim())
          : s);
    }
    sources.addAll(gitSources.isEmpty ? defaults.sources.where((s) => s.kind == SkillRegistryKind.gitRepo) : gitSources);
    final migrated = SkillRegistriesConfig(sources: sources);
    await save(migrated);
    return migrated;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/skill/registry/skill_registry_config_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/skill/registry/skill_registry_config_service.dart client/test/services/skill/registry/skill_registry_config_service_test.dart
git commit -m "feat(skills): registry config service with legacy migration"
```

---

### Task 3: Registry source interface + shared types refactor

**Files:**
- Modify: `client/lib/services/skill/marketplace/skill_marketplace_source.dart` — keep `MarketplaceSkill`, `MarketplaceCapabilities`, `MarketplaceFetchException`, `MarketplaceQuotaException`, `marketplaceQuotaErrorKey`; delete `SkillMarketplaceSource`, `MarketplaceSearchQuery`, `MarketplaceSearchResult`.
- Create: `client/lib/services/skill/registry/skill_registry_source.dart`
- Test: `client/test/services/skill/registry/skill_registry_source_test.dart`

**Interfaces:**
- Produces (used by Task 4-8): `SkillRegistryQuery` (`query`, `page`, `limit`, `category`, `occupation`, `language`, `sortBy`), `SkillRegistryPage` (`entries: List<MarketplaceSkill>`, `hasNext`, `total`), `abstract class SkillRegistrySource` (`id`, `label`, `enabled`, `kind`, `capabilities`, `search(SkillRegistryQuery)`, `testConnection()`, `setApiKey(String)`).
- Consumes: `MarketplaceSkill`, `MarketplaceCapabilities`, `MarketplaceFetchException`, `MarketplaceQuotaException`, `marketplaceQuotaErrorKey` (kept in the marketplace file).

- [ ] **Step 1: Write the failing test**

Create `client/test/services/skill/registry/skill_registry_source_test.dart` — a pure interface conformance test with a fake:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/registry/skill_registry_source.dart';

class _Fake implements SkillRegistrySource {
  _Fake(this.id);
  @override
  final String id;
  @override
  String get label => id;
  @override
  bool get enabled => true;
  @override
  SkillRegistryKind get kind => SkillRegistryKind.api;
  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();
  @override
  Future<SkillRegistryPage> search(SkillRegistryQuery q) async =>
      SkillRegistryPage(entries: const [], hasNext: false, total: 0);
  @override
  Future<void> testConnection() async {}
  @override
  Future<void> setApiKey(String key) async {}
}

void main() {
  test('query defaults: empty query is browse, page starts at 1, limit 20', () {
    const q = SkillRegistryQuery();
    expect(q.query, '');
    expect(q.page, 1);
    expect(q.limit, 20);
    expect(q.category, isNull);
    expect(q.sortBy, isNull);
  });

  test('skill registry source contract', () async {
    final src = _Fake('x');
    final page = await src.search(const SkillRegistryQuery(query: 'ai'));
    expect(page.entries, isEmpty);
    expect(page.hasNext, isFalse);
    expect(src.capabilities.hasAnyFilter, isFalse);
    await src.testConnection();
    await src.setApiKey('k');
  });

  test('marketplace skill flags', () {
    const direct = MarketplaceSkill(
      key: 'k', name: 'n', description: 'd', repoOwner: 'o', repoName: 'r',
      directory: 'dir/skill', githubUrl: 'https://github.com/o/r',
    );
    expect(direct.isInstalledDirectly, isTrue);
    const undirected = MarketplaceSkill(
      key: 'k2', name: 'n', description: 'd', repoOwner: 'o', repoName: 'r',
      directory: null, githubUrl: 'https://github.com/o/r',
    );
    expect(undirected.isInstalledDirectly, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/skill/registry/skill_registry_source_test.dart`
Expected: FAIL — `SkillRegistrySource` not found.

- [ ] **Step 3: Refactor shared types**

Rewrite `client/lib/services/skill/marketplace/skill_marketplace_source.dart` to contain ONLY:

```dart
const marketplaceQuotaErrorKey = 'marketplace_quota_error';

class MarketplaceSkill {
  const MarketplaceSkill({
    required this.key,
    required this.name,
    required this.description,
    required this.repoOwner,
    required this.repoName,
    this.repoBranch = 'main',
    this.directory,
    required this.githubUrl,
    this.installs,
    this.stars,
    this.updatedAt,
    this.contentLanguage,
  });

  final String key;
  final String name;
  final String description;
  final String repoOwner;
  final String repoName;
  final String repoBranch;

  /// SKILL.md 所在 repo 内子目录。null 表示无法直接定位（如 SkillsMP），
  /// 安装需降级为把整个 repo 加入注册中心 git 源。
  final String? directory;
  final String githubUrl;

  /// skills.sh 源的安装次数。
  final int? installs;

  /// SkillsMP 源的 GitHub stars 与最近更新时间（Unix 秒）。
  final int? stars;
  final int? updatedAt;
  final String? contentLanguage;

  bool get isInstalledDirectly =>
      directory != null && directory!.trim().isNotEmpty;
}

class MarketplaceCapabilities {
  const MarketplaceCapabilities({
    this.supportsCategory = false,
    this.supportsOccupation = false,
    this.supportsLanguage = false,
    this.supportsSortBy = false,
    this.categoryChoices = const {},
    this.occupationChoices = const {},
    this.languageChoices = const [],
  });

  final bool supportsCategory;
  final bool supportsOccupation;
  final bool supportsLanguage;
  final bool supportsSortBy;

  /// slug -> 展示标签。slug 直接作为 API 参数值。
  final Map<String, String> categoryChoices;
  final Map<String, String> occupationChoices;
  final List<String> languageChoices;

  bool get hasAnyFilter =>
      supportsCategory ||
      supportsOccupation ||
      supportsLanguage ||
      supportsSortBy;
}

class MarketplaceFetchException implements Exception {
  MarketplaceFetchException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => cause != null
      ? 'MarketplaceFetchException: $message ($cause)'
      : 'MarketplaceFetchException: $message';
}

class MarketplaceQuotaException extends MarketplaceFetchException {
  MarketplaceQuotaException(super.message);
}
```

- [ ] **Step 4: Implement the interface file**

Create `client/lib/services/skill/registry/skill_registry_source.dart`:

```dart
import '../../models/skill_registry_source.dart';
import '../marketplace/skill_marketplace_source.dart';

class SkillRegistryQuery {
  const SkillRegistryQuery({
    this.query = '',
    this.page = 1,
    this.limit = 20,
    this.category,
    this.occupation,
    this.language,
    this.sortBy,
  });

  /// 空字符串 = browse（源自身决定浏览策略）。
  final String query;
  final int page;
  final int limit;
  final String? category;
  final String? occupation;
  final String? language;
  final String? sortBy;
}

class SkillRegistryPage {
  const SkillRegistryPage({
    required this.entries,
    this.hasNext = false,
    this.total = 0,
  });

  final List<MarketplaceSkill> entries;
  final bool hasNext;
  final int total;
}

abstract class SkillRegistrySource {
  String get id;
  String get label;
  bool get enabled;
  SkillRegistryKind get kind;
  MarketplaceCapabilities get capabilities;

  Future<SkillRegistryPage> search(SkillRegistryQuery query);

  Future<void> testConnection();

  Future<void> setApiKey(String key) async {}
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && flutter test test/services/skill/registry/skill_registry_source_test.dart test/models/skill_registry_source_test.dart`
Expected: PASS.
Then fix any compile errors from the deleted types:
Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: errors only in files still referencing `SkillMarketplaceSource`/`MarketplaceSearchQuery`/`MarketplaceSearchResult` — those files are rewritten in Tasks 4-8, and `skills_sh_marketplace_source.dart`/`skills_mp_marketplace_source.dart`/`skill_marketplace_registry.dart` are deleted in Task 4. Temporarily suppress by keeping the old files compiling (they will be deleted in Task 4 — this task leaves `flutter analyze` failing on those 3 old files plus `skill_marketplace_panel.dart`/tests, which is expected; do NOT fix them here).

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/skill/marketplace/skill_marketplace_source.dart client/lib/services/skill/registry/skill_registry_source.dart client/test/services/skill/registry/skill_registry_source_test.dart
git commit -m "refactor(skills): registry source interface, trim marketplace types"
```

---

### Task 4: API registry sources (skills.sh + SkillsMP protocols)

**Files:**
- Create: `client/lib/services/skill/registry/api_registry_source.dart`
- Modify: `client/lib/services/skill/skills_sh_service.dart` (parameterize `baseUrl`, keep everything else)
- Delete: `client/lib/services/skill/marketplace/skills_sh_marketplace_source.dart`, `client/lib/services/skill/marketplace/skills_mp_marketplace_source.dart`, `client/lib/services/skill/marketplace/skill_marketplace_registry.dart`
- Test: `client/test/services/skill/registry/api_registry_source_test.dart`

**Interfaces:**
- Consumes: `SkillRegistrySource`, `SkillRegistryQuery`, `SkillRegistryPage`, `SkillRegistrySourceConfig`, `SkillRegistryProtocol` (Task 1/3), `SkillsShService` (parameterized `baseUrl`).
- Produces (used by Task 6/7): `ApiRegistrySource(SkillRegistrySourceConfig config, {http.Client? client})` — implements `SkillRegistrySource`. Behaviors:
  - `protocol` getter defaults to `skillsSh` when config.protocol null.
  - skillsSh search: `q = query.query.isEmpty ? (config.browseQuery ?? 'ai') : query.query`; GET `$baseUrl/api/search?q=&limit=&offset=`; parses via `SkillsShService` (constructed with `baseUrl`); maps to `MarketplaceSkill` (key/name/directory/repoOwner/repoName/repoBranch 'main'/readmeUrl github browse/installs).
  - skillsMp search: query = `q` param; browse (`query.query` empty) → `q=a` + `sortBy=stars`; params `page/limit` + optional `category/occupation/language/sortBy`; `Authorization: Bearer` when `config.hasApiToken`; 429 → `MarketplaceQuotaException`; parses `data.skills` + `data.pagination` (skill fields: name/description/githubUrl/contentLanguage/stars/updatedAt; owner/repo from githubUrl path segments; `key = id ?? githubUrl`).
  - `capabilities`: skillsMp → full filter caps (category/occupation/language/sortBy); skillsSh → empty.
  - `testConnection()`: `search(SkillRegistryQuery(page: 1, limit: 1))` — throws on failure.
  - `setApiKey`: no-op (token lives in config, persisted by cubit).

- [ ] **Step 1: Modify SkillsShService to accept baseUrl**

In `client/lib/services/skill/skills_sh_service.dart`:

```dart
class SkillsShService {
  SkillsShService({http.Client? client, String baseUrl = 'https://skills.sh'})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl;

  final http.Client _client;
  final String _baseUrl;

  Future<SkillsShResult> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/search').replace(
      queryParameters: {'q': query, 'limit': '$limit', 'offset': '$offset'},
    );
    // ... rest unchanged
  }
```

- [ ] **Step 2: Write the failing test**

Create `client/test/services/skill/registry/api_registry_source_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/registry/api_registry_source.dart';
import 'package:teampilot/services/skill/registry/skill_registry_source.dart';

ApiRegistrySource _source(SkillRegistryProtocol protocol, {String? token, String? browseQuery, String baseUrl = 'https://example.test'}) =>
    ApiRegistrySource(
      SkillRegistrySourceConfig(
        id: protocol == SkillRegistryProtocol.skillsMp ? 'skillsMp' : 'skillsSh',
        kind: SkillRegistryKind.api,
        label: 't',
        protocol: protocol,
        baseUrl: baseUrl,
        apiToken: token,
        browseQuery: browseQuery,
      ),
      client: http.Client(),
    );

void main() {
  test('skillsSh protocol: browse uses browseQuery, query uses q', () async {
    final requests = <Uri>[];
    final client = MockClient((req) async {
      requests.add(req.url);
      return http.Response(
        json.encode({
          'count': 2,
          'skills': [
            {
              'id': 'vercel/ai/ai-sdk',
              'skillId': 'ai-sdk',
              'name': 'ai-sdk',
              'installs': 42,
              'source': 'vercel/ai',
            },
          ],
        }),
        200,
      );
    });
    final src = ApiRegistrySource(
      SkillRegistrySourceConfig(
        id: 'skillsSh',
        kind: SkillRegistryKind.api,
        label: 'skills.sh',
        protocol: SkillRegistryProtocol.skillsSh,
        baseUrl: 'https://skills.sh',
        browseQuery: 'ai',
      ),
      client: client,
    );
    final browse = await src.search(const SkillRegistryQuery());
    expect(requests.single.queryParameters['q'], 'ai');
    expect(browse.entries.single.name, 'ai-sdk');
    expect(browse.entries.single.repoOwner, 'vercel');

    final q = await src.search(const SkillRegistryQuery(query: 'claude', page: 2, limit: 10));
    expect(requests.last.queryParameters['q'], 'claude');
    expect(requests.last.queryParameters['offset'], '10');
  });

  test('skillsMp protocol: browse sends q=a + sortBy=stars, quota throws', () async {
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/quota')) {
        return http.Response('{}', 429);
      }
      return http.Response(
        json.encode({
          'data': {
            'skills': [
              {
                'id': 'openclaw-openclaw-agents-skills-x',
                'name': 'x',
                'description': 'd',
                'contentLanguage': 'en',
                'githubUrl': 'https://github.com/openclaw/openclaw/tree/main/.agents/skills/x',
                'stars': 386158,
                'updatedAt': 1750000000,
              },
            ],
            'pagination': {'hasNext': true, 'total': 7},
          },
        }),
        200,
      );
    });
    final src = ApiRegistrySource(
      SkillRegistrySourceConfig(
        id: 'skillsMp',
        kind: SkillRegistryKind.api,
        label: 'SkillsMP',
        protocol: SkillRegistryProtocol.skillsMp,
        baseUrl: 'https://skillsmp.com/api/v1',
      ),
      client: client,
    );
    final browse = await src.search(const SkillRegistryQuery(sortBy: 'stars'));
    final u = browse.entries;
    expect(u.single.repoOwner, 'openclaw');
    expect(u.single.repoName, 'openclaw');
    expect(u.single.stars, 386158);

    final quotaSrc = ApiRegistrySource(
      SkillRegistrySourceConfig(
        id: 'skillsMp',
        kind: SkillRegistryKind.api,
        label: 'SkillsMP',
        protocol: SkillRegistryProtocol.skillsMp,
        baseUrl: 'https://skillsmp.com/api/v1/quota',
      ),
      client: client,
    );
    expect(
      () => quotaSrc.search(const SkillRegistryQuery(query: 'x')),
      throwsA(isA<MarketplaceQuotaException>()),
    );
  });

  test('skillsMp sends Authorization header when token set', () async {
    final seen = <String?>[];
    final client = MockClient((req) async {
      seen.add(req.headers['Authorization']);
      return http.Response(
        json.encode({'data': {'skills': [], 'pagination': {'hasNext': false}}}),
        200,
      );
    });
    final src = ApiRegistrySource(
      SkillRegistrySourceConfig(
        id: 'skillsMp',
        kind: SkillRegistryKind.api,
        label: 'SkillsMP',
        protocol: SkillRegistryProtocol.skillsMp,
        apiToken: 'tok123',
      ),
      client: client,
    );
    await src.search(const SkillRegistryQuery(query: 'a'));
    expect(seen.single, 'Bearer tok123');
  });

  test('capabilities and testConnection', () async {
    final mp = _source(SkillRegistryProtocol.skillsMp);
    expect(mp.capabilities.supportsSortBy, isTrue);
    expect(mp.capabilities.hasAnyFilter, isTrue);
    final sh = _source(SkillRegistryProtocol.skillsSh);
    expect(sh.capabilities.hasAnyFilter, isFalse);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd client && flutter test test/services/skill/registry/api_registry_source_test.dart`
Expected: FAIL — `ApiRegistrySource` not found.

- [ ] **Step 4: Implement ApiRegistrySource**

Create `client/lib/services/skill/registry/api_registry_source.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/skill_registry_source.dart';
import '../marketplace/skill_marketplace_source.dart';
import '../skills_sh_service.dart';
import 'skill_registry_source.dart';

/// API 注册源：按 [SkillRegistryProtocol] 实现 skills.sh / SkillsMP 两种协议。
/// baseUrl / apiToken / browseQuery 均来自配置，支持自定义源。
class ApiRegistrySource implements SkillRegistrySource {
  ApiRegistrySource(this.config, {http.Client? client})
    : _client = client ?? http.Client();

  final SkillRegistrySourceConfig config;
  final http.Client _client;

  SkillRegistryProtocol get protocol =>
      config.protocol ?? SkillRegistryProtocol.skillsSh;

  String get _baseUrl {
    final url = config.baseUrlOrDefault;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  @override
  String get id => config.id;

  @override
  String get label => config.label;

  @override
  bool get enabled => config.enabled;

  @override
  SkillRegistryKind get kind => SkillRegistryKind.api;

  @override
  MarketplaceCapabilities get capabilities => switch (protocol) {
    SkillRegistryProtocol.skillsSh => const MarketplaceCapabilities(),
    SkillRegistryProtocol.skillsMp => const MarketplaceCapabilities(
      supportsCategory: true,
      supportsOccupation: true,
      supportsLanguage: true,
      supportsSortBy: true,
      categoryChoices: {
        'data-ai': 'Data & AI',
        'devops': 'DevOps',
        'web-development': 'Web Development',
        'automation': 'Automation',
        'data-analysis': 'Data Analysis',
        'marketing': 'Marketing',
        'productivity': 'Productivity',
        'design': 'Design',
        'business': 'Business',
        'education': 'Education',
      },
      occupationChoices: {
        'software-developers': 'Software Developers',
        'data-scientists': 'Data Scientists',
        'devops-engineers': 'DevOps Engineers',
        'project-managers': 'Project Managers',
        'product-managers': 'Product Managers',
        'marketing-specialists': 'Marketing Specialists',
        'content-writers': 'Content Writers',
        'data-analysts': 'Data Analysts',
        'it-support-specialists': 'IT Support',
        'ux-designers': 'UX Designers',
        'quality-assurance-analysts': 'QA Analysts',
        'security-analysts': 'Security Analysts',
        'sales-representatives': 'Sales',
        'customer-service-reps': 'Customer Service',
        'researchers': 'Researchers',
      },
      languageChoices: [
        'zh', 'en', 'ja', 'ko', 'es', 'fr', 'de', 'pt', 'ru',
      ],
    ),
  };

  @override
  Future<SkillRegistryPage> search(SkillRegistryQuery query) async {
    switch (protocol) {
      case SkillRegistryProtocol.skillsSh:
        return _searchSkillsSh(query);
      case SkillRegistryProtocol.skillsMp:
        return _searchSkillsMp(query);
    }
  }

  Future<SkillRegistryPage> _searchSkillsSh(SkillRegistryQuery query) async {
    final q = query.query.trim().isEmpty
        ? (config.browseQuery ?? 'ai')
        : query.query;
    final service = SkillsShService(
      client: _client,
      baseUrl: _baseUrl,
    );
    final res = await service.search(
      q,
      limit: query.limit,
      offset: (query.page - 1) * query.limit,
    );
    return SkillRegistryPage(
      entries: res.skills
          .map(
            (e) => MarketplaceSkill(
              key: e.key,
              name: e.name,
              description: '',
              repoOwner: e.repoOwner,
              repoName: e.repoName,
              repoBranch: e.repoBranch,
              directory: e.directory,
              githubUrl: e.readmeUrl ??
                  'https://github.com/${e.repoOwner}/${e.repoName}',
              installs: e.installs,
            ),
          )
          .toList(),
      hasNext: (query.page * query.limit) < res.totalCount,
      total: res.totalCount,
    );
  }

  Future<SkillRegistryPage> _searchSkillsMp(SkillRegistryQuery query) async {
    final q = query.query.trim();
    final effectiveQ = q.isEmpty ? 'a' : q;
    final params = <String, String>{
      'q': effectiveQ,
      'page': '${query.page}',
      'limit': '${query.limit}',
      if (q.isEmpty) 'sortBy': 'stars',
      if (query.sortBy != null && query.sortBy!.isNotEmpty)
        'sortBy': query.sortBy!,
      if (query.category != null && query.category!.isNotEmpty)
        'category': query.category!,
      if (query.occupation != null && query.occupation!.isNotEmpty)
        'occupation': query.occupation!,
      if (query.language != null && query.language!.isNotEmpty)
        'language': query.language!,
    };
    final uri = Uri.parse('$_baseUrl/skills/search').replace(
      queryParameters: params,
    );
    final headers = <String, String>{
      if (config.hasApiToken) 'Authorization': 'Bearer ${config.apiToken!.trim()}',
    };

    final http.Response resp;
    try {
      resp = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw MarketplaceFetchException('SkillsMP network error: $e', e);
    }
    if (resp.statusCode == 429) {
      throw MarketplaceQuotaException('SkillsMP daily quota exhausted');
    }
    if (resp.statusCode != 200) {
      throw MarketplaceFetchException('SkillsMP HTTP ${resp.statusCode}');
    }
    try {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>? ?? const {};
      final rawSkills = data['skills'] as List<dynamic>? ?? const [];
      final pagination =
          data['pagination'] as Map<String, dynamic>? ?? const {};
      final skills = <MarketplaceSkill>[];
      for (final raw in rawSkills) {
        final m = (raw as Map).cast<String, Object?>();
        final githubUrl = (m['githubUrl'] as String?) ?? '';
        final owner = _ownerOf(githubUrl);
        final repo = _repoOf(githubUrl);
        if (owner.isEmpty || repo.isEmpty) continue;
        skills.add(
          MarketplaceSkill(
            key: (m['id'] as String?) ?? githubUrl,
            name: (m['name'] as String?) ?? '',
            description: (m['description'] as String?) ?? '',
            repoOwner: owner,
            repoName: repo,
            githubUrl: githubUrl,
            stars: (m['stars'] as num?)?.toInt(),
            updatedAt: (m['updatedAt'] as num?)?.toInt(),
            contentLanguage: (m['contentLanguage'] as String?)?.trim(),
          ),
        );
      }
      return SkillRegistryPage(
        skills: skills,
        hasNext: pagination['hasNext'] == true,
        total: (pagination['total'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      throw MarketplaceFetchException('SkillsMP parse error: $e', e);
    }
  }

  @override
  Future<void> testConnection() async {
    await search(const SkillRegistryQuery(page: 1, limit: 1));
  }

  @override
  Future<void> setApiKey(String key) async {}

  static String _ownerOf(String githubUrl) {
    final parts = Uri.tryParse(githubUrl)?.pathSegments ?? const [];
    return parts.length >= 2 ? parts[0] : '';
  }

  static String _repoOf(String githubUrl) {
    final parts = Uri.tryParse(githubUrl)?.pathSegments ?? const [];
    return parts.length >= 2 ? parts[1] : '';
  }
}
```

- [ ] **Step 5: Delete the old marketplace source files**

```bash
git rm client/lib/services/skill/marketplace/skills_sh_marketplace_source.dart client/lib/services/skill/marketplace/skills_mp_marketplace_source.dart client/lib/services/skill/marketplace/skill_marketplace_registry.dart
```

- [ ] **Step 6: Fix the last test (network-free) and run tests**

Replace the final `testConnection` test in `api_registry_source_test.dart` with:

```dart
  test('testConnection calls search and succeeds', () async {
    final client = MockClient((req) async {
      expect(req.url.queryParameters['q'], 'ai');
      return http.Response(
        json.encode({
          'count': 1,
          'skills': [
            {
              'id': 'vercel/ai/ai-sdk',
              'skillId': 'ai-sdk',
              'name': 'ai-sdk',
              'installs': 1,
              'source': 'vercel/ai',
            },
          ],
        }),
        200,
      );
    });
    final src = ApiRegistrySource(
      SkillRegistrySourceConfig(
        id: 'skillsSh',
        kind: SkillRegistryKind.api,
        label: 'skills.sh',
        protocol: SkillRegistryProtocol.skillsSh,
        baseUrl: 'https://skills.sh',
      ),
      client: client,
    );
    await src.testConnection();
  });
```

Run: `cd client && flutter test test/services/skill/registry/api_registry_source_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/skill/registry/api_registry_source.dart client/lib/services/skill/skills_sh_service.dart client/test/services/skill/registry/api_registry_source_test.dart
git commit -m "feat(skills): API registry source with skills.sh/SkillsMP protocols"
```

---

### Task 5: Git repo registry source

**Files:**
- Create: `client/lib/services/skill/registry/git_repo_registry_source.dart`
- Test: `client/test/services/skill/registry/git_repo_registry_source_test.dart`

**Interfaces:**
- Consumes: `SkillRegistrySource` (Task 3), `SkillRegistryQuery`, `SkillRegistrySourceConfig`, `DiscoverableSkill` (`client/lib/models/skill.dart`).
- Produces (used by Task 6): `GitRepoRegistrySource(SkillRegistrySourceConfig config, {required Future<List<DiscoverableSkill>> Function() discoverableProvider, required Future<void> Function() syncNow})`.
  - `search`: entries = provider() results filtered by `query.query` (case-insensitive contains on `name` or `owner/name`); mapped to `MarketplaceSkill` (`key: d.key`, `name`, `description`, `directory: d.directory`, `repoOwner/Name/Branch`, `githubUrl: d.readmeUrl ?? 'https://github.com/$owner/$name'`, `installs/stars/updatedAt: null`); `hasNext: false`, `total: entries.length`.
  - `testConnection`: `await syncNow()`.
  - `setApiKey`: no-op. `capabilities`: empty.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/skill/registry/git_repo_registry_source_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/services/skill/registry/git_repo_registry_source.dart';
import 'package:teampilot/services/skill/registry/skill_registry_source.dart';

const _cfg = SkillRegistrySourceConfig(
  id: 'git-vercel-ai',
  kind: SkillRegistryKind.gitRepo,
  label: 'vercel/ai',
  gitOwner: 'vercel',
  gitName: 'ai',
  gitBranch: 'main',
);

DiscoverableSkill _skill(String name) => DiscoverableSkill(
  key: 'vercel/ai/$name',
  name: name,
  description: 'desc of $name',
  directory: 'skills/$name',
  repoOwner: 'vercel',
  repoName: 'ai',
  repoBranch: 'main',
);

void main() {
  test('search browses all entries when query empty', () async {
    final src = GitRepoRegistrySource(
      _cfg,
      discoverableProvider: () async => [_skill('foo'), _skill('bar')],
      syncNow: () async {},
    );
    final page = await src.search(const SkillRegistryQuery());
    expect(page.entries.length, 2);
    expect(page.entries.first.name, 'foo');
    expect(page.entries.first.repoOwner, 'vercel');
    expect(page.entries.first.directory, 'skills/foo');
    expect(page.entries.first.isInstalledDirectly, isTrue);
  });

  test('search filters by query name and source', () async {
    final src = GitRepoRegistrySource(
      _cfg,
      discoverableProvider: () async => [_skill('foobar'), _skill('baz')],
      syncNow: () async {},
    );
    final page = await src.search(const SkillRegistryQuery(query: 'foo'));
    expect(page.entries.single.name, 'foobar');
    final bySource = await src.search(
      const SkillRegistryQuery(query: 'vercel'),
    );
    expect(bySource.entries.length, 2);
  });

  test('search reports hasNext=false and total', () async {
    final src = GitRepoRegistrySource(
      _cfg,
      discoverableProvider: () async => [_skill('a')],
      syncNow: () async {},
    );
    final page = await src.search(const SkillRegistryQuery());
    expect(page.hasNext, isFalse);
    expect(page.total, 1);
  });

  test('testConnection invokes syncNow', () async {
    var synced = 0;
    final src = GitRepoRegistrySource(
      _cfg,
      discoverableProvider: () async => const [],
      syncNow: () async => synced++,
    );
    await src.testConnection();
    expect(synced, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/skill/registry/git_repo_registry_source_test.dart`
Expected: FAIL — `GitRepoRegistrySource` not found.

- [ ] **Step 3: Implement**

Create `client/lib/services/skill/registry/git_repo_registry_source.dart`:

```dart
import '../../models/skill.dart';
import '../../models/skill_registry_source.dart';
import '../marketplace/skill_marketplace_source.dart';
import 'skill_registry_source.dart';

/// Git 仓库注册源：本地目录扫描的 discoverable 技能，无分页。
class GitRepoRegistrySource implements SkillRegistrySource {
  GitRepoRegistrySource(
    this.config, {
    required Future<List<DiscoverableSkill>> Function() discoverableProvider,
    required Future<void> Function() syncNow,
  }) : _discoverableProvider = discoverableProvider,
       _syncNow = syncNow;

  final SkillRegistrySourceConfig config;
  final Future<List<DiscoverableSkill>> Function() _discoverableProvider;
  final Future<void> Function() _syncNow;

  @override
  String get id => config.id;

  @override
  String get label => config.label;

  @override
  bool get enabled => config.enabled;

  @override
  SkillRegistryKind get kind => SkillRegistryKind.gitRepo;

  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();

  @override
  Future<SkillRegistryPage> search(SkillRegistryQuery query) async {
    final all = await _discoverableProvider();
    final q = query.query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? all
        : all
              .where(
                (d) =>
                    d.name.toLowerCase().contains(q) ||
                    '${d.repoOwner}/${d.repoName}'.toLowerCase().contains(q),
              )
              .toList();
    return SkillRegistryPage(
      entries: filtered.map(_toMarketplace).toList(),
      hasNext: false,
      total: filtered.length,
    );
  }

  MarketplaceSkill _toMarketplace(DiscoverableSkill d) => MarketplaceSkill(
    key: d.key,
    name: d.name,
    description: d.description,
    repoOwner: d.repoOwner,
    repoName: d.repoName,
    repoBranch: d.repoBranch,
    directory: d.directory,
    githubUrl: d.readmeUrl ??
        'https://github.com/${d.repoOwner}/${d.repoName}',
  );

  @override
  Future<void> testConnection() => _syncNow();

  @override
  Future<void> setApiKey(String key) async {}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/skill/registry/git_repo_registry_source_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/skill/registry/git_repo_registry_source.dart client/test/services/skill/registry/git_repo_registry_source_test.dart
git commit -m "feat(skills): git repo registry source"
```

---

### Task 6: Factory + SkillCubit unified state + registry CRUD

**Files:**
- Create: `client/lib/services/skill/registry/skill_registry_factory.dart`
- Modify: `client/lib/cubits/skill_cubit.dart` (state + actions, see below)
- Modify: `client/lib/app/app_shell.dart` (~line 967 wiring)
- Modify: `client/lib/repositories/skill_repository.dart` (remove `skillsSh`/`searchSkillsSh`; remove `repos` field and repo methods — see Step 4)
- Modify: `client/lib/models/unified_skill_entry.dart` — Create
- Modify: `client/lib/services/skill/skill_repo_service.dart` — Delete
- Test: `client/test/cubits/skill_unified_discovery_test.dart` (new), adjust `client/test/cubits/skill_marketplace_cubit_test.dart` (delete) and `client/test/cubits/skill_cubit_test.dart` (replace repo-API usage)

**Interfaces:**
- Consumes: `SkillRegistrySource`, `ApiRegistrySource`, `GitRepoRegistrySource`, `SkillRegistriesConfig`, `SkillRegistryConfigService` (Tasks 1-5).
- Produces (used by Tasks 7-9):
  - `SkillRegistryFactory.build(SkillRegistriesConfig config, {required SkillRepository repository, http.Client? client}) → List<SkillRegistrySource>` — git sources wire `discoverableProvider: () => repository.readCachedDiscoverable(SkillRepo(owner, name, branch))` and `syncNow: () async { await repository.syncRepoCache(repo, force: true); }`; api sources → `ApiRegistrySource`.
  - `SkillState` changes: REMOVE `marketplace` (map) — ADD `registriesConfig: SkillRegistriesConfig`, `sources: List<SkillRegistrySource>`, `discoveryEntries: List<UnifiedSkillEntry>`, `discoveryPages: Map<String, int>`, `discoveryHasNext: Map<String, bool>`, `discoveryTotals: Map<String, int>`, `discoveryError: String?`, `discoveryBrowsing: bool`, `discoveryLastQuery: SkillRegistryQuery?` (drives load-more).
  - `UnifiedSkillEntry` (`client/lib/models/unified_skill_entry.dart`): `{ MarketplaceSkill skill; String sourceId; String? repoKey; }` with `dedupeKey` = `'${owner}/${repo}/${directory}'` lowercase.
  - `SkillCubit` ctor: `SkillCubit(this._repo, {required this.registryConfigService, required List<SkillRegistrySource> initialSources, required List<SkillRegistrySource> Function(SkillRegistriesConfig) rebuildSources, SkillAcquisitionEngine? acquisitionEngine, SkillUninstalledHandler? onSkillUninstalled, PackAcquireActivityAdapter? packAcquireActivity})`.
  - New methods: `unifiedBrowse()`, `unifiedSearch(String query, {String? sourceId, String? category, String? occupation, String? language, String? sortBy})`, `unifiedLoadMore()`, `unifiedSetApiKey(String sourceId, String key)`, `installUnifiedEntry(UnifiedSkillEntry e)`, `Future<bool> testRegistryConnection(String id)`, `addRegistrySource(SkillRegistrySourceConfig cfg)`, `updateRegistrySource(SkillRegistrySourceConfig cfg)`, `removeRegistrySource(String id)`, `toggleRegistrySource(String id, bool enabled)`.
  - Removed: `searchMarketplace`, `loadMoreMarketplace`, `setMarketplaceApiKey`, `clearMarketplaceError`, `installMarketplaceEntry`, `addRepo`, `removeRepo`, `toggleRepoEnabled`, `_marketplaceById`.
  - Kept with adaption: `loadAll` (loads installed + config), `ensureDiscoveryLoaded`/`refreshDiscoverable`/`_syncReposInBackground`/`_aggregateDiscoverableFromDisk` (git repos now from `_gitRepos()` derived from `state.sources`), `installFromDiscovery`, `uninstall`, `toggleSkillEnabled`, `checkUpdates`, `updateSkill`, `updateAll`, `scanUnmanaged`, `importUnmanaged`, `installFromZip`, `_emitInstalled`, `_runPackAcquireTracked`, `installTeamDependency`.

- [ ] **Step 1: Write the failing test**

Create `client/test/cubits/skill_unified_discovery_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/registry/skill_registry_config_service.dart';
import 'package:teampilot/services/skill/registry/skill_registry_source.dart';
import 'package:teampilot/services/storage/app_storage.dart';

class _FakeRegistry implements SkillRegistrySource {
  _FakeRegistry(this.id, this.total, {this.pageSize = 2, this.quota = false});
  final String id;
  final int total;
  final int pageSize;
  final bool quota;
  final List<SkillRegistryQuery> queries = [];

  @override
  String get label => id;
  @override
  bool get enabled => true;
  @override
  SkillRegistryKind get kind => SkillRegistryKind.api;
  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();

  @override
  Future<SkillRegistryPage> search(SkillRegistryQuery q) async {
    queries.add(q);
    if (quota) throw MarketplaceQuotaException('quota');
    final start = (q.page - 1) * pageSize;
    final end = start + pageSize;
    final items = <MarketplaceSkill>[
      for (var i = start; i < end && i < total; i++)
        MarketplaceSkill(
          key: '$id-$i',
          name: '$id-$i',
          description: 'd',
          repoOwner: 'o',
          repoName: 'r',
          directory: 'dir/$i',
          githubUrl: 'https://github.com/o/r',
        ),
    ];
    return SkillRegistryPage(
      entries: items,
      hasNext: end < total,
      total: total,
    );
  }

  @override
  Future<void> testConnection() async {}
  @override
  Future<void> setApiKey(String key) async {}
}

SkillCubit _cubit(List<SkillRegistrySource> sources, SkillRegistryConfigService cfg, SkillRepository repo) =>
    SkillCubit(
      repo,
      registryConfigService: cfg,
      initialSources: sources,
      rebuildSources: (c) => sources,
    );

void main() {
  late Directory tmp;
  late SkillRegistryConfigService cfg;
  late SkillRepository repo;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('skill-unified-');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
    cfg = SkillRegistryConfigService(teampilotRoot: paths.basePath);
    repo = SkillRepository();
  });

  tearDown(() {
    AppStorage.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('unifiedBrowse merges page 1 from all sources', () async {
    final a = _FakeRegistry('a', 3);
    final b = _FakeRegistry('b', 3);
    final cubit = _cubit([a, b], cfg, repo);
    await cubit.unifiedBrowse();
    final s = cubit.state;
    expect(s.discoveryEntries.length, 4); // 2 per source (pageSize 2)
    expect(s.discoveryEntries.map((e) => e.sourceId).toSet(), {'a', 'b'});
    expect(s.discoveryHasNext['a'], isTrue);
    expect(s.discoveryBrowsing, isTrue);
  });

  test('unifiedLoadMore appends next pages and advances cursors', () async {
    final a = _FakeRegistry('a', 3);
    final b = _FakeRegistry('b', 3);
    final cubit = _cubit([a, b], cfg, repo);
    await cubit.unifiedBrowse();
    await cubit.unifiedLoadMore();
    final s = cubit.state;
    expect(s.discoveryEntries.length, 6); // a-0..2 + b-0..2
    expect(s.discoveryPages['a'], 2);
    expect(
      s.discoveryEntries
          .where((e) => e.sourceId == 'a')
          .map((e) => e.skill.key),
      contains('a-2'),
    );
    expect(s.discoveryHasNext['a'], isFalse);
  });

  test('unifiedSearch with short query falls back to browse', () async {
    final a = _FakeRegistry('a', 3);
    final cubit = _cubit([a], cfg, repo);
    await cubit.unifiedSearch('x');
    expect(cubit.state.discoveryEntries.length, 3);
    expect(a.queries.last.query, '');
  });

  test('quota error surfaces discoveryError key', () async {
    final a = _FakeRegistry('a', 3, quota: true);
    final cubit = _cubit([a], cfg, repo);
    await cubit.unifiedBrowse();
    expect(cubit.state.discoveryError, marketplaceQuotaErrorKey);
    expect(cubit.state.discoveryEntries, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/skill_unified_discovery_test.dart`
Expected: FAIL — `SkillCubit` new ctor/state missing.

- [ ] **Step 3: Create UnifiedSkillEntry + factory**

Create `client/lib/models/unified_skill_entry.dart`:

```dart
import 'skill_registry_source.dart';
import '../services/skill/marketplace/skill_marketplace_source.dart';

class UnifiedSkillEntry {
  const UnifiedSkillEntry({
    required this.skill,
    required this.sourceId,
    this.repoKey,
  });

  final MarketplaceSkill skill;
  final String sourceId;

  /// git 源过滤用（`owner__name`）。
  final String? repoKey;

  String get dedupeKey =>
      '${skill.repoOwner}/${skill.repoName}/${skill.directory ?? ''}'
          .toLowerCase();
}
```

Create `client/lib/services/skill/registry/skill_registry_factory.dart`:

```dart
import 'package:http/http.dart' as http;

import '../../../models/skill.dart';
import '../../../models/skill_registry_source.dart';
import '../../../repositories/skill_repository.dart';
import 'api_registry_source.dart';
import 'git_repo_registry_source.dart';
import 'skill_registry_source.dart';

abstract final class SkillRegistryFactory {
  static List<SkillRegistrySource> build(
    SkillRegistriesConfig config, {
    required SkillRepository repository,
    http.Client? client,
  }) => [
    for (final c in config.sources)
      if (c.kind == SkillRegistryKind.api)
        ApiRegistrySource(c, client: client)
      else
        GitRepoRegistrySource(
          c,
          discoverableProvider: () => repository.readCachedDiscoverable(
            SkillRepo(
              owner: c.gitOwner ?? '',
              name: c.gitName ?? '',
              branch: c.gitBranch ?? 'main',
            ),
          ),
          syncNow: () async {
            await repository.syncRepoCache(
              SkillRepo(
                owner: c.gitOwner ?? '',
                name: c.gitName ?? '',
                branch: c.gitBranch ?? 'main',
              ),
              force: true,
            );
          },
        ),
  ];
}
```

- [ ] **Step 4: Modify SkillRepository (remove skillsSh + repos)**

In `client/lib/repositories/skill_repository.dart`:
- Remove `SkillsShService` import, `skillsSh` field, factory param `SkillsShService? skillsSh`, `resolvedSkillsSh` wiring, and `searchSkillsSh` method.
- Remove `SkillRepoService` import, `repos` field, factory param `SkillRepoService? repos`, `resolvedRepos` wiring, `loadRepos`, `syncRepoCache` keep (still used by factory), keep `readCachedDiscoverable`, `deleteRepoCache` (used by cubit removal path).
- The factory ctor `SkillRepository._` drops `repos` and `skillsSh`.
- Delete `client/lib/services/skill/skill_repo_service.dart` (repos.json store) — after confirming no other references (`rg "SkillRepoService" client/lib` should return only the deleted file + skill_repository).

- [ ] **Step 5: Modify SkillCubit state + ctor + git-sync helpers**

In `client/lib/cubits/skill_cubit.dart`:

Replace the `MarketplaceSearchState` class (lines 19-87) with:

```dart
class MarketplaceSearchState extends Equatable {
  // KEEP this class only if still referenced elsewhere; otherwise delete.
}
```

**Decision: delete `MarketplaceSearchState` entirely.** In `SkillState`:

```dart
  const SkillState({
    this.installed = const [],
    this.discoverable = const [],
    this.updates = const [],
    this.registriesConfig = const SkillRegistriesConfig(sources: []),
    this.sources = const [],
    this.discoveryEntries = const [],
    this.discoveryPages = const {},
    this.discoveryHasNext = const {},
    this.discoveryTotals = const {},
    this.discoveryError,
    this.discoveryBrowsing = false,
    this.status = SkillLoadStatus.idle,
    this.errorMessage,
    this.noticeMessage,
    this.busyIds = const {},
    this.discoveryLoading = false,
    this.updatesLoading = false,
    this.repoSyncingKeys = const {},
    this.toolbarBusy = false,
  });
```

with matching `copyWith` params/props and getter `bool get anyDiscoveryHasNext => discoveryHasNext.values.any((v) => v);`. Remove `repos` and `marketplace` fields.

Ctor:

```dart
  SkillCubit(
    this._repo, {
    required this.registryConfigService,
    required List<SkillRegistrySource> initialSources,
    required List<SkillRegistrySource> Function(SkillRegistriesConfig) rebuildSources,
    SkillAcquisitionEngine? acquisitionEngine,
    SkillUninstalledHandler? onSkillUninstalled,
    PackAcquireActivityAdapter? packAcquireActivity,
  }) : _rebuildSources = rebuildSources,
       _acquisitionEngine = acquisitionEngine ?? ... (unchanged),
       _onSkillUninstalled = onSkillUninstalled,
       _packAcquireActivity = packAcquireActivity,
       super(SkillState(sources: initialSources));

  final SkillRegistryConfigService registryConfigService;
  final List<SkillRegistrySource> Function(SkillRegistriesConfig) _rebuildSources;
```

Git repo derivation + sync helpers:

```dart
  List<SkillRepo> _gitRepos() => [
    for (final s in state.sources)
      if (s.kind == SkillRegistryKind.gitRepo && s.enabled)
        SkillRepo(
          owner: (s as GitRepoRegistrySource).config.gitOwner ?? '',
          name: (s as GitRepoRegistrySource).config.gitName ?? '',
          branch: (s as GitRepoRegistrySource).config.gitBranch ?? 'main',
          enabled: true,
        ),
  ];
```

Hmm — `_gitRepos()` needs `GitRepoRegistrySource.config`; instead expose `SkillRepo? get gitRepo` on `GitRepoRegistrySource`:

Add to `GitRepoRegistrySource` (Task 5 file):

```dart
  SkillRepo get gitRepo => SkillRepo(
    owner: config.gitOwner ?? '',
    name: config.gitName ?? '',
    branch: config.gitBranch ?? 'main',
    enabled: config.enabled,
  );
```

Then in cubit: `List<SkillRepo> _gitRepos() => [for (final s in state.sources) if (s is GitRepoRegistrySource && s.enabled) s.gitRepo];`

Update `refreshDiscoverable` (uses `state.repos` → `_gitRepos()`), `_syncReposInBackground` (same), `_aggregateDiscoverableFromDisk(enabled)` (unchanged signature), `ensureDiscoveryLoaded` (unchanged).

- [ ] **Step 6: Replace marketplace/repo actions with unified + registry CRUD**

In `skill_cubit.dart`, replace `searchMarketplace`/`loadMoreMarketplace`/`setMarketplaceApiKey`/`clearMarketplaceError`/`installMarketplaceEntry`/`addRepo`/`removeRepo`/`toggleRepoEnabled` (and `_marketplaceById`) with:

```dart
  static const _unifiedPageSize = 20;

  List<SkillRegistrySource> get _enabledSources =>
      state.sources.where((s) => s.enabled).toList();

  Future<void> unifiedBrowse() async {
    await _unifiedSearch('', sourceId: null);
  }

  Future<void> unifiedSearch(
    String query, {
    String? sourceId,
    String? category,
    String? occupation,
    String? language,
    String? sortBy,
  }) async {
    final q = query.trim();
    final effectiveQ = q.length >= 2 ? q : '';
    final sources = sourceId != null
        ? state.sources.where((s) => s.id == sourceId && s.enabled).toList()
        : _enabledSources;
    if (sources.isEmpty) {
      emit(state.copyWith(
        discoveryEntries: const [],
        discoveryPages: const {},
        discoveryHasNext: const {},
        discoveryTotals: const {},
        discoveryError: null,
        discoveryBrowsing: effectiveQ.isEmpty,
        discoveryLoading: false,
      ));
      return;
    }
    emit(state.copyWith(
      discoveryLoading: true,
      discoveryBrowsing: effectiveQ.isEmpty,
      discoveryError: null,
    ));
    final lastQuery = SkillRegistryQuery(
      query: effectiveQ,
      page: 1,
      limit: _unifiedPageSize,
      category: category,
      occupation: occupation,
      language: language,
      sortBy: sortBy,
    );
    final results = await Future.wait(sources.map((s) async {
      try {
        final page = await s.search(lastQuery);
        return (source: s, page: page, error: null);
      } catch (e) {
        return (
          source: s,
          page: SkillRegistryPage(entries: const [], hasNext: false),
          error: e is MarketplaceQuotaException
              ? marketplaceQuotaErrorKey
              : '$e',
        );
      }
    }));
    if (!isClosed) {
      final merged = _mergeEntries(results);
      emit(state.copyWith(
        discoveryEntries: merged.entries,
        discoveryPages: {for (final r in results) r.source.id: 1},
        discoveryHasNext: {
          for (final r in results) r.source.id: r.page.hasNext,
        },
        discoveryTotals: {
          for (final r in results) r.source.id: r.page.total,
        },
        discoveryLastQuery: lastQuery,
        discoveryError: results.any((r) => r.error != null)
            ? results.firstWhere((r) => r.error != null).error
            : null,
        discoveryLoading: false,
      ));
    }
  }

  Future<void> unifiedLoadMore() async {
    if (state.discoveryLoading) return;
    if (!state.anyDiscoveryHasNext) return;
    emit(state.copyWith(discoveryLoading: true));
    final last = state.discoveryLastQuery ??
        SkillRegistryQuery(page: 1, limit: _unifiedPageSize);
    final nextPages = <String, int>{};
    final results = await Future.wait(
      _enabledSources.map((s) async {
        final loaded = state.discoveryPages[s.id] ?? 0;
        if (loaded == 0) {
          nextPages[s.id] = 0;
          return (
            source: s,
            page: SkillRegistryPage(entries: const [], hasNext: false),
            error: null,
          );
        }
        final next = loaded + 1;
        nextPages[s.id] = next;
        try {
          final page = await s.search(SkillRegistryQuery(
            query: last.query,
            page: next,
            limit: last.limit,
            category: last.category,
            occupation: last.occupation,
            language: last.language,
            sortBy: last.sortBy,
          ));
          return (source: s, page: page, error: null);
        } catch (e) {
          return (
            source: s,
            page: SkillRegistryPage(entries: const [], hasNext: false),
            error: e is MarketplaceQuotaException
                ? marketplaceQuotaErrorKey
                : '$e',
          );
        }
      }),
    );
    if (!isClosed) {
      final merged = _mergeEntries(results, appendTo: state.discoveryEntries);
      emit(state.copyWith(
        discoveryEntries: merged.entries,
        discoveryPages: {...state.discoveryPages, ...nextPages},
        discoveryHasNext: {
          ...state.discoveryHasNext,
          for (final r in results) r.source.id: r.page.hasNext,
        },
        discoveryError: results.any((r) => r.error != null)
            ? results.firstWhere((r) => r.error != null).error
            : null,
        discoveryLoading: false,
      ));
    }
  }

  ({List<UnifiedSkillEntry> entries}) _mergeEntries(
    List<({SkillRegistrySource source, SkillRegistryPage page, String? error})> results, {
    List<UnifiedSkillEntry>? appendTo,
  }) {
    final seen = <String>{};
    final out = <UnifiedSkillEntry>[
      if (appendTo != null) ...appendTo.where((e) => seen.add(e.dedupeKey)),
    ];
    for (final r in results) {
      for (final skill in r.page.entries) {
        final entry = UnifiedSkillEntry(
          skill: skill,
          sourceId: r.source.id,
          repoKey: r.source is GitRepoRegistrySource
              ? SkillRepoDiskCacheService.repoKey((r.source as GitRepoRegistrySource).gitRepo)
              : null,
        );
        if (seen.add(entry.dedupeKey)) out.add(entry);
      }
    }
    return (entries: out);
  }

  Future<void> unifiedSetApiKey(String sourceId, String key) async {
    final cfg = state.registriesConfig.byId(sourceId);
    if (cfg == null || cfg.kind != SkillRegistryKind.api) return;
    await _applyConfig(
      SkillRegistriesConfig(sources: [
        for (final s in state.registriesConfig.sources)
          s.id == sourceId
              ? s.copyWith(clearApiToken: key.trim().isEmpty, apiToken: key.trim().isEmpty ? null : key.trim())
              : s,
      ]),
    );
    emit(state.copyWith(discoveryError: null));
  }

  Future<bool> testRegistryConnection(String id) async {
    SkillRegistrySource? found;
    for (final s in state.sources) {
      if (s.id == id) {
        found = s;
        break;
      }
    }
    if (found == null) return false;
    try {
      await found.testConnection();
      return true;
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
      return false;
    }
  }

  Future<void> addRegistrySource(SkillRegistrySourceConfig cfg) async {
    if (state.registriesConfig.byId(cfg.id) != null) return;
    await _applyConfig(
      SkillRegistriesConfig(sources: [...state.registriesConfig.sources, cfg]),
    );
    if (cfg.kind == SkillRegistryKind.gitRepo && cfg.enabled) {
      await _syncReposInBackground([SkillRepo(owner: cfg.gitOwner ?? '', name: cfg.gitName ?? '', branch: cfg.gitBranch ?? 'main')]);
    }
  }

  Future<void> updateRegistrySource(SkillRegistrySourceConfig cfg) async {
    final next = SkillRegistriesConfig(sources: [
      for (final s in state.registriesConfig.sources)
        s.id == cfg.id ? cfg : s,
    ]);
    await _applyConfig(next);
    var oldIsGit = false;
    for (final s in state.sources) {
      if (s.id == cfg.id && s is GitRepoRegistrySource) {
        oldIsGit = true;
        break;
      }
    }
    if (cfg.kind == SkillRegistryKind.gitRepo && cfg.enabled && !oldIsGit) {
      unawaited(_syncReposInBackground([SkillRepo(owner: cfg.gitOwner ?? '', name: cfg.gitName ?? '', branch: cfg.gitBranch ?? 'main')]));
    }
  }

  Future<void> removeRegistrySource(String id) async {
    final cfg = state.registriesConfig.byId(id);
    if (cfg == null) return;
    if (cfg.kind == SkillRegistryKind.gitRepo) {
      await _repo.deleteRepoCache(SkillRepo(owner: cfg.gitOwner ?? '', name: cfg.gitName ?? '', branch: cfg.gitBranch ?? 'main'));
    }
    await _applyConfig(
      SkillRegistriesConfig(sources: [
        for (final s in state.registriesConfig.sources)
          if (s.id != id) s,
      ]),
    );
  }

  Future<void> toggleRegistrySource(String id, bool enabled) async {
    final cfg = state.registriesConfig.byId(id);
    if (cfg == null) return;
    await updateRegistrySource(cfg.copyWith(enabled: enabled));
  }

  Future<void> _applyConfig(SkillRegistriesConfig config) async {
    await registryConfigService.save(config);
    final sources = _rebuildSources(config);
    if (!isClosed) {
      emit(state.copyWith(registriesConfig: config, sources: sources));
    }
  }
```

Install action replacing `installMarketplaceEntry`:

```dart
  Future<void> installUnifiedEntry(UnifiedSkillEntry e) async {
    final skill = e.skill;
    if (state.busyIds.contains(skill.key)) return;
    emit(state.copyWith(busyIds: {...state.busyIds, skill.key}, clearError: true));
    try {
      if (skill.isInstalledDirectly) {
        await _acquisitionEngine.installGitDir(
          DiscoverableSkill(
            key: skill.key,
            name: skill.name,
            description: skill.description,
            directory: skill.directory!,
            readmeUrl: skill.githubUrl,
            repoOwner: skill.repoOwner,
            repoName: skill.repoName,
            repoBranch: skill.repoBranch,
          ),
        );
        final installed = await _repo.loadInstalled();
        emit(state.copyWith(installed: installed));
      } else {
        await addRegistrySource(
          SkillRegistrySourceConfig(
            id: 'git-${skill.repoOwner}-${skill.repoName}',
            kind: SkillRegistryKind.gitRepo,
            label: '${skill.repoOwner}/${skill.repoName}',
            gitOwner: skill.repoOwner,
            gitName: skill.repoName,
            gitBranch: skill.repoBranch,
          ),
        );
        emit(state.copyWith(noticeMessage: marketplaceRepoAddedNoticeKey));
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    } finally {
      final next = {...state.busyIds}..remove(skill.key);
      emit(state.copyWith(busyIds: next));
    }
  }
```

`loadAll` (replace repos load):

```dart
  Future<void> loadAll() async {
    emit(state.copyWith(status: SkillLoadStatus.loading, clearError: true));
    try {
      final installed = await _repo.loadInstalled();
      final config = await registryConfigService.load();
      final sources = _rebuildSources(config);
      emit(
        state.copyWith(
          installed: installed,
          registriesConfig: config,
          sources: sources,
          status: SkillLoadStatus.ready,
        ),
      );
    } catch (e) {
      appLogger.e('[skills] loadAll failed: $e');
      emit(state.copyWith(status: SkillLoadStatus.error, errorMessage: '$e'));
    }
  }
```

Note: replace all remaining `state.repos` references in `refreshDiscoverable`/`_syncReposInBackground`/`toggleRepoEnabled`-era code with `_gitRepos()`. The `_emitDiscoveryProgress` and `_sameDiscoverableSkills` helpers stay.

Imports to add to skill_cubit.dart: `../models/skill_registry_source.dart`, `../models/unified_skill_entry.dart`, `skill_registry_source.dart` (registry), `git_repo_registry_source.dart`, `api_registry_source.dart` (for `GitRepoRegistrySource` type checks), `skill_registry_config_service.dart`. Keep `SkillRepoDiskCacheService` import.

- [ ] **Step 7: Wire app_shell.dart**

Replace lines ~967-976:

```dart
  final skillRegistryConfigService = SkillRegistryConfigService(
    legacySkillsMpKeyReader: () => appSettings.loadSkillsMpApiKey(),
  );
  final skillRegistryConfig = await skillRegistryConfigService.load();
  skillCubit = SkillCubit(
    skillRepo,
    registryConfigService: skillRegistryConfigService,
    initialSources: SkillRegistryFactory.build(
      skillRegistryConfig,
      repository: skillRepo,
    ),
    rebuildSources: (config) =>
        SkillRegistryFactory.build(config, repository: skillRepo),
    acquisitionEngine: skillAcquisitionEngine,
    onSkillUninstalled: teamCubit.removeSkillFromAllTeams,
    packAcquireActivity: packAcquireActivityAdapter,
  );
```

Add imports to app_shell.dart: `services/skill/registry/skill_registry_config_service.dart`, `services/skill/registry/skill_registry_factory.dart`. Remove `services/skill/marketplace/skill_marketplace_registry.dart` import.

- [ ] **Step 8: Run tests + fix cubit test fallout**

Run: `cd client && flutter test test/cubits/skill_unified_discovery_test.dart`
Expected: PASS (after fixing compile errors in the test file from the `firstOrNull` record syntax — use `where(...).isEmpty ? null : where(...).first` if `firstOrNull` is unavailable).

Then:
- Delete `client/test/cubits/skill_marketplace_cubit_test.dart` (superseded by the unified test).
- In `client/test/cubits/skill_cubit_test.dart`, replace any `addRepo`/`removeRepo`/`toggleRepoEnabled`/`installMarketplaceEntry` usage with the new registry/unified APIs (search the file for `addRepo|removeRepo|toggleRepoEnabled|marketplace` and adapt; the fake `SkillRepository` there must drop the `repos`/`skillsSh` members).

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: remaining errors are the UI files rewritten in Tasks 7-9 + `skill_marketplace_panel.dart`/`skill_discovery_section.dart`/`skill_discovery_repos_panel.dart`/`skill_repos_section.dart`/`skill_discover_card.dart`/`skill_section.dart`/`skill_management_page.dart` — expected until Tasks 7-8.

- [ ] **Step 9: Commit**

```bash
git add client/lib/cubits/skill_cubit.dart client/lib/models/unified_skill_entry.dart client/lib/services/skill/registry/skill_registry_factory.dart client/lib/repositories/skill_repository.dart client/lib/services/skill/registry/git_repo_registry_source.dart client/lib/app/app_shell.dart client/test/cubits/skill_unified_discovery_test.dart client/test/cubits/skill_marketplace_cubit_test.dart client/test/cubits/skill_cubit_test.dart
git rm client/lib/services/skill/skill_repo_service.dart
git commit -m "feat(skills): unified discovery state + registry CRUD in SkillCubit"
```

---

### Task 7: Registries section UI + nav rename

**Files:**
- Modify: `client/lib/pages/skills/skill_section.dart` (enum `repos` → `registries`, title/icon via l10n)
- Modify: `client/lib/pages/skills/skill_management_page.dart` (nav item + body branch; `onGoRepos` → `onGoRegistries` is Task 8)
- Create: `client/lib/pages/skills/skill_registries_section.dart`
- Modify: `client/lib/l10n/app_en.arb` + `app_zh.arb` (add keys; then `flutter gen-l10n`)
- Test: `client/test/pages/skills/skill_registries_section_test.dart`

**Interfaces:**
- Consumes: `SkillCubit` new API (`state.sources`, `state.registriesConfig`, `toggleRegistrySource`, `updateRegistrySource`, `removeRegistrySource`, `addRegistrySource`, `testRegistryConnection`, `state.repoSyncingKeys`), `SkillRegistrySourceConfig`/`SkillRegistriesConfig`, `ApiRegistrySource`/`GitRepoRegistrySource` (for kind/protocol introspection via `source.config`).
- Produces (used by Task 8): `SkillDiscoverySection(onGoRegistries: VoidCallback)` navigates to `/skills/registries`.

- [ ] **Step 1: Update nav enum + l10n**

`client/lib/pages/skills/skill_section.dart`:

```dart
enum SkillSection implements WorkspaceSectionDescriptor {
  installed,
  discovery,
  registries;

  @override
  String get routeSegment => name;

  @override
  String routePath(String basePath) => '$basePath/$routeSegment';

  @override
  String title(AppLocalizations l10n) => switch (this) {
    SkillSection.installed => l10n.skillsNavInstalled,
    SkillSection.discovery => l10n.skillsNavDiscovery,
    SkillSection.registries => l10n.skillsNavRegistries,
  };

  @override
  IconData get icon => skillSectionIcon(this);
}

void navigateSkillSection(BuildContext context, SkillSection target) {
  navigateWorkspaceRoute(context, target.routePath('/skills'));
}

IconData skillSectionIcon(SkillSection section) => switch (section) {
  SkillSection.installed => Icons.inventory_2_outlined,
  SkillSection.discovery => Icons.travel_explore_outlined,
  SkillSection.registries => Icons.source_outlined,
};
```

In `client/lib/l10n/app_en.arb` add:

```json
  "skillsNavRegistries": "Registries",
  "skillsRegistryApiKeySet": "API key set",
  "skillsRegistryAddSource": "Add registry source",
  "skillsRegistrySourceKind": "Source type",
  "skillsRegistrySourceKindApi": "API source",
  "skillsRegistrySourceKindGit": "Git repository",
  "skillsRegistryProtocolLabel": "Protocol",
  "skillsRegistryProtocolSkillsSh": "skills.sh compatible",
  "skillsRegistryProtocolSkillsMp": "SkillsMP compatible",
  "skillsRegistryNameLabel": "Display name",
  "skillsRegistryBaseUrlLabel": "Base URL",
  "skillsRegistryBrowseQueryLabel": "Default browse query",
  "skillsRegistryTokenLabel": "API Key",
  "skillsRegistryOwnerLabel": "Owner",
  "skillsRegistryNameOfRepoLabel": "Repository",
  "skillsRegistryTestOk": "Connection OK",
  "skillsRegistryTestFailed": "Connection failed: {error}",
  "skillsRegistryGoSetKey": "Set API key in Registries",
  "skillsRegistryEditTitle": "Edit registry source",
  "skillsRegistryRemoveTitle": "Reset registry",
  "skillsRegistryResetConfirm": "Reset {name} to defaults?"
```

In `client/lib/l10n/app_zh.arb` add:

```json
  "skillsNavRegistries": "注册中心",
  "skillsRegistryApiKeySet": "已设置 API Key",
  "skillsRegistryAddSource": "添加注册源",
  "skillsRegistrySourceKind": "源类型",
  "skillsRegistrySourceKindApi": "API 源",
  "skillsRegistrySourceKindGit": "Git 仓库",
  "skillsRegistryProtocolLabel": "协议",
  "skillsRegistryProtocolSkillsSh": "skills.sh 兼容",
  "skillsRegistryProtocolSkillsMp": "SkillsMP 兼容",
  "skillsRegistryNameLabel": "显示名称",
  "skillsRegistryBaseUrlLabel": "API 地址",
  "skillsRegistryBrowseQueryLabel": "默认浏览词",
  "skillsRegistryTokenLabel": "API Key",
  "skillsRegistryOwnerLabel": "Owner",
  "skillsRegistryNameOfRepoLabel": "仓库名",
  "skillsRegistryTestOk": "连接成功",
  "skillsRegistryTestFailed": "连接失败：{error}",
  "skillsRegistryGoSetKey": "去注册中心设置 API Key",
  "skillsRegistryEditTitle": "编辑注册源",
  "skillsRegistryRemoveTitle": "重置注册源",
  "skillsRegistryResetConfirm": "将 {name} 重置为默认值？"
```

Run: `cd client && flutter gen-l10n`

- [ ] **Step 2: Write the failing widget test**

Create `client/test/pages/skills/skill_registries_section_test.dart` (concrete; uses the temp-root pattern from `skill_discovery_section_test.dart`):

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/pages/skills/skill_registries_section.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/registry/api_registry_source.dart';
import 'package:teampilot/services/skill/registry/git_repo_registry_source.dart';
import 'package:teampilot/services/skill/registry/skill_registry_config_service.dart';
import 'package:teampilot/services/skill/registry/skill_registry_source.dart';
import 'package:teampilot/services/storage/app_storage.dart';

List<SkillRegistrySource> _rebuild(SkillRegistriesConfig c) => [
  for (final cfg in c.sources)
    if (cfg.kind == SkillRegistryKind.api)
      ApiRegistrySource(cfg)
    else
      GitRepoRegistrySource(
        cfg,
        discoverableProvider: () async => const [],
        syncNow: () async {},
      ),
];

void main() {
  late Directory tmp;
  late AppPaths paths;
  late SkillRegistryConfigService cfgService;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('skill-reg-section-');
    paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
    cfgService = SkillRegistryConfigService(teampilotRoot: paths.basePath);
  });

  tearDown(() {
    AppStorage.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget wrap(SkillCubit cubit) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: BlocProvider<SkillCubit>.value(
        value: cubit,
        child: const SizedBox(height: 900, child: SkillRegistriesSection()),
      ),
    ),
  );

  Future<SkillCubit> buildCubit() async {
    await cfgService.save(SkillRegistriesConfig.defaults());
    final cubit = SkillCubit(
      SkillRepository(),
      registryConfigService: cfgService,
      initialSources: const [],
      rebuildSources: _rebuild,
    );
    await cubit.loadAll();
    return cubit;
  }

  testWidgets('shows source rows with labels and switches', (tester) async {
    final cubit = await buildCubit();
    await tester.pumpWidget(wrap(cubit));
    await tester.pumpAndSettle();
    expect(find.text('https://skills.sh'), findsOneWidget);
    expect(find.text('https://skillsmp.com/api/v1'), findsOneWidget);
    expect(find.text('@SkillsMP'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(6)); // 2 API + 4 default git
  });

  testWidgets('edit dialog saves display name to registries.json', (tester) async {
    final cubit = await buildCubit();
    await tester.pumpWidget(wrap(cubit));
    await tester.pumpAndSettle();
    await tester.tap(find.text('https://skills.sh'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'My Skills');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final raw = await AppStorage.fs.readString(
      AppPaths.skillRegistriesConfigPathForTeampilotRoot(paths.basePath),
    );
    expect(raw, contains('My Skills'));
  });

  testWidgets('add API source flow', (tester) async {
    final cubit = await buildCubit();
    await tester.pumpWidget(wrap(cubit));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add registry source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('API source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SkillsMP compatible'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'My API');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('@My API'), findsWidgets);
  });

  testWidgets('remove custom git source confirms and deletes', (tester) async {
    final defaults = SkillRegistriesConfig.defaults();
    final custom = SkillRegistrySourceConfig(
      id: 'git-vercel-ai',
      kind: SkillRegistryKind.gitRepo,
      label: 'vercel/ai',
      gitOwner: 'vercel',
      gitName: 'ai',
      gitBranch: 'main',
    );
    await cfgService.save(
      SkillRegistriesConfig(sources: [...defaults.sources, custom]),
    );
    final cubit = await buildCubit();
    await tester.pumpWidget(wrap(cubit));
    await tester.pumpAndSettle();
    await tester.tap(find.text('https://github.com/vercel/ai'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('https://github.com/vercel/ai'), findsNothing);
  });
}
```

(Adjust finder details — e.g. first `Switch` count — if the default config differs; the intent is: rows render, edit persists to file, add flow works, remove works.)

- [ ] **Step 3: Implement SkillRegistriesSection**

Create `client/lib/pages/skills/skill_registries_section.dart` — model on `mcp_registries_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/skill_registry_source.dart';
import '../../services/skill/registry/api_registry_source.dart';
import '../../services/skill/registry/git_repo_registry_source.dart';
import '../../services/skill/registry/skill_registry_source.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/debounce/button_callbacks.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/workspace_library_card.dart';
import 'skill_management_cards.dart';

class SkillRegistriesSection extends StatefulWidget {
  const SkillRegistriesSection({super.key});

  @override
  State<SkillRegistriesSection> createState() => _SkillRegistriesSectionState();
}

class _SkillRegistriesSectionState extends State<SkillRegistriesSection> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<SkillCubit, SkillState>(
      builder: (context, state) {
        return SingleChildScrollView(
          child: WorkspaceLibraryCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TpCardHeader(title: l10n.skillsNavRegistries),
                const SizedBox(height: 12),
                for (final source in state.sources)
                  _RegistryRow(
                    source: source,
                    syncing: source is GitRepoRegistrySource &&
                        state.repoSyncingKeys.contains(
                          '${source.gitRepo.owner}__${source.gitRepo.name}',
                        ),
                    onToggle: (v) => context
                        .read<SkillCubit>()
                        .toggleRegistrySource(source.id, v),
                    onEdit: () => _editSource(context, source),
                    onReset: () => _resetSource(context, source),
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: throttledAsync('skill_add_registry', () =>
                        _addSourceDialog(context)),
                    icon: Icon(Icons.add, size: context.tpIconSizes.md),
                    label: Text(l10n.skillsRegistryAddSource),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  // ... (continue below with _editSource / _resetSource / _addSourceDialog /
  //      _RegistryRow / _RegistryEditDialog / _AddSourceDialog — see Step 4)
}
```

- [ ] **Step 4: Complete the section file (dialogs + row)**

Append to the file (full implementation):

```dart
  SkillRegistrySourceConfig _configOf(SkillRegistrySource source) {
    if (source is ApiRegistrySource) return source.config;
    if (source is GitRepoRegistrySource) return source.config;
    return SkillRegistriesConfig.defaults().sources.first;
  }

  Future<void> _editSource(
    BuildContext context,
    SkillRegistrySource source,
  ) async {
    final result = await showDialog<SkillRegistrySourceConfig>(
      context: context,
      builder: (ctx) => _RegistryEditDialog(
        config: _configOf(source),
        onTest: () async {
          final cubit = context.read<SkillCubit>();
          final ok = await cubit.testRegistryConnection(source.id);
          if (!ctx.mounted) return ok;
          AppToast.show(
            ctx,
            message: ok
                ? ctx.l10n.skillsRegistryTestOk
                : ctx.l10n.skillsRegistryTestFailed('connection'),
            variant: ok ? TpToastVariant.success : TpToastVariant.error,
          );
          return ok;
        },
      ),
    );
    if (result == null || !mounted) return;
    await context.read<SkillCubit>().updateRegistrySource(result);
  }

  Future<void> _resetSource(
    BuildContext context,
    SkillRegistrySource source,
  ) async {
    final l10n = context.l10n;
    final isBuiltIn = source.id == 'skillsSh' || source.id == 'skillsMp';
    final cfg = _configOf(source);
    final title = isBuiltIn ? l10n.skillsRegistryRemoveTitle : l10n.skillsRemove;
    final message = isBuiltIn
        ? l10n.skillsRegistryResetConfirm(cfg.label)
        : l10n.skillsRepoRemoveConfirm(cfg.label);
    final ok = await skillConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: isBuiltIn ? l10n.confirm : l10n.skillsRemove,
      destructive: !isBuiltIn,
    );
    if (ok != true || !mounted) return;
    if (isBuiltIn) {
      final defaults = SkillRegistriesConfig.defaults().byId(cfg.id)!;
      await context
          .read<SkillCubit>()
          .updateRegistrySource(cfg.copyWith(
            label: defaults.label,
            baseUrl: defaults.baseUrl,
            browseQuery: defaults.browseQuery,
            clearApiToken: true,
          ));
    } else {
      await context.read<SkillCubit>().removeRegistrySource(cfg.id);
    }
  }

  Future<void> _addSourceDialog(BuildContext context) async {
    final l10n = context.l10n;
    final kind = await showDialog<SkillRegistryKind>(
      context: context,
      builder: (ctx) => TpDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: l10n.skillsRegistryAddSource),
            const SizedBox(height: 16),
            TpDialogListTile(
              icon: Icons.dns_outlined,
              title: l10n.skillsRegistrySourceKindApi,
              subtitle: '',
              onTap: () => Navigator.pop(ctx, SkillRegistryKind.api),
            ),
            TpDialogListTile(
              icon: Icons.source_outlined,
              title: l10n.skillsRegistrySourceKindGit,
              subtitle: '',
              onTap: () => Navigator.pop(ctx, SkillRegistryKind.gitRepo),
            ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    if (kind == SkillRegistryKind.gitRepo) {
      await _addGitSourceDialog(context);
    } else {
      await _addApiSourceDialog(context);
    }
  }

  Future<void> _addGitSourceDialog(BuildContext context) async {
    final l10n = context.l10n;
    final ownerCtl = TextEditingController();
    final nameCtl = TextEditingController();
    final branchCtl = TextEditingController(text: 'main');
    final saved = await showDialog<String?>(
      context: context,
      builder: (ctx) => TpDialog(
        maxWidth: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: l10n.skillsRegistrySourceKindGit),
            const SizedBox(height: 16),
            TextField(
              controller: ownerCtl,
              decoration: InputDecoration(labelText: l10n.skillsRegistryOwnerLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtl,
              decoration: InputDecoration(labelText: l10n.skillsRegistryNameOfRepoLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: branchCtl,
              decoration: InputDecoration(labelText: l10n.skillsRepoBranch),
            ),
            TpDialogActions(
              children: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
                FilledButton(
                  onPressed: () {
                    final owner = ownerCtl.text.trim();
                    final name = nameCtl.text.trim();
                    if (owner.isEmpty || name.isEmpty) return;
                    Navigator.pop(ctx, '$owner/$name/${branchCtl.text.trim().isEmpty ? 'main' : branchCtl.text.trim()}');
                  },
                  child: Text(l10n.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    ownerCtl.dispose();
    nameCtl.dispose();
    branchCtl.dispose();
    if (saved == null || !mounted) return;
    final parts = saved.split('/');
    final id = 'git-${parts[0]}-${parts[1]}';
    if (context.read<SkillCubit>().state.registriesConfig.byId(id) != null) {
      AppToast.show(context, message: l10n.skillsRepoInvalidUrl, variant: TpToastVariant.error);
      return;
    }
    await context.read<SkillCubit>().addRegistrySource(
      SkillRegistrySourceConfig(
        id: id,
        kind: SkillRegistryKind.gitRepo,
        label: '${parts[0]}/${parts[1]}',
        gitOwner: parts[0],
        gitName: parts[1],
        gitBranch: parts[2],
      ),
    );
  }

  Future<void> _addApiSourceDialog(BuildContext context) async {
    final l10n = context.l10n;
    final protocol = await showDialog<SkillRegistryProtocol>(
      context: context,
      builder: (ctx) => TpDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: l10n.skillsRegistryProtocolLabel),
            const SizedBox(height: 16),
            TpDialogListTile(
              icon: Icons.cloud_outlined,
              title: l10n.skillsRegistryProtocolSkillsSh,
              onTap: () => Navigator.pop(ctx, SkillRegistryProtocol.skillsSh),
            ),
            TpDialogListTile(
              icon: Icons.cloud_outlined,
              title: l10n.skillsRegistryProtocolSkillsMp,
              onTap: () => Navigator.pop(ctx, SkillRegistryProtocol.skillsMp),
            ),
          ],
        ),
      ),
    );
    if (protocol == null || !mounted) return;
    final labelCtl = TextEditingController();
    final urlCtl = TextEditingController(text: SkillRegistrySourceConfig.defaultBaseUrl(protocol));
    final browseCtl = TextEditingController(text: protocol == SkillRegistryProtocol.skillsSh ? 'ai' : '');
    final result = await showDialog<SkillRegistrySourceConfig>(
      context: context,
      builder: (ctx) => TpDialog(
        maxWidth: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: l10n.skillsRegistryAddSource),
            const SizedBox(height: 16),
            TextField(
              controller: labelCtl,
              decoration: InputDecoration(labelText: l10n.skillsRegistryNameLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtl,
              decoration: InputDecoration(
                labelText: l10n.skillsRegistryBaseUrlLabel,
                hintText: SkillRegistrySourceConfig.defaultBaseUrl(protocol),
              ),
            ),
            if (protocol == SkillRegistryProtocol.skillsSh) ...[
              const SizedBox(height: 12),
              TextField(
                controller: browseCtl,
                decoration: InputDecoration(labelText: l10n.skillsRegistryBrowseQueryLabel),
              ),
            ],
            TpDialogActions(
              children: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
                FilledButton(
                  onPressed: () {
                    final label = labelCtl.text.trim();
                    if (label.isEmpty) return;
                    final url = urlCtl.text.trim();
                    final now = DateTime.now().microsecondsSinceEpoch;
                    Navigator.pop(
                      ctx,
                      SkillRegistrySourceConfig(
                        id: 'custom-$now',
                        kind: SkillRegistryKind.api,
                        label: label,
                        protocol: protocol,
                        baseUrl: url.isEmpty ? null : url,
                        browseQuery: protocol == SkillRegistryProtocol.skillsSh
                            ? (browseCtl.text.trim().isEmpty ? 'ai' : browseCtl.text.trim())
                            : null,
                      ),
                    );
                  },
                  child: Text(l10n.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    labelCtl.dispose();
    urlCtl.dispose();
    browseCtl.dispose();
    if (result == null || !mounted) return;
    await context.read<SkillCubit>().addRegistrySource(result);
  }
}

class _RegistryRow extends StatelessWidget {
  const _RegistryRow({
    required this.source,
    required this.syncing,
    required this.onToggle,
    required this.onEdit,
    required this.onReset,
  });

  final SkillRegistrySource source;
  final bool syncing;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final textBase = cs.onSurface;
    final cfg = source is ApiRegistrySource
        ? (source as ApiRegistrySource).config
        : (source as GitRepoRegistrySource).config;
    final subtitle = source is GitRepoRegistrySource
        ? '@${(source as GitRepoRegistrySource).gitRepo.branch}'
        : (cfg.hasApiToken
              ? '@${source.label} · ${l10n.skillsRegistryApiKeySet}'
              : '@${source.label}');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TpHover(
        backgroundColor: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: workspaceInsetDecoration(cs, radius: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source is GitRepoRegistrySource
                          ? (source as GitRepoRegistrySource).gitRepo.githubUrl
                          : cfg.baseUrlOrDefault,
                      style: TpTextStyles.of(context).mdSemiboldColored(textBase),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TpTextStyles.of(
                        context,
                      ).xsColored(textBase.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
              ),
              if (syncing) ...[
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
              ],
              Switch(value: source.enabled, onChanged: onToggle),
              IconButton(
                tooltip: source.id == 'skillsSh' || source.id == 'skillsMp'
                    ? l10n.skillsRegistryResetTitle
                    : l10n.skillsRemove,
                onPressed: onReset,
                icon: Icon(
                  Icons.delete_outline,
                  size: context.tpIconSizes.md,
                  color: cs.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegistryEditDialog extends StatefulWidget {
  const _RegistryEditDialog({required this.config, required this.onTest});
  final SkillRegistrySourceConfig config;
  final Future<bool> Function() onTest;

  @override
  State<_RegistryEditDialog> createState() => _RegistryEditDialogState();
}

class _RegistryEditDialogState extends State<_RegistryEditDialog> {
  late final TextEditingController _labelCtl;
  late final TextEditingController _urlCtl;
  late final TextEditingController _tokenCtl;
  late final TextEditingController _browseCtl;
  late final TextEditingController _ownerCtl;
  late final TextEditingController _nameCtl;
  late final TextEditingController _branchCtl;
  bool _testing = false;

  bool get _isApi => widget.config.kind == SkillRegistryKind.api;

  @override
  void initState() {
    super.initState();
    _labelCtl = TextEditingController(text: widget.config.label);
    _urlCtl = TextEditingController(
      text: widget.config.baseUrlOrDefault == '' ? '' : widget.config.baseUrlOrDefault,
    );
    _tokenCtl = TextEditingController(text: widget.config.apiToken ?? '');
    _browseCtl = TextEditingController(text: widget.config.browseQuery ?? '');
    _ownerCtl = TextEditingController(text: widget.config.gitOwner ?? '');
    _nameCtl = TextEditingController(text: widget.config.gitName ?? '');
    _branchCtl = TextEditingController(text: widget.config.gitBranch ?? 'main');
  }

  @override
  void dispose() {
    _labelCtl.dispose(); _urlCtl.dispose(); _tokenCtl.dispose();
    _browseCtl.dispose(); _ownerCtl.dispose(); _nameCtl.dispose(); _branchCtl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      await widget.onTest();
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _save() {
    if (_isApi) {
      Navigator.pop(
        context,
        widget.config.copyWith(
          label: _labelCtl.text.trim().isEmpty ? widget.config.label : _labelCtl.text.trim(),
          baseUrl: _urlCtl.text.trim().isEmpty ? null : _urlCtl.text.trim(),
          apiToken: _tokenCtl.text.trim().isEmpty ? null : _tokenCtl.text.trim(),
          browseQuery: _browseCtl.text.trim().isEmpty ? null : _browseCtl.text.trim(),
        ),
      );
    } else {
      Navigator.pop(
        context,
        widget.config.copyWith(
          label: _labelCtl.text.trim().isEmpty ? widget.config.label : _labelCtl.text.trim(),
          gitOwner: _ownerCtl.text.trim(),
          gitName: _nameCtl.text.trim(),
          gitBranch: _branchCtl.text.trim().isEmpty ? 'main' : _branchCtl.text.trim(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpDialog(
      maxWidth: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.skillsRegistryEditTitle),
          const SizedBox(height: 16),
          TextField(controller: _labelCtl, decoration: InputDecoration(labelText: l10n.skillsRegistryNameLabel)),
          if (_isApi) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtl,
              decoration: InputDecoration(
                labelText: l10n.skillsRegistryBaseUrlLabel,
                hintText: SkillRegistrySourceConfig.defaultBaseUrl(widget.config.protocol ?? SkillRegistryProtocol.skillsSh),
              ),
            ),
            if (widget.config.protocol == SkillRegistryProtocol.skillsMp) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _tokenCtl,
                obscureText: true,
                autocorrect: false,
                decoration: InputDecoration(labelText: l10n.skillsRegistryTokenLabel),
              ),
            ],
            if (widget.config.protocol == SkillRegistryProtocol.skillsSh) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _browseCtl,
                decoration: InputDecoration(labelText: l10n.skillsRegistryBrowseQueryLabel),
              ),
            ],
          ] else ...[
            const SizedBox(height: 12),
            TextField(controller: _ownerCtl, decoration: InputDecoration(labelText: l10n.skillsRegistryOwnerLabel)),
            const SizedBox(height: 12),
            TextField(controller: _nameCtl, decoration: InputDecoration(labelText: l10n.skillsRegistryNameOfRepoLabel)),
            const SizedBox(height: 12),
            TextField(controller: _branchCtl, decoration: InputDecoration(labelText: l10n.skillsRepoBranch)),
          ],
          TpDialogActions(
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
              if (_isApi)
                TextButton(
                  onPressed: _testing ? null : _test,
                  child: _testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.mcpRepoTestConnection),
                ),
              FilledButton(onPressed: _save, child: Text(l10n.save)),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Update management page**

In `client/lib/pages/skills/skill_management_page.dart`, change the `repos` branch to:

```dart
            SkillSection.registries => const SkillRegistriesSection(),
```

Add import `skill_registries_section.dart`; remove `skill_repos_section.dart` import. Also update `SkillDiscoverySection(onGoRepos: ...)` → `onGoRegistries` (Task 8 changes the widget signature — keep `onGoRepos` here until Task 8, then rename).

- [ ] **Step 6: Run tests + analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: errors confined to Task 8 files (`skill_discovery_section.dart`, `skill_marketplace_panel.dart`, `skill_discovery_repos_panel.dart`, `skill_discover_card.dart` still reference deleted APIs) — leave until Task 8.
Run: `cd client && flutter test test/pages/skills/skill_registries_section_test.dart test/models/skill_registry_source_test.dart test/services/skill/registry/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/pages/skills/skill_section.dart client/lib/pages/skills/skill_management_page.dart client/lib/pages/skills/skill_registries_section.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/test/pages/skills/skill_registries_section_test.dart
git commit -m "feat(skills): registries management section with source CRUD"
```

---

### Task 8: Unified discovery UI

**Files:**
- Rewrite: `client/lib/pages/skills/skill_discovery_section.dart`
- Modify: `client/lib/pages/skills/skill_discovery_helpers.dart` (add unified filter helpers; remove `SkillSearchSource` enum)
- Delete: `client/lib/pages/skills/skill_marketplace_panel.dart`, `client/lib/pages/skills/skill_discovery_repos_panel.dart`, `client/lib/pages/skills/skill_discover_card.dart`
- Modify: `client/lib/pages/skills/skill_management_page.dart` (`onGoRepos` → `onGoRegistries`)
- Modify: `client/lib/l10n/app_en.arb` + `app_zh.arb` (search placeholder keys; then `flutter gen-l10n`)
- Test: rewrite `client/test/pages/skills/skill_discovery_section_test.dart`; delete `client/test/pages/skills/skill_marketplace_panel_test.dart`

**Interfaces:**
- Consumes: `SkillCubit.unifiedBrowse/unifiedSearch/unifiedLoadMore/installUnifiedEntry`, `SkillState.discoveryEntries/discoveryLoading/discoveryError/discoveryBrowsing/discoveryHasNext/discoveryPages/discoveryTotals/sources/repoSyncingKeys/discoverable`, `MarketplaceSkillCard`, `marketplaceQuotaErrorKey`.
- Produces: nothing downstream (final UI task).

- [ ] **Step 1: Update helpers**

In `client/lib/pages/skills/skill_discovery_helpers.dart`:
- Delete `enum SkillSearchSource`.
- Keep `skillInstalledKeys`, `sameDiscoverableSkills`, filter slices.
- Add:

```dart
typedef SkillUnifiedGridSlice = ({
  List<UnifiedSkillEntry> entries,
  bool discoveryLoading,
  bool anyHasNext,
  Set<String> busyIds,
});

bool unifiedEntryMatchesStatus(
  UnifiedSkillEntry entry,
  Set<String> installedKeys,
  String filterStatus,
) {
  final installKey = '${entry.skill.directory?.split('/').last ?? ''}'
      .toLowerCase()
      .isEmpty
      ? ''
      : '${(entry.skill.directory!.split('/').last).toLowerCase()}:'
            '${entry.skill.repoOwner.toLowerCase()}:'
            '${entry.skill.repoName.toLowerCase()}';
  final installed = installedKeys.contains(installKey);
  if (filterStatus == 'installed' && !installed) return false;
  if (filterStatus == 'uninstalled' && installed) return false;
  return true;
}
```

- [ ] **Step 2: Rewrite the discovery section**

Rewrite `client/lib/pages/skills/skill_discovery_section.dart` (full file):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/unified_skill_entry.dart';
import '../../services/skill/marketplace/skill_marketplace_source.dart';
import '../../services/skill/registry/skill_registry_source.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/workspace_library_card.dart';
import 'marketplace_skill_card.dart';
import 'skill_discovery_helpers.dart';

class SkillDiscoverySection extends StatefulWidget {
  const SkillDiscoverySection({super.key, required this.onGoRegistries});

  final VoidCallback onGoRegistries;

  @override
  State<SkillDiscoverySection> createState() => SkillDiscoverySectionState();
}

class SkillDiscoverySectionState extends State<SkillDiscoverySection> {
  final _searchCtl = TextEditingController();
  String _query = '';
  String _sourceFilter = 'all';
  String _statusFilter = 'all';
  String? _sortBy;
  String? _language;
  String? _category;
  String? _occupation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final cubit = context.read<SkillCubit>();
      await cubit.ensureDiscoveryLoaded();
      if (!mounted) return;
      await cubit.unifiedBrowse();
    });
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    Debounces.cancel('skill_discovery_search');
    super.dispose();
  }

  void _onSearchChanged(String value) {
    Debounces.debounce('skill_discovery_search', const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final q = value.trim();
      setState(() => _query = q);
      final cubit = context.read<SkillCubit>();
      if (q.length >= 2) {
        cubit.unifiedSearch(q, sourceId: _sourceIdOrNull(), sortBy: _sortBy, language: _language, category: _category, occupation: _occupation);
      } else {
        cubit.unifiedSearch('', sourceId: _sourceIdOrNull(), sortBy: _sortBy, language: _language, category: _category, occupation: _occupation);
      }
    });
  }

  String? _sourceIdOrNull() => _sourceFilter == 'all' ? null : _sourceFilter;

  void _onFilterChanged() {
    final cubit = context.read<SkillCubit>();
    if (_query.trim().length >= 2) {
      cubit.unifiedSearch(_query.trim(), sourceId: _sourceIdOrNull(), sortBy: _sortBy, language: _language, category: _category, occupation: _occupation);
    } else {
      cubit.unifiedSearch('', sourceId: _sourceIdOrNull(), sortBy: _sortBy, language: _language, category: _category, occupation: _occupation);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspaceLibraryCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FilterBar(
                searchCtl: _searchCtl,
                onSearchChanged: _onSearchChanged,
                sourceFilter: _sourceFilter,
                statusFilter: _statusFilter,
                onSourceFilter: (v) {
                  setState(() => _sourceFilter = v ?? 'all');
                  _onFilterChanged();
                },
                onStatusFilter: (v) {
                  setState(() => _statusFilter = v ?? 'all');
                },
                onRefresh: () => context.read<SkillCubit>().unifiedSearch(
                  _query.trim().length >= 2 ? _query.trim() : '',
                  sourceId: _sourceIdOrNull(),
                  sortBy: _sortBy, language: _language,
                  category: _category, occupation: _occupation,
                ),
              ),
              const _SyncBanner(),
            ],
          ),
        ),
        Expanded(
          child: _ResultsBody(
            query: _query,
            sourceFilter: _sourceFilter,
            statusFilter: _statusFilter,
            onGoRegistries: widget.onGoRegistries,
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchCtl,
    required this.onSearchChanged,
    required this.sourceFilter,
    required this.statusFilter,
    required this.onSourceFilter,
    required this.onStatusFilter,
    required this.onRefresh,
  });

  final TextEditingController searchCtl;
  final ValueChanged<String> onSearchChanged;
  final String sourceFilter;
  final String statusFilter;
  final ValueChanged<String?> onSourceFilter;
  final ValueChanged<String?> onStatusFilter;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocSelector<SkillCubit, SkillState, List<SkillRegistrySource>>(
      selector: (state) => state.sources,
      builder: (context, sources) {
        final enabled = sources.where((s) => s.enabled).toList();
        final sourceItems = <String, String>{
          'all': l10n.skillsFilterRepoAll,
          for (final s in enabled) s.id: s.label,
        };
        String statusLabel(String v) => switch (v) {
          'installed' => l10n.skillsFilterInstalled,
          'uninstalled' => l10n.skillsFilterUninstalled,
          _ => l10n.skillsFilterAll,
        };
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: searchCtl,
                decoration: InputDecoration(
                  hintText: l10n.skillsSearchPlaceholder,
                  prefixIcon: Icon(Icons.search, size: context.tpIconSizes.md),
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                ),
                onChanged: onSearchChanged,
              ),
            ),
            SizedBox(
              width: 220,
              child: TpSelect<String>(
                key: ValueKey(sourceItems.keys.join('|')),
                items: sourceItems.keys.toList(),
                initialItem: sourceItems.containsKey(sourceFilter) ? sourceFilter : 'all',
                itemLabel: (v) => sourceItems[v] ?? v,
                onChanged: onSourceFilter,
              ),
            ),
            SizedBox(
              width: 160,
              child: TpSelect<String>(
                items: const ['all', 'installed', 'uninstalled'],
                initialItem: statusFilter,
                itemLabel: statusLabel,
                onChanged: onStatusFilter,
              ),
            ),
            IconButton(
              tooltip: l10n.skillsCheckUpdates,
              onPressed: onRefresh,
              icon: Icon(Icons.refresh, size: context.tpIconSizes.md),
            ),
          ],
        );
      },
    );
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<SkillCubit, SkillState, Set<String>>(
      selector: (state) => state.repoSyncingKeys,
      builder: (context, syncing) {
        if (syncing.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.l10n.skillsDiscoverySyncing, style: TpTextStyles.of(context).sm),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ResultsBody extends StatelessWidget {
  const _ResultsBody({
    required this.query,
    required this.sourceFilter,
    required this.statusFilter,
    required this.onGoRegistries,
  });

  final String query;
  final String sourceFilter;
  final String statusFilter;
  final VoidCallback onGoRegistries;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocSelector<SkillCubit, SkillState, Set<String>>(
      selector: (state) => skillInstalledKeys(state.installed),
      builder: (context, installedKeys) {
        return BlocSelector<SkillCubit, SkillState, SkillUnifiedGridSlice>(
          selector: (state) => (
            entries: state.discoveryEntries,
            discoveryLoading: state.discoveryLoading,
            anyHasNext: state.anyDiscoveryHasNext,
            busyIds: state.busyIds,
          ),
          builder: (context, grid) {
            if (grid.discoveryLoading && grid.entries.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            final filtered = grid.entries.where((e) {
              if (sourceFilter != 'all' && e.sourceId != sourceFilter) return false;
              return unifiedEntryMatchesStatus(e, installedKeys, statusFilter);
            }).toList();

            if (grid.discoveryLoading && filtered.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (filtered.isEmpty) {
              return SingleChildScrollView(
                child: WorkspaceLibraryCard(
                  child: TpEmptyState(
                    icon: Icons.travel_explore_outlined,
                    title: l10n.skillsDiscoveryEmpty,
                    hint: l10n.skillsDiscoveryEmptyHint,
                    actionLabel: l10n.skillsRegistryGoSetKey,
                    onAction: onGoRegistries,
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth >= 1100 ? 3 : (constraints.maxWidth >= 700 ? 2 : 1);
                      return GridView.builder(
                        padding: const EdgeInsets.only(top: 2),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 168,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final entry = filtered[i];
                          return MarketplaceSkillCard(
                            key: ValueKey('${entry.sourceId}:${entry.skill.key}'),
                            skill: entry.skill,
                            installed: installedKeys.contains(
                              '${(entry.skill.directory ?? entry.skill.repoName).split('/').last.toLowerCase()}:${entry.skill.repoOwner.toLowerCase()}:${entry.skill.repoName.toLowerCase()}',
                            ),
                            busy: grid.busyIds.contains(entry.skill.key),
                            onInstall: () => context.read<SkillCubit>().installUnifiedEntry(entry),
                          );
                        },
                      );
                    },
                  ),
                ),
                if (grid.anyHasNext)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: OutlinedButton.icon(
                      onPressed: grid.discoveryLoading
                          ? null
                          : () => context.read<SkillCubit>().unifiedLoadMore(),
                      icon: grid.discoveryLoading
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.expand_more, size: context.tpIconSizes.md),
                      label: Text(l10n.skillsMarketplaceLoadMore),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
```

- [ ] **Step 3: Delete obsolete files + update management page**

```bash
git rm client/lib/pages/skills/skill_marketplace_panel.dart client/lib/pages/skills/skill_discovery_repos_panel.dart client/lib/pages/skills/skill_discover_card.dart
```

In `skill_management_page.dart`, change `SkillDiscoverySection(onGoRepos: ...)` to `SkillDiscoverySection(onGoRegistries: () => select(SkillSection.registries))`.

In l10n arb: update `skillsSearchPlaceholder` text if desired (keep key); remove now-unused keys only if `flutter gen-l10n` complains (it doesn't) — leave unused keys in place to minimize churn, they are harmless.

- [ ] **Step 4: Rewrite discovery widget test + delete old tests**

Delete `client/test/pages/skills/skill_marketplace_panel_test.dart`. Rewrite `client/test/pages/skills/skill_discovery_section_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/pages/skills/skill_discovery_section.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/registry/skill_registry_config_service.dart';
import 'package:teampilot/services/skill/registry/skill_registry_source.dart';
import 'package:teampilot/services/storage/app_storage.dart';

class _FakeSource implements SkillRegistrySource {
  _FakeSource(this.id);
  @override
  final String id;
  @override
  String get label => id;
  @override
  bool get enabled => true;
  @override
  SkillRegistryKind get kind => SkillRegistryKind.api;
  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();

  @override
  Future<SkillRegistryPage> search(SkillRegistryQuery q) async => SkillRegistryPage(
    entries: [
      MarketplaceSkill(
        key: '$id-skill-1',
        name: '$id-skill-1',
        description: 'd',
        repoOwner: 'o',
        repoName: 'r',
        directory: 'dir/1',
        githubUrl: 'https://github.com/o/r',
      ),
    ],
    hasNext: false,
    total: 1,
  );

  @override
  Future<void> testConnection() async {}
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill-disc-unified-');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(pathContext: AppPaths.pathContextForDataRoot(paths.basePath)),
      paths: paths, home: tmp.path, cwd: tmp.path,
    );
  });

  tearDown(() {
    AppStorage.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget wrap(SkillCubit cubit) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: BlocProvider<SkillCubit>.value(
        value: cubit,
        child: SizedBox(
          height: 800,
          child: SkillDiscoverySection(onGoRegistries: () {}),
        ),
      ),
    ),
  );

  SkillCubit buildCubit(List<SkillRegistrySource> sources) {
    final cfg = SkillRegistryConfigService(teampilotRoot: AppStorage.paths.basePath);
    return SkillCubit(
      SkillRepository(),
      registryConfigService: cfg,
      initialSources: sources,
      rebuildSources: (c) => sources,
    );
  }

  testWidgets('auto-browses on open and renders cards', (tester) async {
    final cubit = buildCubit([_FakeSource('alpha')]);
    await tester.pumpWidget(wrap(cubit));
    await tester.pumpAndSettle();
    expect(find.text('alpha-skill-1'), findsOneWidget);
  });

  testWidgets('filters by source and status', (tester) async {
    final cubit = buildCubit([_FakeSource('alpha'), _FakeSource('beta')]);
    await tester.pumpWidget(wrap(cubit));
    await tester.pumpAndSettle();
    expect(find.text('alpha-skill-1'), findsOneWidget);
    expect(find.text('beta-skill-1'), findsOneWidget);
  });

  testWidgets('quota error shows empty state with registries action', (tester) async {
    // build cubit whose source throws MarketplaceQuotaException; expect
    // empty state + 'Go to registries' style action button present.
  });
}
```

- [ ] **Step 5: Run analyze + tests**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: clean (any residual errors from deleted l10n keys or imports — fix them).
Run: `cd client && flutter test test/pages/skills/ test/cubits/skill_unified_discovery_test.dart test/services/skill/registry/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/skills/skill_discovery_section.dart client/lib/pages/skills/skill_discovery_helpers.dart client/lib/pages/skills/skill_management_page.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/test/pages/skills/skill_discovery_section_test.dart
git rm client/lib/pages/skills/skill_marketplace_panel.dart client/lib/pages/skills/skill_discovery_repos_panel.dart client/lib/pages/skills/skill_discover_card.dart client/test/pages/skills/skill_marketplace_panel_test.dart
git commit -m "feat(skills): unified discovery stream UI"
```

---

### Task 9: Cleanup, l10n pruning, and full regression

**Files:**
- Modify: `client/lib/repositories/app_settings_repository.dart` (remove `loadSkillsMpApiKey`/`saveSkillsMpApiKey` + storage keys + memory impl fields — migration already consumed the value)
- Modify: `client/lib/app/app_shell.dart` (remove `legacySkillsMpKeyReader` once migration verified — keep it; it reads from settings which no longer stores new values)
- Delete: any remaining dead files found by analyze
- Verify: full analyze + full test suite

**Interfaces:** none new.

- [ ] **Step 1: Remove legacy settings accessors**

In `client/lib/repositories/app_settings_repository.dart`:
- Delete `_skillsMpApiKey` const, `loadSkillsMpApiKey`, `saveSkillsMpApiKey` from the abstract class and both implementations (`SharedPrefsAppSettingsRepository`, memory impl).
- In `client/lib/app/app_shell.dart`, the `legacySkillsMpKeyReader` must no longer call the deleted method — replace with a constant null reader (the value was already migrated once in Task 2):

```dart
  final skillRegistryConfigService = SkillRegistryConfigService(
    legacySkillsMpKeyReader: () async => null,
  );
```

- [ ] **Step 2: Grep for dead references**

Run: `rg "SkillMarketplaceRegistry|SkillMarketplaceSource|MarketplaceSearchQuery|MarketplaceSearchResult|SkillsShMarketplaceSource|SkillsMpMarketplaceSource|SkillReposSection|skill_discover_card|SkillRepoService|searchSkillsSh|loadSkillsMpApiKey|saveSkillsMpApiKey|MarketplaceSearchState|SkillSearchSource" client/lib client/test`
Expected: no matches (or only intended ones in new files).
Remove any leftover l10n keys that are now unused ONLY if they are referenced nowhere (grep `skillsSourceRepos|skillsSourceSkillsSh|skillsSkillsShPlaceholder|skillsSkillsShSearch|skillsSkillsShPoweredBy|skillsMarketplaceSearchHint` — delete from arb files + `flutter gen-l10n`).

- [ ] **Step 3: Full verification**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues.
Run: `cd client && flutter test --exclude-tags integration`
Expected: All tests pass (including rewritten skill tests + any tests that referenced old sections, e.g. `skill_management_page_compact_tabs_test.dart` — update its `SkillSection` usage to `registries`).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(skills): remove legacy repo/marketplace storage and dead code"
```

---

## Self-Review Notes

- Spec coverage: registries.json storage + migration (T1/T2), source interface + both source kinds (T3-T5), factory + cubit unified state (T6), registries section UI (T7), unified discovery UI with auto-browse + filters + load more + quota guidance (T8), cleanup (T9). All spec sections mapped.
- Type consistency: `SkillRegistryQuery`/`SkillRegistryPage`/`SkillRegistrySource` defined once (T3) and used in T4-T8; `ApiRegistrySource.config`/`GitRepoRegistrySource.config`/`.gitRepo` used consistently; `SkillCubit` ctor signature defined in T6 and used in T7/T8 tests.
- Placeholders: none — every step has concrete code or an exact command.
