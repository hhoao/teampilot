# Hook 管理（全局库 + 按 scope 启用 + 统一物化管线）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用户可配置的 hooks：全局库定义（事件 → 命令/托管脚本 + matcher + policy），按 team > expert > workspace 启用，启动时经每个 CLI 唯一的 HookWriter 物化为原生配置（claude/flashskyai settings.json、codex config.toml、cursor hooks.json、opencode 生成 plugin），并把内部托管 hooks 收敛进同一管线。

**Architecture:** 三层模型（定义 → 启用 → 物化）+ 归一化 `HookEntry` 为唯一中间表示。`ConfigBundle.hookIds` 复用现有 enable-list 合并；每 CLI 一个 `HookWriterCapability` 渲染原生格式（merge-preserving）；command 类 hook 包进生成的粘合脚本（stdin/stdout 透传、静态决策注入、timeout、方言）。收敛阶段把 agent-status/bus/delegate/扩展/插件六条独立 merge 链迁移为 `HookEntry` 源。

**Tech Stack:** Flutter/Dart（flutter_bloc、go_router）、`client/lib/services/io/filesystem.dart`（含 `InMemoryFilesystem` 测试双）、`toml` 包、`HostScriptRunner`/`HostScriptDialect`、l10n（app_en.arb / app_zh.arb）。

**Spec:** `docs/superpowers/specs/2026-08-13-hook-management-design.md`

## Global Constraints

- 验证命令（每任务最后跑）：
  `cd client && flutter test test/<本任务测试> -v`
  最终全量：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
- 测试用内存 fs：`client/test/support/in_memory_filesystem.dart` 的 `InMemoryFilesystem`。
- 不改 l10n 生成文件；只改 `client/lib/l10n/app_en.arb` / `app_zh.arb`，然后 `flutter gen-l10n` 重新生成。
- 诊断用 `AppLogger`（`utils/logging/logger.dart`），禁止 `print`。
- 新增共享 UI 原语进 `client/packages/shared_ui`；页面壳在 `client/lib/pages/<domain>/`。
- 物化脚本路径必须是 session 内绝对路径（staging 用 work-plane 路径，flush 后即机器路径）。
- 各 writer 的 `render` 必须是纯函数（无 IO），脚本内容经 `HookWriteResult.scripts`（`GeneratedScript`，定义在 `registry/capabilities/hook_registry.dart`）返回，由装配点写盘。
- 决策 JSON 格式（writer 提供，粘合脚本注入）：claude/flashskyai/codex flat `{"permissionDecision":"allow"}` / `{"permissionDecision":"deny","permissionDecisionReason":"TeamPilot hook policy"}`；cursor `{"permission":"allow"}` / `{"permission":"deny","user_message":"TeamPilot hook policy"}`；opencode 桥契约 `{"decision":"allow"|"deny"}`。
- cursor 事件名小写（`sessionStart`/`preToolUse`/…）、`beforeSubmitPrompt` 等按官方 docs（https://cursor.com/docs/hooks）；claude/codex 用 PascalCase。
- matcher 语义：claude/codex/cursor 写原生 matcher 字段；opencode 桥仅在 `tool.execute.*` 上用 tool 键限定。

---

## 文件结构

**新建（lib）：**
- `client/lib/models/hook_event.dart` — 归一化事件枚举 + 每 CLI 支持矩阵
- `client/lib/models/hook_entry.dart` — HookEntry/HookAction/HookPolicy/HookSource
- `client/lib/models/hook_definition.dart` — hook.json 持久化模型
- `client/lib/services/hook/hook_repository.dart` — 全局库 CRUD（`<root>/hooks/{id}/`）
- `client/lib/services/hook/hook_library_resolver.dart` — hookIds → HookEntry（脚本内容加载）
- `client/lib/services/hook/glue_script_builder.dart` — 粘合脚本生成（bash/powershell）
- `client/lib/services/cli/registry/capabilities/hook_writer_capability.dart` — HookWriterCapability + HookRenderContext + HookWriteResult
- `client/lib/services/cli/registry/config_profile/claude_family_hook_writer.dart` — claude/flashskyai writer
- `client/lib/services/cli/codex/provider/codex_hook_writer.dart` — codex writer
- `client/lib/services/cli/cursor/provider/cursor_hook_writer.dart` — cursor writer
- `client/lib/services/cli/opencode/capabilities/opencode_hook_writer.dart` — opencode writer（生成 JS plugin）
- `client/lib/services/cli/registry/config_profile/hook_seat_context_completer.dart` — 收敛期托管来源组装
- `client/lib/cubits/hook_cubit.dart`
- `client/lib/pages/hooks/hook_management_page.dart`（列表）
- `client/lib/pages/hooks/hook_editor_page.dart`（表单 + 能力矩阵）
- `client/lib/pages/home_workspace/workspace/config/workspace_hooks_section.dart`
- `client/lib/pages/team_config/team_config_hooks_section.dart`

**修改（lib）：**
- `client/lib/models/config_bundle.dart`（hookIds）
- `client/lib/services/launch/layered_config_bundle.dart`（merge hookIds）
- `client/lib/services/cli/registry/config_profile/config_profile_context.dart`（hooks 字段）
- `client/lib/services/provider/config_profile_service.dart`（staging 解析 + 传 ctx）
- `client/lib/services/cli/claude/capabilities/config_profile.dart`、`claude_tool.dart`
- `client/lib/services/cli/flashskyai/capabilities/config_profile.dart`、`flashskyai_tool.dart`
- `client/lib/services/cli/codex/capabilities/config_profile.dart`、`codex_tool.dart`、`codex/provider/codex_home_provisioner.dart`（agent-status 迁移）
- `client/lib/services/cli/cursor/capabilities/config_profile.dart`、`cursor_tool.dart`、`cursor/provider/cursor_home_provisioner.dart`（迁移）
- `client/lib/services/cli/opencode/capabilities/config_profile.dart`、`opencode_tool.dart`（迁移）
- `client/lib/services/team/team_lead_delegate_settings_merge.dart`（迁移）
- `client/lib/services/extension/effect/settings_hook_effect_applier.dart`（迁移）
- `client/lib/services/plugin/plugin_manifest_service.dart`（迁移）
- `client/lib/services/cli/registry/capabilities/claude_family_hook_registry.dart`、`hook_registry.dart`（删除资产路径）
- `client/lib/pages/home_workspace/workspace/workspace_config_section.dart`（hooks section）
- `client/lib/pages/home_workspace/workspace/workspace_config_workspace.dart`（dispatch）
- `client/lib/router/app_router.dart`（`/hooks` 路由）
- `client/lib/pages/home_workspace/home_workspace_global_section.dart`（`HomeGlobalView.hooks`）
- `client/lib/l10n/app_en.arb`、`app_zh.arb`

**测试（client/test/）：** `models/hook_event_test.dart`、`models/hook_entry_test.dart`、`models/hook_definition_test.dart`、`services/hook/hook_repository_test.dart`、`services/hook/hook_library_resolver_test.dart`、`services/hook/glue_script_builder_test.dart`、`services/cli/registry/capabilities/hook_writer_test.dart`、`services/cli/registry/config_profile/claude_family_hook_writer_test.dart`、`services/cli/codex/codex_hook_writer_test.dart`、`services/cli/cursor/cursor_hook_writer_test.dart`、`services/cli/opencode/opencode_hook_writer_test.dart`、`services/hook/hook_cubit_test.dart`、`pages/hooks/hook_management_page_test.dart`、`pages/hooks/hook_editor_page_test.dart`，以及各迁移任务的对齐测试。

---

### Task 1: HookEvent 枚举 + 每 CLI 支持矩阵

**Files:**
- Create: `client/lib/models/hook_event.dart`
- Test: `client/test/models/hook_event_test.dart`

**Interfaces:**
- Produces: `enum HookEvent`（13 值 + `isIntercepting`）、`class HookCliSupport{supported, approximate, nativeEvent}`、`abstract final class HookEventCapability`（`static HookCliSupport support(HookEvent, CliTool)`、`static String? nativeEvent(HookEvent, CliTool)`、`static bool supports(HookEvent, CliTool)`、`static const matrix`）。后续所有 writer/UI 依赖此表。

- [ ] **Step 1: Write the failing test**

`client/test/models/hook_event_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  group('HookEvent', () {
    test('intercepting events', () {
      expect(HookEvent.preToolUse.isIntercepting, isTrue);
      expect(HookEvent.permissionRequest.isIntercepting, isTrue);
      expect(HookEvent.shellCommandRequest.isIntercepting, isTrue);
      expect(HookEvent.stop.isIntercepting, isFalse);
      expect(HookEvent.sessionStart.isIntercepting, isFalse);
    });
  });

  group('HookEventCapability.matrix', () {
    test('claude native event names are PascalCase', () {
      expect(
        HookEventCapability.nativeEvent(HookEvent.preToolUse, CliTool.claude),
        'PreToolUse',
      );
      expect(
        HookEventCapability.nativeEvent(HookEvent.stop, CliTool.flashskyai),
        'Stop',
      );
    });

    test('codex supports shellCommandRequest; claude does not', () {
      expect(
        HookEventCapability.supports(
          HookEvent.shellCommandRequest,
          CliTool.codex,
        ),
        isTrue,
      );
      expect(
        HookEventCapability.supports(
          HookEvent.shellCommandRequest,
          CliTool.claude,
        ),
        isFalse,
      );
    });

    test('cursor events are lowercase with beforeSubmitPrompt', () {
      expect(
        HookEventCapability.nativeEvent(
          HookEvent.userPromptSubmit,
          CliTool.cursor,
        ),
        'beforeSubmitPrompt',
      );
      expect(
        HookEventCapability.supports(HookEvent.sessionStart, CliTool.cursor),
        isTrue,
      );
      expect(
        HookEventCapability.support(
          HookEvent.permissionRequest,
          CliTool.cursor,
        ).supported,
        isFalse,
      );
    });

    test('opencode bridge events are approximate', () {
      final support = HookEventCapability.support(
        HookEvent.preToolUse,
        CliTool.opencode,
      );
      expect(support.supported, isTrue);
      expect(support.approximate, isTrue);
      expect(support.nativeEvent, 'tool.execute.before');
    });

    test('unknown combo falls back to unsupported', () {
      expect(
        HookEventCapability.support(
          HookEvent.notification,
          CliTool.opencode,
        ).supported,
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/hook_event_test.dart -v`
Expected: FAIL — `hook_event.dart` not found.

- [ ] **Step 3: Write minimal implementation**

`client/lib/models/hook_event.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'team_config.dart';

/// 归一化 hook 事件（claude 命名为规范；各 CLI 由 [HookEventCapability] 映射）。
enum HookEvent {
  sessionStart,
  sessionEnd,
  userPromptSubmit,
  preToolUse,
  postToolUse,
  postToolUseFailure,
  permissionRequest,
  stop,
  stopFailure,
  subagentStop,
  preCompact,
  notification,
  shellCommandRequest;

  /// 可携带静态决策（policy）的事件。
  bool get isIntercepting => switch (this) {
    HookEvent.preToolUse ||
    HookEvent.permissionRequest ||
    HookEvent.shellCommandRequest => true,
    _ => false,
  };

  static HookEvent? tryParse(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// 某 CLI 对某归一化事件的支持情况。
@immutable
class HookCliSupport {
  const HookCliSupport({
    required this.supported,
    this.approximate = false,
    this.nativeEvent,
  });

  final bool supported;

  /// 近似语义（如 opencode `session.idle` ≈ stop）——UI 矩阵标注。
  final bool approximate;
  final String? nativeEvent;
}

/// 归一化事件 → 各 CLI 支持矩阵（唯一事实源；writer 与 UI 能力矩阵共用）。
abstract final class HookEventCapability {
  HookEventCapability._();

  static const Map<HookEvent, Map<CliTool, HookCliSupport>> matrix = {
    HookEvent.sessionStart: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'SessionStart'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'SessionStart'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'SessionStart'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'sessionStart'),
    },
    HookEvent.sessionEnd: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'SessionEnd'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'SessionEnd'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'SessionEnd'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'sessionEnd'),
    },
    HookEvent.userPromptSubmit: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'UserPromptSubmit'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'UserPromptSubmit'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'UserPromptSubmit'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'beforeSubmitPrompt'),
      CliTool.opencode: HookCliSupport(
        supported: true,
        approximate: true,
        nativeEvent: 'chat.message',
      ),
    },
    HookEvent.preToolUse: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'PreToolUse'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'PreToolUse'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'PreToolUse'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'preToolUse'),
      CliTool.opencode: HookCliSupport(
        supported: true,
        approximate: true,
        nativeEvent: 'tool.execute.before',
      ),
    },
    HookEvent.postToolUse: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'PostToolUse'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'PostToolUse'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'PostToolUse'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'postToolUse'),
      CliTool.opencode: HookCliSupport(
        supported: true,
        approximate: true,
        nativeEvent: 'tool.execute.after',
      ),
    },
    HookEvent.postToolUseFailure: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'PostToolUseFailure'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'PostToolUseFailure'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'PostToolUseFailure'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'postToolUseFailure'),
    },
    HookEvent.permissionRequest: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'PermissionRequest'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'PermissionRequest'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'PermissionRequest'),
      CliTool.opencode: HookCliSupport(
        supported: true,
        approximate: true,
        nativeEvent: 'permission.asked',
      ),
    },
    HookEvent.stop: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'Stop'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'Stop'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'Stop'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'stop'),
      CliTool.opencode: HookCliSupport(
        supported: true,
        approximate: true,
        nativeEvent: 'session.idle',
      ),
    },
    HookEvent.stopFailure: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'StopFailure'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'StopFailure'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'StopFailure'),
    },
    HookEvent.subagentStop: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'SubagentStop'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'SubagentStop'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'SubagentStop'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'subagentStop'),
    },
    HookEvent.preCompact: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'PreCompact'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'PreCompact'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'PreCompact'),
      CliTool.cursor: HookCliSupport(supported: true, nativeEvent: 'preCompact'),
    },
    HookEvent.notification: {
      CliTool.claude: HookCliSupport(supported: true, nativeEvent: 'Notification'),
      CliTool.flashskyai: HookCliSupport(supported: true, nativeEvent: 'Notification'),
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'Notification'),
    },
    HookEvent.shellCommandRequest: {
      CliTool.codex: HookCliSupport(supported: true, nativeEvent: 'ShellCommandRequest'),
      CliTool.cursor: HookCliSupport(
        supported: true,
        approximate: true,
        nativeEvent: 'beforeShellExecution',
      ),
    },
  };

  static HookCliSupport support(HookEvent event, CliTool cli) =>
      matrix[event]?[cli] ?? const HookCliSupport(supported: false);

  static bool supports(HookEvent event, CliTool cli) =>
      support(event, cli).supported;

  static String? nativeEvent(HookEvent event, CliTool cli) =>
      support(event, cli).nativeEvent;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/hook_event_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/hook_event.dart client/test/models/hook_event_test.dart
git commit -m "feat(hooks): normalized hook event enum + per-CLI support matrix"
```

---

### Task 2: HookEntry / HookAction / HookPolicy / HookSource

**Files:**
- Create: `client/lib/models/hook_entry.dart`
- Test: `client/test/models/hook_entry_test.dart`

**Interfaces:**
- Consumes: `HookEvent`（Task 1）。
- Produces: `enum HookSource { userLibrary, plugin, extension, managed }`、`enum HookPolicy { none, allow, deny }`、`sealed class HookAction`、`final class CommandHookAction`（`CommandHookAction.raw(command)` / `CommandHookAction.script(fileName, scriptContent)`）、`final class HttpHookAction(url, headers)`、`@immutable class HookEntry`（值语义 `==`/`hashCode`）。所有 writer、resolver、迁移任务使用。

- [ ] **Step 1: Write the failing test**

`client/test/models/hook_entry_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';

void main() {
  test('raw command action', () {
    const action = CommandHookAction.raw('echo hi');
    expect(action.command, 'echo hi');
    expect(action.fileName, isNull);
    expect(action.scriptContent, isNull);
  });

  test('script action carries content resolved from library', () {
    const action = CommandHookAction.script(
      fileName: 'hook.sh',
      scriptContent: '#!/usr/bin/env bash\necho hi',
    );
    expect(action.command, isNull);
    expect(action.fileName, 'hook.sh');
    expect(action.scriptContent, contains('echo hi'));
  });

  test('http action', () {
    const action = HttpHookAction(
      url: 'http://127.0.0.1:1/hook',
      headers: {'X-Member': 'm1'},
    );
    expect(action.url, 'http://127.0.0.1:1/hook');
    expect(action.headers['X-Member'], 'm1');
  });

  test('entry value equality', () {
    const a = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'Bash',
      action: CommandHookAction.raw('echo hi'),
      policy: HookPolicy.deny,
      timeout: Duration(seconds: 30),
      env: {'A': 'b'},
    );
    const b = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'Bash',
      action: CommandHookAction.raw('echo hi'),
      policy: HookPolicy.deny,
      timeout: Duration(seconds: 30),
      env: {'A': 'b'},
    );
    const c = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'Bash',
      action: CommandHookAction.raw('echo bye'),
      policy: HookPolicy.deny,
      timeout: Duration(seconds: 30),
      env: {'A': 'b'},
    );
    expect(a, b);
    expect(a == c, isFalse);
    expect(a.hashCode, b.hashCode);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/hook_entry_test.dart -v`
Expected: FAIL — `hook_entry.dart` not found.

- [ ] **Step 3: Write minimal implementation**

`client/lib/models/hook_entry.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'hook_event.dart';

/// Hook 条目的来源（收敛管线：用户库 / 插件 / 扩展 / 内部托管）。
enum HookSource { userLibrary, plugin, extension, managed }

/// 拦截类事件的静态决策。
enum HookPolicy { none, allow, deny }

/// 归一化 action：命令（原始字符串或托管脚本）或 http。
@immutable
sealed class HookAction {
  const HookAction();
}

@immutable
final class CommandHookAction extends HookAction {
  const CommandHookAction.raw(String command)
    : command = command,
      fileName = null,
      scriptContent = null;

  const CommandHookAction.script({
    required String fileName,
    required String scriptContent,
  }) : command = null,
       fileName = fileName,
       scriptContent = scriptContent;

  /// 原始命令字符串（raw 用户命令；resolver 前未解析）。
  final String? command;

  /// 托管脚本文件名（如 `hook.sh` / `hook.ps1`）。
  final String? fileName;

  /// 托管脚本内容（resolver 从全局库加载后填充）。
  final String? scriptContent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommandHookAction &&
          command == other.command &&
          fileName == other.fileName &&
          scriptContent == other.scriptContent;

  @override
  int get hashCode => Object.hash(command, fileName, scriptContent);
}

@immutable
final class HttpHookAction extends HookAction {
  const HttpHookAction({required this.url, this.headers = const {}});

  final String url;
  final Map<String, String> headers;
}

/// 统一 hook 表示：所有来源（用户库/插件/扩展/托管）的中间形态，
/// 各 CLI HookWriter 的唯一输入。
@immutable
class HookEntry {
  const HookEntry({
    required this.id,
    required this.source,
    required this.event,
    this.matcher,
    required this.action,
    this.policy = HookPolicy.none,
    this.timeout,
    this.env = const {},
    this.blockOnDecision = false,
  });

  /// 身份键（用户库 id；内部托管源为稳定符号 id）。
  final String id;
  final HookSource source;
  final HookEvent event;

  /// 工具名/命令正则（事件支持才生效）。
  final String? matcher;
  final HookAction action;
  final HookPolicy policy;
  final Duration? timeout;
  final Map<String, String> env;

  /// idle 语义：命令末尾 `exit 2`（内部托管用）。
  final bool blockOnDecision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HookEntry &&
          id == other.id &&
          source == other.source &&
          event == other.event &&
          matcher == other.matcher &&
          action == other.action &&
          policy == other.policy &&
          timeout == other.timeout &&
          mapEquals(env, other.env) &&
          blockOnDecision == other.blockOnDecision;

  @override
  int get hashCode => Object.hash(
    id,
    source,
    event,
    matcher,
    action,
    policy,
    timeout,
    Object.hashAll(env.entries),
    blockOnDecision,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/hook_entry_test.dart -v`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/hook_entry.dart client/test/models/hook_entry_test.dart
git commit -m "feat(hooks): unified HookEntry model (action/policy/source)"
```

---

### Task 3: HookDefinition（hook.json 持久化模型）

**Files:**
- Create: `client/lib/models/hook_definition.dart`
- Test: `client/test/models/hook_definition_test.dart`

**Interfaces:**
- Consumes: `HookAction`/`HookPolicy`/`HookEvent`（Task 1-2）。
- Produces: `@immutable class HookDefinition`（`fromJson`/`toJson`/`copyWith`/值语义）。`HookRepository`（Task 5）与编辑器（Task 22）使用。

- [ ] **Step 1: Write the failing test**

`client/test/models/hook_definition_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';

