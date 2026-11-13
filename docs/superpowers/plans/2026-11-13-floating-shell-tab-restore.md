# 浮动工作区 shell tab 持久化与懒恢复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 默认剪掉重启后无法恢复的 shell tab；开启"恢复终端会话"后把 shell tab 持久化为 `cwd + spec`，在 tab 首次激活时懒重建 PTY。

**Architecture:** 快照 v2 增加 `shellSessions` 描述符表；`WorkbenchLayoutPersistence` 负责剪枝策略与描述符合成；重建后通过布局 reducer `replaceTab` 把 tab 从旧 entry id 重绑到新 entry id；`TerminalFloatingSurface` 在无 live entry 时渲染占位并触发一次懒重建。

**Tech Stack:** Flutter / Dart, flutter_bloc, slang l10n, 现有 in-memory 测试脚手架（`InMemoryFilesystem`、`fakeAsync`、`testChatCubit`）。

**Spec:** `docs/superpowers/specs/2026-11-13-floating-shell-tab-restore-design.md`

## Global Constraints

- 禁止直接运行 `flutter test`；一律 `cd client && dart run tool/run_tests.dart <测试路径>`。
- 内循环用 `cd client && flutter analyze`；只跑相关测试文件，不跑全量。
- i18n 只能改 `client/lib/i18n/*.i18n.json`，随后 `cd client && dart run slang`（不要用 build_runner）。
- 诊断日志用 `AppLogger`（`appLogger.w/i`），不允许 `print`。
- 默认行为：`restoreTerminalSessions` 默认 `false`（剪掉 shell tab）。
- 懒重建只在 tab 激活时发生；绝不在恢复阶段或面板渲染阶段批量建 PTY。
- SSH 连接失败保留 tab，由终端内现有错误 UI 展示。

---

### Task 1: Spec JSON 编解码 + 描述符模型

**Files:**
- Modify: `client/lib/models/workspace_terminal_session_spec.dart`
- Create: `client/lib/models/workbench_shell_descriptor.dart`
- Test: `client/test/models/workbench_shell_descriptor_test.dart`

**Interfaces:**
- Produces:
  - `Map<String, Object?> workspaceTerminalSpecToJson(WorkspaceTerminalSessionSpec spec)`
  - `WorkspaceTerminalSessionSpec? workspaceTerminalSpecFromJson(Object? json)`
  - `class WorkbenchShellDescriptor { const WorkbenchShellDescriptor({required String cwd, required WorkspaceTerminalSessionSpec spec}); final String cwd; final WorkspaceTerminalSessionSpec spec; Map<String, Object?> toJson(); static WorkbenchShellDescriptor? fromJson(Object? json); }`（含 `==` / `hashCode`）

- [ ] **Step 1: 写失败测试**

创建 `client/test/models/workbench_shell_descriptor_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workbench_shell_descriptor.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';

void main() {
  test('round-trips every spec variant', () {
    const descriptors = [
      WorkbenchShellDescriptor(
        cwd: '/proj',
        spec: WorkspaceTerminalLocalSpec('/bin/zsh'),
      ),
      WorkbenchShellDescriptor(
        cwd: '',
        spec: WorkspaceTerminalWorkspaceTargetSpec('ssh:profile-1'),
      ),
      WorkbenchShellDescriptor(
        cwd: '/remote/home',
        spec: WorkspaceTerminalSshProfileSpec('profile-1'),
      ),
    ];
    for (final d in descriptors) {
      final restored = WorkbenchShellDescriptor.fromJson(d.toJson());
      expect(restored, isNotNull);
      expect(restored!.cwd, d.cwd);
      expect(restored.spec, d.spec);
    }
  });

  test('rejects junk shapes and unknown spec types', () {
    expect(WorkbenchShellDescriptor.fromJson(null), isNull);
    expect(WorkbenchShellDescriptor.fromJson('nope'), isNull);
    expect(
      WorkbenchShellDescriptor.fromJson(const {
        'cwd': '/p',
        'spec': {'type': 'unknown'},
      }),
      isNull,
    );
    expect(
      WorkbenchShellDescriptor.fromJson(const {
        'spec': {'type': 'local', 'shellPath': '/bin/sh'},
      }),
      isNull,
    );
    expect(
      WorkbenchShellDescriptor.fromJson(const {
        'cwd': '/p',
        'spec': {'type': 'local'},
      }),
      isNull,
    );
  });

  test('equality is value-based', () {
    const a = WorkbenchShellDescriptor(
      cwd: '/p',
      spec: WorkspaceTerminalLocalSpec('/bin/sh'),
    );
    const b = WorkbenchShellDescriptor(
      cwd: '/p',
      spec: WorkspaceTerminalLocalSpec('/bin/sh'),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/models/workbench_shell_descriptor_test.dart`
Expected: 编译失败（文件不存在）。

- [ ] **Step 3: 在 spec 模型追加编解码**

在 `client/lib/models/workspace_terminal_session_spec.dart` 末尾（`_sameSshTarget` 之后）追加：

```dart
/// Persistence codec for workspace shell specs (workbench-layout v2).
Map<String, Object?> workspaceTerminalSpecToJson(
  WorkspaceTerminalSessionSpec spec,
) => switch (spec) {
  WorkspaceTerminalLocalSpec(:final shellPath) => {
    'type': 'local',
    'shellPath': shellPath,
  },
  WorkspaceTerminalWorkspaceTargetSpec(:final targetId) => {
    'type': 'target',
    'targetId': targetId,
  },
  WorkspaceTerminalSshProfileSpec(:final profileId) => {
    'type': 'sshProfile',
    'profileId': profileId,
  },
};

/// Null for malformed input; callers drop the owning persisted tab.
WorkspaceTerminalSessionSpec? workspaceTerminalSpecFromJson(Object? json) {
  if (json is! Map) return null;
  final type = json['type'];
  if (type is! String) return null;
  return switch (type) {
    'local' => switch (json['shellPath']) {
      final String shellPath => WorkspaceTerminalLocalSpec(shellPath),
      _ => null,
    },
    'target' => switch (json['targetId']) {
      final String targetId => WorkspaceTerminalWorkspaceTargetSpec(targetId),
      _ => null,
    },
    'sshProfile' => switch (json['profileId']) {
      final String profileId => WorkspaceTerminalSshProfileSpec(profileId),
      _ => null,
    },
    _ => null,
  };
}
```

创建 `client/lib/models/workbench_shell_descriptor.dart`：

```dart
import 'package:flutter/foundation.dart';

import 'workspace_terminal_session_spec.dart';

/// Everything needed to re-open a floating shell tab after an app restart.
@immutable
class WorkbenchShellDescriptor {
  const WorkbenchShellDescriptor({required this.cwd, required this.spec});

  final String cwd;
  final WorkspaceTerminalSessionSpec spec;

  Map<String, Object?> toJson() => {
    'cwd': cwd,
    'spec': workspaceTerminalSpecToJson(spec),
  };

  static WorkbenchShellDescriptor? fromJson(Object? json) {
    if (json is! Map) return null;
    final cwd = json['cwd'];
    final spec = workspaceTerminalSpecFromJson(json['spec']);
    if (cwd is! String || spec == null) return null;
    return WorkbenchShellDescriptor(cwd: cwd, spec: spec);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkbenchShellDescriptor && cwd == other.cwd && spec == other.spec;

  @override
  int get hashCode => Object.hash(cwd, spec);
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/models/workbench_shell_descriptor_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add client/lib/models/workspace_terminal_session_spec.dart \
  client/lib/models/workbench_shell_descriptor.dart \
  client/test/models/workbench_shell_descriptor_test.dart
git commit -m "feat(models): add workbench shell descriptor codec"
```

---

### Task 2: 布局 reducer `replaceTab` + Cubit 重绑入口

