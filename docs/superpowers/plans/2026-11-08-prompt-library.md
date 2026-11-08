# 提示词管理（全局 / 工作区）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 增加全局与工作区两级的系统提示词库，并在会话启动时自动注入到所有支持 `PromptCapability` 的 CLI。

**Architecture:** 提示词定义分两份 JSON 存储（全局 `prompts/prompts.json`、工作区 `<workspace>/prompts.json`）。启动装配时由 `PromptLibraryResolver` 读取并过滤，`UserPromptContributionProvider` 转成 `PromptContribution`（`append`），经现有 `PromptAssembler` + `PromptCapability` 落盘。工作区通过 `ConfigBundle.disabledPromptIds` 单独关闭全局项。UI 复用 Hooks 的「全局管理页 + 工作区 section」模式。

**Tech Stack:** Flutter / Dart、flutter_bloc、go_router、shared_ui、InMemoryFilesystem 测试替身、`dart run tool/run_tests.dart`。

## Global Constraints

- 只改本计划列出的文件；仓库当前有大量**未提交的用户改动**，每次提交必须显式 `git add <具体文件>` 并用 `git commit -- <具体文件>`，禁止 `git add -A` / `git add .`。
- 永不直接跑 `flutter test`；统一 `cd client && dart run tool/run_tests.dart <paths>`。
- 改完代码先跑 `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`；全量测试只在最后跑一次（后台）。
- 用户可见文案只改 `client/lib/l10n/app_en.arb` 与 `app_zh.arb`；生成文件用 `flutter gen-l10n` 更新。
- 诊断日志用 `appLogger`（`package:teampilot/utils/logging/logger.dart`），禁止 `print`。
- 提示词内容按纯 Markdown 注入，不做变量展开。
- 每个 `PromptContribution` 的 `id` 必须是 `user-prompt:<definitionId>`，`mergeRole` 固定 `PromptMergeRole.append`。
- 生效范围：全局提示词对所有工作区生效（除非被 `disabledPromptIds` 关闭）；工作区提示词只在该工作区生效。

---

### Task 1: PromptDefinition 模型

**Files:**
- Create: `client/lib/models/prompt_definition.dart`
- Test: `client/test/models/prompt_definition_test.dart`

**Interfaces:**
- Produces: `PromptDefinition`（`id`, `name`, `description`, `content`, `enabled`, `order`, `createdAt`, `updatedAt`；`fromJson` / `toJson` / `copyWith` / `==` / `hashCode`）。

- [ ] **Step 1: 写失败测试**

创建 `client/test/models/prompt_definition_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/prompt_definition.dart';

void main() {
  final created = DateTime.utc(2026, 11, 8, 10);
  final updated = DateTime.utc(2026, 11, 8, 11);

  test('toJson/fromJson round-trips every field', () {
    final prompt = PromptDefinition(
      id: 'p1',
      name: 'Review rules',
      description: 'Team review baseline',
      content: '## Review\n- be strict',
      enabled: false,
      order: 3,
      createdAt: created,
      updatedAt: updated,
    );

    final decoded = PromptDefinition.fromJson(prompt.toJson());

    expect(decoded, prompt);
    expect(decoded.createdAt, created);
    expect(decoded.updatedAt, updated);
  });

  test('fromJson applies defaults for missing fields', () {
    final decoded = PromptDefinition.fromJson({'id': 'p1', 'name': 'A'});

    expect(decoded.description, '');
    expect(decoded.content, '');
    expect(decoded.enabled, isTrue);
    expect(decoded.order, 0);
    expect(decoded.createdAt, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    expect(decoded.updatedAt, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
  });

  test('copyWith preserves id and can flip enabled', () {
    final prompt = PromptDefinition(
      id: 'p1',
      name: 'A',
      content: 'body',
      createdAt: created,
      updatedAt: created,
    );

    final next = prompt.copyWith(enabled: false, name: 'B');

    expect(next.id, 'p1');
    expect(next.name, 'B');
    expect(next.enabled, isFalse);
    expect(next.content, 'body');
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run:

```bash
cd client
dart run tool/run_tests.dart test/models/prompt_definition_test.dart
```

Expected: FAIL，提示 `prompt_definition.dart` 不存在 / `PromptDefinition` 未定义。

- [ ] **Step 3: 实现模型**

创建 `client/lib/models/prompt_definition.dart`：

```dart
import 'package:flutter/foundation.dart';

