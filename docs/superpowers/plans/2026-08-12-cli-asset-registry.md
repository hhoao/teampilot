# CLI 资产 Registry（阶段 1：泛型核心 + HookRegistry + hook ACK 桥）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 CLI 配置资产注册架构的泛型核心与 HookRegistry 特化，收敛 7 处手写 hook merge，并用 hook ACK 桥修复"短消息（如 '1'）被重复投递 40 次"的 bug。

**Architecture:** 按资产类型拆 Registry 接口（`HookRegistry`），每 CLI 一个实现；能力通过 `AssetDeclaringCapability` 纯声明资产，Registry 在装配后主动收集（依赖反转）；渲染为纯函数输出文件级片段，落盘收敛到统一装配点；hook ACK 桥复用已有的 `/agent-status` 通道（UserPromptSubmit 事件）作为投递确认，替代不可靠的 grid 探针。

**Tech Stack:** Dart / Flutter, flutter_bloc, 现有 `CliToolRegistry` + `CliCapability` 体系。

## Global Constraints

- 遵循 `docs/superpowers/specs/2026-08-12-cli-asset-registry-design.md`（rev 4）
- 依赖反转：能力**不持有 Registry**，通过 `AssetDeclaringCapability.declaredAssets` 声明，Registry `collectDeclared` 主动收集
- Registry 不落盘：渲染纯函数输出 `Map<path, content>`，落盘由装配点（`ConfigProfileCapability`）执行
- 合并规则链：不同 id 共存追加；冲突仅同 kind+id+scope；`scope > source > level > 注册顺序`
- 不得在 services/cubits 新增 `if (cli == ...)` / `switch (cli)` 特判；CLI 差异收敛到 capability 实现
- 验证命令：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
- 每次 commit 前跑相关测试文件（`flutter test <files>`），全量验证仅在任务末尾
- 不新增 print / debug 输出；日志用 `AppLogger`

---

### Task 1: 泛型核心 `CliAssetRegistry<T>` + 资产模型

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/cli_config_asset.dart`
- Create: `client/lib/services/cli/registry/capabilities/cli_asset_registry.dart`
- Test: `client/test/services/cli/registry/capabilities/cli_asset_registry_test.dart`

**Interfaces:**
- Consumes: `CliCapability`（`client/lib/services/cli/registry/cli_capability.dart`）
- Produces:
  - `enum AssetKind { skills, mcp, plugins, hooks }`
  - `enum AssetScope { app, team, workspace, session }`
  - `enum AssetSource { capability, userConfig, pluginBundle, hubInstall }`
  - `class CliConfigAsset<T>`（kind/payload/scope/source/level/id）
  - `class AssetSeatContext`（`sessionId`, `teamId`, `workspaceId`, `memberId`, `appScope: bool`）
  - `abstract class CliAssetRegistry<T> implements CliCapability`（register/unregister/assetsFor/fingerprint/addListener）
  - `bool isAssetConflict(A, B)` — 同 kind+id+scope

- [ ] **Step 1: 写失败测试**（合并规则链 + 冲突语义）

`client/test/services/cli/registry/capabilities/cli_asset_registry_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_asset_registry.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_config_asset.dart';

void main() {
  group('CliAssetRegistry merge', () {
    test('不同 id 共存追加（集合语义）', () {
      final r = _TestRegistry();
      r.register(_asset('a', AssetScope.app));
      r.register(_asset('b', AssetScope.app));
      final out = r.assetsFor(_seat());
      expect(out.map((a) => a.id), containsAll(['a', 'b']));
    });

    test('同 id 冲突：scope 主序 session > workspace > team > app', () {
      final r = _TestRegistry();
      r.register(_asset('x', AssetScope.app, payload: 'app-payload'));
      r.register(_asset('x', AssetScope.session, payload: 'session-payload'));
      final out = r.assetsFor(_seat());
      expect(out.single.payload, 'session-payload');
    });

    test('同 id 同 scope：source 次序 capability > userConfig', () {
      final r = _TestRegistry();
      r.register(
          _asset('x', AssetScope.app, payload: 'user', source: AssetSource.userConfig));
      r.register(
          _asset('x', AssetScope.app, payload: 'cap', source: AssetSource.capability));
      expect(r.assetsFor(_seat()).single.payload, 'cap');
    });

    test('同 id 同 scope 同 source：level 数值大者优先', () {
      final r = _TestRegistry();
      r.register(_asset('x', AssetScope.app, payload: 'low', level: 1));
      r.register(_asset('x', AssetScope.app, payload: 'high', level: 9));
      expect(r.assetsFor(_seat()).single.payload, 'high');
    });

    test('unregister 后资产消失；指纹随资产集变化', () {
      final r = _TestRegistry();
      r.register(_asset('a', AssetScope.app));
      final f1 = r.fingerprint(r.assetsFor(_seat()));
      r.unregister('a');
      final f2 = r.fingerprint(r.assetsFor(_seat()));
      expect(f1, isNot(f2));
      expect(r.assetsFor(_seat()), isEmpty);
    });
  });
}

class _TestRegistry extends CliAssetRegistry<String> {}

CliConfigAsset<String> _asset(
  String id,
  AssetScope scope, {
  String payload = 'p',
  AssetSource source = AssetSource.capability,
  int level = 0,
}) =>
    CliConfigAsset(
      kind: AssetKind.hooks,
      payload: payload,
      scope: scope,
      source: source,
      level: level,
      id: id,
    );

AssetSeatContext _seat() => const AssetSeatContext(
      sessionId: 's1',
      teamId: 't1',
      workspaceId: 'w1',
      memberId: '',
    );
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/services/cli/registry/capabilities/cli_asset_registry_test.dart`
Expected: FAIL（`CliAssetRegistry` 未定义）

- [ ] **Step 3: 实现资产模型**

`client/lib/services/cli/registry/capabilities/cli_config_asset.dart`：

```dart
import 'cli_asset_registry.dart';

/// rev 4：只建已有真实消费者的类型；agents/rules/commands 有需求再补。
enum AssetKind { skills, mcp, plugins, hooks }

enum AssetScope { app, team, workspace, session }

enum AssetSource { capability, userConfig, pluginBundle, hubInstall }

/// 资产注册时带 scope；落盘时按 seat 上下文合并四层。
class CliConfigAsset<T> {
  const CliConfigAsset({
    required this.kind,
    required this.payload,
    required this.scope,
    required this.source,
    required this.level,
    required this.id,
  });

  final AssetKind kind;
  final T payload;
  final AssetScope scope;
  final AssetSource source;
  final int level;
  final String id;
}

/// 落盘时一个 seat 的完整上下文（assetsFor 的入参——不是单一 scope）。
/// app 层资产始终参与合并（最低优先级基底），无需字段标记。
class AssetSeatContext {
  const AssetSeatContext({
    required this.sessionId,
    required this.teamId,
    required this.workspaceId,
    required this.memberId,
  });