**Files:**
- Modify: `client/lib/cubits/workbench/workbench_split_layout.dart`（在 `SplitLayoutReducer.activate` 之后、`groupForTab` 之前插入）
- Modify: `client/lib/cubits/workbench/workbench_cubit.dart:519-526`（`openShell` 之后）
- Test: `client/test/cubits/workbench/workbench_split_layout_test.dart`
- Test: `client/test/cubits/workbench/workbench_cubit_test.dart`

**Interfaces:**
- Consumes: `WorkbenchTabId`, `TabStrip.copyWith`
- Produces:
  - `WorkbenchGroupLayout SplitLayoutReducer.replaceTab(WorkbenchGroupLayout layout, WorkbenchTabId from, WorkbenchTabId to)`
  - `void WorkbenchCubit.replaceFloatingTabId(String workspaceId, String fromEntryId, String toEntryId)`

- [ ] **Step 1: 写 reducer 失败测试**

在 `test/cubits/workbench/workbench_split_layout_test.dart` 末尾新增：

```dart
  group('replaceTab', () {
    final oldShell = WorkbenchTabId.shell('old');
    final newShell = WorkbenchTabId.shell('new');

    test('replaces id in order, active, preview and pin sets in place', () {
      var layout = _seed(_s1, oldShell, _s3);
      layout = layout.copyWith(
        groups: {
          'g0': layout.groups['g0']!.copyWith(
            activeId: oldShell,
            previewIds: {oldShell},
            pinnedIds: {oldShell},
          ),
        },
      );

      final next = const SplitLayoutReducer().replaceTab(
        layout,
        oldShell,
        newShell,
      );

      final strip = next.groups['g0']!;
      expect(strip.order, [_s1, newShell, _s3]);
      expect(strip.activeId, newShell);
      expect(strip.previewIds, {newShell});
      expect(strip.pinnedIds, {newShell});
      expect(next.focusedGroupId, layout.focusedGroupId);
      expect(next.lockedGroupIds, layout.lockedGroupIds);
    });

    test('no-op guards: same id, missing source, existing target', () {
      final layout = _seed(_s1, oldShell);
      const r = SplitLayoutReducer();
      expect(identical(r.replaceTab(layout, oldShell, oldShell), layout), isTrue);
      expect(
        identical(r.replaceTab(layout, WorkbenchTabId.shell('nope'), newShell), layout),
        isTrue,
      );
      expect(
        identical(r.replaceTab(layout, oldShell, _s1), layout),
        isTrue,
      );
    });
  });
```

在 `test/cubits/workbench/workbench_cubit_test.dart` 末尾新增：

```dart
  test('replaceFloatingTabId retargets only the floating layout', () {
    final cubit = WorkbenchCubit()
      ..openSession('ws', 's1')
      ..openFloating('ws', WorkbenchTabId.shell('old'));
    addTearDown(cubit.close);

    cubit.replaceFloatingTabId('ws', 'old', 'new');

    expect(cubit.mergedFloatingStrip('ws').order, [
      WorkbenchTabId.shell('new'),
    ]);
    expect(cubit.centerOrder('ws'), [WorkbenchTabId.session('s1')]);
  });
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/cubits/workbench/workbench_split_layout_test.dart test/cubits/workbench/workbench_cubit_test.dart`
Expected: 编译失败（`replaceTab` / `replaceFloatingTabId` 未定义）。

- [ ] **Step 3: 实现 reducer**

在 `workbench_split_layout.dart` 的 `SplitLayoutReducer.activate` 结束后插入：

```dart
  /// Replaces [from] with [to] in place across every group (order, active,
  /// preview and pin sets, landing return tab). No-op when [from] == [to],
  /// [from] is absent, or [to] already exists anywhere.
  WorkbenchGroupLayout replaceTab(
    WorkbenchGroupLayout layout,
    WorkbenchTabId from,
    WorkbenchTabId to,
  ) {
    if (from == to) return layout;
    for (final strip in layout.groups.values) {
      if (strip.contains(to)) return layout;
    }
    var changed = false;
    final groups = <String, TabStrip>{};
    for (final entry in layout.groups.entries) {
      final strip = entry.value;
      if (!strip.contains(from)) {
        groups[entry.key] = strip;
        continue;
      }
      changed = true;
      Set<WorkbenchTabId> swap(Set<WorkbenchTabId> ids) {
        if (!ids.contains(from)) return ids;
        return {...ids}..remove(from)..add(to);
      }

      groups[entry.key] = strip.copyWith(
        order: [for (final tab in strip.order) tab == from ? to : tab],
        activeId: strip.activeId == from ? to : strip.activeId,
        previewIds: swap(strip.previewIds),
        pinnedIds: swap(strip.pinnedIds),
        landingReturnTabId: strip.landingReturnTabId == from
            ? to
            : strip.landingReturnTabId,
      );
    }
    if (!changed) return layout;
    final next = layout.copyWith(groups: groups);
    assert(_debugCheck(next));
    return next;
  }
```

- [ ] **Step 4: 实现 Cubit 入口**

在 `WorkbenchCubit.openShell` 之后插入：

```dart
  /// Retargets a restored shell tab from its persisted entry id to the live
  /// entry id created by the lazy rebuild (floating layout only).
  void replaceFloatingTabId(
    String workspaceId,
    String fromEntryId,
    String toEntryId,
  ) {
    _mutateLayout(
      workspaceId,
      floating: true,
      mutate: (layout) => _lr.replaceTab(
        layout,
        WorkbenchTabId.shell(fromEntryId),
        WorkbenchTabId.shell(toEntryId),
      ),
    );
  }
```

- [ ] **Step 5: 运行确认通过**

Run: `cd client && dart run tool/run_tests.dart test/cubits/workbench/workbench_split_layout_test.dart test/cubits/workbench/workbench_cubit_test.dart`
Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add client/lib/cubits/workbench/workbench_split_layout.dart \
  client/lib/cubits/workbench/workbench_cubit.dart \
  client/test/cubits/workbench/workbench_split_layout_test.dart \
  client/test/cubits/workbench/workbench_cubit_test.dart
git commit -m "feat(workbench): add replaceTab reducer and floating shell id retarget"
```

---

### Task 3: 快照仓库 v2（保存描述符 / 恢复返回描述符）

**Files:**
- Modify: `client/lib/repositories/workbench_layout_snapshot_repository.dart:44-130,166-199`
- Modify: `client/lib/services/workbench/workbench_layout_persistence.dart:120-125`（仅机械适配新回调签名）
- Test: `client/test/repositories/workbench_layout_snapshot_repository_test.dart`
- Test: `client/test/cubits/workbench/snapshot_restore_test.dart`（仅回调签名）
- Test: `client/test/services/workbench/workbench_layout_persistence_test.dart:103`（版本断言）

**Interfaces:**
- Consumes: Task 1 的 `WorkbenchShellDescriptor`
- Produces:
  - `Future<void> WorkbenchLayoutSnapshotRepository.save(WorkbenchGroupLayout center, WorkbenchGroupLayout floating, {Map<String, WorkbenchShellDescriptor> shellSessions = const {}})`
  - `Future<Map<String, WorkbenchShellDescriptor>> WorkbenchLayoutSnapshotRepository.restore(WorkbenchCubit workbench, {bool Function(WorkbenchTabId tab, WorkbenchShellDescriptor? descriptor)? tabResolves})`
  - `static const int currentVersion = 2;` / `static const int minReadableVersion = 1;`

- [ ] **Step 1: 更新/新增仓库测试（先失败）**

在 `test/repositories/workbench_layout_snapshot_repository_test.dart`：

1. 加 import：
```dart
import 'package:teampilot/models/workbench_shell_descriptor.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
```
2. 把 `expect(decoded['version'], 1);`（第 64 行）改为 `expect(decoded['version'], 2);`，并追加：
```dart
      expect(decoded['shellSessions'], isEmpty);
```
3. 把第 111-127 行的 resolver 改成两参：
```dart
      await repo.restore(
        cubit,
        tabResolves: (tab, _) => tab != _s2 && tab != _shell2,
      );
