# CLI Agent 包拆分 Spec 1 / 1A 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 5 个包与 1 个纯容器，定义 `AgentId` / `AgentRegistry` / 注解 / 端口契约，并用 `build_runner` 从注解生成 claude 的注册表，使 app 侧测试能注册 claude 而不 import 任何具体 agent 包。

**Architecture:** `teampilot-common`（纯 Dart 值类型）→ `teampilot-agent-api`（契约/端口/registry/注解）→ 9 个 `teampilot-agent-*` 包；`teampilot-agents-bundle` 持有 manifest 与生成物并在启动时 `registerAllAgents`；`teampilot-agents-builder` 是 build_runner Builder。`teampilot-agents/` 是纯容器目录。1A 只做机制骨架与最小 claude definition，1B（50 文件迁移 + 端口适配器 + import 机械改写）另出计划。

**Tech Stack:** Dart 3.8.1 / Flutter / `build_runner 2.16.1` / `build 4.0.11` / `source_gen 4.3.0` / `analyzer 14.3.0`（均为 `client/pubspec.lock` 现有锁定版本）/ `package:test 1.33.0` / `flutter_test` / path packages。

## Global Constraints

- 设计事实源：`docs/superpowers/specs/2026-11-09-cli-agent-packages-design.md`（已提交 `5d0ba19af`）。
- **Never invoke `flutter test` directly** — always `cd client && dart run tool/run_tests.dart <paths/options>`；`dart test` 用于纯 Dart 包不受此限制。
- Test loop：内层 `flutter analyze --no-fatal-infos --no-fatal-warnings`；单文件用 `dart run tool/run_tests.dart <path> --plain-name`；全量只在声称完成前跑一次（后台）。
- 完成前：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`。
- 包名（`pubspec.yaml` 的 `name`）只能用小写字母/数字/下划线；目录名可用连字符。映射：`teampilot-common`→`teampilot_common`、`teampilot-agent-api`→`teampilot_agent_api`、`teampilot-agent-claude`→`teampilot_agent_claude`、`teampilot-agents-bundle`→`teampilot_agents_bundle`、`teampilot-agents-builder`→`teampilot_agents_builder`。
- `teampilot-common` 运行时零 Flutter；`teampilot-agent-api` 只依赖 `flutter/widgets.dart` 的 `Widget` / `BuildContext` 两个类型，不依赖 material。
- app 源码不得出现具体 agent 标识；agent 包不得出现 `package:teampilot/` 开头的 import，不得 import 其它 agent 包。
- `@AgentManifest(defaultId: 'claude')` 标在 `agent_manifest.dart` 的 `library;` 指令上。
- 生成物 `register_all.g.dart` 提交 git；builder 不用 `dart:io` 读目录 / `package_config.json`；`AgentRegistry` 不提供 `values`。
- builder 必须是 `client/pubspec.yaml` 的 `dev_dependencies`（pub 不暴露 path 依赖的 dev_deps 到根包 `package_config.json`）。
- l10n：只编辑 `client/lib/l10n/app_en.arb` / `app_zh.arb`；1A 不改这两个文件。
- 日志：`AppLogger`（app 侧）；1A 的纯 Dart 包不写日志。
- 每个 Task 结束都要 `git commit`；提交只含本 Task 文件，不 `git add -A`。
- 1B 单独成计划。本计划范围内**不**修改 `app_shell.dart` 的现有注册路径、`CliToolRegistry`、`CliBootstrap`、`built_in_cli_tools.dart` 或 `services/cli/` 下任何现有文件；1A 用一条 app 侧测试证明注册链路，不改 app 启动行为。

---

## 文件结构

```
client/
  pubspec.yaml                                  # T2/T4/T7/T8 增加 path deps + dev dep
  tool/run_tests.dart                           # T3 增加 --package
  test/services/cli/agent_registration_test.dart  # T9 app 侧链路测试（新文件）
  .github 之外的 CI：../.github/workflows/client-verify.yml  # T9 增加三个 step
  packages/
    teampilot-common/                           # T2 新建（纯 Dart）
      pubspec.yaml
      lib/teampilot_common.dart
      lib/src/agent_id.dart
      test/agent_id_test.dart
    teampilot-agent-api/                        # T4/T5 新建
      pubspec.yaml
      lib/teampilot_agent_api.dart
      lib/src/annotation.dart
      lib/src/agent_capability.dart
      lib/src/agent_definition.dart
      lib/src/agent_metadata.dart
      lib/src/agent_ui_factory.dart
      lib/src/agent_ports.dart
      lib/src/agent_context.dart
      lib/src/agent_registry.dart
      test/agent_registry_test.dart
      test/agent_context_test.dart
    teampilot-agents/                           # 纯容器，无 pubspec.yaml / lib/ / build.yaml
      teampilot-agent-claude/                   # T6 新建
        pubspec.yaml
        lib/teampilot_agent_claude.dart
        lib/src/claude_agent_definition.dart
        assets/claude.svg
        test/claude_agent_definition_test.dart
      teampilot-agents-builder/                 # T7 新建
        pubspec.yaml
        build.yaml
        lib/builder.dart
      teampilot-agents-bundle/                  # T8 新建
        pubspec.yaml
        build.yaml
        lib/agent_manifest.dart
        lib/register_all.g.dart                 # 生成物，提交 git
        test/agent_manifest_consistency_test.dart
```

---

### Task 1: Spike — 验证跨包注解发现与非 root 包生成

**Files:**
- Create（临时，仓库外）：`/tmp/teampilot-agent-spike/` 下 9 个文件
- Modify：`docs/superpowers/specs/2026-11-09-cli-agent-packages-design.md`（追加「Spike 结论」）

**Interfaces:**
- Consumes: 无
- Produces: 一个 Go/No-Go 结论，写回 spec；1A 后续所有任务以此为前提。

- [ ] **Step 1: 创建 spike 工作区**

```bash
mkdir -p /tmp/teampilot-agent-spike/spike_host/bin \
         /tmp/teampilot-agent-spike/packages/spike_api/lib \
         /tmp/teampilot-agent-spike/packages/spike_agent/lib \
         /tmp/teampilot-agent-spike/packages/spike_builder/lib \
         /tmp/teampilot-agent-spike/packages/spike_bundle/lib
```

写入以下 9 个文件（全部内容）：

`/tmp/teampilot-agent-spike/spike_host/pubspec.yaml`
```yaml
name: spike_host
publish_to: none
environment:
  sdk: ^3.8.1
dependencies:
  spike_api:
    path: packages/spike_api
  spike_agent:
    path: packages/spike_agent
  spike_bundle:
    path: packages/spike_bundle
dev_dependencies:
  spike_builder:
    path: packages/spike_builder
  build_runner: 2.16.1
```

`/tmp/teampilot-agent-spike/spike_host/bin/check.dart`
```dart
import 'package:spike_api/spike_api.dart';
import 'package:spike_bundle/register_all.g.dart';

void main() {
  final registry = AgentRegistry();
  registerAllAgents(registry, const AgentContext());
  final ids = registry.ids.toList();
  print(ids);
  if (ids.toString() != '[demo]' || registry.defaultId != 'demo') {
    throw StateError('Spike failed: ids=$ids default=${registry.defaultId}');
  }
}
```

`/tmp/teampilot-agent-spike/packages/spike_api/pubspec.yaml`
```yaml
name: spike_api
publish_to: none
environment:
  sdk: ^3.8.1
```

`/tmp/teampilot-agent-spike/packages/spike_api/lib/spike_api.dart`
```dart
final class SpikeAgent {
  const SpikeAgent({required this.id});

  final String id;
}

final class SpikeManifest {
  const SpikeManifest({required this.defaultId});

  final String defaultId;
}

abstract interface class AgentDefinition {
  String get id;
}

final class AgentContext {
  const AgentContext();
}

final class AgentRegistry {
  final Map<String, AgentDefinition> _definitions = {};

  void register(AgentDefinition definition) {
    _definitions[definition.id] = definition;
  }

  Iterable<String> get ids => _definitions.keys;

  String? defaultId;
}
```

`/tmp/teampilot-agent-spike/packages/spike_agent/pubspec.yaml`
```yaml
name: spike_agent
publish_to: none
environment:
  sdk: ^3.8.1
dependencies:
  spike_api:
    path: ../spike_api
```

`/tmp/teampilot-agent-spike/packages/spike_agent/lib/spike_agent.dart`
```dart
import 'package:spike_api/spike_api.dart';

@SpikeAgent(id: 'demo')
final class DemoAgentDefinition implements AgentDefinition {
  DemoAgentDefinition(this.context);

  final AgentContext context;

  @override
  String get id => 'demo';
}
```

`/tmp/teampilot-agent-spike/packages/spike_builder/pubspec.yaml`
```yaml
name: spike_builder
publish_to: none
environment:
  sdk: ^3.8.1
dependencies:
  build: 4.0.11
  source_gen: 4.3.0
