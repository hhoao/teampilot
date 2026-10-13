# Mixed Team ACP Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let mixed TeamBus members launch as per-seat ACP chat while PTY siblings, native teams, and personal ACP stay unchanged.

**Architecture:** ACP becomes a seat transport. `AppSession.acp` remains personal-only. `SessionMemberBinding.acp` is the mixed-seat fact. Connect still installs TeamBus, then either `attachMemberAcpRuntime` or PTY. Wake/idle reuse TeamBus; `session/new` can carry teammate-bus MCP.

**Tech Stack:** Flutter/Dart (`teampilot`), vendored `acpd`, existing `AcpSessionRuntime` / `AcpChatRuntimeCubit` / TeamBus.

**Spec:** `docs/superpowers/specs/2026-10-12-mixed-team-acp-session-design.md`

## Global Constraints

- Mixed TeamBus only. Native `--team-name` never ACP.
- `AppSession.acp` is always false on team create.
- Desktop `RuntimeKind.local` only. Android / SSH / WSL / Termux stay PTY.
- First-wave CLIs: Claude, Codex, Gemini. OpenCode / FlashskyAI / Cursor stay PTY.
- ACP attach failure must not fall back to PTY for that seat. Failed attach does not auto fan-out (same as failed PTY).
- Do not rewrite TeamBus wire protocol. Do not add a team-compose ACP toggle.
- Preference keys `claudePersonalAcpDefault` / `codexPersonalAcpDefault` stay. They seed new mixed local members as well as new personal sessions.
- No `if (cli == …)` in `services/acp/` or `SessionConnectExecutor`. Claude/Codex preference picks stay at the existing settings/compose gate.
- `SessionLaunchService` is already ~1088 lines. Extract ACP attach out of it; do not add `attachMemberAcpRuntime` there.
- User copy → `app_en.arb` + `app_zh.arb` only. Diagnostics → `AppLogger`. No `print`.
- Tests: `cd client && dart run tool/run_tests.dart <paths>`. Never `flutter test` directly.
- Inner loop: one test file (optional `--plain-name`). Full suite only before claiming done, in the background.

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/session_member_binding.dart` | `acp` bool, JSON omit-when-false, `==` / `hashCode` |
| `client/lib/services/chat/session/chat_tab.dart` | `isAcpChatSeat`; `memberAcpRuntimes`; `acpRuntime` personal alias |
| `client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart` | `resolveMemberBindingAcp`, `shouldAttachMemberAcp` |
| `client/lib/services/chat/session/session_create_request.dart` | `seedClaudeMemberAcp`, `seedCodexMemberAcp` |
| `client/lib/services/chat/launch/session/session_launch_coordinator.dart` | stamp `binding.acp` on mixed create |
| `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` | pass seeds from preferences on team create |
| `client/lib/services/acp/acp_connection.dart` | `openSession(mcpServers:)` |
| `client/lib/services/acp/acp_session_runtime.dart` | `start(mcpServers:)` |
| `client/lib/services/acp/acp_mcp_servers.dart` | extra MCP map → `acpd.McpServer` list |
| `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` | `seatMemberId` (default `'acp'`) |
| `client/lib/services/chat/launch/connect/acp_runtime_attach.dart` | extracted personal + member attach |
| `client/lib/services/chat/launch/connect/session_connect_executor.dart` | mixed ACP branch after TeamBus |
| `client/lib/services/chat/launch/connect/session_connect_executor.dart` (port) | `attachMemberAcpRuntime` |
| `client/lib/services/chat/launch/session/tab_member_materializer.dart` | ACP `wake` → `sendPrompt`; input-ready on cubit |
| `client/lib/pages/chat_workbench.dart` | selected-member cubit + per-seat terminal toggle |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | settings copy no longer says teams always PTY |

---

### Task 1: `SessionMemberBinding.acp`

**Files:**
- Modify: `client/lib/models/session_member_binding.dart`
- Test: `client/test/models/session_member_binding_test.dart`

**Interfaces:**
- Consumes: existing `SessionMemberBinding` constructor / `fromJson` / `toJson` / `withNativeSessionId`
- Produces: `SessionMemberBinding.acp` (`bool`, default `false`). JSON omit when false. Missing key → false. `withNativeSessionId` preserves `acp`.

- [ ] **Step 1: Write the failing test**

Add to `client/test/models/session_member_binding_test.dart`:

```dart
test('acp defaults false, omits JSON, round-trips true', () {
  const off = SessionMemberBinding(rosterMemberId: 'lead', taskId: 't1');
  expect(off.acp, isFalse);
  expect(off.toJson().containsKey('acp'), isFalse);
  expect(
    SessionMemberBinding.fromJson({
      'rosterMemberId': 'lead',
      'taskId': 't1',
    }).acp,
    isFalse,
  );

  const on = SessionMemberBinding(
    rosterMemberId: 'lead',
    taskId: 't1',
    acp: true,
  );
  expect(on.toJson()['acp'], isTrue);
  expect(SessionMemberBinding.fromJson(on.toJson()).acp, isTrue);

  final kept = on.withNativeSessionId('cursor', 'n1');
  expect(kept.acp, isTrue);
  expect(on, isNot(off));
  expect(on.hashCode, isNot(off.hashCode));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/models/session_member_binding_test.dart --plain-name 'acp defaults false'`

Expected: FAIL — `acp` isn't defined.

- [ ] **Step 3: Write minimal implementation**

In `session_member_binding.dart`:

```dart
const SessionMemberBinding({
  required this.rosterMemberId,
  required this.taskId,
  String? typeId,
  this.cli,
  this.nativeSessionIds = const {},
  this.acp = false,
}) : typeId = typeId ?? rosterMemberId;

factory SessionMemberBinding.fromJson(Map<String, Object?> json) {
  // ...existing native/cli parsing...
  return SessionMemberBinding(
    rosterMemberId: instanceId,
    taskId: json['taskId'] as String? ?? '',
    typeId: json['typeId'] as String? ?? instanceId,
    cli: CliTool.tryParse(json['cli'] as String?),
    nativeSessionIds: native,
    acp: json['acp'] == true,
  );
}

final bool acp;
```

`withNativeSessionId` copies `acp: acp`. `toJson` adds `if (acp) 'acp': true`. `==` / `hashCode` include `acp`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/models/session_member_binding_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/session_member_binding.dart client/test/models/session_member_binding_test.dart
git commit -m "$(cat <<'EOF'
Add SessionMemberBinding.acp for mixed ACP seats.

EOF
)"
```

---

### Task 2: `isAcpChatSeat`

**Files:**
- Modify: `client/lib/services/chat/session/chat_tab.dart`
- Test: `client/test/services/chat/session/is_acp_chat_session_test.dart`

**Interfaces:**
- Consumes: `AppSession.isSimple`, `AppSession.bindingFor`, `SessionMemberBinding.acp`
- Produces: `bool isAcpChatSeat(AppSession session, String memberId)`. `isAcpChatSession` unchanged.

- [ ] **Step 1: Write the failing tests**

Add to `client/test/services/chat/session/is_acp_chat_session_test.dart` (import `session_member_binding.dart`):

```dart
test('isAcpChatSeat is binding-only and never true for simple sessions', () {
  final mixed = AppSession(
    sessionId: 's1',
    workspaceId: 'w1',
    createdAt: 1,
    sessionTeam: 't1',
    members: const [
      SessionMemberBinding(
        rosterMemberId: 'lead',
        taskId: 't',
        acp: true,
      ),
    ],
  );
  expect(isAcpChatSeat(mixed, 'lead'), isTrue);
  expect(isAcpChatSeat(mixed, 'missing'), isFalse);
  expect(isAcpChatSession(mixed), isFalse);

  final simple = session(cli: CliTool.claude, acp: true);
  expect(isAcpChatSeat(simple, simple.sessionId), isFalse);
  expect(isAcpChatSession(simple), isTrue);
});
```

Keep the existing `'teamed claude with acp true is not ACP'` test for `isAcpChatSession`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/session/is_acp_chat_session_test.dart --plain-name 'isAcpChatSeat'`

Expected: FAIL — `isAcpChatSeat` isn't defined.

- [ ] **Step 3: Write minimal implementation**

In `chat_tab.dart` next to `isAcpChatSession`:

```dart
bool isAcpChatSeat(AppSession session, String memberId) =>
    !session.isSimple && (session.bindingFor(memberId)?.acp ?? false);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/session/is_acp_chat_session_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/session/chat_tab.dart client/test/services/chat/session/is_acp_chat_session_test.dart
git commit -m "$(cat <<'EOF'
Add isAcpChatSeat for mixed TeamBus ACP members.

EOF
)"
```

---

### Task 3: Seat resolver and connect-time defense

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart`
- Test: `client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`

**Interfaces:**
- Consumes: `TeamMode`, `runtimeKindOfId`, `CliToolRegistry.capability<AcpCapability>`, existing `resolveLaunchAcp`
- Produces:

```dart
bool resolveMemberBindingAcp({
  required CliTool? cli,
  required TeamMode teamMode,
  required String targetId,
  required bool requested,
  bool? isAndroidOverride,
});

bool shouldAttachMemberAcp({
  required AppSession session,
  required String memberId,
  required TeamProfile? team,
  required String targetId,
  bool? isAndroidOverride,
});
```

`resolveLaunchAcp` stays personal-only (team create `request.acp` remains false). Gemini: `requested` is ignored; if the other gates pass, return true. Claude/Codex: require `requested`. Any CLI without `AcpCapability` → false.

- [ ] **Step 1: Write the failing tests**

Add to `claude_acp_launch_switch_test.dart`:

```dart
group('resolveMemberBindingAcp', () {
  test('mixed local Claude/Codex follow requested; Gemini always', () {
    bool resolve({
      CliTool? cli = CliTool.claude,
      TeamMode mode = TeamMode.mixed,
      String target = 'local',
      bool requested = true,
      bool android = false,
    }) => resolveMemberBindingAcp(
      cli: cli,
      teamMode: mode,
      targetId: target,
      requested: requested,
      isAndroidOverride: android,
    );

    expect(resolve(), isTrue);
    expect(resolve(requested: false), isFalse);
    expect(resolve(cli: CliTool.codex), isTrue);
    expect(resolve(cli: CliTool.gemini, requested: false), isTrue);
    expect(resolve(cli: CliTool.opencode), isFalse);
    expect(resolve(mode: TeamMode.native), isFalse);
    expect(resolve(target: 'ssh:prod'), isFalse);
    expect(resolve(target: 'wsl:ubuntu'), isFalse);
    expect(resolve(android: true), isFalse);
  });
});

group('shouldAttachMemberAcp', () {
  test('false when binding true but target is ssh', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      sessionTeam: 't1',
      members: const [
        SessionMemberBinding(
          rosterMemberId: 'lead',
          taskId: 't',
          cli: CliTool.claude,
          acp: true,
        ),
      ],
    );
    const team = TeamProfile(
      id: 't1',
      name: 'T',
      teamMode: TeamMode.mixed,
      members: [TeamMemberConfig(id: 'lead', name: 'Lead')],
    );
    expect(
      shouldAttachMemberAcp(
        session: session,
        memberId: 'lead',
        team: team,
        targetId: 'ssh:prod',
        isAndroidOverride: false,
      ),
      isFalse,
    );
    expect(
      shouldAttachMemberAcp(
        session: session,
        memberId: 'lead',
        team: team,
        targetId: 'local',
        isAndroidOverride: false,
      ),
      isTrue,
    );
  });
});
```

Keep `'team create stays false even when acp is requested'` for `request.acp`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart --plain-name 'resolveMemberBindingAcp'`

Expected: FAIL — functions missing.

- [ ] **Step 3: Write minimal implementation**

In `claude_acp_launch_switch.dart` import `runtime_target.dart`, `app_session.dart`, `cli_tool_registry.dart`, `acp_capability.dart`.

```dart
bool _memberAcpGates({
  required TeamMode teamMode,
  required String targetId,
  required CliTool? cli,
  bool? isAndroidOverride,
}) {
  if (teamMode != TeamMode.mixed) return false;
  if (_isAndroid(isAndroidOverride)) return false;
  if (runtimeKindOfId(targetId) != RuntimeKind.local) return false;
  if (cli == null) return false;
  return CliToolRegistry.builtIn().capability<AcpCapability>(cli) != null;
}

bool resolveMemberBindingAcp({
  required CliTool? cli,
  required TeamMode teamMode,
  required String targetId,
  required bool requested,
  bool? isAndroidOverride,
}) {
  if (!_memberAcpGates(
    teamMode: teamMode,
    targetId: targetId,
    cli: cli,
    isAndroidOverride: isAndroidOverride,
  )) {
    return false;
  }
  if (cli == CliTool.gemini) return true;
  return requested;
}

bool shouldAttachMemberAcp({
  required AppSession session,
  required String memberId,
  required TeamProfile? team,
  required String targetId,
  bool? isAndroidOverride,
}) {
  if (!isAcpChatSeat(session, memberId)) return false;
  final cli = session.bindingFor(memberId)?.cli;
  return _memberAcpGates(
    teamMode: team?.teamMode ?? TeamMode.native,
    targetId: targetId,
    cli: cli,
    isAndroidOverride: isAndroidOverride,
  );
}
```

Gemini `==` here is the same settings-gate exception already used by personal create (`acp || cli == gemini`). Do not copy it into the executor.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart
git commit -m "$(cat <<'EOF'
Add mixed-seat ACP resolver and connect-time defense.

EOF
)"
```

---

### Task 4: Stamp `binding.acp` on mixed create

**Files:**
- Modify: `client/lib/services/chat/session/session_create_request.dart`
- Modify: `client/lib/services/chat/launch/session/session_launch_coordinator.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` (`buildWorkspaceConversationCreateRequest`)
- Test: `client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart` (create request seeds)
- Test: `client/test/services/chat/launch/session_launch_coordinator_test.dart` (or add `session_member_acp_stamp_test.dart` if coordinator tests are heavy)
- Test: `client/test/repositories/session_repository_acp_test.dart` (team `session.acp` still false when a binding is true)

**Interfaces:**
- Consumes: `resolveMemberBindingAcp`, `TeamSessionMemberPlan`
- Produces: `SessionCreateRequest.seedClaudeMemberAcp` (default `true`), `seedCodexMemberAcp` (default `false`). Coordinator rewrites `plan.members` with `acp` set. `createSession` already persists whatever bindings it is given. Team `AppSession.acp` stays false.

- [ ] **Step 1: Write the failing tests**

Create-request seed (extend existing `buildWorkspaceConversationCreateRequest` tests):

```dart
test('team create keeps request.acp false and copies CLI seeds', () {
  final request = buildWorkspaceConversationCreateRequest(
    workspace: workspace,
    isPersonal: false,
    cli: CliTool.claude,
    acp: true,
    seedClaudeMemberAcp: true,
    seedCodexMemberAcp: true,
    isAndroidOverride: false,
  );
  expect(request.acp, isFalse);
  expect(request.seedClaudeMemberAcp, isTrue);
  expect(request.seedCodexMemberAcp, isTrue);
});
```

Coordinator / stamp: after create/open of a mixed team with local targets, `session.members.single.acp` is true for Claude when `seedClaudeMemberAcp: true`, false when false; Gemini member is true even when both seeds are false; `session.acp` is false.

Repository: extend `'team session persists false even when acp is true'` — also persist a binding with `acp: true` via `members:` and assert `session.acp == false` and `session.members.first.acp == true`.

If coordinator tests cannot reach disk easily, extract a pure helper in `claude_acp_launch_switch.dart` or `team_session_member_plan.dart`:

```dart
List<SessionMemberBinding> stampMemberAcp({
  required List<SessionMemberBinding> members,
  required Map<String, String> memberTargets,
  required TeamMode teamMode,
  required bool seedClaudeMemberAcp,
  required bool seedCodexMemberAcp,
  bool? isAndroidOverride,
}) { ... }
```

and unit-test that. Coordinator calls the helper. Prefer the helper so the test does not need a full launch host.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart --plain-name 'team create keeps request.acp false'`

Expected: FAIL — `seedClaudeMemberAcp` missing.

- [ ] **Step 3: Write minimal implementation**

Add fields to `SessionCreateRequest`. Implement `stampMemberAcp` using `resolveMemberBindingAcp` and `requested:` `cli == claude → seedClaude`, `cli == codex → seedCodex`, else `false` (Gemini ignores it). Coordinator after `buildTeamSessionMemberPlan`:

```dart
provisional = provisional.copyWith(
  members: stampMemberAcp(
    members: plan.members,
    memberTargets: plan.memberTargets,
    teamMode: request.team!.teamMode,
    seedClaudeMemberAcp: request.seedClaudeMemberAcp,
    seedCodexMemberAcp: request.seedCodexMemberAcp,
  ),
  memberTargets: plan.memberTargets,
);
```

`buildWorkspaceConversationCreateRequest` passes through optional seeds (defaults match preference defaults: Claude true, Codex false). Do not set `request.acp` true for teams.

- [ ] **Step 4: Run the new tests**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart test/repositories/session_repository_acp_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/session/session_create_request.dart \
  client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart \
  client/lib/pages/home_workspace/workspace/workspace_session_actions.dart \
  client/lib/services/chat/launch/session/session_launch_coordinator.dart \
  client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart \
  client/test/repositories/session_repository_acp_test.dart
git commit -m "$(cat <<'EOF'
Stamp mixed member ACP from Claude/Codex settings seeds.

EOF
)"
```

---

### Task 5: `ChatTab.memberAcpRuntimes`

**Files:**
- Modify: `client/lib/services/chat/session/chat_tab.dart`
- Test: `client/test/services/chat/session/chat_tab_acp_runtimes_test.dart` (new)

**Interfaces:**
- Consumes: existing `ChatTab.acpRuntime` assign in personal attach
- Produces: `Map<String, AcpChatRuntimeCubit> memberAcpRuntimes`. `acpRuntime` getter/setter is the personal alias keyed by `persistedSession?.sessionId ?? info.id`. Team UI must not use the getter for a selected teammate. `disposeBus` closes every cubit in the map.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';

void main() {
  test('personal acpRuntime alias writes memberAcpRuntimes[sessionId]', () {
    final tab = ChatTab(
      info: const ChatTabInfo(id: 's1', title: 't', subtitle: ''),
      cliTeamName: '',
    );
    expect(tab.acpRuntime, isNull);

    // Use a tiny fake cubit or skip if constructing AcpChatRuntimeCubit
    // needs a runtime — prefer a test-only setter that accepts the map:
    tab.memberAcpRuntimes['lead'] = /* cannot assign without cubit */;
  });
}
```

Do **not** construct a real cubit if it is heavy. Test the map + getter/setter with a `FakeAcpChatRuntimeCubit` only if one already exists. Otherwise test:

```dart
test('disposeBus closes every member ACP runtime', () async {
  final tab = ChatTab(
    info: const ChatTabInfo(id: 's1', title: 't', subtitle: ''),
    cliTeamName: '',
  );
  final a = _RecordingAcpCubit();
  final b = _RecordingAcpCubit();
  tab.memberAcpRuntimes['s1'] = a;
  tab.memberAcpRuntimes['lead'] = b;
  tab.acpRuntime = a; // personal alias if setter uses info.id
  await tab.disposeBus();
  expect(a.closed, isTrue);
  expect(b.closed, isTrue);
  expect(tab.memberAcpRuntimes, isEmpty);
  expect(tab.acpRuntime, isNull);
});
```

If `AcpChatRuntimeCubit` cannot be faked as a subtype, extract `AcpChatRuntimeApi` only if tests otherwise cannot compile. Prefer storing the cubit type and using `AcpChatRuntimeCubit` with the existing fake runtime from `acp_chat_runtime_cubit_test.dart`. Copy that fake into the new test (do not say "similar to Task N" — paste the fake).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/session/chat_tab_acp_runtimes_test.dart`

Expected: FAIL — `memberAcpRuntimes` missing.

- [ ] **Step 3: Write minimal implementation**

Replace the single field with:

```dart
final Map<String, AcpChatRuntimeCubit> memberAcpRuntimes = {};

AcpChatRuntimeCubit? get acpRuntime {
  final key = persistedSession?.sessionId ?? info.id;
  return memberAcpRuntimes[key];
}

set acpRuntime(AcpChatRuntimeCubit? value) {
  final key = persistedSession?.sessionId ?? info.id;
  if (value == null) {
    memberAcpRuntimes.remove(key);
  } else {
    memberAcpRuntimes[key] = value;
  }
}
```

`disposeBus`:

```dart
final cubits = memberAcpRuntimes.values.toList();
memberAcpRuntimes.clear();
for (final cubit in cubits) {
  await cubit.close();
}
```

Keep TeamBus teardown order: remote mounts, ssh, teamBus, then ACP cubits.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/session/chat_tab_acp_runtimes_test.dart test/services/chat/launch/session_launch_acp_attach_test.dart`

Expected: PASS (personal attach tests still assign `tab.acpRuntime`).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/session/chat_tab.dart client/test/services/chat/session/chat_tab_acp_runtimes_test.dart
git commit -m "$(cat <<'EOF'
Store ACP runtimes per member on ChatTab.

EOF
)"
```

---

### Task 6: `openSession` / `start` accept `mcpServers`

**Files:**
- Modify: `client/lib/services/acp/acp_connection.dart`
- Modify: `client/lib/services/acp/acp_session_runtime.dart`
- Create: `client/lib/services/acp/acp_mcp_servers.dart`
- Test: `client/test/services/acp/acp_session_test.dart`
- Test: `client/test/services/acp/acp_mcp_servers_test.dart` (new)
- Test: `client/test/services/acp/acp_session_runtime_test.dart` (pass-through)

**Interfaces:**
- Consumes: `acpd.McpServer`, extra MCP `Map<String, Map<String, Object?>>` (`command`/`args` or `type: http` + `url` + `headers`)
- Produces:

```dart
Future<AcpAgentSession> openSession({
  required String cwd,
  List<acpd.McpServer> mcpServers = const [],
  Duration permissionTimeout = AcpAgentSession.defaultPermissionTimeout,
});

Future<void> start({
  required CliTool tool,
  required String executable,
  required String sessionToolDir,
  required String workingDirectory,
  Map<String, String> baseEnv = const {},
  List<acpd.McpServer> mcpServers = const [],
});

List<acpd.McpServer> acpMcpServersFromExtra(
  Map<String, Map<String, Object?>> extra,
);
```

Personal callers keep default `[]`.

- [ ] **Step 1: Write the failing tests**

In `acp_session_test.dart` (the existing empty-list assertion around `seenNew!.mcpServers`): add a case that `openSession(mcpServers: [McpServerStdio(name: 'teammate-bus', command: '/bin/bridge', args: ['--bus-url', 'http://x'])])` records that server on `session/new`.

New `acp_mcp_servers_test.dart`:

```dart
test('maps stdio and http extra MCP dicts', () {
  final servers = acpMcpServersFromExtra({
    'teammate-bus': {
      'command': '/bridge',
      'args': ['--member', 'lead', '--bus-url', 'http://127.0.0.1/mcp'],
    },
    'teampilot': {
      'type': 'http',
      'url': 'http://127.0.0.1/catalog/mcp',
      'headers': {'X-Member': 'lead'},
    },
  });
  expect(servers, hasLength(2));
  expect(servers[0], isA<acpd.McpServerStdio>());
  expect((servers[0] as acpd.McpServerStdio).name, 'teammate-bus');
  expect(servers[1], isA<acpd.McpServerHttp>());
});

test('empty extra yields empty list', () {
  expect(acpMcpServersFromExtra(const {}), isEmpty);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_mcp_servers_test.dart test/services/acp/acp_session_test.dart --plain-name 'maps stdio'`

Expected: FAIL — helper / parameter missing.

- [ ] **Step 3: Write minimal implementation**

`acp_connection.dart`: `NewSessionRequest(cwd: cwd, mcpServers: mcpServers)`.

`acp_session_runtime.dart`: `start` takes `mcpServers` and passes them to `openSession`. Update `AcpSessionRuntimeApi`.

`acp_mcp_servers.dart`: map `command` → `McpServerStdio`; `url`/`type == http` → `McpServerHttp` with `HttpHeader` list from a `Map` or list. Skip invalid entries (no command and no url).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/`

Expected: PASS. Personal tests still see empty `mcpServers` when omitted.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_connection.dart \
  client/lib/services/acp/acp_session_runtime.dart \
  client/lib/services/acp/acp_mcp_servers.dart \
  client/test/services/acp/
git commit -m "$(cat <<'EOF'
Pass MCP servers through ACP session/new.

EOF
)"
```

---

### Task 7: `AcpChatRuntimeCubit.seatMemberId`

**Files:**
- Modify: `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart`
- Test: `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

**Interfaces:**
- Consumes: existing `_applyAttention(..., memberId: acpMemberId)`
- Produces: constructor arg `String seatMemberId = acpMemberId`. Attention / permission holds use `seatMemberId`. Keep static `acpMemberId = 'acp'` for personal.

- [ ] **Step 1: Write the failing test**

In the cubit test file, construct with `seatMemberId: 'lead'` and assert the `AgentAttentionPort` fake received `memberId: 'lead'` on start/prompt (whatever event the existing test already checks for `'acp'`). If no such assertion exists, add a recording port:

```dart
test('attention events use seatMemberId', () async {
  final attention = _RecordingAttention();
  final cubit = AcpChatRuntimeCubit(
    runtime: fakeRuntime,
    sessionId: 's1',
    tool: CliTool.claude,
    attention: attention,
    seatMemberId: 'lead',
  );
  await cubit.start(executable: 'x', sessionToolDir: '/t', workingDirectory: '/w');
  expect(attention.memberIds, contains('lead'));
  expect(attention.memberIds, isNot(contains('acp')));
});
```

Paste `_RecordingAttention` implementing `AgentAttentionPort.applyEvent` by appending `memberId`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart --plain-name 'attention events use seatMemberId'`

Expected: FAIL — named param missing or still `'acp'`.

- [ ] **Step 3: Write minimal implementation**

```dart
AcpChatRuntimeCubit({
  required AcpSessionRuntimeApi runtime,
  required this.sessionId,
  required this.tool,
  this.seatMemberId = acpMemberId,
  ...
});

final String seatMemberId;
```

Replace `_applyAttention` `memberId: acpMemberId` with `memberId: seatMemberId`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

Expected: PASS (personal tests omit the arg).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart
git commit -m "$(cat <<'EOF'
Key ACP attention to the roster member id.

EOF
)"
```

---

### Task 8: Extract ACP attach + member attach

**Files:**
- Create: `client/lib/services/chat/launch/connect/acp_runtime_attach.dart`
- Modify: `client/lib/services/chat/launch/session_launch_service.dart` (delegate; do not add net lines)
- Modify: `client/lib/services/chat/launch/connect/session_connect_executor.dart` (port method)
- Modify: `client/lib/services/acp/acp_chat_transcript.dart` or attach helper for path
- Test: `client/test/services/chat/launch/session_launch_acp_attach_test.dart`
- Test: `client/test/services/chat/launch/acp_runtime_attach_test.dart` (new)

**Interfaces:**
- Consumes: `prepareSimpleConnect` (personal), `prepareTeamConnect` (mixed), `acpMcpServersFromExtra`, `AcpChatRuntimeCubit.seatMemberId`
- Produces:

```dart
Future<bool> attachAcpRuntime(...); // moved, behavior unchanged