```
   同样把 `test/cubits/workbench/snapshot_restore_test.dart:88` 改为：
```dart
    await repo.restore(
      cubit,
      tabResolves: (tab, _) => tab != _s3 && tab != _sh1,
    );
```
4. `test/services/workbench/workbench_layout_persistence_test.dart:103` 的
   `expect(decoded['version'], 1)` 改为 `expect(decoded['version'], 2)`。
4. 末尾新增两个测试：

```dart
  test('round-trips shell descriptors and prunes tabs without one', () async {
    final cubit = seedCubit();
    const descriptor = WorkbenchShellDescriptor(
      cwd: '/proj',
      spec: WorkspaceTerminalLocalSpec('/bin/bash'),
    );
    await repo.save(
      cubit.centerLayout(_ws),
      cubit.floatingLayout(_ws),
      shellSessions: {_shell1.id: descriptor},
    );

    final workbench = WorkbenchCubit();
    addTearDown(workbench.close);
    final restored = await repo.restore(
      workbench,
      tabResolves: (tab, d) => tab.kind != WorkbenchTabKind.shell || d != null,
    );

    expect(restored.keys, {_shell1.id});
    expect(restored[_shell1.id], descriptor);
    expect(workbench.mergedFloatingStrip(_ws).contains(_shell1), isTrue);
    expect(workbench.mergedFloatingStrip(_ws).contains(_shell2), isFalse);
  });

  test('a v1 snapshot restores layouts with no shell descriptors', () async {
    final cubit = seedCubit();
    await repo.save(cubit.centerLayout(_ws), cubit.floatingLayout(_ws));
    final decoded = jsonDecode(fs.files[_file]!) as Map<String, Object?>;
    decoded['version'] = 1;
    decoded.remove('shellSessions');
    await fs.writeString(_file, jsonEncode(decoded));

    final workbench = WorkbenchCubit();
    addTearDown(workbench.close);
    final restored = await repo.restore(
      workbench,
      tabResolves: (tab, d) => tab.kind != WorkbenchTabKind.shell || d != null,
    );

    expect(restored, isEmpty);
    expect(workbench.mergedFloatingStrip(_ws).order, isEmpty);
  });

  test('a corrupt descriptor prunes only its own tab', () async {
    final cubit = seedCubit();
    await repo.save(
      cubit.centerLayout(_ws),
      cubit.floatingLayout(_ws),
      shellSessions: {
        _shell1.id: const WorkbenchShellDescriptor(
          cwd: '/tmp',
          spec: WorkspaceTerminalLocalSpec('/bin/bash'),
        ),
      },
    );
    final decoded = jsonDecode(fs.files[_file]!) as Map<String, Object?>;
    (decoded['shellSessions'] as Map)[_shell2.id] = const {
      'cwd': '/tmp',
      'spec': {'type': 'bogus'},
    };
    await fs.writeString(_file, jsonEncode(decoded));

    final workbench = WorkbenchCubit();
    addTearDown(workbench.close);
    final restored = await repo.restore(
      workbench,
      tabResolves: (tab, d) => tab.kind != WorkbenchTabKind.shell || d != null,
    );

    expect(restored.keys, {_shell1.id});
    expect(workbench.floatingOrder(_ws), [_shell1]);
  });
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/repositories/workbench_layout_snapshot_repository_test.dart test/cubits/workbench/snapshot_restore_test.dart`
Expected: FAIL（版本仍为 1、`shellSessions` 不存在、回调签名不符）。

- [ ] **Step 3: 实现仓库改动**

`workbench_layout_snapshot_repository.dart` 顶部 import 追加：

```dart
import '../models/workbench_shell_descriptor.dart';
```

同时把类注释里的 JSON 示例（原 v1 单行示例）更新为：

```text
/// {"center": <layout snapshot>, "floating": <layout snapshot>, "version": 2,
///  "shellSessions": {"<tabId>": {"cwd": "...", "spec": {...}}}}
```

版本常量改为：

```dart
  /// Snapshot format version. v2 adds the `shellSessions` descriptor table;
  /// v1 files remain readable (their shell tabs prune for lack of a descriptor).
  static const int currentVersion = 2;
  static const int minReadableVersion = 1;
```

`save` 签名与编码：

```dart
  Future<void> save(
    WorkbenchGroupLayout center,
    WorkbenchGroupLayout floating, {
    Map<String, WorkbenchShellDescriptor> shellSessions = const {},
  }) async {
    final encoded = jsonEncode({
      'version': currentVersion,
      'center': toSnapshot(center),
      'floating': toSnapshot(floating),
      'shellSessions': {
        for (final entry in shellSessions.entries)
          entry.key: entry.value.toJson(),
      },
    });
    try {
      await _fs.ensureDir(_layout.workspaceDir(workspaceId));
      await _fs.atomicWrite(_file, encoded);
    } on Object catch (e) {
      appLogger.w('[workbench-layout] save failed ($workspaceId): $e');
    }
  }
```

`restore` 改为：

```dart
  Future<Map<String, WorkbenchShellDescriptor>> restore(
    WorkbenchCubit workbench, {
    bool Function(WorkbenchTabId tab, WorkbenchShellDescriptor? descriptor)?
    tabResolves,
  }) async {
    final resolve = tabResolves ?? (tab, descriptor) => true;
    final Map<String, Object?>? json = await _readSnapshot();
    if (json == null) return const {};
    final descriptors = _descriptorsFromSnapshot(json['shellSessions']);

    final centerJson = json['center'];
    final floatingJson = json['floating'];
    if (centerJson is! Map || floatingJson is! Map) {
      appLogger.w(
        '[workbench-layout] corrupt snapshot ($workspaceId): '
        'center/floating must be objects',
      );
      return descriptors;
    }

    final WorkbenchGroupLayout? center;
    final WorkbenchGroupLayout? floating;
    try {
      final resolved = (WorkbenchTabId tab) =>
          resolve(tab, descriptors[tab.id]);
      final decodedCenter = layoutFromSnapshot(
        Map<String, Object?>.from(centerJson),
        tabResolves: resolved,
      );
      final decodedFloating = layoutFromSnapshot(
        Map<String, Object?>.from(floatingJson),
        tabResolves: resolved,
      );
      center = decodedCenter == null
          ? null
          : _withoutRuntimeLanding(decodedCenter);
      floating = decodedFloating == null
          ? null
          : _withoutRuntimeLanding(decodedFloating);
    } on Object catch (e) {
      appLogger.w('[workbench-layout] corrupt snapshot ($workspaceId): $e');
      return descriptors;
    }

    if (center == null && floating == null) {
      appLogger.w(
        '[workbench-layout] snapshot pruned to empty ($workspaceId); '
        'keeping current layout',
      );
      return descriptors;
    }
    workbench.resetLayoutToSnapshot(workspaceId, center, floating);
    return descriptors;
  }
```

新增私有解析：

```dart
  Map<String, WorkbenchShellDescriptor> _descriptorsFromSnapshot(
    Object? json,
  ) {
    if (json is! Map) return const {};
    final out = <String, WorkbenchShellDescriptor>{};
    for (final entry in json.entries) {
      final tabId = entry.key;
      if (tabId is! String || tabId.trim().isEmpty) continue;
      final descriptor = WorkbenchShellDescriptor.fromJson(entry.value);
      if (descriptor == null) {
        appLogger.w(
          '[workbench-layout] dropping corrupt shell descriptor '
          '($workspaceId): $tabId',
        );
        continue;
      }
      out[tabId] = descriptor;
    }
    return out;
  }
```

`_readSnapshot` 的版本校验替换为：

```dart
    final version = json['version'];
    if (version is! int ||
        version < minReadableVersion ||
        version > currentVersion) {
      appLogger.w(
        '[workbench-layout] unsupported snapshot version ($workspaceId): '
        '${json['version']} not in '
        '[$minReadableVersion, $currentVersion]',
      );
      return null;
    }
