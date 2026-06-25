# Mixed Team Claude Bus Integration Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a three-tier integration test stack (mock Anthropic package → fast bus ping/pong → full ChatCubit + real Claude PTY) that proves two Claude members in mixed mode exchange messages through the production launch path and teammate-bus MCP.

**Architecture:** Standalone `tools/mock_anthropic` package with declarative Scenario DSL and shared `ping_pong_mixed_claude` script. L1-fast test drives the same scenario via HTTP MCP clients against a real `TeammateBusMcpServer`. L2-full test runs `ChatCubit.openSessionTab` with real PTY, mock API via `ANTHROPIC_BASE_URL`, forced HTTP teammate-bus (`TEAMPILOT_BUS_BRIDGE` dead path). Assertions poll bus mail jsonl only — transport-agnostic.

**Tech Stack:** Dart 3, Flutter test, `dart:io` HttpServer, existing TeamPilot ChatCubit / SessionLifecycleService / TerminalSession / TeammateBusMcpServer.

**Design authority:** [docs/superpowers/specs/2026-06-25-mixed-team-claude-bus-integration-design.md](../specs/2026-06-25-mixed-team-claude-bus-integration-design.md)

## Global Constraints

- **零兼容、最优终态** — 不保留旧 test/support 内联 mock；新 infrastructure 在 `tools/mock_anthropic`。
- L0 + L1 必须在无 `claude` 无 PTY 环境可跑（`flutter test --exclude-tags integration` 包含 L0；L1 带 `integration` tag）。
- L2 需要 Linux PTY + `claude` on PATH；不进 default CI verify。
- 完成判据：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` 全绿；L1/L2 本地手动验证通过。
- 每 Task ≥1 commit。

## File Structure

| 文件 | 职责 | 动作 |
|------|------|------|
| `tools/mock_anthropic/pubspec.yaml` | 独立包 manifest | 新增 |
| `tools/mock_anthropic/lib/scenario.dart` | `MockTurn`, `MockScenario`, `ScenarioRegistry` | 新增 |
| `tools/mock_anthropic/lib/sse/anthropic_sse_encoder.dart` | SSE streaming 编码 | 新增 |
| `tools/mock_anthropic/lib/server.dart` | `MockAnthropicServer` | 新增 |
| `tools/mock_anthropic/lib/scenarios/ping_pong_mixed_claude.dart` | 共享 ping/pong 剧本 | 新增 |
| `tools/mock_anthropic/bin/mock_anthropic.dart` | 调试 CLI | 新增 |
| `tools/mock_anthropic/test/sse_encoder_test.dart` | L0 | 新增 |
| `tools/mock_anthropic/test/scenario_test.dart` | L0 | 新增 |
| `tools/mock_anthropic/test/server_test.dart` | L0 HTTP | 新增 |
| `client/pubspec.yaml` | path dev_dependency | 改 |
| `client/test/integration/support/bus_mail_assertions.dart` | jsonl poll | 新增 |
| `client/test/integration/support/mixed_team_integration_harness.dart` | providers + orchestration helpers | 新增 |
| `client/test/integration/support/teammate_bus_http_client.dart` | L1 MCP 客户端 | 新增 |
| `client/test/integration/mixed_team_bus_ping_pong_integration_test.dart` | L1-fast | 新增 |
| `client/test/integration/mixed_team_claude_bus_integration_test.dart` | L2-full | 新增 |
| `docs/DEVELOPMENT.md` | 运行命令 | 改 |

---

### Task 1: Scaffold `tools/mock_anthropic` package

**Files:**
- Create: `tools/mock_anthropic/pubspec.yaml`
- Create: `tools/mock_anthropic/analysis_options.yaml` (copy minimal from `tools/teammate_bus_bridge/`)
- Create: `tools/mock_anthropic/.gitignore`

- [ ] **Step 1: Create pubspec**

```yaml
name: mock_anthropic
description: Mock Anthropic Messages API server for TeamPilot integration tests
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.7.0

dev_dependencies:
  test: ^1.25.0
  lints: ^5.0.0
```

- [ ] **Step 2: Verify package resolves**

Run: `cd tools/mock_anthropic && dart pub get`
Expected: success

- [ ] **Step 3: Commit**

```bash
git add tools/mock_anthropic/pubspec.yaml tools/mock_anthropic/analysis_options.yaml tools/mock_anthropic/.gitignore
git commit -m "chore: scaffold mock_anthropic tool package"
```

---

### Task 2: Scenario DSL + ping/pong scenario

**Files:**
- Create: `tools/mock_anthropic/lib/scenario.dart`
- Create: `tools/mock_anthropic/lib/scenarios/ping_pong_mixed_claude.dart`
- Test: `tools/mock_anthropic/test/scenario_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// tools/mock_anthropic/test/scenario_test.dart
import 'package:mock_anthropic/scenario.dart';
import 'package:mock_anthropic/scenarios/ping_pong_mixed_claude.dart';
import 'package:test/test.dart';