Future<bool> attachMemberAcpRuntime(
  SessionConnectJob job,
  AppSession session,
  ResolvedLaunchMembers resolved,
);
```

Member attach:

- Returns `false` when `shouldAttachMemberAcp` is false (executor falls through to PTY).
- Returns `true` after storing `tab.memberAcpRuntimes[member.id]` and `cubit.start`.
- `seatMemberId: member.id`.
- Transcript: `runtime/acp-transcript-<member.id>.jsonl`.
- Env: `prepareTeamConnect` (same shape as `prepareAcpLaunchEnvironment` but team).
- `mcpServers`: `acpMcpServersFromExtra(extra)` from that staging. If TeamBus extra contains `teammate-bus` and the mapped list is empty → throw (attach failure, no PTY).
- Personal transcript path stays `runtime/acp-transcript.jsonl`.

- [ ] **Step 1: Write the failing tests**

Extend `session_launch_acp_attach_test.dart` with a mixed session: binding `acp: true`, `TeamMode.mixed`, local target. After `attachMemberAcpRuntime` / executor (if wired in this task, otherwise call the new function directly):

- `tab.memberAcpRuntimes['lead']` is non-null
- `tab.acpRuntime` is null (personal alias key is session id, not `lead`) unless you also set personal
- fake runtime `start` saw non-empty `mcpServers` when extra had teammate-bus
- fake runtime `start` cwd/env came from team prepare (assert a distinctive env key you inject in the test `prepareTeamConnect`)

Path helper test:

```dart
test('mixed transcript is per member', () {
  expect(
    acpTranscriptFileName(memberId: 'lead', personal: false),
    'acp-transcript-lead.jsonl',
  );
  expect(
    acpTranscriptFileName(memberId: null, personal: true),
    'acp-transcript.jsonl',
  );
});
```

Put `acpTranscriptFileName` in `acp_runtime_attach.dart` or `acp_chat_transcript.dart`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/acp_runtime_attach_test.dart`