```

- [ ] **Step 4: 机械适配持久化协调器（仅编译）**

`workbench_layout_persistence.dart` 第 121 行改为：

```dart
        .restore(
          _workbench,
          tabResolves: (tab, _) => _tabResolves(id, tab),
        )
```

（本任务不改变剪枝策略；Task 4 再改。）

- [ ] **Step 5: 运行仓库测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/repositories/workbench_layout_snapshot_repository_test.dart test/cubits/workbench/snapshot_restore_test.dart test/services/workbench/workbench_layout_persistence_test.dart`
Expected: PASS。

再跑：
Run: `cd client && flutter analyze`
Expected: 无错误。

- [ ] **Step 6: 提交**

```bash
git add client/lib/repositories/workbench_layout_snapshot_repository.dart \
  client/lib/services/workbench/workbench_layout_persistence.dart \
  client/test/repositories/workbench_layout_snapshot_repository_test.dart \
  client/test/cubits/workbench/snapshot_restore_test.dart \
  client/test/services/workbench/workbench_layout_persistence_test.dart
git commit -m "feat(workbench): persist shell descriptors in layout snapshot v2"
```

---

### Task 4: 恢复剪枝 + 保存时描述符合成

**Files:**
- Modify: `client/lib/services/terminal/workspace_terminal_registry.dart:134-142`（新增 `containsEntry`）
- Modify: `client/lib/services/workbench/workbench_layout_persistence.dart:44-59,109-139,226-237,239-285`
- Test: `client/test/services/workbench/workbench_layout_persistence_test.dart`
- Test: `client/test/services/terminal/workspace_terminal_registry_test.dart`

**Interfaces:**
- Consumes: Task 1 描述符、Task 3 的 `restore(...) → Map<String, WorkbenchShellDescriptor>` 与 `save(..., shellSessions:)`
- Produces:
  - `bool WorkspaceTerminalRegistry.containsEntry(String workspaceId, String entryId)`
  - `WorkbenchLayoutPersistence({..., WorkspaceTerminalRegistry? terminalRegistry, bool Function()? restoreTerminalSessions})`
  - `WorkbenchShellDescriptor? WorkbenchLayoutPersistence.descriptorFor(String workspaceId, String tabId)`

- [ ] **Step 1: 写失败测试**

在 `test/services/terminal/workspace_terminal_registry_test.dart` 的 group 末尾新增：

```dart
    test('containsEntry peek does not create a group', () {
      final reg = WorkspaceTerminalRegistry();
      final a = reg.groupFor('A');
      final entry = a.addEntry(
        cwd: '/tmp/a',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        select: true,
      );

      expect(reg.containsEntry('A', entry.id), isTrue);
      expect(reg.containsEntry('A', 'missing'), isFalse);
      // Unknown workspace: false, and no group is materialized.
      expect(reg.containsEntry('B', entry.id), isFalse);
      reg.disposeAll();
    });
```

在 `test/services/workbench/workbench_layout_persistence_test.dart`：

1. 追加 imports：
```dart
import 'package:teampilot/models/workbench_shell_descriptor.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';

import '../../support/rust_lib_test_init.dart';
```
2. `main()` 顶部 `setUp(...)` 之前加 `setUpAll(initRustLibForTests);`。
3. 修改 `withPersistence` 帮助函数为：

```dart
  void withPersistence(
    void Function(
      FakeAsync async,
      InMemoryFilesystem fs,
      WorkbenchCubit workbench,
      ChatCubit chat,
      WorkbenchLayoutPersistence persistence,
    )
    body, {
    bool restoreTerminalSessions = true,
    WorkspaceTerminalRegistry? terminalRegistry,
  }) {
    fakeAsync((async) {
      final fs = InMemoryFilesystem();
      final layout = WorkspaceLayout(teampilotRoot: _root, fs: fs);
      final home = fakeHomeStorage(filesystem: fs, appDataRoot: _root);
      final workbench = WorkbenchCubit();
      final chat = ChatCubit(
        executableResolver: () => 'true',
        storage: home,
        automationRepository: AutomationRepository(fs: fs, layout: layout),
      );
      final persistence = WorkbenchLayoutPersistence(
        workbench: workbench,
        chat: chat,
        storage: home,
        fs: fs,
        layout: layout,
        terminalRegistry: terminalRegistry,
        restoreTerminalSessions: () => restoreTerminalSessions,
      )..start();
      body(async, fs, workbench, chat, persistence);
    });
  }
```
4. 修改 `seedSnapshot` 为自动补 shell 描述符：

```dart
  Map<String, WorkbenchShellDescriptor> descriptorsFor(WorkbenchCubit cubit) {
    final ids = <String>{};
    for (final layout in [
      cubit.centerLayout(_ws),
      cubit.floatingLayout(_ws),
    ]) {
      for (final strip in layout.groups.values) {
        for (final tab in strip.order) {
          if (tab.kind == WorkbenchTabKind.shell) ids.add(tab.id);
        }
      }
    }
    return {
      for (final id in ids)
        id: const WorkbenchShellDescriptor(
          cwd: '/tmp',
          spec: WorkspaceTerminalLocalSpec('/bin/bash'),
        ),
    };
  }

  void seedSnapshot(
    FakeAsync async,
    InMemoryFilesystem fs,
    WorkbenchCubit seeder, {
    Map<String, WorkbenchShellDescriptor>? shellSessions,
  }) {
    unawaited(
      WorkbenchLayoutSnapshotRepository(
        workspaceId: _ws,
        storage: fakeHomeStorage(filesystem: fs, appDataRoot: _root),
        fs: fs,
        layout: WorkspaceLayout(teampilotRoot: _root, fs: fs),
      ).save(
        seeder.centerLayout(_ws),
        seeder.floatingLayout(_ws),
        shellSessions: shellSessions ?? descriptorsFor(seeder),
      ),
    );
    async.flushMicrotasks();
  }
```
5. 末尾新增测试：

```dart
  test('shell tabs are pruned when terminal restore is off', () {
    withPersistence(
      (async, fs, workbench, _, persistence) {
        final seeder = WorkbenchCubit()
          ..openFile(_ws, '/one.dart')
          ..openFloating(_ws, _sh1);
        seedSnapshot(async, fs, seeder);
        seeder.close();

        unawaited(persistence.restoreForWorkspace(_ws));
        async.flushMicrotasks();

        expect(workbench.centerOrder(_ws), [WorkbenchTabId.file('/one.dart')]);
        expect(workbench.floatingOrder(_ws), isEmpty);
      },
      restoreTerminalSessions: false,
    );
  });

  test('shell tabs without a descriptor are pruned even when enabled', () {
    withPersistence((async, fs, workbench, _, persistence) {
      final seeder = WorkbenchCubit()..openFloating(_ws, _sh1);
      seedSnapshot(async, fs, seeder, shellSessions: const {});
      seeder.close();

      unawaited(persistence.restoreForWorkspace(_ws));
      async.flushMicrotasks();

      expect(workbench.floatingOrder(_ws), isEmpty);
    });
  });

  test('save derives live descriptors and preserves unactivated ones', () {
    final registry = WorkspaceTerminalRegistry();
    addTearDown(registry.disposeAll);
    withPersistence(
      (async, fs, workbench, _, persistence) {
        final seeder = WorkbenchCubit()
          ..openFloating(_ws, _sh1)
          ..openFloating(_ws, _sh2);
        seedSnapshot(async, fs, seeder);
        seeder.close();

        unawaited(persistence.restoreForWorkspace(_ws));
        async.flushMicrotasks();
        expect(workbench.floatingOrder(_ws), [_sh1, _sh2]);

        // The lazy rebuild turned sh1 into a live entry (new id).
        final live = registry.groupFor(_ws).addEntry(
          cwd: '/live',
          spec: const WorkspaceTerminalSshProfileSpec('p1'),
          session: TerminalSession(
            executable: '/bin/bash',
            validateLaunch: false,
            parseExecutable: false,
            fs: InMemoryFilesystem(),
          ),
          select: true,
        );
        workbench.replaceFloatingTabId(_ws, _sh1.id, live.id);
        expect(persistence.descriptorFor(_ws, _sh1.id), isNull);
        expect(persistence.descriptorFor(_ws, _sh2.id), isNotNull);

        async.elapse(const Duration(milliseconds: 600));
        final decoded = jsonDecode(fs.files[_file]!) as Map<String, Object?>;
        final shells = decoded['shellSessions'] as Map<String, Object?>;
        expect(shells.keys, {live.id, _sh2.id});
        expect(
          (shells[live.id] as Map)['cwd'],
          '/live',
        );
        expect(
          ((shells[live.id] as Map)['spec'] as Map)['type'],
          'sshProfile',
        );
      },
      terminalRegistry: registry,
    );
  });

  test('a live registry entry keeps its shell tab even with restore off', () {
    final registry = WorkspaceTerminalRegistry();
    addTearDown(registry.disposeAll);
    withPersistence(
      (async, fs, workbench, _, persistence) {
        final seeder = WorkbenchCubit()..openFloating(_ws, _sh1);
        seedSnapshot(async, fs, seeder, shellSessions: const {});
        seeder.close();

        registry.groupFor(_ws).addEntry(
          cwd: '/tmp',
          spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
          session: TerminalSession(
            executable: '/bin/bash',
            validateLaunch: false,
            parseExecutable: false,
            fs: InMemoryFilesystem(),
          ),
          select: true,
        );

        unawaited(persistence.restoreForWorkspace(_ws));
        async.flushMicrotasks();

        expect(workbench.floatingOrder(_ws), [_sh1]);
      },
      restoreTerminalSessions: false,
      terminalRegistry: registry,
    );
  });
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/terminal/workspace_terminal_registry_test.dart test/services/workbench/workbench_layout_persistence_test.dart`
Expected: 编译失败（构造参数 / `descriptorFor` / `containsEntry` 未定义）及新用例失败。

