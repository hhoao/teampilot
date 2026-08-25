# Skills/Plugins/MCP 发现与市场刷新策略 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 skills/plugins/mcp 三个发现页默认只在手动刷新时检查远端；「自动刷新」成为设置项（默认关，开启后按 24h TTL 检查）。

**Architecture:** 新增全局 `DiscoverySettingsCubit`（SharedPreferences 持久化）+ 常量 `kDiscoveryAutoRefreshTtl = 24h`。TTL 下沉到缓存服务层：`SkillRepoDiskCacheService.ensureSynced` / `PluginRepoDiskCacheService.syncMarketplace` 新增可选 `maxStaleness` 参数（缓存年龄在 TTL 内直接返回磁盘缓存、零网络）。三个发现 cubit 只做策略判断：默认手动（仅首次无缓存时初始化拉取一次），开启后按 TTL 检查。设置页新增「发现与市场」分组承载开关。

**Tech Stack:** Flutter (flutter_bloc), SharedPreferences, l10n (app_en.arb / app_zh.arb + `flutter gen-l10n`)。

## Global Constraints

- 默认行为：自动刷新 = 关。打开发现页只显示磁盘缓存、零网络请求；无缓存（首次）仍自动拉取一次。
- 自动刷新开启时：缓存年龄 < 24h 不检查远端；≥ 24h 才检查远端 commit SHA 并更新。
- 手动刷新按钮（`force: true`）不受 TTL 限制，总是强制检查。
- 一个全局开关同时控制 skills / plugins / mcp 三个发现页。
- 开关持久化键：`discoveryAutoRefresh`（SharedPreferences `teampilot.app_settings.v1`），默认 `false`。
- 设置 UI：新增「发现与市场」分组，位置在 Download Sources 之后、Shortcuts 之前（settings 弹窗 + `/config/discovery` 路由 + Android hub 三处同步注册）。
- 测试命令：`cd client && flutter test <file>`；最后全量 `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`。
- 不新增依赖；不动 TeamHub/ExpertHub；TTL 固定 24h 不做可配置。

---

### Task 1: 持久化 + 策略常量 + DiscoverySettingsCubit

**Files:**
- Modify: `client/lib/repositories/app_settings_repository.dart`
- Create: `client/lib/services/discovery/discovery_refresh_policy.dart`
- Create: `client/lib/cubits/discovery_settings_cubit.dart`
- Test: `client/test/repositories/app_settings_repository_test.dart`
- Create: `client/test/cubits/discovery_settings_cubit_test.dart`

**Interfaces:**
- Produces: `AppSettingsRepository.loadDiscoveryAutoRefreshEnabled() → Future<bool>`（默认 false）、`saveDiscoveryAutoRefreshEnabled(bool)`；`InMemoryAppSettingsRepository(discoveryAutoRefreshEnabled: bool = false)` 构造参数；`const kDiscoveryAutoRefreshTtl = Duration(hours: 24)`；`DiscoverySettingsCubit({required AppSettingsRepository repository})`，`state.autoRefreshEnabled`（默认 false），`load()`、`setAutoRefreshEnabled(bool)`。

- [ ] **Step 1: 写失败的测试 — AppSettingsRepository 新键**

在 `client/test/repositories/app_settings_repository_test.dart` 末尾（`test('SharedPrefs persists key in the settings map'...` 之后）追加：

```dart
  group('AppSettingsRepository.discoveryAutoRefresh', () {
    test('defaults to disabled (opt-in) when nothing stored', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      expect(await repo.loadDiscoveryAutoRefreshEnabled(), isFalse);
    });

    test('round-trips enabled flag', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      await repo.saveDiscoveryAutoRefreshEnabled(true);
      expect(await repo.loadDiscoveryAutoRefreshEnabled(), isTrue);

      await repo.saveDiscoveryAutoRefreshEnabled(false);
      expect(await repo.loadDiscoveryAutoRefreshEnabled(), isFalse);
    });
  });

  test('InMemory discoveryAutoRefresh round trip and seed', () async {
    final repo = InMemoryAppSettingsRepository();
    expect(await repo.loadDiscoveryAutoRefreshEnabled(), isFalse);
    await repo.saveDiscoveryAutoRefreshEnabled(true);
    expect(await repo.loadDiscoveryAutoRefreshEnabled(), isTrue);

    final seeded = InMemoryAppSettingsRepository(
      discoveryAutoRefreshEnabled: true,
    );
    expect(await seeded.loadDiscoveryAutoRefreshEnabled(), isTrue);
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/repositories/app_settings_repository_test.dart`
Expected: 编译错误（`loadDiscoveryAutoRefreshEnabled` 未定义）。

- [ ] **Step 3: 实现 AppSettingsRepository 新键**

`app_settings_repository.dart` — 抽象类在 `saveAiFeatureSetting` 声明后追加：

```dart
  /// Whether skills/plugins/MCP discovery pages auto-refresh remote catalogs
  /// on open. Defaults to `false` (manual refresh only).
  Future<bool> loadDiscoveryAutoRefreshEnabled();
  Future<void> saveDiscoveryAutoRefreshEnabled(bool value);
```

`SharedPrefsAppSettingsRepository`：`static const _discoveryAutoRefreshKey = 'discoveryAutoRefresh';`（`_aiFeaturesKey` 声明旁），并在 `saveAiFeatureSetting` 之后追加实现：

```dart
  @override
  Future<bool> loadDiscoveryAutoRefreshEnabled() async {
    final value = _readMap()[_discoveryAutoRefreshKey];
    // Opt-in: disabled unless explicitly turned on.
    return value == true;
  }

  @override
  Future<void> saveDiscoveryAutoRefreshEnabled(bool value) async {
    final current = _readMap();
    current[_discoveryAutoRefreshKey] = value;
    await _writeMap(current);
  }
```

`InMemoryAppSettingsRepository`：构造函数加命名参数 `bool discoveryAutoRefreshEnabled = false`（放在 `skillsMpApiKey` 参数后），初始化列表加 `_discoveryAutoRefreshEnabled = discoveryAutoRefreshEnabled`，加字段 `bool _discoveryAutoRefreshEnabled;`，在 `saveSkillsMpApiKey` 实现后追加：

```dart
  @override
  Future<bool> loadDiscoveryAutoRefreshEnabled() async =>
      _discoveryAutoRefreshEnabled;

  @override
  Future<void> saveDiscoveryAutoRefreshEnabled(bool value) async {
    _discoveryAutoRefreshEnabled = value;
  }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter test test/repositories/app_settings_repository_test.dart`
Expected: 全部 PASS（含新 3 个测试）。

- [ ] **Step 5: 创建策略常量**

创建 `client/lib/services/discovery/discovery_refresh_policy.dart`：

```dart
/// Refresh policy for skills/plugins/MCP discovery catalogs.
///
/// Auto-refresh is opt-in (see `AppSettingsRepository.discoveryAutoRefresh`);
/// when enabled, remote catalogs are only checked on page open when the disk
/// cache is older than [kDiscoveryAutoRefreshTtl]. Manual refresh (force)
/// always bypasses the TTL.
const kDiscoveryAutoRefreshTtl = Duration(hours: 24);
```

- [ ] **Step 6: 创建 DiscoverySettingsCubit + 测试**

创建 `client/lib/cubits/discovery_settings_cubit.dart`（模式参考 `ai_feature_settings_cubit.dart`）：

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../repositories/app_settings_repository.dart';

class DiscoverySettingsState extends Equatable {
  const DiscoverySettingsState({this.autoRefreshEnabled = false});

  final bool autoRefreshEnabled;