Expected: FAIL — attach member API missing.

- [ ] **Step 3: Write minimal implementation**

Move personal attach body into `acp_runtime_attach.dart`. `SessionLaunchService.attachAcpRuntime` becomes a one-line delegate. Add `attachMemberAcpRuntime` on the preparation port; service delegates.

Add `mcpServers` to the fake runtime used in attach tests.

Extend `prepareAcpLaunchEnvironment` with an optional `AcpTeamConnectPrepare? prepareTeamConnect` **or** a sibling `prepareAcpTeamLaunchEnvironment` that calls `prepareTeamConnect`. Do not call `prepareSimpleConnect` for mixed seats.

If `SessionLaunchService` cannot shrink in the same PR, at least make attach methods one-liners so net growth is in the new file.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session_launch_acp_attach_test.dart test/services/chat/launch/acp_runtime_attach_test.dart test/services/chat/launch/acp_launch_environment_test.dart`

Expected: PASS. Personal attach tests unchanged.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/launch/connect/acp_runtime_attach.dart \
  client/lib/services/chat/launch/session_launch_service.dart \
  client/lib/services/chat/launch/connect/session_connect_executor.dart \
  client/lib/services/chat/launch/connect/acp_launch_environment.dart \
  client/test/services/chat/launch/
git commit -m "$(cat <<'EOF'
Attach mixed-seat ACP after TeamBus staging.

EOF
)"
```

