# opencode 供应商 + 模型目录全量适配 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让用户在 teampilot 中体验到 opencode 的完整供应商 + 完整模型：新增 `opencode-go` 订阅供应商 preset，模型选择器显示各 provider 的实时全量模型（live-fetch models.dev），并把 opencode 模型能力迁移到 per-CLI 目录。

**Architecture:** 镜像 `CursorAgentModelsService` 的 live-fetch + 磁盘缓存模式，新建 `OpencodeModelsService`（全局拉 `https://models.dev/api.json`，TTL 6h，离线回退静态清单）；新建 per-CLI 能力文件 `opencode_provider_model_capability.dart`（从共享 `registry/capabilities/provider_model_capability.dart` 迁出并升级为 `RefreshableProviderModelCapability`）；通过 `OpencodeBootstrapEntry` → `built_in_cli_tools.dart` → `app_shell.dart` 注入。UI 零改动（`provider_model_picker_field.dart` 已泛化支持）。

**Tech Stack:** Dart / Flutter，`flutter_bloc`，`package:http`（`MockClient` 测试），`InMemoryFilesystem`（测试支持），per-CLI capability 模式（`docs/cli-architecture.md`）。

## Global Constraints

- 所有 CLI 代码必须落在 per-CLI 目录 `client/lib/services/cli/opencode/`（capabilities 在 `capabilities/`，provider 层在 `provider/`，presets 在 `provider_presets.dart`）。禁止在共享 `registry/` 里放 CLI 特定实现。
- 禁止 `if (cli == CliTool.X)` 散落判断；差异化行为一律通过能力接口（`CliToolRegistry.capability<T>(cli)`）。
- opencode 的模型默认值仍由 preset 的 `defaultModel` 决定（models.dev 无默认模型概念）；live 目录只补全候选列表。
- 离线/首拉失败必须回退到 `OpencodeModelCatalog` 静态清单，不抛异常。
- 验证命令（每个任务结束必跑）：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`。
- 测试路径沿用现有 opencode 测试目录 `client/test/services/provider/opencode/`。
- 新增文件命名按 per-CLI 规范：`opencode_models_service.dart`、`opencode_provider_model_capability.dart`。

---

### Task 1: `opencode-go` 订阅供应商 preset

**Files:**
- Modify: `client/lib/services/cli/opencode/provider_presets.dart`（在 `opencode` preset 之后、`openai` 之前插入）
- Test: Create `client/test/services/provider/opencode/opencode_provider_presets_test.dart`

**Interfaces:**
- Consumes: `AppProviderPreset` / `AppProviderConfig`（`client/lib/models/app_provider_config.dart`）、`CliTool`、`AppProviderCategory`。
- Produces: `OpencodeProviderPresets.byId('opencode-go')` 返回非空 official preset；`preset.template` 带 `defaultModel: 'deepseek-v4-flash'`、`baseUrl: 'https://opencode.ai/zen/go/v1'`、`config['npm']: '@ai-sdk/openai-compatible'`。

- [ ] **Step 1: 写失败测试**

Create `client/test/services/provider/opencode/opencode_provider_presets_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/opencode/provider_presets.dart';