  DiscoverySettingsState copyWith({bool? autoRefreshEnabled}) =>
      DiscoverySettingsState(
        autoRefreshEnabled: autoRefreshEnabled ?? this.autoRefreshEnabled,
      );

  @override
  List<Object?> get props => [autoRefreshEnabled];
}

class DiscoverySettingsCubit extends Cubit<DiscoverySettingsState> {
  DiscoverySettingsCubit({required AppSettingsRepository repository})
    : _repository = repository,
      super(const DiscoverySettingsState());

  final AppSettingsRepository _repository;

  Future<void> load() async {
    final enabled = await _repository.loadDiscoveryAutoRefreshEnabled();
    emit(state.copyWith(autoRefreshEnabled: enabled));
  }

  Future<void> setAutoRefreshEnabled(bool value) async {
    emit(state.copyWith(autoRefreshEnabled: value));
    await _repository.saveDiscoveryAutoRefreshEnabled(value);
  }
}
```

创建 `client/test/cubits/discovery_settings_cubit_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/discovery_settings_cubit.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';

void main() {
  test('default state has autoRefresh disabled', () {
    final cubit = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    expect(cubit.state.autoRefreshEnabled, isFalse);
  });

  test('load() reads repository value', () async {
    final cubit = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(
        discoveryAutoRefreshEnabled: true,
      ),
    );
    await cubit.load();
    expect(cubit.state.autoRefreshEnabled, isTrue);
  });

  test('setAutoRefreshEnabled persists and updates state', () async {
    final repo = InMemoryAppSettingsRepository();
    final cubit = DiscoverySettingsCubit(repository: repo);
    await cubit.setAutoRefreshEnabled(true);
    expect(cubit.state.autoRefreshEnabled, isTrue);
    expect(await repo.loadDiscoveryAutoRefreshEnabled(), isTrue);
  });
}
```

- [ ] **Step 7: 运行测试确认通过**

Run: `cd client && flutter test test/cubits/discovery_settings_cubit_test.dart test/repositories/app_settings_repository_test.dart`
Expected: 全部 PASS。

- [ ] **Step 8: Commit**

```bash
git add client/lib/repositories/app_settings_repository.dart \
  client/lib/services/discovery/discovery_refresh_policy.dart \
  client/lib/cubits/discovery_settings_cubit.dart \
  client/test/repositories/app_settings_repository_test.dart \
  client/test/cubits/discovery_settings_cubit_test.dart
git commit -m "feat: discovery auto-refresh setting (default off) + TTL policy constant"
```

---

### Task 2: SkillRepoDiskCacheService.ensureSynced 支持 maxStaleness（+ SkillRepository 透传）

**Files:**
- Modify: `client/lib/services/skill/skill_repo_disk_cache_service.dart`
- Modify: `client/lib/repositories/skill_repository.dart`
- Test: `client/test/services/skill/skill_repo_disk_cache_service_test.dart`

**Interfaces:**
- Consumes: `kDiscoveryAutoRefreshTtl`（Task 1）
- Produces: `SkillRepoDiskCacheService.ensureSynced(SkillRepo repo, {bool force = false, List<String> requiredRelativePaths = const [], Duration? maxStaleness})`；`SkillRepository.syncRepoCache(SkillRepo repo, {bool force = false, Duration? maxStaleness})`；`SkillRepository.hasCachedSnapshot(SkillRepo repo) → Future<bool>`（meta.json 存在即 true）。

- [ ] **Step 1: 写失败的测试**

`client/test/services/skill/skill_repo_disk_cache_service_test.dart`：
- `_CountingFetch` 加计数器（`fetchBranchCommitSha` 里 `shaChecks++`）：

```dart
class _CountingFetch extends SkillFetchService {
  int downloads = 0;
  int shaChecks = 0;
  String? remoteSha;
  String commitShaOnDownload = 'abc123';