---

### Task 9: Executor mixed ACP branch

**Files:**
- Modify: `client/lib/services/chat/launch/connect/session_connect_executor.dart`
- Modify: `client/test/services/chat/launch/session_connect_executor_test.dart`

**Interfaces:**
- Consumes: `attachMemberAcpRuntime` returning bool; `isAcpChatSession` personal shortcut unchanged
- Produces: after `installTeamRuntime`, if member attach returns true, `onResult(..., attached)` then return. No PTY. If attach throws, do not open a shell. Failed attach does not call `onResult` with `attached`.

- [ ] **Step 1: Write the failing tests**

In `session_connect_executor_test.dart`, `_job` must accept `members` / `sessionTeam` / binding `acp`. `_FakePreparation.attachMemberAcpRuntime` records `'attach-member-acp'` and returns a field `memberAcpHandled`.

```dart
test('mixed ACP seat attaches after TeamBus and skips PTY', () async {
  job = _mixedAcpJob();
  preparation.memberAcpHandled = true;

  await executor.execute(job);

  expect(events, <String>[
    'persist',
    'ensure-ready',
    'resolve-member',
    'install-team-runtime',
    'attach-member-acp',
  ]);
  expect(shellConnector.connectCalls, 0);
});

test('mixed ACP success reports attached for fan-out', () async {
  job = _mixedAcpJob();
  preparation.memberAcpHandled = true;
  final results = <ConnectShellResult>[];
  executor = SessionConnectExecutor(
    preparation: preparation,
    shellConnector: shellConnector,
    onResult: (job, session, resolved, result) => results.add(result),
  );
  await executor.execute(job);
  expect(results, [ConnectShellResult.attached]);
});

test('mixed ACP attach false falls through to PTY', () async {
  job = _mixedAcpJob();
  preparation.memberAcpHandled = false;
  await executor.execute(job);
  expect(events, contains('connect-shell'));
});

test('mixed ACP attach throw does not open PTY', () async {
  job = _mixedAcpJob();
  preparation.memberAcpError = StateError('adapter missing');
  await executor.execute(job);
  expect(shellConnector.connectCalls, 0);
  expect(events, isNot(contains('connect-shell')));
});
```