void main() {
  test('pingPongMixedClaude registers lead and worker scenarios', () {
    final reg = pingPongMixedClaudeScenarios();
    expect(reg.keys, containsAll(['lead-script', 'worker-script']));
    expect(reg['lead-script']!.turns.length, 3);
    expect(reg['worker-script']!.turns.length, 2);
  });

  test('ScenarioRegistry advances turns per api key', () {
    final reg = ScenarioRegistry({'k': MockScenario(turns: [
      MockTurn.toolUse(id: 't1', name: 'list_teammates', input: {}),
      MockTurn.text('done'),
    ])});
    final first = reg.nextTurn('k');
    expect(first, isA<ToolUseTurn>());
    final second = reg.nextTurn('k');
    expect(second, isA<TextTurn>());
    expect(() => reg.nextTurn('k'), throwsStateError);
  });
}
```

- [ ] **Step 2: Run test → FAIL**

Run: `cd tools/mock_anthropic && dart test test/scenario_test.dart`
Expected: FAIL — library not found

- [ ] **Step 3: Implement scenario.dart**

```dart
// tools/mock_anthropic/lib/scenario.dart
sealed class MockTurn {
  const MockTurn();
}

final class ToolUseTurn extends MockTurn {
  const ToolUseTurn({required this.id, required this.name, required this.input});
  final String id;
  final String name;
  final Map<String, Object?> input;
}

final class TextTurn extends MockTurn {
  const TextTurn(this.text);
  final String text;
}

class MockScenario {
  const MockScenario({required this.turns});
  final List<MockTurn> turns;
}

class ScenarioRegistry {
  ScenarioRegistry(Map<String, MockScenario> scenarios)
      : _scenarios = Map.unmodifiable(scenarios),
        _indices = {for (final k in scenarios.keys) k: 0};

  final Map<String, MockScenario> _scenarios;
  final Map<String, int> _indices;

  Iterable<String> get keys => _scenarios.keys;

  MockTurn nextTurn(String apiKey) {
    final scenario = _scenarios[apiKey];
    if (scenario == null) throw StateError('unknown api key: $apiKey');
    final i = _indices[apiKey] ?? 0;
    if (i >= scenario.turns.length) {
      throw StateError('scenario exhausted for $apiKey at turn $i');
    }
    _indices[apiKey] = i + 1;
    return scenario.turns[i];
  }

  void reset() {
    for (final k in _scenarios.keys) {
      _indices[k] = 0;
    }
  }
}
```

- [ ] **Step 4: Implement ping_pong_mixed_claude.dart**

```dart
// tools/mock_anthropic/lib/scenarios/ping_pong_mixed_claude.dart
import '../scenario.dart';

const leadScriptApiKey = 'lead-script';
const workerScriptApiKey = 'worker-script';

ScenarioRegistry pingPongMixedClaudeScenarios() => ScenarioRegistry({
  leadScriptApiKey: MockScenario(turns: [
    ToolUseTurn(id: 'tu_list', name: 'list_teammates', input: {}),
    ToolUseTurn(
      id: 'tu_send',
      name: 'send_message',
      input: {'to': 'worker-1', 'content': 'ping'},
    ),
    TextTurn('done'),
  ]),
  workerScriptApiKey: MockScenario(turns: [
    ToolUseTurn(id: 'tu_wait', name: 'wait_for_message', input: {}),
    ToolUseTurn(
      id: 'tu_reply',
      name: 'send_message',
      input: {'to': 'team-lead', 'content': 'pong'},
    ),
  ]),
});
```

- [ ] **Step 5: Run test → PASS**

Run: `cd tools/mock_anthropic && dart test test/scenario_test.dart`

- [ ] **Step 6: Commit**

```bash
git commit -am "feat(mock_anthropic): scenario DSL and ping/pong mixed claude script"
```

---

### Task 3: Anthropic SSE encoder

**Files:**
- Create: `tools/mock_anthropic/lib/sse/anthropic_sse_encoder.dart`
- Test: `tools/mock_anthropic/test/sse_encoder_test.dart`

- [ ] **Step 1: Write failing test**

```dart
import 'dart:convert';
import 'package:mock_anthropic/scenario.dart';
import 'package:mock_anthropic/sse/anthropic_sse_encoder.dart';
import 'package:test/test.dart';