void main() {
  test('opencode-go resolves as an official subscription preset', () {
    final preset = OpencodeProviderPresets.byId('opencode-go');
    expect(preset, isNotNull);
    expect(preset!.label, 'OpenCode Go (subscription)');
    expect(preset.template.isOfficial, isTrue);
    expect(preset.template.category, AppProviderCategory.official);
    expect(preset.template.apiKeyUrl, 'https://opencode.ai/go');
    expect(preset.template.baseUrl, 'https://opencode.ai/zen/go/v1');
    expect(preset.template.defaultModel, 'deepseek-v4-flash');
    expect(preset.template.config['npm'], '@ai-sdk/openai-compatible');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/services/provider/opencode/opencode_provider_presets_test.dart`
Expected: FAIL（`byId('opencode-go')` 返回 null）。

- [ ] **Step 3: 加 preset**

在 `client/lib/services/cli/opencode/provider_presets.dart` 的 `opencode` preset（第 19-32 行）之后插入：

```dart
    AppProviderPreset(
      id: "opencode-go",
      label: "OpenCode Go (subscription)",
      template: AppProviderConfig(
        id: "opencode-go",
        cli: CliTool.opencode,
        name: "OpenCode Go",
        websiteUrl: "https://opencode.ai",
        apiKeyUrl: "https://opencode.ai/go",
        category: AppProviderCategory.official,
        baseUrl: "https://opencode.ai/zen/go/v1",
        defaultModel: "deepseek-v4-flash",
        config: {"npm": "@ai-sdk/openai-compatible"},
        isOfficial: true,
      ),
    ),
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter test test/services/provider/opencode/opencode_provider_presets_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/opencode/provider_presets.dart \
        client/test/services/provider/opencode/opencode_provider_presets_test.dart
git commit -m "feat(opencode): add opencode-go subscription provider preset

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: `OpencodeModelsService`（live-fetch models.dev）

**Files:**
- Create: `client/lib/services/cli/opencode/provider/opencode_models_service.dart`
- Test: Create `client/test/services/provider/opencode/opencode_models_service_test.dart`

**Interfaces:**
- Consumes: `Filesystem`（`client/lib/services/io/filesystem.dart`）、`AppStorage`、`package:http`。
- Produces:
  - `class OpencodeModelsService { OpencodeModelsService({Filesystem? fs, String? basePath, http.Client? httpClient, Duration cacheTtl = 6h}); }`
  - `Listenable get catalogUpdates`
  - `List<String> modelIdsFor({String providerId = ''})`
  - `Future<void> ensureLoaded({bool forceRefresh = false})`
  - `@visibleForTesting Future<void> writeCacheForTest(OpencodeModelsCacheEntry entry)`
  - `class OpencodeModelsCacheEntry { int fetchedAtMs; Map<String, List<String>> modelsByProvider; toJson/fromJson; }`

- [ ] **Step 1: 写失败测试**

Create `client/test/services/provider/opencode/opencode_models_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_models_service.dart';

import '../../../support/in_memory_filesystem.dart';

const _apiJson = '''
{
  "opencode": {"name": "OpenCode Zen", "models": {"claude-sonnet-4-5": {}, "gpt-5.2": {}}},
  "opencode-go": {"name": "OpenCode Go", "models": {"deepseek-v4-flash": {}, "qwen3.6-plus": {}}},
  "openai": {"name": "OpenAI", "models": {"gpt-4o": {}}},
  "empty-provider": {"name": "X", "models": {}}
}
''';

OpencodeModelsCacheEntry _entry(Map<String, List<String>> byProvider) =>
    OpencodeModelsCacheEntry(
      fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
      modelsByProvider: byProvider,
    );

void main() {
  test('fetches live catalog and slices per provider', () async {
    final fs = InMemoryFilesystem();
    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: MockClient((request) async {
        expect(request.url.toString(), 'https://models.dev/api.json');
        return http.Response(_apiJson, 200);
      }),
    );

    await service.ensureLoaded();
    expect(
      service.modelIdsFor(providerId: 'opencode'),
      contains('claude-sonnet-4-5'),
    );
    expect(
      service.modelIdsFor(providerId: 'opencode-go'),
      containsAll(['deepseek-v4-flash', 'qwen3.6-plus']),
    );
    expect(service.modelIdsFor(providerId: 'unknown'), isEmpty);
  });

  test('reads fresh disk cache without HTTP', () async {
    final fs = InMemoryFilesystem();
    final neverCalled = MockClient((request) async {
      throw StateError('http should not be called');
    });
    // seed disk cache, then use a fresh service (empty memory)
    await OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: neverCalled,
    ).writeCacheForTest(_entry({'opencode': const ['gpt-5.2']}));

    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: neverCalled,
    );
    await service.ensureLoaded();
    expect(service.modelIdsFor(providerId: 'opencode'), ['gpt-5.2']);
  });

  test('falls back to stale disk cache when fetch fails', () async {
    final fs = InMemoryFilesystem();
    final stale = OpencodeModelsCacheEntry(
      fetchedAtMs: 0,
      modelsByProvider: {'opencode': const ['claude-haiku-4-5']},
    );
    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: MockClient(
        (request) async => http.Response('oops', 500),
      ),
    );
    await service.writeCacheForTest(stale);

    await service.ensureLoaded();
    expect(service.modelIdsFor(providerId: 'opencode'), ['claude-haiku-4-5']);
  });

  test('returns empty without crashing on network error', () async {
    final fs = InMemoryFilesystem();
    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: MockClient(
        (request) async => throw Exception('network down'),
      ),
    );
    await service.ensureLoaded();
    expect(service.modelIdsFor(providerId: 'opencode'), isEmpty);
  });

  test('dedupes concurrent ensureLoaded calls', () async {
    var calls = 0;
    final fs = InMemoryFilesystem();
    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: MockClient((request) async {
        calls++;
        return http.Response(_apiJson, 200);
      }),
    );
    final f1 = service.ensureLoaded();
    final f2 = service.ensureLoaded();
    await Future.wait([f1, f2]);
    expect(calls, 1);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/services/provider/opencode/opencode_models_service_test.dart`
Expected: FAIL（`OpencodeModelsService` 未定义）。

- [ ] **Step 3: 实现 service**

Create `client/lib/services/cli/opencode/provider/opencode_models_service.dart`:

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../io/filesystem.dart';
import '../../../storage/app_storage.dart';

/// Cache entry for a fetched models.dev catalog slice.
///
/// models.dev's `api.json` is a single global catalog (all providers); only the
/// `providerId -> [model ids]` mapping is kept on disk.
class OpencodeModelsCacheEntry {
  const OpencodeModelsCacheEntry({
    required this.fetchedAtMs,
    required this.modelsByProvider,
  });

  final int fetchedAtMs;
  final Map<String, List<String>> modelsByProvider;

  Map<String, Object?> toJson() => {
    'fetchedAtMs': fetchedAtMs,
    'modelsByProvider': modelsByProvider,
  };

  factory OpencodeModelsCacheEntry.fromJson(Map<String, Object?> json) {
    final byProvider = <String, List<String>>{};
    final raw = json['modelsByProvider'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final ids = entry.value;
        if (ids is List) {
          final list = ids
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (list.isNotEmpty) {
            byProvider[entry.key.toString().trim()] = list;
          }
        }
      }
    }
    return OpencodeModelsCacheEntry(
      fetchedAtMs: (json['fetchedAtMs'] as num?)?.toInt() ?? 0,
      modelsByProvider: byProvider,
    );
  }
}

class _ResolvedStorage {
  const _ResolvedStorage({required this.fs, required this.basePath});

  final Filesystem fs;
  final String basePath;
}

/// Fetches and caches the models.dev catalog for opencode provider pickers.
///
/// opencode itself syncs its provider catalog from `https://models.dev/api.json`
/// (`packages/opencode/src/cli/cmd/providers.ts`). One fetch refreshes every
/// provider opencode can launch with (zen, go, openai, anthropic, google, …).
/// Falls back to the built-in static catalog (see `OpencodeCatalogSource`).
class OpencodeModelsService {
  OpencodeModelsService({
    @visibleForTesting Filesystem? fs,
    @visibleForTesting String? basePath,
    http.Client? httpClient,
    this.cacheTtl = const Duration(hours: 6),
  }) : _fsOverride = fs,
       _basePathOverride = basePath?.trim(),
       _httpClient = httpClient ?? http.Client();

  static const _modelsDevUrl = 'https://models.dev/api.json';
  static const _cacheKey = 'models';

  final Filesystem? _fsOverride;
  final String? _basePathOverride;
  final http.Client _httpClient;
  final Duration cacheTtl;

  OpencodeModelsCacheEntry? _memory;
  Future<void>? _inFlight;
  final _CatalogUpdatesNotifier _catalogUpdates = _CatalogUpdatesNotifier();
  String? _lastResolvedBasePath;

  Listenable get catalogUpdates => _catalogUpdates;

  List<String> modelIdsFor({String providerId = ''}) {
    final entry = _memory;
    if (entry == null) return const [];
    final ids = entry.modelsByProvider[providerId.trim()];
    if (ids == null) return const [];
    return List<String>.unmodifiable(ids);
  }

  Future<void> ensureLoaded({bool forceRefresh = false}) {
    if (!forceRefresh && _isFresh(_memory)) {
      return Future.value();
    }
    final existing = _inFlight;
    if (existing != null) return existing;
    final task = _load().whenComplete(() => _inFlight = null);
    _inFlight = task;
    return task;
  }

  Future<void> _load() async {
    final roots = await _resolveStorage();
    final disk = await _readDiskCache(roots);
    if (disk != null && _isFresh(disk)) {
      _memory = disk;
      _catalogUpdates.bump();
      return;
    }

    final fetched = await _fetchLive();
    if (fetched != null) {
      _memory = fetched;
      await _writeDiskCache(roots, fetched);
      _catalogUpdates.bump();
      return;
    }

    if (disk != null && _memory == null) {
      _memory = disk;
      _catalogUpdates.bump();
    }
  }

  Future<_ResolvedStorage> _resolveStorage() async {
    final fsOverride = _fsOverride;
    final basePathOverride = _basePathOverride;
    if (fsOverride != null && basePathOverride != null) {
      _syncMemoryForBasePath(basePathOverride);
      return _ResolvedStorage(fs: fsOverride, basePath: basePathOverride);
    }
    if (AppStorage.isInstalled) {
      final snap = AppStorage.context;
      _syncMemoryForBasePath(snap.teampilotRoot);
      return _ResolvedStorage(fs: snap.fs, basePath: snap.teampilotRoot);
    }
    _syncMemoryForBasePath(AppStorage.appDataRoot);
    return _ResolvedStorage(
      fs: AppStorage.fs,
      basePath: AppStorage.appDataRoot,
    );
  }

  void _syncMemoryForBasePath(String basePath) {
    if (_lastResolvedBasePath != null && _lastResolvedBasePath != basePath) {
      _memory = null;
    }
    _lastResolvedBasePath = basePath;
  }

  bool _isFresh(OpencodeModelsCacheEntry? entry) {
    if (entry == null || entry.modelsByProvider.isEmpty) return false;
    final age = DateTime.now().millisecondsSinceEpoch - entry.fetchedAtMs;
    return age >= 0 && age < cacheTtl.inMilliseconds;
  }

  String _cacheFilePath(_ResolvedStorage roots) => roots.fs.pathContext.join(
    roots.basePath,
    'cache',
    'opencode_models',
    '$_cacheKey.json',
  );

  Future<OpencodeModelsCacheEntry?> _readDiskCache(
    _ResolvedStorage roots,
  ) async {
    final path = _cacheFilePath(roots);
    final stat = await roots.fs.stat(path);
    if (!stat.isFile) return null;
    final text = await roots.fs.readString(path);
    if (text == null) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return OpencodeModelsCacheEntry.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _writeDiskCache(
    _ResolvedStorage roots,
    OpencodeModelsCacheEntry entry,
  ) async {
    final path = _cacheFilePath(roots);
    await roots.fs.ensureDir(roots.fs.pathContext.dirname(path));
    await roots.fs.writeString(path, jsonEncode(entry.toJson()));
  }

  Future<OpencodeModelsCacheEntry?> _fetchLive() async {
    try {
      final response = await _httpClient.get(Uri.parse(_modelsDevUrl));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final byProvider = <String, List<String>>{};
      for (final entry in decoded.entries) {
        final providerId = entry.key.toString().trim();
        if (providerId.isEmpty) continue;
        final provider = entry.value;
        if (provider is! Map) continue;
        final models = provider['models'];
        if (models is! Map) continue;
        final ids = models.keys
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (ids.isEmpty) continue;
        byProvider[providerId] = ids;
      }
      if (byProvider.isEmpty) return null;
      return OpencodeModelsCacheEntry(
        fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
        modelsByProvider: byProvider,
      );
    } on Object {
      return null;
    }
  }

  @visibleForTesting
  Future<void> writeCacheForTest(OpencodeModelsCacheEntry entry) async {
    _memory = entry;
    final roots = await _resolveStorage();
    await _writeDiskCache(roots, entry);
  }
}

class _CatalogUpdatesNotifier extends ChangeNotifier {
  void bump() => notifyListeners();
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter test test/services/provider/opencode/opencode_models_service_test.dart`
Expected: PASS（5 个用例）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/opencode/provider/opencode_models_service.dart \
        client/test/services/provider/opencode/opencode_models_service_test.dart
git commit -m "feat(opencode): add live models.dev catalog service

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: per-CLI 模型能力迁移 + live 升级

**Files:**
- Create: `client/lib/services/cli/opencode/provider/opencode_provider_model_capability.dart`
- Modify: `client/lib/services/cli/registry/capabilities/provider_model_capability.dart`（删第 4 行 import + 第 207-232 行 opencode 实现）
- Modify: `client/lib/services/cli/opencode/opencode_tool.dart`（import + 构造参数）
- Test: Modify `client/test/services/cli/registry/provider_model_capability_test.dart`（补 import、去 `const`）

**Interfaces:**
- Consumes: `OpencodeModelsService.modelIdsFor`（Task 2）、`OpencodeModelCatalog.knownModelsForProvider`、共享 `provider_model_capability.dart` 的接口/基类。
- Produces:
  - `class OpencodeCatalogSource implements ModelCatalogSource { const OpencodeCatalogSource(OpencodeModelsService? modelsService); }`（live 优先，空则静态回退）
  - `class OpencodeProviderModelCapability extends CatalogModelCapability implements RefreshableProviderModelCapability { OpencodeProviderModelCapability({OpencodeModelsService? modelsService}); }`

- [ ] **Step 1: 写失败测试**

Create `client/test/services/cli/opencode/provider/opencode_provider_model_capability_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_models_service.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_provider_model_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_model_capability.dart';

import '../../../../support/in_memory_filesystem.dart';

const _apiJson = '''
{"opencode": {"models": {"live-model-a": {}, "live-model-b": {}}}}
''';

void main() {
  test('uses live catalog when service loaded', () async {
    final fs = InMemoryFilesystem();
    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: MockClient((request) async => http.Response(_apiJson, 200)),
    );
    await service.ensureLoaded();

    // service is a runtime value, so the capability cannot be const here.
    final capability = OpencodeProviderModelCapability(modelsService: service);
    final models = capability.modelCandidates(
      provider: null,
      providerId: 'opencode',
      currentModel: '',
    );
    expect(models, containsAll(['live-model-a', 'live-model-b']));
  });

  test('falls back to static catalog without service', () {
    const capability = OpencodeProviderModelCapability();
    final models = capability.modelCandidates(
      provider: null,
      providerId: 'opencode',
      currentModel: '',
    );
    expect(models, contains('big-pickle'));
  });

  test('is refreshable and exposes picker mode', () {
    const capability = OpencodeProviderModelCapability();
    expect(capability, isA<RefreshableProviderModelCapability>());
    expect(
      capability.pickerMode(
        const AppProviderConfig(
          id: 'opencode',
          cli: CliTool.opencode,
          name: 'OpenCode',
        ),
      ),
      ProviderModelPickerMode.catalogWithCustomEntry,
    );
  });
}
```

注：`const capability = OpencodeProviderModelCapability(modelsService: service)` 中的 `service` 是运行时值 → 该行不能是 `const`，应为 `final capability = OpencodeProviderModelCapability(modelsService: service);`。测试里以 `final` 为准。

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/services/cli/opencode/provider/opencode_provider_model_capability_test.dart`
Expected: FAIL（新文件不存在，import 找不到）。

- [ ] **Step 3: 创建 per-CLI 能力文件**

Create `client/lib/services/cli/opencode/provider/opencode_provider_model_capability.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../../../models/app_provider_config.dart';
import '../../registry/capabilities/provider_model_capability.dart';
import 'opencode_model_catalog.dart';
import 'opencode_models_service.dart';

/// OpenCode model catalog from the live models.dev fetch, falling back to the
/// built-in static [OpencodeModelCatalog] (offline / first run before fetch).
final class OpencodeCatalogSource implements ModelCatalogSource {
  const OpencodeCatalogSource(this._modelsService);

  final OpencodeModelsService? _modelsService;

  @override
  List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) {
    final id = provider?.id ?? providerId;
    final live = _modelsService?.modelIdsFor(providerId: id) ?? const [];
    if (live.isNotEmpty) return live;
    return OpencodeModelCatalog.knownModelsForProvider(id);
  }
}

/// OpenCode's model picker capability with a live models.dev catalog.
final class OpencodeProviderModelCapability extends CatalogModelCapability
    implements RefreshableProviderModelCapability {
  OpencodeProviderModelCapability({OpencodeModelsService? modelsService})
    : _modelsService = modelsService;

  final OpencodeModelsService? _modelsService;

  @override
  bool get supportsModelTiers => false;

  @override
  List<ModelCatalogSource> get catalogSources => [
    OpencodeCatalogSource(_modelsService),
  ];

  @override
  Listenable get catalogUpdates =>
      _modelsService?.catalogUpdates ?? _emptyCatalogUpdates;

  @override
  Future<void> refreshModelCatalog({
    required String providerId,
    String? executable,
    bool forceRefresh = false,
  }) {
    final service = _modelsService;
    if (service == null) return Future.value();
    return service.ensureLoaded(forceRefresh: forceRefresh);
  }

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) =>
      ProviderModelPickerMode.catalogWithCustomEntry;
}

final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
```

- [ ] **Step 4: 从共享文件删除 opencode 实现**

在 `client/lib/services/cli/registry/capabilities/provider_model_capability.dart`：
- 删第 4 行 `import '../../opencode/provider/opencode_model_catalog.dart';`
- 删第 207-232 行（`OpencodeCatalogSource` + `OpencodeProviderModelCapability` 两个类的完整定义）。保留 `ProviderRecordModelCapability`。

- [ ] **Step 5: 更新 `opencode_tool.dart`**

`client/lib/services/cli/opencode/opencode_tool.dart`：
- 新增 import（与现有 `provider/opencode_provider_form_capability.dart` import 同类位置）：
  ```dart
  import 'provider/opencode_provider_model_capability.dart';
  ```
- 构造参数：把
  ```dart
      this.providerModel = const OpencodeProviderModelCapability(),
  ```
  改为
  ```dart
      OpencodeProviderModelCapability? providerModel,
  ```
  并把初始化列表改为（注意 `providerModel` 需排在前面）：
  ```dart
    }) : providerModel = providerModel ?? OpencodeProviderModelCapability(),
       providerCredential = providerCredential ?? OpencodeProviderCredentialCapability();
  ```
- 字段类型 `final ProviderModelCapability providerModel;` 保持不变。

- [ ] **Step 6: 更新既有测试**

`client/test/services/cli/registry/provider_model_capability_test.dart`：
- 新增 import：
  ```dart
  import 'package:teampilot/services/cli/opencode/provider/opencode_provider_model_capability.dart';
  ```
- 第 123、145 行的 `const OpencodeProviderModelCapability()` 改为 `OpencodeProviderModelCapability()`（去 `const`，新构造非 const）。

- [ ] **Step 7: 跑新增 + 既有测试**

Run: `cd client && flutter test test/services/cli/opencode/provider/opencode_provider_model_capability_test.dart test/services/cli/registry/provider_model_capability_test.dart`
Expected: PASS（3 个新用例 + 既有用例）。

- [ ] **Step 8: Commit**

```bash
git add client/lib/services/cli/opencode/provider/opencode_provider_model_capability.dart \
        client/lib/services/cli/opencode/provider/opencode_model_catalog.dart \
        client/lib/services/cli/registry/capabilities/provider_model_capability.dart \
        client/lib/services/cli/opencode/opencode_tool.dart \
        client/test/services/cli/opencode/provider/opencode_provider_model_capability_test.dart \
        client/test/services/cli/registry/provider_model_capability_test.dart
git commit -m "refactor(opencode): migrate model capability to per-CLI dir + live source

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Bootstrap 接线（`OpencodeBootstrapEntry` → registry → app shell）

**Files:**
- Modify: `client/lib/services/cli/opencode/opencode_bootstrap_entry.dart`
- Modify: `client/lib/services/cli/registry/built_in_cli_tools.dart`
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Consumes: `OpencodeModelsService`（Task 2）、`OpencodeProviderModelCapability`（Task 3）。
- Produces: 运行时 `CliToolRegistry.builtIn()` 的 opencode `ProviderModelCapability` 携带已注入的 service；picker 打开即触发 live refresh。

- [ ] **Step 1: 扩展 BootstrapEntry**

`client/lib/services/cli/opencode/opencode_bootstrap_entry.dart` 改为：

```dart
import '../registry/cli_bootstrap.dart';
import 'provider/opencode_models_service.dart';
import 'provider/opencode_provider_credentials_service.dart';

final class OpencodeBootstrapEntry implements CliBootstrapEntry {
  const OpencodeBootstrapEntry({
    required this.credentialsService,
    this.modelsService,
  });

  final OpencodeProviderCredentialsService credentialsService;
  final OpencodeModelsService? modelsService;
}
```

- [ ] **Step 2: registry 注入**

`client/lib/services/cli/registry/built_in_cli_tools.dart`：
- 新增 import：
  ```dart
  import '../../../services/cli/opencode/provider/opencode_provider_model_capability.dart';
  ```
- 把 `OpencodeCliTool(...)` 注册块改为：
  ```dart
    registry.register(
      OpencodeCliTool(
        providerModel: OpencodeProviderModelCapability(
          modelsService: opencodeEntry?.modelsService,
        ),
        providerCredential: OpencodeProviderCredentialCapability(
          credentials: opencodeEntry?.credentialsService,
        ),
      ),
    );
  ```

- [ ] **Step 3: app_shell 构造 service**

`client/lib/app/app_shell.dart`：
- 新增 import（放在第 156 行 `opencode_provider_credentials_service.dart` 附近）：
  ```dart
  import '../services/cli/opencode/provider/opencode_models_service.dart';
  ```
- 把 `CliBootstrap` map 里 opencode 条目（第 753-755 行）改为：
  ```dart
        CliTool.opencode: OpencodeBootstrapEntry(
          credentialsService: opencodeCredentialsService,
          modelsService: OpencodeModelsService(),
        ),
  ```

- [ ] **Step 4: 编译验证 + 注册断言**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无错误（`built-in registry registers ProviderModelCapability for every cli` 断言覆盖 opencode 注册）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/opencode/opencode_bootstrap_entry.dart \
        client/lib/services/cli/registry/built_in_cli_tools.dart \
        client/lib/app/app_shell.dart
git commit -m "feat(opencode): wire live models service through bootstrap

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: 静态回退清单刷新（zen 87 + go 24）

**Files:**
- Modify: `client/lib/services/cli/opencode/provider/opencode_model_catalog.dart`
- Test: Modify `client/test/services/cli/opencode/provider/opencode_provider_model_capability_test.dart`（加回退断言）

**Interfaces:**
- Consumes: `OpencodeModelCatalog.knownModelsForProvider`。
- Produces: `knownModelsForProvider('opencode-go')` 返回 24 个模型；`zen` 常量对齐实时目录 87 个。

- [ ] **Step 1: 写失败测试**

在 `client/test/services/cli/opencode/provider/opencode_provider_model_capability_test.dart` 追加用例（文件顶部加 `import 'package:teampilot/services/cli/opencode/provider/opencode_model_catalog.dart';`）：

```dart
  test('static fallback covers opencode-go and current zen ids', () {
    final go = OpencodeModelCatalog.knownModelsForProvider('opencode-go');
    expect(go, containsAll(['deepseek-v4-flash', 'qwen3.7-max', 'kimi-k3']));
    expect(go, hasLength(24));

    final zen = OpencodeModelCatalog.knownModelsForProvider('opencode');
    expect(zen, contains('claude-sonnet-5'));
    expect(zen, contains('gemini-3.6-flash'));
    expect(zen, hasLength(87));
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/services/cli/opencode/provider/opencode_provider_model_capability_test.dart`
Expected: FAIL（`opencode-go` 返回空、zen 长度不足）。

- [ ] **Step 3: 刷新静态清单**

把 `client/lib/services/cli/opencode/provider/opencode_model_catalog.dart` 的 `zen` 常量整体替换为（按实时 models.dev 目录，87 个）：

```dart
  static const zen = <String>[
    'big-pickle',
    'claude-3-5-haiku',
    'claude-fable-5',
    'claude-haiku-4-5',
    'claude-opus-4-1',
    'claude-opus-4-5',
    'claude-opus-4-6',
    'claude-opus-4-7',
    'claude-opus-4-8',
    'claude-opus-5',
    'claude-sonnet-4',
    'claude-sonnet-4-5',
    'claude-sonnet-4-6',
    'claude-sonnet-5',
    'deepseek-v4-flash',
    'deepseek-v4-flash-free',
    'deepseek-v4-pro',
    'gemini-3-flash',
    'gemini-3-pro',
    'gemini-3.1-pro',
    'gemini-3.5-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.6-flash',
    'glm-4.6',
    'glm-4.7',
    'glm-4.7-free',
    'glm-5',
    'glm-5-free',
    'glm-5.1',
    'glm-5.2',
    'gpt-5',
    'gpt-5-codex',
    'gpt-5-nano',
    'gpt-5.1',
    'gpt-5.1-codex',
    'gpt-5.1-codex-max',
    'gpt-5.1-codex-mini',
    'gpt-5.2',
    'gpt-5.2-codex',
    'gpt-5.3-codex',
    'gpt-5.3-codex-spark',
    'gpt-5.4',
    'gpt-5.4-mini',
    'gpt-5.4-nano',
    'gpt-5.4-pro',
    'gpt-5.5',
    'gpt-5.5-pro',
    'gpt-5.6-luna',
    'gpt-5.6-sol',
    'gpt-5.6-terra',
    'grok-4.5',
    'grok-build-0.1',
    'grok-code',
    'hy3-free',
    'hy3-preview-free',
    'kimi-k2',
    'kimi-k2-thinking',
    'kimi-k2.5',
    'kimi-k2.5-free',
    'kimi-k2.6',
    'kimi-k2.7-code',
    'kimi-k3',
    'laguna-s-2.1-free',
    'ling-2.6-flash-free',
    'ling-3.0-flash-free',
    'ling-3.0-tiny-free',
    'longcat-2.0-free',
    'mimo-v2-flash-free',
    'mimo-v2-omni-free',
    'mimo-v2-pro-free',
    'mimo-v2.5-free',
    'minimax-m2.1',
    'minimax-m2.1-free',
    'minimax-m2.5',
    'minimax-m2.5-free',
    'minimax-m2.7',
    'minimax-m3',
    'minimax-m3-free',
    'nemotron-3-super-free',
    'nemotron-3-ultra-free',
    'north-mini-code-free',
    'qwen3-coder',
    'qwen3.5-plus',
    'qwen3.6-plus',
    'qwen3.6-plus-free',
    'ring-2.6-1t-free',
    'trinity-large-preview-free',
  ];
```

在 `_byProviderId` 中增加 opencode-go 键（放在 `'opencode': zen,` 之后）：

```dart
    'opencode-go': [
      'deepseek-v4-flash',
      'deepseek-v4-pro',
      'glm-5',
      'glm-5.1',
      'glm-5.2',
      'gpt-5.6-luna',
      'grok-4.5',
      'hy3',
      'kimi-k2.5',
      'kimi-k2.6',
      'kimi-k2.7-code',
      'kimi-k3',
      'mimo-v2-omni',
      'mimo-v2-pro',
      'mimo-v2.5',
      'mimo-v2.5-pro',
      'minimax-m2.5',
      'minimax-m2.7',
      'minimax-m3',
      'qwen3.5-plus',
      'qwen3.6-plus',
      'qwen3.7-max',
      'qwen3.7-plus',
      'qwen3.8-max',
    ],
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter test test/services/cli/opencode/provider/opencode_provider_model_capability_test.dart`
Expected: PASS。

- [ ] **Step 5: 全量验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: 全绿。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/opencode/provider/opencode_model_catalog.dart \
        client/test/services/cli/opencode/provider/opencode_provider_model_capability_test.dart
git commit -m "feat(opencode): refresh static fallback catalog (zen 87, go 24)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## 验证（全部任务完成后）

1. `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` — 无错误。
2. `cd client && flutter test --exclude-tags integration` — 全绿。
3. 手动（可选）：`flutter run -d linux` → opencode provider 表单 → 添加 "OpenCode Go (subscription)" → 模型下拉出现实时模型；Zen 下拉出现全量。