Personal Claude/Codex ACP tests must still be `persist, ensure-ready, attach-acp` without `resolve-member`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session_connect_executor_test.dart --plain-name 'mixed ACP seat'`

Expected: FAIL — no member attach call.

- [ ] **Step 3: Write minimal implementation**

After `installTeamRuntime`:

```dart
final resolved = await preparation.resolveMember(job, activeSession);
if (!preparation.isValid(job)) return;
await preparation.installTeamRuntime(job, activeSession, resolved.team);
if (!preparation.isValid(job)) return;
if (await preparation.attachMemberAcpRuntime(job, activeSession, resolved)) {
  if (preparation.isValid(job)) {
    await onResult?.call(
      job,
      activeSession,
      resolved,
      ConnectShellResult.attached,
    );
  }
  return;
}
```

Keep the personal `isAcpChatSession` block **before** `resolveMember`.

On throw from member attach: existing catch. Do not start `attachmentStarted` / `shellConnector.connect`. Call `markConnectFailed(job, resolved.member.id)` if resolve already happened — set `attachedMemberId` before member attach.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session_connect_executor_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/launch/connect/session_connect_executor.dart \
  client/test/services/chat/launch/session_connect_executor_test.dart
git commit -m "$(cat <<'EOF'
Branch mixed connect through per-member ACP attach.

EOF
)"
```