void main() {
  test('encodes tool_use turn as SSE data lines', () {
    const turn = ToolUseTurn(
      id: 'tu1',
      name: 'send_message',
      input: {'to': 'worker-1', 'content': 'ping'},
    );
    final body = AnthropicSseEncoder.encodeTurn(
      messageId: 'msg_1',
      model: 'mock-model',
      turn: turn,
    );
    expect(body, contains('event: message_start'));
    expect(body, contains('content_block_start'));
    expect(body, contains('"type":"tool_use"'));
    expect(body, contains('"name":"send_message"'));
    expect(body, contains('event: message_stop'));
  });
}
```

- [ ] **Step 2: Run → FAIL**

- [ ] **Step 3: Implement encoder**

Implement full event sequence per Anthropic streaming spec:
`message_start` → `content_block_start` (tool_use) → `content_block_delta` (partial_json) → `content_block_stop` → `message_delta` (stop_reason:end_turn) → `message_stop`.

Use `tool_use` id like `toolu_01...`, input JSON in delta.

- [ ] **Step 4: Run → PASS**

Run: `cd tools/mock_anthropic && dart test test/sse_encoder_test.dart`

- [ ] **Step 5: Commit**

---

### Task 4: MockAnthropicServer HTTP server

**Files:**
- Create: `tools/mock_anthropic/lib/server.dart`
- Test: `tools/mock_anthropic/test/server_test.dart`

- [ ] **Step 1: Write failing test**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:mock_anthropic/scenarios/ping_pong_mixed_claude.dart';
import 'package:mock_anthropic/server.dart';
import 'package:test/test.dart';

void main() {
  late MockAnthropicServer server;
  late HttpClient client;

  setUp(() async {
    server = MockAnthropicServer(scenarios: pingPongMixedClaudeScenarios());
    await server.start();
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  test('POST /v1/messages routes by x-api-key and returns SSE', () async {
    final req = await client.postUrl(server.messagesUri);
    req.headers.set('content-type', 'application/json');
    req.headers.set('x-api-key', leadScriptApiKey);
    req.add(utf8.encode(jsonEncode({'model': 'mock-model', 'max_tokens': 1024, 'messages': []})));
    final resp = await req.close();
    expect(resp.statusCode, 200);
    expect(resp.headers.contentType?.mimeType, 'text');
    final body = await resp.transform(utf8.decoder).join();
    expect(body, contains('list_teammates'));
  });
}
```

- [ ] **Step 2: Run → FAIL**

- [ ] **Step 3: Implement MockAnthropicServer**

Key behaviors:
- `bind(InternetAddress.loopbackIPv4, 0)`
- Accept `POST` on `/v1/messages` **and** `/anthropic/v1/messages` (register both or normalize path)
- Parse api key from `x-api-key` or `Authorization: Bearer`
- `ScenarioRegistry.nextTurn(apiKey)` → `AnthropicSseEncoder.encodeTurn`
- `RequestLogEntry` list + `dumpDiagnostics()` for failures
- `messagesUri` getter → `Uri.parse('http://127.0.0.1:$port/v1/messages')`

- [ ] **Step 4: Run → PASS**

Run: `cd tools/mock_anthropic && dart test`

- [ ] **Step 5: Commit**

---

### Task 5: Debug CLI + wire client dev_dependency

**Files:**
- Create: `tools/mock_anthropic/bin/mock_anthropic.dart`
- Modify: `client/pubspec.yaml`

- [ ] **Step 1: Implement bin**

```dart
// bin/mock_anthropic.dart — starts server with pingPongMixedClaudeScenarios, prints base URL, waits for SIGINT
```

- [ ] **Step 2: Add dev_dependency to client**

```yaml
dev_dependencies:
  mock_anthropic:
    path: ../tools/mock_anthropic
```

Run: `cd client && flutter pub get`

- [ ] **Step 3: Smoke run**

Run: `dart run tools/mock_anthropic/bin/mock_anthropic.dart` (background, curl test, kill)
Expected: SSE response with list_teammates

- [ ] **Step 4: Commit**

---

### Task 6: Bus mail assertions helper

**Files:**
- Create: `client/test/integration/support/bus_mail_assertions.dart`
- Test: `client/test/integration/support/bus_mail_assertions_test.dart` (non-integration)

- [ ] **Step 1: Write failing test**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'bus_mail_assertions.dart';