  final String sessionId;
  final String teamId;
  final String workspaceId;
  final String memberId;
}

/// 冲突定义：同 kind + 同 id + 同 scope。
bool isAssetConflict<T>(CliConfigAsset<T> a, CliConfigAsset<T> b) =>
    a.kind == b.kind && a.id == b.id && a.scope == b.scope;
```

- [ ] **Step 4: 实现泛型核心**

`client/lib/services/cli/registry/capabilities/cli_asset_registry.dart`：

```dart
import 'dart:collection';

import '../cli_capability.dart';
import 'cli_config_asset.dart';

/// 泛型核心：纯内存注册表（无 IO）。
///
/// 合并规则链（spec rev 4）：
/// 1. 不同 id → 共存追加（集合语义）
/// 2. 同 id 冲突 → scope 层级（session > workspace > team > app）
/// 3. 同 id 同 scope → source 优先级（capability > userConfig > pluginBundle > hubInstall）
/// 4. 同 id 同 scope 同 source → level（int，数值大者优先）
/// 5. 仍相同 → 后注册覆盖先注册
abstract class CliAssetRegistry<T> implements CliCapability {
  final Map<String, CliConfigAsset<T>> _byId = LinkedHashMap();
  final List<void Function()> _listeners = [];

  void register(CliConfigAsset<T> asset) {
    _byId[asset.id] = asset;
    _notify();
  }

  void unregister(String id) {
    if (_byId.remove(id) != null) _notify();
  }

  /// 按 seat 上下文合并四层 scope。app 层资产在 appScope 时加入；
  /// team/workspace/session 层按上下文匹配。
  List<CliConfigAsset<T>> assetsFor(AssetSeatContext seat) {
    final all = _byId.values.where((a) => _matchesScope(a, seat)).toList();
    final result = <CliConfigAsset<T>>[];
    for (final asset in all) {
      final i = result.indexWhere((e) => isAssetConflict(e, asset));
      if (i < 0) {
        result.add(asset);
        continue;
      }
      if (_winsOver(asset, result[i])) {
        result[i] = asset;
      }
    }
    return result;
  }

  bool _matchesScope(CliConfigAsset<T> a, AssetSeatContext seat) {
    switch (a.scope) {
      // app 层是全局默认层：始终参与合并（作为最低优先级基底）。
      case AssetScope.app:
        return true;
      case AssetScope.team:
        return seat.teamId.trim().isNotEmpty;
      case AssetScope.workspace:
        return seat.workspaceId.trim().isNotEmpty;
      case AssetScope.session:
        return seat.sessionId.trim().isNotEmpty;
    }
  }

  bool _winsOver(CliConfigAsset<T> a, CliConfigAsset<T> b) {
    final scopeRank = {
      AssetScope.session: 3,
      AssetScope.workspace: 2,
      AssetScope.team: 1,
      AssetScope.app: 0,
    };
    final sr = scopeRank[a.scope]!.compareTo(scopeRank[b.scope]!);
    if (sr != 0) return sr > 0;
    final sourceRank = {
      AssetSource.capability: 3,
      AssetSource.userConfig: 2,
      AssetSource.pluginBundle: 1,
      AssetSource.hubInstall: 0,
    };
    final or = sourceRank[a.source]!.compareTo(sourceRank[b.source]!);
    if (or != 0) return or > 0;
    if (a.level != b.level) return a.level > b.level;
    return true; // 后注册覆盖先注册（遍历顺序即注册顺序）
  }

  /// 增量重渲染指纹：资产集稳定 → 指纹稳定。
  String fingerprint(List<CliConfigAsset<T>> assets) {
    final buffer = StringBuffer();
    for (final a in assets) {
      buffer
        ..write(a.id)
        ..write('|')
        ..write(a.scope.name)
        ..write('|')
        ..write(a.source.name)
        ..write('|')
        ..write(a.level)
        ..write('|')
        ..write(a.payload.hashCode)
        ..write(';');
    }
    return buffer.toString();
  }

  void addListener(void Function() onChanged) => _listeners.add(onChanged);

  void _notify() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `cd client && flutter test test/services/cli/registry/capabilities/cli_asset_registry_test.dart`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add client/lib/services/cli/registry/capabilities/cli_config_asset.dart client/lib/services/cli/registry/capabilities/cli_asset_registry.dart client/test/services/cli/registry/capabilities/cli_asset_registry_test.dart
git commit -m "feat(cli-registry): generic CliAssetRegistry core with merge rule chain"
```

---

### Task 2: `AssetDeclaringCapability` 声明接口 + `collectDeclared`

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/asset_declaring_capability.dart`
- Modify: `client/lib/services/cli/registry/capabilities/cli_asset_registry.dart`（加 `collectDeclared`）
- Test: `client/test/services/cli/registry/capabilities/cli_asset_registry_test.dart`（追加 group）

**Interfaces:**
- Consumes: `CliCapability`, `CliConfigAsset`（Task 1）
- Produces:
  - `abstract interface class AssetDeclaringCapability implements CliCapability { List<CliConfigAsset> get declaredAssets; }`
  - `void collectDeclared(Iterable<CliCapability> capabilities)` on `CliAssetRegistry<T>`

- [ ] **Step 1: 追加失败测试**

在 `cli_asset_registry_test.dart` 追加：

```dart
group('collectDeclared', () {
  test('从能力声明收集资产', () {
    final r = _TestRegistry();
    r.collectDeclared([const _DeclaringCap([_asset('d', AssetScope.app)])]);
    expect(r.assetsFor(_seat()).single.id, 'd');
  });

  test('非声明能力被跳过', () {
    final r = _TestRegistry();
    r.collectDeclared([const _DeclaringCap([])]);
    expect(r.assetsFor(_seat()), isEmpty);
  });
});

class _DeclaringCap implements CliCapability, AssetDeclaringCapability {
  const _DeclaringCap(this.assets);
  final List<CliConfigAsset<String>> assets;
  @override
  List<CliConfigAsset> get declaredAssets => assets;
}
```

注意：`CliCapability` 是 `abstract interface class`（空接口），必须 `implements` 而非 `extends`；测试文件需 import `package:teampilot/services/cli/registry/cli_capability.dart`。

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/services/cli/registry/capabilities/cli_asset_registry_test.dart`
Expected: FAIL（`AssetDeclaringCapability` / `collectDeclared` 未定义）

- [ ] **Step 3: 实现声明接口 + collectDeclared**

`client/lib/services/cli/registry/capabilities/asset_declaring_capability.dart`：

```dart
import '../cli_capability.dart';
import 'cli_config_asset.dart';

/// 能力侧纯声明资产（依赖反转：能力不持有 Registry）。
///
/// 惰性 getter：可依赖运行时数据（如 session 才知道的 ack endpoint）。
abstract interface class AssetDeclaringCapability implements CliCapability {
  List<CliConfigAsset> get declaredAssets;
}
```

在 `cli_asset_registry.dart` 的 `CliAssetRegistry<T>` 中加入：

```dart
import 'asset_declaring_capability.dart';