```

`/tmp/teampilot-agent-spike/packages/spike_builder/build.yaml`
```yaml
builders:
  aggregator:
    import: "package:spike_builder/builder.dart"
    builder_factories: ["spikeAggregator"]
    build_extensions: {"lib/agent_manifest.dart": ["lib/register_all.g.dart"]}
    auto_apply: none
    build_to: source
```

`/tmp/teampilot-agent-spike/packages/spike_builder/lib/builder.dart`
```dart
import 'dart:async';

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

Builder spikeAggregator(BuilderOptions options) => _SpikeAggregator();

const _agentChecker = TypeChecker.fromUrl(
  'package:spike_api/spike_api.dart#SpikeAgent',
);
const _manifestChecker = TypeChecker.fromUrl(
  'package:spike_api/spike_api.dart#SpikeManifest',
);

final class _SpikeAggregator extends Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
    'lib/agent_manifest.dart': ['lib/register_all.g.dart'],
  };

  @override
  Future<void> build(BuildStep step) async {
    final manifestLibrary =
        await step.resolver.libraryFor(step.inputId);
    final manifestAnnotation =
        _manifestChecker.firstAnnotationOf(manifestLibrary);
    if (manifestAnnotation == null) {
      throw StateError(
        '${step.inputId}: missing @SpikeManifest on the library directive',
      );
    }
    final defaultId = ConstantReader(manifestAnnotation)
        .read('defaultId')
        .stringValue;

    final found = <_Found>[];
    await for (final library in step.resolver.libraries) {
      final uri = Uri.parse(library.identifier);
      String? importUri;
      if (uri.scheme == 'package') {
        importUri = library.identifier;
      } else if (uri.scheme == 'asset' && uri.pathSegments.length > 2) {
        importUri = 'package:${uri.pathSegments.first}/'
            '${uri.pathSegments.skip(2).join('/')}';
      }
      if (importUri == null) continue;
      for (final annotated
          in LibraryReader(library).annotatedWith(_agentChecker)) {
        found.add(_Found(
          id: annotated.annotation.read('id').stringValue,
          className: annotated.element.name!,
          importUri: importUri,
        ));
      }
    }
    found.sort((a, b) => a.id.compareTo(b.id));
    final buffer = StringBuffer('// GENERATED CODE - DO NOT MODIFY BY HAND\n')
      ..writeln("import 'package:spike_api/spike_api.dart' as api;");
    for (var i = 0; i < found.length; i++) {
      buffer.writeln("import '${found[i].importUri}' as a$i;");
    }
    buffer
      ..writeln(
        '\nvoid registerAllAgents(api.AgentRegistry registry, '
        'api.AgentContext context) {',
      )
      ..writeln("  registry.defaultId = '$defaultId';");
    for (var i = 0; i < found.length; i++) {
      buffer.writeln('  registry.register(a$i.${found[i].className}(context));');
    }
    buffer.writeln('}');
    await step.writeAsString(
      AssetId(step.inputId.package, 'lib/register_all.g.dart'),
      buffer.toString(),
    );
  }
}

final class _Found {
  const _Found({
    required this.id,
    required this.className,
    required this.importUri,
  });

  final String id;
  final String className;
  final String importUri;
}
```

`/tmp/teampilot-agent-spike/packages/spike_bundle/pubspec.yaml`
```yaml
name: spike_bundle
publish_to: none
environment:
  sdk: ^3.8.1
dependencies:
  spike_api:
    path: ../spike_api
  spike_agent:
    path: ../spike_agent
```

`/tmp/teampilot-agent-spike/packages/spike_bundle/build.yaml`
```yaml
targets:
  $default:
    builders:
      spike_builder|aggregator:
        enabled: true
```

`/tmp/teampilot-agent-spike/packages/spike_bundle/lib/agent_manifest.dart`
```dart
@SpikeManifest(defaultId: 'demo')
library;

import 'package:spike_api/spike_api.dart';
import 'package:spike_agent/spike_agent.dart';
```

- [ ] **Step 2: 跑 spike（预期三件事全通过）**

```bash
cd /tmp/teampilot-agent-spike/spike_host && dart pub get && \
  dart run build_runner build --delete-conflicting-outputs && \
  cat packages/spike_bundle/lib/register_all.g.dart && \
  dart run spike_host:check
```

Expected：stdout 包含

```
// GENERATED CODE - DO NOT MODIFY BY HAND
import 'package:spike_api/spike_api.dart' as api;
import 'package:spike_agent/spike_agent.dart' as a0;

void registerAllAgents(api.AgentRegistry registry, api.AgentContext context) {
  registry.defaultId = 'demo';
  registry.register(a0.DemoAgentDefinition(context));
}
[demo]
```

且退出码 0。这同时验证了第 4 项：`library;` 指令上的 `@SpikeManifest` 能被 `firstAnnotationOf` 读到，`defaultId` 被写进生成物。

若 `resolver.libraries` 看不到 `spike_agent` 里的注解、生成物没有落进 `spike_bundle/lib/`、library 级注解读不到、或 `dart run` 报找不到 `register_all.g.dart`，记录具体失败信息并按 spec 第 3 节 D6 回退到 2-γ / 方案 1，**停止本计划后续任务**。

- [ ] **Step 3: 把结论写回 spec 并清理**

在 `docs/superpowers/specs/2026-11-09-cli-agent-packages-design.md` 末尾追加：

```markdown
## 14. Spike 结论（1A 第 0 步）

- 日期：2026-11-09
- 结果：通过 / 不通过（二选一，写明实测命令与输出摘要）
- 四项验证：
  1. `step.resolver.libraries` 能看到 path 依赖包里的 `@SpikeAgent` 标注类：通过 / 不通过
  2. `build_runner build` 能在非 root path 包生成 `build_to: source` 产物：通过 / 不通过
  3. 生成物 import 依赖包 barrel 后可被宿主编译并注册：通过 / 不通过
  4. `library;` 指令上的 `@SpikeManifest` 能被 `firstAnnotationOf` 读到并写入 `defaultId`：通过 / 不通过
- 失败时的机制回退选择与理由：无 / 2-γ / 方案 1（写明）
```

```bash
cd /home/hhoa/git/hhoa/teampilot && \
  git add docs/superpowers/specs/2026-11-09-cli-agent-packages-design.md && \
  git commit -m "docs: record agent-registry spike result" -- \
    docs/superpowers/specs/2026-11-09-cli-agent-packages-design.md
rm -rf /tmp/teampilot-agent-spike
```

---

### Task 2: `teampilot-common` 包与 `AgentId`

**Files:**
- Create: `client/packages/teampilot-common/pubspec.yaml`
- Create: `client/packages/teampilot-common/lib/teampilot_common.dart`
- Create: `client/packages/teampilot-common/lib/src/agent_id.dart`
- Create: `client/packages/teampilot-common/test/agent_id_test.dart`
- Modify: `client/pubspec.yaml`（`dependencies` 段）

**Interfaces:**
- Consumes: 无
- Produces: `AgentId`（`const AgentId(String value)`、`String value`、`bool isValid`、`static AgentId fromJson(Object?)`、`String toJson()`、`==` / `hashCode` / `toString`）；包 `teampilot_common` 的 barrel `package:teampilot_common/teampilot_common.dart`。后续所有任务通过它引用 `AgentId`。

- [ ] **Step 1: 写失败测试**

`client/packages/teampilot-common/test/agent_id_test.dart`
```dart
import 'package:test/test.dart';
import 'package:teampilot_common/teampilot_common.dart';