void main() {
  test('waitForBusMail finds matching jsonl line', () async {
    final tmp = await Directory.systemTemp.createTemp('bus_mail_');
    final layout = WorkspaceLayout(teampilotRoot: tmp.path);
    final file = File(layout.busMailFile('ws', 'sess', 'worker-1'));
    await file.parent.create(recursive: true);
    await file.writeAsString('${jsonEncode({
      't': 'msg', 'from': 'team-lead', 'to': 'worker-1', 'content': 'ping',
    })}\n');

    final found = await waitForBusMail(
      teampilotRoot: tmp.path,
      workspaceId: 'ws',
      sessionId: 'sess',
      memberId: 'worker-1',
      where: (row) => row['content'] == 'ping' && row['from'] == 'team-lead',
      timeout: Duration(seconds: 1),
    );
    expect(found, isTrue);
    await tmp.delete(recursive: true);
  });
}
```

- [ ] **Step 2: Run → FAIL**

Run: `cd client && flutter test test/integration/support/bus_mail_assertions_test.dart`

- [ ] **Step 3: Implement**

```dart
Future<bool> waitForBusMail({...}) async {
  // poll file every 200ms, parse jsonl lines, match predicate
}

Future<List<Map<String, Object?>>> readBusMailLines({...}) async { ... }

Future<void> dumpBusMailDiagnostics({...}) async { ... }
```

Use `ClaudeTeamRosterService.safeClaudePathSegment(memberId)` for file path segment.

- [ ] **Step 4: Run → PASS**

- [ ] **Step 5: Commit**

---

### Task 7: Teammate bus HTTP client (L1 driver)

**Files:**
- Create: `client/test/integration/support/teammate_bus_http_client.dart`
- Reuse patterns from `client/test/services/team_bus/mcp/teammate_bus_mcp_server_test.dart`

- [ ] **Step 1: Implement client**

```dart
class TeammateBusHttpClient {
  TeammateBusHttpClient({required this.endpoint, required this.memberId});
  Future<void> initialize();
  Future<Map<String, Object?>> callTool(String name, Map<String, Object?> arguments);
  Future<Map<String, Object?>> waitForMessage(); // handles SSE response parsing
}
```

Copy SSE/JSON parsing from `teammate_bus_mcp_server_test.dart` `rpc()` helper.

- [ ] **Step 2: Commit**

---

### Task 8: L1-fast integration test (bus ping/pong, no Claude)

**Files:**
- Create: `client/test/integration/mixed_team_bus_ping_pong_integration_test.dart`

- [ ] **Step 1: Write test**

```dart
@Tags(['integration'])
library;

// Flow:
// 1. TeamBus + TeammateBusMcpServer + declareMember(leader/worker)
// 2. TeammateBusHttpClient(worker) → wait_for_message (async schedule)
// 3. TeammateBusHttpClient(leader) → send_message(worker, ping)
// 4. worker wait returns ping
// 5. worker → send_message(lead, pong)
// 6. leader wait_for_message → pong
// 7. bus_mail_assertions confirm jsonl
```

This validates scenario semantics **before** L2 complexity.

- [ ] **Step 2: Run → PASS**

Run: `cd client && flutter test test/integration/mixed_team_bus_ping_pong_integration_test.dart --tags integration`

- [ ] **Step 3: Commit**

---

### Task 9: MixedTeamIntegrationHarness

**Files:**
- Create: `client/test/integration/support/mixed_team_integration_harness.dart`

- [ ] **Step 1: Implement harness class**

Responsibilities:
- `startMockServer()` → `MockAnthropicServer`
- `writeMockProviders(baseUrl)` → `AppProviderRepository.saveProviders`
- `createCubit({required PostFrameTestHarness postFrame})` → configured `ChatCubit`
- `Future<void> waitUntilMembersRunning(ChatCubit cubit, List<String> memberIds)`
- `Future<void> kickoffMembers(ChatCubit cubit)` — selectMember + submitFullScreenInput sequence
- `Future<void> waitForPingPong({workspaceId, sessionId})` — wraps bus_mail_assertions
- `Future<void> dumpFailureArtifacts(...)` — mock log + settings.json paths + mail dir
- `static String? resolveClaudePath()` — `which claude` / skip
- `static bool get nativePtyAvailable` — copy from pty_spawn_harness_test

Constants: `kItMixedClaudeTeam`, `kLeadMember`, `kWorkerMember`, provider ids.

- [ ] **Step 2: Commit**

---

### Task 10: L2-full ChatCubit integration test

**Files:**
- Create: `client/test/integration/mixed_team_claude_bus_integration_test.dart`

- [ ] **Step 1: Write test skeleton with skips**

```dart
@Tags(['integration'])
@Timeout(Duration(minutes: 2))
library;