---

### Task 10: TeamBus wake / idle / input-ready

**Files:**
- Modify: `client/lib/services/chat/launch/session/tab_member_materializer.dart`
- Modify: `client/lib/services/chat/launch/connect/acp_runtime_attach.dart` (idle subscription)
- Test: `client/test/cubits/chat/tab_member_materializer_test.dart`
- Test: `client/test/services/chat/launch/acp_runtime_attach_test.dart` or a focused `acp_member_idle_test.dart`

**Interfaces:**
- Consumes: `tab.memberAcpRuntimes[memberId]`, `AcpChatRuntimeCubit.sendPrompt`, `AcpChatPhase.idle` / `ready`, `TeamBus.onMemberIdle`
- Produces:
  - `injectMemberStdin` / `retryDelivery`: if that seat has an ACP cubit, `sendPrompt(notice)` and return; else existing PTY inject.
  - `ensureMemberInputReady`: if `isAcpChatSeat`, wait until cubit phase is `ready` or `idle` (or cubit already present); do not wait on a PTY composer.
  - After member attach, listen to cubit: on transition to `idle` (and not `ended`), `tab.teamBus?.onMemberIdle(member.id)` with default `fromPtyQuietWatch: false`.

Do **not** refactor `MixedMemberCoordination` to take a nullable shell. Presence for ACP seats is `AgentAttentionPort` via `seatMemberId`.