void main() {
  group('AgentId', () {
    test('equal values are equal and hash equally', () {
      expect(const AgentId('claude'), equals(const AgentId('claude')));
      expect(
        const AgentId('claude').hashCode,
        const AgentId('claude').hashCode,
      );
    });

    test('different values are not equal', () {
      expect(const AgentId('claude'), isNot(const AgentId('codex')));
    });

    test('fromJson accepts lower-case ids, digits, dash and underscore', () {
      expect(AgentId.fromJson('claude').value, 'claude');
      expect(AgentId.fromJson('my_agent-2').value, 'my_agent-2');
    });

    test('fromJson rejects null, empty, upper-case, spaces and dots', () {
      for (final raw in <Object?>[null, '', 'Claude', 'has space', 'a.b']) {
        expect(
          () => AgentId.fromJson(raw),
          throwsFormatException,
          reason: 'raw=$raw',
        );
      }
    });

    test('toJson round-trips', () {
      expect(
        AgentId.fromJson(const AgentId('claude').toJson()).value,
        'claude',
      );
    });

    test('isValid reflects the same rule', () {
      expect(const AgentId('claude').isValid, isTrue);
      expect(const AgentId('Claude').isValid, isFalse);
      expect(const AgentId('').isValid, isFalse);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/teampilot-common && \
  dart pub get && dart test
```
Expected: FAIL（`package:teampilot_common/teampilot_common.dart` 不存在 / `AgentId` 未定义）。

- [ ] **Step 3: 写实现**

`client/packages/teampilot-common/pubspec.yaml`
```yaml
name: teampilot_common
description: Pure-Dart shared types for TeamPilot agent packages.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.1

dev_dependencies:
  test: ^1.25.0
```

`client/packages/teampilot-common/lib/teampilot_common.dart`
```dart
export 'src/agent_id.dart';
```

`client/packages/teampilot-common/lib/src/agent_id.dart`
```dart
/// Opaque identifier for a registered agent.
///
/// There is deliberately no `values` list and no constants for concrete
/// agents: the set of agents is discovered from the registry at runtime.
final class AgentId {
  const AgentId(this.value);

  final String value;

  static final RegExp _valid = RegExp(r'^[a-z0-9_-]+$');

  bool get isValid => _valid.hasMatch(value);

  static AgentId fromJson(Object? raw) {
    final value = raw?.toString() ?? '';
    if (!_valid.hasMatch(value)) {
      throw FormatException('Invalid AgentId: "$raw"');
    }
    return AgentId(value);
  }

  String toJson() => value;

  @override
  bool operator ==(Object other) =>
      other is AgentId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'AgentId($value)';
}
```

在 `client/pubspec.yaml` 的 `dependencies:` 段（`ai_message_core:` 之前）加入：

```yaml
  teampilot_common:
    path: packages/teampilot-common
```

- [ ] **Step 4: 跑测试确认通过并让 app 解析新依赖**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/teampilot-common && dart test
cd /home/hhoa/git/hhoa/teampilot/client && flutter pub get
```
Expected: 6 tests PASS；`flutter pub get` 退出码 0。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && \
  git add client/packages/teampilot-common client/pubspec.yaml client/pubspec.lock && \
  git commit -m "feat(agents): add teampilot_common package with AgentId" -- \
    client/packages/teampilot-common client/pubspec.yaml client/pubspec.lock
```

---

### Task 3: `tool/run_tests.dart` 支持 `--package`

**Files:**
- Modify: `client/tool/run_tests.dart`（在 `main` 前插入 2 个 helper，替换 `main`）
- Test: `client/packages/teampilot-common`（复用其 6 个测试）

**Interfaces:**
- Consumes: Task 2 的 `teampilot-common` 包
- Produces: `dart run tool/run_tests.dart --package <path> [其它 test 参数]`；`--package=<path>` 同义。纯 Dart 包执行 `dart test`，声明了 Flutter 依赖的包执行 `flutter test`；两者共用 `.dart_tool/run_tests.lock`，且运行前在包目录内先跑一次 `<dart|flutter> pub get`（仓库内 path 包都自带 `pubspec.lock`，这是既有惯例）。

- [ ] **Step 1: 写失败测试（命令级）**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && \
  dart run tool/run_tests.dart --package packages/teampilot-common
```
Expected: FAIL — `flutter test` 报 "Could not find an option named `--package`"（该参数被透传给 flutter test）。

- [ ] **Step 2: 插入 helper 并替换 `main`**

在 `client/tool/run_tests.dart` 第 148 行（`pubSourceMismatchMessage` 结束）之后插入：

```dart
const packageOption = '--package';

/// Removes `--package <path>` / `--package=<path>` from [args].
/// Returns the path and the remaining arguments, or null when absent.
({String path, List<String> rest})? extractPackageOption(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == packageOption) {
      if (i + 1 >= args.length) {
        throw FormatException('$packageOption requires a path');
      }
      return (
        path: args[i + 1],
        rest: [...args.sublist(0, i), ...args.sublist(i + 2)],
      );
    }
    if (arg.startsWith('$packageOption=')) {
      return (
        path: arg.substring(packageOption.length + 1),
        rest: [...args.sublist(0, i), ...args.sublist(i + 1)],
      );
    }
  }
  return null;
}

/// Whether the package at [packageDir] declares a Flutter dependency.
bool packageNeedsFlutter(String packageDir) {
  final pubspec = File('$packageDir/pubspec.yaml');
  if (!pubspec.existsSync()) {
    throw StateError('No pubspec.yaml in $packageDir');
  }
  return RegExp(r'^\s+flutter:\s*$', multiLine: true)
      .hasMatch(pubspec.readAsStringSync());
}
```

把 `main`（现第 150–187 行）整体替换为：

```dart
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final package = extractPackageOption(args);
  final effectiveArgs = package?.rest ?? args;

  // The pub-source check targets the client lockfile; path packages have
  // their own resolution and are checked by `pub get` in their own dir.
  if (package == null) {
    final lockFile = File('pubspec.lock');
    final mismatch = pubSourceMismatchMessage(
      lockedUrl: lockFile.existsSync()
          ? firstHostedUrl(await lockFile.readAsString())
          : null,
      effectiveSource: env['PUB_HOSTED_URL'] ?? defaultHostedUrl,
    );
    if (mismatch != null) {
      final allowed = env[allowPubSourceMismatchEnv] == '1';
      stderr.writeln('${allowed ? 'warning' : 'error'}: $mismatch');
      if (!allowed) {
        exitCode = 1;
        return;
      }
    }
  }

  final useFlutter = package == null || packageNeedsFlutter(package.path);
  final executable = useFlutter
      ? (Platform.isWindows ? 'flutter.bat' : 'flutter')
      : (Platform.isWindows ? 'dart.bat' : 'dart');

  // Path packages in this repo carry their own pubspec.lock; resolving in
  // the package dir makes `dart test` / `flutter test` deterministic.
  if (package != null) {
    final pubGet = await Process.start(
      executable,
      ['pub', 'get'],
      workingDirectory: package.path,
      mode: ProcessStartMode.inheritStdio,
    );
    final pubGetCode = await pubGet.exitCode;
    if (pubGetCode != 0) {
      exitCode = pubGetCode;
      return;
    }
  }

  exitCode = await withTestSuiteLock(
    testSuiteLockPath,
    () async {
      final process = await Process.start(
        executable,
        buildFlutterTestArgs(
          effectiveArgs,
          concurrencyOverride: env[testConcurrencyEnv],
        ),
        workingDirectory: package?.path,
        mode: ProcessStartMode.inheritStdio,
      );
      return process.exitCode;
    },
    onWaitStart: () {
      stderr.writeln(
        'Another run_tests.dart invocation holds the test-suite lock; '
        'waiting for it to finish…',
      );
    },
  );
}
```

- [ ] **Step 3: 跑同一命令确认通过**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && \
  dart run tool/run_tests.dart --package packages/teampilot-common
```
Expected: `dart pub get` 在包目录内成功，随后 6 tests PASS（走 `dart test`，因为 `teampilot-common/pubspec.yaml` 没有 `flutter:` 依赖）。

```bash
cd /home/hhoa/git/hhoa/teampilot/client && \
  dart run tool/run_tests.dart test/models/app_provider_config_test.dart
```
Expected: 原行为不变（不带 `--package` 时仍走 `flutter test`，该现有测试文件 PASS）。

- [ ] **Step 4: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && \
  git add client/tool/run_tests.dart && \
  git commit -m "feat(tests): add --package support to run_tests.dart" -- \
    client/tool/run_tests.dart
```

---

### Task 4: `teampilot-agent-api` 核心契约

**Files:**
- Create: `client/packages/teampilot-agent-api/pubspec.yaml`
- Create: `client/packages/teampilot-agent-api/lib/teampilot_agent_api.dart`
- Create: `client/packages/teampilot-agent-api/lib/src/annotation.dart`
- Create: `client/packages/teampilot-agent-api/lib/src/agent_capability.dart`
- Create: `client/packages/teampilot-agent-api/lib/src/agent_definition.dart`
- Create: `client/packages/teampilot-agent-api/lib/src/agent_metadata.dart`
- Create: `client/packages/teampilot-agent-api/lib/src/agent_ui_factory.dart`
- Create: `client/packages/teampilot-agent-api/lib/src/agent_registry.dart`
- Create: `client/packages/teampilot-agent-api/test/agent_registry_test.dart`
- Modify: `client/pubspec.yaml`（`dependencies` 段）

**Interfaces:**
- Consumes: `AgentId` from `package:teampilot_common/teampilot_common.dart`
- Produces: `TeampilotAgent`、`AgentManifest`、`AgentCapability`、`AgentDefinition`、`AgentMetadata`、`AgentUiFactory`、`AgentRegistry`、`UnknownAgentException`、`requireAgent`；barrel `package:teampilot_agent_api/teampilot_agent_api.dart`。Task 5 追加 `AgentPorts` 等端口类型，Task 6/7/8 全部依赖本 barrel。

- [ ] **Step 1: 写失败测试**

`client/packages/teampilot-agent-api/test/agent_registry_test.dart`
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_agent_api/teampilot_agent_api.dart';
import 'package:teampilot_common/teampilot_common.dart';

final class _FakeCapability implements AgentCapability {
  const _FakeCapability();
}

final class _FakeDefinition implements AgentDefinition {
  const _FakeDefinition(this._id, {this.caps = const []});

  final AgentId _id;
  final List<AgentCapability> caps;

  @override
  AgentId get id => _id;
  @override
  Iterable<AgentCapability> get capabilities => caps;
  @override
  AgentMetadata get metadata => const AgentMetadata(
    displayName: 'Fake',
    icon: 'fake.svg',
    hookSupport: {},
    providerPersistenceStrategy: 'default',
    usageCategory: 'cli',
    transport: {'pty'},
  );
  @override
  AgentUiFactory get ui => const _FakeUiFactory();
}

final class _FakeUiFactory implements AgentUiFactory {
  const _FakeUiFactory();
  @override
  Widget buildProviderFormSection(BuildContext context) =>
      const SizedBox.shrink();
  @override
  Future<bool> showLoginDialog(
    BuildContext context, {
    required String executable,
  }) async =>
      false;
}

void main() {
  test('register, tryGet, all and launchable', () {
    final registry = AgentRegistry();
    final def = _FakeDefinition(const AgentId('fake'));
    registry.register(def);
    expect(registry.tryGet(const AgentId('fake')), same(def));
    expect(registry.all.map((d) => d.id.value), ['fake']);
    expect(registry.launchable.length, 1);
  });

  test('duplicate id throws StateError mentioning both types', () {
    final registry = AgentRegistry();
    registry.register(_FakeDefinition(const AgentId('fake')));
    expect(
      () => registry.register(_FakeDefinition(const AgentId('fake'))),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Duplicate AgentId fake'),
        ),
      ),
    );
  });

  test('capability resolves by type from the definition', () {
    final registry = AgentRegistry();
    final cap = const _FakeCapability();
    registry.register(
      _FakeDefinition(const AgentId('fake'), caps: [cap]),
    );
    expect(
      registry.capability<_FakeCapability>(const AgentId('fake')),
      same(cap),
    );
    expect(
      registry.capability<_FakeCapability>(const AgentId('missing')),
      isNull,
    );
  });

  test('defaultId is settable and readable', () {
    final registry = AgentRegistry();
    expect(registry.defaultId, isNull);
    registry.defaultId = const AgentId('fake');
    expect(registry.defaultId, const AgentId('fake'));
  });

  test('requireAgent throws UnknownAgentException without a fallback', () {
    final registry = AgentRegistry();
    expect(
      () => requireAgent(registry, const AgentId('ghost')),
      throwsA(isA<UnknownAgentException>()),
    );
    registry.register(_FakeDefinition(const AgentId('fake')));
    expect(
      requireAgent(registry, const AgentId('fake')).id.value,
      'fake',
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter pub get && \
  dart run tool/run_tests.dart --package packages/teampilot-agent-api
```
Expected: FAIL（包不存在 / `package:teampilot_agent_api/...` 找不到）。

- [ ] **Step 3: 写实现**

`client/packages/teampilot-agent-api/pubspec.yaml`
```yaml
name: teampilot_agent_api
description: Contracts, ports, registry and annotations for TeamPilot agent packages.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.1

dependencies:
  flutter:
    sdk: flutter
  teampilot_common:
    path: ../teampilot-common

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
```

`client/packages/teampilot-agent-api/lib/src/annotation.dart`
```dart
/// Marks an [AgentDefinition] implementation for build-time registration.
final class TeampilotAgent {
  const TeampilotAgent({
    required this.id,
    required this.displayName,
    required this.icon,
  });

  final String id;
  final String displayName;
  final String icon;
}

/// Marks the bundle manifest library and declares the fallback agent id.
final class AgentManifest {
  const AgentManifest({required this.defaultId});

  final String defaultId;
}
```

`client/packages/teampilot-agent-api/lib/src/agent_capability.dart`
```dart
/// Marker interface for capabilities an [AgentDefinition] exposes.
/// Concrete capability interfaces move here from `services/cli/registry/`
/// in Spec 1 / 1B.
abstract interface class AgentCapability {}
```

`client/packages/teampilot-agent-api/lib/src/agent_definition.dart`
```dart
import 'package:teampilot_common/teampilot_common.dart';

import 'agent_capability.dart';
import 'agent_metadata.dart';
import 'agent_ui_factory.dart';

abstract interface class AgentDefinition {
  AgentId get id;
  Iterable<AgentCapability> get capabilities;
  AgentMetadata get metadata;
  AgentUiFactory get ui;
}
```

`client/packages/teampilot-agent-api/lib/src/agent_metadata.dart`
```dart
/// Agent-owned metadata. Replaces the app-side `Map<CliTool, ...>` tables
/// and the exhaustive l10n switch in the final state. Field types are
/// refined with the real domain types during Spec 1 / 1B.
final class AgentMetadata {
  const AgentMetadata({
    required this.displayName,
    required this.icon,
    required this.hookSupport,
    required this.providerPersistenceStrategy,
    required this.usageCategory,
    required this.transport,
  });

  final String displayName;
  final String icon;
  final Map<String, Set<String>> hookSupport;
  final String providerPersistenceStrategy;
  final String usageCategory;
  final Set<String> transport;
}
```

`client/packages/teampilot-agent-api/lib/src/agent_ui_factory.dart`
```dart
import 'package:flutter/widgets.dart';

/// Agent-provided UI entry points. The app places the returned widget
/// directly in the widget tree and holds no agent-specific widget branches.
abstract interface class AgentUiFactory {
  Widget buildProviderFormSection(BuildContext context);

  Future<bool> showLoginDialog(
    BuildContext context, {
    required String executable,
  });
}
```

`client/packages/teampilot-agent-api/lib/src/agent_registry.dart`
```dart
import 'package:teampilot_common/teampilot_common.dart';

import 'agent_capability.dart';
import 'agent_definition.dart';

final class AgentRegistry {
  final Map<AgentId, AgentDefinition> _definitions = {};

  void register(AgentDefinition definition) {
    final existing = _definitions[definition.id];
    if (existing != null) {
      throw StateError(
        'Duplicate AgentId ${definition.id.value}: '
        '${existing.runtimeType} and ${definition.runtimeType}',
      );
    }
    _definitions[definition.id] = definition;
  }

  AgentDefinition? tryGet(AgentId id) => _definitions[id];

  T? capability<T extends AgentCapability>(AgentId id) {
    final definition = _definitions[id];
    if (definition == null) return null;
    for (final cap in definition.capabilities) {
      if (cap is T) return cap;
    }
    return null;
  }

  Iterable<AgentDefinition> get all => _definitions.values;

  Iterable<AgentDefinition> get launchable =>
      all.where((d) => d.metadata.transport.isNotEmpty);

  AgentId? _defaultId;

  AgentId? get defaultId => _defaultId;
  set defaultId(AgentId id) => _defaultId = id;
}

final class UnknownAgentException implements Exception {
  const UnknownAgentException(this.id, this.registered);

  final AgentId id;
  final Iterable<AgentId> registered;

  @override
  String toString() => 'Unknown agent ${id.value}; registered: '
      '${registered.map((e) => e.value).join(', ')}';
}

/// Resolves an agent id without ever falling back to a hard-coded default.
AgentDefinition requireAgent(AgentRegistry registry, AgentId id) {
  final definition = registry.tryGet(id);
  if (definition == null) {
    throw UnknownAgentException(
      id,
      registry.all.map((d) => d.id).toList(),
    );
  }
  return definition;
}
```

`client/packages/teampilot-agent-api/lib/teampilot_agent_api.dart`
```dart
export 'package:flutter/widgets.dart' show BuildContext, Widget;

export 'src/agent_capability.dart';
export 'src/agent_definition.dart';
export 'src/agent_metadata.dart';
export 'src/agent_registry.dart';
export 'src/agent_ui_factory.dart';
export 'src/annotation.dart';
```

在 `client/pubspec.yaml` 的 `dependencies:` 段加入：

```yaml
  teampilot_agent_api:
    path: packages/teampilot-agent-api
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter pub get && \
  dart run tool/run_tests.dart --package packages/teampilot-agent-api && \
  flutter analyze --no-fatal-infos --no-fatal-warnings
```
Expected: 5 tests PASS；analyze 无 error。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && \
  git add client/packages/teampilot-agent-api client/pubspec.yaml client/pubspec.lock && \
  git commit -m "feat(agents): add teampilot_agent_api core contracts" -- \
    client/packages/teampilot-agent-api client/pubspec.yaml client/pubspec.lock
```

---

### Task 5: `teampilot-agent-api` 宿主侧端口与 `AgentContext`

**Files:**
- Create: `client/packages/teampilot-agent-api/lib/src/agent_ports.dart`
- Create: `client/packages/teampilot-agent-api/lib/src/agent_context.dart`
- Create: `client/packages/teampilot-agent-api/test/agent_context_test.dart`
- Modify: `client/packages/teampilot-agent-api/lib/teampilot_agent_api.dart`

**Interfaces:**
- Consumes: `AgentId` from `package:teampilot_common/teampilot_common.dart`
- Produces: `AgentStorage`、`AgentFileSystem`、`AgentProcessRunner`、`AgentModelCatalog`、`AgentAcpRuntime`、`AgentHookRuntime`、`AgentLocalization`、`AgentLogger`、`AgentPorts`（含 `List<String> missing()`）、`AgentContext`（`const AgentContext({required AgentPorts ports})`，构造时 fail-fast 校验）。Task 6 的 claude definition 与 Task 7/8 的注册链路都消费 `AgentContext`。

- [ ] **Step 1: 写失败测试**

`client/packages/teampilot-agent-api/test/agent_context_test.dart`
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_agent_api/teampilot_agent_api.dart';

final class _NoopStorage implements AgentStorage {
  @override
  String homeDirectory() => '/tmp';
  @override
  Map<String, Object?>? readJson(String path) => null;
  @override
  void writeJson(String path, Map<String, Object?> value) {}
}

final class _NoopFileSystem implements AgentFileSystem {
  @override
  bool exists(String path) => false;
  @override
  String read(String path) => '';
  @override
  void write(String path, String contents) {}
  @override
  List<String> list(String directory) => const [];
}

final class _NoopProcessRunner implements AgentProcessRunner {
  @override
  ({int exitCode, String stdout, String stderr}) run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) =>
      (exitCode: 0, stdout: '', stderr: '');
}

final class _NoopModelCatalog implements AgentModelCatalog {
  @override
  List<Map<String, Object?>> providers(AgentId id) => const [];
}

final class _NoopAcpRuntime implements AgentAcpRuntime {
  @override
  String? locateAdapter(AgentId id) => null;
}

final class _NoopHookRuntime implements AgentHookRuntime {
  @override
  String renderGlueScript(String hookId, String event, String command) => '';
}

final class _NoopLocalization implements AgentLocalization {
  @override
  String label(String key) => key;
}

final class _NoopLogger implements AgentLogger {
  @override
  void info(String message) {}
  @override
  void warning(String message) {}
}

AgentPorts fullPorts() => AgentPorts(
  storage: _NoopStorage(),
  fileSystem: _NoopFileSystem(),
  processRunner: _NoopProcessRunner(),
  modelCatalog: _NoopModelCatalog(),
  acpRuntime: _NoopAcpRuntime(),
  hookRuntime: _NoopHookRuntime(),
  localization: _NoopLocalization(),
  logger: _NoopLogger(),
);

void main() {
  test('missing() reports every absent port', () {
    expect(
      const AgentPorts().missing(),
      containsAll(<String>[
        'storage',
        'fileSystem',
        'processRunner',
        'modelCatalog',
        'acpRuntime',
        'hookRuntime',
        'localization',
        'logger',
      ]),
    );
  });

  test('missing() is empty for a complete set', () {
    expect(fullPorts().missing(), isEmpty);
  });

  test('AgentContext exposes the ports', () {
    final ports = fullPorts();
    expect(AgentContext(ports: ports).ports, same(ports));
  });

  test('AgentContext fails fast listing missing ports', () {
    expect(
      () => AgentContext(ports: const AgentPorts()),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Missing agent ports: storage'),
        ),
      ),
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && \
  dart run tool/run_tests.dart --package packages/teampilot-agent-api
```
Expected: FAIL（`AgentPorts` / `AgentContext` 未定义）。

- [ ] **Step 3: 写实现**

`client/packages/teampilot-agent-api/lib/src/agent_ports.dart`
```dart
import 'package:teampilot_common/teampilot_common.dart';

abstract interface class AgentStorage {
  String homeDirectory();
  Map<String, Object?>? readJson(String path);
  void writeJson(String path, Map<String, Object?> value);
}

abstract interface class AgentFileSystem {
  bool exists(String path);
  String read(String path);
  void write(String path, String contents);
  List<String> list(String directory);
}

abstract interface class AgentProcessRunner {
  ({int exitCode, String stdout, String stderr}) run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
  });
}

abstract interface class AgentModelCatalog {
  List<Map<String, Object?>> providers(AgentId id);
}

abstract interface class AgentAcpRuntime {
  String? locateAdapter(AgentId id);
}

abstract interface class AgentHookRuntime {
  String renderGlueScript(String hookId, String event, String command);
}

abstract interface class AgentLocalization {
  String label(String key);
}

abstract interface class AgentLogger {
  void info(String message);
  void warning(String message);
}

/// Host-side ports injected into every agent definition.
final class AgentPorts {
  const AgentPorts({
    this.storage,
    this.fileSystem,
    this.processRunner,
    this.modelCatalog,
    this.acpRuntime,
    this.hookRuntime,
    this.localization,
    this.logger,
  });

  final AgentStorage? storage;
  final AgentFileSystem? fileSystem;
  final AgentProcessRunner? processRunner;
  final AgentModelCatalog? modelCatalog;
  final AgentAcpRuntime? acpRuntime;
  final AgentHookRuntime? hookRuntime;
  final AgentLocalization? localization;
  final AgentLogger? logger;

  List<String> missing() => [
    if (storage == null) 'storage',
    if (fileSystem == null) 'fileSystem',
    if (processRunner == null) 'processRunner',
    if (modelCatalog == null) 'modelCatalog',
    if (acpRuntime == null) 'acpRuntime',
    if (hookRuntime == null) 'hookRuntime',
    if (localization == null) 'localization',
    if (logger == null) 'logger',
  ];
}
```

`client/packages/teampilot-agent-api/lib/src/agent_context.dart`
```dart
import 'agent_ports.dart';

/// Injected runtime context passed to each `@TeampilotAgent` constructor.
final class AgentContext {
  AgentContext({required AgentPorts ports}) : ports = _validate(ports);

  final AgentPorts ports;

  static AgentPorts _validate(AgentPorts ports) {
    final missing = ports.missing();
    if (missing.isNotEmpty) {
      throw StateError('Missing agent ports: ${missing.join(', ')}');
    }
    return ports;
  }
}
```

在 `client/packages/teampilot-agent-api/lib/teampilot_agent_api.dart` 的 export 列表中追加两行：

```dart
export 'src/agent_context.dart';
export 'src/agent_ports.dart';
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && \
  dart run tool/run_tests.dart --package packages/teampilot-agent-api && \
  flutter analyze --no-fatal-infos --no-fatal-warnings
```
Expected: 9 tests PASS（Task 4 的 5 个 + 本任务 4 个）；analyze 无 error。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && \
  git add client/packages/teampilot-agent-api && \
  git commit -m "feat(agents): add host-side ports and AgentContext" -- \
    client/packages/teampilot-agent-api
```

---

### Task 6: `teampilot-agent-claude` 包骨架（最小 definition）

**Files:**
- Create: `client/packages/teampilot-agents/teampilot-agent-claude/pubspec.yaml`
- Create: `client/packages/teampilot-agents/teampilot-agent-claude/lib/teampilot_agent_claude.dart`
- Create: `client/packages/teampilot-agents/teampilot-agent-claude/lib/src/claude_agent_definition.dart`
- Create: `client/packages/teampilot-agents/teampilot-agent-claude/assets/claude.svg`
- Create: `client/packages/teampilot-agents/teampilot-agent-claude/test/claude_agent_definition_test.dart`

**Interfaces:**
- Consumes: `package:teampilot_agent_api/teampilot_agent_api.dart`、`package:teampilot_common/teampilot_common.dart`
- Produces: `ClaudeAgentDefinition`（`@TeampilotAgent(id: 'claude', displayName: 'Claude Code', icon: 'packages/teampilot_agent_claude/assets/claude.svg')`，单参构造 `ClaudeAgentDefinition(AgentContext context)`）；barrel `package:teampilot_agent_claude/teampilot_agent_claude.dart`。Task 7 builder 生成的代码 import 此 barrel 并实例化此类。

> 1A 的最小实现（`_ClaudeMarkerCapability` / `_ClaudeUiFactory`）在 1B 被迁入的真实 capability 与 UI 工厂替换。它们是真实可运行的实现，不是占位符；1A 只验证注册链路。

- [ ] **Step 1: 写失败测试**

`client/packages/teampilot-agents/teampilot-agent-claude/test/claude_agent_definition_test.dart`
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_agent_api/teampilot_agent_api.dart';
import 'package:teampilot_agent_claude/teampilot_agent_claude.dart';
import 'package:teampilot_common/teampilot_common.dart';

void main() {
  test('ClaudeAgentDefinition exposes id, metadata, capability and ui', () {
    final definition = ClaudeAgentDefinition(
      AgentContext(
        ports: AgentPorts(
          storage: _Stub(),
          fileSystem: _Stub(),
          processRunner: _Stub(),
          modelCatalog: _Stub(),
          acpRuntime: _Stub(),
          hookRuntime: _Stub(),
          localization: _Stub(),
          logger: _Stub(),
        ),
      ),
    );

    expect(definition.id, const AgentId('claude'));
    expect(definition.metadata.displayName, 'Claude Code');
    expect(definition.metadata.icon,
        'packages/teampilot_agent_claude/assets/claude.svg');
    expect(definition.metadata.transport, containsAll(<String>['pty', 'acp']));
    expect(definition.capabilities, isNotEmpty);
    expect(definition.ui, isA<AgentUiFactory>());
  });
}

/// Satisfies every host port interface for the minimal definition test.
final class _Stub implements
    AgentStorage,
    AgentFileSystem,
    AgentProcessRunner,
    AgentModelCatalog,
    AgentAcpRuntime,
    AgentHookRuntime,
    AgentLocalization,
    AgentLogger {
  @override
  String homeDirectory() => '/tmp';
  @override
  Map<String, Object?>? readJson(String path) => null;
  @override
  void writeJson(String path, Map<String, Object?> value) {}
  @override
  bool exists(String path) => false;
  @override
  String read(String path) => '';
  @override
  void write(String path, String contents) {}
  @override
  List<String> list(String directory) => const [];
  @override
  ({int exitCode, String stdout, String stderr}) run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) =>
      (exitCode: 0, stdout: '', stderr: '');
  @override
  List<Map<String, Object?>> providers(AgentId id) => const [];
  @override
  String? locateAdapter(AgentId id) => null;
  @override
  String renderGlueScript(String hookId, String event, String command) => '';
  @override
  String label(String key) => key;
  @override
  void info(String message) {}
  @override
  void warning(String message) {}
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && \
  dart run tool/run_tests.dart --package packages/teampilot-agents/teampilot-agent-claude
```
Expected: FAIL（`package:teampilot_agent_claude/...` 找不到）。

- [ ] **Step 3: 写实现**

`client/packages/teampilot-agents/teampilot-agent-claude/pubspec.yaml`
```yaml
name: teampilot_agent_claude
description: Claude Code agent package for TeamPilot.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.1

dependencies:
  flutter:
    sdk: flutter
  teampilot_agent_api:
    path: ../../teampilot-agent-api
  teampilot_common:
    path: ../../teampilot-common

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/claude.svg
```

`client/packages/teampilot-agents/teampilot-agent-claude/lib/teampilot_agent_claude.dart`
```dart
export 'src/claude_agent_definition.dart';
```

`client/packages/teampilot-agents/teampilot-agent-claude/lib/src/claude_agent_definition.dart`
```dart
import 'package:flutter/widgets.dart';
import 'package:teampilot_agent_api/teampilot_agent_api.dart';
import 'package:teampilot_common/teampilot_common.dart';

@TeampilotAgent(
  id: 'claude',
  displayName: 'Claude Code',
  icon: 'packages/teampilot_agent_claude/assets/claude.svg',
)
final class ClaudeAgentDefinition implements AgentDefinition {
  ClaudeAgentDefinition(this.context);

  final AgentContext context;

  @override
  AgentId get id => const AgentId('claude');

  @override
  Iterable<AgentCapability> get capabilities => const [
    _ClaudeMarkerCapability(),
  ];

  @override
  AgentMetadata get metadata => const AgentMetadata(
    displayName: 'Claude Code',
    icon: 'packages/teampilot_agent_claude/assets/claude.svg',
    hookSupport: {},
    providerPersistenceStrategy: 'default',
    usageCategory: 'cli',
    transport: {'pty', 'acp'},
  );

  @override
  AgentUiFactory get ui => const _ClaudeUiFactory();
}

final class _ClaudeMarkerCapability implements AgentCapability {
  const _ClaudeMarkerCapability();
}

final class _ClaudeUiFactory implements AgentUiFactory {
  const _ClaudeUiFactory();

  @override
  Widget buildProviderFormSection(BuildContext context) =>
      const SizedBox.shrink();

  @override
  Future<bool> showLoginDialog(
    BuildContext context, {
    required String executable,
  }) async =>
      false;
}
```

`client/packages/teampilot-agents/teampilot-agent-claude/assets/claude.svg`
```xml
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
  <circle cx="12" cy="12" r="10" fill="#D97757"/>
</svg>
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && \
  dart run tool/run_tests.dart --package packages/teampilot-agents/teampilot-agent-claude && \
  flutter analyze --no-fatal-infos --no-fatal-warnings
```
Expected: 1 test PASS；analyze 无 error。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && \
  git add client/packages/teampilot-agents/teampilot-agent-claude && \
  git commit -m "feat(agents): add teampilot_agent_claude package skeleton" -- \
    client/packages/teampilot-agents/teampilot-agent-claude
```

---

### Task 7: `teampilot-agents-builder`（build_runner Builder）

**Files:**
- Create: `client/packages/teampilot-agents/teampilot-agents-builder/pubspec.yaml`
- Create: `client/packages/teampilot-agents/teampilot-agents-builder/build.yaml`
- Create: `client/packages/teampilot-agents/teampilot-agents-builder/lib/builder.dart`
- Create: `client/packages/teampilot-agents/teampilot-agents-bundle/pubspec.yaml`（最小骨架，Task 8 补全依赖）
- Create: `client/packages/teampilot-agents/teampilot-agents-bundle/test/agent_manifest_consistency_test.dart`
- Modify: `client/pubspec.yaml`（`dev_dependencies` 段）

**Interfaces:**
- Consumes: `TeampilotAgent` / `AgentManifest` / `AgentDefinition` from `package:teampilot_agent_api/teampilot_agent_api.dart`；`AgentId` from `package:teampilot_common/teampilot_common.dart`
- Produces: builder key `teampilot_agents_builder|agent_aggregator`；生成 `lib/register_all.g.dart`，签名 `void registerAllAgents(api.AgentRegistry registry, api.AgentContext context)`，并在开头设置 `registry.defaultId`。Task 8 的 bundle `build.yaml` 引用此 key。

- [ ] **Step 1: 写失败测试（bundle 契约测试）**

本任务的验证入口是「bundle 里还没有生成物时契约测试失败」，因此先建 bundle 的测试骨架与最小 pubspec：

```bash
mkdir -p /home/hhoa/git/hhoa/teampilot/client/packages/teampilot-agents/teampilot-agents-bundle/{lib,test}
```

`client/packages/teampilot-agents/teampilot-agents-bundle/pubspec.yaml`
```yaml
name: teampilot_agents_bundle
description: Generated registration bundle for the TeamPilot agent packages.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.1

dev_dependencies:
  test: ^1.25.0
```

`client/packages/teampilot-agents/teampilot-agents-bundle/test/agent_manifest_consistency_test.dart`
```dart
import 'dart:io';

import 'package:test/test.dart';

const _apiPackage = 'teampilot_agent_api';

void main() {
  final bundleDir = Directory.current.path;

  test('generated registry registers exactly the annotated agents', () {
    final generated = File('$bundleDir/lib/register_all.g.dart').readAsStringSync();
    expect(generated, contains('void registerAllAgents('));
    expect(generated, contains('registry.register(a0.ClaudeAgentDefinition(context));'));
    expect(generated, contains("registry.defaultId = const common.AgentId('claude');"));
    expect(generated, isNot(contains('if (id ==')));
  });

  test('manifest imports match bundle pubspec agent path deps', () {
    final manifest =
        File('$bundleDir/lib/agent_manifest.dart').readAsStringSync();
    final pubspec = File('$bundleDir/pubspec.yaml').readAsStringSync();
    final importNames = RegExp(r"import 'package:([a-z0-9_]+)/")
        .allMatches(manifest)
        .map((m) => m.group(1)!)
        .where((name) =>
            name.startsWith('teampilot_agent_') && name != _apiPackage)
        .toSet();
    final depNames = RegExp(r'^  (teampilot_agent_[a-z0-9_]+):$', multiLine: true)
        .allMatches(pubspec)
        .map((m) => m.group(1)!)
        .where((name) => name != _apiPackage)
        .toSet();
    expect(importNames, equals(depNames));
  });
}
```

```bash
cd /home/hhoa/git/hhoa/teampilot/client && \
  dart run tool/run_tests.dart --package packages/teampilot-agents/teampilot-agents-bundle
```
Expected: FAIL（`register_all.g.dart` 不存在 / `agent_manifest.dart` 不存在）。

- [ ] **Step 2: 写 builder 实现**

`client/packages/teampilot-agents/teampilot-agents-builder/pubspec.yaml`
```yaml
name: teampilot_agents_builder
description: build_runner Builder that generates the TeamPilot agent registry.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.1

dependencies:
  analyzer: 14.3.0
  build: 4.0.11
  source_gen: 4.3.0
  teampilot_agent_api:
    path: ../../teampilot-agent-api
  teampilot_common:
    path: ../../teampilot-common

dev_dependencies:
  lints: ^5.0.0
```

`client/packages/teampilot-agents/teampilot-agents-builder/build.yaml`
```yaml
builders:
  agent_aggregator:
    import: "package:teampilot_agents_builder/builder.dart"
    builder_factories: ["agentAggregator"]
    build_extensions: {"lib/agent_manifest.dart": ["lib/register_all.g.dart"]}
    auto_apply: none
    build_to: source
```

`client/packages/teampilot-agents/teampilot-agents-builder/lib/builder.dart`
```dart
import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:teampilot_common/teampilot_common.dart';

Builder agentAggregator(BuilderOptions options) => _AgentAggregator();

const _agentChecker = TypeChecker.fromUrl(
  'package:teampilot_agent_api/teampilot_agent_api.dart#TeampilotAgent',
);
const _manifestChecker = TypeChecker.fromUrl(
  'package:teampilot_agent_api/teampilot_agent_api.dart#AgentManifest',
);
const _definitionChecker = TypeChecker.fromUrl(
  'package:teampilot_agent_api/teampilot_agent_api.dart#AgentDefinition',
);

final class _AgentAggregator extends Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
    'lib/agent_manifest.dart': ['lib/register_all.g.dart'],
  };

  @override
  Future<void> build(BuildStep step) async {
    final manifestLibrary =
        await step.resolver.libraryFor(step.inputId);
    final manifestAnnotation =
        _manifestChecker.firstAnnotationOf(manifestLibrary);
    if (manifestAnnotation == null) {
      throw StateError(
        '${step.inputId}: missing @AgentManifest on the library directive',
      );
    }
    final manifestValues = ConstantReader(manifestAnnotation);
    final defaultId = manifestValues.read('defaultId').stringValue;
    if (!AgentId(defaultId).isValid) {
      throw StateError('${step.inputId}: invalid defaultId "$defaultId"');
    }

    final found = <_Found>[];
    final seenIds = <String>{};
    await for (final library in step.resolver.libraries) {
      final importUri = _packageUri(library);
      if (importUri == null) continue;
      for (final annotated
          in LibraryReader(library).annotatedWith(_agentChecker)) {
        final element = annotated.element;
        if (element is! ClassElement) {
          throw StateError(
            '$importUri: @TeampilotAgent must annotate a class, '
            'got ${element.name}',
          );
        }
        if (!_definitionChecker.isAssignableFrom(element)) {
          throw StateError(
            '$importUri: ${element.name} must implement AgentDefinition',
          );
        }
        final annotation = annotated.annotation;
        final id = annotation.read('id').stringValue;
        final displayName = annotation.read('displayName').stringValue;
        final icon = annotation.read('icon').stringValue;
        if (!AgentId(id).isValid) {
          throw StateError('$importUri: invalid AgentId "$id"');
        }
        if (!seenIds.add(id)) {
          throw StateError('$importUri: duplicate AgentId "$id"');
        }
        if (displayName.isEmpty || icon.isEmpty) {
          throw StateError(
            '$importUri: @TeampilotAgent($id) needs displayName and icon',
          );
        }
        found.add(_Found(
          id: id,
          className: element.name!,
          importUri: importUri,
        ));
      }
    }

    if (!seenIds.contains(defaultId)) {
      throw StateError(
        '@AgentManifest(defaultId: "$defaultId") has no registered agent',
      );
    }
    found.sort((a, b) => a.id.compareTo(b.id));

    final buffer = StringBuffer('// GENERATED CODE - DO NOT MODIFY BY HAND\n')
      ..writeln("import 'package:teampilot_agent_api/teampilot_agent_api.dart' as api;")
      ..writeln("import 'package:teampilot_common/teampilot_common.dart' as common;");
    for (var i = 0; i < found.length; i++) {
      buffer.writeln("import '${found[i].importUri}' as a$i;");
    }
    buffer
      ..writeln(
        '\nvoid registerAllAgents(api.AgentRegistry registry, '
        'api.AgentContext context) {',
      )
      ..writeln("  registry.defaultId = const common.AgentId('$defaultId');");
    for (var i = 0; i < found.length; i++) {
      buffer.writeln('  registry.register(a$i.${found[i].className}(context));');
    }
    buffer.writeln('}');

    await step.writeAsString(
      AssetId(step.inputId.package, 'lib/register_all.g.dart'),
      buffer.toString(),
    );
  }
}

String? _packageUri(LibraryElement library) {
  final uri = Uri.parse(library.identifier);
  if (uri.scheme == 'package') return library.identifier;
  if (uri.scheme == 'asset' && uri.pathSegments.length > 2) {
    return 'package:${uri.pathSegments.first}/'
        '${uri.pathSegments.skip(2).join('/')}';
  }
  return null;
}

final class _Found {
  const _Found({
    required this.id,
    required this.className,
    required this.importUri,
  });

  final String id;
  final String className;
  final String importUri;
}
```

> 实施说明：`AgentContext` 单参构造由生成代码 `ClaudeAgentDefinition(context)` 在编译期保证（比 builder 反射检查更强）；barrel 已导出由「类能被 `resolver.libraries` 从 manifest 的 import 图发现」这一事实保证。两者都不在 builder 里重复检查，等价于 spec 第 6.2 节第 4 项的校验意图。

在 `client/pubspec.yaml` 的 `dev_dependencies:` 段加入：

```yaml
  teampilot_agents_builder:
    path: packages/teampilot-agents/teampilot-agents-builder
```

- [ ] **Step 3: 分析 builder 包**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter pub get && \
  dart analyze packages/teampilot-agents/teampilot-agents-builder
```
Expected: 无 error。builder 已用 `element.name!`（analyzer 14.3.0 的 `Element.name` 是 `String?`）、显式声明 `analyzer: 14.3.0` 依赖。

- [ ] **Step 4: Commit（bundle 测试仍红，等 Task 8）**

```bash
cd /home/hhoa/git/hhoa/teampilot && \
  git add client/packages/teampilot-agents/teampilot-agents-builder \
          client/packages/teampilot-agents/teampilot-agents-bundle \
          client/pubspec.yaml client/pubspec.lock && \
  git commit -m "feat(agents): add build_runner agent registry builder" -- \
    client/packages/teampilot-agents/teampilot-agents-builder \
    client/packages/teampilot-agents/teampilot-agents-bundle \
    client/pubspec.yaml client/pubspec.lock
```

---

### Task 8: `teampilot-agents-bundle` 与生成物

**Files:**
- Modify: `client/packages/teampilot-agents/teampilot-agents-bundle/pubspec.yaml`（Task 7 已建最小骨架，本任务补全依赖）
- Create: `client/packages/teampilot-agents/teampilot-agents-bundle/build.yaml`
- Create: `client/packages/teampilot-agents/teampilot-agents-bundle/lib/agent_manifest.dart`
- Create: `client/packages/teampilot-agents/teampilot-agents-bundle/lib/register_all.g.dart`（由生成器产生）
- Modify: `client/pubspec.yaml`（`dependencies` 段）

**Interfaces:**
- Consumes: builder key `teampilot_agents_builder|agent_aggregator`（Task 7）；`package:teampilot_agent_claude/teampilot_agent_claude.dart`（Task 6）；`package:teampilot_agent_api/teampilot_agent_api.dart`
- Produces: `package:teampilot_agents_bundle/register_all.g.dart` 导出 `void registerAllAgents(AgentRegistry, AgentContext)`。Task 9 的 app 侧测试与 CI 消费它。

- [ ] **Step 1: 写 bundle 文件**

把 `client/packages/teampilot-agents/teampilot-agents-bundle/pubspec.yaml` 整体替换为：
```yaml
name: teampilot_agents_bundle
description: Generated registration bundle for the TeamPilot agent packages.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.1

dependencies:
  teampilot_agent_api:
    path: ../../teampilot-agent-api
  teampilot_common:
    path: ../../teampilot-common
  teampilot_agent_claude:
    path: ../teampilot-agent-claude

dev_dependencies:
  test: ^1.25.0
```

`client/packages/teampilot-agents/teampilot-agents-bundle/build.yaml`
```yaml
targets:
  $default:
    builders:
      teampilot_agents_builder|agent_aggregator:
        enabled: true
```

`client/packages/teampilot-agents/teampilot-agents-bundle/lib/agent_manifest.dart`
```dart
@AgentManifest(defaultId: 'claude')
library;

import 'package:teampilot_agent_api/teampilot_agent_api.dart';
import 'package:teampilot_agent_claude/teampilot_agent_claude.dart';
```

在 `client/pubspec.yaml` 的 `dependencies:` 段加入：

```yaml
  teampilot_agents_bundle:
    path: packages/teampilot-agents/teampilot-agents-bundle
```

- [ ] **Step 2: 生成注册表**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter pub get && \
  dart run build_runner build --delete-conflicting-outputs
```
Expected: 构建成功；`client/packages/teampilot-agents/teampilot-agents-bundle/lib/register_all.g.dart` 内容为：

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND
import 'package:teampilot_agent_api/teampilot_agent_api.dart' as api;
import 'package:teampilot_common/teampilot_common.dart' as common;
import 'package:teampilot_agent_claude/teampilot_agent_claude.dart' as a0;

void registerAllAgents(api.AgentRegistry registry, api.AgentContext context) {
  registry.defaultId = const common.AgentId('claude');
  registry.register(a0.ClaudeAgentDefinition(context));
}
```

- [ ] **Step 3: 跑 Task 7 写的契约测试确认通过**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && \
  dart run tool/run_tests.dart --package packages/teampilot-agents/teampilot-agents-bundle && \
  flutter analyze --no-fatal-infos --no-fatal-warnings
```
Expected: 2 tests PASS；analyze 无 error。

- [ ] **Step 4: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && \
  git add client/packages/teampilot-agents/teampilot-agents-bundle \
          client/pubspec.yaml client/pubspec.lock && \
  git commit -m "feat(agents): add bundle package and generated agent registry" -- \
    client/packages/teampilot-agents/teampilot-agents-bundle \
    client/pubspec.yaml client/pubspec.lock
```

---

### Task 9: app 侧链路测试与 CI 接线

**Files:**
- Create: `client/test/services/cli/agent_registration_test.dart`
- Modify: `.github/workflows/client-verify.yml`

**Interfaces:**
- Consumes: `package:teampilot_agents_bundle/register_all.g.dart`（Task 8）、`package:teampilot_agent_api/teampilot_agent_api.dart`、`package:teampilot_common/teampilot_common.dart`
- Produces: 一条证明「app 侧无需 import 具体 agent 即可注册 claude」的测试；CI 中的生成物一致性门禁与包级测试步骤。

- [ ] **Step 1: 写 app 侧链路测试并立即运行**

前 8 个任务的 TDD 循环已完成；本任务是接线验证，测试写完即应通过（生成物与 client pubspec 依赖在 Task 8 已就位）。

`client/test/services/cli/agent_registration_test.dart`
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_agent_api/teampilot_agent_api.dart';
import 'package:teampilot_agents_bundle/register_all.g.dart';
import 'package:teampilot_common/teampilot_common.dart';

void main() {
  test('registerAllAgents registers claude without app-specific imports', () {
    final registry = AgentRegistry();
    registerAllAgents(registry, AgentContext(ports: _allPorts));

    expect(registry.tryGet(const AgentId('claude')), isNotNull);
    expect(registry.all.map((d) => d.id.value).toList(), ['claude']);
    expect(registry.defaultId, const AgentId('claude'));
    expect(registry.launchable.length, 1);
  });

  test('unknown agent ids do not silently fall back', () {
    final registry = AgentRegistry();
    registerAllAgents(registry, AgentContext(ports: _allPorts));

    expect(
      () => requireAgent(registry, const AgentId('ghost')),
      throwsA(isA<UnknownAgentException>()),
    );
  });
}

final AgentPorts _allPorts = AgentPorts(
  storage: _Stub(),
  fileSystem: _Stub(),
  processRunner: _Stub(),
  modelCatalog: _Stub(),
  acpRuntime: _Stub(),
  hookRuntime: _Stub(),
  localization: _Stub(),
  logger: _Stub(),
);

final class _Stub implements
    AgentStorage,
    AgentFileSystem,
    AgentProcessRunner,
    AgentModelCatalog,
    AgentAcpRuntime,
    AgentHookRuntime,
    AgentLocalization,
    AgentLogger {
  @override
  String homeDirectory() => '/tmp';
  @override
  Map<String, Object?>? readJson(String path) => null;
  @override
  void writeJson(String path, Map<String, Object?> value) {}
  @override
  bool exists(String path) => false;
  @override
  String read(String path) => '';
  @override
  void write(String path, String contents) {}
  @override
  List<String> list(String directory) => const [];
  @override
  ({int exitCode, String stdout, String stderr}) run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) =>
      (exitCode: 0, stdout: '', stderr: '');
  @override
  List<Map<String, Object?>> providers(AgentId id) => const [];
  @override
  String? locateAdapter(AgentId id) => null;
  @override
  String renderGlueScript(String hookId, String event, String command) => '';
  @override
  String label(String key) => key;
  @override
  void info(String message) {}
  @override
  void warning(String message) {}
}
```

```bash
cd /home/hhoa/git/hhoa/teampilot/client && \
  dart run tool/run_tests.dart test/services/cli/agent_registration_test.dart
```
Expected: 2 tests PASS。若报 `Target of URI doesn't exist: 'package:teampilot_agents_bundle/...'`，先跑 `flutter pub get` 再重试。

- [ ] **Step 2: 接线 CI**

在 `.github/workflows/client-verify.yml` 的 `Analyze (errors only)` step 之后、`teampilot_search Rust tests` 之前插入：

```yaml
      - name: Generate agent registry
        run: dart run build_runner build --delete-conflicting-outputs

      - name: Check agent registry is up to date
        run: git diff --exit-code -- packages/teampilot-agents/teampilot-agents-bundle/lib/register_all.g.dart

      - name: Agent package tests
        run: |
          dart run tool/run_tests.dart --package packages/teampilot-common
          dart run tool/run_tests.dart --package packages/teampilot-agent-api
          dart run tool/run_tests.dart --package packages/teampilot-agents/teampilot-agent-claude
          dart run tool/run_tests.dart --package packages/teampilot-agents/teampilot-agents-bundle
```

- [ ] **Step 3: 跑测试确认通过**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && \
  dart run tool/run_tests.dart test/services/cli/agent_registration_test.dart && \
  dart run build_runner build --delete-conflicting-outputs && \
  git diff --exit-code -- packages/teampilot-agents/teampilot-agents-bundle/lib/register_all.g.dart
```
Expected: 2 tests PASS；最后一条命令退出码 0（生成物已提交且可重复生成）。

- [ ] **Step 4: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && \
  git add client/test/services/cli/agent_registration_test.dart \
          .github/workflows/client-verify.yml && \
  git commit -m "test(agents): wire generated registry into client tests and CI" -- \
    client/test/services/cli/agent_registration_test.dart \
    .github/workflows/client-verify.yml
```

---

### Task 10: 1A 验收

**Files:** 无新增；只做验证与必要的修复提交。

**Interfaces:**
- Consumes: Task 1–9 全部产物
- Produces: 1A 完成结论；1B 计划的入口条件。

- [ ] **Step 1: 全量内层验证**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && \
  flutter pub get && \
  dart run build_runner build --delete-conflicting-outputs && \
  flutter analyze --no-fatal-infos --no-fatal-warnings
```
Expected: 全部退出码 0。

- [ ] **Step 2: 包级测试**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && \
  dart run tool/run_tests.dart --package packages/teampilot-common && \
  dart run tool/run_tests.dart --package packages/teampilot-agent-api && \
  dart run tool/run_tests.dart --package packages/teampilot-agents/teampilot-agent-claude && \
  dart run tool/run_tests.dart --package packages/teampilot-agents/teampilot-agents-bundle
```
Expected: 6 + 9 + 1 + 2 = 18 tests PASS。

- [ ] **Step 3: 全量 suite（后台运行，完成前只跑一次）**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart
```
Expected: PASS。若失败，按 `docs/DEVELOPMENT.md` 的 test-loop 规则先修再重跑；不要跳过。

- [ ] **Step 4: 生成物与目录结构验收**

```bash
cd /home/hhoa/git/hhoa/teampilot && \
  git diff --exit-code -- client/packages/teampilot-agents/teampilot-agents-bundle/lib/register_all.g.dart && \
  test ! -f client/packages/teampilot-agents/pubspec.yaml && \
  echo "1A OK: container is pure, generated registry is stable"
```
Expected: `1A OK: container is pure, generated registry is stable`。

- [ ] **Step 5: 记录 1A 完成并给出 1B 入口条件**

在 `docs/superpowers/specs/2026-11-09-cli-agent-packages-design.md` 的「14. Spike 结论」之后追加：

```markdown
## 15. 1A 完成记录

- 日期：2026-11-09
- 验证：`flutter analyze --no-fatal-infos --no-fatal-warnings` 通过；包级 18 个测试通过；全量 `dart run tool/run_tests.dart` 通过；生成物可重复生成。
- 1B 入口条件：本记录存在、Spike 结论为通过、`register_all.g.dart` 已提交、CI 三个 step 已生效。
- 1B 单独成计划。
```

```bash
cd /home/hhoa/git/hhoa/teampilot && \
  git add docs/superpowers/specs/2026-11-09-cli-agent-packages-design.md && \
  git commit -m "docs: record 1A completion and 1B entry conditions" -- \
    docs/superpowers/specs/2026-11-09-cli-agent-packages-design.md
```

---

## 计划自检（作者填写）

- **Spec 覆盖**：spec 第 4 节包布局 → Task 2/4/6/7/8；第 5 节契约层 → Task 2/4/5；第 6 节注册机制 → Task 7/8；第 7 节数据流 → Task 9（以 app 侧测试代替 app_shell 接线，1B 再做真实接线）；第 8 节失败模式 → Task 5（`AgentContext` fail-fast）、Task 4（`UnknownAgentException`、重复 id）、Task 7（构建期校验）；第 9 节 spike → Task 1；第 10 节测试/CI → Task 3/9/10；第 11 节后续约定 → Global Constraints + Task 6 注释。
- **1B 的边界**：50 文件迁移、63 个 app 内部依赖分类、8 组端口的 app 侧适配器、`registry/` 接口 import 改写、过渡 facade 与 legacy adapter、`app_shell.dart` 真实接线、能力接口 `Agent*` 重命名、arb 补键，全部留给 1B 计划。本计划不改 `services/cli/` 下任何现有文件。
- **占位符扫描**：无 TBD / TODO / "implement later" / "similar to Task N"；每个改动步骤都有完整代码或完整命令。
- **类型一致性**：`AgentId` / `AgentContext` / `AgentPorts` / `AgentRegistry` / `registerAllAgents` / `ClaudeAgentDefinition` / builder key `teampilot_agents_builder|agent_aggregator` 在各任务中拼写与签名一致；生成物里 `api.AgentRegistry`、`api.AgentContext`、`common.AgentId`、`a0.ClaudeAgentDefinition(context)` 与 Task 4/6 定义一致。