import '../support/post_frame_test_harness.dart';
import 'support/mixed_team_integration_harness.dart';

void main() {
  setUp(() {
    HttpOverrides.global = null;
    setUpTestAppStorage();
  });
  tearDown(tearDownTestAppStorage);

  test('two Claude members exchange ping/pong via ChatCubit launch path', () async {
    if (!MixedTeamIntegrationHarness.nativePtyAvailable) {
      markTestSkipped('Requires libflutter_pty.so');
    }
    final claude = MixedTeamIntegrationHarness.resolveClaudePath();
    if (claude == null) markTestSkipped('claude not on PATH');

    final harness = MixedTeamIntegrationHarness(claudePath: claude);
    final postFrame = PostFrameTestHarness();
    try {
      await harness.startMockServer();
      await harness.writeMockProviders(harness.mockBaseUrl);
      final repo = SessionRepository();
      final cubit = harness.createCubit(postFrame: postFrame);
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: AppStorage.cwd),
      ]);
      final session = await repo.createSession(
        workspace.workspaceId,
        sessionTeam: kItMixedClaudeTeam.id,
        rosterMembers: kItMixedClaudeTeam.members,
      );

      await cubit.openSessionTab(
        session,
        team: kItMixedClaudeTeam,
        member: kLeadMember,
        repo: repo,
        connectImmediately: true,
      );
      await postFrame.flush();
      await harness.waitUntilMembersRunning(
        cubit,
        [kLeadMember.id, kWorkerMember.id],
      );
      await harness.kickoffMembers(cubit);
      await harness.waitForPingPong(
        workspaceId: session.workspaceId,
        sessionId: session.sessionId,
      );

      expect(cubit.hasTeamBusResources(session.sessionId), isTrue);
    } catch (e, st) {
      await harness.dumpFailureArtifacts();
      Error.throwWithStackTrace(e, st);
    } finally {
      await cubit.close();
      await postFrame.flush();
      await drainPendingAsyncWork();
      await harness.dispose();
    }
  }, skip: false);
}
```

- [ ] **Step 2: Wire TEAMPILOT_BUS_BRIDGE override**

In harness `createCubit` or lifecycle, ensure member launch env includes dead bridge path. Options:
- Set `Platform.environment` in test setUp (if lifecycle reads at spawn time via inherited env)
- Or patch via `SessionLifecycleService` test hook if needed

Verify via reading provisioned member settings / launch env that HTTP MCP URL is used (not stdio command).

- [ ] **Step 3: Run locally → PASS (manual golden)**

Run:
```bash
cd client
flutter build linux --debug
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  flutter test test/integration/mixed_team_claude_bus_integration_test.dart --tags integration
```

- [ ] **Step 4: Commit**

---

### Task 11: Documentation + spec sync

**Files:**
- Modify: `docs/DEVELOPMENT.md`
- Modify: `docs/superpowers/specs/2026-06-25-mixed-team-claude-bus-integration-design.md` (status → 已实现)

- [ ] **Step 1: Add DEVELOPMENT.md section**

```markdown
### Mixed team Claude bus integration tests

L1 (fast, no claude):
```bash
cd client && flutter test test/integration/mixed_team_bus_ping_pong_integration_test.dart --tags integration
```

L2 (full ChatCubit + claude + PTY, Linux):
```bash
cd client
flutter build linux --debug
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  flutter test test/integration/mixed_team_claude_bus_integration_test.dart --tags integration
```

Debug mock API standalone:
```bash
dart run tools/mock_anthropic/bin/mock_anthropic.dart
# export ANTHROPIC_BASE_URL=http://127.0.0.1:<printed-port>
```
```

- [ ] **Step 2: Run full unit suite**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`

- [ ] **Step 3: Commit**

```bash
git commit -am "docs: mixed team Claude bus integration test commands"
```

---

## Verification Checklist

- [ ] `cd tools/mock_anthropic && dart test` — all green
- [ ] `cd client && flutter test --exclude-tags integration` — all green
- [ ] L1: `flutter test test/integration/mixed_team_bus_ping_pong_integration_test.dart --tags integration`
- [ ] L2 (Linux + claude): full ping/pong pass
- [ ] Failure path: intentionally break scenario → `dumpFailureArtifacts` prints useful output

## Execution Handoff

Plan complete. Recommended: **Subagent-Driven Development** — one subagent per Task, review between tasks.