/// 全局或工作区提示词库中的一条持久化定义。
///
/// 范围不写在模型里：全局库里的都是全局提示词，工作区 `prompts.json`
/// 里的都是工作区提示词。
@immutable
class PromptDefinition {
  const PromptDefinition({
    required this.id,
    required this.name,
    this.description = '',
    this.content = '',
    this.enabled = true,
    this.order = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PromptDefinition.fromJson(Map<String, Object?> json) {
    final createdAt = _parseDate(json['createdAt']);
    final updatedAt = _parseDate(json['updatedAt']);
    return PromptDefinition(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      description: json['description'] as String? ?? '',
      content: json['content'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      order: (json['order'] as num?)?.toInt() ?? 0,
      createdAt: createdAt ?? _epoch,
      updatedAt: updatedAt ?? createdAt ?? _epoch,
    );
  }

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static DateTime? _parseDate(Object? raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  final String id;
  final String name;
  final String description;
  final String content;
  final bool enabled;
  final int order;
  final DateTime createdAt;
  final DateTime updatedAt;

  PromptDefinition copyWith({
    String? name,
    String? description,
    String? content,
    bool? enabled,
    int? order,
    DateTime? updatedAt,
  }) {
    return PromptDefinition(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      content: content ?? this.content,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'content': content,
    'enabled': enabled,
    'order': order,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PromptDefinition &&
          other.id == id &&
          other.name == name &&
          other.description == description &&
          other.content == content &&
          other.enabled == enabled &&
          other.order == order &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    content,
    enabled,
    order,
    createdAt,
    updatedAt,
  );
}
```

- [ ] **Step 4: 运行确认通过**

Run:

```bash
cd client
dart run tool/run_tests.dart test/models/prompt_definition_test.dart
```

Expected: PASS（3 tests）。

- [ ] **Step 5: 提交**

```bash
git add client/lib/models/prompt_definition.dart client/test/models/prompt_definition_test.dart
git commit -m "feat(prompts): add PromptDefinition model" -- client/lib/models/prompt_definition.dart client/test/models/prompt_definition_test.dart
```

---

### Task 2: 存储路径 + PromptRepository

**Files:**
- Modify: `client/lib/services/storage/app_paths.dart`
- Modify: `client/lib/services/storage/workspace_layout.dart`
- Create: `client/lib/services/prompt/prompt_repository.dart`
- Test: `client/test/services/prompt/prompt_repository_test.dart`

**Interfaces:**
- Consumes: `PromptDefinition`（Task 1）。
- Produces: `AppPaths.promptsDirForTeampilotRoot(String root)`；`WorkspaceLayout.promptsFile(String workspaceId)`；`PromptRepository({required Filesystem fs, required String directory})`、`PromptRepository.global({required Filesystem fs, required String teampilotRoot})`、`PromptRepository.workspace({required Filesystem fs, required String workspaceDir})`、`loadAll()` / `load(id)` / `save(prompt)` / `delete(id)` / `PromptValidationException`。

- [ ] **Step 1: 写失败测试**

创建 `client/test/services/prompt/prompt_repository_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/prompt_definition.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/prompt/prompt_repository.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  final now = DateTime.utc(2026, 11, 8, 10);

  PromptDefinition prompt({
    String id = 'p1',
    String name = 'A',
    String content = 'body',
    bool enabled = true,
    int order = 0,
  }) => PromptDefinition(
    id: id,
    name: name,
    content: content,
    enabled: enabled,
    order: order,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() {
    fs = InMemoryFilesystem();
  });

  test('paths helpers resolve the documented locations', () {
    expect(AppPaths.promptsDirForTeampilotRoot('/tp'), '/tp/prompts');
    final layout = WorkspaceLayout(teampilotRoot: '/tp', fs: fs);
    expect(layout.promptsFile('w1'), '/tp/workspace/workspaces/w1/prompts.json');
  });

  test('loadAll returns empty when the file is missing', () async {
    final repo = PromptRepository.global(fs: fs, teampilotRoot: '/tp');
    expect(await repo.loadAll(), isEmpty);
  });

  test('save upserts and loadAll sorts by order then name', () async {
    final repo = PromptRepository.global(fs: fs, teampilotRoot: '/tp');
    await repo.save(prompt(id: 'b', name: 'B', order: 2));
    await repo.save(prompt(id: 'a', name: 'A', order: 2));
    await repo.save(prompt(id: 'z', name: 'Z', order: 1));
    await repo.save(prompt(id: 'a', name: 'A2', order: 2));

    final all = await repo.loadAll();

    expect(all.map((p) => p.id), ['z', 'a', 'b']);
    expect(all.firstWhere((p) => p.id == 'a').name, 'A2');
  });

  test('load returns a single prompt or null', () async {
    final repo = PromptRepository.global(fs: fs, teampilotRoot: '/tp');
    await repo.save(prompt());

    expect((await repo.load('p1'))?.id, 'p1');
    expect(await repo.load('missing'), isNull);
  });

  test('delete removes the prompt', () async {
    final repo = PromptRepository.global(fs: fs, teampilotRoot: '/tp');
    await repo.save(prompt());
    await repo.delete('p1');

    expect(await repo.loadAll(), isEmpty);
  });

  test('corrupt document degrades to empty', () async {
    await fs.ensureDir('/tp/prompts');
    await fs.writeString('/tp/prompts/prompts.json', 'not json');
    final repo = PromptRepository.global(fs: fs, teampilotRoot: '/tp');

    expect(await repo.loadAll(), isEmpty);
  });

  test('workspace repository uses the workspace directory', () async {
    final repo = PromptRepository.workspace(fs: fs, workspaceDir: '/tp/workspace/workspaces/w1');
    await repo.save(prompt());

    expect(await repo.load('p1'), isNotNull);
    expect(await fs.readString('/tp/workspace/workspaces/w1/prompts.json'), contains('"p1"'));
  });

  test('save rejects empty name or content', () async {
    final repo = PromptRepository.global(fs: fs, teampilotRoot: '/tp');

    await expectLater(
      repo.save(prompt(name: '  ')),
      throwsA(isA<PromptValidationException>()),
    );
    await expectLater(
      repo.save(prompt(content: '  ')),
      throwsA(isA<PromptValidationException>()),
    );
  });

  test('save trims name and content', () async {
    final repo = PromptRepository.global(fs: fs, teampilotRoot: '/tp');
    await repo.save(prompt(name: '  A  ', content: '  body  '));

    final saved = (await repo.load('p1'))!;
    expect(saved.name, 'A');
    expect(saved.content, 'body');
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run:

```bash
cd client
dart run tool/run_tests.dart test/services/prompt/prompt_repository_test.dart
```

Expected: FAIL，`prompt_repository.dart` / `promptsDirForTeampilotRoot` / `promptsFile` 未定义。

- [ ] **Step 3: 加路径 helper**

在 `client/lib/services/storage/app_paths.dart` 的 `skillsDirForTeampilotRoot` 附近加入：

```dart
  /// User prompt library (`prompts/prompts.json`).
  static String promptsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'prompts');
```

在 `client/lib/services/storage/workspace_layout.dart` 的 `projectConfigFile` 附近加入：

```dart
  /// Workspace-local prompt library.
  String promptsFile(String workspaceId) =>
      _ctx.join(workspaceDir(workspaceId), 'prompts.json');
```

- [ ] **Step 4: 实现仓储**

创建 `client/lib/services/prompt/prompt_repository.dart`：

```dart
import 'dart:convert';

import '../../models/prompt_definition.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import '../storage/app_paths.dart';

/// 提示词定义校验失败。
class PromptValidationException implements Exception {
  const PromptValidationException(this.code);

  final String code;

  @override
  String toString() => 'PromptValidationException($code)';
}

/// 单文档提示词库：`{directory}/prompts.json`。
///
/// 全局库用 [PromptRepository.global]，工作区库用
/// [PromptRepository.workspace]。
class PromptRepository {
  PromptRepository({required Filesystem fs, required String directory})
    : _fs = fs,
      _directory = directory;

  factory PromptRepository.global({
    required Filesystem fs,
    required String teampilotRoot,
  }) => PromptRepository(
    fs: fs,
    directory: AppPaths.promptsDirForTeampilotRoot(teampilotRoot),
  );

  factory PromptRepository.workspace({
    required Filesystem fs,
    required String workspaceDir,
  }) => PromptRepository(fs: fs, directory: workspaceDir);

  static const fileName = 'prompts.json';
  static const documentVersion = 1;

  final Filesystem _fs;
  final String _directory;

  String get _file => _fs.pathContext.join(_directory, fileName);

  Future<List<PromptDefinition>> loadAll() async {
    final raw = await _fs.readString(_file);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      final list = decoded['prompts'];
      if (list is! List) return const [];
      final prompts = <PromptDefinition>[];
      for (final item in list) {
        if (item is! Map) continue;
        final prompt = PromptDefinition.fromJson(
          item.cast<String, Object?>(),
        );
        if (prompt.id.isEmpty) continue;
        prompts.add(prompt);
      }
      prompts.sort(_compare);
      return List.unmodifiable(prompts);
    } on Object catch (error) {
      appLogger.w('[prompts] corrupt prompt library at $_file: $error');
      return const [];
    }
  }

  Future<PromptDefinition?> load(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    for (final prompt in await loadAll()) {
      if (prompt.id == trimmed) return prompt;
    }
    return null;
  }

  Future<void> save(PromptDefinition prompt) async {
    final normalized = _normalize(prompt);
    final prompts = List<PromptDefinition>.of(await loadAll());
    final index = prompts.indexWhere((item) => item.id == normalized.id);
    if (index < 0) {
      prompts.add(normalized);
    } else {
      prompts[index] = normalized;
    }
    prompts.sort(_compare);
    await _writeAll(prompts);
  }

  Future<void> delete(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final prompts = List<PromptDefinition>.of(await loadAll());
    final before = prompts.length;
    prompts.removeWhere((item) => item.id == trimmed);
    if (prompts.length == before) return;
    await _writeAll(prompts);
  }

  PromptDefinition _normalize(PromptDefinition prompt) {
    final id = prompt.id.trim();
    final name = prompt.name.trim();
    final content = prompt.content.trim();
    if (id.isEmpty) throw const PromptValidationException('prompt_id_empty');
    if (name.isEmpty) {
      throw const PromptValidationException('prompt_name_empty');
    }
    if (content.isEmpty) {
      throw const PromptValidationException('prompt_content_empty');
    }
    return PromptDefinition(
      id: id,
      name: name,
      description: prompt.description.trim(),
      content: content,
      enabled: prompt.enabled,
      order: prompt.order,
      createdAt: prompt.createdAt,
      updatedAt: prompt.updatedAt,
    );
  }

  Future<void> _writeAll(List<PromptDefinition> prompts) async {
    await _fs.ensureDir(_directory);
    final document = {
      'version': documentVersion,
      'prompts': [for (final prompt in prompts) prompt.toJson()],
    };
    await _fs.atomicWrite(
      _file,
      const JsonEncoder.withIndent('  ').convert(document),
    );
  }

  static int _compare(PromptDefinition a, PromptDefinition b) {
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (byName != 0) return byName;
    return a.id.compareTo(b.id);
  }
}
```

- [ ] **Step 5: 运行确认通过**

Run:

```bash
cd client
dart run tool/run_tests.dart test/services/prompt/prompt_repository_test.dart
```

Expected: PASS（9 tests）。

- [ ] **Step 6: 提交**

```bash
git add client/lib/services/storage/app_paths.dart client/lib/services/storage/workspace_layout.dart client/lib/services/prompt/prompt_repository.dart client/test/services/prompt/prompt_repository_test.dart
git commit -m "feat(prompts): add prompt storage and repository" -- client/lib/services/storage/app_paths.dart client/lib/services/storage/workspace_layout.dart client/lib/services/prompt/prompt_repository.dart client/test/services/prompt/prompt_repository_test.dart
```

---

### Task 3: PromptLibraryResolver（读取 + 过滤 + 分组）

**Files:**
- Create: `client/lib/services/prompt/prompt_library_resolver.dart`
- Test: `client/test/services/prompt/prompt_library_resolver_test.dart`

**Interfaces:**
- Consumes: `PromptRepository`（Task 2）、`PromptDefinition`（Task 1）。
- Produces: `PromptLibraryGroups`（`global` / `workspace` 两个 `List<PromptDefinition>`、`isEmpty`）、`PromptLibraryResolver({required Filesystem fs, required String teampilotRoot, required String workspaceDir, PromptRepository? globalRepository, PromptRepository? workspaceRepository})`、`resolve({Set<String> disabledGlobalIds = const {}})`。

- [ ] **Step 1: 写失败测试**

创建 `client/test/services/prompt/prompt_library_resolver_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/prompt_definition.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/prompt/prompt_library_resolver.dart';
import 'package:teampilot/services/prompt/prompt_repository.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late PromptRepository global;
  late PromptRepository workspace;
  late PromptLibraryResolver resolver;
  final now = DateTime.utc(2026, 11, 8, 10);

  PromptDefinition prompt(String id, {bool enabled = true, int order = 0}) =>
      PromptDefinition(
        id: id,
        name: id,
        content: 'body-$id',
        enabled: enabled,
        order: order,
        createdAt: now,
        updatedAt: now,
      );

  setUp(() {
    fs = InMemoryFilesystem();
    global = PromptRepository.global(fs: fs, teampilotRoot: '/tp');
    workspace = PromptRepository.workspace(
      fs: fs,
      workspaceDir: '/tp/workspace/workspaces/w1',
    );
    resolver = PromptLibraryResolver(
      fs: fs,
      teampilotRoot: '/tp',
      workspaceDir: '/tp/workspace/workspaces/w1',
      globalRepository: global,
      workspaceRepository: workspace,
    );
  });

  test('returns enabled global prompts minus disabled ids', () async {
    await global.save(prompt('g1'));
    await global.save(prompt('g2'));
    await global.save(prompt('off', enabled: false));

    final groups = await resolver.resolve(disabledGlobalIds: {'g2'});

    expect(groups.global.map((p) => p.id), ['g1']);
    expect(groups.workspace, isEmpty);
  });

  test('returns enabled workspace prompts', () async {
    await workspace.save(prompt('w1'));
    await workspace.save(prompt('off', enabled: false));

    final groups = await resolver.resolve();

    expect(groups.workspace.map((p) => p.id), ['w1']);
  });

  test('missing files resolve to empty groups', () async {
    final groups = await resolver.resolve();

    expect(groups.isEmpty, isTrue);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run:

```bash
cd client
dart run tool/run_tests.dart test/services/prompt/prompt_library_resolver_test.dart
```

Expected: FAIL（`prompt_library_resolver.dart` 不存在）。

- [ ] **Step 3: 实现 resolver**

创建 `client/lib/services/prompt/prompt_library_resolver.dart`：

```dart
import '../../models/prompt_definition.dart';
import '../io/filesystem.dart';
import 'prompt_repository.dart';

class PromptLibraryGroups {
  PromptLibraryGroups({
    Iterable<PromptDefinition> global = const [],
    Iterable<PromptDefinition> workspace = const [],
  }) : global = List.unmodifiable(global),
       workspace = List.unmodifiable(workspace);

  final List<PromptDefinition> global;
  final List<PromptDefinition> workspace;

  bool get isEmpty => global.isEmpty && workspace.isEmpty;
}

/// 读取全局 + 工作区提示词库，并按启用状态过滤。
class PromptLibraryResolver {
  PromptLibraryResolver({
    required Filesystem fs,
    required String teampilotRoot,
    required String workspaceDir,
    PromptRepository? globalRepository,
    PromptRepository? workspaceRepository,
  }) : _global =
           globalRepository ??
           PromptRepository.global(fs: fs, teampilotRoot: teampilotRoot),
       _workspace =
           workspaceRepository ??
           PromptRepository.workspace(fs: fs, workspaceDir: workspaceDir);

  final PromptRepository _global;
  final PromptRepository _workspace;

  Future<PromptLibraryGroups> resolve({
    Set<String> disabledGlobalIds = const {},
  }) async {
    final global = [
      for (final prompt in await _global.loadAll())
        if (prompt.enabled && !disabledGlobalIds.contains(prompt.id)) prompt,
    ];
    final workspace = [
      for (final prompt in await _workspace.loadAll())
        if (prompt.enabled) prompt,
    ];
    return PromptLibraryGroups(global: global, workspace: workspace);
  }
}
```

- [ ] **Step 4: 运行确认通过**

Run:

```bash
cd client
dart run tool/run_tests.dart test/services/prompt/prompt_library_resolver_test.dart
```

Expected: PASS（3 tests）。

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/prompt/prompt_library_resolver.dart client/test/services/prompt/prompt_library_resolver_test.dart
git commit -m "feat(prompts): resolve global and workspace prompt libraries" -- client/lib/services/prompt/prompt_library_resolver.dart client/test/services/prompt/prompt_library_resolver_test.dart
```

---

### Task 4: ConfigBundle.disabledPromptIds

**Files:**
- Modify: `client/lib/models/config_bundle.dart`
- Modify: `client/lib/services/chat/launch/staging/layered_config_bundle.dart`
- Test: `client/test/models/config_bundle_prompts_test.dart`

**Interfaces:**
- Consumes: 无。
- Produces: `ConfigBundle.disabledPromptIds`（参与 `fromJson` / `toJson` / `copyWith` / `==` / `hashCode`）；`LayeredConfigBundle.merge` 传播该字段。

- [ ] **Step 1: 写失败测试**

创建 `client/test/models/config_bundle_prompts_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/services/chat/launch/staging/layered_config_bundle.dart';

void main() {
  test('disabledPromptIds round-trips through JSON', () {
    const bundle = ConfigBundle(disabledPromptIds: ['g1', 'g2']);

    final decoded = ConfigBundle.fromJson(bundle.toJson());

    expect(decoded.disabledPromptIds, ['g1', 'g2']);
  });

  test('empty disabledPromptIds is omitted from JSON', () {
    expect(const ConfigBundle().toJson().containsKey('disabledPromptIds'), isFalse);
  });

  test('layered merge unions team, expert, workspace order', () {
    final merged = LayeredConfigBundle.merge(
      workspace: const ConfigBundle(disabledPromptIds: ['w1', 'g1']),
      expert: const ConfigBundle(disabledPromptIds: ['e1', 'g1']),
      team: const ConfigBundle(disabledPromptIds: ['t1']),
    );

    expect(merged.disabledPromptIds, ['t1', 'e1', 'w1', 'g1']);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run:

```bash
cd client
dart run tool/run_tests.dart test/models/config_bundle_prompts_test.dart
```

Expected: FAIL（`disabledPromptIds` 未定义）。

- [ ] **Step 3: 扩展 ConfigBundle**

编辑 `client/lib/models/config_bundle.dart`：

1. 构造函数加参数：

```dart
  const ConfigBundle({
    this.skillIds = const [],
    this.pluginIds = const [],
    this.mcpServerIds = const [],
    this.hookIds = const [],
    this.disabledPromptIds = const [],
  });
```

2. `fromJson` 加：

```dart
    disabledPromptIds: _decodeIds(json['disabledPromptIds']),
```

3. 字段：

```dart
  /// 全局提示词在本工作区被关闭的 id 列表。
  final List<String> disabledPromptIds;
```

4. `copyWith` 加参数与赋值：

```dart
    List<String>? disabledPromptIds,
```

```dart
    disabledPromptIds: disabledPromptIds ?? this.disabledPromptIds,
```

5. `toJson` 加：

```dart
    if (disabledPromptIds.isNotEmpty)
      'disabledPromptIds': disabledPromptIds,
```

6. `==` 加：

```dart
          listEquals(disabledPromptIds, other.disabledPromptIds) &&
```

7. `hashCode` 加：

```dart
    Object.hashAll(disabledPromptIds),
```

- [ ] **Step 4: 扩展 LayeredConfigBundle**

编辑 `client/lib/services/chat/launch/staging/layered_config_bundle.dart` 的 `merge`：

```dart
    return ConfigBundle(
      skillIds: _mergeIds(workspace.skillIds, expert?.skillIds, team?.skillIds),
      pluginIds: _mergeIds(
        workspace.pluginIds,
        expert?.pluginIds,
        team?.pluginIds,
      ),
      mcpServerIds: _mergeIds(
        workspace.mcpServerIds,
        expert?.mcpServerIds,
        team?.mcpServerIds,
      ),
      hookIds: _mergeIds(workspace.hookIds, expert?.hookIds, team?.hookIds),
      disabledPromptIds: _mergeIds(
        workspace.disabledPromptIds,
        expert?.disabledPromptIds,
        team?.disabledPromptIds,
      ),
    );
```

- [ ] **Step 5: 运行确认通过**

Run:

```bash
cd client
dart run tool/run_tests.dart test/models/config_bundle_prompts_test.dart
```

Expected: PASS（3 tests）。

- [ ] **Step 6: 提交**

```bash
git add client/lib/models/config_bundle.dart client/lib/services/chat/launch/staging/layered_config_bundle.dart client/test/models/config_bundle_prompts_test.dart
git commit -m "feat(prompts): carry disabledPromptIds in ConfigBundle" -- client/lib/models/config_bundle.dart client/lib/services/chat/launch/staging/layered_config_bundle.dart client/test/models/config_bundle_prompts_test.dart
```

---

### Task 5: UserPromptContributionProvider

**Files:**
- Create: `client/lib/services/resource/providers/user_prompt_contribution_provider.dart`
- Test: `client/test/services/resource/providers/user_prompt_contribution_provider_test.dart`

**Interfaces:**
- Consumes: `PromptDefinition`（Task 1）。
- Produces: `UserPromptContributionProvider({Iterable<PromptDefinition> globalPrompts = const [], Iterable<PromptDefinition> workspacePrompts = const []})`，`providerId == 'user-prompts'`。

- [ ] **Step 1: 写失败测试**

创建 `client/test/services/resource/providers/user_prompt_contribution_provider_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/prompt_definition.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/resource/assemblers/prompt_assembler.dart';
import 'package:teampilot/services/resource/contribution/prompt_document.dart';
import 'package:teampilot/services/resource/providers/prompt_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/user_prompt_contribution_provider.dart';

void main() {
  final now = DateTime.utc(2026, 11, 8, 10);

  PromptDefinition prompt(String id, String content) => PromptDefinition(
    id: id,
    name: 'Name $id',
    content: content,
    createdAt: now,
    updatedAt: now,
  );

  PromptProviderContext context() => PromptProviderContext(cli: CliTool.claude);

  test('emits global then workspace contributions as append sections', () async {
    final provider = UserPromptContributionProvider(
      globalPrompts: [prompt('g1', 'global body')],
      workspacePrompts: [prompt('w1', 'workspace body')],
    );

    final result = await const PromptAssembler().assemble(
      context: context(),
      providers: [provider],
    );

    expect(result.document.contributions.map((c) => c.id), [
      'user-prompt:g1',
      'user-prompt:w1',
    ]);
    expect(result.document.contributions.map((c) => c.scope), [
      PromptScope.global,
      PromptScope.workspace,
    ]);
    expect(
      result.document.contributions.map((c) => c.mergeRole),
      [PromptMergeRole.append, PromptMergeRole.append],
    );
    expect(result.document.content, 'global body\n\nworkspace body');
  });

  test('skips empty content and reports a warning diagnostic', () async {
    final provider = UserPromptContributionProvider(
      globalPrompts: [prompt('g1', '')],
      workspacePrompts: [prompt('w1', 'ok')],
    );

    final result = await const PromptAssembler().assemble(
      context: context(),
      providers: [provider],
    );

    expect(result.document.contributions.map((c) => c.id), ['user-prompt:w1']);
    expect(
      result.assembly.diagnostics.where(
        (d) => d.severity.name == 'warning',
      ),
      isNotEmpty,
    );
  });

  test('skips empty ids', () async {
    final provider = UserPromptContributionProvider(
      globalPrompts: [prompt('  ', 'body')],
    );

    final result = await const PromptAssembler().assemble(
      context: context(),
      providers: [provider],
    );

    expect(result.document.contributions, isEmpty);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run:

```bash
cd client
dart run tool/run_tests.dart test/services/resource/providers/user_prompt_contribution_provider_test.dart
```

Expected: FAIL（provider 文件不存在）。

- [ ] **Step 3: 实现 provider**

创建 `client/lib/services/resource/providers/user_prompt_contribution_provider.dart`：

```dart
import 'dart:async';

import '../../../models/prompt_definition.dart';
import '../contribution/prompt_document.dart';
import '../contribution/resource_assembly_error.dart';
import '../contribution/resource_origin.dart';
import 'prompt_contribution_provider.dart';

/// 把用户提示词库转成目标无关的 [PromptContribution]。
///
/// 每个提示词独立成 section（`append`），不会和 CLI 内置内容发生 replace
/// 冲突；顺序固定为全局在前、工作区在后。
final class UserPromptContributionProvider
    implements PromptContributionProvider {
  UserPromptContributionProvider({
    Iterable<PromptDefinition> globalPrompts = const [],
    Iterable<PromptDefinition> workspacePrompts = const [],
  }) : globalPrompts = List.unmodifiable(globalPrompts),
       workspacePrompts = List.unmodifiable(workspacePrompts);

  final List<PromptDefinition> globalPrompts;
  final List<PromptDefinition> workspacePrompts;
  List<ResourceAssemblyDiagnostic> _diagnostics = const [];

  @override
  String get providerId => 'user-prompts';

  @override
  FutureOr<Iterable<PromptContribution>> provide(
    PromptProviderContext context,
  ) {
    final diagnostics = <ResourceAssemblyDiagnostic>[];
    final contributions = <PromptContribution>[];

    void add(
      Iterable<PromptDefinition> prompts,
      PromptScope scope,
      ResourceOriginKind kind,
    ) {
      final seen = <String>{};
      for (final prompt in prompts) {
        final id = prompt.id.trim();
        final content = prompt.content.trim();
        if (id.isEmpty) {
          diagnostics.add(
            _warning(context, prompt.id, 'Prompt id is empty; skipped.'),
          );
          continue;
        }
        if (content.isEmpty) {
          diagnostics.add(
            _warning(context, id, 'Prompt $id has empty content; skipped.'),
          );
          continue;
        }
        if (!seen.add(id)) {
          diagnostics.add(
            _warning(context, id, 'Duplicate prompt id $id; skipped.'),
          );
          continue;
        }
        contributions.add(
          PromptContribution(
            id: 'user-prompt:$id',
            title: prompt.name.trim().isEmpty ? id : prompt.name.trim(),
            content: content,
            scope: scope,
            mergeRole: PromptMergeRole.append,
            origin: ContributionOrigin(
              providerId: providerId,
              kind: kind,
              sourceId: id,
            ),
          ),
        );
      }
    }

    add(globalPrompts, PromptScope.global, ResourceOriginKind.managed);
    add(workspacePrompts, PromptScope.workspace, ResourceOriginKind.workspace);
    _diagnostics = List.unmodifiable(diagnostics);
    return List.unmodifiable(contributions);
  }

  ResourceAssemblyDiagnostic _warning(
    PromptProviderContext context,
    String sourceId,
    String message,
  ) => ResourceAssemblyDiagnostic(
    severity: ResourceAssemblyDiagnosticSeverity.warning,
    resourceKind: ResourceContributionKind.prompt,
    cli: context.cli,
    providerId: providerId,
    sourceId: sourceId,
    message: message,
  );
}
```

- [ ] **Step 4: 运行确认通过**

Run:

```bash
cd client
dart run tool/run_tests.dart test/services/resource/providers/user_prompt_contribution_provider_test.dart
```

Expected: PASS（3 tests）。

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/resource/providers/user_prompt_contribution_provider.dart client/test/services/resource/providers/user_prompt_contribution_provider_test.dart
git commit -m "feat(prompts): add user prompt contribution provider" -- client/lib/services/resource/providers/user_prompt_contribution_provider.dart client/test/services/resource/providers/user_prompt_contribution_provider_test.dart
```

---

### Task 6: 接入 ConfigProfileService

**Files:**
- Create: `client/lib/services/resource/providers/user_prompt_library_factory.dart`
- Modify: `client/lib/services/chat/launch/config_profile_service.dart`
- Test: `client/test/services/resource/providers/user_prompt_library_factory_test.dart`
- Test: `client/test/services/resource/user_prompt_provisioning_test.dart`

**Interfaces:**
- Consumes: `PromptLibraryResolver`（Task 3）、`UserPromptContributionProvider`（Task 5）、`ConfigBundle.disabledPromptIds`（Task 4）。
- Produces: `userPromptProvidersForLaunch({required Filesystem fs, required String teampilotRoot, required String workspaceDir, required Iterable<String> disabledPromptIds}) → Future<List<PromptContributionProvider>>`。

- [ ] **Step 1: 写失败测试（工厂）**

创建 `client/test/services/resource/providers/user_prompt_library_factory_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/prompt_definition.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/prompt/prompt_repository.dart';
import 'package:teampilot/services/resource/assemblers/prompt_assembler.dart';
import 'package:teampilot/services/resource/providers/prompt_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/user_prompt_library_factory.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  final now = DateTime.utc(2026, 11, 8, 10);

  PromptDefinition prompt(String id, {bool enabled = true}) => PromptDefinition(
    id: id,
    name: id,
    content: 'body-$id',
    enabled: enabled,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() {
    fs = InMemoryFilesystem();
  });

  test('builds providers from enabled global and workspace prompts', () async {
    final global = PromptRepository.global(fs: fs, teampilotRoot: '/tp');
    final workspace = PromptRepository.workspace(
      fs: fs,
      workspaceDir: '/tp/workspace/workspaces/w1',
    );
    await global.save(prompt('g1'));
    await global.save(prompt('g2'));
    await workspace.save(prompt('w1'));

    final providers = await userPromptProvidersForLaunch(
      fs: fs,
      teampilotRoot: '/tp',
      workspaceDir: '/tp/workspace/workspaces/w1',
      disabledPromptIds: const ['g2'],
    );

    expect(providers, hasLength(1));

    final result = await const PromptAssembler().assemble(
      context: PromptProviderContext(cli: CliTool.claude),
      providers: providers,
    );
    expect(result.document.contributions.map((c) => c.id), [
      'user-prompt:g1',
      'user-prompt:w1',
    ]);
  });

  test('returns an empty list when nothing is enabled', () async {
    final providers = await userPromptProvidersForLaunch(
      fs: fs,
      teampilotRoot: '/tp',
      workspaceDir: '/tp/workspace/workspaces/w1',
      disabledPromptIds: const [],
    );

    expect(providers, isEmpty);
  });
}
```

- [ ] **Step 2: 写物化集成测试**

创建 `client/test/services/resource/user_prompt_provisioning_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/prompt_definition.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/config_profile/config_profile_scope.dart';
import 'package:teampilot/services/resource/cli_resource_provisioner.dart';
import 'package:teampilot/services/resource/providers/user_prompt_contribution_provider.dart';
import 'package:teampilot/services/resource/resource_provider_set.dart';
import 'package:teampilot/services/resource/resource_scope.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/cursor_lifecycle_test_paths.dart';
import '../../../support/in_memory_filesystem.dart';

void main() {
  final now = DateTime.utc(2026, 11, 8, 10);

  PromptDefinition prompt(String id, String content) => PromptDefinition(
    id: id,
    name: id,
    content: content,
    createdAt: now,
    updatedAt: now,
  );

  test('user prompt provider materializes into the CLI prompt file', () async {
    final fs = InMemoryFilesystem();
    final layout = RuntimeLayout(teampilotRoot: '/data/tp', fs: fs);
    final paths = CursorLifecycleTestPaths(fs: fs, layout: layout);
    const scope = LaunchProfileScope(
      workspaceId: 'w',
      teamId: 't',
      sessionId: 's',
      cliTeamName: 's',
    );

    final report = await CliResourceProvisioner(
      fs: fs,
      registry: CliToolRegistry.builtIn(),
    ).provision(
      CliResourceProvisionContext(
        cli: CliTool.opencode,
        scope: WorkspaceResourceScope(bundle: const ConfigBundle()),
        runtimeBundle: const ConfigBundle(),
        fs: fs,
        layout: layout,
        configDir: '/data/tp/config/opencode',
        resourceProviders: ResourceProviderSet(
          prompts: [
            UserPromptContributionProvider(
              globalPrompts: [prompt('g1', 'global body')],
              workspacePrompts: [prompt('w1', 'workspace body')],
            ),
          ],
        ),
        paths: paths,
        launchScope: scope,
      ),
    );

    expect(report.promptMaterialization?.written, isTrue);
    final toolDir = paths.sessionToolDir('w', 's', 'opencode');
    final body = await fs.readString(
      fs.pathContext.join(toolDir, 'AGENTS.md'),
    );
    expect(body, contains('global body'));
    expect(body, contains('workspace body'));
    expect(
      body!.indexOf('global body'),
      lessThan(body.indexOf('workspace body')),
    );
  });
}
```

- [ ] **Step 3: 运行确认工厂测试失败**

Run:

```bash
cd client
dart run tool/run_tests.dart test/services/resource/providers/user_prompt_library_factory_test.dart
```

Expected: FAIL（`user_prompt_library_factory.dart` 不存在）。

- [ ] **Step 4: 实现工厂**

创建 `client/lib/services/resource/providers/user_prompt_library_factory.dart`：

```dart
import '../../io/filesystem.dart';
import '../../prompt/prompt_library_resolver.dart';
import 'prompt_contribution_provider.dart';
import 'user_prompt_contribution_provider.dart';

/// 读取全局 + 工作区提示词库，返回可直接注入资源装配的 provider 列表。
Future<List<PromptContributionProvider>> userPromptProvidersForLaunch({
  required Filesystem fs,
  required String teampilotRoot,
  required String workspaceDir,
  required Iterable<String> disabledPromptIds,
}) async {
  final groups = await PromptLibraryResolver(
    fs: fs,
    teampilotRoot: teampilotRoot,
    workspaceDir: workspaceDir,
  ).resolve(disabledGlobalIds: disabledPromptIds.toSet());
  if (groups.isEmpty) return const [];
  return [
    UserPromptContributionProvider(
      globalPrompts: groups.global,
      workspacePrompts: groups.workspace,
    ),
  ];
}
```

- [ ] **Step 5: 运行工厂测试通过**

Run:

```bash
cd client
dart run tool/run_tests.dart test/services/resource/providers/user_prompt_library_factory_test.dart test/services/resource/user_prompt_provisioning_test.dart
```

Expected: PASS（3 tests）。

- [ ] **Step 6: 接入 ConfigProfileService**

在 `client/lib/services/chat/launch/config_profile_service.dart` 顶部 import 区加入：

```dart
import '../../resource/providers/user_prompt_library_factory.dart';
```

在 `prepareSimpleSessionLaunch` 的 `final report = await _provisionStagedResources(` 之前插入：

```dart
      final userPromptProviders = await userPromptProvidersForLaunch(
        fs: catalog.fs,
        teampilotRoot: catalog.basePath,
        workspaceDir: catalog.layout.workspace.workspaceDir(trimmedWorkspaceId),
        disabledPromptIds: runtimeBundle.disabledPromptIds,
      );
```

把该处的 prompts 列表改为：

```dart
            prompts: [
              ...providers.prompts,
              ...userPromptProviders,
              ...injectedResourceProviders.prompts,
            ],
```

在 `stageTeamLaunch` 的 `final resourceReport = await _provisionStagedResources(` 之前插入：

```dart
    final userPromptProviders = await userPromptProvidersForLaunch(
      fs: catalog.fs,
      teampilotRoot: catalog.basePath,
      workspaceDir: catalog.layout.workspace.workspaceDir(trimmedWorkspaceId),
      disabledPromptIds: runtimeBundle.disabledPromptIds,
    );
```

把该处的 prompts 列表改为：

```dart
          prompts: [
            ...providers.prompts,
            ...userPromptProviders,
          ],
```

- [ ] **Step 7: 运行针对性测试与静态检查**

Run:

```bash
cd client
dart run tool/run_tests.dart test/services/resource/user_prompt_provisioning_test.dart test/services/resource/providers/user_prompt_contribution_provider_test.dart test/services/resource/providers/user_prompt_library_factory_test.dart test/services/prompt
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: PASS；analyze 无新增问题。

- [ ] **Step 8: 提交**

```bash
git add client/lib/services/resource/providers/user_prompt_library_factory.dart client/lib/services/chat/launch/config_profile_service.dart client/test/services/resource/user_prompt_provisioning_test.dart client/test/services/resource/providers/user_prompt_library_factory_test.dart
git commit -m "feat(prompts): inject user prompt library at launch" -- client/lib/services/resource/providers/user_prompt_library_factory.dart client/lib/services/chat/launch/config_profile_service.dart client/test/services/resource/user_prompt_provisioning_test.dart client/test/services/resource/providers/user_prompt_library_factory_test.dart
```

---

### Task 7: PromptCubit / WorkspacePromptCubit + AppShell DI

**Files:**
- Create: `client/lib/cubits/prompt_cubit.dart`
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/main.dart`
- Test: `client/test/services/prompt/prompt_cubit_test.dart`

**Interfaces:**
- Consumes: `PromptRepository`（Task 2）、`PromptDefinition`（Task 1）。
- Produces: `PromptLibraryState`（`loading`, `prompts`, `errorMessage`）；`PromptCubit`（`load` / `upsert` / `remove` / `setEnabled`）；`WorkspacePromptCubit extends PromptCubit`（仅用于类型区分，行为相同）。

- [ ] **Step 1: 写失败测试**

创建 `client/test/services/prompt/prompt_cubit_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/prompt_cubit.dart';
import 'package:teampilot/models/prompt_definition.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/prompt/prompt_repository.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late PromptRepository repository;
  late PromptCubit cubit;
  final now = DateTime.utc(2026, 11, 8, 10);

  PromptDefinition prompt(String id, {bool enabled = true}) =>
      PromptDefinition(
        id: id,
        name: id,
        content: 'body-$id',
        enabled: enabled,
        createdAt: now,
        updatedAt: now,
      );

  setUp(() {
    fs = InMemoryFilesystem();
    repository = PromptRepository.global(fs: fs, teampilotRoot: '/tp');
    cubit = PromptCubit(repository: repository);
  });

  tearDown(() => cubit.close());

  test('load populates sorted prompts', () async {
    await repository.save(prompt('b'));
    await repository.save(prompt('a'));

    await cubit.load();

    expect(cubit.state.loading, isFalse);
    expect(cubit.state.prompts.map((p) => p.id), ['a', 'b']);
  });

  test('upsert and remove write through the repository', () async {
    expect(await cubit.upsert(prompt('a')), isTrue);
    expect(cubit.state.prompts.map((p) => p.id), ['a']);

    expect(await cubit.remove('a'), isTrue);
    expect(cubit.state.prompts, isEmpty);
  });

  test('setEnabled toggles and persists', () async {
    await cubit.upsert(prompt('a'));

    expect(await cubit.setEnabled('a', false), isTrue);

    expect(cubit.state.prompts.single.enabled, isFalse);
    expect((await repository.load('a'))!.enabled, isFalse);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run:

```bash
cd client
dart run tool/run_tests.dart test/services/prompt/prompt_cubit_test.dart
```

Expected: FAIL（`prompt_cubit.dart` 不存在）。

- [ ] **Step 3: 实现 cubit**

创建 `client/lib/cubits/prompt_cubit.dart`：

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/prompt_definition.dart';
import '../services/prompt/prompt_repository.dart';

class PromptLibraryState extends Equatable {
  const PromptLibraryState({
    this.loading = false,
    this.prompts = const [],
    this.errorMessage,
  });

  final bool loading;
  final List<PromptDefinition> prompts;
  final String? errorMessage;

  @override
  List<Object?> get props => [loading, prompts, errorMessage];
}

class PromptCubit extends Cubit<PromptLibraryState> {
  PromptCubit({required PromptRepository repository})
    : _repository = repository,
      super(const PromptLibraryState());

  final PromptRepository _repository;

  Future<void> load() async {
    emit(const PromptLibraryState(loading: true));
    try {
      emit(PromptLibraryState(prompts: await _repository.loadAll()));
    } on Object catch (error) {
      emit(PromptLibraryState(errorMessage: error.toString()));
    }
  }

  Future<bool> upsert(PromptDefinition prompt) async {
    try {
      await _repository.save(prompt);
      await load();
      return true;
    } on Object catch (error) {
      emit(PromptLibraryState(errorMessage: error.toString()));
      return false;
    }
  }

  Future<bool> remove(String id) async {
    try {
      await _repository.delete(id);
      await load();
      return true;
    } on Object catch (error) {
      emit(PromptLibraryState(errorMessage: error.toString()));
      return false;
    }
  }

  Future<bool> setEnabled(String id, bool enabled) async {
    final current = await _repository.load(id);
    if (current == null) return false;
    return upsert(
      current.copyWith(enabled: enabled, updatedAt: DateTime.now().toUtc()),
    );
  }
}

/// 工作区提示词库使用同一个状态机，仅用类型区分全局实例。
class WorkspacePromptCubit extends PromptCubit {
  WorkspacePromptCubit({required super.repository});
}
```

- [ ] **Step 4: 运行确认通过**

Run:

```bash
cd client
dart run tool/run_tests.dart test/services/prompt/prompt_cubit_test.dart
```

Expected: PASS（3 tests）。

- [ ] **Step 5: 接入 AppShell**

编辑 `client/lib/app/app_shell.dart`：

1. 顶部 import 区加：

```dart
import '../cubits/prompt_cubit.dart';
import '../services/prompt/prompt_repository.dart';
```

2. 构造函数参数列表（`required this.hookCubit,` 附近）加：

```dart
    required this.promptCubit,
    required this.promptRepository,
```

3. 字段区（`final HookCubit hookCubit;` 附近）加：

```dart
  final PromptCubit promptCubit;
  final PromptRepository promptRepository;
```

4. `late final` 区（`late final HookCubit hookCubit;` 附近）加：

```dart
  late final PromptCubit promptCubit;
  late final PromptRepository promptRepository;
```

5. `hookRepository = HookRepository(...)` 之后加：

```dart
    promptRepository = PromptRepository.global(
      fs: homeStorage.fs,
      teampilotRoot: homeStorage.paths.basePath,
    );
```

6. `hookCubit = HookCubit(...)..load();` 之后加：

```dart
    promptCubit = PromptCubit(repository: promptRepository)..load();
```

7. `AppShell(...)` 调用处（`hookCubit: hookCubit,` 附近）加：

```dart
      promptCubit: promptCubit,
      promptRepository: promptRepository,
```

- [ ] **Step 6: 接入 main.dart 的 BlocProvider / RepositoryProvider**

在 `client/lib/main.dart` 中：

1. `BlocProvider.value(value: shell.hookCubit),` 之后加：

```dart
                    BlocProvider.value(value: shell.promptCubit),
```

2. `RepositoryProvider<HookRepository>.value(...)` 之后加：

```dart
                  RepositoryProvider<PromptRepository>.value(
                    value: shell.promptRepository,
                  ),
```

并在 import 区加入：

```dart
import 'services/prompt/prompt_repository.dart';
```

- [ ] **Step 7: 静态检查**

Run:

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: No issues found（或仅存量无关 warning）。

- [ ] **Step 8: 提交**

```bash
git add client/lib/cubits/prompt_cubit.dart client/lib/app/app_shell.dart client/lib/main.dart client/test/services/prompt/prompt_cubit_test.dart
git commit -m "feat(prompts): add prompt cubit and app shell wiring" -- client/lib/cubits/prompt_cubit.dart client/lib/app/app_shell.dart client/lib/main.dart client/test/services/prompt/prompt_cubit_test.dart
```

---

### Task 8: 全局提示词管理页 + 路由 + 侧边栏 + l10n

**Files:**
- Create: `client/lib/pages/prompts/prompt_editor_dialog.dart`
- Create: `client/lib/pages/prompts/prompt_management_page.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_global_section.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_sidebar.dart`
- Modify: `client/lib/router/app_router.dart`
- Modify: `client/lib/utils/ui/app_keys.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Regenerate: `client/lib/l10n/app_localizations*.dart`（`flutter gen-l10n`）
- Test: `client/test/pages/prompts/prompt_management_page_test.dart`

**Interfaces:**
- Consumes: `PromptCubit`（Task 7）、`PromptDefinition`（Task 1）。
- Produces: `PromptManagementPage({bool embedded = false})`、`showPromptEditorDialog(BuildContext, {required PromptCubit cubit, PromptDefinition? prompt, int nextOrder = 0})`；`HomeGlobalView.prompts`；`/prompts` 路由。

- [ ] **Step 1: 加 l10n key**

在 `client/lib/l10n/app_en.arb` 末尾（最后一个 key 之后）加入：

```json
  "promptNavTitle": "Prompts",
  "promptInstalledCount": "{count} prompts",
  "@promptInstalledCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "promptNew": "New prompt",
  "promptEdit": "Edit prompt",
  "promptDelete": "Delete prompt",
  "promptName": "Name",
  "promptDescription": "Description",
  "promptContent": "Prompt content",
  "promptEnabled": "Enabled",
  "promptNameRequired": "Name is required.",
  "promptContentRequired": "Prompt content is required.",
  "promptSave": "Save",
  "promptCancel": "Cancel",
  "promptNoPrompts": "No prompts yet",
  "promptNoPromptsHint": "Create a prompt to inject it into new agent sessions.",
  "promptSaveFailed": "Could not save the prompt.",
  "promptDeleteFailed": "Could not delete the prompt.",
  "promptGlobalScope": "Global",
  "promptWorkspaceScope": "Workspace"
```

在 `client/lib/l10n/app_zh.arb` 末尾加入：

```json
  "promptNavTitle": "提示词",
  "promptInstalledCount": "{count} 条提示词",
  "@promptInstalledCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "promptNew": "新建提示词",
  "promptEdit": "编辑提示词",
  "promptDelete": "删除提示词",
  "promptName": "名称",
  "promptDescription": "描述",
  "promptContent": "提示词内容",
  "promptEnabled": "启用",
  "promptNameRequired": "名称不能为空。",
  "promptContentRequired": "提示词内容不能为空。",
  "promptSave": "保存",
  "promptCancel": "取消",
  "promptNoPrompts": "暂无提示词",
  "promptNoPromptsHint": "创建提示词，自动注入新会话。",
  "promptSaveFailed": "保存提示词失败。",
  "promptDeleteFailed": "删除提示词失败。",
  "promptGlobalScope": "全局",
  "promptWorkspaceScope": "工作区"
```

Run:

```bash
cd client
flutter gen-l10n
```

Expected: 生成/更新 `lib/l10n/app_localizations.dart` 等文件，无报错。

- [ ] **Step 2: 写失败测试**

创建 `client/test/pages/prompts/prompt_management_page_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/prompt_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/prompt_definition.dart';
import 'package:teampilot/pages/prompts/prompt_management_page.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/prompt/prompt_repository.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late PromptRepository repository;
  late PromptCubit cubit;
  final now = DateTime.utc(2026, 11, 8, 10);

  PromptDefinition prompt(String id, String name) => PromptDefinition(
    id: id,
    name: name,
    content: 'body-$id',
    createdAt: now,
    updatedAt: now,
  );

  setUp(() {
    fs = InMemoryFilesystem();
    repository = PromptRepository.global(fs: fs, teampilotRoot: '/tp');
    cubit = PromptCubit(repository: repository);
  });

  tearDown(() => cubit.close());

  Future<void> pumpPage(WidgetTester tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    await tester.pumpWidget(
      MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => TpTheme(
                data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
                child: RepositoryProvider<PromptRepository>.value(
                  value: repository,
                  child: MultiBlocProvider(
                    providers: [
                      BlocProvider<PromptCubit>.value(value: cubit),
                      BlocProvider(create: (_) => LayoutCubit()),
                    ],
                    child: const Scaffold(body: PromptManagementPage()),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty state opens the editor and cancel exits', (tester) async {
    await pumpPage(tester);

    expect(find.text('No prompts yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('prompt-new')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('prompt-name')), findsOneWidget);

    await tester.tap(find.byKey(const Key('prompt-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('prompt-name')), findsNothing);
  });

  testWidgets('existing prompt opens the editor with its content', (
    tester,
  ) async {
    await repository.save(prompt('p1', 'Existing'));
    await cubit.load();
    await pumpPage(tester);

    await tester.tap(find.text('Existing'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('prompt-content')))
          .controller!
          .text,
      'body-p1',
    );
  });
}
```

- [ ] **Step 3: 运行确认失败**

Run:

```bash
cd client
dart run tool/run_tests.dart test/pages/prompts/prompt_management_page_test.dart
```

Expected: FAIL（页面/编辑器不存在）。

- [ ] **Step 4: 实现编辑器**

创建 `client/lib/pages/prompts/prompt_editor_dialog.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';

import '../../cubits/prompt_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/prompt_definition.dart';
import '../../widgets/app_toast/app_toast.dart';

/// 打开提示词编辑器；保存成功返回 true。
Future<bool> showPromptEditorDialog(
  BuildContext context, {
  required PromptCubit cubit,
  PromptDefinition? prompt,
  int nextOrder = 0,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: _PromptEditorDialog(prompt: prompt, nextOrder: nextOrder),
    ),
  );
  return result ?? false;
}

class _PromptEditorDialog extends StatefulWidget {
  const _PromptEditorDialog({this.prompt, required this.nextOrder});

  final PromptDefinition? prompt;
  final int nextOrder;

  @override
  State<_PromptEditorDialog> createState() => _PromptEditorDialogState();
}

class _PromptEditorDialogState extends State<_PromptEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _content;
  late bool _enabled;
  String? _nameError;
  String? _contentError;

  @override
  void initState() {
    super.initState();
    final prompt = widget.prompt;
    _name = TextEditingController(text: prompt?.name ?? '');
    _description = TextEditingController(text: prompt?.description ?? '');
    _content = TextEditingController(text: prompt?.content ?? '');
    _enabled = prompt?.enabled ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final name = _name.text.trim();
    final content = _content.text.trim();
    setState(() {
      _nameError = name.isEmpty ? l10n.promptNameRequired : null;
      _contentError = content.isEmpty ? l10n.promptContentRequired : null;
    });
    if (_nameError != null || _contentError != null) return;

    final now = DateTime.now().toUtc();
    final existing = widget.prompt;
    final definition = PromptDefinition(
      id: existing?.id ?? const Uuid().v4(),
      name: name,
      description: _description.text.trim(),
      content: content,
      enabled: _enabled,
      order: existing?.order ?? widget.nextOrder,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    final ok = await context.read<PromptCubit>().upsert(definition);
    if (!mounted) return;
    if (!ok) {
      AppToast.show(
        context,
        message: l10n.promptSaveFailed,
        variant: TpToastVariant.error,
      );
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.prompt == null ? l10n.promptNew : l10n.promptEdit),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('prompt-name'),
                controller: _name,
                decoration: InputDecoration(
                  labelText: l10n.promptName,
                  errorText: _nameError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('prompt-description'),
                controller: _description,
                decoration: InputDecoration(labelText: l10n.promptDescription),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('prompt-content'),
                controller: _content,
                minLines: 6,
                maxLines: null,
                decoration: InputDecoration(
                  labelText: l10n.promptContent,
                  errorText: _contentError,
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('prompt-enabled'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.promptEnabled),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('prompt-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.promptCancel),
        ),
        FilledButton(
          key: const Key('prompt-save'),
          onPressed: _save,
          child: Text(l10n.promptSave),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: 实现管理页**

创建 `client/lib/pages/prompts/prompt_management_page.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/prompt_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/prompt_definition.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/settings/workspace_section_host.dart';
import '../../widgets/settings/workspace_section_nav_item.dart';
import '../../widgets/workspace_library_card.dart';
import 'prompt_editor_dialog.dart';

class PromptManagementPage extends StatelessWidget {
  const PromptManagementPage({this.embedded = false, super.key});

  final bool embedded;

  Future<void> _openEditor(
    BuildContext context, {
    required PromptCubit cubit,
    PromptDefinition? prompt,
  }) async {
    await showPromptEditorDialog(
      context,
      cubit: cubit,
      prompt: prompt,
      nextOrder: cubit.state.prompts.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WorkspaceAdaptiveSectionPage(
      pageKey: AppKeys.promptsWorkspace,
      title: l10n.promptNavTitle,
      embedded: embedded,
      compactSectionTabs: true,
      items: [
        WorkspaceSectionNavItem(
          label: l10n.promptNavTitle,
          icon: Icons.article_outlined,
          selected: true,
          onSelect: () {},
        ),
      ],
      body: BlocBuilder<PromptCubit, PromptLibraryState>(
        builder: (context, state) {
          if (state.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final cubit = context.read<PromptCubit>();
          final prompts = state.prompts;
          return SingleChildScrollView(
            child: WorkspaceLibraryCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TpCardHeader(
                    title: l10n.promptInstalledCount(prompts.length),
                    trailing: FilledButton(
                      key: const Key('prompt-new'),
                      onPressed: () => _openEditor(context, cubit: cubit),
                      child: Text(l10n.promptNew),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (prompts.isEmpty)
                    TpEmptyState(
                      icon: Icons.article_outlined,
                      title: l10n.promptNoPrompts,
                      hint: l10n.promptNoPromptsHint,
                      actionLabel: l10n.promptNew,
                      onAction: () => _openEditor(context, cubit: cubit),
                    )
                  else
                    for (final prompt in prompts)
                      _PromptRow(
                        prompt: prompt,
                        onEdit: () =>
                            _openEditor(context, cubit: cubit, prompt: prompt),
                        onToggle: (enabled) =>
                            unawaited(cubit.setEnabled(prompt.id, enabled)),
                        onDelete: () async {
                          final ok = await cubit.remove(prompt.id);
                          if (!ok && context.mounted) {
                            AppToast.show(
                              context,
                              message: l10n.promptDeleteFailed,
                              variant: TpToastVariant.error,
                            );
                          }
                        },
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PromptRow extends StatelessWidget {
  const _PromptRow({
    required this.prompt,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final PromptDefinition prompt;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final subtitle = prompt.description.trim().isEmpty
        ? l10n.promptGlobalScope
        : prompt.description.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: workspaceInsetDecoration(cs, radius: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onEdit,
          child: Row(
            children: [
              Icon(
                Icons.article_outlined,
                size: context.tpIconSizes.md,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prompt.name.isEmpty ? prompt.id : prompt.name,
                      style: TpTextStyles.of(context).mdBold,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TpTextStyles.of(
                        context,
                      ).smColored(cs.onSurface.withValues(alpha: 0.6)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Switch(
                value: prompt.enabled,
                onChanged: onToggle,
              ),
              IconButton(
                tooltip: l10n.promptEdit,
                visualDensity: VisualDensity.compact,
                iconSize: context.tpIconSizes.md,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: l10n.promptDelete,
                visualDensity: VisualDensity.compact,
                iconSize: context.tpIconSizes.md,
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline, color: cs.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: 加 AppKeys**

在 `client/lib/utils/ui/app_keys.dart` 的 `hooksWorkspace` 附近加：

```dart
  static const promptsWorkspace = Key('prompts-workspace');
```

- [ ] **Step 7: 接路由、全局视图与侧边栏**

1. `client/lib/router/app_router.dart` import 区加：

```dart
import '../pages/prompts/prompt_management_page.dart';
```

2. 在 `/hooks` 路由后加：

```dart
            GoRoute(
              path: '/prompts',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: PromptManagementPage()),
            ),
```

3. `client/lib/pages/home_workspace/home_workspace_global_section.dart`：
   - enum 增加 `prompts,`（放在 `hooks` 后）。
   - `homeLocation` 的 switch 增加：

```dart
    HomeGlobalView.prompts => '/prompts',
```

   - import 加：

```dart
import '../prompts/prompt_management_page.dart';
```

   - `HomeGlobalSection` 的 switch 增加：

```dart
      HomeGlobalView.prompts => const PromptManagementPage(embedded: true),
```

4. `client/lib/pages/home_workspace/home_workspace_sidebar.dart`：在 Hooks 的 `_ShortcutRow` 后加：

```dart
        const SizedBox(height: 4),
        _ShortcutRow(
          icon: Icons.article_outlined,
          label: l10n.promptNavTitle,
          active: activeGlobalView == HomeGlobalView.prompts,
          onTap: () => onGlobal?.call(HomeGlobalView.prompts),
        ),
```

- [ ] **Step 8: 运行页面测试与静态检查**

Run:

```bash
cd client
dart run tool/run_tests.dart test/pages/prompts/prompt_management_page_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: PASS；analyze 无新增问题。

- [ ] **Step 9: 提交**

```bash
git add client/lib/pages/prompts client/lib/pages/home_workspace/home_workspace_global_section.dart client/lib/pages/home_workspace/home_workspace_sidebar.dart client/lib/router/app_router.dart client/lib/utils/ui/app_keys.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/test/pages/prompts/prompt_management_page_test.dart
git commit -m "feat(prompts): add global prompt management page" -- client/lib/pages/prompts client/lib/pages/home_workspace/home_workspace_global_section.dart client/lib/pages/home_workspace/home_workspace_sidebar.dart client/lib/router/app_router.dart client/lib/utils/ui/app_keys.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/test/pages/prompts/prompt_management_page_test.dart
```

---

### Task 9: 工作区提示词 section

**Files:**
- Create: `client/lib/pages/home_workspace/workspace/config/workspace_prompts_section.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_config_section.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_config_workspace.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Regenerate: `client/lib/l10n/app_localizations*.dart`
- Test: `client/test/pages/home_workspace/workspace/config/workspace_prompts_section_test.dart`

**Interfaces:**
- Consumes: `PromptCubit` / `WorkspacePromptCubit`（Task 7）、`WorkspaceProjectConfigCubit`、`ConfigBundle.disabledPromptIds`（Task 4）、`PromptRepository`（Task 2）。
- Produces: `WorkspacePromptsSection({required String workspaceId, PromptRepository? repository})`；`WorkspaceConfigSection.prompts`。

- [ ] **Step 1: 加 l10n key**

`client/lib/l10n/app_en.arb` 追加：

```json
  "workspacePromptsGlobalTitle": "Global prompts",
  "workspacePromptsGlobalHint": "Disable a global prompt for this workspace only.",
  "workspacePromptsLocalTitle": "Workspace prompts",
  "workspacePromptsLocalHint": "Injected only in sessions started in this workspace.",
  "workspacePromptsManageGlobal": "Manage global prompts",
  "workspacePromptsGlobalDisabled": "Disabled globally",
  "workspacePromptsNoLocal": "No workspace prompts yet",
  "workspacePromptsNoLocalHint": "Create a prompt that only this workspace uses."
```

`client/lib/l10n/app_zh.arb` 追加：

```json
  "workspacePromptsGlobalTitle": "全局提示词",
  "workspacePromptsGlobalHint": "只在本工作区关闭某条全局提示词。",
  "workspacePromptsLocalTitle": "本工作区提示词",
  "workspacePromptsLocalHint": "只注入本工作区启动的会话。",
  "workspacePromptsManageGlobal": "管理全局提示词",
  "workspacePromptsGlobalDisabled": "全局已停用",
  "workspacePromptsNoLocal": "暂无工作区提示词",
  "workspacePromptsNoLocalHint": "创建一条仅本工作区使用的提示词。"
```

Run:

```bash
cd client
flutter gen-l10n
```

- [ ] **Step 2: 写失败测试**

创建 `client/test/pages/home_workspace/workspace/config/workspace_prompts_section_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/prompt_cubit.dart';
import 'package:teampilot/cubits/workspace_project_config_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/prompt_definition.dart';
import 'package:teampilot/pages/home_workspace/workspace/config/workspace_prompts_section.dart';
import 'package:teampilot/repositories/workspace_project_config_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/prompt/prompt_repository.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../../../../support/in_memory_filesystem.dart';
import '../../../../support/post_frame_test_harness.dart';

void main() {
  final now = DateTime.utc(2026, 11, 8, 10);

  PromptDefinition prompt(String id, String name) => PromptDefinition(
    id: id,
    name: name,
    content: 'body-$id',
    createdAt: now,
    updatedAt: now,
  );

  testWidgets('toggling a global prompt adds it to disabledPromptIds', (
    tester,
  ) async {
    setUpTestAppStorage();
    addTearDown(tearDownTestAppStorage);

    final fs = InMemoryFilesystem();
    final globalRepo = PromptRepository.global(fs: fs, teampilotRoot: '/root');
    await globalRepo.save(prompt('g1', 'Global one'));
    final globalCubit = PromptCubit(repository: globalRepo)..load();
    addTearDown(globalCubit.close);

    final workspaceRepo = PromptRepository.workspace(
      fs: fs,
      workspaceDir: '/root/workspace/workspaces/ws1',
    );
    final projectRepository = WorkspaceProjectConfigRepository(
      storage: testHomeStorage,
      fs: fs,
      layout: WorkspaceLayout(teampilotRoot: '/root', fs: fs),
    );
    final projectCubit = WorkspaceProjectConfigCubit(
      repository: projectRepository,
      workspaceId: 'ws1',
    )..load();
    addTearDown(projectCubit.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<PromptCubit>.value(value: globalCubit),
          BlocProvider<WorkspaceProjectConfigCubit>.value(value: projectCubit),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: WorkspacePromptsSection(
              workspaceId: 'ws1',
              repository: workspaceRepo,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Global one'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(
      projectCubit.state.config.bundle.disabledPromptIds,
      contains('g1'),
    );
  });
}
```

- [ ] **Step 3: 运行确认失败**

Run:

```bash
cd client
dart run tool/run_tests.dart test/pages/home_workspace/workspace/config/workspace_prompts_section_test.dart
```

Expected: FAIL（section 文件不存在）。

- [ ] **Step 4: 实现 section**

创建 `client/lib/pages/home_workspace/workspace/config/workspace_prompts_section.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../cubits/prompt_cubit.dart';
import '../../../../cubits/workspace_project_config_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/prompt_definition.dart';
import '../../../../services/prompt/prompt_repository.dart';
import '../../../../services/storage/home_storage.dart';
import '../../../../services/storage/workspace_layout.dart';
import '../../../../theme/workspace_surface_layers.dart';
import '../../../../widgets/app_toast/app_toast.dart';
import '../../../team_config/team_config_cards.dart';
import '../../../prompts/prompt_editor_dialog.dart';

class WorkspacePromptsSection extends StatelessWidget {
  const WorkspacePromptsSection({
    required this.workspaceId,
    this.repository,
    super.key,
  });

  final String workspaceId;

  /// 测试注入；生产从 [HomeStorage] 解析。
  final PromptRepository? repository;

  @override
  Widget build(BuildContext context) {
    final resolved = repository ?? _repositoryFromContext(context);
    return BlocProvider(
      create: (_) => WorkspacePromptCubit(repository: resolved)..load(),
      child: _WorkspacePromptsBody(workspaceId: workspaceId),
    );
  }

  PromptRepository _repositoryFromContext(BuildContext context) {
    final storage = context.read<HomeStorage>();
    final layout = WorkspaceLayout(
      teampilotRoot: storage.paths.basePath,
      fs: storage.fs,
    );
    return PromptRepository.workspace(
      fs: storage.fs,
      workspaceDir: layout.workspaceDir(workspaceId),
    );
  }
}

class _WorkspacePromptsBody extends StatelessWidget {
  const _WorkspacePromptsBody({required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final projectState = context.watch<WorkspaceProjectConfigCubit>().state;
    final projectCubit = context.read<WorkspaceProjectConfigCubit>();
    final globalState = context.watch<PromptCubit>().state;
    final localState = context.watch<WorkspacePromptCubit>().state;
    final disabled = projectState.config.bundle.disabledPromptIds;

    if (projectState.loading || localState.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamConfigCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamConfigCardHeader(
                  title: l10n.workspacePromptsGlobalTitle,
                  trailing: OutlinedButton.icon(
                    onPressed: () => context.go('/prompts'),
                    icon: const Icon(Icons.article_outlined),
                    label: Text(l10n.workspacePromptsManageGlobal),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.workspacePromptsGlobalHint,
                  style: TpTextStyles.of(context).smColored(
                    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 10),
                if (globalState.prompts.isEmpty)
                  TpEmptyState(
                    icon: Icons.article_outlined,
                    title: l10n.promptNoPrompts,
                    hint: l10n.promptNoPromptsHint,
                  )
                else
                  for (final prompt in globalState.prompts)
                    _GlobalPromptRow(
                      prompt: prompt,
                      disabledInWorkspace: disabled.contains(prompt.id),
                      onChanged: (enabled) {
                        final ids = List<String>.from(disabled);
                        if (enabled) {
                          ids.remove(prompt.id);
                        } else if (!ids.contains(prompt.id)) {
                          ids.add(prompt.id);
                        }
                        unawaited(
                          projectCubit.updateBundle(
                            projectState.config.bundle.copyWith(
                              disabledPromptIds: List<String>.unmodifiable(ids),
                            ),
                          ),
                        );
                      },
                    ),
              ],
            ),
          ),
          TeamConfigCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamConfigCardHeader(
                  title: l10n.workspacePromptsLocalTitle,
                  trailing: FilledButton(
                    onPressed: () => showPromptEditorDialog(
                      context,
                      cubit: context.read<WorkspacePromptCubit>(),
                      nextOrder: localState.prompts.length,
                    ),
                    child: Text(l10n.promptNew),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.workspacePromptsLocalHint,
                  style: TpTextStyles.of(context).smColored(
                    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 10),
                if (localState.prompts.isEmpty)
                  TpEmptyState(
                    icon: Icons.sticky_note_2_outlined,
                    title: l10n.workspacePromptsNoLocal,
                    hint: l10n.workspacePromptsNoLocalHint,
                    actionLabel: l10n.promptNew,
                    onAction: () => showPromptEditorDialog(
                      context,
                      cubit: context.read<WorkspacePromptCubit>(),
                      nextOrder: localState.prompts.length,
                    ),
                  )
                else
                  for (final prompt in localState.prompts)
                    _LocalPromptRow(
                      prompt: prompt,
                      onEdit: () => showPromptEditorDialog(
                        context,
                        cubit: context.read<WorkspacePromptCubit>(),
                        prompt: prompt,
                      ),
                      onDelete: () async {
                        final ok = await context
                            .read<WorkspacePromptCubit>()
                            .remove(prompt.id);
                        if (!ok && context.mounted) {
                          AppToast.show(
                            context,
                            message: l10n.promptDeleteFailed,
                            variant: TpToastVariant.error,
                          );
                        }
                      },
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlobalPromptRow extends StatelessWidget {
  const _GlobalPromptRow({
    required this.prompt,
    required this.disabledInWorkspace,
    required this.onChanged,
  });

  final PromptDefinition prompt;
  final bool disabledInWorkspace;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(prompt.name, style: TpTextStyles.of(context).mdBold),
                if (!prompt.enabled)
                  Text(
                    l10n.workspacePromptsGlobalDisabled,
                    style: TpTextStyles.of(context).smColored(
                      cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: prompt.enabled && !disabledInWorkspace,
            onChanged: prompt.enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

class _LocalPromptRow extends StatelessWidget {
  const _LocalPromptRow({
    required this.prompt,
    required this.onEdit,
    required this.onDelete,
  });

  final PromptDefinition prompt;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: workspaceInsetDecoration(cs, radius: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onEdit,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prompt.name.isEmpty ? prompt.id : prompt.name,
                      style: TpTextStyles.of(context).mdBold,
                    ),
                    if (prompt.description.trim().isNotEmpty)
                      Text(
                        prompt.description,
                        style: TpTextStyles.of(context).smColored(
                          cs.onSurface.withValues(alpha: 0.6),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.promptEdit,
                visualDensity: VisualDensity.compact,
                iconSize: context.tpIconSizes.md,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: l10n.promptDelete,
                visualDensity: VisualDensity.compact,
                iconSize: context.tpIconSizes.md,
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline, color: cs.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: 加 section 枚举与面板分支**

编辑 `client/lib/pages/home_workspace/workspace/workspace_config_section.dart`：

1. enum 加 `prompts,`（在 `hooks` 后）。
2. `routeSegment` switch 加：

```dart
    WorkspaceConfigSection.prompts => 'prompts',
```

3. `title` switch 加：

```dart
    WorkspaceConfigSection.prompts => l10n.promptNavTitle,
```

4. `workspaceConfigSectionIcon` 加：

```dart
      WorkspaceConfigSection.prompts => Icons.article_outlined,
```

编辑 `client/lib/pages/home_workspace/workspace/workspace_config_workspace.dart`：

1. import 加：

```dart
import 'config/workspace_prompts_section.dart';
```

2. `_ProjectConfigBody` 的 switch 加：

```dart
      WorkspaceConfigSection.prompts => WorkspacePromptsSection(
        workspaceId: workspace.workspaceId,
      ),
```

- [ ] **Step 6: 运行测试与静态检查**

Run:

```bash
cd client
dart run tool/run_tests.dart test/pages/home_workspace/workspace/config/workspace_prompts_section_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: PASS；analyze 无新增问题。

- [ ] **Step 7: 提交**

```bash
git add client/lib/pages/home_workspace/workspace/config/workspace_prompts_section.dart client/lib/pages/home_workspace/workspace/workspace_config_section.dart client/lib/pages/home_workspace/workspace/workspace_config_workspace.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/test/pages/home_workspace/workspace/config/workspace_prompts_section_test.dart
git commit -m "feat(prompts): add workspace prompt section" -- client/lib/pages/home_workspace/workspace/config/workspace_prompts_section.dart client/lib/pages/home_workspace/workspace/workspace_config_section.dart client/lib/pages/home_workspace/workspace/workspace_config_workspace.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/test/pages/home_workspace/workspace/config/workspace_prompts_section_test.dart
```

---

### Task 10: 文档与最终验证

**Files:**
- Modify: `docs/workspace-storage-layout.md`（注意：该文件已有用户未提交改动，只做最小插入，不要覆盖）
- Modify: `docs/superpowers/specs/2026-11-08-prompt-library-design.md`（如需同步实现细节，可选）

**Interfaces:**
- Consumes: 前 9 个任务。
- Produces: 可运行的完整功能与通过的验证。

- [ ] **Step 1: 更新存储文档**

在 `docs/workspace-storage-layout.md` 的顶层目录块中，`skills/installed/` 行附近加：

```text
  prompts/prompts.json           # global system-prompt library
```

在工作区目录块中，`project-config.json` 行附近加：

```text
  prompts.json                   # workspace-local system-prompt library
```

只插入这两行，保留文件里已有的用户改动。

- [ ] **Step 2: 静态检查**

Run:

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: No issues found。

- [ ] **Step 3: 跑本次相关的全部测试**

Run:

```bash
cd client
dart run tool/run_tests.dart \
  test/models/prompt_definition_test.dart \
  test/models/config_bundle_prompts_test.dart \
  test/services/prompt \
  test/services/resource/providers/user_prompt_contribution_provider_test.dart \
  test/services/resource/user_prompt_provisioning_test.dart \
  test/pages/prompts \
  test/pages/home_workspace/workspace/config/workspace_prompts_section_test.dart
```

Expected: 全部 PASS。

- [ ] **Step 4: 跑全量测试（后台，仅一次）**

Run（后台）：

```bash
cd client
dart run tool/run_tests.dart
```

Expected: 全部 PASS。若出现与本次无关的存量失败，记录并在提交说明中注明。

- [ ] **Step 5: 文档变更不自动提交**

`docs/workspace-storage-layout.md` 在本任务开始前已有用户未提交改动。**不要**把它加入本次提交：保持工作区里的两行插入即可，最终报告里注明「文档已更新但未提交，避免混入用户改动」。

- [ ] **Step 6: 最终验收**

逐条核对设计文档「验收标准」：

1. 全局页 CRUD + 重启保留。
2. 工作区 section CRUD，切换工作区互不可见。
3. 新会话的 CLI 原生提示词文件包含启用项，顺序全局 → 工作区。
4. `disabledPromptIds` 只影响本工作区。
5. 空内容 / 损坏文件只告警，不阻塞启动。
6. `flutter analyze` + 相关测试通过；全量测试已跑一次。

完成后在对话中报告：改动文件、验证命令与结果、已知限制（运行中会话需重启生效）。

---

## Self-Review

**Spec coverage**

- 全局库 / 工作区库存储 → Task 2。
- 自动注入所有 `PromptCapability` CLI → Task 5 + Task 6。
- 全局 → 工作区顺序、append、独立 section → Task 5。
- 工作区关闭全局项 → Task 4 + Task 9。
- 全局管理页 + 工作区 section + Hooks 同构入口 → Task 8 + Task 9。
- 错误处理（空内容 / 损坏文件）→ Task 2 + Task 5。
- 测试与文档 → Task 10。

**Placeholder scan**

- 无 TBD / TODO / “稍后补”。
- 每个代码步骤都给出了可粘贴代码或明确的插入位置。

**Type consistency**

- `PromptDefinition` 字段在 Task 1 定义，Task 2/3/5/7/8/9 使用一致。
- `disabledPromptIds` 在 Task 4 定义，Task 6/9 使用一致。
- `UserPromptContributionProvider` 的构造参数在 Task 5 定义，Task 6 使用一致。
- `WorkspacePromptCubit` 在 Task 7 定义，Task 9 使用一致。

**已知风险**

- `ConfigProfileService` 的装配点行号会随仓库改动漂移；执行时按“方法名 + 代码片段”定位，不依赖行号。
- `docs/workspace-storage-layout.md` 已有用户改动，文档步骤只允许插入两行。
- `CliResourceProvisioner` 使用 OpenCode 的真实 `PromptCapability` 做物化测试；若 OpenCode 的 prompt 目标路径未来变化，改测试断言而不是改产品逻辑。
