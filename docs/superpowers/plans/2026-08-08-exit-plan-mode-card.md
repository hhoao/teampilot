# ExitPlanMode 卡片优化 + Claude/flashskyai 聊天内批准 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 ExitPlanMode 卡片升级为 Markdown 渲染 + 展开/收起 + 复制 + 可点击路径，并为 claude/flashskyai 提供聊天内批准/拒绝（hook-gate）。

**Architecture:** 复用 AskUserQuestion 的成熟 hook-gate 机制：`AgentStatusHttpHandler` 挂起 ExitPlanMode `PreToolUse` 响应，卡片批准/拒绝后回复官方 `permissionDecision: allow/deny`。新加 `ExitPlanModeCapability`（capability 注册表）门控哪些 CLI 支持；cursor/codex/opencode 保持「打开终端」回退。

**Tech Stack:** Flutter/Dart，flutter_bloc（ChatCubit/AgentAttentionCubit），tp_markdown（Markdown 渲染），shared_ui（TpButton/TpIconButton/TpHover），l10n（app_en.arb/app_zh.arb）。

## Global Constraints

- 设计 spec：`docs/superpowers/specs/2026-08-08-exit-plan-mode-card-design.md`（唯一权威需求）。
- CLI capability 接线仿各 tool 定义中 `askUserQuestion` 字段写法（构造参数 + 字段 + `capabilities` 列表）。
- claude、flashskyai → `HookExitPlanModeCapability`；codex、opencode、cursor → `NoExitPlanModeCapability`（不做聊天内批准）。
- Hook 挂起仅当 capability 支持（未验证 CLI 永不阻塞回合）。
- 每任务完成后 `cd client && flutter test <该任务测试>` 必须通过；全量 `flutter analyze --no-fatal-infos --no-fatal-warnings`。
- 新 l10n 键只编辑 `client/lib/l10n/app_en.arb` 与 `app_zh.arb`，然后 `cd client && flutter gen-l10n` 重新生成 `app_localizations.dart`。
- 提交信息用 `Co-Authored-By: Claude <noreply@anthropic.com>` 结尾。

---

### Task 1: ExitPlanModeCapability

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/exit_plan_mode_capability.dart`
- Modify: `client/lib/services/cli/registry/tools/claude_cli_tool.dart`、`flashskyai_cli_tool.dart`、`codex_cli_tool.dart`、`opencode_cli_tool.dart`、`cursor_cli_tool.dart`
- Test: `client/test/services/cli/registry/exit_plan_mode_capability_test.dart`

**Interfaces:**
- Produces: `enum ExitPlanApprovalKind { hookReply, none }`；`abstract interface class ExitPlanModeCapability implements CliCapability { bool get supportsInChatApproval; ExitPlanApprovalKind get approvalKind; }`；`final class HookExitPlanModeCapability`；`final class NoExitPlanModeCapability`。后续 Task 3/8 用 `registry.capability<ExitPlanModeCapability>(cli)`。

- [ ] **Step 1: 写失败测试**

`client/test/services/cli/registry/exit_plan_mode_capability_test.dart`：
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/exit_plan_mode_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  test('claude + flashskyai support in-chat approval', () {
    for (final cli in [CliTool.claude, CliTool.flashskyai]) {
      final cap = registry.capability<ExitPlanModeCapability>(cli);
      expect(cap, isNotNull);
      expect(cap!.supportsInChatApproval, isTrue);
      expect(cap.approvalKind, ExitPlanApprovalKind.hookReply);
    }
  });

  test('codex + opencode + cursor do not support in-chat approval', () {
    for (final cli in [CliTool.codex, CliTool.opencode, CliTool.cursor]) {
      final cap = registry.capability<ExitPlanModeCapability>(cli);
      expect(cap, isNotNull);
      expect(cap!.supportsInChatApproval, isFalse);
      expect(cap.approvalKind, ExitPlanApprovalKind.none);
    }
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/cli/registry/exit_plan_mode_capability_test.dart -v`
Expected: 编译失败（`exit_plan_mode_capability.dart` 不存在 / 无法解析 import）。

- [ ] **Step 3: 实现 capability**

Create `client/lib/services/cli/registry/capabilities/exit_plan_mode_capability.dart`：
```dart
import '../cli_capability.dart';

/// How a CLI resolves an in-chat ExitPlanMode approval.
enum ExitPlanApprovalKind { hookReply, none }

/// Per-CLI support for approving/rejecting `ExitPlanMode` in chat.
///
/// claude + flashskyai hold the `PreToolUse` HTTP hook and reply with the
/// official `permissionDecision`. Other CLIs keep the "Open Terminal" fallback.
abstract interface class ExitPlanModeCapability implements CliCapability {
  bool get supportsInChatApproval;
  ExitPlanApprovalKind get approvalKind;
}

final class HookExitPlanModeCapability implements ExitPlanModeCapability {
  const HookExitPlanModeCapability();

  @override
  bool get supportsInChatApproval => true;

  @override
  ExitPlanApprovalKind get approvalKind => ExitPlanApprovalKind.hookReply;
}

final class NoExitPlanModeCapability implements ExitPlanModeCapability {
  const NoExitPlanModeCapability();

  @override
  bool get supportsInChatApproval => false;

  @override
  ExitPlanApprovalKind get approvalKind => ExitPlanApprovalKind.none;
}
```

- [ ] **Step 4: 接线 5 个 tool 定义**

每个文件 4 处改动（import + 构造参数 + 字段 + capabilities 列表）。以 `claude_cli_tool.dart` 为例（其余同构）：

在 import 区加（`ask_user_question_capability.dart` import 附近）：
```dart
import '../capabilities/exit_plan_mode_capability.dart';
```
构造器参数区（`this.askUserQuestion = ...` 旁）：
```dart
    this.exitPlanMode = const HookExitPlanModeCapability(),
```
字段区（`final AskUserQuestionCapability askUserQuestion;` 旁）：
```dart
  final ExitPlanModeCapability exitPlanMode;
```
`capabilities` 列表（`askUserQuestion,` 后）：
```dart
    exitPlanMode,
```

- `claude_cli_tool.dart`、`flashskyai_cli_tool.dart` → `const HookExitPlanModeCapability()`
- `codex_cli_tool.dart`、`opencode_cli_tool.dart`、`cursor_cli_tool.dart` → `const NoExitPlanModeCapability()`

- [ ] **Step 5: 运行确认通过**

Run: `cd client && flutter test test/services/cli/registry/exit_plan_mode_capability_test.dart -v`
Expected: PASS (2 tests)。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/exit_plan_mode_capability.dart \
        client/lib/services/cli/registry/tools/claude_cli_tool.dart \
        client/lib/services/cli/registry/tools/flashskyai_cli_tool.dart \
        client/lib/services/cli/registry/tools/codex_cli_tool.dart \
        client/lib/services/cli/registry/tools/opencode_cli_tool.dart \
        client/lib/services/cli/registry/tools/cursor_cli_tool.dart \
        client/test/services/cli/registry/exit_plan_mode_capability_test.dart
git commit -m "feat(cli): ExitPlanMode capability gates in-chat approval

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: ExitPlanModeHookGate

**Files:**
- Create: `client/lib/services/agent_status/exit_plan_mode_hook_gate.dart`
- Test: `client/test/services/agent_status/exit_plan_mode_hook_gate_test.dart`