- [ ] **Step 3: 注册表新增 `containsEntry`**

```dart
  /// Presence peek that does not create a group.
  bool containsEntry(String workspaceId, String entryId) =>
      _groups[workspaceId]?.contains(entryId) ?? false;
```

- [ ] **Step 4: 持久化协调器实现**

构造函数改为：

```dart
  WorkbenchLayoutPersistence({
    required WorkbenchCubit workbench,
    required ChatCubit chat,
    required HomeStorage storage,
    Filesystem? fs,
    WorkspaceLayout? layout,
    WorkspaceTerminalRegistry? terminalRegistry,
    bool Function()? restoreTerminalSessions,
  }) : _workbench = workbench,
       _chat = chat,
       _storage = storage,
       _fs = fs ?? storage.fs,
       _layout =
           layout ??
           WorkspaceLayout(
             teampilotRoot: storage.paths.basePath,
             fs: storage.fs,
           ),
       _terminalRegistry = terminalRegistry,
       _restoreTerminalSessions = restoreTerminalSessions ?? (() => false);
```

字段：

```dart
  final WorkspaceTerminalRegistry? _terminalRegistry;
  final bool Function() _restoreTerminalSessions;
  final Map<String, Map<String, WorkbenchShellDescriptor>> _restoredDescriptors =
      {};
```

`restoreForWorkspace` 的 restore 链改为：

```dart
    final restore = _repositoryFor(id)
        .restore(
          _workbench,
          tabResolves: (tab, descriptor) => _tabResolves(id, tab, descriptor),
        )
        .then((descriptors) async {
          _restoredDescriptors[id] = {
            for (final entry in descriptors.entries)
              if (_shellTabIds(id).contains(entry.key))
                entry.key: entry.value,
          };
          _registerRestoredSessionTabs(id);
          await _hydrateRestoredSessionTabs(id);
        });
```

新增方法：

```dart
  Set<String> _shellTabIds(String workspaceId) {
    final ids = <String>{};
    for (final layout in [
      _workbench.centerLayout(workspaceId),
      _workbench.floatingLayout(workspaceId),
    ]) {
      for (final strip in layout.groups.values) {
        for (final tab in strip.order) {
          if (tab.kind == WorkbenchTabKind.shell) ids.add(tab.id);
        }
      }
    }
    return ids;
  }

  /// Restored descriptor for a not-yet-rebuilt shell tab (null once the tab
  /// was retargeted, pruned, or already has a live entry).
  WorkbenchShellDescriptor? descriptorFor(String workspaceId, String tabId) {
    final id = workspaceId.trim();
    final descriptor = _restoredDescriptors[id]?[tabId];
    if (descriptor == null) return null;
    if (_terminalRegistry?.containsEntry(id, tabId) ?? false) return null;
    return _shellTabIds(id).contains(tabId) ? descriptor : null;
  }
```

`_tabResolves` 改为：

```dart
  bool _tabResolves(
    String workspaceId,
    WorkbenchTabId tab,
    WorkbenchShellDescriptor? descriptor,
  ) {
    if (tab.kind == WorkbenchTabKind.shell) {
      if (_terminalRegistry?.containsEntry(workspaceId, tab.id) ?? false) {
        return true;
      }
      return _restoreTerminalSessions() && descriptor != null;
    }
    if (tab.kind != WorkbenchTabKind.session) return true;
    for (final session in _chat.state.sessions) {
      if (session.sessionId == tab.id && session.workspaceId == workspaceId) {
        return true;
      }
    }
    for (final tabInfo in _chat.tabStore.openTabs) {
      if (tabInfo.sessionId == tab.id) return true;
    }
    return false;
  }
```

`_flush` 保存改为：

```dart
          await _repositoryFor(id).save(
            bar.center,
            bar.floating,
            shellSessions: _shellDescriptorsFor(id, bar),
          );
```

新增：

```dart
  Map<String, WorkbenchShellDescriptor> _shellDescriptorsFor(
    String workspaceId,
    WorkspaceTabBar bar,
  ) {
    if (!_restoreTerminalSessions()) return const {};
    final restored = _restoredDescriptors[workspaceId];
    final out = <String, WorkbenchShellDescriptor>{};
    for (final layout in [bar.center, bar.floating]) {
      for (final strip in layout.groups.values) {
        for (final tab in strip.order) {
          if (tab.kind != WorkbenchTabKind.shell) continue;
          final entry =
              (_terminalRegistry?.containsEntry(workspaceId, tab.id) ?? false)
              ? _terminalRegistry!.groupFor(workspaceId).entryById(tab.id)
              : null;
          final descriptor = entry != null
              ? WorkbenchShellDescriptor(cwd: entry.cwd, spec: entry.spec)
              : restored?[tab.id];
          if (descriptor != null) out[tab.id] = descriptor;
        }
      }
    }
    return out;
  }
```

`_onWorkbenchState` 的“bar cleared”分支追加：

```dart
        _dirty.remove(id);
        _restored.remove(id);
        _restoredDescriptors.remove(id);
```

imports 追加：

```dart
import '../../models/workbench_shell_descriptor.dart';
import '../terminal/workspace_terminal_registry.dart';
```

- [ ] **Step 5: 运行测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/terminal/workspace_terminal_registry_test.dart test/services/workbench/workbench_layout_persistence_test.dart`
Expected: PASS（含原有用例 + 5 个新用例）。

Run: `cd client && flutter analyze`
Expected: 无错误。

- [ ] **Step 6: 提交**

```bash
git add client/lib/services/terminal/workspace_terminal_registry.dart \
  client/lib/services/workbench/workbench_layout_persistence.dart \
  client/test/services/terminal/workspace_terminal_registry_test.dart \
  client/test/services/workbench/workbench_layout_persistence_test.dart