- [ ] **Step 1: Write the failing tests**

Materializer: with a tab that has `memberAcpRuntimes['worker'] = cubit` (recording `sendPrompt`), `injectMemberStdin(sessionId, 'worker', 'hello')` calls `sendPrompt('hello')` and does not call PTY deliver. A PTY-only member still goes to stdin.

`ensureMemberInputReady` for `isAcpChatSeat` returns without waiting when cubit phase is `ready`.

Idle: driving the cubit to `idle` after attach invokes `onMemberIdle('lead')` on a fake bus. Must not pass `fromPtyQuietWatch: true`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/tab_member_materializer_test.dart --plain-name 'ACP'`

Expected: FAIL — still PTY inject / composer wait.

- [ ] **Step 3: Write minimal implementation**

`injectMemberStdin`:

```dart
final cubit = _tabStore
    .getOpenTabBySessionId(sessionId)
    ?.memberAcpRuntimes[memberId];
if (cubit != null) {
  cubit.sendPrompt(text);
  return;
}
// existing PTY path
```

`ensureMemberInputReady`: if `isAcpChatSeat(session, memberId)`, poll/listen until cubit is non-null and phase is `ready` or `idle` (reuse wait cap), then return.

Attach: `cubit.stream.listen` — when `state.phase == AcpChatPhase.idle`, `tab.teamBus?.onMemberIdle(member.id)`. Cancel the subscription in cubit `close` / tab dispose (cubit close is enough if the listen is on the cubit).

Queued doorbell during `launching` is already `_queuedPrompt` inside `sendPrompt`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/tab_member_materializer_test.dart test/services/chat/team_bus/idle_notification_test.dart`

Expected: PASS. Existing PTY idle tests unchanged.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/launch/session/tab_member_materializer.dart \
  client/lib/services/chat/launch/connect/acp_runtime_attach.dart \
  client/test/cubits/chat/tab_member_materializer_test.dart \
  client/test/services/chat/launch/
git commit -m "$(cat <<'EOF'
Route TeamBus wake and idle through ACP seats.