  /// 通道 ②：从能力的声明收集。时序：必须在 registerBuiltInCliTools
  /// 完成之后统一调用一次（能力集合启动时固定）。
  void collectDeclared(Iterable<CliCapability> capabilities) {
    for (final cap in capabilities) {
      if (cap is AssetDeclaringCapability) {
        for (final asset in cap.declaredAssets) {
          if (asset is CliConfigAsset<T>) {
            register(asset as CliConfigAsset<T>);
          }
        }
      }
    }
  }
```

检查 `cli_capability.dart`：`CliCapability` 是 `abstract interface class`（空接口，无成员），测试里必须 `implements`：

```dart
class _DeclaringCap implements CliCapability, AssetDeclaringCapability {
  const _DeclaringCap(this.assets);
  final List<CliConfigAsset<String>> assets;
  @override
  List<CliConfigAsset> get declaredAssets => assets;
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter test test/services/cli/registry/capabilities/cli_asset_registry_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/cli/registry/capabilities/asset_declaring_capability.dart client/lib/services/cli/registry/capabilities/cli_asset_registry.dart client/test/services/cli/registry/capabilities/cli_asset_registry_test.dart
git commit -m "feat(cli-registry): AssetDeclaringCapability + collectDeclared"
```

---

### Task 3: `HookRegistry` 特化 + `CliHookSpec` + `ClaudeFamilyHookRegistry`

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/hook_registry.dart`
- Create: `client/lib/services/cli/registry/capabilities/claude_family_hook_registry.dart`
- Test: `client/test/services/cli/registry/capabilities/claude_family_hook_registry_test.dart`

**Interfaces:**
- Consumes: `CliAssetRegistry<T>`、`CliConfigAsset`（Task 1）
- Produces:
  - `class CliHookSpec { final String event; final String? url; final Map<String,String> headers; final Duration? timeout; final bool blockOnDecision; }`（`event` 为规范事件名，如 `promptSubmit`/`stop`）
  - `class GeneratedScript { final String fileName; final String content; }`
  - `abstract interface class HookRegistry extends CliAssetRegistry<CliHookSpec>`
    - `Map<String, String> get eventNameMap`（规范事件 → CLI 原生事件名）
    - `Map<String, Object?> render(List<CliConfigAsset<CliHookSpec>> assets)` — 输出该 CLI 配置文件的 hooks 段（key 为文件相对路径）
    - `List<GeneratedScript> generateScripts(...)`
  - `final class ClaudeFamilyHookRegistry extends CliAssetRegistry<CliHookSpec> implements HookRegistry`（claude + flashskyai 共享）

- [ ] **Step 1: 写失败测试**

`client/test/services/cli/registry/capabilities/claude_family_hook_registry_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_asset_registry.dart';
import 'package:teampilot/services/cli/registry/capabilities/claude_family_hook_registry.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_registry.dart';

void main() {
  final registry = ClaudeFamilyHookRegistry(); // 有可变状态，不能 const

  group('ClaudeFamilyHookRegistry.render', () {
    test('http hook 渲染为 settings.json hooks 段（幂等可合并）', () {
      final out = registry.render([
        hookAsset('ack', CliHookSpec(
          event: 'promptSubmit',
          url: 'http://127.0.0.1:1/agent-status?event=promptSubmit',
          headers: const {'X-Member': 'm1'},
          timeout: const Duration(seconds: 5),
        )),
      ]);
      final hooks = (out['settings.json'] as Map)['hooks'] as Map;
      final entries = hooks['UserPromptSubmit'] as List;
      expect(entries.single['hooks'], isA<List>());
      final h = (entries.single['hooks'] as List).single as Map;
      expect(h['type'], 'http');
      expect(h['url'], contains('/agent-status?event=promptSubmit'));
      expect(h['timeout'], 5);
    });

    test('eventNameMap: promptSubmit → UserPromptSubmit', () {
      expect(registry.eventNameMap['promptSubmit'], 'UserPromptSubmit');
      expect(registry.eventNameMap['stop'], 'Stop');
    });

    test('command hook 生成脚本', () {
      final scripts = registry.generateScripts([
        hookAsset('idle', CliHookSpec(
          event: 'stop',
          command: 'bash stop-idle.sh',
          blockOnDecision: true,
        )),
      ]);
      expect(scripts, isNotEmpty);
    });
  });
}

CliConfigAsset<CliHookSpec> hookAsset(String id, CliHookSpec spec) =>
    CliConfigAsset(
      kind: AssetKind.hooks,
      payload: spec,
      scope: AssetScope.app,
      source: AssetSource.capability,
      level: 0,
      id: id,
    );
```

注意：`CliHookSpec` 需要 `command` 字段（上例使用）；`hookAsset` 用到的 `AssetSeatContext` 不需要。

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/services/cli/registry/capabilities/claude_family_hook_registry_test.dart`
Expected: FAIL（未定义）

- [ ] **Step 3: 实现 `CliHookSpec` + `HookRegistry` 接口**

`client/lib/services/cli/registry/capabilities/hook_registry.dart`：

```dart
import 'cli_asset_registry.dart';
import 'cli_config_asset.dart';

/// 统一 hook 声明（能力侧只写这个，不碰原始 map）。
class CliHookSpec {
  const CliHookSpec({
    required this.event,
    this.url,
    this.headers = const {},
    this.timeout,
    this.command,
    this.blockOnDecision = false,
  });

  /// 规范事件名：promptSubmit / stop / questionAsked / permissionAsked / ...
  final String event;

  /// http 类 hook 目标（与 [command] 二选一）。
  final String? url;
  final Map<String, String> headers;
  final Duration? timeout;

  /// command 类 hook（脚本路径或内容引用）。
  final String? command;

  /// 是否需要解析 decision:block（idle 类钩子）。
  final bool blockOnDecision;
}

class GeneratedScript {
  const GeneratedScript({required this.fileName, required this.content});
  final String fileName;
  final String content;
}

/// hooks 特化：只加"资产 → 配置文件片段"。
abstract interface class HookRegistry extends CliAssetRegistry<CliHookSpec> {
  /// 规范事件 → CLI 原生事件名映射。
  Map<String, String> get eventNameMap;

  /// 纯函数：资产集 → 该 CLI 的配置文件片段（幂等）。
  /// 输出为文件级（Map<relativePath, content>），不假设进 settings.json。
  Map<String, Object?> render(List<CliConfigAsset<CliHookSpec>> assets);