**Interfaces:**
- Produces: `final class ExitPlanModeHookReply { const ExitPlanModeHookReply.allow(); const ExitPlanModeHookReply.deny(); final bool deny; }`；`final class ExitPlanModeHookGate { Future<ExitPlanModeHookReply?> wait({required String sessionId, required String memberId, required String toolUseId, Duration timeout}); bool complete({sessionId, memberId, toolUseId, required ExitPlanModeHookReply reply}); bool hasWaiter({sessionId, memberId, toolUseId}); void clearSeat({sessionId, memberId}); void clearSession(String sessionId); }`。Task 3 调 `wait`，Task 4 调 `complete`。

- [ ] **Step 1: 写失败测试**

`client/test/services/agent_status/exit_plan_mode_hook_gate_test.dart`：
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/exit_plan_mode_hook_gate.dart';

void main() {
  test('wait registers a waiter; complete resolves allow', () async {
    final gate = ExitPlanModeHookGate();
    final future = gate.wait(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't1',
      timeout: const Duration(milliseconds: 500),
    );
    expect(
      gate.hasWaiter(sessionId: 's', memberId: 'm', toolUseId: 't1'),
      isTrue,
    );
    expect(
      gate.complete(
        sessionId: 's',
        memberId: 'm',
        toolUseId: 't1',
        reply: const ExitPlanModeHookReply.allow(),
      ),
      isTrue,
    );
    final reply = await future;
    expect(reply?.deny, isFalse);
    expect(
      gate.hasWaiter(sessionId: 's', memberId: 'm', toolUseId: 't1'),
      isFalse,
    );
  });

  test('complete with no waiter returns false', () {
    final gate = ExitPlanModeHookGate();
    expect(
      gate.complete(
        sessionId: 's',
        memberId: 'm',
        toolUseId: 'nope',
        reply: const ExitPlanModeHookReply.deny(),
      ),
      isFalse,
    );
  });

  test('wait times out and returns null', () async {
    final gate = ExitPlanModeHookGate();
    final reply = await gate.wait(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't3',
      timeout: const Duration(milliseconds: 30),
    );
    expect(reply, isNull);
  });

  test('clearSeat resolves pending waiters as deny', () async {
    final gate = ExitPlanModeHookGate();
    final future = gate.wait(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't4',
      timeout: const Duration(hours: 1),
    );
    gate.clearSeat(sessionId: 's', memberId: 'm');
    final reply = await future;
    expect(reply?.deny, isTrue);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/agent_status/exit_plan_mode_hook_gate_test.dart -v`
Expected: 编译失败（文件不存在）。

- [ ] **Step 3: 实现 gate**

Create `client/lib/services/agent_status/exit_plan_mode_hook_gate.dart`：
```dart
import 'dart:async';

/// Reply for a held Claude-family ExitPlanMode `PreToolUse` HTTP hook.
final class ExitPlanModeHookReply {
  const ExitPlanModeHookReply.allow() : deny = false;
  const ExitPlanModeHookReply.deny() : deny = true;

  final bool deny;
}

/// Holds open Claude `PreToolUse` HTTP hooks for ExitPlanMode until the chat
/// card approves/rejects (official `permissionDecision` allow/deny path).
///
/// Parallel to `AskUserQuestionHookGate`; a distinct reply type (allow/deny,
/// no answers payload) keeps the two gates independent.
final class ExitPlanModeHookGate {
  final _waiters = <String, Completer<ExitPlanModeHookReply>>{};

  /// Waits for [complete] with the same ids. Returns `null` on timeout so the
  /// handler can fall through to Claude's native TUI (`{}` response).
  Future<ExitPlanModeHookReply?> wait({
    required String sessionId,
    required String memberId,
    required String toolUseId,
    Duration timeout = const Duration(hours: 24),
  }) async {
    final key = _key(sessionId, memberId, toolUseId);
    final existing = _waiters.remove(key);
    if (existing != null && !existing.isCompleted) {
      existing.complete(const ExitPlanModeHookReply.deny());
    }
    final completer = Completer<ExitPlanModeHookReply>();
    _waiters[key] = completer;
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      final current = _waiters[key];
      if (identical(current, completer)) {
        _waiters.remove(key);
      }
    }
  }

  /// Returns true when a waiter was completed (hook still open).
  bool complete({
    required String sessionId,
    required String memberId,
    required String toolUseId,
    required ExitPlanModeHookReply reply,
  }) {
    final completer = _waiters.remove(
      _key(sessionId, memberId, toolUseId),
    );
    if (completer == null || completer.isCompleted) return false;
    completer.complete(reply);
    return true;
  }

  bool hasWaiter({
    required String sessionId,
    required String memberId,
    required String toolUseId,
  }) {
    final completer = _waiters[_key(sessionId, memberId, toolUseId)];
    return completer != null && !completer.isCompleted;
  }

  void clearSeat({required String sessionId, required String memberId}) {
    final prefix = '${sessionId.trim()}/${memberId.trim()}/';
    final doomed = <String>[];
    for (final key in _waiters.keys) {
      if (key.startsWith(prefix)) doomed.add(key);
    }
    for (final key in doomed) {
      final c = _waiters.remove(key);
      if (c != null && !c.isCompleted) {
        c.complete(const ExitPlanModeHookReply.deny());
      }
    }
  }

  void clearSession(String sessionId) {
    final prefix = '${sessionId.trim()}/';
    final doomed = <String>[];
    for (final key in _waiters.keys) {
      if (key.startsWith(prefix)) doomed.add(key);
    }
    for (final key in doomed) {
      final c = _waiters.remove(key);
      if (c != null && !c.isCompleted) {
        c.complete(const ExitPlanModeHookReply.deny());
      }
    }
  }

  String _key(String sessionId, String memberId, String toolUseId) =>
      '${sessionId.trim()}/${memberId.trim()}/${toolUseId.trim()}';
}
```

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/services/agent_status/exit_plan_mode_hook_gate_test.dart -v`
Expected: PASS (4 tests)。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/agent_status/exit_plan_mode_hook_gate.dart \
        client/test/services/agent_status/exit_plan_mode_hook_gate_test.dart
git commit -m "feat(agent-status): ExitPlanMode hook gate holds PreToolUse approval

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: AgentStatusHttpHandler 挂起 ExitPlanMode

**Files:**
- Modify: `client/lib/services/agent_status/agent_status_http_handler.dart`
- Test: `client/test/services/agent_status/agent_status_http_handler_exit_plan_test.dart`

**Interfaces:**
- Consumes: `ExitPlanModeHookGate`（Task 2）、`ExitPlanModeCapability`（Task 1）、`isExitPlanModeTool`（`agent_status/exit_plan_mode.dart`）。
- Produces: `AgentStatusHttpHandler` 新增可选参数 `ExitPlanModeHookGate? exitPlanModeHookGate` 和 `CliToolRegistry? registry`（默认 `CliToolRegistry.builtIn()`）。Task 9 传 gate。

- [ ] **Step 1: 写失败测试**

`client/test/services/agent_status/agent_status_http_handler_exit_plan_test.dart`（仿 `agent_status_http_handler_ask_user_test.dart`）：
```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_http_handler.dart';
import 'package:teampilot/services/agent_status/exit_plan_mode_hook_gate.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late AgentAttentionCubit cubit;
  late ExitPlanModeHookGate gate;
  late TeammateBusMcpGateway gateway;
  late HttpClient client;

  setUp(() async {
    cubit = AgentAttentionCubit(pruneInterval: null);
    gate = ExitPlanModeHookGate();
    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    gateway.attachAgentStatusHandler(
      AgentStatusHttpHandler(
        attention: cubit,
        resolveCli: (_, __) => CliTool.claude,
        resolveSkipPermissions: (_, __) => false,
        exitPlanModeHookGate: gate,
      ),
    );
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await cubit.close();
    await gateway.dispose();
  });

  Future<HttpClientResponse> postExitPlan({
    required String sessionId,
    required String memberId,
    required Map<String, Object?> body,
  }) async {
    final uri = Uri.parse('http://127.0.0.1:${gateway.httpPort}/agent-status');
    final req = await client.postUrl(uri);
    req.headers.set('content-type', 'application/json');
    req.headers.set('connection', 'close');
    req.headers.set(teammateBusMcpSessionHeader, sessionId);
    req.headers.set(teammateBusMcpMemberHeader, memberId);
    req.add(utf8.encode(jsonEncode(body)));
    return req.close();
  }

  Future<void> waitUntilWaiter({
    required String sessionId,
    required String memberId,
    required String toolUseId,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (gate.hasWaiter(
        sessionId: sessionId,
        memberId: memberId,
        toolUseId: toolUseId,
      )) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('timed out waiting for ExitPlanMode hook waiter');
  }

  Map<String, Object?> exitPlanBody({
    required String toolUseId,
    required String plan,
  }) {
    return {
      'hook_event_name': 'PreToolUse',
      'tool_name': 'ExitPlanMode',
      'tool_use_id': toolUseId,
      'tool_input': {'plan': plan},
    };
  }

  test('PreToolUse hold → allow → permissionDecision allow', () async {
    const sessionId = 'ep-s1';
    const memberId = 'm1';
    const toolUseId = 'toolu-ep-1';
    gateway.registerAgentStatusSession(sessionId: sessionId);

    final responseFuture = postExitPlan(
      sessionId: sessionId,
      memberId: memberId,
      body: exitPlanBody(toolUseId: toolUseId, plan: '1. Do x.'),
    );

    await waitUntilWaiter(
      sessionId: sessionId,
      memberId: memberId,
      toolUseId: toolUseId,
    );
    expect(
      cubit.state.attentionFor(sessionId: sessionId, memberId: memberId),
      AgentSeatAttention.waiting,
    );

    expect(
      gate.complete(
        sessionId: sessionId,
        memberId: memberId,
        toolUseId: toolUseId,
        reply: const ExitPlanModeHookReply.allow(),
      ),
      isTrue,
    );

    final resp = await responseFuture.timeout(const Duration(seconds: 5));
    expect(resp.statusCode, HttpStatus.ok);
    final decoded = jsonDecode(await resp.transform(utf8.decoder).join());
    expect(decoded, isA<Map>());
    final hook = (decoded as Map)['hookSpecificOutput'] as Map;
    expect(hook['permissionDecision'], 'allow');
  });

  test('PreToolUse hold → deny → permissionDecision deny', () async {
    const sessionId = 'ep-s2';
    const memberId = 'm1';
    const toolUseId = 'toolu-ep-2';
    gateway.registerAgentStatusSession(sessionId: sessionId);

    final responseFuture = postExitPlan(
      sessionId: sessionId,
      memberId: memberId,
      body: exitPlanBody(toolUseId: toolUseId, plan: '1. Do y.'),
    );

    await waitUntilWaiter(
      sessionId: sessionId,
      memberId: memberId,
      toolUseId: toolUseId,
    );

    expect(
      gate.complete(
        sessionId: sessionId,
        memberId: memberId,
        toolUseId: toolUseId,
        reply: const ExitPlanModeHookReply.deny(),
      ),
      isTrue,
    );

    final resp = await responseFuture.timeout(const Duration(seconds: 5));
    expect(resp.statusCode, HttpStatus.ok);
    final decoded = jsonDecode(await resp.transform(utf8.decoder).join());
    final hook = (decoded as Map)['hookSpecificOutput'] as Map;
    expect(hook['permissionDecision'], 'deny');
  });

  test('ExitPlan without gate still returns empty 200 and keeps waiting',
      () async {
    final soloCubit = AgentAttentionCubit(pruneInterval: null);
    addTearDown(soloCubit.close);
    final soloGateway = TeammateBusMcpGateway();
    await soloGateway.ensureStarted();
    addTearDown(soloGateway.dispose);
    soloGateway.attachAgentStatusHandler(
      AgentStatusHttpHandler(
        attention: soloCubit,
        resolveCli: (_, __) => CliTool.claude,
        resolveSkipPermissions: (_, __) => false,
      ),
    );
    soloGateway.registerAgentStatusSession(sessionId: 'no-gate');

    final uri = Uri.parse(
      'http://127.0.0.1:${soloGateway.httpPort}/agent-status',
    );
    final req = await client.postUrl(uri);
    req.headers.set('content-type', 'application/json');
    req.headers.set('connection', 'close');
    req.headers.set(teammateBusMcpSessionHeader, 'no-gate');
    req.headers.set(teammateBusMcpMemberHeader, 'm1');
    req.add(
      utf8.encode(
        jsonEncode(exitPlanBody(toolUseId: 'toolu-x', plan: '1. Do z.')),
      ),
    );
    final resp = await req.close().timeout(const Duration(seconds: 5));
    expect(resp.statusCode, HttpStatus.ok);
    final text = await resp.transform(utf8.decoder).join();
    expect(jsonDecode(text), <String, Object?>{});
    expect(
      soloCubit.state.attentionFor(sessionId: 'no-gate', memberId: 'm1'),
      AgentSeatAttention.waiting,
    );
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/agent_status/agent_status_http_handler_exit_plan_test.dart -v`
Expected: 编译失败（`exitPlanModeHookGate` 参数不存在）。

- [ ] **Step 3: 实现 handler 分支**

Modify `client/lib/services/agent_status/agent_status_http_handler.dart`：

import 区新增：
```dart
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/capabilities/exit_plan_mode_capability.dart';
import 'exit_plan_mode.dart';
import 'exit_plan_mode_hook_gate.dart';
```
（注意本文件在 `lib/services/agent_status/`，`cli_tool_registry` 用相对路径 `../../services/cli/...`——即从 `agent_status/` 上两级到 `lib/` 再进 `services/cli/`。）

类头新增构造参数（在 `askUserHookGate` 参数后）：
```dart
    this.exitPlanModeHookGate,
    this.registry,
```
字段：
```dart
  final ExitPlanModeHookGate? exitPlanModeHookGate;
  final CliToolRegistry registry;
```
并在初始化列表给默认值：
```dart
  AgentStatusHttpHandler({
    required this.attention,
    required this.resolveCli,
    required this.resolveSkipPermissions,
    this.askUserHookGate,
    this.exitPlanModeHookGate,
    CliToolRegistry? registry,
  }) : registry = registry ?? CliToolRegistry.builtIn();
```

`handle()` 中，在 `_maybeAnswerAskUserQuestionHook` 判断后加（`if (answered) return;` 之后）：
```dart
            final answeredPlan = await _maybeAnswerExitPlanModeHook(
              request,
              sessionId: sessionId,
              memberId: memberId,
              event: event,
            );
            if (answeredPlan) return;
```

新增方法（`_maybeAnswerAskUserQuestionHook` 之后）：
```dart
  /// Returns true when the HTTP response was already written.
  ///
  /// Holds ExitPlanMode `PreToolUse` until the chat card approves/rejects,
  /// then returns the official `permissionDecision` allow/deny (TUI skipped).
  Future<bool> _maybeAnswerExitPlanModeHook(
    HttpRequest request, {
    required String sessionId,
    required String memberId,
    required AgentStatusEvent event,
  }) async {
    final gate = exitPlanModeHookGate;
    if (gate == null) return false;
    final hook = event.hookEventName?.trim() ?? '';
    if (hook != 'PreToolUse' || !isExitPlanModeTool(event.toolName)) {
      return false;
    }
    final hasPlan =
        (event.planText?.trim() ?? '').isNotEmpty ||
        (event.planFilePath?.trim() ?? '').isNotEmpty;
    if (!hasPlan) return false;
    final cli = resolveCli(sessionId, memberId);
    final capability = registry.capability<ExitPlanModeCapability>(cli);
    if (capability == null || !capability.supportsInChatApproval) return false;
    final toolUseId = event.toolUseId?.trim() ?? '';
    if (toolUseId.isEmpty) return false;

    final reply = await gate.wait(
      sessionId: sessionId,
      memberId: memberId,
      toolUseId: toolUseId,
    );
    if (reply == null) return false;

    if (reply.deny) {
      await _writeJson(request, {
        'hookSpecificOutput': {
          'hookEventName': 'PreToolUse',
          'permissionDecision': 'deny',
          'permissionDecisionReason': 'User rejected the plan',
        },
      });
      return true;
    }

    await _writeJson(request, {
      'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'allow',
      },
    });
    return true;
  }
```

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/services/agent_status/agent_status_http_handler_exit_plan_test.dart -v`
Expected: PASS (3 tests)。同时 `flutter test test/services/agent_status/agent_status_http_handler_ask_user_test.dart -v` 仍 PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/agent_status/agent_status_http_handler.dart \
        client/test/services/agent_status/agent_status_http_handler_exit_plan_test.dart
git commit -m "feat(agent-status): hold ExitPlanMode PreToolUse hook for allow/deny

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: ExitPlanModeApprovalService + ChatCubit approve/reject + dismissWaiting

**Files:**
- Create: `client/lib/services/terminal/exit_plan_mode_approval_service.dart`
- Modify: `client/lib/cubits/agent_attention_cubit.dart`、`client/lib/cubits/chat_cubit.dart`
- Test: `client/test/services/terminal/exit_plan_mode_approval_service_test.dart`、`client/test/cubits/chat_cubit_exit_plan_approval_test.dart`

**Interfaces:**
- Consumes: `ExitPlanModeHookGate`/`ExitPlanModeHookReply`（Task 2）。
- Produces: `sealed class ExitPlanApprovalResult` + `ExitPlanApprovalOk` / `ExitPlanApprovalFailed(reason)`；`ExitPlanModeApprovalService({ExitPlanModeHookGate? hookGate})` 带 `approve({sessionId, memberId, toolUseId})` / `reject(...)` 返回 `Future<ExitPlanApprovalResult>`；`AgentAttentionCubit.dismissWaiting({sessionId, memberId})`；`ChatCubit.approveExitPlanMode({sessionId, memberId, toolUseId})` / `rejectExitPlanMode(...)`。Task 7 卡片、Task 8 banner、Task 9 app_shell 使用。

- [ ] **Step 1: 写失败测试（service）**

`client/test/services/terminal/exit_plan_mode_approval_service_test.dart`：
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/exit_plan_mode_hook_gate.dart';
import 'package:teampilot/services/terminal/exit_plan_mode_approval_service.dart';

void main() {
  test('approve completes the held hook with allow', () async {
    final gate = ExitPlanModeHookGate();
    final held = gate.wait(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't1',
      timeout: const Duration(hours: 1),
    );
    final service = ExitPlanModeApprovalService(hookGate: gate);

    final result = await service.approve(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't1',
    );

    expect(result, isA<ExitPlanApprovalOk>());
    final reply = await held;
    expect(reply?.deny, isFalse);
  });

  test('reject completes the held hook with deny', () async {
    final gate = ExitPlanModeHookGate();
    final held = gate.wait(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't2',
      timeout: const Duration(hours: 1),
    );
    final service = ExitPlanModeApprovalService(hookGate: gate);

    final result = await service.reject(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 't2',
    );

    expect(result, isA<ExitPlanApprovalOk>());
    final reply = await held;
    expect(reply?.deny, isTrue);
  });

  test('no waiter → Failed', () async {
    final gate = ExitPlanModeHookGate();
    final service = ExitPlanModeApprovalService(hookGate: gate);
    final result = await service.approve(
      sessionId: 's',
      memberId: 'm',
      toolUseId: 'nope',
    );
    expect(result, isA<ExitPlanApprovalFailed>());
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/terminal/exit_plan_mode_approval_service_test.dart -v`
Expected: 编译失败（文件不存在）。

- [ ] **Step 3: 实现 service**

Create `client/lib/services/terminal/exit_plan_mode_approval_service.dart`：
```dart
import '../agent_status/exit_plan_mode_hook_gate.dart';

sealed class ExitPlanApprovalResult {
  const ExitPlanApprovalResult();
}

final class ExitPlanApprovalOk extends ExitPlanApprovalResult {
  const ExitPlanApprovalOk();
}

final class ExitPlanApprovalFailed extends ExitPlanApprovalResult {
  const ExitPlanApprovalFailed(this.reason);
  final String reason;
}

/// Completes a held Claude-family ExitPlanMode `PreToolUse` hook with the
/// official allow/deny decision from the chat card.
final class ExitPlanModeApprovalService {
  ExitPlanModeApprovalService({ExitPlanModeHookGate? hookGate})
    : _hookGate = hookGate;

  final ExitPlanModeHookGate? _hookGate;

  Future<ExitPlanApprovalResult> approve({
    required String sessionId,
    required String memberId,
    required String toolUseId,
  }) => _complete(
    sessionId: sessionId,
    memberId: memberId,
    toolUseId: toolUseId,
    reply: const ExitPlanModeHookReply.allow(),
  );

  Future<ExitPlanApprovalResult> reject({
    required String sessionId,
    required String memberId,
    required String toolUseId,
  }) => _complete(
    sessionId: sessionId,
    memberId: memberId,
    toolUseId: toolUseId,
    reply: const ExitPlanModeHookReply.deny(),
  );

  Future<ExitPlanApprovalResult> _complete({
    required String sessionId,
    required String memberId,
    required String toolUseId,
    required ExitPlanModeHookReply reply,
  }) async {
    final gate = _hookGate;
    final id = toolUseId.trim();
    if (gate == null || id.isEmpty) {
      return const ExitPlanApprovalFailed('no_pending_approval');
    }
    final ok = gate.complete(
      sessionId: sessionId,
      memberId: memberId,
      toolUseId: id,
      reply: reply,
    );
    return ok
        ? const ExitPlanApprovalOk()
        : const ExitPlanApprovalFailed('no_pending_approval');
  }
}
```

- [ ] **Step 4: 实现 dismissWaiting**

Modify `client/lib/cubits/agent_attention_cubit.dart`，在 `markAskAnswered` 之后加：
```dart
  /// Optimistically drop a waiting seat back to working (plan approved /
  /// rejected) while retaining [AgentSeatAttentionEntry.lastEvent].
  void dismissWaiting({required String sessionId, required String memberId}) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    final existing = state.seats[key];
    if (existing == null || existing.attention != AgentSeatAttention.waiting) {
      return;
    }
    final seats = Map<String, AgentSeatAttentionEntry>.of(state.seats);
    seats[key] = AgentSeatAttentionEntry(
      attention: AgentSeatAttention.working,
      updatedAt: _clock(),
      lastEvent: existing.lastEvent,
    );
    emit(AgentAttentionState(seats: seats, clock: _clock));
  }
```

- [ ] **Step 5: 实现 ChatCubit 方法**

Modify `client/lib/cubits/chat_cubit.dart`：

import 区加：
```dart
import '../services/agent_status/exit_plan_mode_hook_gate.dart';
import '../services/terminal/exit_plan_mode_approval_service.dart';
```

构造参数（`askUserQuestionAnswerService` 参数后）：
```dart
    ExitPlanModeApprovalService? exitPlanApprovalService,
```
初始化列表字段（`_askUserAnswer = ...` 前）：
```dart
       _exitPlanApproval = exitPlanApprovalService ?? ExitPlanModeApprovalService(),
```
字段声明（`_askUserAnswer` 附近）：
```dart
  late final ExitPlanModeApprovalService _exitPlanApproval;
```

在 `cancelAskUserQuestion` 之后加两个方法：
```dart
  /// Approves the pending Claude `ExitPlanMode` plan from the chat card
  /// (completes the held PreToolUse hook with allow). On success,
  /// optimistically dismisses the waiting attention.
  Future<ExitPlanApprovalResult> approveExitPlanMode({
    required String sessionId,
    required String memberId,
    required String toolUseId,
  }) async {
    final result = await _exitPlanApproval.approve(
      sessionId: sessionId,
      memberId: memberId,
      toolUseId: toolUseId,
    );
    if (result is ExitPlanApprovalOk) {
      _agentAttentionCubit?.dismissWaiting(
        sessionId: sessionId,
        memberId: memberId,
      );
    }
    return result;
  }

  /// Rejects the pending Claude `ExitPlanMode` plan (keeps the agent in plan
  /// mode). On success, optimistically dismisses the waiting attention.
  Future<ExitPlanApprovalResult> rejectExitPlanMode({
    required String sessionId,
    required String memberId,
    required String toolUseId,
  }) async {
    final result = await _exitPlanApproval.reject(
      sessionId: sessionId,
      memberId: memberId,
      toolUseId: toolUseId,
    );
    if (result is ExitPlanApprovalOk) {
      _agentAttentionCubit?.dismissWaiting(
        sessionId: sessionId,
        memberId: memberId,
      );
    }
    return result;
  }
```

- [ ] **Step 6: 写失败测试（cubit）**

`client/test/cubits/chat_cubit_exit_plan_approval_test.dart`（仿 `chat_cubit_ask_user_answer_test.dart` 结构）：
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/agent_status/exit_plan_mode_hook_gate.dart';
import 'package:teampilot/services/terminal/exit_plan_mode_approval_service.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('ChatCubit exit-plan approve/reject', () {
    late AgentAttentionCubit attention;
    late ExitPlanModeHookGate gate;

    setUp(() {
      attention = AgentAttentionCubit(pruneInterval: null);
      gate = ExitPlanModeHookGate();
    });

    tearDown(() async {
      await attention.close();
    });

    ChatCubit _buildCubit() {
      return ChatCubit(
        executableResolver: () => '/bin/true',
        automationRepository: testAutomationRepository(),
        agentAttentionCubit: attention,
        exitPlanApprovalService: ExitPlanModeApprovalService(hookGate: gate),
      );
    }

    void _seedWaitingTab(ChatCubit cubit, {required String sessionId}) {
      final tab = ChatTab(
        info: ChatTabInfo(id: sessionId, title: sessionId, subtitle: ''),
        cliTeamName: sessionId,
        selectedMemberId: sessionId,
      );
      cubit.tabStore.append(tab);
      cubit.refreshActiveWorkspaceTabs();
      attention.applyEvent(
        sessionId: sessionId,
        memberId: sessionId,
        event: AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          toolName: 'ExitPlanMode',
          toolUseId: 'toolu-plan-1',
          planText: '1. Do x.',
        ),
        skipPermissions: false,
      );
    }

    test('approve completes gate and dismisses waiting', () async {
      final held = gate.wait(
        sessionId: 'sess-ep',
        memberId: 'sess-ep',
        toolUseId: 'toolu-plan-1',
        timeout: const Duration(hours: 1),
      );
      final cubit = _buildCubit();
      addTearDown(cubit.close);
      const sessionId = 'sess-ep';
      _seedWaitingTab(cubit, sessionId: sessionId);

      final result = await cubit.approveExitPlanMode(
        sessionId: sessionId,
        memberId: sessionId,
        toolUseId: 'toolu-plan-1',
      );

      expect(result, isA<ExitPlanApprovalOk>());
      expect((await held)?.deny, isFalse);
      final entry = attention.state.entryFor(
        sessionId: sessionId,
        memberId: sessionId,
      );
      expect(entry?.attention, AgentSeatAttention.working);
    });

    test('reject completes gate with deny and dismisses waiting', () async {
      final held = gate.wait(
        sessionId: 'sess-ep2',
        memberId: 'sess-ep2',
        toolUseId: 'toolu-plan-2',
        timeout: const Duration(hours: 1),
      );
      final cubit = _buildCubit();
      addTearDown(cubit.close);
      const sessionId = 'sess-ep2';
      _seedWaitingTab(cubit, sessionId: sessionId);

      final result = await cubit.rejectExitPlanMode(
        sessionId: sessionId,
        memberId: sessionId,
        toolUseId: 'toolu-plan-2',
      );

      expect(result, isA<ExitPlanApprovalOk>());
      expect((await held)?.deny, isTrue);
      final entry = attention.state.entryFor(
        sessionId: sessionId,
        memberId: sessionId,
      );
      expect(entry?.attention, AgentSeatAttention.working);
    });

    test('failed approval does not dismiss waiting', () async {
      final cubit = _buildCubit();
      addTearDown(cubit.close);
      const sessionId = 'sess-ep3';
      _seedWaitingTab(cubit, sessionId: sessionId);

      final result = await cubit.approveExitPlanMode(
        sessionId: sessionId,
        memberId: sessionId,
        toolUseId: 'no-such-tool-use',
      );

      expect(result, isA<ExitPlanApprovalFailed>());
      final entry = attention.state.entryFor(
        sessionId: sessionId,
        memberId: sessionId,
      );
      expect(entry?.attention, AgentSeatAttention.waiting);
    });
  });
}
```

- [ ] **Step 7: 运行确认通过**

Run: `cd client && flutter test test/services/terminal/exit_plan_mode_approval_service_test.dart test/cubits/chat_cubit_exit_plan_approval_test.dart -v`
Expected: PASS (6 tests)。

- [ ] **Step 8: Commit**

```bash
git add client/lib/services/terminal/exit_plan_mode_approval_service.dart \
        client/lib/cubits/agent_attention_cubit.dart \
        client/lib/cubits/chat_cubit.dart \
        client/test/services/terminal/exit_plan_mode_approval_service_test.dart \
        client/test/cubits/chat_cubit_exit_plan_approval_test.dart