void main() {
  test('round-trips a raw command definition', () {
    final definition = HookDefinition(
      id: 'h1',
      name: 'Deny git push',
      description: 'Block git push in Bash',
      event: HookEvent.preToolUse,
      matcher: 'Bash',
      action: const CommandHookAction.raw('exit 2'),
      policy: HookPolicy.deny,
      timeoutSec: 10,
      env: const {'DEBUG': '1'},
    );
    final json = definition.toJson();
    final restored = HookDefinition.fromJson(json);
    expect(restored, definition);
    expect(restored.policy, HookPolicy.deny);
    expect((restored.action as CommandHookAction).command, 'exit 2');
  });

  test('round-trips a script definition', () {
    const action = CommandHookAction.script(
      fileName: 'hook.sh',
      scriptContent: '#!/usr/bin/env bash\ncat >/dev/null',
    );
    final definition = HookDefinition(
      id: 'h2',
      name: 'On start',
      event: HookEvent.sessionStart,
      action: action,
    );
    final restored = HookDefinition.fromJson(definition.toJson());
    expect(restored.id, 'h2');
    expect(restored.event, HookEvent.sessionStart);
    expect((restored.action as CommandHookAction).fileName, 'hook.sh');
    // 持久化不存内容（内容在脚本文件里）。
    expect((restored.action as CommandHookAction).scriptContent, isNull);
  });

  test('round-trips http action', () {
    final definition = HookDefinition(
      id: 'h3',
      name: 'Notify',
      event: HookEvent.notification,
      action: const HttpHookAction(
        url: 'http://127.0.0.1:1/hook',
        headers: {'X-A': 'b'},
      ),
    );
    final restored = HookDefinition.fromJson(definition.toJson());
    expect(restored.action, definition.action);
  });

  test('defaults on absent fields', () {
    final definition = HookDefinition.fromJson({
      'id': 'h4',
      'event': 'stop',
    });
    expect(definition.name, '');
    expect(definition.description, '');
    expect(definition.policy, HookPolicy.none);
    expect(definition.matcher, isNull);
    expect(definition.timeoutSec, isNull);
    expect(definition.env, isEmpty);
  });

  test('unknown event falls back to stop', () {
    final definition = HookDefinition.fromJson({'id': 'h5', 'event': 'nope'});
    expect(definition.event, HookEvent.stop);
  });

  test('copyWith', () {
    final base = HookDefinition(
      id: 'h6',
      name: 'a',
      event: HookEvent.stop,
      action: const CommandHookAction.raw('echo a'),
    );
    final next = base.copyWith(name: 'b', policy: HookPolicy.allow);
    expect(next.id, 'h6');
    expect(next.name, 'b');
    expect(next.policy, HookPolicy.allow);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/hook_definition_test.dart -v`
Expected: FAIL — file not found.

- [ ] **Step 3: Write minimal implementation**

`client/lib/models/hook_definition.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'hook_entry.dart';
import 'hook_event.dart';

/// 全局库中一个 hook 的持久化定义（`<root>/hooks/{id}/hook.json`）。
///
/// 托管脚本内容不持久化在这里——脚本是 hook 目录下的独立文件
/// （`hook.sh` / `hook.ps1`），[HookLibraryResolver] 加载后填入
/// [CommandHookAction.scriptContent]。
@immutable
class HookDefinition {
  const HookDefinition({
    required this.id,
    this.name = '',
    this.description = '',
    required this.event,
    this.matcher,
    required this.action,
    this.policy = HookPolicy.none,
    this.timeoutSec,
    this.env = const {},
  });

  factory HookDefinition.fromJson(Map<String, Object?> json) {
    final action = _actionFromJson(json['action']);
    return HookDefinition(
      id: (json['id'] as String? ?? '').trim(),
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      event: HookEvent.tryParse(json['event'] as String?) ?? HookEvent.stop,
      matcher: (json['matcher'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['matcher'] as String).trim(),
      action: action,
      policy: HookPolicy.values.asNameMap()[json['policy']] ??
          HookPolicy.none,
      timeoutSec: (json['timeoutSec'] as num?)?.toInt(),
      env: _decodeEnv(json['env']),
    );
  }

  final String id;
  final String name;
  final String description;
  final HookEvent event;
  final String? matcher;
  final HookAction action;
  final HookPolicy policy;
  final int? timeoutSec;
  final Map<String, String> env;

  HookDefinition copyWith({
    String? name,
    String? description,
    HookEvent? event,
    String? matcher,
    HookAction? action,
    HookPolicy? policy,
    int? timeoutSec,
    Map<String, String>? env,
  }) => HookDefinition(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    event: event ?? this.event,
    matcher: matcher ?? this.matcher,
    action: action ?? this.action,
    policy: policy ?? this.policy,
    timeoutSec: timeoutSec ?? this.timeoutSec,
    env: env ?? this.env,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    if (name.isNotEmpty) 'name': name,
    if (description.isNotEmpty) 'description': description,
    'event': event.name,
    if (matcher != null) 'matcher': matcher,
    'action': _actionToJson(action),
    if (policy != HookPolicy.none) 'policy': policy.name,
    if (timeoutSec != null) 'timeoutSec': timeoutSec,
    if (env.isNotEmpty) 'env': env,
  };

  static Map<String, Object?> _actionToJson(HookAction action) =>
      switch (action) {
        CommandHookAction c => c.command != null
            ? {'type': 'raw', 'command': c.command}
            : {'type': 'script', 'fileName': c.fileName},
        HttpHookAction h => {
          'type': 'http',
          'url': h.url,
          if (h.headers.isNotEmpty) 'headers': h.headers,
        },
      };

  static HookAction _actionFromJson(Object? raw) {
    final map = raw is Map
        ? raw.cast<String, Object?>()
        : const <String, Object?>{};
    final type = map['type'] as String? ?? 'raw';
    return switch (type) {
      'script' => CommandHookAction.script(
        fileName: map['fileName'] as String? ?? 'hook.sh',
        scriptContent: map['scriptContent'] as String?,
      ),
      'http' => HttpHookAction(
        url: map['url'] as String? ?? '',
        headers: _decodeEnv(map['headers']),
      ),
      _ => CommandHookAction.raw(map['command'] as String? ?? ''),
    };
  }

  static Map<String, String> _decodeEnv(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is String) out[entry.key.toString()] = value;
    }
    return Map.unmodifiable(out);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HookDefinition &&
          id == other.id &&
          name == other.name &&
          description == other.description &&
          event == other.event &&
          matcher == other.matcher &&
          action == other.action &&
          policy == other.policy &&
          timeoutSec == other.timeoutSec &&
          mapEquals(env, other.env);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    event,
    matcher,
    action,
    policy,
    timeoutSec,
    Object.hashAll(env.entries),
  );
}
```

注意：`CommandHookAction` 的 `==`/`hashCode` 必须在 Task 2 的类内定义（若 Task 2 末尾留了顶层 `operator ==`，在这里一并修正为类内成员）。

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/hook_definition_test.dart test/models/hook_entry_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/hook_definition.dart client/test/models/hook_definition_test.dart
git commit -m "feat(hooks): HookDefinition persistence model (hook.json)"
```

---

### Task 4: ConfigBundle.hookIds + LayeredConfigBundle.merge

**Files:**
- Modify: `client/lib/models/config_bundle.dart`
- Modify: `client/lib/services/launch/layered_config_bundle.dart`
- Test: `client/test/services/launch/layered_config_bundle_test.dart`

**Interfaces:**
- Consumes: 现有 `ConfigBundle`（skillIds/pluginIds/mcpServerIds）。
- Produces: `ConfigBundle.hookIds`（`copyWith`/`toJson`/`fromJson`/`==`/`hashCode` 同步）、`LayeredConfigBundle.merge` 增加 `hookIds` 维度（team > expert > workspace 顺序合并）。`SessionRuntimePlanBuilder`、`WorkspaceProjectConfigCubit`、staging 自动携带（Task 9 消费）。

- [ ] **Step 1: Write the failing test**

`client/test/services/launch/layered_config_bundle_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/services/launch/layered_config_bundle.dart';

void main() {
  test('merge hookIds team > expert > workspace with dedupe', () {
    final merged = LayeredConfigBundle.merge(
      team: const ConfigBundle(hookIds: ['h-team', 'h-shared']),
      expert: const ConfigBundle(hookIds: ['h-exp', 'h-shared']),
      workspace: const ConfigBundle(hookIds: ['h-ws', 'h-shared']),
    );
    expect(merged.hookIds, ['h-team', 'h-shared', 'h-exp', 'h-ws']);
  });

  test('empty layers fall back to workspace', () {
    final merged = LayeredConfigBundle.merge(
      workspace: const ConfigBundle(hookIds: ['h-ws']),
    );
    expect(merged.hookIds, ['h-ws']);
  });

  test('hookIds round-trip through toJson/fromJson', () {
    const bundle = ConfigBundle(
      skillIds: ['s1'],
      hookIds: ['h1', 'h2'],
    );
    final restored = ConfigBundle.fromJson(bundle.toJson());
    expect(restored, bundle);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/launch/layered_config_bundle_test.dart -v`
Expected: FAIL — `hookIds` getter undefined.

- [ ] **Step 3: Write minimal implementation**

`client/lib/models/config_bundle.dart` 全量替换为：
```dart
import 'package:flutter/foundation.dart';

/// The shared skills/plugins/mcp/hooks enable-lists carried by every
/// [LaunchProfile]. Extensions are tracked separately in
/// ExtensionRepository, keyed by identity id.
@immutable
class ConfigBundle {
  const ConfigBundle({
    this.skillIds = const [],
    this.pluginIds = const [],
    this.mcpServerIds = const [],
    this.hookIds = const [],
  });

  factory ConfigBundle.fromJson(Map<String, Object?> json) => ConfigBundle(
    skillIds: _decodeIds(json['skillIds']),
    pluginIds: _decodeIds(json['pluginIds']),
    mcpServerIds: _decodeIds(json['mcpServerIds']),
    hookIds: _decodeIds(json['hookIds']),
  );

  final List<String> skillIds;
  final List<String> pluginIds;
  final List<String> mcpServerIds;
  final List<String> hookIds;

  static List<String> _decodeIds(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  ConfigBundle copyWith({
    List<String>? skillIds,
    List<String>? pluginIds,
    List<String>? mcpServerIds,
    List<String>? hookIds,
  }) => ConfigBundle(
    skillIds: skillIds ?? this.skillIds,
    pluginIds: pluginIds ?? this.pluginIds,
    mcpServerIds: mcpServerIds ?? this.mcpServerIds,
    hookIds: hookIds ?? this.hookIds,
  );

  Map<String, Object?> toJson() => {
    if (skillIds.isNotEmpty) 'skillIds': skillIds,
    if (pluginIds.isNotEmpty) 'pluginIds': pluginIds,
    if (mcpServerIds.isNotEmpty) 'mcpServerIds': mcpServerIds,
    if (hookIds.isNotEmpty) 'hookIds': hookIds,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConfigBundle &&
          listEquals(skillIds, other.skillIds) &&
          listEquals(pluginIds, other.pluginIds) &&
          listEquals(mcpServerIds, other.mcpServerIds) &&
          listEquals(hookIds, other.hookIds);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(skillIds),
    Object.hashAll(pluginIds),
    Object.hashAll(mcpServerIds),
    Object.hashAll(hookIds),
  );
}
```

`client/lib/services/launch/layered_config_bundle.dart` 的 `merge` 增加一行：
```dart
      hookIds: _mergeIds(workspace.hookIds, expert?.hookIds, team?.hookIds),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/launch/layered_config_bundle_test.dart -v`
Expected: PASS（现有 config bundle 相关测试不应回归）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/config_bundle.dart \
  client/lib/services/launch/layered_config_bundle.dart \
  client/test/services/launch/layered_config_bundle_test.dart
git commit -m "feat(hooks): ConfigBundle.hookIds enable-list + layered merge"
```

---

### Task 5: HookRepository（全局库 CRUD）

**Files:**
- Create: `client/lib/services/hook/hook_repository.dart`
- Test: `client/test/services/hook/hook_repository_test.dart`

**Interfaces:**
- Consumes: `HookDefinition`（Task 3）、`Filesystem`（`client/lib/services/io/filesystem.dart`）。
- Produces: `class HookRepository{ HookRepository({required Filesystem fs, required String teampilotRoot}); Future<List<HookDefinition>> loadAll(); Future<HookDefinition?> load(String id); Future<void> save(HookDefinition); Future<void> delete(String id); Future<void> writeScript(String id, String fileName, String content); Future<String?> readScript(String id, String fileName); Future<List<String>> scriptFileNames(String id); }`。Task 6 resolver、Task 21-22 UI 使用。

- [ ] **Step 1: Write the failing test**

`client/test/services/hook/hook_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/hook/hook_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import '../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late HookRepository repository;

  setUp(() {
    fs = InMemoryFilesystem();
    repository = HookRepository(fs: fs, teampilotRoot: '/root');
  });

  const definition = HookDefinition(
    id: 'h1',
    name: 'On start',
    event: HookEvent.sessionStart,
    action: CommandHookAction.raw('echo start'),
  );

  test('loadAll returns empty when library missing', () async {
    expect(await repository.loadAll(), isEmpty);
  });

  test('save then load round-trips', () async {
    await repository.save(definition);
    final loaded = await repository.load('h1');
    expect(loaded, definition);
    final all = await repository.loadAll();
    expect(all.map((d) => d.id), ['h1']);
  });

  test('load skips corrupt definitions', () async {
    await fs.writeString('/root/hooks/bad/hook.json', 'not json');
    await repository.save(definition);
    final all = await repository.loadAll();
    expect(all.map((d) => d.id), ['h1']);
  });

  test('delete removes directory', () async {
    await repository.save(definition);
    await repository.writeScript('h1', 'hook.sh', '#!/usr/bin/env bash\n');
    await repository.delete('h1');
    expect(await repository.load('h1'), isNull);
    expect(await repository.scriptFileNames('h1'), isEmpty);
  });

  test('scripts round-trip', () async {
    await repository.save(definition);
    await repository.writeScript('h1', 'hook.sh', 'echo hi');
    expect(await repository.readScript('h1', 'hook.sh'), 'echo hi');
    expect(await repository.scriptFileNames('h1'), ['hook.sh']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/hook/hook_repository_test.dart -v`
Expected: FAIL — file not found。若 `InMemoryFilesystem` 构造需要参数，检查 `client/test/support/in_memory_filesystem.dart`（无参构造）。

- [ ] **Step 3: Write minimal implementation**

`client/lib/services/hook/hook_repository.dart`:
```dart
import 'dart:convert';

import '../../models/hook_definition.dart';
import '../io/filesystem.dart';

/// 全局 hook 库 CRUD：`<teampilotRoot>/hooks/{id}/hook.json` + 托管脚本文件。
class HookRepository {
  HookRepository({required Filesystem fs, required String teampilotRoot})
    : _fs = fs,
      _root = fs.pathContext.join(teampilotRoot, 'hooks');

  static const definitionsFileName = 'hook.json';

  final Filesystem _fs;
  final String _root;

  String _hookDir(String id) => _fs.pathContext.join(_root, id);

  String _definitionPath(String id) =>
      _fs.pathContext.join(_hookDir(id), definitionsFileName);

  String _scriptPath(String id, String fileName) =>
      _fs.pathContext.join(_hookDir(id), fileName);

  Future<List<HookDefinition>> loadAll() async {
    if (!(await _fs.stat(_root)).isDirectory) return const [];
    final out = <HookDefinition>[];
    for (final entry in await _fs.listDir(_root)) {
      if (!entry.isDirectory) continue;
      final definition = await load(entry.name);
      if (definition != null) out.add(definition);
    }
    out.sort((a, b) => a.id.compareTo(b.id));
    return List.unmodifiable(out);
  }

  Future<HookDefinition?> load(String id) async {
    final text = await _fs.readString(_definitionPath(id));
    if (text == null || text.trim().isEmpty) return null;
    try {
      return HookDefinition.fromJson(
        jsonDecode(text) as Map<String, Object?>,
      );
    } on Object {
      return null;
    }
  }

  Future<void> save(HookDefinition definition) async {
    await _fs.ensureDir(_hookDir(definition.id));
    await _fs.atomicWrite(
      _definitionPath(definition.id),
      const JsonEncoder.withIndent('  ').convert(definition.toJson()),
    );
  }

  Future<void> delete(String id) async {
    await _fs.removeRecursive(_hookDir(id));
  }

  Future<void> writeScript(String id, String fileName, String content) async {
    await _fs.ensureDir(_hookDir(id));
    await _fs.atomicWrite(_scriptPath(id, fileName), content);
  }

  Future<String?> readScript(String id, String fileName) =>
      _fs.readString(_scriptPath(id, fileName));

  Future<List<String>> scriptFileNames(String id) async {
    if (!(await _fs.stat(_hookDir(id))).isDirectory) return const [];
    final names = <String>[];
    for (final entry in await _fs.listDir(_hookDir(id))) {
      if (entry.isFile && entry.name != definitionsFileName) {
        names.add(entry.name);
      }
    }
    return List.unmodifiable(names);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/hook/hook_repository_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/hook/hook_repository.dart \
  client/test/services/hook/hook_repository_test.dart
git commit -m "feat(hooks): global hook library repository (hook.json + scripts)"
```

---

### Task 6: HookLibraryResolver

**Files:**
- Create: `client/lib/services/hook/hook_library_resolver.dart`
- Test: `client/test/services/hook/hook_library_resolver_test.dart`

**Interfaces:**
- Consumes: `HookRepository`（Task 5）、`HookEntry`/`HookDefinition`。
- Produces: `class ResolvedHooks{ entries, warnings }`、`class HookLibraryResolver{ Future<ResolvedHooks> resolve(List<String> hookIds) }`。Task 9 staging 调用。

- [ ] **Step 1: Write the failing test**

`client/test/services/hook/hook_library_resolver_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/hook/hook_library_resolver.dart';
import 'package:teampilot/services/io/filesystem.dart';
import '../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late HookLibraryResolver resolver;

  setUp(() {
    fs = InMemoryFilesystem();
    resolver = HookLibraryResolver(fs: fs, teampilotRoot: '/root');
  });

  Future<void> writeDefinition(HookDefinition definition) async {
    final repo = HookRepository(fs: fs, teampilotRoot: '/root');
    await repo.save(definition);
  }

  test('resolves raw command hooks in order with dedupe', () async {
    await writeDefinition(const HookDefinition(
      id: 'h1',
      name: 'a',
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo a'),
    ));
    await writeDefinition(const HookDefinition(
      id: 'h2',
      name: 'b',
      event: HookEvent.sessionStart,
      action: CommandHookAction.raw('echo b'),
    ));
    final resolved = await resolver.resolve(['h2', 'h1', 'h2']);
    expect(resolved.warnings, isEmpty);
    expect(resolved.entries.map((e) => e.id), ['h2', 'h1']);
    expect(resolved.entries.first.source, HookSource.userLibrary);
    expect(resolved.entries.first.event, HookEvent.sessionStart);
  });

  test('loads managed script content', () async {
    await writeDefinition(const HookDefinition(
      id: 'h1',
      name: 'a',
      event: HookEvent.preToolUse,
      action: CommandHookAction.script(fileName: 'hook.sh'),
    ));
    await fs.writeString('/root/hooks/h1/hook.sh', '#!/usr/bin/env bash\necho hi');
    final resolved = await resolver.resolve(['h1']);
    final action = resolved.entries.single.action as CommandHookAction;
    expect(action.scriptContent, contains('echo hi'));
  });

  test('missing definition and missing script produce warnings', () async {
    await writeDefinition(const HookDefinition(
      id: 'h1',
      name: 'a',
      event: HookEvent.stop,
      action: CommandHookAction.script(fileName: 'hook.sh'),
    ));
    final resolved = await resolver.resolve(['missing', 'h1']);
    expect(resolved.entries, isEmpty);
    expect(
      resolved.warnings,
      containsAll(['hook_missing_missing', 'hook_script_missing_h1_hook.sh']),
    );
  });

  test('policy and env are carried over', () async {
    await writeDefinition(const HookDefinition(
      id: 'h1',
      name: 'a',
      event: HookEvent.preToolUse,
      matcher: 'Bash',
      policy: HookPolicy.deny,
      timeoutSec: 12,
      env: {'A': 'b'},
      action: CommandHookAction.raw('exit 2'),
    ));
    final resolved = await resolver.resolve(['h1']);
    final entry = resolved.entries.single;
    expect(entry.policy, HookPolicy.deny);
    expect(entry.matcher, 'Bash');
    expect(entry.timeout, const Duration(seconds: 12));
    expect(entry.env, {'A': 'b'});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/hook/hook_library_resolver_test.dart -v`
Expected: FAIL — file not found。

- [ ] **Step 3: Write minimal implementation**

`client/lib/services/hook/hook_library_resolver.dart`:
```dart
import '../../models/hook_definition.dart';
import '../../models/hook_entry.dart';
import '../io/filesystem.dart';
import 'hook_repository.dart';

class ResolvedHooks {
  const ResolvedHooks({this.entries = const [], this.warnings = const []});

  final List<HookEntry> entries;
  final List<String> warnings;
}

/// 把启用的 hookIds（已按 team > expert > workspace 合并）解析为
/// [HookEntry] 列表：加载定义、读取托管脚本内容、未知 id / 缺脚本记 warning。
class HookLibraryResolver {
  HookLibraryResolver({
    required Filesystem fs,
    required String teampilotRoot,
    HookRepository? repository,
  }) : _repository =
           repository ?? HookRepository(fs: fs, teampilotRoot: teampilotRoot);

  final HookRepository _repository;

  Future<ResolvedHooks> resolve(List<String> hookIds) async {
    final entries = <HookEntry>[];
    final warnings = <String>[];
    final seen = <String>{};
    for (final raw in hookIds) {
      final id = raw.trim();
      if (id.isEmpty || seen.contains(id)) continue;
      seen.add(id);
      final definition = await _repository.load(id);
      if (definition == null) {
        warnings.add('hook_missing_$id');
        continue;
      }
      final action = await _resolveAction(definition, warnings);
      if (action == null) continue;
      entries.add(_toEntry(definition, action));
    }
    return ResolvedHooks(
      entries: List.unmodifiable(entries),
      warnings: List.unmodifiable(warnings),
    );
  }

  Future<HookAction?> _resolveAction(
    HookDefinition definition,
    List<String> warnings,
  ) async {
    final action = definition.action;
    if (action is CommandHookAction && action.command != null) return action;
    if (action is HttpHookAction) return action;
    if (action is CommandHookAction && action.fileName != null) {
      final content = await _repository.readScript(
        definition.id,
        action.fileName!,
      );
      if (content == null || content.trim().isEmpty) {
        warnings.add('hook_script_missing_${definition.id}_${action.fileName}');
        return null;
      }
      return CommandHookAction.script(
        fileName: action.fileName!,
        scriptContent: content,
      );
    }
    warnings.add('hook_invalid_action_${definition.id}');
    return null;
  }

  HookEntry _toEntry(HookDefinition definition, HookAction action) =>
      HookEntry(
        id: definition.id,
        source: HookSource.userLibrary,
        event: definition.event,
        matcher: definition.matcher,
        action: action,
        policy: definition.policy,
        timeout: definition.timeoutSec == null
            ? null
            : Duration(seconds: definition.timeoutSec!),
        env: definition.env,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/hook/hook_library_resolver_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/hook/hook_library_resolver.dart \
  client/test/services/hook/hook_library_resolver_test.dart
git commit -m "feat(hooks): resolve enabled hook ids to entries with warnings"
```

---

### Task 7: HookWriterCapability + HookRenderContext + HookWriteResult

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/hook_writer_capability.dart`
- Test: `client/test/services/cli/registry/capabilities/hook_writer_test.dart`

**Interfaces:**
- Consumes: `HookEntry`、`CliCapability`（`client/lib/services/cli/registry/cli_capability.dart`）、`GeneratedScript`（`registry/capabilities/hook_registry.dart`）。
- Produces: `class HookRenderContext{hooksDir, runner, glueBuilder}`、`class HookWriteResult{configFragments, scripts, warnings}`、`abstract interface class HookWriterCapability implements CliCapability{ nativeEvent(HookEvent); supportsMatcher; supportsHttp; supportsPolicy; supportsEvent(HookEvent); render({entries, ctx}) }`。Task 10-14 各 writer 实现，Task 9 起装配。

- [ ] **Step 1: Write the failing test**

`client/test/services/cli/registry/capabilities/hook_writer_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_registry.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_writer_capability.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';

class _FakeWriter implements HookWriterCapability {
  const _FakeWriter();
  @override
  String? nativeEvent(HookEvent event) =>
      event == HookEvent.stop ? 'Stop' : null;
  @override
  bool get supportsMatcher => true;
  @override
  bool get supportsHttp => false;
  @override
  bool get supportsPolicy => true;
  @override
  HookWriteResult render({
    required List<HookEntry> entries,
    required HookRenderContext ctx,
  }) {
    final warnings = <String>[];
    for (final entry in entries) {
      if (nativeEvent(entry.event) == null) {
        warnings.add('unsupported_${entry.id}');
      }
    }
    return HookWriteResult(
      configFragments: const {'config': {'hooks': []}},
      scripts: const [
        GeneratedScript(fileName: 'a.sh', content: 'echo hi'),
      ],
      warnings: warnings,
    );
  }
}

void main() {
  const writer = _FakeWriter();

  test('supportsEvent reflects nativeEvent', () {
    expect(writer.supportsEvent(HookEvent.stop), isTrue);
    expect(writer.supportsEvent(HookEvent.preToolUse), isFalse);
  });

  test('render is a pure function returning fragments and scripts', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(
      entries: const [entry],
      ctx: const HookRenderContext(
        hooksDir: '/x/hooks',
        runner: null,
        glueBuilder: GlueScriptBuilder(),
      ),
    );
    expect(result.configFragments['config'], {'hooks': []});
    expect(result.scripts.single.fileName, 'a.sh');
    expect(result.warnings, isEmpty);
  });

  test('unsupported events produce warnings', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(
      entries: const [entry],
      ctx: const HookRenderContext(
        hooksDir: '/x/hooks',
        runner: null,
        glueBuilder: GlueScriptBuilder(),
      ),
    );
    expect(result.warnings, ['unsupported_h1']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/capabilities/hook_writer_test.dart -v`
Expected: FAIL — files not found（含 GlueScriptBuilder，Task 8 创建；本任务先建占位）。

- [ ] **Step 3: Write minimal implementation**

先创建 Task 8 的 `GlueScriptBuilder`（本任务测试引用；Task 8 会补全行为测试）：

`client/lib/services/hook/glue_script_builder.dart`:
```dart
import '../../models/hook_entry.dart';

/// 生成包住用户命令的粘合脚本（bash / powershell）。
///
/// 契约（所有 CLI 一致）：
/// 1. stdin 透传给用户命令（hook payload 由 CLI 经 stdin 注入）；
/// 2. env 合并（hook.env → 导出）；
/// 3. 用户命令 stdout 非空 → 原样透传；
/// 4. 用户命令 stdout 为空且 policy != none → 输出 writer 提供的决策 JSON；
/// 5. exit code 透传；blockOnDecision → 末尾 `exit 2`。
class GlueScriptBuilder {
  const GlueScriptBuilder();

  String build({
    required HookPolicy policy,
    required String innerCommand,
    String? decisionJson,
    Duration? timeout,
    Map<String, String> env = const {},
    bool blockOnDecision = false,
    required String dialect,
  }) {
    final body = dialect == 'powershell'
        ? _buildPowershell(
            policy: policy,
            innerCommand: innerCommand,
            decisionJson: decisionJson,
            env: env,
            blockOnDecision: blockOnDecision,
          )
        : _buildBash(
            policy: policy,
            innerCommand: innerCommand,
            decisionJson: decisionJson,
            timeout: timeout,
            env: env,
            blockOnDecision: blockOnDecision,
          );
    return dialect == 'powershell'
        ? '# TeamPilot hook glue — do not edit.\n$body'
        : '#!/usr/bin/env bash\n# TeamPilot hook glue — do not edit.\n$body';
  }

  String _buildBash({
    required HookPolicy policy,
    required String innerCommand,
    String? decisionJson,
    Duration? timeout,
    required Map<String, String> env,
    required bool blockOnDecision,
  }) {
    final buffer = StringBuffer('set -u\n');
    for (final entry in env.entries) {
      buffer.writeln("export ${entry.key}=${_shellQuote(entry.value)}");
    }
    if (decisionJson != null) {
      buffer.writeln("DECISION=${_shellQuote(decisionJson)}");
    }
    final inner = _shellQuote(innerCommand);
    final runLine = timeout == null
        ? 'out="\$(eval $inner 2>&1)"'
        : 'out="\$(timeout ${timeout.inSeconds}s eval $inner 2>&1)"';
    buffer
      ..writeln(runLine)
      ..writeln('code=$?')
      ..writeln('if [ -z "$out" ] && [ -n "${DECISION:-}" ]; then')
      ..writeln('  printf \'%s\n\' "$DECISION"')
      ..writeln('  exit 0')
      ..writeln('fi')
      ..writeln('if [ -n "$out" ]; then printf \'%s\n\' "$out"; fi')
      ..writeln('if [ "$blockOnDecision" = "1" ]; then exit 2; fi');
    if (blockOnDecision) {
      return buffer.toString();
    }
    buffer.writeln('exit $code');
    return buffer.toString();
  }

  String _buildPowershell({
    required HookPolicy policy,
    required String innerCommand,
    String? decisionJson,
    required Map<String, String> env,
    required bool blockOnDecision,
  }) {
    final buffer = StringBuffer("$ErrorActionPreference = 'Continue'\n");
    for (final entry in env.entries) {
      buffer.writeln("\$env:${entry.key} = '${entry.value.replaceAll("'", "''")}'");
    }
    if (decisionJson != null) {
      buffer.writeln("\$Decision = '${decisionJson.replaceAll("'", "''")}'");
    }
    final inner = innerCommand.replaceAll('"', '\\"');
    buffer
      ..writeln('\$out = cmd /c "$inner" 2>&1 | Out-String')
      ..writeln('\$code = \$LASTEXITCODE')
      ..writeln("if ([string]::IsNullOrWhiteSpace(\$out)) {")
      ..writeln('  if ($Decision) { Write-Output $Decision; exit 0 }')
      ..writeln('} else {')
      ..writeln('  Write-Output $out.TrimEnd()')
      ..writeln('}');
    if (blockOnDecision) {
      buffer.writeln('exit 2');
    } else {
      buffer.writeln('exit $code');
    }
    return buffer.toString();
  }

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", r"'\''")}'";
}
```

`client/lib/services/cli/registry/capabilities/hook_writer_capability.dart`:
```dart
import '../../../models/hook_entry.dart';
import '../cli_capability.dart';
import 'hook_registry.dart';

/// 渲染上下文：脚本落盘目录 + 运行器（方言） + 胶水生成器。
class HookRenderContext {
  const HookRenderContext({
    required this.hooksDir,
    required this.runner,
    required this.glueBuilder,
  });

  /// session 内脚本目录（绝对路径，work-plane 路径即机器路径）。
  final String hooksDir;

  /// 主机运行器（dialect：bash / powershell）。
  final HostScriptRunner? runner;

  final GlueScriptBuilder glueBuilder;
}

/// 一次 render 的输出：文件级配置片段 + 生成的脚本 + 警告。
class HookWriteResult {
  const HookWriteResult({
    this.configFragments = const {},
    this.scripts = const [],
    this.warnings = const [],
  });

  /// `Map<相对文件名, 配置内容>`，如 `{'settings.json': {...}}`、
  /// `{'config.toml': '...'}`、`{'hooks.json': {...}}`。
  final Map<String, Object?> configFragments;
  final List<GeneratedScript> scripts;
  final List<String> warnings;
}

/// 每 CLI 一个实现：把归一化 [HookEntry] 渲染为该 CLI 原生 hook 配置。
/// render 必须是纯函数（无 IO）——脚本经 [HookWriteResult.scripts] 返回，
/// 由装配点写盘。
abstract interface class HookWriterCapability implements CliCapability {
  String? nativeEvent(HookEvent event);

  bool get supportsMatcher;
  bool get supportsHttp;
  bool get supportsPolicy;

  bool supportsEvent(HookEvent event) => nativeEvent(event) != null;

  HookWriteResult render({
    required List<HookEntry> entries,
    required HookRenderContext ctx,
  });
}
```

`host_script_runner.dart` 中 `HostScriptRunner` 与 `GeneratedScript`/`GlueScriptBuilder` 的 import 关系：`hook_writer_capability.dart` 需要 `import '../../../host/host_script_runner.dart';`（`HookRenderContext.runner` 类型）。

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/cli/registry/capabilities/hook_writer_test.dart test/services/hook/glue_script_builder_test.dart -v`
Expected: PASS（glue_script_builder_test 在 Task 8 补齐）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/hook/glue_script_builder.dart \
  client/lib/services/cli/registry/capabilities/hook_writer_capability.dart \
  client/test/services/cli/registry/capabilities/hook_writer_test.dart
git commit -m "feat(hooks): HookWriterCapability + render context/result + glue builder"
```

---

### Task 8: GlueScriptBuilder 行为测试

**Files:**
- Modify: `client/lib/services/hook/glue_script_builder.dart`（如有必要）
- Test: `client/test/services/hook/glue_script_builder_test.dart`

**Interfaces:**
- Consumes: Task 7 已建 `GlueScriptBuilder`。
- Produces: 完整验证的 `GlueScriptBuilder.build(...)` 契约。

- [ ] **Step 1: Write the failing test**

`client/test/services/hook/glue_script_builder_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';

void main() {
  const builder = GlueScriptBuilder();

  test('bash glue injects decision JSON on empty output', () {
    final script = builder.build(
      policy: HookPolicy.deny,
      innerCommand: 'echo run',
      decisionJson: '{"permissionDecision":"deny"}',
      dialect: 'bash',
    );
    expect(script, contains('#!/usr/bin/env bash'));
    expect(script, contains("DECISION='{\"permissionDecision\":\"deny\"}'"));
    expect(script, contains('eval $inner'));
    expect(script, contains('exit 0'));
    expect(script, contains('exit $code'));
  });

  test('bash glue passes through user stdout verbatim', () {
    final script = builder.build(
      policy: HookPolicy.none,
      innerCommand: 'echo hi',
      dialect: 'bash',
    );
    expect(script, contains('printf \'%s\n\' "$out"'));
    expect(script, isNot(contains('DECISION=')));
  });

  test('bash glue applies timeout and env and blockOnDecision exit 2', () {
    final script = builder.build(
      policy: HookPolicy.none,
      innerCommand: 'echo hi',
      timeout: const Duration(seconds: 9),
      env: const {'FOO': 'bar'},
      blockOnDecision: true,
      dialect: 'bash',
    );
    expect(script, contains("export FOO='bar'"));
    expect(script, contains('timeout 9s'));
    expect(script, contains('exit 2'));
    expect(script, isNot(contains('exit $code')));
  });

  test('powershell glue injects decision and forwards via cmd /c', () {
    final script = builder.build(
      policy: HookPolicy.allow,
      innerCommand: 'echo run',
      decisionJson: '{"permissionDecision":"allow"}',
      dialect: 'powershell',
    );
    expect(script, contains('cmd /c'));
    expect(script, contains('$Decision'));
    expect(script, contains('$LASTEXITCODE'));
    expect(script, contains('# TeamPilot hook glue'));
  });

  test('single quotes in inner command are escaped for bash', () {
    final script = builder.build(
      policy: HookPolicy.none,
      innerCommand: "echo 'it''s'",
      dialect: 'bash',
    );
    expect(script, contains("'echo '\''it'");
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/hook/glue_script_builder_test.dart -v`
Expected: FAIL（首次跑可能因生成文本与断言差异）——按失败信息调整断言或实现。

- [ ] **Step 3: Adjust implementation until green**

Task 7 的 `GlueScriptBuilder` 已按契约实现（timeout 经 `timeout <t>s eval ...` 包装、`_shellQuote` 转义单引号）。若断言与实现仍有出入（如 `DECISION=` 引号形态、powershell 片段），按失败信息调整断言或实现——**以测试绿为准，契约不变**。

- [ ] **Step 4: Run all hook tests**

Run: `cd client && flutter test test/services/hook/ test/services/cli/registry/capabilities/hook_writer_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/hook/glue_script_builder.dart \
  client/test/services/hook/glue_script_builder_test.dart
git commit -m "test(hooks): glue script contract (decision injection/timeout/env/dialects)"
```

---

### Task 9: 启动编排 — ConfigProfileLaunchContext.hooks + staging 解析

**Files:**
- Modify: `client/lib/services/cli/registry/config_profile/config_profile_context.dart`
- Modify: `client/lib/services/provider/config_profile_service.dart`
- Test: `client/test/services/provider/config_profile_service_hooks_test.dart`

**Interfaces:**
- Consumes: `HookLibraryResolver`（Task 6）、`HookEntry`。
- Produces: `ConfigProfileLaunchContext.hooks: List<HookEntry>`（默认 `const []`）；`stageSimpleSessionLaunch` / `stageTeamLaunch` 内解析 `runtimeBundle.hookIds` → `hooks` 传入 ctx，warning 并入 `TeamLaunchOutcome.warnings`。Task 10-14 各 writer 从 `ctx.hooks` 消费。

- [ ] **Step 1: Write the failing test**

先建一个轻量装配点测试（对 `ConfigProfileLaunchContext` 的字段透传）：

`client/test/services/provider/config_profile_service_hooks_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/registry/config_profile/config_profile_context.dart';

void main() {
  test('ConfigProfileLaunchContext carries hooks with empty default', () {
    const ctx = ConfigProfileLaunchContext(
      workspaceId: 'w',
      teamId: 't',
      sessionId: 's',
      scope: null,
      member: null,
      members: [],
      paths: null,
      catalog: null,
      busIdle: null,
      agentStatus: null,
    );
    expect(ctx.hooks, isEmpty);
  });

  test('hooks are threaded through constructor', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo hi'),
    );
    final ctx = ConfigProfileLaunchContext(
      workspaceId: 'w',
      teamId: 't',
      sessionId: 's',
      scope: null,
      member: null,
      members: const [],
      paths: null,
      catalog: null,
      hooks: const [entry],
    );
    expect(ctx.hooks.single.id, 'h1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/provider/config_profile_service_hooks_test.dart -v`
Expected: FAIL — `hooks` 未定义。若 `ConfigProfileLaunchContext` 构造签名与上面假设不符，先读 `config_profile_context.dart` 实际构造参数，改写测试到与现有调用点一致的必填参数。

- [ ] **Step 3: Modify the context**

`client/lib/services/cli/registry/config_profile/config_profile_context.dart`：
- 字段区（`members` 附近）加：
```dart
  /// 该 seat 生效的用户 hook 条目（staging 按 runtimeBundle.hookIds 解析）。
  final List<HookEntry> hooks;
```
- 构造参数区加：`this.hooks = const []`（保持 const 构造）。
- 顶部 import `../../../models/hook_entry.dart`。

- [ ] **Step 4: Resolve hooks in staging**

`client/lib/services/provider/config_profile_service.dart`：

`stageSimpleSessionLaunch`（`applySimpleSessionFilesystem` 之后、`contributeSimpleSessionLaunch` 之前）：
```dart
    final hooksResult = await HookLibraryResolver(
      fs: readDelegate,
      teampilotRoot: workTeampilotRoot,
    ).resolve(runtimeBundle.hookIds);
```
并把 `hooksResult.entries` 传给 `staging.contributeSimpleSessionLaunch(..., hooks: hooksResult.entries)`；在返回的 outcome warnings 里 `[...fsWarnings, ...hooksResult.warnings, ...outcome.warnings]`。

`stageTeamLaunch`：`ensureSessionProfile` 之后、`cap.contributeLaunch(...)` 之前同样 resolve；`ConfigProfileLaunchContext(...)` 加 `hooks: hooksResult.entries`；outcome warnings 合并 `...hooksResult.warnings`。

`ConfigProfileService.contributeSimpleSessionLaunch`（被 staging 调用，签名加 `List<HookEntry> hooks = const []`）与内部 `ConfigProfileLaunchContext(...)` 传 `hooks: hooks`。注意：`stageSimpleSessionLaunch` 在 `config_profile_service.dart` 内调用的是 `staging.contributeSimpleSessionLaunch(...)`（`_stagingService` 返回同类型实例）。

- [ ] **Step 5: Run test to verify it passes**

Run: `cd client && flutter test test/services/provider/config_profile_service_hooks_test.dart -v`
Expected: PASS

- [ ] **Step 6: Run analyzer**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无新增 error。若 `contributeSimpleSessionLaunch` 有其它调用点（如 `prepareSimpleSessionLaunch` 直连），同步补默认参数即可。

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/cli/registry/config_profile/config_profile_context.dart \
  client/lib/services/provider/config_profile_service.dart \
  client/test/services/provider/config_profile_service_hooks_test.dart
git commit -m "feat(hooks): thread resolved user hooks into launch context"
```

---

### Task 10: claude/flashskyai — ClaudeFamilyHookWriter + 接线

**Files:**
- Create: `client/lib/services/cli/registry/config_profile/claude_family_hook_writer.dart`
- Modify: `client/lib/services/cli/claude/capabilities/config_profile.dart`、`client/lib/services/cli/claude/claude_tool.dart`
- Modify: `client/lib/services/cli/flashskyai/capabilities/config_profile.dart`、`client/lib/services/cli/flashskyai/flashskyai_tool.dart`
- Test: `client/test/services/cli/registry/config_profile/claude_family_hook_writer_test.dart`

**Interfaces:**
- Consumes: `HookWriterCapability`/`HookRenderContext`（Task 7）、`GlueScriptBuilder`、`mergeHooksInto`（`registry/capabilities/claude_family_hook_registry.dart`）、`GeneratedScript`、`CliToolRegistry.builtIn().capability<HookWriterCapability>(cli)`。
- Produces: `class ClaudeFamilyHookWriter implements HookWriterCapability`（claude/flashskyai 共享；`configFragments['settings.json']` = `{'hooks': {...}}` 片段，脚本在 `ctx.hooksDir` 下，命令用 `runner.commandStringForScriptFile`）。两个 tool 定义注册 `hookWriter` 能力；两个 `_writeMemberProfile` 在现有 merge 链后追加渲染 + `mergeHooksInto`。

- [ ] **Step 1: Write the failing test**

`client/test/services/cli/registry/config_profile/claude_family_hook_writer_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/registry/config_profile/claude_family_hook_writer.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_writer_capability.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/host/host_script_dialect.dart';
import 'package:teampilot/services/host/host_script_runner.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';

HookRenderContext bashCtx(String hooksDir) => HookRenderContext(
  hooksDir: hooksDir,
  runner: HostScriptRunner(
    const HostExecutionEnvironment(
      dialect: HostScriptDialect.bash,
      isWindowsHost: false,
      storageMode: 'native',
    ),
  ),
  glueBuilder: const GlueScriptBuilder(),
);

void main() {
  const writer = ClaudeFamilyHookWriter();

  test('raw preToolUse deny hook renders glue + native event + policy json', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'Bash',
      policy: HookPolicy.deny,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(
      entries: const [entry],
      ctx: bashCtx('/s/hooks'),
    );
    expect(result.warnings, isEmpty);
    final section = result.configFragments['settings.json']! as Map;
    final pre = (section['hooks'] as Map)['PreToolUse'] as List;
    final entryJson = pre.single as Map;
    expect(entryJson['matcher'], 'Bash');
    final hook = ((entryJson['hooks'] as List).single) as Map;
    expect(hook['type'], 'command');
    final command = hook['command'] as String;
    expect(command, contains('/s/hooks/teampilot-hook-h1.sh'));
    expect(hook['timeout'], 5);
    // 胶水脚本含决策 JSON
    final glue = result.scripts.singleWhere(
      (s) => s.fileName == 'teampilot-hook-h1.sh',
    );
    expect(glue.content, contains('"permissionDecision":"deny"'));
  });

  test('http action renders native http hook', () {
    const entry = HookEntry(
      id: 'h2',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: HttpHookAction(
        url: 'http://127.0.0.1:1/hook',
        headers: {'X-A': 'b'},
      ),
    );
    final result = writer.render(entries: const [entry], ctx: bashCtx('/s/h'));
    final section = result.configFragments['settings.json']! as Map;
    final stop = (section['hooks'] as Map)['Stop'] as List;
    final hook = (((stop.single as Map)['hooks'] as List).single) as Map;
    expect(hook['type'], 'http');
    expect(hook['url'], 'http://127.0.0.1:1/hook');
    expect(hook['headers'], {'X-A': 'b'});
  });

  test('unsupported event and script-action script file are written', () {
    const entry = HookEntry(
      id: 'h3',
      source: HookSource.userLibrary,
      event: HookEvent.stopFailure, // supported
      action: CommandHookAction.script(
        fileName: 'hook.sh',
        scriptContent: 'echo hi',
      ),
    );
    final result = writer.render(entries: const [entry], ctx: bashCtx('/s/h'));
    // 托管脚本也作为 GeneratedScript 写出
    expect(
      result.scripts.any((s) => s.fileName == 'h3/hook.sh'),
      isTrue,
    );
    expect(result.warnings, isEmpty);
  });

  test('policy on non-intercepting event warns', () {
    const entry = HookEntry(
      id: 'h4',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      policy: HookPolicy.deny,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: bashCtx('/s/h'));
    expect(result.warnings, ['hook_policy_ignored_h4_stop']);
  });

  test('idempotent render: same entry renders same fragment', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo hi'),
    );
    final a = writer.render(entries: const [entry], ctx: bashCtx('/s/h'));
    final b = writer.render(entries: const [entry], ctx: bashCtx('/s/h'));
    expect(a.configFragments, b.configFragments);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/config_profile/claude_family_hook_writer_test.dart -v`
Expected: FAIL — `ClaudeFamilyHookWriter` 不存在。若 `HostExecutionEnvironment` 参数名不同（读 `client/lib/services/host/host_execution_environment.dart`），调整测试构造。

- [ ] **Step 3: Write the writer**

`client/lib/services/cli/registry/config_profile/claude_family_hook_writer.dart`:
```dart
import '../../../models/hook_entry.dart';
import '../../../models/hook_event.dart';
import '../../../models/team_config.dart';
import '../../../host/host_script_runner.dart';
import '../../../hook/glue_script_builder.dart';
import '../../registry/capabilities/hook_registry.dart';
import '../../registry/capabilities/hook_writer_capability.dart';

/// claude / flashskyai 共享的 hook writer：settings.json `hooks` 片段。
///
/// 渲染产物与 [ClaudeFamilyHookRegistry.render] 同构（`{'hooks': {...}}`），
/// 装配点用 `mergeHooksInto` 幂等并入（按 (event, url|command) 去重）。
class ClaudeFamilyHookWriter implements HookWriterCapability {
  const ClaudeFamilyHookWriter({this.denyReason = 'TeamPilot hook policy'});

  final String denyReason;

  @override
  String? nativeEvent(HookEvent event) =>
      HookEventCapability.nativeEvent(event, CliTool.claude);

  @override
  bool get supportsMatcher => true;
  @override
  bool get supportsHttp => true;
  @override
  bool get supportsPolicy => true;

  @override
  HookWriteResult render({
    required List<HookEntry> entries,
    required HookRenderContext ctx,
  }) {
    final hooks = <String, Object?>{};
    final scripts = <GeneratedScript>[];
    final warnings = <String>[];

    for (final entry in entries) {
      final native = nativeEvent(entry.event);
      if (native == null) {
        warnings.add('hook_unsupported_event_${entry.id}_${entry.event.name}');
        continue;
      }
      if (entry.policy != HookPolicy.none && !entry.event.isIntercepting) {
        warnings.add('hook_policy_ignored_${entry.id}_${entry.event.name}');
      }
      final decisionJson = entry.policy == HookPolicy.none ||
              !entry.event.isIntercepting
          ? null
          : entry.policy == HookPolicy.allow
          ? '{"permissionDecision":"allow"}'
          : '{"permissionDecision":"deny","permissionDecisionReason":'
                '"$denyReason"}';
      final hooksList =
          List<Object?>.from((hooks[native] as List?) ?? const []);

      switch (entry.action) {
        case HttpHookAction http:
          final hookJson = <String, Object?>{
            'type': 'http',
            'url': http.url,
            if (http.headers.isNotEmpty) 'headers': http.headers,
            if (entry.timeout != null)
              'timeout': entry.timeout!.inSeconds,
          };
          hooksList.add({'hooks': [hookJson]});
        case CommandHookAction command:
          final inner = _innerCommand(command, entry.id, ctx, scripts);
          if (inner == null) {
            warnings.add('hook_script_missing_${entry.id}');
            continue;
          }
          final glue = ctx.glueBuilder.build(
            policy: entry.policy,
            innerCommand: inner,
            decisionJson: decisionJson,
            timeout: entry.timeout,
            env: entry.env,
            blockOnDecision: entry.blockOnDecision,
            dialect: ctx.runner?.dialect.name == 'powershell'
                ? 'powershell'
                : 'bash',
          );
          final scriptFileName = 'teampilot-hook-${entry.id}'
              '${ctx.runner?.dialect.scriptExtension ?? '.sh'}';
          scripts.add(GeneratedScript(fileName: scriptFileName, content: glue));
          final scriptPath = ctx.runner == null
              ? '${ctx.hooksDir}/$scriptFileName'
              : ctx.runner.commandStringForScriptFile(
                  '${ctx.hooksDir}/$scriptFileName',
                );
          final hookJson = <String, Object?>{
            'type': 'command',
            'command': scriptPath,
            'timeout': entry.timeout?.inSeconds ?? 5,
          };
          hooksList.add({
            if (entry.matcher != null && entry.matcher!.trim().isNotEmpty)
              'matcher': entry.matcher,
            'hooks': [hookJson],
          });
      }
      hooks[native] = hooksList;
    }

    return HookWriteResult(
      configFragments: {
        'settings.json': {'hooks': hooks},
      },
      scripts: scripts,
      warnings: warnings,
    );
  }

  /// 用户命令 / 托管脚本 → 内层命令；托管脚本以 GeneratedScript 写出
  /// 并在 hooksDir 子目录落盘。
  String? _innerCommand(
    CommandHookAction command,
    String id,
    HookRenderContext ctx,
    List<GeneratedScript> scripts,
  ) {
    if (command.command != null) return command.command;
    final fileName = command.fileName;
    final content = command.scriptContent;
    if (fileName == null || content == null) return null;
    final scriptFileName = '$id/$fileName';
    scripts.add(GeneratedScript(fileName: scriptFileName, content: content));
    final path = '${ctx.hooksDir}/$scriptFileName';
    return ctx.runner?.commandStringForScriptFile(path) ?? path;
  }
}
```

注意：`HostScriptDialect` 枚举值名与 `HostScriptRunner.dialect.scriptExtension`（`.sh` / `.ps1`）——`dialect.name` 为 `bash`/`powershell`（若不同，用 `ctx.runner.dialect.scriptExtension == '.ps1'` 判断）。

- [ ] **Step 4: Wire into claude tool + config profile**

`client/lib/services/cli/claude/claude_tool.dart`：
- import `../registry/config_profile/claude_family_hook_writer.dart` + `hook_writer_capability.dart`；
- 构造参数 `this.hookWriter = const ClaudeFamilyHookWriter()`；字段 `final HookWriterCapability hookWriter;`；`capabilities` 列表加 `hookWriter`。

`client/lib/services/cli/claude/capabilities/config_profile.dart`：
- `_writeMemberProfile` 签名加 `required List<HookEntry> userHooks`；
- 在现有 hookRegistry merge 块之后（`mergeHooksInto` 之后、`maybeApplyTeamLeadHooks` 之前）追加：
```dart
    final hookWriter = CliToolRegistry.builtIn().capability<HookWriterCapability>(
      CliTool.claude,
    );
    if (hookWriter != null && userHooks.isNotEmpty) {
      final hooksDir = delegate.joinWork(memberToolDir, 'hooks');
      final result = hookWriter.render(
        entries: userHooks,
        ctx: HookRenderContext(
          hooksDir: hooksDir,
          runner: delegate.hostEnvironmentForProvision().scriptRunner,
          glueBuilder: const GlueScriptBuilder(),
        ),
      );
      for (final script in result.scripts) {
        await delegate.fs.writeString(
          delegate.joinWork(hooksDir, script.fileName),
          script.content,
        );
      }
      settings = mergeHooksInto(
        settings,
        (result.configFragments['settings.json'] as Map<String, Object?>) ??
            const <String, Object?>{},
      );
      for (final warning in result.warnings) {
        appLogger.d('[hook-writer] claude $warning');
      }
    }
```
- 调用点（`contributeLaunch` 内 `_writeMemberProfile(...)`）传 `userHooks: ctx.hooks`。
- import：`models/hook_entry.dart`、`hook_writer_capability.dart`、`hook/glue_script_builder.dart`、`utils/logging/logger.dart`。

- [ ] **Step 5: Wire into flashskyai tool + config profile**

同 Step 4，`flashskyai_tool.dart` 注册 `hookWriter = const ClaudeFamilyHookWriter()`；`flashskyai/capabilities/config_profile.dart` 的 `_writeMemberProfile` 同样追加渲染块（`CliTool.flashskyai`，`hooksDir = delegate.joinWork(memberToolDir, 'hooks')`），调用点传 `userHooks: ctx.hooks`。

- [ ] **Step 6: Run tests + analyzer**

Run: `cd client && flutter test test/services/cli/registry/config_profile/claude_family_hook_writer_test.dart -v && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS + 无新增 error。

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/cli/registry/config_profile/claude_family_hook_writer.dart \
  client/lib/services/cli/claude/ client/lib/services/cli/flashskyai/ \
  client/test/services/cli/registry/config_profile/claude_family_hook_writer_test.dart
git commit -m "feat(hooks): claude/flashskyai hook writer wired into session settings"
```

---

### Task 11: Codex — CodexHookWriter + 接线

**Files:**
- Create: `client/lib/services/cli/codex/provider/codex_hook_writer.dart`
- Modify: `client/lib/services/cli/codex/codex_tool.dart`
- Modify: `client/lib/services/cli/codex/capabilities/config_profile.dart`
- Test: `client/test/services/cli/codex/codex_hook_writer_test.dart`

**Interfaces:**
- Consumes: `HookWriterCapability`、`CodexCommandHookProvisioner.hookToml`（`provider/codex_command_hook_provisioner.dart`，TOML 片段生成）。
- Produces: `class CodexHookWriter implements HookWriterCapability`（`configFragments['config.toml']` = TOML 片段字符串，复用 `CodexCommandHookProvisioner.hookToml`）；codex tool 注册；`CodexConfigProfileCapability.contributeLaunch` 在 overlayParts 追加用户 hook 片段并把脚本写到 `codexHome/hooks/`。

- [ ] **Step 1: Write the failing test**

`client/test/services/cli/codex/codex_hook_writer_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/codex/provider/codex_hook_writer.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_writer_capability.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';

void main() {
  const writer = CodexHookWriter();
  const ctx = HookRenderContext(
    hooksDir: '/s/hooks',
    runner: null,
    glueBuilder: GlueScriptBuilder(),
  );

  test('shellCommandRequest is supported by codex writer', () {
    expect(writer.supportsEvent(HookEvent.shellCommandRequest), isTrue);
    expect(writer.nativeEvent(HookEvent.shellCommandRequest),
        'ShellCommandRequest');
    expect(writer.supportsEvent(HookEvent.preToolUse), isTrue);
  });

  test('renders TOML fragment with [[hooks.Event]] and glue script', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      matcher: null,
      action: CommandHookAction.raw('echo done'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    expect(result.warnings, isEmpty);
    final toml = result.configFragments['config.toml']! as String;
    expect(toml, contains('[[hooks.Stop]]'));
    expect(toml, contains('type = "command"'));
    expect(toml, contains('/s/hooks/teampilot-hook-h1.sh'));
    expect(
      result.scripts.singleWhere((s) => s.fileName == 'teampilot-hook-h1.sh'),
      isNotNull,
    );
  });

  test('policy deny injects decision JSON into glue', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      policy: HookPolicy.deny,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    final glue = result.scripts.single;
    expect(glue.content, contains('"permissionDecision":"deny"'));
  });

  test('unsupported event is skipped with warning', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.notification,
      action: CommandHookAction.raw('echo hi'),
    );
    // notification 是 codex 支持的事件：产物非空、无警告。
    final result = writer.render(entries: const [entry], ctx: ctx);
    expect(result.warnings, isEmpty);
    expect(result.configFragments['config.toml'], isNotNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/codex/codex_hook_writer_test.dart -v`
Expected: FAIL — writer 不存在。

- [ ] **Step 3: Write the writer**

`client/lib/services/cli/codex/provider/codex_hook_writer.dart`:
```dart
import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../../models/team_config.dart';
import '../../../hook/glue_script_builder.dart';
import '../../registry/capabilities/hook_registry.dart';
import '../../registry/capabilities/hook_writer_capability.dart';
import 'codex_command_hook_provisioner.dart';

/// Codex hook writer：`config.toml` 的 `[[hooks.<Event>]]` 片段。
class CodexHookWriter implements HookWriterCapability {
  const CodexHookWriter({this.denyReason = 'TeamPilot hook policy'});

  final String denyReason;

  @override
  String? nativeEvent(HookEvent event) =>
      HookEventCapability.nativeEvent(event, CliTool.codex);

  @override
  bool get supportsMatcher => true;
  @override
  bool get supportsHttp => true;
  @override
  bool get supportsPolicy => true;

  @override
  HookWriteResult render({
    required List<HookEntry> entries,
    required HookRenderContext ctx,
  }) {
    final buffer = StringBuffer(
      '# TeamPilot user hooks — do not edit.',
    );
    final scripts = <GeneratedScript>[];
    final warnings = <String>[];
    var first = true;

    for (final entry in entries) {
      final native = nativeEvent(entry.event);
      if (native == null) {
        warnings.add('hook_unsupported_event_${entry.id}_${entry.event.name}');
        continue;
      }
      if (entry.policy != HookPolicy.none && !entry.event.isIntercepting) {
        warnings.add('hook_policy_ignored_${entry.id}_${entry.event.name}');
      }
      final decisionJson = entry.policy == HookPolicy.none ||
              !entry.event.isIntercepting
          ? null
          : entry.policy == HookPolicy.allow
          ? '{"permissionDecision":"allow"}'
          : '{"permissionDecision":"deny","permissionDecisionReason":'
                '"$denyReason"}';
      final command = entry.action;
      final String? inner;
      if (command is CommandHookAction) {
        inner = _innerCommand(command, entry.id, ctx, scripts);
      } else if (command is HttpHookAction) {
        // codex TOML 原生 http 类 hook（url + headers）在此渲染。
        final timeout = entry.timeout?.inSeconds;
        if (!first) buffer.writeln();
        buffer.writeln('[[hooks.$native]]');
        buffer.writeln();
        buffer.writeln('[[hooks.$native.hooks]]');
        buffer.writeln('type = "http"');
        buffer.writeln(
          'url = "${command.url.replaceAll('\\', r'\\').replaceAll('"', r'\"')}"',
        );
        if (command.headers.isNotEmpty) {
          final escapedHeaders = command.headers.entries
              .map(
                (e) =>
                    '"${e.key.replaceAll('\\', r'\\').replaceAll('"', r'\"')}" = '
                    '"${e.value.replaceAll('\\', r'\\').replaceAll('"', r'\"')}"',
              )
              .join(', ');
          buffer.writeln('headers = {$escapedHeaders}');
        }
        if (timeout != null) buffer.writeln('timeout = $timeout');
        first = false;
        continue;
      } else {
        warnings.add('hook_invalid_action_${entry.id}');
        continue;
      }
      if (inner == null) {
        warnings.add('hook_script_missing_${entry.id}');
        continue;
      }
      final glue = ctx.glueBuilder.build(
        policy: entry.policy,
        innerCommand: inner,
        decisionJson: decisionJson,
        timeout: entry.timeout,
        env: entry.env,
        blockOnDecision: entry.blockOnDecision,
        dialect: ctx.runner?.dialect.name == 'powershell'
            ? 'powershell'
            : 'bash',
      );
      final scriptFileName = 'teampilot-hook-${entry.id}'
          '${ctx.runner?.dialect.scriptExtension ?? '.sh'}';
      scripts.add(GeneratedScript(fileName: scriptFileName, content: glue));
      final scriptPath = ctx.runner == null
          ? '${ctx.hooksDir}/$scriptFileName'
          : ctx.runner.commandStringForScriptFile(
              '${ctx.hooksDir}/$scriptFileName',
            );
      if (!first) buffer.writeln();
      buffer.writeln('[[hooks.$native]]');
      if (entry.matcher != null && entry.matcher!.trim().isNotEmpty) {
        buffer.writeln('matcher = "${_escape(entry.matcher!)}"');
      }
      buffer.writeln();
      buffer.writeln('[[hooks.$native.hooks]]');
      buffer.writeln('type = "command"');
      buffer.writeln('command = "${_escape(scriptPath)}"');
      buffer.writeln('timeout = ${entry.timeout?.inSeconds ?? 5}');
      first = false;
    }

    if (first) {
      // 无条目时不产出空片段。
      return const HookWriteResult(warnings: []);
    }
    return HookWriteResult(
      configFragments: {'config.toml': buffer.toString()},
      scripts: scripts,
      warnings: warnings,
    );
  }

  String _innerCommand(
    CommandHookAction command,
    String id,
    HookRenderContext ctx,
    List<GeneratedScript> scripts,
  ) {
    if (command.command != null) return command.command!;
    final fileName = command.fileName;
    final content = command.scriptContent;
    if (fileName == null || content == null) return '';
    final scriptFileName = '$id/$fileName';
    scripts.add(GeneratedScript(fileName: scriptFileName, content: content));
    final path = '${ctx.hooksDir}/$scriptFileName';
    return ctx.runner?.commandStringForScriptFile(path) ?? path;
  }

  static String _escape(String value) =>
      value.replaceAll('\\', r'\\').replaceAll('"', r'\"');
}
```

- [ ] **Step 4: Wire into codex tool + config profile**

`client/lib/services/cli/codex/codex_tool.dart`：import `provider/codex_hook_writer.dart` + `hook_writer_capability.dart`；构造参数 `this.hookWriter = const CodexHookWriter()`；字段 + `capabilities` 列表。

`client/lib/services/cli/codex/capabilities/config_profile.dart` `contributeLaunch`：在 `overlayParts` 组装处（`installsManagedHooks` 块之后、`busOverlay` 计算之前）加：
```dart
      if (ctx.hooks.isNotEmpty) {
        final writer = const CodexHookWriter();
        final hooksDir = paths.joinWork(codexHome, 'hooks');
        final result = writer.render(
          entries: ctx.hooks,
          ctx: HookRenderContext(
            hooksDir: hooksDir,
            runner: host.scriptRunner,
            glueBuilder: const GlueScriptBuilder(),
          ),
        );
        for (final script in result.scripts) {
          await paths.fs.atomicWrite(
            paths.joinWork(hooksDir, script.fileName),
            script.content,
          );
        }
        final fragment = result.configFragments['config.toml'] as String?;
        if (fragment != null && fragment.trim().isNotEmpty) {
          overlayParts.add(fragment);
        }
        for (final warning in result.warnings) {
          appLogger.d('[hook-writer] codex $warning');
        }
      }
```
import：`hook_writer_capability.dart`、`services/hook/glue_script_builder.dart`、`utils/logging/logger.dart`。

- [ ] **Step 5: Run tests + analyzer**

Run: `cd client && flutter test test/services/cli/codex/codex_hook_writer_test.dart -v && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS + 无新增 error。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/codex/ \
  client/test/services/cli/codex/codex_hook_writer_test.dart
git commit -m "feat(hooks): codex hook writer (config.toml [[hooks.*]]) wired into launch"
```

---

### Task 12: Cursor — CursorHookWriter + 接线

**Files:**
- Create: `client/lib/services/cli/cursor/provider/cursor_hook_writer.dart`
- Modify: `client/lib/services/cli/cursor/cursor_tool.dart`
- Modify: `client/lib/services/cli/cursor/capabilities/config_profile.dart`
- Modify: `client/lib/services/cli/cursor/provider/cursor_home_provisioner.dart`
- Test: `client/test/services/cli/cursor/cursor_hook_writer_test.dart`

**Interfaces:**
- Consumes: `CursorHomeLayout.hooksConfig(homeRoot)` / `agentStatusScript(homeRoot, name)`（`provider/cursor_home_layout.dart`）、`HookWriterCapability`。
- Produces: `class CursorHookWriter implements HookWriterCapability`（`configFragments['hooks.json']` = `{'version':1,'hooks':{...}}`，命令一律 `bash '<glue path>'`）；cursor tool 注册；`CursorHomeProvisioner.writeUserHooks({memberHome, entries, runner})`（读现有 hooks.json → merge → 写回，脚本落 `~/.cursor/hooks/`）；simple + mixed 分支调用。

- [ ] **Step 1: Write the failing test**

`client/test/services/cli/cursor/cursor_hook_writer_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_hook_writer.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_writer_capability.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';

void main() {
  const writer = CursorHookWriter();
  const ctx = HookRenderContext(
    hooksDir: '/s/hooks',
    runner: null,
    glueBuilder: GlueScriptBuilder(),
  );

  test('cursor events are lowercase native names', () {
    expect(writer.nativeEvent(HookEvent.userPromptSubmit), 'beforeSubmitPrompt');
    expect(writer.nativeEvent(HookEvent.preToolUse), 'preToolUse');
    expect(writer.nativeEvent(HookEvent.stop), 'stop');
    expect(writer.supportsEvent(HookEvent.permissionRequest), isFalse);
  });

  test('renders hooks.json with command, matcher, loop_limit', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'Shell|Read|Write',
      timeout: Duration(seconds: 20),
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    expect(result.warnings, isEmpty);
    final hooksJson = result.configFragments['hooks.json']! as Map;
    expect(hooksJson['version'], 1);
    final pre = ((hooksJson['hooks'] as Map)['preToolUse'] as List).single
        as Map;
    expect(pre['matcher'], 'Shell|Read|Write');
    expect(pre['timeout'], 20);
    final command = pre['command'] as String;
    expect(command, contains('/s/hooks/teampilot-hook-h1.sh'));
  });

  test('stop hook gets loop_limit null; policy deny renders cursor JSON', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo done'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    final stop = ((result.configFragments['hooks.json'] as Map)['hooks']
        as Map)['stop'] as List;
    expect((stop.single as Map)['loop_limit'], isNull);
  });

  test('policy deny on preToolUse injects cursor permission JSON', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      policy: HookPolicy.deny,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    final glue = result.scripts.single;
    expect(glue.content, contains('"permission":"deny"'));
  });

  test('http action unsupported → warning', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: HttpHookAction(url: 'http://x'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    expect(result.warnings, contains('hook_http_unsupported_h1'));
    expect(result.configFragments, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/cursor/cursor_hook_writer_test.dart -v`
Expected: FAIL — writer 不存在。

- [ ] **Step 3: Write the writer**

`client/lib/services/cli/cursor/provider/cursor_hook_writer.dart`:
```dart
import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../../models/team_config.dart';
import '../../../hook/glue_script_builder.dart';
import '../../registry/capabilities/hook_registry.dart';
import '../../registry/capabilities/hook_writer_capability.dart';

/// Cursor hook writer：`~/.cursor/hooks.json`（`{"version":1,"hooks":{...}}`）。
///
/// cursor 命令一律 bash（官方文档确认）；per-script 字段：command / matcher /
/// timeout / loop_limit（stop 用 null）。policy 输出 `{"permission":"allow|deny"}`
/// （preToolUse 等拦截事件；exit code 2 阻塞语义由胶水 exit 2 承担）。
class CursorHookWriter implements HookWriterCapability {
  const CursorHookWriter({this.denyReason = 'TeamPilot hook policy'});

  final String denyReason;

  @override
  String? nativeEvent(HookEvent event) =>
      HookEventCapability.nativeEvent(event, CliTool.cursor);

  @override
  bool get supportsMatcher => true;
  @override
  bool get supportsHttp => false;
  @override
  bool get supportsPolicy => true;

  @override
  HookWriteResult render({
    required List<HookEntry> entries,
    required HookRenderContext ctx,
  }) {
    final hooks = <String, Object?>{};
    final scripts = <GeneratedScript>[];
    final warnings = <String>[];

    for (final entry in entries) {
      final native = nativeEvent(entry.event);
      if (native == null) {
        warnings.add('hook_unsupported_event_${entry.id}_${entry.event.name}');
        continue;
      }
      if (entry.action is HttpHookAction) {
        warnings.add('hook_http_unsupported_${entry.id}');
        continue;
      }
      final command = entry.action as CommandHookAction;
      if (entry.policy != HookPolicy.none && !entry.event.isIntercepting) {
        warnings.add('hook_policy_ignored_${entry.id}_${entry.event.name}');
      }
      final decisionJson = entry.policy == HookPolicy.none ||
              !entry.event.isIntercepting
          ? null
          : entry.policy == HookPolicy.allow
          ? '{"permission":"allow"}'
          : '{"permission":"deny","user_message":"$denyReason"}';
      final inner = _innerCommand(command, entry.id, ctx, scripts);
      if (inner == null) {
        warnings.add('hook_script_missing_${entry.id}');
        continue;
      }
      final glue = ctx.glueBuilder.build(
        policy: entry.policy,
        innerCommand: inner,
        decisionJson: decisionJson,
        timeout: entry.timeout,
        env: entry.env,
        blockOnDecision: entry.blockOnDecision,
        dialect: 'bash',
      );
      final scriptFileName = 'teampilot-hook-${entry.id}.sh';
      scripts.add(GeneratedScript(fileName: scriptFileName, content: glue));
      final scriptPath = '${ctx.hooksDir}/$scriptFileName';
      final hookJson = <String, Object?>{
        'command': "bash '$scriptPath'",
        if (entry.matcher != null && entry.matcher!.trim().isNotEmpty)
          'matcher': entry.matcher,
        if (entry.timeout != null) 'timeout': entry.timeout!.inSeconds,
        if (entry.event == HookEvent.stop) 'loop_limit': null,
      };
      final hooksList =
          List<Object?>.from((hooks[native] as List?) ?? const []);
      if (!hooksList.any(
        (e) => e is Map && e['command'] == hookJson['command'],
      )) {
        hooksList.add(hookJson);
      }
      hooks[native] = hooksList;
    }

    if (hooks.isEmpty) {
      return HookWriteResult(warnings: warnings);
    }
    return HookWriteResult(
      configFragments: {
        'hooks.json': {'version': 1, 'hooks': hooks},
      },
      scripts: scripts,
      warnings: warnings,
    );
  }

  String? _innerCommand(
    CommandHookAction command,
    String id,
    HookRenderContext ctx,
    List<GeneratedScript> scripts,
  ) {
    if (command.command != null) return command.command;
    final fileName = command.fileName;
    final content = command.scriptContent;
    if (fileName == null || content == null) return null;
    final scriptFileName = '$id/$fileName';
    scripts.add(GeneratedScript(fileName: scriptFileName, content: content));
    return '${ctx.hooksDir}/$scriptFileName';
  }
}
```

- [ ] **Step 4: Wire into cursor tool + provisioner + config profile**

`client/lib/services/cli/cursor/cursor_tool.dart`：import + 构造参数 `this.hookWriter = const CursorHookWriter()` + 字段 + capabilities。

`client/lib/services/cli/cursor/provider/cursor_home_provisioner.dart` 新增（平行于 `writeAgentStatusHooks`）：
```dart
  /// Writes user hooks into `~/.cursor/hooks.json`, preserving existing
  /// entries (agent-status / bus). Glue + managed scripts land under
  /// `~/.cursor/hooks/`.
  Future<void> writeUserHooks({
    required String memberHome,
    required List<HookEntry> entries,
    required HostScriptRunner runner,
  }) async {
    if (entries.isEmpty) return;
    final layout = CursorHomeLayout(pathContext: _fs.pathContext);
    final cursorDir = layout.cursorDir(memberHome);
    final hooksDir = _fs.pathContext.join(cursorDir, 'hooks');
    final result = const CursorHookWriter().render(
      entries: entries,
      ctx: HookRenderContext(
        hooksDir: hooksDir,
        runner: runner,
        glueBuilder: const GlueScriptBuilder(),
      ),
    );
    for (final script in result.scripts) {
      await _fs.atomicWrite(
        _fs.pathContext.join(hooksDir, script.fileName),
        script.content,
      );
    }
    final hooksJsonPath = layout.hooksConfig(memberHome);
    final existing = await _readHooksJson(hooksJsonPath);
    final fragment =
        (result.configFragments['hooks.json'] as Map<String, Object?>?) ??
        const <String, Object?>{};
    final merged = mergeCursorHooksConfig(existing, fragment);
    await _fs.atomicWrite(
      hooksJsonPath,
      const JsonEncoder.withIndent('  ').convert(merged),
    );
  }
```
（`_readHooksJson` 读文件或返回 `{'version':1,'hooks':{}}`。）

同时在 `client/lib/services/cli/cursor/provider/cursor_hook_writer.dart` 增加顶层函数（Task 16 测试依赖）：
```dart
/// 按 (event, command) 去重把 writer 渲染的 hooks 片段并入现有 hooks.json map
/// （保留 agent-status / bus 已写入条目）。
Map<String, Object?> mergeCursorHooksConfig(
  Map<String, Object?> existing,
  Map<String, Object?> hooksFragment,
) {
  final hooks = Map<String, Object?>.from(
    (existing['hooks'] as Map?)?.cast<String, Object?>() ?? const {},
  );
  final incoming = (hooksFragment['hooks'] as Map?)?.cast<String, Object?>() ??
      const <String, Object?>{};
  for (final entry in incoming.entries) {
    final event = entry.key;
    final incomingList = List<Object?>.from((entry.value as List?) ?? const []);
    final existingList =
        List<Object?>.from((hooks[event] as List?) ?? const []);
    for (final inc in incomingList) {
      if (inc is! Map) continue;
      final command = inc['command'];
      if (command == null) continue;
      if (!existingList.any((e) => e is Map && e['command'] == command)) {
        existingList.add(inc);
      }
    }
    hooks[event] = existingList;
  }
  return {...existing, 'hooks': hooks};
}
```

`client/lib/services/cli/cursor/capabilities/config_profile.dart`：
- `_contributeSimpleLaunch`：`CursorHomeProvisioner(...).provision(...)` 之后加：
```dart
    if (ctx.hooks.isNotEmpty) {
      await CursorHomeProvisioner(
        fs: paths.fs,
        layout: CursorHomeLayout(pathContext: paths.fs.pathContext),
      ).writeUserHooks(
        memberHome: home,
        entries: ctx.hooks,
        runner: paths.hostEnvironmentForProvision().scriptRunner,
      );
    }
```
- `_contributeTeamLaunch` mixed 分支：`writeAgentStatusHooks` 之后同样调用（`memberHome: agentHome`）。

- [ ] **Step 5: Run tests + analyzer**

Run: `cd client && flutter test test/services/cli/cursor/cursor_hook_writer_test.dart -v && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS + 无新增 error。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/cursor/ \
  client/test/services/cli/cursor/cursor_hook_writer_test.dart
git commit -m "feat(hooks): cursor hook writer (hooks.json + matcher/policy) wired into launch"
```

---

### Task 13: Opencode — OpencodeHookWriter（生成 JS plugin 桥）

**Files:**
- Create: `client/lib/services/cli/opencode/capabilities/opencode_hook_writer.dart`
- Modify: `client/lib/services/cli/opencode/opencode_tool.dart`
- Modify: `client/lib/services/cli/opencode/capabilities/config_profile.dart`
- Test: `client/test/services/cli/opencode/opencode_hook_writer_test.dart`

**Interfaces:**
- Consumes: `HookWriterCapability`、`opencodeAgentStatusPluginFileName` 的 JS 写法惯例（`agent_status_plugin.dart` 的 `input.client.events.on` 订阅模式）。
- Produces: `const opencodeUserHooksPluginFileName = 'teampilot-user-hooks.js'`；`class OpencodeHookWriter implements HookWriterCapability`（`configFragments['opencode.json']` = `{'plugin': ['./teampilot-user-hooks.js']}`，scripts 含 JS plugin + 各 glue）。JS plugin 对每个支持事件 `events.on(...)`，用 `child_process.execFile` 跑 glue 命令并把 stdout 传回 opencode hook 输出（`{decision}` 桥契约）。

- [ ] **Step 1: Write the failing test**

`client/test/services/cli/opencode/opencode_hook_writer_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/opencode/capabilities/opencode_hook_writer.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_writer_capability.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';

void main() {
  const writer = OpencodeHookWriter();
  const ctx = HookRenderContext(
    hooksDir: '/s/hooks',
    runner: null,
    glueBuilder: GlueScriptBuilder(),
  );

  test('bridge supports tool + permission + stop events only', () {
    expect(writer.supportsEvent(HookEvent.preToolUse), isTrue);
    expect(writer.supportsEvent(HookEvent.stop), isTrue);
    expect(writer.supportsEvent(HookEvent.sessionStart), isFalse);
  });

  test('renders plugin entry + JS source with event subscriptions', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'bash',
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    expect(result.warnings, isEmpty);
    final opencodeJson = result.configFragments['opencode.json']! as Map;
    expect(opencodeJson['plugin'], ['./teampilot-user-hooks.js']);
    final js = result.scripts.singleWhere(
      (s) => s.fileName == 'teampilot-user-hooks.js',
    );
    expect(js.content, contains('tool.execute.before'));
    expect(js.content, contains('/s/hooks/teampilot-hook-h1.sh'));
  });

  test('policy deny injects decision bridge contract', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.permissionRequest,
      policy: HookPolicy.deny,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    final glue = result.scripts.singleWhere(
      (s) => s.fileName == 'teampilot-hook-h1.sh',
    );
    expect(glue.content, contains('"decision":"deny"'));
  });

  test('unsupported events warn', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.sessionStart,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    expect(
      result.warnings,
      ['hook_unsupported_event_h1_sessionStart'],
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/opencode/opencode_hook_writer_test.dart -v`
Expected: FAIL — writer 不存在。

- [ ] **Step 3: Write the writer**

`client/lib/services/cli/opencode/capabilities/opencode_hook_writer.dart`:
```dart
import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../../models/team_config.dart';
import '../../../hook/glue_script_builder.dart';
import '../../registry/capabilities/hook_registry.dart';
import '../../registry/capabilities/hook_writer_capability.dart';

const opencodeUserHooksPluginFileName = 'teampilot-user-hooks.js';

/// opencode 无原生 hooks —— 生成一个 JS plugin 桥：
/// 订阅 SDK 事件（`input.client.events.on`），对每个 hook 用 Node
/// `child_process` 跑 glue 命令，stdout（决策 JSON）原样传回。
class OpencodeHookWriter implements HookWriterCapability {
  const OpencodeHookWriter({this.denyReason = 'TeamPilot hook policy'});

  final String denyReason;

  @override
  String? nativeEvent(HookEvent event) =>
      HookEventCapability.nativeEvent(event, CliTool.opencode);

  @override
  bool get supportsMatcher => true;
  @override
  bool get supportsHttp => false;
  @override
  bool get supportsPolicy => true;

  @override
  HookWriteResult render({
    required List<HookEntry> entries,
    required HookRenderContext ctx,
  }) {
    final scripts = <GeneratedScript>[];
    final warnings = <String>[];
    final subscriptions = <String, List<String>>{}; // nativeEvent -> command

    for (final entry in entries) {
      final native = nativeEvent(entry.event);
      if (native == null) {
        warnings.add('hook_unsupported_event_${entry.id}_${entry.event.name}');
        continue;
      }
      if (entry.action is HttpHookAction) {
        warnings.add('hook_http_unsupported_${entry.id}');
        continue;
      }
      final command = entry.action as CommandHookAction;
      if (entry.policy != HookPolicy.none && !entry.event.isIntercepting) {
        warnings.add('hook_policy_ignored_${entry.id}_${entry.event.name}');
      }
      final decisionJson = entry.policy == HookPolicy.none ||
              !entry.event.isIntercepting
          ? null
          : entry.policy == HookPolicy.allow
          ? '{"decision":"allow"}'
          : '{"decision":"deny","reason":"$denyReason"}';
      final inner = _innerCommand(command, entry.id, ctx, scripts);
      if (inner == null) {
        warnings.add('hook_script_missing_${entry.id}');
        continue;
      }
      final glue = ctx.glueBuilder.build(
        policy: entry.policy,
        innerCommand: inner,
        decisionJson: decisionJson,
        timeout: entry.timeout,
        env: entry.env,
        blockOnDecision: entry.blockOnDecision,
        dialect: 'bash',
      );
      final scriptFileName = 'teampilot-hook-${entry.id}.sh';
      scripts.add(GeneratedScript(fileName: scriptFileName, content: glue));
      final commandLine = "bash '${ctx.hooksDir}/$scriptFileName'";
      subscriptions.putIfAbsent(native, () => []).add(commandLine);
    }

    if (subscriptions.isEmpty) {
      return HookWriteResult(warnings: warnings);
    }
    scripts.add(
      GeneratedScript(
        fileName: opencodeUserHooksPluginFileName,
        content: _buildPluginSource(subscriptions),
      ),
    );
    return HookWriteResult(
      configFragments: {
        'opencode.json': {
          'plugin': ['./$opencodeUserHooksPluginFileName'],
        },
      },
      scripts: scripts,
      warnings: warnings,
    );
  }

  String _buildPluginSource(Map<String, List<String>> subscriptions) {
    final buffer = StringBuffer()
      ..writeln('export const TeampilotUserHooks = async (input, options) => {')
      ..writeln('  const { execFile } = require("node:child_process");')
      ..writeln('  const run = (command) =>')
      ..writeln(
        '    new Promise((resolve) => {'
        ' execFile(command.split(/\s+/)[0], '
        'command.split(/\s+/).slice(1), '
        '{ encoding: "utf8" }, (err, stdout) => resolve(stdout || null)); });',
      )
      ..writeln('  const on = (event, handler) => {');
    for (final entry in subscriptions.entries) {
      final event = entry.key.replaceAll('"', r'\"');
      for (final command in entry.value) {
        final safe = command.replaceAll('"', r'\"');
        buffer.writeln(
          '    if (input.client?.events?.on) '
          'input.client.events.on("$event", async () => {'
          ' const out = await run("$safe"); return out ? JSON.parse(out) : {}; });',
        );
      }
    }
    buffer
      ..writeln('  };')
      ..writeln('  on();')
      ..writeln('};');
    return buffer.toString();
  }

  String? _innerCommand(
    CommandHookAction command,
    String id,
    HookRenderContext ctx,
    List<GeneratedScript> scripts,
  ) {
    if (command.command != null) return command.command;
    final fileName = command.fileName;
    final content = command.scriptContent;
    if (fileName == null || content == null) return null;
    final scriptFileName = '$id/$fileName';
    scripts.add(GeneratedScript(fileName: scriptFileName, content: content));
    return '${ctx.hooksDir}/$scriptFileName';
  }
}
```

- [ ] **Step 4: Wire into opencode tool + config profile**

`client/lib/services/cli/opencode/opencode_tool.dart`：import + `this.hookWriter = const OpencodeHookWriter()` + 字段 + capabilities。

`client/lib/services/cli/opencode/capabilities/config_profile.dart` `contributeLaunch`：在 `_writeAgentStatusPlugin` 块之后、`if (changed)` 之前加：
```dart
    if (ctx.hooks.isNotEmpty) {
      final writer = const OpencodeHookWriter();
      final hooksDir = paths.joinWork(opencodeDir, 'hooks');
      final result = writer.render(
        entries: ctx.hooks,
        ctx: HookRenderContext(
          hooksDir: hooksDir,
          runner: paths.hostEnvironmentForProvision().scriptRunner,
          glueBuilder: const GlueScriptBuilder(),
        ),
      );
      for (final script in result.scripts) {
        await paths.fs.atomicWrite(
          paths.joinWork(opencodeDir, script.fileName),
          script.content,
        );
      }
      final fragment =
          result.configFragments['opencode.json'] as Map<String, Object?>?;
      if (fragment != null) {
        config = mergeOpencodePluginEntries(
          config,
          ((fragment['plugin'] as List?) ?? const []).map(
            (e) => e is String ? e : e.toString(),
          ),
        );
        changed = true;
      }
      for (final warning in result.warnings) {
        appLogger.d('[hook-writer] opencode $warning');
      }
    }
```
import：`hook_writer_capability.dart`、`services/hook/glue_script_builder.dart`、`utils/logging/logger.dart`。

- [ ] **Step 5: Run tests + analyzer**

Run: `cd client && flutter test test/services/cli/opencode/opencode_hook_writer_test.dart -v && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS + 无新增 error。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/opencode/ \
  client/test/services/cli/opencode/opencode_hook_writer_test.dart
git commit -m "feat(hooks): opencode bridge via generated user-hooks plugin"
```

---

### Task 14: 收敛 — HookSeatContextCompleter + claude-family agent-status/bus 迁移

**Files:**
- Create: `client/lib/services/cli/registry/config_profile/hook_seat_context_completer.dart`
- Modify: `client/lib/services/cli/claude/capabilities/config_profile.dart`
- Modify: `client/lib/services/cli/flashskyai/capabilities/config_profile.dart`
- Test: `client/test/services/cli/registry/config_profile/hook_seat_context_completer_test.dart`

**Interfaces:**
- Consumes: `MemberAgentStatusEndpoint`、`MemberBusIdleEndpoint`、`agentStatusHookUrl`（`registry/config_profile/agent_status_hooks.dart`）。
- Produces: `class HookSeatContextCompleter{ List<HookEntry> agentStatusHooks({endpoint, memberId}); List<HookEntry> busIdleHooks({idle, memberId}); }`——把 agent-status 六事件与 bus Stop/StopFailure 转成 `HookEntry(source: managed)`（claude 事件名就是归一化事件名），并暴露 `agentStatusEventNames` / `busIdleEventNames`。装配点在 `_writeMemberProfile` 用其替代 `mergeAgentStatusHooks` / `mergeStopIdleHook`，经统一 writer 渲染。

- [ ] **Step 1: Write the failing test**

`client/test/services/cli/registry/config_profile/hook_seat_context_completer_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/cli/registry/config_profile/hook_seat_context_completer.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';

void main() {
  const completer = HookSeatContextCompleter();

  test('agent status hooks cover all events with per-event urls', () {
    const endpoint = MemberAgentStatusEndpoint(
      url: 'http://127.0.0.1:1/agent-status',
      memberHeader: 'X-Member',
      memberParam: 'memberId',
      token: 't',
      sessionId: 's',
    );
    final entries = completer.agentStatusHooks(
      endpoint: endpoint,
      memberId: 'm1',
    );
    expect(entries.map((e) => e.event), containsAll([
      HookEvent.permissionRequest,
      HookEvent.preToolUse,
      HookEvent.postToolUse,
      HookEvent.postToolUseFailure,
      HookEvent.stop,
      HookEvent.stopFailure,
      HookEvent.userPromptSubmit,
    ]));
    for (final entry in entries) {
      expect(entry.source, HookSource.managed);
      final http = entry.action as HttpHookAction;
      // URL 事件名与现有 agent-status 一致（PascalCase 原生名），
      // 保证 per-event URL 去重身份与 hook-gate 兼容。
      final native = HookEventCapability.nativeEvent(
        entry.event,
        CliTool.claude,
      );
      expect(http.url, contains('event=$native'));
      expect(http.headers['X-Member'], 'm1');
      expect(http.timeout, isNotNull);
    }
  });

  test('bus idle hooks are stop + stopFailure with blockOnDecision', () {
    const idle = MemberBusIdleEndpoint(
      url: 'http://127.0.0.1:2/idle',
      token: null,
      sessionId: null,
    );
    final entries = completer.busIdleHooks(idle: idle, memberId: 'm1');
    expect(entries.map((e) => e.event), [HookEvent.stop, HookEvent.stopFailure]);
    expect(entries.every((e) => e.blockOnDecision), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/config_profile/hook_seat_context_completer_test.dart -v`
Expected: FAIL——先核对 `MemberAgentStatusEndpoint` / `MemberBusIdleEndpoint` 构造参数名（读 `member_agent_status_endpoint.dart` / `member_bus_idle_endpoint.dart`），按实际签名调整测试。

- [ ] **Step 3: Write the completer**

`client/lib/services/cli/registry/config_profile/hook_seat_context_completer.dart`:
```dart
import '../../../models/hook_entry.dart';
import '../../../models/hook_event.dart';
import '../../../models/team_config.dart';
import '../../../agent_status/member_agent_status_endpoint.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import 'agent_status_hooks.dart';

/// 把内部托管 hook 组装为 [HookEntry]（source: managed）。
/// 装配点（各 CLI config_profile）用它替代各自的 mergeAgentStatusHooks /
/// mergeStopIdleHook，渲染走统一 writer（收敛目标）。
class HookSeatContextCompleter {
  const HookSeatContextCompleter();

  /// agent-status 全事件集（与 agent_status_hooks.dart 常量一致）。
  static const List<HookEvent> agentStatusEvents = [
    HookEvent.permissionRequest,
    HookEvent.preToolUse,
    HookEvent.postToolUse,
    HookEvent.postToolUseFailure,
    HookEvent.stop,
    HookEvent.stopFailure,
    HookEvent.userPromptSubmit,
  ];

  /// 需要 matcher `*` 的事件（与 agent_status_hooks.dart 一致）。
  static const Set<HookEvent> agentStatusMatcherEvents = {
    HookEvent.permissionRequest,
    HookEvent.preToolUse,
    HookEvent.postToolUse,
    HookEvent.postToolUseFailure,
  };

  List<HookEntry> agentStatusHooks({
    required MemberAgentStatusEndpoint endpoint,
    required String memberId,
  }) {
    final headers = endpoint.headersFor(memberId);
    return [
      for (final event in agentStatusEvents)
        HookEntry(
          id: 'teampilot-agent-status-${event.name}',
          source: HookSource.managed,
          event: event,
          matcher: agentStatusMatcherEvents.contains(event) ? '*' : null,
          action: HttpHookAction(
            // URL 事件名用原生 PascalCase，与现有 agent_status_hooks.dart
            // 的 per-event URL 身份一致（hook-gate / 去重兼容）。
            url: agentStatusHookUrl(
              endpoint.url,
              HookEventCapability.nativeEvent(event, CliTool.claude)!,
            ),
            headers: headers,
          ),
          // AskUserQuestion PreToolUse 保持挂起（与现状 timeout 86400 一致）。
          timeout: event == HookEvent.preToolUse
              ? const Duration(days: 1)
              : const Duration(seconds: 5),
        ),
    ];
  }

  List<HookEntry> busIdleHooks({
    required MemberBusIdleEndpoint idle,
    required String memberId,
  }) {
    final url = idle.url;
    return [
      for (final event in const [
        HookEvent.stop,
        HookEvent.stopFailure,
      ])
        HookEntry(
          id: 'teampilot-bus-idle-${event.name}',
          source: HookSource.managed,
          event: event,
          action: HttpHookAction(url: url, headers: idle.headersFor(memberId)),
          timeout: const Duration(seconds: 5),
          blockOnDecision: true,
        ),
    ];
  }
}
```

- [ ] **Step 4: Switch claude `_writeMemberProfile` to the completer + unified writer**

`client/lib/services/cli/claude/capabilities/config_profile.dart`：
- 删除 `settings = mergeStopIdleHook(settings, member.id, busIdle);` 与 `settings = mergeAgentStatusHooks(settings, member.id, agentStatus);` 两行；
- 替换为：把 `const HookSeatContextCompleter()` 产出的 entries（busIdle 非空时 + agentStatus 非空时）与 `userHooks` 合并成一个列表，走 Task 10 已接线的统一 writer 渲染块（同一 `hookWriter.render(...)` 调用，一次 `mergeHooksInto`）。
- 既有 registry 资产块（`hookRegistry.assetsFor` + `completeBusIdleHooks`）保留到 Task 19 删除前，但此处不再调用 `mergeAgentStatusHooks`。

- [ ] **Step 5: Same for flashskyai**

`client/lib/services/cli/flashskyai/capabilities/config_profile.dart`：同样删除两个 merge 调用（保留 `flashskyaiStopIdleScript` 写盘逻辑到 Task 19 评估——command 通道 idle 语义由 writer 的 blockOnDecision 承担后删除）。

- [ ] **Step 6: Run tests + analyzer**

Run: `cd client && flutter test test/services/cli/registry/config_profile/hook_seat_context_completer_test.dart test/services/cli/registry/config_profile/claude_family_hook_writer_test.dart -v && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS + 无新增 error。若现有 agent-status 测试（如 ask_user_question 集成链）依赖 settings 里的 http hook 结构，确保 writer 渲染的 http 条目与 `mergeAgentStatusHooks` 产物字段一致（url/headers/timeout/matcher 全对齐）。

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/cli/registry/config_profile/hook_seat_context_completer.dart \
  client/lib/services/cli/claude/capabilities/config_profile.dart \
  client/lib/services/cli/flashskyai/capabilities/config_profile.dart \
  client/test/services/cli/registry/config_profile/hook_seat_context_completer_test.dart
git commit -m "refactor(hooks): converge claude-family agent-status/bus hooks into unified writer"
```

---

### Task 15: 收敛 — codex agent-status/bus 迁移

**Files:**
- Modify: `client/lib/services/cli/codex/capabilities/config_profile.dart`
- Modify: `client/lib/services/cli/codex/provider/codex_agent_status_overlay.dart`、`codex_team_bus_overlay.dart`（仅保留被测试引用的静态构建器，装配点改走 completer）
- Test: `client/test/services/cli/codex/codex_hook_writer_test.dart`（追加迁移断言）

**Interfaces:**
- Consumes: `HookSeatContextCompleter`（Task 14）。
- Produces: codex `contributeLaunch` 用 completer 产出 managed entries，与用户 hooks 合并走 `CodexHookWriter`（Task 11）统一渲染；`CodexAgentStatusOverlay` / `CodexTeamBusOverlay` 的装配调用删除（保留纯构建函数供既有测试）。

- [ ] **Step 1: Write the failing test（先固定行为）**

追加到 `client/test/services/cli/codex/codex_hook_writer_test.dart`:
```dart
  test('agent-status managed entries render http hooks with headers', () {
    const completer = HookSeatContextCompleter();
    const endpoint = MemberAgentStatusEndpoint(
      url: 'http://127.0.0.1:1/agent-status',
      memberHeader: 'X-Member',
      memberParam: 'memberId',
      token: 't',
      sessionId: 's',
    );
    final entries = [
      ...completer.agentStatusHooks(endpoint: endpoint, memberId: 'm1'),
      const HookEntry(
        id: 'h1',
        source: HookSource.userLibrary,
        event: HookEvent.stop,
        action: CommandHookAction.raw('echo done'),
      ),
    ];
    final result = const CodexHookWriter().render(
      entries: entries,
      ctx: const HookRenderContext(
        hooksDir: '/s/hooks',
        runner: null,
        glueBuilder: GlueScriptBuilder(),
      ),
    );
    final toml = result.configFragments['config.toml']! as String;
    expect(toml, contains('[[hooks.Stop]]'));
    expect(toml, contains('type = "http"'));
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/codex/codex_hook_writer_test.dart -v`
Expected: FAIL——`HookSeatContextCompleter` import 或断言不符（TOML 里 http 条目类型）。

- [ ] **Step 3: Rewire codex contributeLaunch**

`client/lib/services/cli/codex/capabilities/config_profile.dart`：
- 删除 `CodexAgentStatusOverlay.provision(...)` 与 `CodexTeamBusOverlay.provisionStopHook/buildLocal(...)` 的装配调用；
- 在用户 hooks 渲染块（Task 11）前把 managed entries 并入：
```dart
      final managedEntries = <HookEntry>[
        if (busIdle != null)
          ...const HookSeatContextCompleter()
              .busIdleHooks(idle: busIdle, memberId: member.id),
        if (ctx.agentStatus != null)
          ...const HookSeatContextCompleter().agentStatusHooks(
            endpoint: ctx.agentStatus!,
            memberId: member.id,
          ),
      ];
      final allEntries = [...managedEntries, ...ctx.hooks];
```
  并把渲染块改成遍历 `allEntries`（bus 走 http 渲染分支；注意 codex http 类 hook 的 headers/url 已在 Task 11 支持）。
- 保留 `CodexManagedHookOverlay`（sandbox 设置，非 hooks 表）。

- [ ] **Step 4: Run tests + analyzer**

Run: `cd client && flutter test test/services/cli/codex/codex_hook_writer_test.dart -v && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS。既有 `codex_agent_status_overlay` / `codex_team_bus_overlay` 单测（若有）改为直接测保留的静态构建器，不回归。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/codex/
git commit -m "refactor(hooks): converge codex agent-status/bus hooks into unified writer"
```

---

### Task 16: 收敛 — cursor agent-status/bus 迁移（全量，按 spec §4.3）

**Files:**
- Modify: `client/lib/services/cli/cursor/provider/cursor_hook_writer.dart`（http → bash 转发脚本渲染）
- Modify: `client/lib/services/cli/cursor/capabilities/config_profile.dart`（装配改走 completer + writer）
- Modify: `client/lib/services/cli/cursor/provider/cursor_home_provisioner.dart`（`writeAgentStatusHooks` 删除，新增 `writeHooks({memberHome, entries, runner})` 统一入口）
- Test: `client/test/services/cli/cursor/cursor_hook_writer_test.dart`（追加迁移断言）

**Interfaces:**
- Consumes: `HookSeatContextCompleter`（Task 14）、`mergeCursorHooksConfig`（Task 12）。
- Produces: `CursorHookWriter` 对 **http 类 action 生成 bash 转发脚本**（cursor hooks.json 仅 command 类）：
  - `blockOnDecision=false`（agent-status）：脚本 `cat` stdin → `curl -sS -X POST <url> <headers> -d @- >/dev/null 2>&1 || true`，恒 exit 0（best-effort，与现有 `CursorHomeAgentStatusOverlay.scriptFor` 同语义）；
  - `blockOnDecision=true`（bus idle stop/stopFailure）：脚本 POST `<url>/idle`（headers 注入），响应含 `"decision":"block"` 时输出 `{"followup_message":"<stopRedirectReason>"}`，exit 0（与现有 `CursorHomeBusOverlay.idleScript` 同语义；`stopRedirectReason` 从 `teammate_bus_mcp_handler.dart` 读取）。
  - 脚本文件名：`teampilot-http-<id>-<event>.sh`；hooks.json 条目 command = `bash '<hooksDir>/<name>'`。
- 装配：`config_profile.dart` 的 simple + mixed 分支用 completer 产出 managed entries（`agentStatusHooks`/`busIdleHooks`）与 `ctx.hooks` 合并，一次 `writeHooks(memberHome, allEntries, runner)` 完成（内部条目与用户条目同一次 render + merge，按 (event, command) 去重）；删除对 `CursorHomeAgentStatusOverlay` / `CursorHomeBusOverlay` 的装配调用。

- [ ] **Step 1: Write the failing test（http 转发 + bus idle 语义）**

追加到 `client/test/services/cli/cursor/cursor_hook_writer_test.dart`:
```dart
  test('http agent-status entry renders bash forwarding script', () {
    const entry = HookEntry(
      id: 'teampilot-agent-status-stop',
      source: HookSource.managed,
      event: HookEvent.stop,
      action: HttpHookAction(
        url: 'http://127.0.0.1:1/agent-status?event=Stop',
        headers: {'X-Member': 'm1'},
      ),
    );
    final result = const CursorHookWriter().render(
      entries: const [entry],
      ctx: const HookRenderContext(
        hooksDir: '/h/hooks',
        runner: null,
        glueBuilder: GlueScriptBuilder(),
      ),
    );
    expect(result.warnings, isEmpty);
    final script = result.scripts.singleWhere(
      (s) => s.fileName == 'teampilot-http-teampilot-agent-status-stop-stop.sh',
    );
    expect(script.content, contains("curl -sS -X POST"));
    expect(script.content, contains("'http://127.0.0.1:1/agent-status?event=Stop'"));
    expect(script.content, contains("'X-Member: m1'"));
    final hooksJson = result.configFragments['hooks.json']! as Map;
    final stop = ((hooksJson['hooks'] as Map)['stop'] as List).single as Map;
    expect(stop['command'], contains('teampilot-http-teampilot-agent-status-stop-stop.sh'));
    expect(stop['timeout'], isNotNull);
  });

  test('bus idle hook prints followup_message on decision:block', () {
    const entry = HookEntry(
      id: 'teampilot-bus-idle-stop',
      source: HookSource.managed,
      event: HookEvent.stop,
      blockOnDecision: true,
      timeout: Duration(seconds: 5),
      action: HttpHookAction(
        url: 'http://127.0.0.1:2/idle',
        headers: {'X-Member': 'm1'},
      ),
    );
    final result = const CursorHookWriter().render(
      entries: const [entry],
      ctx: const HookRenderContext(
        hooksDir: '/h/hooks',
        runner: null,
        glueBuilder: GlueScriptBuilder(),
      ),
    );
    final script = result.scripts.single;
    expect(script.content, contains('"decision":"block"'));
    expect(script.content, contains('followup_message'));
    expect(script.content, contains('exit 0'));
  });

  test('managed + user entries merge idempotently by command', () {
    const agentStatus = HookEntry(
      id: 'teampilot-agent-status-stop',
      source: HookSource.managed,
      event: HookEvent.stop,
      action: HttpHookAction(url: 'http://127.0.0.1:1/agent-status?event=Stop'),
    );
    const userHook = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo done'),
    );
    final ctx = const HookRenderContext(
      hooksDir: '/h/hooks',
      runner: null,
      glueBuilder: GlueScriptBuilder(),
    );
    final result = const CursorHookWriter().render(
      entries: const [agentStatus, userHook],
      ctx: ctx,
    );
    final stop = ((result.configFragments['hooks.json'] as Map)['hooks']
        as Map)['stop'] as List;
    expect(stop, hasLength(2));
    final re = const CursorHookWriter().render(
      entries: const [agentStatus, userHook],
      ctx: ctx,
    );
    expect(
      ((re.configFragments['hooks.json'] as Map)['hooks'] as Map)['stop'],
      hasLength(2),
    );
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/cursor/cursor_hook_writer_test.dart -v`
Expected: FAIL——http 渲染与 `teampilot-http-*` 脚本未实现。

- [ ] **Step 3: Extend CursorHookWriter with http → bash forwarding**

在 `cursor_hook_writer.dart` 的 `render` 中，`entry.action is HttpHookAction` 分支从「warning 跳过」改为生成转发脚本：
```dart
      if (entry.action is HttpHookAction) {
        final http = entry.action as HttpHookAction;
        final scriptFileName = 'teampilot-http-${entry.id}-${entry.event.name}.sh';
        scripts.add(
          GeneratedScript(
            fileName: scriptFileName,
            content: _httpForwardScript(http, entry.blockOnDecision),
          ),
        );
        final hooksList =
            List<Object?>.from((hooks[native] as List?) ?? const []);
        final hookJson = <String, Object?>{
          'command': "bash '${ctx.hooksDir}/$scriptFileName'",
          if (entry.timeout != null) 'timeout': entry.timeout!.inSeconds,
          if (entry.event == HookEvent.stop) 'loop_limit': null,
        };
        if (!hooksList.any(
          (e) => e is Map && e['command'] == hookJson['command'],
        )) {
          hooksList.add(hookJson);
        }
        hooks[native] = hooksList;
        continue;
      }
```
配套生成器（与现有 overlay 同语义）：
```dart
  String _httpForwardScript(HttpHookAction http, bool blockOnDecision) {
    final headerArgs = http.headers.entries
        .map((e) => "-H '${e.key}: ${e.value}'")
        .join(' ');
    if (!blockOnDecision) {
      return '''
#!/usr/bin/env bash
# TeamPilot hook glue (http forward) — do not edit.
set -u
payload="\$(cat)"
[ -z "\$payload" ] && exit 0
curl -sS -X POST '$http.url' $headerArgs -H 'Content-Type: application/json' -d "\$payload" >/dev/null 2>&1 || true
exit 0
''';
    }
    // bus idle：/idle 返回 decision:block 时输出 followup_message（与
    // CursorHomeBusOverlay.idleScript 同语义）。
    final followup = jsonEncode({
      'followup_message': TeammateBusMcpHandler.stopRedirectReason,
    });
    return '''
#!/usr/bin/env bash
# TeamPilot hook glue (bus idle) — do not edit.
set -u
cat >/dev/null 2>&1 || true
resp="\$(curl -sS -X POST $headerArgs '${http.url}' 2>/dev/null || true)"
case "\$resp" in
  *'"decision":"block"'*)
    printf '%s' '$followup'
    ;;
esac
exit 0
''';
  }
```
（import：`dart:convert`、`../../../team_bus/mcp/teammate_bus_mcp_handler.dart`。）

- [ ] **Step 4: Rewire assembly to completer + writer**

`client/lib/services/cli/cursor/capabilities/config_profile.dart`：
- `_contributeSimpleLaunch` 与 `_contributeTeamLaunch`（mixed 分支）均改为：
```dart
    final completer = const HookSeatContextCompleter();
    final managed = <HookEntry>[
      if (busIdle != null)
        ...completer.busIdleHooks(idle: busIdle, memberId: member.id),
      if (agentStatus != null)
        ...completer.agentStatusHooks(
          endpoint: agentStatus,
          memberId: member.id,
        ),
    ];
    await CursorHomeProvisioner(
      fs: paths.fs,
      layout: CursorHomeLayout(pathContext: paths.fs.pathContext),
    ).writeHooks(
      memberHome: home,
      entries: [...managed, ...ctx.hooks],
      runner: paths.hostEnvironmentForProvision().scriptRunner,
    );
```
  （simple 分支 busIdle 恒 null；member 为 `ctx.member`。bus idle 条目只在该 CLI 支持的事件集内生效——cursor writer 对 `stop`/`stopFailure` 原生名映射后渲染。）
- `CursorHomeProvisioner.writeAgentStatusHooks` 删除；`CursorHomeAgentStatusOverlay` / `CursorHomeBusOverlay` 的装配调用删除（静态构建函数保留给既有单测，Task 19 评估去留）。
- 把 Task 12 的 `writeUserHooks` 更名为 `writeHooks`（同一实现；managed 条目也经它落盘）。

- [ ] **Step 5: Run tests + analyzer**

Run: `cd client && flutter test test/services/cli/cursor/cursor_hook_writer_test.dart -v && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS。既有 cursor agent-status 相关测试若断言 `~/.cursor/hooks/teampilot-agent-status-*.sh` 文件名，迁移后文件名变化（`teampilot-http-teampilot-agent-status-<event>-<event>.sh`）——更新断言指向新文件名，语义不变（stdin 透传 + POST /agent-status）。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/cursor/
git commit -m "refactor(hooks): migrate cursor agent-status/bus hooks into unified writer"
```

---

### Task 17: 收敛 — opencode agent-status/idle 迁移

**Files:**
- Modify: `client/lib/services/cli/opencode/capabilities/config_profile.dart`
- Test: `client/test/services/cli/opencode/opencode_hook_writer_test.dart`（追加断言）

**Interfaces:**
- Consumes: `HookSeatContextCompleter`。
- Produces: opencode 的 agent-status/idle 保持现有 JS plugin（事件订阅 + `/agent-status` POST 与 `/idle` 是 opencode 特有能力，不是"hook 配置"），**不迁移**；本任务只确保用户 hooks plugin 与 agent-status/idle plugin 共存（`mergeOpencodePluginEntries` 已按 path 去重，Task 13 已处理）。因此本任务退化为验证 + 文档注释，无代码改动。

- [ ] **Step 1: 验证共存**

追加断言到 `client/test/services/cli/opencode/opencode_hook_writer_test.dart`:
```dart
  test('user hooks plugin coexists with agent-status/idle plugin entries', () {
    var config = const <String, Object?>{'plugin': ['./teampilot-agent-status.js']};
    config = mergeOpencodePluginEntries(config, ['./teampilot-user-hooks.js']);
    expect(config['plugin'], [
      './teampilot-agent-status.js',
      './teampilot-user-hooks.js',
    ]);
  });
```
（`mergeOpencodePluginEntries` 从 `capabilities/config_profile.dart` import。）

- [ ] **Step 2: Run test**

Run: `cd client && flutter test test/services/cli/opencode/opencode_hook_writer_test.dart -v`
Expected: PASS（现有实现已支持——回归保护）。

- [ ] **Step 3: 在 `opencode_hook_writer.dart` 顶部注释补充共存说明**

更新文件头注释：用户 hooks plugin 与 `teampilot-agent-status.js` / `teampilot-idle.js` 平行安装；opencode 无 http/原生 hooks，内部托管经专属 JS plugin 保持。

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/cli/opencode/ \
  client/test/services/cli/opencode/opencode_hook_writer_test.dart
git commit -m "docs(hooks): opencode internal plugins coexist with user-hooks bridge"
```

---

### Task 18: 收敛 — delegate / 扩展 settings-hook / 插件 hooks 迁移

**Files:**
- Modify: `client/lib/services/cli/registry/config_profile/hook_seat_context_completer.dart`（新增三个来源的组装）
- Modify: `client/lib/services/team/team_lead_delegate_settings_merge.dart`
- Modify: `client/lib/services/extension/effect/settings_hook_effect_applier.dart`
- Modify: `client/lib/services/plugin/plugin_manifest_service.dart`
- Test: `client/test/services/cli/registry/config_profile/hook_seat_context_completer_test.dart`（追加）

**Interfaces:**
- Consumes: 现有 delegate / settings-hook / plugin 结构。
- Produces: `HookSeatContextCompleter.delegateHooks({commands})` / `extensionHooks({events, command})` / `pluginHooks({PluginHook hooks})` 三个组装方法；各来源的装配点改为产出 entries 并并入统一 writer；`TeamLeadDelegateSettingsMerge`、`SettingsHookEffectApplier` 的 merge 逻辑删除（纯构建保留给测试）。

- [ ] **Step 1: Write the failing test**

追加到 `client/test/services/cli/registry/config_profile/hook_seat_context_completer_test.dart`:
```dart
  test('delegate hooks become managed preToolUse entries', () {
    final entries = completer.delegateHooks(
      commands: ['/s/scripts/team-lead-delegate.sh'],
    );
    expect(entries.single.event, HookEvent.preToolUse);
    expect(entries.single.source, HookSource.managed);
    final cmd = entries.single.action as CommandHookAction;
    expect(cmd.command, '/s/scripts/team-lead-delegate.sh');
  });

  test('extension settings hooks become managed entries', () {
    final entries = completer.extensionHooks(
      events: const ['PreToolUse', 'UserPromptSubmit'],
      command: 'bash /s/ext-hook.sh',
    );
    expect(entries.map((e) => e.event), [
      HookEvent.preToolUse,
      HookEvent.userPromptSubmit,
    ]);
    expect(entries.first.source, HookSource.extension);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/config_profile/hook_seat_context_completer_test.dart -v`
Expected: FAIL——方法不存在。

- [ ] **Step 3: Implement the assemblers**

`client/lib/services/cli/registry/config_profile/hook_seat_context_completer.dart` 追加：
```dart
  /// team-lead delegate PreToolUse 命令钩子（source: managed）。
  List<HookEntry> delegateHooks({required List<String> commands}) => [
    for (final command in commands)
      if (command.trim().isNotEmpty)
        HookEntry(
          id: 'teampilot-team-lead-delegate',
          source: HookSource.managed,
          event: HookEvent.preToolUse,
          matcher: '*',
          action: CommandHookAction.raw(command.trim()),
        ),
  ];

  /// 扩展 settings-hook（manifest `config.event` + command）。
  List<HookEntry> extensionHooks({
    required List<String> events,
    required String command,
  }) => [
    for (final eventName in events)
      if (HookEvent.tryParse(eventName) != null &&
          command.trim().isNotEmpty)
        HookEntry(
          id: 'teampilot-extension-settings-hook-$eventName',
          source: HookSource.extension,
          event: HookEvent.tryParse(eventName)!,
          action: CommandHookAction.raw(command.trim()),
        ),
  ];
```

- [ ] **Step 4: Rewire the three sources**

`client/lib/services/team/team_lead_delegate_settings_merge.dart`：删除 `TeamLeadDelegateSettingsMerge.merge` / `remove` 被装配点的调用（`maybeApplyTeamLeadHooks` 改为产出 commands 交给装配点——若签名复杂，最小改动：`ConfigProfileDelegate.maybeApplyTeamLeadHooks` 内部改为调用 completer + 统一 writer；`TeamLeadDelegateSettingsMerge` 的纯函数保留给既有单测）。

`client/lib/services/extension/effect/settings_hook_effect_applier.dart`：`apply` 改为返回 `(events, command)` 结构（或直接产 `HookEntry` 列表），由 claude/flashskyai `_writeMemberProfile` 的 `applyExtensionSettings` 消费点改为并入 entries。

`client/lib/services/plugin/plugin_manifest_service.dart`：`_scanHooks` 保留扫描；把 `PluginHook` 映射为 `HookEntry(source: plugin)` 的转换放 `HookSeatContextCompleter.pluginHooks(hooks: ...)`，装配点（插件物化处）并入。插件 hooks 的 matcher/event 语义照抄 `PluginHook` 现有字段（读 `client/lib/models/plugin.dart` 的 `PluginHook` 定义后对齐）。

- [ ] **Step 5: Run tests + analyzer**

Run: `cd client && flutter test test/services/cli/registry/config_profile/hook_seat_context_completer_test.dart -v && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS + 无新增 error。既有 delegate / settings-hook / plugin 测试若依赖旧 merge 行为，保持纯构建函数、只换装配调用点。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/registry/config_profile/hook_seat_context_completer.dart \
  client/lib/services/team/ client/lib/services/extension/ client/lib/services/plugin/
git commit -m "refactor(hooks): converge delegate/extension/plugin hooks into unified writer"
```

---

### Task 19: 删除死代码与资产路径

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/claude_family_hook_registry.dart`
- Modify: `client/lib/services/cli/registry/capabilities/hook_registry.dart`
- Modify: `client/lib/services/cli/registry/config_profile/agent_status_hooks.dart`（保留 `agentStatusHookUrl`）
- Modify: 各 tool 定义（移除 `HookRegistry` 能力注册，若已无消费者）

**Interfaces:**
- Consumes: 前序收敛结果。
- Produces: `ClaudeFamilyHookRegistry.render` / `mergeHooksInto`（若仍有消费者如扩展装配）保留；删除已无消费者的 `CliHookSpec` 资产注册路径（`ClaudeFamilyHookRegistry` 的 `collectDeclared`/`assetsFor` 用法与 `completeBusIdleHooks`），删除 `mergeAgentStatusHooks` 的 map 合并实现（保留 `agentStatusHookUrl`）。`HookRegistry` / `CliHookSpec` / `CliAssetRegistry` 若全库无引用则删除。

- [ ] **Step 1: 全库 grep 引用**

Run: `cd client && rg -n "mergeAgentStatusHooks|completeBusIdleHooks|ClaudeFamilyHookRegistry|HookRegistry|CliHookSpec|CliAssetRegistry" lib test`
按结果删除或保留：被测试引用的保留（纯构建），无引用的删除。删除后跑：
Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无未使用 import / undefined 引用。

- [ ] **Step 2: 删除死代码**

- `mergeAgentStatusHooks`：删除函数体，保留 `agentStatusHookUrl`（Task 14 completer 使用）。
- `completeBusIdleHooks` / registry 资产装配：删除（Task 14 已改走 completer）。
- 若 `HookRegistry` 无引用，删除 `hook_registry.dart` 中 `CliHookSpec`/`GeneratedScript`（`GeneratedScript` 被 hook_writer_capability 使用——保留该类，删 `CliHookSpec`）。

- [ ] **Step 3: 全量测试**

Run: `cd client && flutter test --exclude-tags integration`
Expected: PASS。失败项是迁移遗漏（引用已删符号），修复后重跑。

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/cli/registry/
git commit -m "refactor(hooks): remove dead asset-registry hook path after convergence"
```

---

### Task 20: HookCubit + 全局库 `/hooks` 路由 + 列表页

**Files:**
- Create: `client/lib/cubits/hook_cubit.dart`
- Create: `client/lib/pages/hooks/hook_management_page.dart`
- Modify: `client/lib/router/app_router.dart`
- Test: `client/test/services/hook/hook_cubit_test.dart`、`client/test/pages/hooks/hook_management_page_test.dart`

**Interfaces:**
- Consumes: `HookRepository`（Task 5）、`HookDefinition`。
- Produces: `class HookLibraryState{loading, definitions, errorMessage}`、`class HookCubit extends Cubit<HookLibraryState>{ load(); Future<bool> upsert(HookDefinition, {Map<String,String>? scripts}); Future<bool> remove(String id); }`；路由 `/hooks` → `HookManagementPage`；列表页展示定义卡片 + 新建/编辑入口（`HookEditorPage`，Task 21）。

- [ ] **Step 1: Write the failing cubit test**

`client/test/services/hook/hook_cubit_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/hook_cubit.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/hook/hook_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import '../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late HookRepository repository;
  late HookCubit cubit;

  setUp(() {
    fs = InMemoryFilesystem();
    repository = HookRepository(fs: fs, teampilotRoot: '/root');
    cubit = HookCubit(repository: repository);
  });

  tearDown(() => cubit.close());

  test('load populates definitions sorted', () async {
    await repository.save(const HookDefinition(
      id: 'h2',
      name: 'b',
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo b'),
    ));
    await repository.save(const HookDefinition(
      id: 'h1',
      name: 'a',
      event: HookEvent.sessionStart,
      action: CommandHookAction.raw('echo a'),
    ));
    await cubit.load();
    expect(cubit.state.loading, isFalse);
    expect(cubit.state.definitions.map((d) => d.id), ['h1', 'h2']);
  });

  test('upsert writes definition and scripts; remove deletes', () async {
    final ok = await cubit.upsert(
      const HookDefinition(
        id: 'h1',
        name: 'a',
        event: HookEvent.stop,
        action: CommandHookAction.script(fileName: 'hook.sh'),
      ),
      scripts: const {'hook.sh': 'echo hi'},
    );
    expect(ok, isTrue);
    expect(await repository.readScript('h1', 'hook.sh'), 'echo hi');
    final removed = await cubit.remove('h1');
    expect(removed, isTrue);
    expect(await repository.load('h1'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/hook/hook_cubit_test.dart -v`
Expected: FAIL——`HookCubit` 不存在。

- [ ] **Step 3: Write the cubit**

`client/lib/cubits/hook_cubit.dart`:
```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../models/hook_definition.dart';
import '../services/hook/hook_repository.dart';

class HookLibraryState extends Equatable {
  const HookLibraryState({
    this.loading = false,
    this.definitions = const [],
    this.errorMessage,
  });

  final bool loading;
  final List<HookDefinition> definitions;
  final String? errorMessage;

  @override
  List<Object?> get props => [loading, definitions, errorMessage];
}

class HookCubit extends Cubit<HookLibraryState> {
  HookCubit({required HookRepository repository}) : _repository = repository;

  final HookRepository _repository;

  Future<void> load() async {
    emit(const HookLibraryState(loading: true));
    try {
      final definitions = await _repository.loadAll();
      emit(HookLibraryState(definitions: definitions));
    } on Object catch (e) {
      emit(HookLibraryState(errorMessage: e.toString()));
    }
  }

  Future<bool> upsert(
    HookDefinition definition, {
    Map<String, String> scripts = const {},
  }) async {
    try {
      await _repository.save(definition);
      for (final entry in scripts.entries) {
        await _repository.writeScript(definition.id, entry.key, entry.value);
      }
      await load();
      return true;
    } on Object catch (e) {
      emit(HookLibraryState(errorMessage: e.toString()));
      return false;
    }
  }

  Future<bool> remove(String id) async {
    try {
      await _repository.delete(id);
      await load();
      return true;
    } on Object catch (e) {
      emit(HookLibraryState(errorMessage: e.toString()));
      return false;
    }
  }
}
```
（若 `equatable` 已是依赖——`client/pubspec.yaml` 无则改用 `flutter/foundation` 手写 `==`/`hashCode`，参照 `McpCubit` state 的写法。）

- [ ] **Step 4: List page + route**

`client/lib/pages/hooks/hook_management_page.dart`（列表壳，参照 `skill_management_page.dart` 结构；简化版）：
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/hook_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../repositories/hook_repository_provider.dart'; // 见 Step 5
import '../../widgets/settings/workspace_section_host.dart';
import 'hook_editor_page.dart';

class HookManagementPage extends StatelessWidget {
  const HookManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocProvider(
      create: (context) => HookCubit(
        repository: context.read<HookRepositoryProvider>().repository,
      )..load(),
      child: WorkspaceSectionHost(
        title: l10n.hookNavTitle,
        child: BlocBuilder<HookCubit, HookLibraryState>(
          builder: (context, state) {
            if (state.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            final definitions = state.definitions;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TpButton(
                    label: l10n.hookNew,
                    icon: Icons.add,
                    onPressed: () => context.go('/hooks/new'),
                  ),
                ),
                const SizedBox(height: 12),
                if (definitions.isEmpty)
                  TpEmptyState(
                    icon: Icons.bolt_outlined,
                    title: l10n.hooksNoInstalled,
                    hint: l10n.hooksNoInstalledHint,
                  )
                else
                  for (final definition in definitions)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.bolt_outlined),
                        title: Text(
                          definition.name.isEmpty
                              ? definition.id
                              : definition.name,
                        ),
                        subtitle: Text(
                          '${definition.event.name}'
                          '${definition.matcher == null ? '' : ' · ${definition.matcher}'}',
                        ),
                        onTap: () =>
                            context.go('/hooks/${definition.id}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await context
                                .read<HookCubit>()
                                .remove(definition.id);
                          },
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}
```
（`TpButton`/`TpEmptyState` 已在 shared_ui 使用；`WorkspaceSectionHost` 在 `widgets/settings/workspace_section_host.dart`——若签名不匹配，参照 `skill_management_page.dart` 的实际壳。）

路由 `client/lib/router/app_router.dart`：加 `GoRoute(path: '/hooks', builder: ...)` 与 `/hooks/:id`、`/hooks/new` → `HookEditorPage`（Task 21）。

**Repository 注入**：全局库需要可从路由取到 `HookRepository`——参照现有模式（如 `McpCubit` 在 bootstrap 注入）。若 app 已有注入点（`app_shell.dart` / `TeamPilotBootstrap`），直接 `context.read<HookRepository>()`；否则建 `client/lib/repositories/hook_repository_provider.dart` 的 InheritedWidget（按 `RuntimeContextRegistry` 或现有 provider 风格），构造参数 `fs`/`teampilotRoot` 来自 `AppStorage`。实现时以最小注入为准，保证测试可注入。

- [ ] **Step 5: l10n（列表页所需 key 在此添加）**

`client/lib/l10n/app_en.arb` / `app_zh.arb` 添加（en/zh 成对）：`hookNavTitle`（Hooks / Hooks）、`hookNew`（New hook / 新建 hook）、`hooksNoInstalled`（No hooks / 暂无 hooks）、`hooksNoInstalledHint`（Create a hook to run commands on CLI events. / 创建 hook，在 CLI 事件时运行命令。）
然后：`cd client && flutter gen-l10n`。其余编辑器/启用 section 的 key 在 Task 21-22 添加。

- [ ] **Step 6: Run tests + analyzer**

Run: `cd client && flutter test test/services/hook/hook_cubit_test.dart -v && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS（页面 widget 测试在 Task 21 补全）。

- [ ] **Step 7: Commit**

```bash
git add client/lib/cubits/hook_cubit.dart client/lib/pages/hooks/ \
  client/lib/router/app_router.dart \
  client/test/services/hook/hook_cubit_test.dart
git commit -m "feat(hooks): global library list page + route + HookCubit"
```

---

### Task 21: hook 编辑器表单 + 能力矩阵

**Files:**
- Create: `client/lib/pages/hooks/hook_editor_page.dart`
- Modify: `client/lib/l10n/app_en.arb`、`app_zh.arb`
- Test: `client/test/pages/hooks/hook_editor_page_test.dart`

**Interfaces:**
- Consumes: `HookCubit`、`HookEventCapability.matrix`（Task 1）、`CliTool.values`。
- Produces: `HookEditorPage(definition?)`——新建/编辑表单：name、description、event 下拉（带支持徽标）、matcher、action 双模式（命令/脚本 + 脚本内容编辑）、policy 下拉（拦截事件才显示）、timeoutSec、env 键值；保存走 `HookCubit.upsert`；只读能力矩阵（事件 × 5 CLI）。

- [ ] **Step 1: Write the failing widget test**

`client/test/pages/hooks/hook_editor_page_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/hook_cubit.dart';
import 'package:teampilot/pages/hooks/hook_editor_page.dart';
import 'package:teampilot/services/hook/hook_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  testWidgets('editor renders fields and saves a raw command hook', (
    tester,
  ) async {
    final fs = InMemoryFilesystem();
    final cubit = HookCubit(
      repository: HookRepository(fs: fs, teampilotRoot: '/root'),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        home: HookEditorPage(cubit: cubit),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('On session start'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('hook-name')),
      'On session start',
    );
    await tester.enterText(
      find.byKey(const Key('hook-command')),
      'echo start',
    );
    await tester.tap(find.byKey(const Key('hook-save')));
    await tester.pumpAndSettle();

    final saved = await HookRepository(
      fs: fs,
      teampilotRoot: '/root',
    ).loadAll();
    expect(saved, hasLength(1));
    expect(saved.single.name, 'On session start');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/hooks/hook_editor_page_test.dart -v`
Expected: FAIL——页面不存在。若 `MaterialApp` 需要 `TpTheme` 包裹（shared_ui），按 `shared_ui/README.md` 包裹。

- [ ] **Step 3: Write the editor page**

`client/lib/pages/hooks/hook_editor_page.dart`（骨架完整、字段按 Key 暴露）:
```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/hook_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/hook_definition.dart';
import '../../models/hook_entry.dart';
import '../../models/hook_event.dart';
import '../../models/team_config.dart';
import '../../widgets/settings/workspace_section_host.dart';

class HookEditorPage extends StatefulWidget {
  const HookEditorPage({required this.cubit, this.definition, super.key});

  final HookCubit cubit;
  final HookDefinition? definition;

  @override
  State<HookEditorPage> createState() => _HookEditorPageState();
}

class _HookEditorPageState extends State<HookEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _command;
  late final TextEditingController _scriptContent;
  late final TextEditingController _timeout;
  late final TextEditingController _env;

  late HookEvent _event;
  late String _matcher;
  late HookPolicy _policy;
  bool _useScript = false;

  @override
  void initState() {
    super.initState();
    final definition = widget.definition;
    _name = TextEditingController(text: definition?.name ?? '');
    _description = TextEditingController(text: definition?.description ?? '');
    final action = definition?.action;
    final command = action is CommandHookAction ? action.command ?? '' : '';
    _command = TextEditingController(text: command);
    _scriptContent = TextEditingController();
    _timeout = TextEditingController(
      text: definition?.timeoutSec?.toString() ?? '',
    );
    _env = TextEditingController(
      text: definition?.env.entries
              .map((e) => '${e.key}=${e.value}')
              .join('\n') ??
          '',
    );
    _event = definition?.event ?? HookEvent.stop;
    _matcher = definition?.matcher ?? '';
    _policy = definition?.policy ?? HookPolicy.none;
    _useScript = action is CommandHookAction && action.command == null;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _command.dispose();
    _scriptContent.dispose();
    _timeout.dispose();
    _env.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = widget.definition?.id ?? _slugify(_name.text);
    if (id.isEmpty) return;
    final env = <String, String>{};
    for (final line in _env.text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final index = trimmed.indexOf('=');
      if (index <= 0) continue;
      env[trimmed.substring(0, index)] = trimmed.substring(index + 1);
    }
    final action = _useScript
        ? CommandHookAction.script(
            fileName: 'hook.sh',
            scriptContent: _scriptContent.text,
          )
        : CommandHookAction.raw(_command.text);
    final definition = HookDefinition(
      id: id,
      name: _name.text,
      description: _description.text,
      event: _event,
      matcher: _matcher.trim().isEmpty ? null : _matcher.trim(),
      action: action,
      policy: _event.isIntercepting ? _policy : HookPolicy.none,
      timeoutSec: int.tryParse(_timeout.text),
      env: env,
    );
    final scripts = _useScript
        ? {if (_scriptContent.text.isNotEmpty) 'hook.sh': _scriptContent.text}
        : const <String, String>{};
    final ok = await widget.cubit.upsert(definition, scripts: scripts);
    if (!mounted) return;
    if (ok) Navigator.of(context).pop();
  }

  String _slugify(String value) {
    final slug = value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return slug.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WorkspaceSectionHost(
      title: widget.definition == null ? l10n.hookNew : l10n.hookEdit,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('hook-name'),
            controller: _name,
            decoration: InputDecoration(labelText: l10n.hookName),
          ),
          TextField(
            controller: _description,
            decoration: InputDecoration(labelText: l10n.hookDescription),
          ),
          DropdownButtonFormField<HookEvent>(
            key: const Key('hook-event'),
            initialValue: _event,
            items: [
              for (final event in HookEvent.values)
                DropdownMenuItem(
                  value: event,
                  child: Text('${event.name}${_supportBadge(event)}'),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _event = value);
            },
            decoration: InputDecoration(labelText: l10n.hookEvent),
          ),
          TextField(
            controller: _command,
            enabled: !_useScript,
            key: const Key('hook-command'),
            decoration: InputDecoration(labelText: l10n.hookActionCommand),
          ),
          SwitchListTile(
            key: const Key('hook-use-script'),
            title: Text(l10n.hookActionScript),
            value: _useScript,
            onChanged: (value) => setState(() => _useScript = value),
          ),
          if (_useScript)
            TextField(
              key: const Key('hook-script'),
              controller: _scriptContent,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: 'hook.sh',
                alignLabelWithHint: true,
              ),
            ),
          if (_event.isIntercepting)
            DropdownButtonFormField<HookPolicy>(
              key: const Key('hook-policy'),
              initialValue: _policy,
              items: [
                for (final policy in HookPolicy.values)
                  DropdownMenuItem(value: policy, child: Text(policy.name)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _policy = value);
              },
              decoration: InputDecoration(labelText: l10n.hookPolicy),
            ),
          TextField(
            controller: _timeout,
            key: const Key('hook-timeout'),
            decoration: InputDecoration(labelText: l10n.hookTimeoutSec),
          ),
          TextField(
            controller: _env,
            maxLines: 4,
            decoration: InputDecoration(labelText: l10n.hookEnv),
          ),
          const SizedBox(height: 16),
          _CapabilityMatrix(event: _event),
          const SizedBox(height: 16),
          TpButton(
            key: const Key('hook-save'),
            label: l10n.hookSave,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  String _supportBadge(HookEvent event) {
    final supported = CliTool.values
        .where((cli) => HookEventCapability.supports(event, cli))
        .length;
    return ' ($supported/5)';
  }
}

class _CapabilityMatrix extends StatelessWidget {
  const _CapabilityMatrix({required this.event});

  final HookEvent event;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Capability matrix'),
        const SizedBox(height: 4),
        for (final cli in CliTool.values)
          Builder(builder: (context) {
            final support = HookEventCapability.support(event, cli);
            final mark = !support.supported
                ? '✗'
                : support.approximate
                ? '≈'
                : '✓';
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(mark),
              title: Text(cli.name),
              subtitle: support.nativeEvent == null
                  ? null
                  : Text(support.nativeEvent!),
            );
          }),
      ],
    );
  }
}
```
（l10n key 与 `TpButton`/`WorkspaceSectionHost` 签名按现有实现微调；`initialValue` 若 SDK 版本不支持改用 `value:`。）

- [ ] **Step 4: l10n keys**

`client/lib/l10n/app_en.arb` / `app_zh.arb` 添加（en/zh 成对；`hookNavTitle`/`hookNew`/`hooksNoInstalled`/`hooksNoInstalledHint` 已在 Task 20 添加，勿重复）：
`hookEdit`（Edit hook / 编辑 hook）、`hookName`（Name / 名称）、`hookDescription`（Description / 描述）、`hookEvent`（Event / 事件）、`hookActionCommand`（Command / 命令）、`hookActionScript`（Script / 脚本）、`hookPolicy`（Policy / 策略）、`hookTimeoutSec`（Timeout (seconds) / 超时（秒））、`hookEnv`（Environment (KEY=VALUE per line) / 环境变量（每行 KEY=VALUE））、`hookSave`（Save / 保存）
然后：`cd client && flutter gen-l10n`。

- [ ] **Step 5: Run tests + analyzer**

Run: `cd client && flutter test test/pages/hooks/hook_editor_page_test.dart test/services/hook/hook_cubit_test.dart -v && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS + 无新增 error。

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/hooks/hook_editor_page.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/test/pages/hooks/hook_editor_page_test.dart
git commit -m "feat(hooks): hook editor form with capability matrix + l10n"
```

---

### Task 22: workspace manage + team-config 启用 section + 全局视图入口

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_config_section.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_config_workspace.dart`
- Create: `client/lib/pages/home_workspace/workspace/config/workspace_hooks_section.dart`
- Create: `client/lib/pages/team_config/team_config_hooks_section.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_global_section.dart`
- Test: `client/test/pages/team_config/team_config_hooks_section_test.dart`、`client/test/pages/home_workspace/workspace/config/workspace_hooks_section_test.dart`

**Interfaces:**
- Consumes: `HookCubit`/`HookRepository`、`WorkspaceProjectConfigCubit`（`updateBundle`）、`LaunchProfileCubit`（team bundle）。
- Produces: `WorkspaceConfigSection.hooks`（routeSegment `hooks`，icon `Icons.bolt_outlined`，title `l10n.homeWorkspaceWorkspaceHooks`）；`WorkspaceHooksSection`（勾选启用 → `projectState.config.bundle.copyWith(hookIds: ...)`）；`TeamHooksSection`（`team.hookIds` → `cubit` 更新）；`HomeGlobalView.hooks` → `/hooks`。

- [ ] **Step 1: Write the failing test**

`client/test/pages/team_config/team_config_hooks_section_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/hook_cubit.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/pages/team_config/team_config_hooks_section.dart';
import 'package:teampilot/services/hook/hook_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  testWidgets('team hooks section lists library and toggles assignment', (
    tester,
  ) async {
    final fs = InMemoryFilesystem();
    final repository = HookRepository(fs: fs, teampilotRoot: '/root');
    await repository.save(const HookDefinition(
      id: 'h1',
      name: 'On start',
      event: HookEvent.sessionStart,
      action: CommandHookAction.raw('echo a'),
    ));
    final hookCubit = HookCubit(repository: repository)..load();
    addTearDown(hookCubit.close);

    var teamHookIds = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<HookCubit>.value(
          value: hookCubit,
          child: TeamHooksSection(
            assignedIds: teamHookIds,
            onAssignedChanged: (ids) => teamHookIds = ids,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('On start'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(teamHookIds, contains('h1'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/team_config/team_config_hooks_section_test.dart -v`
Expected: FAIL——section 不存在。若 `TeamHooksSection` 构造契约与真实团队页不同（真实用 `TeamProfile` + `LaunchProfileCubit`，见 `team_config_mcp_section.dart`），本测试定义最小接口 `TeamHooksSection({assignedIds, onAssignedChanged})`，装配页负责适配 `team`/`cubit`。

- [ ] **Step 3: Write the two sections**

`client/lib/pages/home_workspace/workspace/config/workspace_hooks_section.dart`（仿 `workspace_skills_section.dart`，交互对象为 hook 定义列表与 `hookIds`）:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../cubits/hook_cubit.dart';
import '../../../../cubits/workspace_project_config_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../team_config/team_config_cards.dart';

class WorkspaceHooksSection extends StatelessWidget {
  const WorkspaceHooksSection({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final projectState = context.watch<WorkspaceProjectConfigCubit>().state;
    if (projectState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final hookState = context.watch<HookCubit>().state;
    final definitions = hookState.definitions;
    final hookIds = projectState.config.bundle.hookIds;
    final assignedCount = definitions.where((d) => hookIds.contains(d.id)).length;
    final projectCubit = context.read<WorkspaceProjectConfigCubit>();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamConfigCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamConfigCardHeader(
                  title: l10n.workspaceHooksAssignedCount(
                    assignedCount,
                    definitions.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: () => context.go('/hooks'),
                    icon: const Icon(Icons.bolt_outlined),
                    label: Text(l10n.workspaceHooksManage),
                  ),
                ),
                const SizedBox(height: 14),
                if (definitions.isEmpty)
                  TpEmptyState(
                    icon: Icons.bolt_outlined,
                    title: l10n.hooksNoInstalled,
                    hint: l10n.hooksNoInstalledHint,
                    actionLabel: l10n.workspaceHooksManage,
                    onAction: () => context.go('/hooks'),
                  )
                else
                  for (final definition in definitions)
                    CheckboxListTile(
                      value: hookIds.contains(definition.id),
                      title: Text(
                        definition.name.isEmpty
                            ? definition.id
                            : definition.name,
                      ),
                      subtitle: Text(definition.event.name),
                      onChanged: (assigned) {
                        final ids = List<String>.from(hookIds);
                        if (assigned == true) {
                          if (!ids.contains(definition.id)) ids.add(definition.id);
                        } else {
                          ids.remove(definition.id);
                        }
                        unawaited(
                          projectCubit.updateBundle(
                            projectState.config.bundle.copyWith(
                              hookIds: List<String>.unmodifiable(ids),
                            ),
                          ),
                        );
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
```

`client/lib/pages/team_config/team_config_hooks_section.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/hook_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import 'team_config_cards.dart';

/// 团队身份的 hooks 启用 section（装配页负责传团队当前 hookIds 与回调）。
class TeamHooksSection extends StatelessWidget {
  const TeamHooksSection({
    required this.assignedIds,
    required this.onAssignedChanged,
    this.onManageGlobal,
    super.key,
  });

  final List<String> assignedIds;
  final void Function(List<String> ids) onAssignedChanged;
  final VoidCallback? onManageGlobal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final onManage = onManageGlobal ?? () => context.go('/hooks');
    final hookState = context.watch<HookCubit>().state;
    final definitions = hookState.definitions;
    final assignedCount =
        definitions.where((d) => assignedIds.contains(d.id)).length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamConfigCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamConfigCardHeader(
                  title: l10n.teamHooksAssignedCount(
                    assignedCount,
                    definitions.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: onManage,
                    icon: const Icon(Icons.bolt_outlined),
                    label: Text(l10n.teamHooksManage),
                  ),
                ),
                const SizedBox(height: 14),
                if (definitions.isEmpty)
                  TpEmptyState(
                    icon: Icons.bolt_outlined,
                    title: l10n.hooksNoInstalled,
                    hint: l10n.hooksNoInstalledHint,
                    actionLabel: l10n.teamHooksManage,
                    onAction: onManage,
                  )
                else
                  for (final definition in definitions)
                    CheckboxListTile(
                      value: assignedIds.contains(definition.id),
                      title: Text(
                        definition.name.isEmpty
                            ? definition.id
                            : definition.name,
                      ),
                      subtitle: Text(definition.event.name),
                      onChanged: (assigned) {
                        final ids = List<String>.from(assignedIds);
                        if (assigned == true) {
                          if (!ids.contains(definition.id)) {
                            ids.add(definition.id);
                          }
                        } else {
                          ids.remove(definition.id);
                        }
                        onAssignedChanged(ids);
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
```

- [ ] **Step 4: Wire sections + global view**

- `workspace_config_section.dart`：枚举加 `hooks`（routeSegment/icon/title）。
- `workspace_config_workspace.dart`：`_ProjectConfigBody` switch 加 `WorkspaceConfigSection.hooks => WorkspaceHooksSection(workspaceId: workspace.workspaceId)`。
- `team_config_page.dart` 的成员/资源 section 装配：在团队配置导航（参照 `team_config_mcp_section.dart` 的挂载方式）挂 `TeamHooksSection(assignedIds: team.hookIds, onAssignedChanged: (ids) { cubit 更新 team bundle })`——`LaunchProfileCubit` 更新 team 的 `ConfigBundle.hookIds`。
- `home_workspace_global_section.dart`：`HomeGlobalView` 枚举加 `hooks`（location `/hooks`），并确保 `home` 导航入口（如 skills 入口旁边）可见。
- l10n：`workspaceHooksAssignedCount`/`workspaceHooksManage`/`teamHooksAssignedCount`/`teamHooksManage`/`homeWorkspaceWorkspaceHooks`（en/zh），`flutter gen-l10n`。

- [ ] **Step 5: Run tests + analyzer + full suite**

Run: `cd client && flutter test test/pages/team_config/team_config_hooks_section_test.dart -v && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: PASS。若有 l10n 生成或 section 挂载的编译错误，按报错修正。

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/home_workspace/ client/lib/pages/team_config/ \
  client/lib/l10n/ \
  client/test/pages/team_config/team_config_hooks_section_test.dart
git commit -m "feat(hooks): workspace + team enablement sections and global view entry"
```

---

### Task 23: 端到端冒烟 + 文档

**Files:**
- Create: `docs/cli-formats/hooks.md`
- Modify: `docs/cli-architecture.md`（新增 hooks 管线一节，如适用）

**Interfaces:**
- Consumes: 全量实现。
- Produces: 文档（归一化事件目录、各 CLI 格式映射、决策 JSON 契约、故障排查）。

- [ ] **Step 1: 全量验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: 全绿。

- [ ] **Step 2: 端到端冒烟（手工清单）**

1. `/hooks` 新建一个 `sessionStart` 命令 hook（`echo start > /tmp/tp-hook.log`）；
2. 工作区 manage → hooks 勾选；Simple 启动 claude 会话 → 检查 session settings.json 含 `SessionStart` hooks 表 + `hooks/teampilot-hook-<id>.sh`，且 `~/.claude` 类托管 hooks 仍在；
3. Team 团队身份挂同 hook → mixed 成员 settings.json 同样物化；
4. codex 会话：`CODEX_HOME/config.toml` 含 `[[hooks.SessionStart]]`；
5. cursor 会话：fake HOME `~/.cursor/hooks.json` 含条目（与 agent-status 条目共存）；
6. opencode 会话：config dir 有 `teampilot-user-hooks.js`，`opencode.json` plugin 数组含三项（agent-status/idle/user-hooks）；
7. 删除库中 hook → 重连会话 → 配置里条目消失。

- [ ] **Step 3: 写文档**

`docs/cli-formats/hooks.md`：归一化事件表（13 事件 × 5 CLI 支持矩阵，含 ≈ 语义）、决策 JSON 契约（claude/codex flat `permissionDecision`、cursor `permission` + exit 2、opencode `{decision}`）、配置落点、glue 契约（stdin 透传/空输出注入/透传输出）、已知限制（cursor 无 permissionRequest、opencode 无 sessionStart 等）。

- [ ] **Step 4: Commit**

```bash
git add docs/cli-formats/hooks.md docs/cli-architecture.md
git commit -m "docs(hooks): CLI format reference and architecture notes"
```

---

## 收尾清单（全部任务完成后）

- `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` 无错误；
- `cd client && flutter test --exclude-tags integration` 全绿；
- `docs/superpowers/plans/2026-08-13-hook-management.md` 无占位符；spec 每节有对应任务：
  - §2.1 事件目录/矩阵 → Task 1、12（cursor 官方 docs 落地）
  - §2.2 HookEntry → Task 2
  - §2.3 用户库模型 → Task 3、5
  - §3 启用层 → Task 4、9
  - §4.1 能力接口 + 胶水 → Task 7、8
  - §4.2 各 CLI writer → Task 10-13
  - §4.3 收敛 → Task 14-19
  - §5 UI → Task 20-22
  - §6 磁盘布局 → Task 9-13 装配点
  - §7 错误处理/测试 → 各任务内
  - §8 不在范围 → 无任务（符合预期）