  @override
  Future<String?> fetchBranchCommitSha(
    String owner,
    String name,
    String branch,
  ) async {
    shaChecks++;
    return remoteSha;
  }
  // ...downloadRepoEntries 保持原样
}
```

- `main()` 末尾（`missing requiredRelativePaths forces download` 测试后）追加：

```dart
  test('maxStaleness skips network when cache is fresh', () async {
    final fs = AppStorage.fs;
    await _plantSnapshot(commitSha: 'deadbeef');
    final metaPath = fs.pathContext.join(
      AppStorage.paths.skillRepoCacheDir,
      SkillRepoDiskCacheService.repoKey(_repo),
      'meta.json',
    );
    final meta = SkillRepoCacheMeta(
      configuredBranch: 'main',
      resolvedBranch: 'main',
      commitSha: 'deadbeef',
      syncedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await fs.writeString(
      metaPath,
      const JsonEncoder.withIndent('  ').convert(meta.toJson()),
    );

    final fetch = _CountingFetch()..remoteSha = 'deadbeef';
    final cache = SkillRepoDiskCacheService(fetch: fetch);

    final result = await cache.ensureSynced(
      _repo,
      maxStaleness: const Duration(hours: 24),
    );

    expect(fetch.downloads, 0);
    expect(fetch.shaChecks, 0);
    expect(result.updated, isFalse);
    expect(result.skills, isNotEmpty);
  });

  test('maxStaleness still checks remote when cache is stale', () async {
    await _plantSnapshot(commitSha: 'deadbeef');
    final fetch = _CountingFetch()..remoteSha = 'deadbeef';
    final cache = SkillRepoDiskCacheService(fetch: fetch);

    final result = await cache.ensureSynced(
      _repo,
      maxStaleness: const Duration(hours: 24),
    );

    expect(fetch.shaChecks, 1);
    expect(fetch.downloads, 0);
    expect(result.updated, isFalse);
  });
```

（`_plantSnapshot` 已写 `syncedAtMs: 1`，即 1970 年 → 过期。）

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/services/skill/skill_repo_disk_cache_service_test.dart`
Expected: 编译错误（`maxStaleness` 参数不存在）。

- [ ] **Step 3: 实现 maxStaleness**

`skill_repo_disk_cache_service.dart`：

```dart
  Future<SkillRepoSyncResult> ensureSynced(
    SkillRepo repo, {
    bool force = false,
    List<String> requiredRelativePaths = const [],
    Duration? maxStaleness,
  }) {
    final key = RepoDiskSyncCoalescer.syncKey(_cacheRoot, repoKey(repo));
    return _coalescer.run(
      key,
      () => _ensureSyncedOnce(
        repo,
        force: force,
        requiredRelativePaths: requiredRelativePaths,
        maxStaleness: maxStaleness,
      ),
    );
  }

  Future<SkillRepoSyncResult> _ensureSyncedOnce(
    SkillRepo repo, {
    required bool force,
    required List<String> requiredRelativePaths,
    Duration? maxStaleness,
  }) async {
```

在 `_ensureSyncedOnce` 中 `final trusted = ...;` 之后、`if (!force && trusted) {` 之前插入：

```dart
    if (maxStaleness != null && trusted) {
      final age = DateTime.now().millisecondsSinceEpoch - meta!.syncedAtMs;
      if (age >= 0 && age < maxStaleness.inMilliseconds) {
        return SkillRepoSyncResult(
          skills: await readSkillsFromDisk(repo),
          updated: false,
          repoKey: key,
        );
      }
    }
```

（`trusted` 为 true 时 `meta` 非空，`meta!` 安全；`requiredRelativePaths` 校验已含在 `_isTrustedSnapshot` 中。）

`skill_repository.dart`：

```dart
  Future<SkillRepoSyncResult> syncRepoCache(
    SkillRepo repo, {
    bool force = false,
    Duration? maxStaleness,
  }) => repoCache.ensureSynced(repo, force: force, maxStaleness: maxStaleness);

  /// True when the repo was synced to disk at least once (meta.json exists).
  Future<bool> hasCachedSnapshot(SkillRepo repo) async =>
      (await repoCache.readMeta(repo)) != null;
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter test test/services/skill/skill_repo_disk_cache_service_test.dart`
Expected: 全部 PASS（含新 2 个）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/skill/skill_repo_disk_cache_service.dart \
  client/lib/repositories/skill_repository.dart \
  client/test/services/skill/skill_repo_disk_cache_service_test.dart
git commit -m "feat: skill repo cache TTL (maxStaleness) fast path"
```

---

### Task 3: PluginRepoDiskCacheService.syncMarketplace 支持 maxStaleness + hasCachedSnapshot

**Files:**
- Modify: `client/lib/services/plugin/plugin_repo_disk_cache_service.dart`
- Test: `client/test/services/plugin/plugin_repo_disk_cache_service_test.dart`

**Interfaces:**
- Consumes: `kDiscoveryAutoRefreshTtl`（Task 1）
- Produces: `PluginRepoDiskCacheService.syncMarketplace(PluginMarketplace m, {bool force = false, Duration? maxStaleness})`；`PluginRepoDiskCacheService.hasCachedSnapshot(PluginMarketplace m) → Future<bool>`。

- [ ] **Step 1: 写失败的测试**

`client/test/services/plugin/plugin_repo_disk_cache_service_test.dart`：
- 顶部 import 加 `dart:convert`（已有 `dart:io`/`dart:typed_data`）。
- `_CountingPluginGit` 加计数器：

```dart
class _CountingPluginGit extends PluginRepoGitService {
  int syncCheckouts = 0;
  int resolveShaCalls = 0;

  // ...syncCheckout 保持原样

  @override
  Future<({String sha, String branch})?> resolveRemoteShaWithFallback(
    String owner,
    String name,
    String configuredBranch,
  ) async {
    resolveShaCalls++;
    return null;
  }
}
```

- 在 `group('coalesced syncMarketplace', ...)` 之后追加：

```dart
  group('maxStaleness TTL', () {
    setUp(setUpTestAppStorage);
    tearDown(tearDownTestAppStorage);

    test('fresh cache skips remote SHA check', () async {
      final git = _CountingPluginGit();
      const market = PluginMarketplace(owner: 'acme', name: 'mkt');
      final svc = PluginRepoDiskCacheService(gitService: git);

      await svc.syncMarketplace(market);

      final result = await svc.syncMarketplace(
        market,
        maxStaleness: const Duration(hours: 24),
      );

      expect(git.syncCheckouts, 1);
      expect(git.resolveShaCalls, 0);
      expect(result, isNotEmpty);
    });

    test('stale cache still checks remote SHA', () async {
      final git = _CountingPluginGit();
      const market = PluginMarketplace(owner: 'acme', name: 'mkt');
      final svc = PluginRepoDiskCacheService(gitService: git);
      final dir = await svc.syncMarketplace(market);
      final metaPath = AppStorage.fs.pathContext.join(
        dir,
        '.teampilot-plugin-cache-meta.json',
      );
      await AppStorage.fs.writeString(
        metaPath,
        jsonEncode({
          'configuredBranch': 'main',
          'resolvedBranch': 'main',
          'commitSha': 'abc123',
          'syncedAtMs': 1,
        }),
      );

      await svc.syncMarketplace(
        market,
        maxStaleness: const Duration(hours: 24),
      );

      expect(git.resolveShaCalls, 1);
      expect(git.syncCheckouts, 1);
    });
  });
```

（需 import：`package:teampilot/services/storage/app_storage.dart`。）

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/services/plugin/plugin_repo_disk_cache_service_test.dart`
Expected: 编译错误（`maxStaleness` 参数不存在）。

- [ ] **Step 3: 实现 maxStaleness + hasCachedSnapshot**

`plugin_repo_disk_cache_service.dart`：

```dart
  Future<String> syncMarketplace(
    PluginMarketplace m, {
    bool force = false,
    Duration? maxStaleness,
  }) async {
    final root = await _cacheRoot();
    final key = RepoDiskSyncCoalescer.syncKey(root, repoKey(m));
    return _coalescer.run(
      key,
      () => _syncMarketplaceOnce(m, force: force, maxStaleness: maxStaleness),
    );
  }

  Future<String> _syncMarketplaceOnce(
    PluginMarketplace m, {
    required bool force,
    Duration? maxStaleness,
  }) async {
```

在 `_syncMarketplaceOnce` 的 `if (!force && (await _fs.stat(dirPath)).exists) {` 内、`final remote = await _git.resolveRemoteShaWithFallback(...)` 之前插入：

```dart
        if (maxStaleness != null &&
            DateTime.now().millisecondsSinceEpoch - meta.syncedAtMs <
                maxStaleness.inMilliseconds) {
          appLogger.d(
            '[PluginRepoDiskCache] skipped ${m.fullName} (fresh within TTL)',
          );
          return dirPath;
        }
```

（`meta` 在该块内已判 `meta != null` 且 `configuredBranch` 匹配。）

在 `discoverablePluginsCached` 前追加：

```dart
  /// True when a cache meta exists on disk for [m] (synced at least once).
  Future<bool> hasCachedSnapshot(PluginMarketplace m) async {
    final dirPath = await _repoDirPath(m);
    if (!(await _fs.stat(dirPath)).exists) return false;
    return (await _readMeta(dirPath)) != null;
  }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter test test/services/plugin/plugin_repo_disk_cache_service_test.dart`
Expected: 全部 PASS（含新 2 个）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/plugin/plugin_repo_disk_cache_service.dart \
  client/test/services/plugin/plugin_repo_disk_cache_service_test.dart
git commit -m "feat: plugin marketplace cache TTL (maxStaleness) fast path"
```

---

### Task 4: SkillCubit 刷新策略

**Files:**
- Modify: `client/lib/cubits/skill_cubit.dart`
- Test: `client/test/cubits/skill_cubit_test.dart`

**Interfaces:**
- Consumes: `DiscoverySettingsCubit`、`kDiscoveryAutoRefreshTtl`、`SkillRepository.syncRepoCache(..., maxStaleness)`、`SkillRepository.hasCachedSnapshot`
- Produces: `SkillCubit(SkillRepository repo, {List<SkillMarketplaceSource>? marketplaces, SkillAcquisitionEngine? acquisitionEngine, SkillUninstalledHandler? onSkillUninstalled, PackAcquireActivityAdapter? packAcquireActivity, DiscoverySettingsCubit? discoverySettings})`。

- [ ] **Step 1: 写失败的测试**

`client/test/cubits/skill_cubit_test.dart` — 顶部 import 追加：

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:teampilot/cubits/discovery_settings_cubit.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/skill/skill_fetch_service.dart';
import 'package:teampilot/services/skill/skill_repo_disk_cache_service.dart';
```

文件底部追加 fake 与测试（`_repo` 常量复用 Task 2 里相同的 repo 定义）：

```dart
const _discoveryRepo = SkillRepo(owner: 'acme', name: 'skills', branch: 'main');

class _FakeSkillFetch extends SkillFetchService {
  int downloads = 0;
  int shaChecks = 0;

  @override
  Future<String?> fetchBranchCommitSha(
    String owner,
    String name,
    String branch,
  ) async {
    shaChecks++;
    return null;
  }

  @override
  Future<({Map<String, Uint8List> entries, String branch, String commitSha})>
  downloadRepoEntries(
    SkillRepo repo, {
    Filesystem? fs,
    String? persistentGitPath,
  }) async {
    downloads++;
    return (
      entries: {
        'demo/SKILL.md': Uint8List.fromList(
          utf8.encode('---\nname: demo\ndescription: d\n---\n'),
        ),
      },
      branch: repo.branch,
      commitSha: 'abc123',
    );
  }
}

void _emitRepos(SkillCubit cubit) {
  cubit.emit(cubit.state.copyWith(repos: const [_discoveryRepo]));
}
```

测试（追加到 `main()` 内）：

```dart
  test('manual mode syncs repos without disk cache once', () async {
    final fetch = _FakeSkillFetch();
    final cubit = SkillCubit(
      SkillRepository(fetch: fetch),
    );
    _emitRepos(cubit);

    await cubit.ensureDiscoveryLoaded();

    expect(fetch.downloads, 1);
    expect(cubit.state.discoverable, isNotEmpty);
  });

  test('manual mode with disk cache does not hit network', () async {
    final fetch = _FakeSkillFetch();
    final cache = SkillRepoDiskCacheService(fetch: fetch);
    await cache.ensureSynced(_discoveryRepo);
    expect(fetch.downloads, 1);
    final cubit = SkillCubit(
      SkillRepository(fetch: fetch, repoCache: cache),
    );
    _emitRepos(cubit);

    await cubit.ensureDiscoveryLoaded();

    expect(fetch.downloads, 1);
    expect(fetch.shaChecks, 0);
    expect(cubit.state.discoverable, isNotEmpty);
  });

  test('manual mode with force always checks remote', () async {
    final fetch = _FakeSkillFetch();
    final cache = SkillRepoDiskCacheService(fetch: fetch);
    await cache.ensureSynced(_discoveryRepo);
    final cubit = SkillCubit(
      SkillRepository(fetch: fetch, repoCache: cache),
    );
    _emitRepos(cubit);

    await cubit.ensureDiscoveryLoaded(force: true);

    expect(fetch.shaChecks, 1);
    expect(fetch.downloads, 1);
    expect(cubit.state.discoverable, isNotEmpty);
  });

  test('auto mode with fresh cache skips network', () async {
    final fetch = _FakeSkillFetch();
    final cache = SkillRepoDiskCacheService(fetch: fetch);
    await cache.ensureSynced(_discoveryRepo);
    final settings = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    await settings.load();
    await settings.setAutoRefreshEnabled(true);
    final cubit = SkillCubit(
      SkillRepository(fetch: fetch, repoCache: cache),
      discoverySettings: settings,
    );
    _emitRepos(cubit);

    await cubit.ensureDiscoveryLoaded();

    expect(fetch.shaChecks, 0);
    expect(fetch.downloads, 1);
    expect(cubit.state.discoverable, isNotEmpty);
  });

  test('auto mode with stale cache checks remote', () async {
    final fetch = _FakeSkillFetch();
    final cache = SkillRepoDiskCacheService(fetch: fetch);
    await cache.ensureSynced(_discoveryRepo);
    final fs = AppStorage.fs;
    final metaPath = fs.pathContext.join(
      AppStorage.paths.skillRepoCacheDir,
      SkillRepoDiskCacheService.repoKey(_discoveryRepo),
      'meta.json',
    );
    final stale = SkillRepoCacheMeta(
      configuredBranch: 'main',
      resolvedBranch: 'main',
      commitSha: 'abc123',
      syncedAtMs: 1,
    );
    await fs.writeString(
      metaPath,
      const JsonEncoder.withIndent('  ').convert(stale.toJson()),
    );
    final settings = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    await settings.setAutoRefreshEnabled(true);
    final cubit = SkillCubit(
      SkillRepository(fetch: fetch, repoCache: cache),
      discoverySettings: settings,
    );
    _emitRepos(cubit);

    await cubit.ensureDiscoveryLoaded();

    expect(fetch.shaChecks, 1);
    expect(fetch.downloads, 1);
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/cubits/skill_cubit_test.dart`
Expected: 编译错误（`discoverySettings` 参数不存在；手动模式用例会因真实网络/无缓存而失败）。

- [ ] **Step 3: 实现 SkillCubit 策略**

`skill_cubit.dart` — import 追加：

```dart
import '../services/discovery/discovery_refresh_policy.dart';
import 'discovery_settings_cubit.dart';
```

构造函数加参数与字段：

```dart
  SkillCubit(
    this._repo, {
    this.marketplaces = const [],
    SkillAcquisitionEngine? acquisitionEngine,
    SkillUninstalledHandler? onSkillUninstalled,
    PackAcquireActivityAdapter? packAcquireActivity,
    DiscoverySettingsCubit? discoverySettings,
  }) : _acquisitionEngine = ...（原样）,
       ...
       _discoverySettings = discoverySettings,
       super(const SkillState());
```

字段区加：

```dart
  final DiscoverySettingsCubit? _discoverySettings;

  bool _autoRefreshEnabled() =>
      _discoverySettings?.state.autoRefreshEnabled ?? false;
```

替换 `ensureDiscoveryLoaded`（原 228-235 行）：

```dart
  /// Loads discovery when the Discovery tab opens: disk cache first; remote
  /// sync only for first-time (no cache) repos when auto-refresh is off, or
  /// per [kDiscoveryAutoRefreshTtl] when it is on. [force] always syncs.
  Future<void> ensureDiscoveryLoaded({bool force = false}) async {
    if (!force && state.discoveryLoading) return;
    if (!force && state.repoSyncingKeys.isNotEmpty) return;
    if (!force && state.discoverable.isNotEmpty) return;
    if (force) {
      await refreshDiscoverable(force: true);
      return;
    }
    if (_autoRefreshEnabled()) {
      await refreshDiscoverable(force: false);
      return;
    }
    await _syncMissingReposOnce();
  }

  /// 手动模式（默认）：只对从未同步过的 repo 做一次初始化同步，
  /// 有磁盘缓存的 repo 不发网络请求。
  Future<void> _syncMissingReposOnce() async {
    final enabled = state.repos.where((r) => r.enabled).toList();
    final missing = <SkillRepo>[];
    for (final repo in enabled) {
      if (!await _repo.hasCachedSnapshot(repo)) missing.add(repo);
    }
    if (missing.isEmpty) {
      emit(
        state.copyWith(
          discoveryLoading: false,
          repoSyncingKeys: const {},
          discoverable: await _aggregateDiscoverableFromDisk(enabled),
        ),
      );
      return;
    }
    await _syncReposInBackground(missing, force: true, clearError: true);
  }
```

`refreshDiscoverable`（原 237-250 行）改为：

```dart
  Future<void> refreshDiscoverable({bool force = false}) async {
    final enabled = state.repos.where((r) => r.enabled).toList();
    if (enabled.isEmpty) {
      emit(
        state.copyWith(
          discoveryLoading: false,
          discoverable: const [],
          repoSyncingKeys: const {},
        ),
      );
      return;
    }
    await _syncReposInBackground(
      enabled,
      force: force,
      clearError: true,
      maxStaleness: force
          ? null
          : (_autoRefreshEnabled() ? kDiscoveryAutoRefreshTtl : null),
    );
  }
```

`_syncReposInBackground` 签名（原 253-257 行）加参数：

```dart
  Future<void> _syncReposInBackground(
    List<SkillRepo> reposToSync, {
    bool force = false,
    bool clearError = false,
    Duration? maxStaleness,
  }) async {
```

其中同步调用（原 302 行）改为：

```dart
          await _repo.syncRepoCache(
            repo,
            force: force,
            maxStaleness: maxStaleness,
          );
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter test test/cubits/skill_cubit_test.dart test/services/skill/skill_repo_disk_cache_service_test.dart`
Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/skill_cubit.dart client/test/cubits/skill_cubit_test.dart
git commit -m "feat: skill discovery refresh policy (manual default, TTL auto)"
```

---

### Task 5: PluginCubit 刷新策略 + force 透传修复

**Files:**
- Modify: `client/lib/cubits/plugin_cubit.dart`
- Test: `client/test/cubits/plugin_cubit_test.dart`

**Interfaces:**
- Consumes: `DiscoverySettingsCubit`、`kDiscoveryAutoRefreshTtl`、`PluginRepoDiskCacheService.syncMarketplace(m, {force, maxStaleness})`、`hasCachedSnapshot`
- Produces: `PluginCubit({..., DiscoverySettingsCubit? discoverySettings})`。

- [ ] **Step 1: 写失败的测试**

`client/test/cubits/plugin_cubit_test.dart` — import 追加：

```dart
import 'package:teampilot/cubits/discovery_settings_cubit.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/plugin/plugin_repo_disk_cache_service.dart';
import 'package:teampilot/services/plugin/plugin_repo_git_service.dart';
```

文件底部追加 fake：

```dart
class _FakePluginGit extends PluginRepoGitService {
  int syncCheckouts = 0;
  int resolveShaCalls = 0;

  @override
  Future<({Map<String, Uint8List> entries, String branch, String commitSha})>
  syncCheckout(
    PluginMarketplace marketplace,
    Filesystem fs,
    String workDirPath,
  ) async {
    syncCheckouts++;
    await fs.ensureDir(workDirPath);
    await fs.ensureDir(fs.pathContext.join(workDirPath, '.claude-plugin'));
    await fs.writeString(
      fs.pathContext.join(workDirPath, '.claude-plugin', 'marketplace.json'),
      '{"name":"m","plugins":[{"name":"p1","description":"d","version":"1.0.0","source":"./plugins/p1"}]}',
    );
    return (
      entries: const <String, Uint8List>{},
      branch: marketplace.branch,
      commitSha: 'abc123',
    );
  }

  @override
  Future<({String sha, String branch})?> resolveRemoteShaWithFallback(
    String owner,
    String name,
    String configuredBranch,
  ) async {
    resolveShaCalls++;
    return null;
  }
}
```

需要 import `dart:typed_data` 与 `package:teampilot/services/io/filesystem.dart`、`package:teampilot/models/plugin.dart`（已有 plugin.dart）。

`main()` 末尾追加：

```dart
  test('manual mode syncs marketplaces without disk cache once', () async {
    final git = _FakePluginGit();
    final cubit = PluginCubit(
      repository: PluginRepository(),
      installService: PluginRepository().install,
      repoService: PluginRepoService(),
      diskCache: PluginRepoDiskCacheService(gitService: git),
    );
    await cubit.load();
    final enabledCount = cubit.state.marketplaces
        .where((m) => m.enabled)
        .length;
    expect(enabledCount, greaterThan(0));

    await cubit.ensureDiscoveryLoaded();

    expect(git.syncCheckouts, enabledCount);
    expect(git.resolveShaCalls, 0);
  });

  test('manual mode with disk cache does not hit network', () async {
    final git = _FakePluginGit();
    final diskCache = PluginRepoDiskCacheService(gitService: git);
    final cubit = PluginCubit(
      repository: PluginRepository(),
      installService: PluginRepository().install,
      repoService: PluginRepoService(),
      diskCache: diskCache,
    );
    await cubit.load();
    final enabledCount = cubit.state.marketplaces
        .where((m) => m.enabled)
        .length;

    await cubit.ensureDiscoveryLoaded();
    expect(git.syncCheckouts, enabledCount);

    final cubit2 = PluginCubit(
      repository: PluginRepository(),
      installService: PluginRepository().install,
      repoService: PluginRepoService(),
      diskCache: diskCache,
    );
    await cubit2.load();

    await cubit2.ensureDiscoveryLoaded();

    expect(git.syncCheckouts, enabledCount);
    expect(git.resolveShaCalls, 0);
    expect(cubit2.state.discoverable, isNotEmpty);
  });

  test('auto mode with stale cache checks remote SHA', () async {
    final git = _FakePluginGit();
    final diskCache = PluginRepoDiskCacheService(gitService: git);
    final settings = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    await settings.setAutoRefreshEnabled(true);
    final cubit = PluginCubit(
      repository: PluginRepository(),
      installService: PluginRepository().install,
      repoService: PluginRepoService(),
      diskCache: diskCache,
      discoverySettings: settings,
    );
    await cubit.load();
    final enabledCount = cubit.state.marketplaces
        .where((m) => m.enabled)
        .length;

    await cubit.ensureDiscoveryLoaded();
    expect(git.syncCheckouts, enabledCount);

    // 把缓存 meta 改成过期，再走自动刷新 → 应检查远端 SHA（remote null → 保留缓存）
    final market = cubit.state.marketplaces.firstWhere((m) => m.enabled);
    final metaPath = AppStorage.fs.pathContext.join(
      AppStorage.paths.pluginMarketplaceCacheDir,
      PluginRepoDiskCacheService.repoKey(market),
      '.teampilot-plugin-cache-meta.json',
    );
    await AppStorage.fs.writeString(
      metaPath,
      const JsonEncoder.withIndent('  ').convert({
        'configuredBranch': 'main',
        'resolvedBranch': 'main',
        'commitSha': 'abc123',
        'syncedAtMs': 1,
      }),
    );

    final cubit2 = PluginCubit(
      repository: PluginRepository(),
      installService: PluginRepository().install,
      repoService: PluginRepoService(),
      diskCache: diskCache,
      discoverySettings: settings,
    );
    await cubit2.load();

    await cubit2.ensureDiscoveryLoaded();

    expect(git.resolveShaCalls, 1);
  });
```

需要 import `dart:convert`。

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/cubits/plugin_cubit_test.dart`
Expected: 编译错误（`discoverySettings` 参数不存在）。

- [ ] **Step 3: 实现 PluginCubit 策略**

`plugin_cubit.dart` — import 追加：

```dart
import '../services/discovery/discovery_refresh_policy.dart';
import 'discovery_settings_cubit.dart';
```

构造函数（98-112 行）加：

```dart
    PluginUpdatedHandler? onPluginUpdated,
    PackAcquireActivityAdapter? packAcquireActivity,
    DiscoverySettingsCubit? discoverySettings,
  }) : _diskCache = diskCache ?? PluginRepoDiskCacheService(),
       ...
       _discoverySettings = discoverySettings,
       super(const PluginState());
```

字段区加：

```dart
  final DiscoverySettingsCubit? _discoverySettings;

  bool _autoRefreshEnabled() =>
      _discoverySettings?.state.autoRefreshEnabled ?? false;
```

替换 `ensureDiscoveryLoaded`（原 144-151 行）：

```dart
  /// Loads discovery when the Discovery tab opens: disk cache first; remote
  /// sync only for first-time (no cache) marketplaces when auto-refresh is
  /// off, or per [kDiscoveryAutoRefreshTtl] when it is on. [force] always
  /// syncs.
  Future<void> ensureDiscoveryLoaded({bool force = false}) async {
    if (!force && state.discoveryLoading) return;
    if (!force && state.marketplaceSyncingKeys.isNotEmpty) return;
    if (!force && state.discoverable.isNotEmpty) return;
    if (force) {
      await refreshDiscoverable(force: true);
      return;
    }
    if (_autoRefreshEnabled()) {
      await refreshDiscoverable(force: false);
      return;
    }
    await _syncMissingMarketplacesOnce();
  }

  /// 手动模式（默认）：只对从未同步过的 marketplace 做一次初始化同步，
  /// 有磁盘缓存的 marketplace 不发网络请求。
  Future<void> _syncMissingMarketplacesOnce() async {
    final enabled = state.marketplaces.where((m) => m.enabled).toList();
    final missing = <PluginMarketplace>[];
    for (final m in enabled) {
      if (!await _diskCache.hasCachedSnapshot(m)) missing.add(m);
    }
    if (missing.isEmpty) {
      emit(
        state.copyWith(
          discoveryLoading: false,
          marketplaceSyncingKeys: const {},
          discoverable: await _aggregateDiscoverableFromDisk(enabled),
        ),
      );
      return;
    }
    await _syncMarketplacesInBackground(
      missing,
      force: true,
      clearError: true,
    );
  }
```

`refreshDiscoverable`（原 175-192 行）改为：

```dart
  Future<void> refreshDiscoverable({bool force = false}) async {
    final enabled = state.marketplaces.where((m) => m.enabled).toList();
    if (enabled.isEmpty) {
      emit(
        state.copyWith(
          discoveryLoading: false,
          discoverable: const [],
          marketplaceSyncingKeys: const {},
        ),
      );
      return;
    }
    await _syncMarketplacesInBackground(
      enabled,
      force: force,
      clearError: true,
      maxStaleness: force
          ? null
          : (_autoRefreshEnabled() ? kDiscoveryAutoRefreshTtl : null),
    );
  }
```

`_syncMarketplacesInBackground`（原 194-198 行）签名加参数：

```dart
  Future<void> _syncMarketplacesInBackground(
    List<PluginMarketplace> marketplacesToSync, {
    bool force = false,
    bool clearError = false,
    Duration? maxStaleness,
  }) async {
```

同步调用（原 245 行，force 透传修复）改为：

```dart
          await _diskCache.syncMarketplace(
            m,
            force: force,
            maxStaleness: maxStaleness,
          );
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter test test/cubits/plugin_cubit_test.dart test/services/plugin/plugin_repo_disk_cache_service_test.dart`
Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/plugin_cubit.dart client/test/cubits/plugin_cubit_test.dart
git commit -m "feat: plugin discovery refresh policy (manual default, TTL auto, force passthrough)"
```

---

### Task 6: McpDiscoveryCubit 刷新策略

**Files:**
- Modify: `client/lib/cubits/mcp_discovery_cubit.dart`
- Create: `client/test/cubits/mcp_discovery_cubit_test.dart`

**Interfaces:**
- Consumes: `DiscoverySettingsCubit`、`kDiscoveryAutoRefreshTtl`
- Produces: `McpDiscoveryCubit({McpRegistryConfigService? registryConfig, SmitheryMcpService? smithery, McpRegistryBrowseService? registry, McpDiscoveryDiskCacheService? diskCache, DiscoverySettingsCubit? discoverySettings})`。

- [ ] **Step 1: 写失败的测试**

创建 `client/test/cubits/mcp_discovery_cubit_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/cubits/discovery_settings_cubit.dart';
import 'package:teampilot/cubits/mcp_discovery_cubit.dart';
import 'package:teampilot/models/mcp_catalog_listing.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/mcp/mcp_discovery_disk_cache_service.dart';
import 'package:teampilot/services/mcp/mcp_registry_browse_service.dart';
import 'package:teampilot/services/mcp/smithery_mcp_service.dart';

import '../support/post_frame_test_harness.dart';

const _listing = McpCatalogListing(
  id: 'acme/foo',
  title: 'Foo',
  description: 'd',
  source: McpCatalogSource.smithery,
  serverSpec: {'command': 'foo'},
);

class _FakeSmithery extends SmitheryMcpService {
  _FakeSmithery() : super(client: MockClient((_) async => http.Response('{}', 200)));

  int searches = 0;

  @override
  Future<SmitherySearchResult> search(
    String query, {
    required String baseUrl,
    String? apiToken,
    int page = 1,
    int pageSize = 20,
  }) async {
    searches++;
    return SmitherySearchResult(
      items: const [],
      page: 1,
      totalPages: 1,
      query: query,
    );
  }
}

class _FakeRegistry extends McpRegistryBrowseService {
  _FakeRegistry() : super(client: MockClient((_) async => http.Response('{}', 200)));

  int searches = 0;

  @override
  Future<McpRegistryBrowseResult> search(
    String query, {
    required String baseUrl,
    String? cursor,
    int pageSize = 20,
  }) async {
    searches++;
    return McpRegistryBrowseResult(items: const [], nextCursor: null, query: query);
  }
}

Future<void> _seedCache({required int syncedAtMs}) async {
  final disk = McpDiscoveryDiskCacheService();
  await disk.write(
    sourceKey: mcpDiscoveryCacheSmithery,
    snapshot: McpDiscoveryDiskSnapshot(
      items: const [_listing],
      query: '',
      syncedAtMs: syncedAtMs,
    ),
  );
  await disk.write(
    sourceKey: mcpDiscoveryCacheOfficial,
    snapshot: McpDiscoveryDiskSnapshot(
      items: const [_listing],
      query: '',
      syncedAtMs: syncedAtMs,
    ),
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('manual mode with disk cache does not fetch remote', () async {
    await _seedCache(syncedAtMs: 1);
    final smithery = _FakeSmithery();
    final registry = _FakeRegistry();
    final cubit = McpDiscoveryCubit(
      smithery: smithery,
      registry: registry,
      discoverySettings: DiscoverySettingsCubit(
        repository: InMemoryAppSettingsRepository(),
      ),
    );

    await cubit.initialize();

    expect(smithery.searches, 0);
    expect(registry.searches, 0);
    expect(cubit.state.smitheryItems, isNotEmpty);
    expect(cubit.state.officialItems, isNotEmpty);
  });

  test('manual mode with no disk cache fetches once (initialization)', () async {
    final smithery = _FakeSmithery();
    final registry = _FakeRegistry();
    final cubit = McpDiscoveryCubit(
      smithery: smithery,
      registry: registry,
      discoverySettings: DiscoverySettingsCubit(
        repository: InMemoryAppSettingsRepository(),
      ),
    );

    await cubit.initialize();

    expect(smithery.searches, 1);
    expect(registry.searches, 1);
  });

  test('auto mode with fresh cache does not fetch remote', () async {
    await _seedCache(
      syncedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final smithery = _FakeSmithery();
    final registry = _FakeRegistry();
    final settings = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    await settings.setAutoRefreshEnabled(true);
    final cubit = McpDiscoveryCubit(
      smithery: smithery,
      registry: registry,
      discoverySettings: settings,
    );

    await cubit.initialize();

    expect(smithery.searches, 0);
    expect(registry.searches, 0);
  });

  test('auto mode with stale cache fetches remote', () async {
    await _seedCache(syncedAtMs: 1);
    final smithery = _FakeSmithery();
    final registry = _FakeRegistry();
    final settings = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    await settings.setAutoRefreshEnabled(true);
    final cubit = McpDiscoveryCubit(
      smithery: smithery,
      registry: registry,
      discoverySettings: settings,
    );

    await cubit.initialize();

    expect(smithery.searches, 1);
    expect(registry.searches, 1);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/cubits/mcp_discovery_cubit_test.dart`
Expected: 编译错误（`discoverySettings` 参数不存在；或行为失败：manual+缓存用例仍 fetch）。

- [ ] **Step 3: 实现 McpDiscoveryCubit 策略**

`mcp_discovery_cubit.dart` — import 追加：

```dart
import '../services/discovery/discovery_refresh_policy.dart';
import 'discovery_settings_cubit.dart';
```

构造函数（130-139 行）加参数与字段：

```dart
  McpDiscoveryCubit({
    McpRegistryConfigService? registryConfig,
    SmitheryMcpService? smithery,
    McpRegistryBrowseService? registry,
    McpDiscoveryDiskCacheService? diskCache,
    DiscoverySettingsCubit? discoverySettings,
  }) : _registryConfig = registryConfig ?? McpRegistryConfigService(),
       _smithery = smithery ?? SmitheryMcpService(),
       _registry = registry ?? McpRegistryBrowseService(),
       _diskCache = diskCache ?? McpDiscoveryDiskCacheService(),
       _discoverySettings = discoverySettings,
       super(const McpDiscoveryState());
```

字段区加：

```dart
  final DiscoverySettingsCubit? _discoverySettings;

  bool _autoRefreshEnabled() =>
      _discoverySettings?.state.autoRefreshEnabled ?? false;
```

`_RemoteSourceSnapshot`（15-22 行）加字段：

```dart
class _RemoteSourceSnapshot {
  List<McpCatalogListing> items = [];
  String query = '';
  int syncedAtMs = 0;
  int smitheryPage = 1;
  int smitheryTotalPages = 1;
  String? registryCursor;
  String? registryNextCursor;
}
```

`_hydrateSourceFromDisk`（315-329 行）同步 `syncedAtMs`：

```dart
    final snapshot = _remoteSnapshots[source]!;
    snapshot
      ..items = List<McpCatalogListing>.from(cached.items)
      ..query = cached.query
      ..syncedAtMs = cached.syncedAtMs
      ..smitheryPage = cached.smitheryPage
      ..smitheryTotalPages = cached.smitheryTotalPages
      ..registryCursor = cached.registryCursor
      ..registryNextCursor = cached.registryNextCursor;
```

`_warmRemoteCaches`（331-347 行）改为：

```dart
  Future<void> _warmRemoteCaches() async {
    if (state.loading) return;
    final ttl = _autoRefreshEnabled() ? kDiscoveryAutoRefreshTtl : null;
    final needsSmithery = _needsWarm(McpDiscoverySource.smithery, ttl);
    final needsOfficial = _needsWarm(McpDiscoverySource.official, ttl);
    if (!needsSmithery && !needsOfficial) return;

    emit(state.copyWith(loading: true, clearError: true));
    await Future.wait([
      if (needsSmithery)
        _loadRemoteSource(McpDiscoverySource.smithery, reset: true),
      if (needsOfficial)
        _loadRemoteSource(McpDiscoverySource.official, reset: true),
    ]);
    emit(state.copyWith(loading: false));
  }

  /// 手动模式（ttl == null）：有缓存即不拉取；自动模式：缓存超过
  /// TTL 才算过期。无缓存（首次）总是拉取。
  bool _needsWarm(McpDiscoverySource source, Duration? ttl) {
    final snapshot = _remoteSnapshots[source]!;
    if (snapshot.items.isEmpty) return true;
    if (ttl == null) return false;
    return DateTime.now().millisecondsSinceEpoch - snapshot.syncedAtMs >=
        ttl.inMilliseconds;
  }
```

`_persistSnapshotToDisk`（474-491 行）写盘前刷新 `syncedAtMs`：

```dart
    if (snapshot.query.isNotEmpty) return;
    snapshot.syncedAtMs = DateTime.now().millisecondsSinceEpoch;
    await _diskCache.write(
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter test test/cubits/mcp_discovery_cubit_test.dart`
Expected: 全部 PASS（4 个用例）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/mcp_discovery_cubit.dart client/test/cubits/mcp_discovery_cubit_test.dart
git commit -m "feat: mcp discovery refresh policy (manual default, TTL auto)"
```

---

### Task 7: 设置页「发现与市场」分组（UI + 路由 + l10n）

**Files:**
- Create: `client/lib/pages/config/discovery_config_section.dart`
- Modify: `client/lib/cubits/config_cubit.dart`
- Modify: `client/lib/pages/config/config_workspace.dart`
- Modify: `client/lib/router/app_router.dart`
- Modify: `client/lib/router/android_shell_chrome.dart`
- Modify: `client/lib/utils/ui/app_keys.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`

**Interfaces:**
- Consumes: `DiscoverySettingsCubit`
- Produces: `DiscoveryConfigWorkspace({bool showHeading = true})`；`ConfigSection.discovery`（routeSegment `'discovery'`）；`AppKeys.configDiscoverySectionButton`；l10n keys `discoverySettingsTitle/discoverySettingsSubtitle/discoveryAutoRefreshTitle/discoveryAutoRefreshSubtitle`。

- [ ] **Step 1: l10n 文案（先加 key，后生成）**

`client/lib/l10n/app_en.arb` 中 `"downloadSourcesSettingsTitle"` 附近追加：

```json
  "discoverySettingsTitle": "Discovery & Marketplaces",
  "discoverySettingsSubtitle": "How skills, plugins and MCP discovery content refreshes.",
  "discoveryAutoRefreshTitle": "Auto-refresh discovery content",
  "discoveryAutoRefreshSubtitle": "When on, opening discovery pages checks for updates when the cache is older than 24 hours. Manual refresh always updates."
```

`client/lib/l10n/app_zh.arb` 对应追加：

```json
  "discoverySettingsTitle": "发现与市场",
  "discoverySettingsSubtitle": "技能、插件与 MCP 发现内容的刷新方式。",
  "discoveryAutoRefreshTitle": "自动刷新发现内容",
  "discoveryAutoRefreshSubtitle": "开启后，打开发现页时若缓存超过 24 小时将自动检查更新；手动刷新始终有效。"
```

- [ ] **Step 2: 生成 l10n 并确认 key 可用**

Run: `cd client && flutter gen-l10n`
Expected: 成功；`lib/l10n/app_localizations.dart` 出现 4 个 getter。

- [ ] **Step 3: 创建 DiscoveryConfigWorkspace**

创建 `client/lib/pages/config/discovery_config_section.dart`（行样式参考 `ai_features_config_section.dart` 的 `AiFeatureConfigRow`）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/discovery_settings_cubit.dart';
import '../../l10n/l10n_extensions.dart';

/// Global "Discovery & Marketplaces" settings: auto-refresh policy for the
/// skills / plugins / MCP discovery pages.
class DiscoveryConfigWorkspace extends StatelessWidget {
  const DiscoveryConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<DiscoverySettingsCubit, DiscoverySettingsState>(
      builder: (context, state) {
        return SingleChildScrollView(
          child: TpCard.outlined(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showHeading) ...[
                  TpSectionHeader(title: l10n.discoverySettingsTitle),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text(
                      l10n.discoverySettingsSubtitle,
                      style: TpTextStyles.of(context).smMediumColored(
                        Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                _DiscoveryAutoRefreshRow(
                  enabled: state.autoRefreshEnabled,
                  onChanged: (value) => context
                      .read<DiscoverySettingsCubit>()
                      .setAutoRefreshEnabled(value),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DiscoveryAutoRefreshRow extends StatelessWidget {
  const _DiscoveryAutoRefreshRow({
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.storefront_outlined,
            size: 22,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.discoveryAutoRefreshTitle,
                  style: styles.lgColored(cs.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.discoveryAutoRefreshSubtitle,
                  style: styles.smColored(cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: enabled, onChanged: onChanged),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 注册 ConfigSection**

`client/lib/cubits/config_cubit.dart`：
- enum `downloadSources,` 后加 `discovery,`
- `routeSegment` switch 加 `ConfigSection.discovery => 'discovery',`
- `title` switch 加 `ConfigSection.discovery => 'Discovery & Marketplaces',`
- `breadcrumb` switch 加 `ConfigSection.discovery => 'Config / Discovery & Marketplaces',`

- [ ] **Step 5: 注册 config_workspace.dart**

`client/lib/pages/config/config_workspace.dart`：
- import 加 `import 'discovery_config_section.dart';`
- `_configSectionDialogIndex` 改为：

```dart
int _configSectionDialogIndex(ConfigSection section) {
  return switch (section) {
    ConfigSection.layout => 0,
    ConfigSection.session => 1,
    ConfigSection.cli => 2,
    ConfigSection.aiFeatures => 3,
    ConfigSection.sshProfiles => 4,
    ConfigSection.github => 5,
    ConfigSection.downloadSources => 6,
    ConfigSection.discovery => 7,
    ConfigSection.shortcuts => 8,
    ConfigSection.about => 9,
    ConfigSection.logs => 9,
  };
}
```

- `showWorkspaceSettingsDialog` 的 entries：`DownloadSourcesConfigWorkspace` entry 之后插入：

```dart
      SettingsDialogEntry(
        icon: Icons.storefront_outlined,
        navLabel: (l10n) => l10n.discoverySettingsTitle,
        title: (l10n) => l10n.discoverySettingsTitle,
        subtitle: (l10n) => l10n.discoverySettingsSubtitle,
        bodyBuilder: (_) => const DiscoveryConfigWorkspace(showHeading: false),
      ),
```

- `ConfigSettingsHubPage` 的 entries：downloadSources entry 之后插入：

```dart
        WorkspaceHubEntry(
          key: AppKeys.configDiscoverySectionButton,
          title: l10n.discoverySettingsTitle,
          icon: Icons.storefront_outlined,
          onTap: throttledTap('config_hub_discovery', () {
            context.read<ConfigCubit>().selectSection(ConfigSection.discovery);
            context.push('/config/${ConfigSection.discovery.routeSegment}');
          }),
        ),
```

- `ConfigWorkspace` body switch 加：`ConfigSection.discovery => DiscoveryConfigWorkspace(showHeading: showHeading),`
- `ConfigNavPanel` entries：downloadSources entry 之后插入：

```dart
        WorkspaceHubEntry(
          key: AppKeys.configDiscoverySectionButton,
          title: l10n.discoverySettingsTitle,
          icon: Icons.storefront_outlined,
          selected: section == ConfigSection.discovery,
          onTap: throttledTap(
            'config_nav_discovery',
            () => onSelectSection(ConfigSection.discovery),
          ),
        ),
```

- [ ] **Step 6: 注册路由 + Android 标题 + key**

`client/lib/router/app_router.dart` — `/config/download-sources` GoRoute 之后插入：

```dart
            GoRoute(
              path: '/config/discovery',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ConfigWorkspace(section: ConfigSection.discovery),
              ),
            ),
```

`client/lib/router/android_shell_chrome.dart` — `download-sources` 行后插入：

```dart
    if (path == '/config/discovery') return l10n.discoverySettingsTitle;
```

`client/lib/utils/ui/app_keys.dart` — `configShortcutsSectionButton` 前插入：

```dart
  static const configDiscoverySectionButton = Key(
    'config-discovery-section-button',
  );
```

- [ ] **Step 7: 编译验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无新增错误。

- [ ] **Step 8: Commit**

```bash
git add client/lib/pages/config/discovery_config_section.dart \
  client/lib/cubits/config_cubit.dart \
  client/lib/pages/config/config_workspace.dart \
  client/lib/router/app_router.dart \
  client/lib/router/android_shell_chrome.dart \
  client/lib/utils/ui/app_keys.dart \
  client/lib/l10n/app_en.arb \
  client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart
git commit -m "feat: discovery & marketplaces settings section with auto-refresh toggle"
```

（`flutter gen-l10n` 会改动 3 个生成文件，一并提交。）

---

### Task 8: 全局 wiring + 全量验证

**Files:**
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/app/app_data_bootstrap.dart`
- Modify: `client/lib/main.dart`
- Modify: `client/lib/pages/mcp/mcp_management_page.dart`

**Interfaces:**
- Consumes: `DiscoverySettingsCubit`
- Produces: `shell.discoverySettingsCubit`（app 级 BlocProvider）

- [ ] **Step 1: app_shell 创建 cubit 并注入**

`client/lib/app/app_shell.dart` — `aiFeatureSettingsCubit` 创建后（约 408-410 行）加：

```dart
  final discoverySettingsCubit = DiscoverySettingsCubit(
    repository: appSettings,
  );
```

`SkillCubit(...)` 调用（约 967 行）加参数 `discoverySettings: discoverySettingsCubit,`；`PluginCubit(...)` 调用（约 977 行）同样加 `discoverySettings: discoverySettingsCubit,`。

把 `discoverySettingsCubit` 暴露为 shell 字段（与 `aiFeatureSettingsCubit` 相同的暴露方式，main.dart 用 `shell.aiFeatureSettingsCubit` 引用；找到对应字段声明处，为 `discoverySettingsCubit` 加同款字段并在创建处赋值）。

- [ ] **Step 2: bootstrap 加载**

`client/lib/app/app_data_bootstrap.dart` — `prepareInteractiveShell` 参数列表（266-269 行）加：

```dart
    required DiscoverySettingsCubit discoverySettingsCubit,
```

`aiFeatureSettings` `_timed` 之后（283 行后）加：

```dart
    await _timed(boot, 'discoverySettings', discoverySettingsCubit.load);
    await yieldUiFrame();
```

并在 `prepareInteractiveShell` 的调用点（app_shell.dart 内）传入 `discoverySettingsCubit: discoverySettingsCubit`。

- [ ] **Step 3: main.dart 提供 cubit**

`client/lib/main.dart` MultiBlocProvider（739-780 行）`shell.aiFeatureSettingsCubit` 行后加：

```dart
                  BlocProvider.value(value: shell.discoverySettingsCubit),
```

- [ ] **Step 4: mcp_management_page 注入**

`client/lib/pages/mcp/mcp_management_page.dart` — import 加 `import '../../cubits/discovery_settings_cubit.dart';`，`initState` 改为：

```dart
    _discoveryCubit = McpDiscoveryCubit(
      discoverySettings: context.read<DiscoverySettingsCubit>(),
    );
```

- [ ] **Step 5: 编译验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无新增错误/警告。

- [ ] **Step 6: 全量测试**

Run: `cd client && flutter test --exclude-tags integration`
Expected: 全部 PASS（含 Task 1-6 新增测试）。

- [ ] **Step 7: 手动 QA（可选但建议）**

1. 启动 app → 设置 → 「发现与市场」→ 开关默认关。
2. 打开 MCP 发现页（首次）→ 会拉取一次；关闭重进 → 不再请求（可在日志确认无 `/servers` 请求）。
3. 打开开关 → 重进发现页 → 缓存新鲜则不请求。
4. Skills / Plugins 发现页同样验证：默认无网络、点刷新按钮强制更新。
5. 重启 app → 开关状态保持。

- [ ] **Step 8: Commit**

```bash
git add client/lib/app/app_shell.dart \
  client/lib/app/app_data_bootstrap.dart \
  client/lib/main.dart \
  client/lib/pages/mcp/mcp_management_page.dart
git commit -m "feat: wire discovery auto-refresh setting into shell, bootstrap and MCP page"
```