git commit -m "feat(chat): approve/reject ExitPlanMode from the chat card

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: preserveExitPlanModePayload 保留 toolUseId

**Files:**
- Modify: `client/lib/services/agent_status/exit_plan_mode.dart`
- Test: `client/test/services/agent_status/exit_plan_mode_test.dart`（新建）

**Interfaces:**
- Produces: `preserveExitPlanModePayload` 现在在保留 plan 载荷时也保留 `toolUseId`（next 为空时取 previous），使卡片能用 PreToolUse 的 `tool_use_id` 关联挂起的 hook。Task 7/8 依赖此。

- [ ] **Step 1: 写失败测试**

`client/test/services/agent_status/exit_plan_mode_test.dart`：
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/agent_status/exit_plan_mode.dart';

void main() {
  test('preserves plan payload and toolUseId across a later waiting hook',
      () {
    const previous = AgentStatusEvent(
      state: AgentSeatAttention.waiting,
      toolName: 'ExitPlanMode',
      toolUseId: 'toolu-plan-1',
      planText: '1. Do x.',
      planFilePath: '/tmp/plan.md',
    );
    const next = AgentStatusEvent(state: AgentSeatAttention.waiting);
    final effective = preserveExitPlanModePayload(previous, next);
    expect(effective.planText, '1. Do x.');
    expect(effective.planFilePath, '/tmp/plan.md');
    expect(effective.toolUseId, 'toolu-plan-1');
  });

  test('does not preserve across a non-waiting event', () {
    const previous = AgentStatusEvent(
      state: AgentSeatAttention.waiting,
      toolName: 'ExitPlanMode',
      toolUseId: 'toolu-plan-2',
      planText: '1. Do x.',
    );
    const next = AgentStatusEvent(
      state: AgentSeatAttention.working,
      toolName: 'PostToolUse',
    );
    final effective = preserveExitPlanModePayload(previous, next);
    expect(effective.planText, isNull);
    expect(effective.toolUseId, isNull);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/agent_status/exit_plan_mode_test.dart -v`
Expected: 第一个用例失败（`effective.toolUseId` 为 null 而期望 `toolu-plan-1`）。

- [ ] **Step 3: 实现**

Modify `client/lib/services/agent_status/exit_plan_mode.dart` 中 `preserveExitPlanModePayload` 的 `copyWith` 调用：
```dart
  return next.copyWith(
    planText: previous.planText,
    planFilePath: previous.planFilePath,
    toolUseId: next.toolUseId ?? previous.toolUseId,
  );
```

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/services/agent_status/exit_plan_mode_test.dart -v`
Expected: PASS (2 tests)。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/agent_status/exit_plan_mode.dart \
        client/test/services/agent_status/exit_plan_mode_test.dart
git commit -m "fix(agent-status): preserve ExitPlanMode toolUseId across waiting hooks

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: l10n 键 + AppKeys

**Files:**
- Modify: `client/lib/l10n/app_en.arb`、`client/lib/l10n/app_zh.arb`、`client/lib/utils/ui/app_keys.dart`
- Regenerate: `cd client && flutter gen-l10n`

**Interfaces:**
- Produces: l10n getters `exitPlanModeTitle`、`exitPlanModeApprove`、`exitPlanModeReject`、`exitPlanModeCopyPlan`、`exitPlanModeExpand`、`exitPlanModeCollapse`、`exitPlanModeOpenPlanFile`、`exitPlanModeApproveFailed`、`exitPlanModeRejectFailed`；AppKeys：`exitPlanModeApproveButton`、`exitPlanModeRejectButton`、`exitPlanModeCopyPlanButton`、`exitPlanModeExpandButton`、`exitPlanModeOpenPlanFileButton`、`exitPlanModeInlineError`。Task 7 使用。

- [ ] **Step 1: 编辑 app_en.arb**

在 `agentPermissionOpenTerminal` 键后加（值必须是合法的 JSON 字符串，注意转义）：
```json
  "exitPlanModeTitle": "Plan ready for approval",
  "exitPlanModeApprove": "Approve",
  "exitPlanModeReject": "Reject",
  "exitPlanModeCopyPlan": "Copy plan",
  "exitPlanModeExpand": "Expand",
  "exitPlanModeCollapse": "Collapse",
  "exitPlanModeOpenPlanFile": "Open plan file",
  "exitPlanModeApproveFailed": "Couldn't approve the plan",
  "exitPlanModeRejectFailed": "Couldn't reject the plan"
```

- [ ] **Step 2: 编辑 app_zh.arb**

同样位置加：
```json
  "exitPlanModeTitle": "计划已就绪，等待批准",
  "exitPlanModeApprove": "批准",
  "exitPlanModeReject": "拒绝",
  "exitPlanModeCopyPlan": "复制计划",
  "exitPlanModeExpand": "展开",
  "exitPlanModeCollapse": "收起",
  "exitPlanModeOpenPlanFile": "打开计划文件",
  "exitPlanModeApproveFailed": "批准计划失败",
  "exitPlanModeRejectFailed": "拒绝计划失败"
```

- [ ] **Step 3: 加 AppKeys**

Modify `client/lib/utils/ui/app_keys.dart`，在 `askUserQuestionInlineError` 键后加：
```dart
  static const exitPlanModeApproveButton = Key('exit-plan-mode-approve-button');
  static const exitPlanModeRejectButton = Key('exit-plan-mode-reject-button');
  static const exitPlanModeCopyPlanButton = Key(
    'exit-plan-mode-copy-plan-button',
  );
  static const exitPlanModeExpandButton = Key('exit-plan-mode-expand-button');
  static const exitPlanModeOpenPlanFileButton = Key(
    'exit-plan-mode-open-plan-file-button',
  );
  static const exitPlanModeInlineError = Key('exit-plan-mode-inline-error');
```

- [ ] **Step 4: 重新生成 + 验证**

Run: `cd client && flutter gen-l10n && grep -c "exitPlanModeTitle" lib/l10n/app_localizations.dart`
Expected: 输出 >= 1（getter 已生成）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
        client/lib/l10n/app_localizations.dart \
        client/lib/utils/ui/app_keys.dart
git commit -m "feat(l10n): ExitPlanMode card strings + keys

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: ExitPlanModeCard 全面优化

**Files:**
- Modify: `client/lib/pages/chat/exit_plan_mode_card.dart`
- Test: `client/test/pages/chat/exit_plan_mode_card_test.dart`（整文件重写）

**Interfaces:**
- Consumes: `ExitPlanApprovalResult`/`ExitPlanApprovalFailed`（Task 4）、`ChatCubit`（banner 传入回调）、l10n（Task 6）、`tp_markdown`、`buildAppMarkdownTokens`、`AppKeys`。
- Produces: `ExitPlanModeCard({required String planText, String? planFilePath, Future<ExitPlanApprovalResult> Function()? onApprove, Future<ExitPlanApprovalResult> Function()? onReject, required VoidCallback onOpenTerminal, required ValueChanged<String> onOpenPlanFile})`。`onApprove`/`onReject` 为 null 时渲染「打开终端」主按钮；非 null 时渲染「拒绝(ghost)」「批准(primary)」+ 终端窥视图标。Task 8 构造。

- [ ] **Step 1: 重写卡片**

Modify `client/lib/pages/chat/exit_plan_mode_card.dart`（整体替换）：
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:tp_markdown/tp_markdown.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/terminal/exit_plan_mode_approval_service.dart';
import '../../theme/app_markdown_style_sheet.dart';
import '../../utils/ui/app_keys.dart';

/// Chat card for Claude `ExitPlanMode`: Markdown plan, expand/collapse, copy,
/// clickable plan file, and (when [onApprove]/[onReject] are provided) an
/// in-chat Approve / Reject footer.
class ExitPlanModeCard extends StatefulWidget {
  const ExitPlanModeCard({
    required this.planText,
    this.planFilePath,
    this.onApprove,
    this.onReject,
    required this.onOpenTerminal,
    required this.onOpenPlanFile,
    super.key,
  });

  final String planText;
  final String? planFilePath;

  /// When both are non-null, the card renders in-chat Approve / Reject.
  final Future<ExitPlanApprovalResult> Function()? onApprove;
  final Future<ExitPlanApprovalResult> Function()? onReject;
  final VoidCallback onOpenTerminal;
  final ValueChanged<String> onOpenPlanFile;

  @override
  State<ExitPlanModeCard> createState() => _ExitPlanModeCardState();
}

class _ExitPlanModeCardState extends State<ExitPlanModeCard> {
  var _expanded = false;
  var _approving = false;
  String? _inlineError;

  bool get _canApprove =>
      widget.onApprove != null && widget.onReject != null;

  Future<void> _approve() => _submit(widget.onApprove, approve: true);

  Future<void> _reject() => _submit(widget.onReject, approve: false);

  Future<void> _submit(
    Future<ExitPlanApprovalResult> Function()? action, {
    required bool approve,
  }) async {
    if (action == null || _approving) return;
    setState(() {
      _approving = true;
      _inlineError = null;
    });
    final result = await action();
    if (!mounted) return;
    if (result is ExitPlanApprovalFailed) {
      setState(() {
        _approving = false;
        _inlineError = approve
            ? context.l10n.exitPlanModeApproveFailed
            : context.l10n.exitPlanModeRejectFailed;
      });
    } else {
      setState(() => _approving = false);
    }
  }

  Future<void> _copyPlan() async {
    await Clipboard.setData(ClipboardData(text: widget.planText));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final radius = TpTheme.of(context).control.radius;
    final path = widget.planFilePath?.trim() ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Material(
        key: AppKeys.exitPlanModeCard,
        elevation: 2,
        shadowColor: cs.shadow.withValues(alpha: 0.28),
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.md,
            spacing.sm,
            spacing.sm,
            spacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.fact_check_rounded, size: 16, color: cs.tertiary),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Text(
                      l10n.exitPlanModeTitle,
                      style: styles.smColored(cs.onSurface),
                    ),
                  ),
                  TpIconButton(
                    key: AppKeys.exitPlanModeCopyPlanButton,
                    icon: Icons.copy_rounded,
                    tooltip: l10n.exitPlanModeCopyPlan,
                    compact: true,
                    size: TpIconButton.kCompactSize,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                    borderRadius: radius,
                    onTap: widget.planText.isEmpty ? null : _copyPlan,
                  ),
                ],
              ),
              if (widget.planText.isNotEmpty) ...[
                SizedBox(height: spacing.sm),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  child: Container(
                    constraints: _expanded
                        ? null
                        : const BoxConstraints(maxHeight: 160),
                    padding: EdgeInsets.all(spacing.sm),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(radius),
                    ),
                    child: SingleChildScrollView(
                      child: MarkdownView(
                        document: compileMarkdown(widget.planText),
                        tokens: buildAppMarkdownTokens(
                          Theme.of(context),
                          MarkdownProfile.compact,
                          width: MediaQuery.sizeOf(context).width,
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: AppKeys.exitPlanModeExpandButton,
                    onPressed: () =>
                        setState(() => _expanded = !_expanded),
                    child: Text(
                      _expanded
                          ? l10n.exitPlanModeCollapse
                          : l10n.exitPlanModeExpand,
                    ),
                  ),
                ),
              ],
              if (path.isNotEmpty) ...[
                SizedBox(height: spacing.sm),
                TpHover(
                  borderRadius: BorderRadius.circular(radius),
                  onTap: () => widget.onOpenPlanFile(path),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.xs,
                      vertical: spacing.xs,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 14,
                          color: cs.onSurfaceVariant,
                        ),
                        SizedBox(width: spacing.xs),
                        Expanded(
                          child: Text(
                            path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: styles.xsColored(cs.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_inlineError != null) ...[
                SizedBox(height: spacing.sm),
                Text(
                  _inlineError!,
                  key: AppKeys.exitPlanModeInlineError,
                  style: styles.smColored(cs.error),
                ),
              ],
              SizedBox(height: spacing.sm),
              if (_canApprove) ...[
                Row(
                  children: [
                    TpIconButton(
                      key: AppKeys.agentPermissionOpenTerminalButton,
                      icon: Icons.terminal_rounded,
                      tooltip: l10n.agentPermissionOpenTerminal,
                      compact: true,
                      size: TpIconButton.kCompactSize,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                      borderRadius: radius,
                      onTap: widget.onOpenTerminal,
                    ),
                    const Spacer(),
                    TpButton(
                      key: AppKeys.exitPlanModeRejectButton,
                      variant: TpButtonVariant.ghost,
                      size: TpControlSize.small,
                      onPressed: _approving ? null : _reject,
                      child: Text(l10n.exitPlanModeReject),
                    ),
                    SizedBox(width: spacing.sm),
                    TpButton(
                      key: AppKeys.exitPlanModeApproveButton,
                      variant: TpButtonVariant.primary,
                      size: TpControlSize.small,
                      onPressed: _approving ? null : _approve,
                      child: Text(l10n.exitPlanModeApprove),
                    ),
                  ],
                ),
              ] else ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TpButton(
                    key: AppKeys.agentPermissionOpenTerminalButton,
                    variant: TpButtonVariant.primary,
                    size: TpControlSize.small,
                    onPressed: widget.onOpenTerminal,
                    child: Text(l10n.agentPermissionOpenTerminal),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 重写 widget 测试**

`client/test/pages/chat/exit_plan_mode_card_test.dart`（整体替换）：
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/exit_plan_mode_card.dart';
import 'package:teampilot/services/terminal/exit_plan_mode_approval_service.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';
import 'package:tp_markdown/tp_markdown.dart';

Widget _wrap(Widget child) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('renders markdown plan and opens terminal', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      _wrap(
        ExitPlanModeCard(
          planText: '1. Refactor the launcher.\n2. Add tests.',
          planFilePath: '/tmp/plan.md',
          onOpenTerminal: () => opened = true,
          onOpenPlanFile: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.exitPlanModeCard), findsOneWidget);
    expect(find.byType(MarkdownView), findsOneWidget);
    expect(find.text('/tmp/plan.md'), findsOneWidget);
    // No in-chat approve → primary Open Terminal.
    expect(
      find.byKey(AppKeys.exitPlanModeApproveButton),
      findsNothing,
    );

    await tester.tap(find.byKey(AppKeys.agentPermissionOpenTerminalButton));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('expand/collapse toggles', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ExitPlanModeCard(
          planText: 'Long plan text here.',
          onOpenTerminal: () {},
          onOpenPlanFile: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.exitPlanModeExpandButton), findsOneWidget);
    expect(find.text('Expand'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.exitPlanModeExpandButton));
    await tester.pumpAndSettle();
    expect(find.text('Collapse'), findsOneWidget);
  });

  testWidgets('copy button copies plan text', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      _wrap(
        ExitPlanModeCard(
          planText: 'Copy me',
          onOpenTerminal: () {},
          onOpenPlanFile: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.exitPlanModeCopyPlanButton));
    await tester.pumpAndSettle();
    expect(copied, ['Copy me']);
  });

  testWidgets('plan file path tap calls onOpenPlanFile', (tester) async {
    String? openedPath;
    await tester.pumpWidget(
      _wrap(
        ExitPlanModeCard(
          planText: 'plan',
          planFilePath: '/tmp/plan.md',
          onOpenTerminal: () {},
          onOpenPlanFile: (p) => openedPath = p,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('/tmp/plan.md'));
    await tester.pumpAndSettle();
    expect(openedPath, '/tmp/plan.md');
  });

  testWidgets('in-chat approve/reject visible and approve shows error',
      (tester) async {
    var approved = false;
    await tester.pumpWidget(
      _wrap(
        ExitPlanModeCard(
          planText: 'plan',
          onApprove: () async {
            approved = true;
            return const ExitPlanApprovalFailed('no_pending_approval');
          },
          onReject: () async => const ExitPlanApprovalOk(),
          onOpenTerminal: () {},
          onOpenPlanFile: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.exitPlanModeApproveButton), findsOneWidget);
    expect(find.byKey(AppKeys.exitPlanModeRejectButton), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.exitPlanModeApproveButton));
    await tester.pumpAndSettle();
    expect(approved, isTrue);
    expect(find.byKey(AppKeys.exitPlanModeInlineError), findsOneWidget);
  });
}
```

- [ ] **Step 3: 运行确认通过**

Run: `cd client && flutter test test/pages/chat/exit_plan_mode_card_test.dart -v`
Expected: PASS (5 tests)。若 `MarkdownView` 在窄 Scaffold 下断言 `find.byType(MarkdownView)` 失败（未渲染），改用 `find.byType(SingleChildScrollView)` 断言并在卡片约束下确认（实现内 MarkdownView 始终构造，`compileMarkdown` 非空即渲染）。

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/chat/exit_plan_mode_card.dart \
        client/test/pages/chat/exit_plan_mode_card_test.dart
git commit -m "feat(chat): Markdown ExitPlanMode card with expand/copy/path/approve

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: Banner 接线

**Files:**
- Modify: `client/lib/pages/chat/agent_permission_attention_banner.dart`

**Interfaces:**
- Consumes: `ExitPlanModeCapability`（Task 1）、`ExitPlanModeCard` 新签名（Task 7）、`WorkbenchEditorOpener.openFile`、`filesystemForComposeAtFileOpen`（`services/compose/compose_at_file_refs.dart`）。
- Produces: banner 在 `isExitPlanModeTool` 分支解析 capability，传 `onApprove`/`onReject`（经 `ChatCubit.approveExitPlanMode/rejectExitPlanMode`）、`onOpenPlanFile` 给卡片。

- [ ] **Step 1: 实现**

Modify `client/lib/pages/chat/agent_permission_attention_banner.dart`：

import 区加：
```dart
import 'dart:async';

import '../../services/cli/registry/capabilities/exit_plan_mode_capability.dart';
import '../../services/compose/compose_at_file_refs.dart';
import '../../services/workbench/workbench_editor_opener.dart';
```

在 `ExitPlanModeCard(...)` 分支（`isExitPlanModeTool(lastEvent?.toolName)` 处）替换为：
```dart
    final lastEvent = entry.lastEvent;
    final planText = lastEvent?.planText?.trim() ?? '';
    final planFilePath = lastEvent?.planFilePath?.trim() ?? '';
    if (isExitPlanModeTool(lastEvent?.toolName) &&
        (planText.isNotEmpty || planFilePath.isNotEmpty)) {
      final exitPlanCapability =
          registry.capability<ExitPlanModeCapability>(lockedCli);
      final supportsInChatApproval =
          exitPlanCapability?.supportsInChatApproval ?? false;
      final toolUseId = lastEvent?.toolUseId?.trim() ?? '';
      return ExitPlanModeCard(
        planText: planText,
        planFilePath: planFilePath.isEmpty ? null : planFilePath,
        onApprove: supportsInChatApproval
            ? () => context.read<ChatCubit>().approveExitPlanMode(
                  sessionId: sessionId,
                  memberId: seatId,
                  toolUseId: toolUseId,
                )
            : null,
        onReject: supportsInChatApproval
            ? () => context.read<ChatCubit>().rejectExitPlanMode(
                  sessionId: sessionId,
                  memberId: seatId,
                  toolUseId: toolUseId,
                )
            : null,
        onOpenTerminal: () => _openTerminal(
          context,
          sessionId: sessionId,
          seatId: seatId,
          selectedMemberId: selectedMemberId,
        ),
        onOpenPlanFile: (path) {
          unawaited(
            context.read<WorkbenchEditorOpener>().openFile(
                  session.workspaceId,
                  path,
                  preview: true,
                  fs: filesystemForComposeAtFileOpen(path),
                ),
          );
        },
      );
    }
```

> 注意：原代码里 `final lastEvent = entry.lastEvent;` 已在 `_openTerminal` 调用前声明；替换分支时保留该声明，仅替换 `ExitPlanModeCard(...)` 构造块。

- [ ] **Step 2: 运行确认通过**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error。

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/chat/agent_permission_attention_banner.dart
git commit -m "feat(chat): wire ExitPlanMode card in-chat approval + plan file open

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: app_shell 布线

**Files:**
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Consumes: `ExitPlanModeHookGate`（Task 2）、`ExitPlanModeApprovalService`（Task 4）。
- Produces: 单例 gate + service，注入 `AgentStatusHttpHandler(...)` 与 `ChatCubit(...)`。

- [ ] **Step 1: 实现**

Modify `client/lib/app/app_shell.dart`：

在 `final askUserQuestionHookGate = AskUserQuestionHookGate();`（约 1127 行）后加：
```dart
  final exitPlanModeHookGate = ExitPlanModeHookGate();
  final exitPlanModeApprovalService = ExitPlanModeApprovalService(
    hookGate: exitPlanModeHookGate,
  );
```

`AgentStatusHttpHandler(...)` 构造（`askUserHookGate: askUserQuestionHookGate,` 后）加：
```dart
      exitPlanModeHookGate: exitPlanModeHookGate,
```

`ChatCubit(...)` 构造（`askUserQuestionAnswerService: askUserQuestionAnswerService,` 后）加：
```dart
    exitPlanApprovalService: exitPlanModeApprovalService,
```

确保 import 存在：
```dart
import '../services/agent_status/exit_plan_mode_hook_gate.dart';
import '../services/terminal/exit_plan_mode_approval_service.dart';
```

- [ ] **Step 2: 运行确认通过**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error。

- [ ] **Step 3: Commit**

```bash
git add client/lib/app/app_shell.dart
git commit -m "feat(app): wire ExitPlanMode hook gate + approval service

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:** §3 卡片（Task 7）、§4.1 capability（Task 1）、§4.2 gate（Task 2）、§4.3 handler（Task 3）、§4.4 service（Task 4）、§4.5 cubit（Task 4 + Task 9）、§4.6 toolUseId（Task 5）、§4.7 banner（Task 8）、§6 错误处理（Task 4/7）、§7 测试（各任务）、§8 验证。§5 实验结论驱动 cursor 排除——无需代码改动。

**Placeholder scan:** 所有步骤含完整代码，无 TBD/TODO。

**Type consistency:** `ExitPlanApprovalResult`/`Ok`/`Failed` 一致；`supportsInChatApproval`/`approvalKind`/`ExitPlanApprovalKind` 一致；`ExitPlanModeHookReply.allow()/.deny()` 与 `deny` bool 一致；`dismissWaiting`/`approveExitPlanMode`/`rejectExitPlanMode` 签名一致。

## 执行收尾

全量验证：
```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```
手动验证见 spec §8。