  /// command 类 hook 的脚本内容。
  List<GeneratedScript> generateScripts(List<CliConfigAsset<CliHookSpec>> assets);
}
```

- [ ] **Step 4: 实现 `ClaudeFamilyHookRegistry`**

`client/lib/services/cli/registry/capabilities/claude_family_hook_registry.dart`：

```dart
import 'cli_asset_registry.dart';
import 'cli_config_asset.dart';
import 'hook_registry.dart';

/// claude / flashskyai 共享：settings.json `hooks` 段的渲染实现。
/// 语法收敛自 agent_status_hooks.dart + bus_idle_stop_hook.dart。
/// 有可变状态（继承 CliAssetRegistry 的注册表），不可 const。
final class ClaudeFamilyHookRegistry extends CliAssetRegistry<CliHookSpec>
    implements HookRegistry {
  ClaudeFamilyHookRegistry();

  @override
  Map<String, String> get eventNameMap => const {
    'promptSubmit': 'UserPromptSubmit',
    'stop': 'Stop',
  };

  /// 幂等合并：按 (event, url|command) 查重，重复不追加。
  Map<String, Object?> render(List<CliConfigAsset<CliHookSpec>> assets) {
    final hooks = <String, Object?>{};
    for (final asset in assets) {
      final spec = asset.payload;
      final nativeEvent = eventNameMap[spec.event] ?? spec.event;
      final entries =
          List<Object?>.from((hooks[nativeEvent] as List?) ?? const []);
      final entry = <String, Object?>{
        'hooks': [
          if (spec.url != null)
            {
              'type': 'http',
              'url': spec.url,
              'headers': spec.headers,
              if (spec.timeout != null)
                'timeout': spec.timeout!.inSeconds,
            }
          else if (spec.command != null)
            {'type': 'command', 'command': spec.command, 'timeout': 5},
        ],
      };
      final dupKey = spec.url ?? spec.command;
      final exists = entries.any(
        (e) =>
            e is Map &&
            (e['hooks'] as List?)?.any(
                  (h) =>
                      h is Map &&
                      ((h['url'] ?? h['command']) == dupKey),
                ) ==
                true,
      );
      if (!exists) entries.add(entry);
      hooks[nativeEvent] = entries;
    }
    return {'settings.json': {'hooks': hooks}};
  }

  @override
  List<GeneratedScript> generateScripts(
    List<CliConfigAsset<CliHookSpec>> assets,
  ) {
    // claude-family 的 Stop → /idle 用 HTTP hook 而非脚本（flashskyai 例外，
    // 其 command 脚本在 flashskyai 特化中生成——见阶段 1 范围说明）。
    return const [];
  }
}
```

注意：flashskyai 的 Stop → /idle 是 command 脚本（exit 2 语义），需要 flashskyai 特化或在本类用 `blockOnDecision` 分支生成 curl 脚本——实现时按 `assets` 中 `blockOnDecision && command == null` 的 spec 生成脚本（见 Task 4 迁移）。

- [ ] **Step 5: 运行测试确认通过**

Run: `cd client && flutter test test/services/cli/registry/capabilities/claude_family_hook_registry_test.dart`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add client/lib/services/cli/registry/capabilities/hook_registry.dart client/lib/services/cli/registry/capabilities/claude_family_hook_registry.dart client/test/services/cli/registry/capabilities/claude_family_hook_registry_test.dart
git commit -m "feat(cli-registry): HookRegistry specialization + ClaudeFamilyHookRegistry"
```

---

### Task 4: 迁移 `agent_status_hooks.dart` 与 `bus_idle_stop_hook.dart` 到 ClaudeFamilyHookRegistry

**Files:**
- Modify: `client/lib/services/cli/claude/capabilities/config_profile.dart:769-775`（装配点）
- Modify: `client/lib/services/cli/flashskyai/capabilities/config_profile.dart:310`（装配点）
- Modify: `client/lib/services/cli/flashskyai/capabilities/stop_idle_hook.dart`（保留脚本生成函数，供迁移期使用）
- Test: `client/test/services/provider/claude/claude_config_profile_hook_test.dart`（新建，断言 settings 含合并后的 hooks 段）

**Interfaces:**
- Consumes: `ClaudeFamilyHookRegistry`、`CliHookSpec`（Task 3）
- Produces: 装配点行为：写 settings 前调用 `claudeHooks.render(assets)` 并合并进 settings

**背景（关键事实）**：`agent_status_hooks.dart` 的 8 个事件 URL 都带 `?event=<name>` 防去重；`bus_idle_stop_hook.dart` 的 Stop → `/idle` 在 mixed 模式才装。迁移后这些 hook 由**能力声明**驱动（Task 5 的 `AgentStatusHooksCapability` 和 BusIdle 能力声明资产），本任务先让装配点消费 `HookRegistry.render`，旧 merge 函数保留到 Task 5 替换声明源。

- [ ] **Step 1: 写失败测试**

`client/test/services/provider/claude/claude_config_profile_hook_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/claude_family_hook_registry.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_registry.dart';

void main() {
  test('ClaudeFamilyHookRegistry 渲染结果可并入 settings.json', () {
    final r = ClaudeFamilyHookRegistry();
    final rendered = r.render([
      // 模拟 agent-status 的 8 事件中的 UserPromptSubmit + Stop
      _asset('agent-status', CliHookSpec(
        event: 'promptSubmit',
        url: 'http://127.0.0.1:9/agent-status?event=UserPromptSubmit',
        headers: const {'X-Member': 'm'},
        timeout: const Duration(seconds: 5),
      )),
      _asset('bus-idle', CliHookSpec(
        event: 'stop',
        url: 'http://127.0.0.1:9/idle',
        headers: const {'X-Member': 'm'},
      )),
    ]);
    final settings = <String, Object?>{'model': 'x'};
    final merged = mergeHooksInto(settings, rendered['settings.json'] as Map);
    final hooks = merged['hooks'] as Map;
    expect((hooks['UserPromptSubmit'] as List), hasLength(1));
    expect((hooks['Stop'] as List), hasLength(1));
    expect(merged['model'], 'x'); // 其余 settings 保留
  });
}

CliConfigAsset<CliHookSpec> _asset(String id, CliHookSpec spec) =>
    CliConfigAsset(
      kind: AssetKind.hooks,
      payload: spec,
      scope: AssetScope.app,
      source: AssetSource.capability,
      level: 0,
      id: id,
    );
```

`mergeHooksInto` 需要实现（放在 `claude_family_hook_registry.dart` 导出）：

```dart
Map<String, Object?> mergeHooksInto(
  Map<String, Object?> settings,
  Map<String, Object?> hooksSection,
) {
  final merged = Map<String, Object?>.from(settings);
  final hooks = Map<String, Object?>.from(
    (merged['hooks'] as Map?)?.cast<String, Object?>() ?? const {},
  );
  for (final entry in (hooksSection['hooks'] as Map).entries) {
    final event = entry.key as String;
    final incoming = List<Object?>.from((entry.value as List?) ?? const []);
    final existing = List<Object?>.from((hooks[event] as List?) ?? const []);
    for (final inc in incoming) {
      if (!existing.any((e) => _sameHookEntry(e, inc))) existing.add(inc);
    }
    hooks[event] = existing;
  }
  merged['hooks'] = hooks;
  return merged;
}

bool _sameHookEntry(Object? a, Object? b) {
  if (a is! Map || b is! Map) return false;
  final ha = a['hooks'];
  final hb = b['hooks'];
  if (ha is! List || hb is! List || ha.isEmpty || hb.isEmpty) return false;
  final fa = ha.first as Map;
  final fb = hb.first as Map;
  return (fa['url'] ?? fa['command']) == (fb['url'] ?? fb['command']);
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/services/provider/claude/claude_config_profile_hook_test.dart`
Expected: FAIL（`mergeHooksInto` 未定义）

- [ ] **Step 3: 实现 `mergeHooksInto`（加入 claude_family_hook_registry.dart）**

按 Step 1 代码实现，并加导出。

- [ ] **Step 4: 接入 claude 装配点**

`client/lib/services/cli/claude/capabilities/config_profile.dart` 中 `_writeMemberSettings`（约 757-781 行），在 `writeSettingsFile` 前把 `mergeAgentStatusHooks` / `mergeStopIdleHook` 替换为 Registry 渲染（保留条件，见 Task 5 注释）：

```dart
// 迁移期：先由旧 merge 保持行为，同时并入 Registry 资产（Task 5 移除旧 merge）
if (mixed && busIdle != null) {
  settings = mergeStopIdleHook(settings, member.id, busIdle);
}
if (agentStatus != null) {
  settings = mergeAgentStatusHooks(settings, member.id, agentStatus);
}
// 新通道：ClaudeFamilyHookRegistry 资产渲染（Task 5 前为空集合，行为不变）
final hookRegistry = ctx.hookRegistry; // 经 ConfigProfileContext 注入（Task 5 接线）
if (hookRegistry != null) {
  final assets = hookRegistry.assetsFor(seatContextFrom(ctx));
  if (assets.isNotEmpty) {
    final rendered = hookRegistry.render(assets);
    settings = mergeHooksInto(
      settings,
      rendered['settings.json'] as Map? ?? const {},
    );
  }
}
```

`ctx.hookRegistry` 与 `seatContextFrom` 为 Task 5 引入（本任务先加编译占位，Task 5 完成接线）。为保持本任务可编译，可先注入 `CliToolRegistry` 并 `capability<HookRegistry>(CliTool.claude)` 查询（与 `_crAckForMember` 同模式）。

- [ ] **Step 5: 运行测试确认通过**

Run: `cd client && flutter test test/services/provider/claude/claude_config_profile_hook_test.dart && flutter test test/services/cli/registry/capabilities/claude_family_hook_registry_test.dart`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add client/lib/services/cli/registry/capabilities/claude_family_hook_registry.dart client/lib/services/cli/claude/capabilities/config_profile.dart client/test/services/provider/claude/claude_config_profile_hook_test.dart
git commit -m "refactor(cli-registry): wire ClaudeFamilyHookRegistry into claude config profile"
```

---

### Task 5: `AgentStatusHooksCapability` + BusIdle 能力声明资产（依赖反转落地）

**Files:**
- Create: `client/lib/services/agent_status/agent_status_hooks_capability.dart`
- Create: `client/lib/services/team_bus/bus_idle_hooks_capability.dart`
- Modify: `client/lib/services/cli/claude/claude_tool.dart`（挂载能力）
- Modify: `client/lib/services/cli/flashskyai/flashskyai_tool.dart`（挂载能力）
- Modify: `client/lib/app/app_shell.dart`（collectDeclared 时序）
- Modify: `client/lib/services/cli/registry/built_in_cli_tools.dart`（collectDeclared 调用）

**Interfaces:**
- Consumes: `AssetDeclaringCapability`（Task 2）、`CliHookSpec`（Task 3）、`ConfigProfileContext`（agentStatus/busIdle 注入）
- Produces:
  - `final class AgentStatusHooksCapability implements AssetDeclaringCapability` — 声明 8 个 agent-status hook 资产（事件: PermissionRequest/PreToolUse/PostToolUse/PostToolUseFailure/Stop/StopFailure/UserPromptSubmit，URL 带 `?event=` 防去重）
  - `final class BusIdleHooksCapability implements AssetDeclaringCapability` — 声明 Stop → /idle（`blockOnDecision: true`）
  - `app_shell.dart` 在 `cliToolRegistry.configure(...)` 之后调用各 CLI Registry 的 `collectDeclared`

**关键设计**：agent-status 的 URL/headers 依赖运行时 endpoint（`MemberAgentStatusEndpoint`）。`AgentStatusHooksCapability` 的 `declaredAssets` 是惰性 getter——但 endpoint 在 session 启动才知道，**不能**在 app 启动的 collectDeclared 时求值。方案：能力持有 `endpoint` 可更新字段（`updateEndpoint(...)`），collectDeclared 在**每次 launch 前**重新调用（或 assetsFor 时惰性求值）。

为简化阶段 1：`AgentStatusHooksCapability` 的 `declaredAssets` 返回"事件名集合 + 占位 URL"，`ClaudeFamilyHookRegistry.render` 收到 `CliHookSpec` 时若 `url == null` 则跳过渲染（URL 在装配点从 `ctx.agentStatus` 补全——装配点调用 `render` 前先 `resolveEndpoint`）。

**实际落地（更简单）**：阶段 1 不改 agent-status hook 的注入源——`mergeAgentStatusHooks` 继续使用（Task 4 已保留），本任务只做 **BusIdle 能力声明** + **collectDeclared 接线**，验证依赖反转端到端（agent-status 迁移列入阶段 1.5 后续）。若实现时发现 `mergeAgentStatusHooks` 可以直接改写为 `AgentStatusHooksCapability` + render（URL 由装配点补全），优先后者。

- [ ] **Step 1: 写失败测试**

`client/test/services/cli/registry/capabilities/bus_idle_hooks_capability_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/bus_idle_hooks_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/asset_declaring_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_config_asset.dart';

void main() {
  test('BusIdleHooksCapability 声明 stop → /idle 资产', () {
    const cap = BusIdleHooksCapability();
    final assets = cap.declaredAssets;
    expect(assets, hasLength(1));
    final a = assets.single;
    expect(a.kind, AssetKind.hooks);
    expect(a.scope, AssetScope.session);
    expect(a.source, AssetSource.capability);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/services/cli/registry/capabilities/bus_idle_hooks_capability_test.dart`
Expected: FAIL（未定义）

- [ ] **Step 3: 实现 BusIdleHooksCapability**

`client/lib/services/team_bus/bus_idle_hooks_capability.dart`：

```dart
import '../cli/registry/capabilities/asset_declaring_capability.dart';
import '../cli/registry/capabilities/cli_config_asset.dart';
import '../cli/registry/capabilities/hook_registry.dart';

/// mixed 模式：声明 Stop → /idle hook（blockOnDecision 语义）。
/// URL/headers 由装配点从 ctx.busIdle 补全（见 ClaudeFamilyHookRegistry.render）。
final class BusIdleHooksCapability implements AssetDeclaringCapability {
  const BusIdleHooksCapability();

  @override
  List<CliConfigAsset> get declaredAssets => [
    const CliConfigAsset(
      kind: AssetKind.hooks,
      payload: CliHookSpec(
        event: 'stop',
        blockOnDecision: true,
      ),
      scope: AssetScope.session,
      source: AssetSource.capability,
      level: 0,
      id: 'bus-idle-stop',
    ),
  ];
}
```

- [ ] **Step 4: 接线 collectDeclared**

`built_in_cli_tools.dart` 中 `registerBuiltInCliTools` 末尾（各 tool 注册后）：

```dart
// 依赖反转：Registry 从能力声明收集资产（能力集合启动时固定）。
for (final def in registry.launchable) {
  for (final cap in def.capabilities) {
    if (cap is CliAssetRegistry) {
      (cap as CliAssetRegistry).collectDeclared(def.capabilities);
    }
  }
}
```

`app_shell.dart` 装配处把 `BusIdleHooksCapability` 加入 claude/flashskyai tool 构造（`busIdleHooks: const BusIdleHooksCapability()`），并在 `CliToolDefinition.capabilities` 列表中挂载（同步改 claude_tool.dart / flashskyai_tool.dart）。

- [ ] **Step 5: 运行测试确认通过**

Run: `cd client && flutter test test/services/cli/registry/capabilities/bus_idle_hooks_capability_test.dart && flutter test test/services/cli/registry/capabilities/cli_asset_registry_test.dart`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add client/lib/services/team_bus/bus_idle_hooks_capability.dart client/lib/services/cli/registry/built_in_cli_tools.dart client/lib/services/cli/claude/claude_tool.dart client/lib/services/cli/flashskyai/flashskyai_tool.dart client/lib/app/app_shell.dart client/test/services/cli/registry/capabilities/bus_idle_hooks_capability_test.dart
git commit -m "feat(cli-registry): BusIdleHooksCapability declared assets + collectDeclared wiring"
```

---

### Task 6: hook ACK 桥 — AgentStatusEvent 携带 prompt 文本

**Files:**
- Modify: `client/lib/services/agent_status/agent_status_event.dart`（加 `prompt` 字段）
- Modify: `client/lib/services/cli/registry/capabilities/claude_family_agent_status_normalizer.dart`（提取 prompt）
- Modify: `client/lib/services/cli/cursor/capabilities/agent_status_normalizer.dart`（提取 prompt，若 payload 有）
- Modify: `client/lib/services/cli/opencode/capabilities/agent_status_normalizer.dart`（透传 message/prompt）
- Test: `client/test/services/agent_status/agent_status_normalizer_test.dart`（追加用例）

**Interfaces:**
- Consumes: `AgentStatusEvent`（现有）、`readPayloadString`
- Produces: `AgentStatusEvent.prompt`（`String?`）——UserPromptSubmit 等事件的 prompt 原文

**背景**：Claude Code 的 `UserPromptSubmit` hook payload 含 `prompt` 字段；当前 normalizer 只提取 `hookEventName`。ACK 桥需要 prompt 文本与注入文本匹配。

- [ ] **Step 1: 追加失败测试**

`agent_status_normalizer_test.dart` 追加：

```dart
test('Claude UserPromptSubmit 携带 prompt 原文', () {
  final e = AgentStatusNormalizer.normalize(
    cli: CliTool.claude,
    body: {
      'hook_event_name': 'UserPromptSubmit',
      'prompt': '1',
    },
  );
  expect(e?.prompt, '1');
});

test('非 UserPromptSubmit 事件 prompt 为 null', () {
  final e = AgentStatusNormalizer.normalize(
    cli: CliTool.claude,
    body: {'hook_event_name': 'Stop'},
  );
  expect(e?.prompt, isNull);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/services/agent_status/agent_status_normalizer_test.dart`
Expected: FAIL（`prompt` 未定义）

- [ ] **Step 3: 实现**

`agent_status_event.dart` 加字段：

```dart
  /// UserPromptSubmit 事件的 prompt 原文（投递 ACK 匹配用）。
  final String? prompt;
```

构造参数、`copyWith`、`==`/`hashCode` 同步（`prompt ?? this.prompt` 模式）。

`claude_family_agent_status_normalizer.dart` 的 `build` 中：

```dart
  final prompt = readPayloadString(body, const ['prompt']);
  // ...
  AgentStatusEvent build(AgentSeatAttention state, {bool explicit = false}) =>
      AgentStatusEvent(
        // ...
        prompt: prompt,
      );
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter test test/services/agent_status/agent_status_normalizer_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/agent_status/agent_status_event.dart client/lib/services/cli/registry/capabilities/claude_family_agent_status_normalizer.dart client/test/services/agent_status/agent_status_normalizer_test.dart
git commit -m "feat(agent-status): carry prompt text in AgentStatusEvent"
```

---

### Task 7: hook ACK 桥 — 投递确认注册表 + 重试取消

**Files:**
- Create: `client/lib/services/terminal/prompt_submit_ack_tracker.dart`
- Modify: `client/lib/services/agent_status/agent_status_http_handler.dart`（匹配 pending 并完成）
- Modify: `client/lib/cubits/chat/tab_member_pty_delivery.dart`（投递前注册 pending，ACK 后取消重试）
- Modify: `client/lib/services/terminal/member_pty_inject_service.dart`（暴露 hasPendingRetry/clearPending 已存在；新增 ack 检查回调）
- Test: `client/test/services/terminal/prompt_submit_ack_tracker_test.dart`
- Test: `client/test/services/agent_status/agent_status_http_handler_test.dart`（若存在，追加）

**Interfaces:**
- Consumes: `AgentStatusEvent.prompt`（Task 6）、`MemberPtyInjectService`（现有）
- Produces:
  - `final class PromptSubmitAckTracker` — 注册/匹配/超时清理
    - `Future<void> register({required String sessionId, required String memberId, required String text, required String cli})` → 返回一个 Future，ACK 命中或超时完成
    - `bool tryAck({required String sessionId, required String memberId, required String text})` — 命中返回 true（pending 移除并完成 future）
    - `void clear(String sessionId, String memberId)`

**设计**：投递路径（`deliverMemberStdin` / `retryMemberDelivery`）在 `_ptyInject.deliver`/`retry` **之前**注册 pending；`AgentStatusHttpHandler` 在 `attention.applyEvent` 后调用 `tracker.tryAck(...)`（用 `event.prompt`）；ACK 命中 → 通知投递方（通过 shared tracker 的 future）→ 投递方标记 `submitted` 并 `clearPending`（取消重试队列），**不再走 grid 探针重试**。

**关键**：ACK 只作为"提前确认"优化 + 取消重试的守卫——grid 探针保留为兜底（hook 通道缺失时行为不变）。

- [ ] **Step 1: 写失败测试**

`client/test/services/terminal/prompt_submit_ack_tracker_test.dart`：

```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/prompt_submit_ack_tracker.dart';

void main() {
  test('注册后 ACK 命中完成 future', () async {
    final tracker = PromptSubmitAckTracker();
    final f = tracker.register(
      sessionId: 's1', memberId: 'm1', text: '1',
    );
    expect(tracker.tryAck(sessionId: 's1', memberId: 'm1', text: '1'), isTrue);
    expect(await f, isTrue);
  });

  test('文本不匹配不命中', () async {
    final tracker = PromptSubmitAckTracker();
    final f = tracker.register(
      sessionId: 's1', memberId: 'm1', text: '1',
    );
    expect(tracker.tryAck(sessionId: 's1', memberId: 'm1', text: '其他'), isFalse);
    expect(await f.timeout(const Duration(milliseconds: 50),
        onTimeout: () => false), isFalse);
  });

  test('clear 后不再命中', () async {
    final tracker = PromptSubmitAckTracker();
    tracker.register(sessionId: 's1', memberId: 'm1', text: '1');
    tracker.clear('s1', 'm1');
    expect(tracker.tryAck(sessionId: 's1', memberId: 'm1', text: '1'), isFalse);
  });

  test('多 seat 互不干扰', () async {
    final tracker = PromptSubmitAckTracker();
    final fa = tracker.register(sessionId: 's1', memberId: 'm1', text: '1');
    final fb = tracker.register(sessionId: 's2', memberId: 'm1', text: '1');
    expect(tracker.tryAck(sessionId: 's2', memberId: 'm1', text: '1'), isTrue);
    expect(await fb, isTrue);
    expect(tracker.tryAck(sessionId: 's1', memberId: 'm1', text: '1'), isFalse);
    unawaited(fa);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/services/terminal/prompt_submit_ack_tracker_test.dart`
Expected: FAIL（未定义）

- [ ] **Step 3: 实现 PromptSubmitAckTracker**

`client/lib/services/terminal/prompt_submit_ack_tracker.dart`：

```dart
import 'dart:async';

/// 投递 ACK 注册表：注入前注册 pending，hook 事件命中时完成。
/// 文本完全匹配（trim 后）；每个 seat 同时最多一个 pending。
final class PromptSubmitAckTracker {
  final Map<String, _Pending> _pending = {};

  Future<bool> register({
    required String sessionId,
    required String memberId,
    required String text,
  }) {
    final key = _key(sessionId, memberId);
    final existing = _pending.remove(key);
    existing?.completer.complete(false);
    final completer = Completer<bool>();
    _pending[key] = _Pending(
      text: text.trim(),
      completer: completer,
    );
    return completer.future;
  }

  bool tryAck({
    required String sessionId,
    required String memberId,
    required String text,
  }) {
    final pending = _pending.remove(_key(sessionId, memberId));
    if (pending == null) return false;
    if (pending.text != text.trim()) {
      // 不匹配：不消耗 pending（等真正命中或超时清理）
      _pending[_key(sessionId, memberId)] = pending;
      return false;
    }
    pending.completer.complete(true);
    return true;
  }

  void clear(String sessionId, String memberId) {
    final removed = _pending.remove(_key(sessionId, memberId));
    if (removed != null && !removed.completer.isCompleted) {
      removed.completer.complete(false);
    }
  }

  static String _key(String sessionId, String memberId) =>
      '${sessionId.trim()}\u0000${memberId.trim()}';
}

final class _Pending {
  const _Pending({required this.text, required this.completer});
  final String text;
  final Completer<bool> completer;
}
```

- [ ] **Step 4: 接线 handler**

`agent_status_http_handler.dart`：构造参数加 `this.promptAckTracker`（可选）；`handle` 中 `attention.applyEvent` 之后：

```dart
final acked = promptAckTracker?.tryAck(
  sessionId: sessionId,
  memberId: memberId,
  text: event.prompt ?? '',
) ?? false;
if (acked) {
  appLogger.d('[ai-history] prompt-submit acked session=$sessionId member=$memberId');
}
```

- [ ] **Step 5: 接线投递方**

`tab_member_pty_delivery.dart`：
- 构造参数注入 `PromptSubmitAckTracker`（经 `TabMemberPtyDelivery` 构造，`app_shell` 创建单例传入 `ChatCubit`）
- `deliverMemberStdin` 的 `_deliverFullScreen` 分支、`retryMemberDelivery`、`retryAutomationTick`：在 `_ptyInject.deliver`/`retry` 调用前：

```dart
final ackFuture = _promptAckTracker.register(
  sessionId: sessionId,
  memberId: memberId,
  text: trimmed,
);
// 并行等待 ACK：命中 → 视为 submitted，清空重试队列
ackFuture.then((acked) {
  if (acked) {
    _ptyInject.clearPending(sessionId, memberId);
    if (isOperatorTurn) {
      _markMemberTurnStartedOnSubmitSuccess(sessionId, memberId);
    }
  }
}).ignore();
```

（ACK 完成不取消已进行中的探针投递——投递幂等性由 `submitted` 结果保证；`_handleOutcome` 的 crStuck 重试队列在 ACK 到达后被 clear，不产生重贴。）

- [ ] **Step 6: 运行测试确认通过**

Run: `cd client && flutter test test/services/terminal/prompt_submit_ack_tracker_test.dart && flutter test test/services/terminal/member_pty_inject_service_test.dart && flutter test test/services/terminal/fullscreen_pty_automation_test.dart`
Expected: PASS

- [ ] **Step 7: 提交**

```bash
git add client/lib/services/terminal/prompt_submit_ack_tracker.dart client/lib/services/agent_status/agent_status_http_handler.dart client/lib/cubits/chat/tab_member_pty_delivery.dart client/test/services/terminal/prompt_submit_ack_tracker_test.dart
git commit -m "feat(pty): prompt-submit ACK tracker cancels crStuck retry storm"
```

---

### Task 8: opencode 插件补事件上报 + 全量验证

**Files:**
- Modify: `client/lib/services/cli/opencode/capabilities/agent_status_plugin.dart`（事件流转发 user message 提交）
- Modify: `client/lib/services/cli/opencode/capabilities/agent_status_normalizer.dart`（解析新事件 → prompt）
- Test: `client/test/services/cli/opencode/capabilities/agent_status_normalizer_test.dart`（若存在，追加）

**Interfaces:**
- Consumes: Task 6 的 `AgentStatusEvent.prompt`
- Produces: opencode 事件流中 user 消息提交事件 → POST `/agent-status`（`event: userMessageSubmitted, prompt: <text>`）→ normalizer 产出 `AgentStatusEvent(state: working, prompt: text, hookEventName: 'userMessageSubmitted')`

**背景**：opencode 插件当前只转发 `question.*`/`permission.*`/`session.idle`。需在 `event` handler 加分支：opencode 事件流中 user 消息提交对应 `session.updated`（含新 message part）或专用消息事件——实现时以本机 opencode 版本实测事件名（`event.type`），代码注释记录版本。

- [ ] **Step 1: 写失败测试**

在 opencode normalizer 测试中追加（若文件不存在则新建）：

```dart
test('opencode userMessageSubmitted → working + prompt', () {
  final e = AgentStatusNormalizer.normalize(
    cli: CliTool.opencode,
    body: {'event': 'userMessageSubmitted', 'prompt': '1'},
  );
  expect(e?.state, AgentSeatAttention.working);
  expect(e?.prompt, '1');
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/services/cli/opencode/capabilities/agent_status_normalizer_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现 normalizer 分支**

`agent_status_normalizer.dart`（opencode）：识别 `event == 'userMessageSubmitted'` 时产出 `AgentStatusEvent(state: working, hookEventName: event, prompt: body['prompt'])`。

- [ ] **Step 4: 实现插件事件转发**

`agent_status_plugin.dart` 的 `event` handler 中（`session.idle` 分支旁）：

```javascript
// User message commit: forward prompt so the app can ACK the PTY delivery.
// Event name verified against opencode <version> (update comment).
if (event.type === "session.updated") {
  const session = event.properties ?? event.data ?? {};
  const parts = session.parts ?? session.messages ?? null;
  if (parts && Array.isArray(parts)) {
    for (const part of parts) {
      if (part && (part.type === "text" || part.type === "input")) {
        const text = part.text ?? "";
        if (text && text.trim()) {
          await post("userMessageSubmitted", { prompt: text });
          break;
        }
      }
    }
  }
  return;
}
```

**注意**：事件名与 payload 结构必须实测校准（见 Step 5），代码注释记录验证方式与版本。

- [ ] **Step 5: 实测校准事件名**

在真实 opencode TUI 会话中发送消息，观察插件 POST 的 `/agent-status` 事件（app 日志），确认 `event.type` 与 message part 路径。若 `session.updated` 不携带新消息，改用 `message.updated` / 轮询 DB 差异。**校准结果写入代码注释**。

- [ ] **Step 6: 运行测试 + 全量验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: 无新增失败（pre-existing 失败与 main 一致）

- [ ] **Step 7: 提交**

```bash
git add client/lib/services/cli/opencode/capabilities/agent_status_plugin.dart client/lib/services/cli/opencode/capabilities/agent_status_normalizer.dart client/test/services/cli/opencode/capabilities/agent_status_normalizer_test.dart
git commit -m "feat(opencode): plugin forwards user message submit for delivery ACK"
```

---

### Task 9: cursor `beforeSubmitPrompt` payload 确认 + 迁移遗留（阶段 1 收尾）

**Files:**
- Modify: `client/lib/services/cli/cursor/provider/cursor_home_agent_status_overlay.dart`（如需带 prompt 转发）
- Modify: `client/lib/services/cli/cursor/capabilities/agent_status_normalizer.dart`（提取 prompt）
- Test: `client/test/services/provider/cursor/cursor_agent_status_overlay_test.dart`（若存在，追加断言）

**背景**：cursor 的 `beforeSubmitPrompt` hook 已安装（转发 stdin payload → /agent-status）。需实测确认 payload 是否含 prompt 原文；若含，normalizer 提取后 ACK 桥自动覆盖 cursor。

- [ ] **Step 1: 实测 cursor hook payload**

在真实 cursor 会话发送消息，检查 `/agent-status?event=beforeSubmitPrompt` 收到的 body（app 日志 / 临时日志）。确认 `prompt` 字段存在与否。

- [ ] **Step 2: 按实测结果实现**

- 若 payload 含 prompt：`cursor/capabilities/agent_status_normalizer.dart` 提取 prompt（测试断言 `event.prompt == text`），ACK 桥覆盖 cursor。
- 若不含：在 `cursor_home_agent_status_overlay.dart` 的转发脚本中把 prompt 注入 payload（若 hook stdin 含 prompt 则透传；否则记录为阶段 1.5 遗留，cursor 保持 grid 探针兜底）。

- [ ] **Step 3: 运行测试**

Run: `cd client && flutter test test/services/provider/cursor/cursor_agent_status_overlay_test.dart && flutter test test/services/agent_status/agent_status_normalizer_test.dart`
Expected: PASS

- [ ] **Step 4: 全量验证 + 提交**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`

```bash
git add client/lib/services/cli/cursor/ client/test/services/provider/cursor/
git commit -m "feat(cursor): beforeSubmitPrompt payload for delivery ACK"
```

---

## Self-Review 结论（计划内）

**Spec 覆盖核对**：
- 泛型核心 + 合并规则链（含 level）→ Task 1 ✅
- 依赖反转（AssetDeclaringCapability + collectDeclared）→ Task 2、5 ✅
- HookRegistry 特化 + 共享实现（claude family）→ Task 3 ✅
- 统一落盘装配点（render 文件级输出 + mergeHooksInto）→ Task 4 ✅
- 中途变更/seat coordinator → 阶段 1 范围外（spec 允许阶段 1 仅 launch 装配，见 spec "seat 映射" 段）✅
- hook ACK 桥（prompt 匹配 + 取消重试）→ Task 6、7 ✅
- opencode 插件事件 / cursor payload 确认 → Task 8、9 ✅
- agents/rules/commands 不建 → 全局约束 ✅

**遗留（阶段 1.5+，不在本计划）**：agent-status 8 事件迁移为能力声明（Task 5 标注"优先路径"）、`mcp_registry_service` fan-out 收敛（阶段 2）、cursor 无 prompt 时的注入（Task 9 分支）。