git commit -m "feat(workbench): prune stale shell tabs and synthesize descriptors"
```

---

### Task 5: 偏好开关 `restoreTerminalSessions` + 设置 UI

**Files:**
- Modify: `client/lib/models/layout_preferences.dart:146-201,203-315,431-437,486-497,584-589,706-714`
- Modify: `client/lib/cubits/layout_cubit.dart:416-417`
- Modify: `client/lib/pages/config/layout_appearance_in_layout_section.dart:247-256`
- Modify: `client/lib/i18n/floating_en.i18n.json`, `client/lib/i18n/floating_zh.i18n.json`
- Test: `client/test/models/layout_preferences_default_test.dart`
- Generated: `client/lib/l10n/*`

**Interfaces:**
- Produces:
  - `const LayoutPreferences({..., bool restoreTerminalSessions = false, ...})`
  - 注：`LayoutPreferences` 没有 `==` / `hashCode` 覆写，无需补齐等值比较。
  - `bool LayoutPreferences.restoreTerminalSessions`
  - `Future<void> LayoutCubit.setRestoreTerminalSessions(bool value)`
  - l10n: `context.l10n.floating.restoreTerminalSessionsTitle` / `...Description`

- [ ] **Step 1: 写失败测试**

在 `test/models/layout_preferences_default_test.dart` 末尾新增：

```dart
  test('restoreTerminalSessions defaults false and round-trips', () {
    expect(const LayoutPreferences().restoreTerminalSessions, isFalse);
    expect(
      LayoutPreferences.fromJson(const {}).restoreTerminalSessions,
      isFalse,
    );
    const enabled = LayoutPreferences(restoreTerminalSessions: true);
    expect(enabled.toJson()['restoreTerminalSessions'], isTrue);
    expect(
      LayoutPreferences.fromJson(enabled.toJson()).restoreTerminalSessions,
      isTrue,
    );
    expect(
      enabled.copyWith(restoreTerminalSessions: false).restoreTerminalSessions,
      isFalse,
    );
  });
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/models/layout_preferences_default_test.dart`
Expected: 编译失败（字段不存在）。

- [ ] **Step 3: 模型与 Cubit**

`layout_preferences.dart` 四处补充：

1. 构造函数（`floatingPreviewTabs = true,` 之后）：
```dart
    this.restoreTerminalSessions = false,
```
2. `fromJson`（`floatingPreviewTabs: ...` 之后）：
```dart
      restoreTerminalSessions:
          json['restoreTerminalSessions'] as bool? ?? false,
```
3. 字段（`floatingPreviewTabs` 字段注释之后）：
```dart
  /// Keep floating shell tabs across restarts; a tab reconnects (PTY/SSH) only
  /// when it is first activated. Default off — stale runtime tabs are pruned.
  final bool restoreTerminalSessions;
```
4. `copyWith` 参数与调用（`bool? floatingPreviewTabs,` 之后 / `floatingPreviewTabs: ...` 之后）：
```dart
    bool? restoreTerminalSessions,
```
```dart
      restoreTerminalSessions:
          restoreTerminalSessions ?? this.restoreTerminalSessions,
```
5. `toJson`（`'floatingPreviewTabs': floatingPreviewTabs,` 之后）：
```dart
      'restoreTerminalSessions': restoreTerminalSessions,
```

`layout_cubit.dart` 在 `setFloatingPreviewTabs` 之后：

```dart
  Future<void> setRestoreTerminalSessions(bool value) =>
      _save(state.preferences.copyWith(restoreTerminalSessions: value));
```

- [ ] **Step 4: 设置 UI + l10n**

`floating_en.i18n.json` 增加（保持字母序）：

```json
  "restoreTerminalSessionsDescription": "Keep floating terminal tabs across restarts; a tab reconnects only when you first open it.",
  "restoreTerminalSessionsTitle": "Restore terminal tabs",
```

`floating_zh.i18n.json`：

```json
  "restoreTerminalSessionsDescription": "重启后保留浮动终端标签，首次打开该标签时才重新连接。",
  "restoreTerminalSessionsTitle": "恢复终端标签",
```

在 `layout_appearance_in_layout_section.dart` 的 `l10n.floating.previewTabsTitle` 行块之后插入：

```dart
                TpPreferenceRow(
                  title: l10n.floating.restoreTerminalSessionsTitle,
                  subtitle: l10n.floating.restoreTerminalSessionsDescription,
                  trailing: Switch(
                    value: context.select<LayoutCubit, bool>(
                      (c) => c.state.preferences.restoreTerminalSessions,
                    ),
                    onChanged: controller.setRestoreTerminalSessions,
                  ),
                  showDividerBelow: true,
                ),
```

- [ ] **Step 5: 重新生成 l10n 并验证**

Run: `cd client && dart run slang`
Expected: 生成成功，`translations_*.g.dart` 含新 key。

Run: `cd client && dart run tool/run_tests.dart test/models/layout_preferences_default_test.dart`
Expected: PASS。

Run: `cd client && flutter analyze`
Expected: 无错误。

- [ ] **Step 6: 提交**

```bash
git add client/lib/models/layout_preferences.dart \
  client/lib/cubits/layout_cubit.dart \
  client/lib/pages/config/layout_appearance_in_layout_section.dart \
  client/lib/i18n/floating_en.i18n.json \
  client/lib/i18n/floating_zh.i18n.json \
  client/lib/l10n \
  client/test/models/layout_preferences_default_test.dart
git commit -m "feat(settings): add restore-terminal-tabs preference"
```

---

### Task 6: `WorkbenchShellLauncher.restorePersistedShell`

**Files:**
- Modify: `client/lib/services/workbench/workbench_shell_launcher.dart:389`（类末尾之前）
- Test: `client/test/services/workbench/workbench_shell_launcher_test.dart`

**Interfaces:**
- Consumes: Task 1 描述符、Task 2 `WorkbenchCubit.replaceFloatingTabId`、现有 `_sessionOps` / `_connector` / `_registry`
- Produces:
  - `Future<void> WorkbenchShellLauncher.restorePersistedShell({required String workspaceId, required String tabId, required WorkbenchShellDescriptor descriptor})`

- [ ] **Step 1: 写失败测试**

在 `test/services/workbench/workbench_shell_launcher_test.dart` 追加 import：

```dart
import 'package:teampilot/models/workbench_shell_descriptor.dart';
```

在 `group('WorkbenchShellLauncher.openAndSelect', ...)` 同级新增 group：

```dart
  group('WorkbenchShellLauncher.restorePersistedShell', () {
    late ChatCubit chat;
    late WorkbenchCubit workbench;
    late FloatingWorkspaceCubit floating;
    late WorkspaceTerminalRegistry registry;

    setUp(() {
      chat = testChatCubit(executableResolver: () => 'true');
      workbench = WorkbenchCubit();
      floating = FloatingWorkspaceCubit();
      registry = WorkspaceTerminalRegistry();
    });

    tearDown(() async {
      await chat.close();
      await workbench.close();
      await floating.close();
      registry.disposeAll();
    });

    testWidgets('creates the entry and retargets the persisted tab', (
      tester,
    ) async {
      final launcher = _launcher(
        chat: chat,
        workbench: workbench,
        floating: floating,
        registry: registry,
      );
      workbench.openFloating('ws', WorkbenchTabId.shell('persisted'));

      await launcher.restorePersistedShell(
        workspaceId: 'ws',
        tabId: 'persisted',
        descriptor: const WorkbenchShellDescriptor(
          cwd: '/tmp/proj',
          spec: WorkspaceTerminalLocalSpec('/bin/bash'),
        ),
      );
      await tester.pump();

      final entry = registry.groupFor('ws').entries.single;
      expect(entry.cwd, '/tmp/proj');
      expect(entry.spec, const WorkspaceTerminalLocalSpec('/bin/bash'));
      expect(registry.groupFor('ws').activeId, entry.id);
      expect(workbench.mergedFloatingStrip('ws').order, [
        WorkbenchTabId.shell(entry.id),
      ]);
    });

    testWidgets('a live entry short-circuits without creating a new one', (
      tester,
    ) async {
      final launcher = _launcher(
        chat: chat,
        workbench: workbench,
        floating: floating,
        registry: registry,
      );
      final entry = registry.groupFor('ws').addEntry(
        cwd: '/tmp',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        select: false,
      );
      workbench.openFloating('ws', WorkbenchTabId.shell(entry.id));

      await launcher.restorePersistedShell(
        workspaceId: 'ws',
        tabId: entry.id,
        descriptor: const WorkbenchShellDescriptor(
          cwd: '/elsewhere',
          spec: WorkspaceTerminalLocalSpec('/bin/zsh'),
        ),
      );
      await tester.pump();

      expect(registry.groupFor('ws').entries, hasLength(1));
      expect(registry.groupFor('ws').activeId, entry.id);
    });
  });
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/workbench/workbench_shell_launcher_test.dart`
Expected: 编译失败（方法不存在）。

- [ ] **Step 3: 实现**

在 `WorkbenchShellLauncher` 末尾（`openAndSelect` 之后）追加：

```dart
  /// Recreates the PTY/SSH session for a persisted floating shell tab and
  /// retargets the tab id from the persisted id to the new live entry id.
  ///
  /// Connect is deferred one frame (same "tab first, transport next" rhythm as
  /// [openAndSelect]); the entry creation is what the caller awaits.
  Future<void> restorePersistedShell({
    required String workspaceId,
    required String tabId,
    required WorkbenchShellDescriptor descriptor,
  }) async {
    final wsId = workspaceId.trim();
    final persistedId = tabId.trim();
    if (wsId.isEmpty || persistedId.isEmpty) return;

    final group = _registry.groupFor(wsId);
    final live = group.entryById(persistedId);
    if (live != null) {
      group.activeId = live.id;
      return;
    }
    if (!_workbench
        .mergedFloatingStrip(wsId)
        .order
        .contains(WorkbenchTabId.shell(persistedId))) {
      return;
    }

    final workspace = _chat.state.workspaces
        .where((w) => w.workspaceId == wsId)
        .firstOrNull;
    final folders = workspace?.folders ?? const <WorkspaceFolder>[];
    final spec = descriptor.spec;
    final home = _homeTarget();
    final launchCwd = workspaceShellLaunchWorkingDirectory(
      spec: spec,
      folders: folders,
      localCwd: descriptor.cwd,
      home: home,
      usesPosixPaths: _usesPosixPaths,
      sshDefaultWorkingDirectory: _sshDefaultWorkingDirectory(),
    );
    final entry = await _sessionOps.createEntry(
      group: group,
      connector: _connector,
      cwd: launchCwd,
      spec: spec,
      select: true,
      // Spec: a restored tab is pinned to its persisted cwd/spec; later
      // workspace cwd syncs must not rewrite it.
      followWorkspace: false,
    );

    _workbench.replaceFloatingTabId(wsId, persistedId, entry.id);

    final resolvedTheme = resolveTerminalThemeFromLayout(
      preferences: _layout.state.preferences,
      platformBrightness: _platformBrightness(),
    );
    final coordinator = WorkspaceTerminalConnectCoordinator.termuxAware(
      connector: _connector,
      termuxConnected: _termuxConnected,
      termuxWorkOpsBlockedMessage: _termuxWorkOpsBlockedMessage,
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _sessionOps.connectEntry(
          group: group,
          entry: entry,
          connectCoordinator: coordinator,
          theme: resolvedTheme,
          sshConnectFailedMessage: _sshConnectFailedMessage(),
        ),
      );
    });
  }
```

imports 追加：

```dart
import '../../models/workbench_shell_descriptor.dart';
```

- [ ] **Step 4: 运行确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/workbench/workbench_shell_launcher_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/workbench/workbench_shell_launcher.dart \
  client/test/services/workbench/workbench_shell_launcher_test.dart
git commit -m "feat(workbench): restore persisted shell tabs on demand"
```

---

### Task 7: 浮动终端 surface 懒重建 + 占位 + app 接线

**Files:**
- Modify: `client/lib/services/floating_workspace/surfaces/terminal_floating_surface.dart`
- Modify: `client/lib/i18n/workspace_en.i18n.json`, `client/lib/i18n/workspace_zh.i18n.json`
- Modify: `client/lib/app/app_shell.dart:1378-1382,2040-2049`
- Test: `client/test/services/floating_workspace/terminal_floating_surface_test.dart`（新建）

**Interfaces:**
- Consumes: Task 4 `descriptorFor`, Task 6 `restorePersistedShell`
- Produces:
  - `TerminalFloatingSurface({..., WorkbenchShellDescriptor? Function(String workspaceId, String tabId)? descriptorFor, Future<void> Function({required String workspaceId, required String tabId, required WorkbenchShellDescriptor descriptor})? restoreTab})`
  - l10n: `context.l10n.workspace.terminalRestoring`

- [ ] **Step 1: 写失败测试**

创建 `client/test/services/floating_workspace/terminal_floating_surface_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/l10n/l10n_compat.dart';
import 'package:teampilot/models/floating_workspace_tab.dart';
import 'package:teampilot/models/workbench_shell_descriptor.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/services/floating_workspace/surfaces/terminal_floating_surface.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';
import 'package:teampilot/services/terminal/workspace_terminal_run_service.dart';

const _descriptor = WorkbenchShellDescriptor(
  cwd: '/tmp/proj',
  spec: WorkspaceTerminalLocalSpec('/bin/bash'),
);

class _SurfaceHost extends StatelessWidget {
  const _SurfaceHost({required this.surface, required this.tab});

  final TerminalFloatingSurface surface;
  final FloatingTab tab;

  @override
  Widget build(BuildContext context) => surface.build(context, tab);
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: appLocalizationsSupportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: child),
);

void main() {
  test('createTab titles a persisted tab from its cwd basename', () {
    final surface = TerminalFloatingSurface(
      floating: FloatingWorkspaceCubit(),
      registry: WorkspaceTerminalRegistry(),
      runService: WorkspaceTerminalRunService(),
      descriptorFor: (_, id) => id == 'persisted' ? _descriptor : null,
    );
    final tab = surface.createTab(workspaceId: 'ws', payload: 'persisted');
    expect(tab.title, 'proj');
  });

  testWidgets('a restored tab shows the placeholder and restores once', (
    tester,
  ) async {
    final floating = FloatingWorkspaceCubit()..setActiveWorkspace('ws');
    final registry = WorkspaceTerminalRegistry();
    var calls = 0;
    final surface = TerminalFloatingSurface(
      floating: floating,
      registry: registry,
      runService: WorkspaceTerminalRunService(),
      descriptorFor: (_, id) => id == 'persisted' ? _descriptor : null,
      restoreTab:
          ({
            required String workspaceId,
            required String tabId,
            required WorkbenchShellDescriptor descriptor,
          }) async {
            calls++;
          },
    );
    final tab = surface.createTab(workspaceId: 'ws', payload: 'persisted');

    await tester.pumpWidget(_app(_SurfaceHost(surface: surface, tab: tab)));
    await tester.pump();
    await tester.pump();

    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Restoring terminal…'), findsOneWidget);
  });

  testWidgets('a failed restore shows retry and can re-run', (tester) async {
    final floating = FloatingWorkspaceCubit()..setActiveWorkspace('ws');
    var calls = 0;
    final surface = TerminalFloatingSurface(
      floating: floating,
      registry: WorkspaceTerminalRegistry(),
      runService: WorkspaceTerminalRunService(),
      descriptorFor: (_, id) => id == 'persisted' ? _descriptor : null,
      restoreTab:
          ({
            required String workspaceId,
            required String tabId,
            required WorkbenchShellDescriptor descriptor,
          }) async {
            calls++;
            throw StateError('boom');
          },
    );
    final tab = surface.createTab(workspaceId: 'ws', payload: 'persisted');

    await tester.pumpWidget(_app(_SurfaceHost(surface: surface, tab: tab)));
    await tester.pump();
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(calls, 2);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/floating_workspace/terminal_floating_surface_test.dart`
Expected: 编译失败（构造参数 / l10n key 不存在）。

- [ ] **Step 3: 实现 surface**

`terminal_floating_surface.dart`：

1. imports 追加：
```dart
import 'dart:async';

import '../../../l10n/l10n_compat.dart';
import '../../../models/workbench_shell_descriptor.dart';
import '../../../utils/logging/logger.dart';
```
2. 构造参数追加：

```dart
  TerminalFloatingSurface({
    required FloatingWorkspaceCubit floating,
    required WorkspaceTerminalRegistry registry,
    required WorkspaceTerminalRunService runService,
    WorkbenchShellDescriptor? Function(String workspaceId, String tabId)?
    descriptorFor,
    Future<void> Function({
      required String workspaceId,
      required String tabId,
      required WorkbenchShellDescriptor descriptor,
    })?
    restoreTab,
  }) : _floating = floating,
       _registry = registry,
       _runService = runService,
       _descriptorFor = descriptorFor,
       _restoreTab = restoreTab;

  final WorkbenchShellDescriptor? Function(String workspaceId, String tabId)?
  _descriptorFor;
  final Future<void> Function({
    required String workspaceId,
    required String tabId,
    required WorkbenchShellDescriptor descriptor,
  })?
  _restoreTab;

  /// Tab id → in-flight restore. One attempt per tab even if the body rebuilds
  /// or remounts mid-restore; cleared on completion so a retry can re-run.
  final Map<String, Future<bool>> _restoring = {};
```

3. `createTab` 的标题逻辑改为：

```dart
  @override
  FloatingTab createTab({required String workspaceId, Object? payload}) {
    final entryId = payload is String ? payload.trim() : '';
    final label = entryId.isEmpty
        ? ''
        : (_registry.groupFor(workspaceId).entryById(entryId)?.titleLabel ??
              '');
    final persistedTitle = entryId.isEmpty
        ? ''
        : _titleForDescriptor(_descriptorFor?.call(workspaceId, entryId));
    final title = label.trim().isNotEmpty
        ? label
        : (persistedTitle.isNotEmpty
              ? persistedTitle
              : (entryId.isEmpty ? 'Terminal' : entryId));
    return FloatingTab(
      id: entryId.isEmpty ? 'shell:' : floatingShellTabId(entryId),
      surfaceId: id,
      title: title,
      payload: entryId.isEmpty ? null : entryId,
    );
  }

  static String _titleForDescriptor(WorkbenchShellDescriptor? descriptor) {
    final cwd = descriptor?.cwd.trim().replaceAll('\\', '/') ?? '';
    if (cwd.isEmpty) return '';
    final segments = cwd.split('/').where((s) => s.isNotEmpty);
    return segments.isEmpty ? '' : segments.last;
  }
```

4. `build` 的 entry-missing 分支改为：

```dart
    final group = _registry.groupFor(workspaceId);
    final entry = group.entryById(entryId);
    if (entry == null) {
      final descriptor = _descriptorFor?.call(workspaceId, entryId);
      if (descriptor == null) return const SizedBox.shrink();
      return _RestoringTerminalBody(
        key: ValueKey('restoring-$entryId'),
        restore: () => _attemptRestore(workspaceId, entryId, descriptor),
      );
    }
    final cwd = entry.cwd.trim().isNotEmpty
        ? entry.cwd
        : (context
                  .read<ChatCubit>()
                  .state
                  .workspaces
                  .where((w) => w.workspaceId == workspaceId)
                  .firstOrNull
                  ?.firstFolderPath
                  .trim() ??
              '');
    if (cwd.isEmpty) {
      return const SizedBox.shrink();
    }
    return ShellTerminalSurface(
      workspaceId: workspaceId,
      tabScopeId: workspaceId,
      workingDirectory: cwd,
      holdHandle: FloatingTerminalPtyHoldScope.maybeOf(context),
      activeEntryId: entryId,
    );
```

5. 新增方法：

```dart
  Future<bool> _attemptRestore(
    String workspaceId,
    String tabId,
    WorkbenchShellDescriptor descriptor,
  ) {
    final restore = _restoreTab;
    if (restore == null) return Future<bool>.value(false);
    final existing = _restoring[tabId];
    if (existing != null) return existing;
    final future = () async {
      try {
        await restore(
          workspaceId: workspaceId,
          tabId: tabId,
          descriptor: descriptor,
        );
        return true;
      } on Object catch (e, st) {
        appLogger.w('[floating-shell] restore failed ($tabId): $e\n$st');
        return false;
      }
    }();
    _restoring[tabId] = future;
    unawaited(future.whenComplete(() => _restoring.remove(tabId)));
    return future;
  }
```

6. 文件末尾新增私有 widget：

```dart
/// Placeholder while a persisted shell tab rebuilds its PTY. Owns the trigger
/// (one per tab body) and the retry affordance when entry creation throws.
class _RestoringTerminalBody extends StatefulWidget {
  const _RestoringTerminalBody({required this.restore, super.key});

  final Future<bool> Function() restore;

  @override
  State<_RestoringTerminalBody> createState() => _RestoringTerminalBodyState();
}

class _RestoringTerminalBodyState extends State<_RestoringTerminalBody> {
  var _started = false;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || _started) return;
    _started = true;
    final ok = await widget.restore();
    if (!mounted) return;
    if (!ok) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    if (_failed) {
      return Center(
        child: TextButton(
          onPressed: () {
            setState(() {
              _failed = false;
              _started = false;
            });
            _start();
          },
          child: Text(l10n.retry),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.workspace.terminalRestoring,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 加 l10n key 并重新生成**

`workspace_en.i18n.json`（按文件现有排序插入）：

```json
  "terminalRestoring": "Restoring terminal…",
```

`workspace_zh.i18n.json`：

```json
  "terminalRestoring": "正在恢复终端…",
```

Run: `cd client && dart run slang`

- [ ] **Step 5: app 接线**

`app_shell.dart` 第 1378 行构造改为：

```dart
    final workbenchLayoutPersistence = WorkbenchLayoutPersistence(
      workbench: workbenchCubit,
      chat: chatCubit,
      storage: homeStorage,
      terminalRegistry: workspaceTerminalRegistry,
      restoreTerminalSessions: () =>
          layoutCubit.state.preferences.restoreTerminalSessions,
    )..start();
```

第 2040 行 surface 注册改为：

```dart
      terminal: TerminalFloatingSurface(
        floating: floatingWorkspaceCubit,
        registry: workspaceTerminalRegistry,
        runService: workspaceTerminalRunService,
        descriptorFor: workbenchLayoutPersistence.descriptorFor,
        restoreTab: resolvedShellLauncher.restorePersistedShell,
      ),
```

- [ ] **Step 6: 运行确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/floating_workspace/terminal_floating_surface_test.dart`
Expected: PASS。

Run: `cd client && flutter analyze`
Expected: 无错误。

- [ ] **Step 7: 提交**

```bash
git add client/lib/services/floating_workspace/surfaces/terminal_floating_surface.dart \
  client/lib/i18n/workspace_en.i18n.json \
  client/lib/i18n/workspace_zh.i18n.json \
  client/lib/l10n \
  client/lib/app/app_shell.dart \
  client/test/services/floating_workspace/terminal_floating_surface_test.dart
git commit -m "feat(floating): lazily restore persisted shell tabs on activation"
```

---

## 收尾验证

- [ ] Run: `cd client && flutter analyze`
- [ ] Run: `cd client && dart run tool/run_tests.dart test/models/workbench_shell_descriptor_test.dart test/cubits/workbench/workbench_split_layout_test.dart test/cubits/workbench/workbench_cubit_test.dart test/repositories/workbench_layout_snapshot_repository_test.dart test/services/workbench/workbench_layout_persistence_test.dart test/services/workbench/workbench_shell_launcher_test.dart test/services/floating_workspace/terminal_floating_surface_test.dart test/models/layout_preferences_default_test.dart`
- [ ] 手工核对：开关默认关闭 → 重启后 shell tab 被剪掉；开启 → 重启后 chip 保留、点开才出现占位并重建；SSH profile 删除 → tab 保留且终端显示连接失败。