EOF
)"
```

---

### Task 11: Chat UI per selected seat

**Files:**
- Modify: `client/lib/pages/chat_workbench.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart` (`_usesAcpTranscript` must use the passed cubit / `isAcpChatSeat`, not only `isAcpChatSession`)
- Test: `client/test/pages/chat/session_chat_view_acp_test.dart`
- Test: add/extend a workbench test if one already selects members; otherwise a small pure helper test:

```dart
AcpChatRuntimeCubit? acpRuntimeForView({
  required AppSession session,
  required ChatTab tab,
  required String selectedMemberId,
}) {
  if (isAcpChatSession(session)) return tab.acpRuntime;
  return tab.memberAcpRuntimes[selectedMemberId];
}

bool hideTerminalToggle({
  required AppSession session,
  required String selectedMemberId,
}) =>
    isAcpChatSession(session) || isAcpChatSeat(session, selectedMemberId);
```

Put the helper next to workbench or in `chat_tab.dart`. Pages call it so the executor never grows `if (cli == …)`.

**Interfaces:**
- Consumes: `memberAcpRuntimes`, `isAcpChatSeat`
- Produces: chat view `acpRuntime` is the selected mixed member's cubit; terminal toggle hidden only for that ACP seat. PTY teammate still shows toggle. `onSubmit` uses the same helper (never PTY-inject an ACP seat).

- [ ] **Step 1: Write the failing tests**

Helper unit tests: simple ACP session → personal cubit + hide toggle. Mixed ACP lead selected → lead cubit + hide toggle. Mixed PTY worker selected → null cubit + show toggle.

`session_chat_view_acp_test.dart`: when `acpRuntime` is non-null, submit still goes to cubit even if `isAcpChatSession` is false (mixed seat). If the view currently gates on `isAcpChatSession` only, this test fails until `_usesAcpTranscript` includes `widget.acpRuntime != null` (it already does) **and** `onSubmit` in the workbench uses the helper instead of `isAcpChatSession` alone.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/session_chat_view_acp_test.dart`

Expected: FAIL or missing helper — mixed seat submit still waits for a shell.

- [ ] **Step 3: Write minimal implementation**

`chat_workbench.dart`: `acpRuntime: acpRuntimeForView(...)`, `viewToggle: hideTerminalToggle(...) ? null : viewToggle`. `onSubmit`: if helper returns a cubit, `sendPrompt`; if `isAcpChatSeat` but cubit is null, `failed()` (do not PTY). Else existing PTY path.

`session_chat_view.dart`: `_usesAcpTranscript` already ORs cubit; keep that. History hydrate must not load PTY history when `widget.acpRuntime != null`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/session_chat_view_acp_test.dart test/pages/chat/acp_seat_message_sync_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat_workbench.dart \
  client/lib/pages/chat/session_chat_view.dart \
  client/lib/services/chat/session/chat_tab.dart \
  client/test/pages/chat/
git commit -m "$(cat <<'EOF'
Bind mixed chat chrome to the selected ACP seat.

EOF
)"
```

---

### Task 12: Settings copy

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/config/cli_config_section_test.dart` (it already matches `'Personal sessions use ACP chat'`)

**Interfaces:**
- Consumes: existing preference keys (unchanged)
- Produces: new English/Chinese descriptions. Labels may stay "Personal sessions use ACP chat" **or** become "Sessions use ACP chat" if the config test is updated in the same task. Description must no longer say team sessions always use the terminal.

English description (Claude):

`Run new personal and mixed-team Claude sessions as terminal-less ACP chat via claude-agent-acp. Existing sessions stay as they were started. Native teams and remote members still use the terminal.`

English description (Codex): same shape with `codex-acp`.

Chinese:

`新建个人和混合团队 Claude 会话走无终端 ACP（claude-agent-acp）。已有会话保持原启动方式。原生团队和远程成员仍用终端。`

- [ ] **Step 1: Write the failing test**

In `cli_config_section_test.dart`, expect the new description substring `'mixed-team'` / `'混合团队'` (or the exact new sentence). If the test only checks the label, add one `find.textContaining('Native teams')`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart --plain-name 'ACP'`

Expected: FAIL — old copy.

- [ ] **Step 3: Update arb and generate l10n**

Edit `app_en.arb` and `app_zh.arb` only. Then:

Run: `cd client && flutter gen-l10n`

Do not hand-edit `app_localizations*.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations*.dart \
  client/test/pages/config/cli_config_section_test.dart
git commit -m "$(cat <<'EOF'
Document mixed-team ACP on Claude and Codex settings.

EOF
)"
```

---

## Self-review (spec coverage)

| Spec requirement | Task |
|------------------|------|
| `SessionMemberBinding.acp` JSON / equality | 1 |
| `isAcpChatSeat` binding-only; personal `isAcpChatSession` unchanged | 2 |
| Create stamp + Gemini always + native/SSH/Android false | 3–4 |
| Team `AppSession.acp` false | 4 |
| `memberAcpRuntimes` + personal alias | 5 |
| `mcpServers` on `session/new`; personal empty | 6 |
| `seatMemberId` | 7 |
| Extract attach; `prepareTeamConnect`; per-member transcript | 8 |
| Executor after TeamBus; `onResult` attached; no PTY fallback | 9 |
| wake → `sendPrompt`; idle → `onMemberIdle`; input-ready | 10 |
| Selected-member chrome / no session-level toggle for mixed PTY sibling | 11 |
| Settings copy | 12 |
| No TeamBus protocol change | (reuse, task 10) |
| No native / SSH / Cursor / compose toggle | out of scope, no task |

No TBD/TODO left in task bodies. `attachMemberAcpRuntime` / `stampMemberAcp` / `acpMcpServersFromExtra` names are used consistently across tasks.
