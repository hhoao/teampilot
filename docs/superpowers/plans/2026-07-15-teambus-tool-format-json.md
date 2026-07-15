# TeamBus MCP JSON format Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert every encoder in `TeammateBusToolFormat` to compact JSON success bodies (empty collections when empty), including roster `machine` / `machine_kind` / `machine_id` when profile fields are set.

**Architecture:** Replace prose builders with `Map`/`List` + `jsonEncode`. Shared omit-empty helper. Machine keys read from `TeammateRosterProfile` (filled by prerequisite install plan). Update MCP handler tests and tool descriptions.

**Tech Stack:** Dart `dart:convert`, existing TeamBus MCP tools / handler tests.

**Spec:** [`2026-07-15-mixed-team-machine-ui-and-teambus-json-design.md`](../specs/2026-07-15-mixed-team-machine-ui-and-teambus-json-design.md) Track B

**Prerequisite:** [`2026-07-15-list-teammates-machine.md`](./2026-07-15-list-teammates-machine.md) must land first (profile `machine` / `machineKind` / `machineId` + install cwd). If those fields are not yet on `TeammateRosterProfile`, stop and finish that plan before Task 2 machine assertions.

**Independent of:** Members UI grouping plan.

---

## File map

| Path | Responsibility |
|------|----------------|
| Modify: `client/lib/services/team_bus/mcp/toolkit/teammate_bus_tool_format.dart` | All encoders → JSON |
| Create: `client/test/services/team_bus/mcp/teammate_bus_tool_format_test.dart` | Unit tests for each encoder |
| Modify: `client/test/services/team_bus/mcp/teammate_bus_mcp_handler_test.dart` | Assert JSON instead of prose |
| Modify: `client/test/integration/mixed_team_bus_comm_tasks_integration_test.dart` | Replace `ASSIGNED TASK` prose assertions with JSON task shape |
| Modify: `client/lib/services/team_bus/mcp/tools/send_message_tool.dart` | Append hint with `\n` + always-JSON `known_recipients` |
| Modify: tool description strings in `list_teammates_tool.dart`, `list_tasks_tool.dart`, `claim_task_tool.dart`, `read_messages_tool.dart`, `wait_for_message_tool.dart` | Document JSON + dual wait shapes + post-claim loop |

---

### Task 1: Failing format unit tests (TDD)

**Files:**
- Create: `client/test/services/team_bus/mcp/teammate_bus_tool_format_test.dart`

- [ ] **Step 1: Write failing tests** (import paths / helpers as needed from existing TeamBus fixtures)

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/mcp/toolkit/teammate_bus_tool_format.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/teammate_roster_profile.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';
import 'package:teampilot/services/team_bus/team_message.dart';
// + FakeMemberLauncher / TaskQueue from existing test support

void main() {
  test('encodeRoster empty → members []', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    final raw = TeammateBusToolFormat.encodeRoster(bus, 'lead');
    final json = jsonDecode(raw) as Map<String, Object?>;
    expect(json['caller'], 'lead');
    expect(json['members'], isEmpty);
    expect(raw.trimLeft(), startsWith('{'));
  });

  test('encodeRoster member includes machine keys when profile set', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    // After prerequisite plan: TeammateRosterProfile has machine/machineKind/machineId.
    bus.declareMember(
      AgentNode(
        profile: TeammateRosterProfile(
          memberId: 'dev',
          displayName: 'Dev',
          cwd: '/work',
          machine: 'root@h:22',
          machineKind: 'ssh',
          machineId: 'ssh:p1',
        ),
      ),
    );
    final json = jsonDecode(
      TeammateBusToolFormat.encodeRoster(bus, 'dev'),
    ) as Map<String, Object?>;
    final member = (json['members'] as List).single as Map<String, Object?>;
    expect(member['machine'], 'root@h:22');
    expect(member['machine_kind'], 'ssh');
    expect(member['machine_id'], 'ssh:p1');
    expect(member['cwd'], '/work');
    expect(member['self'], isTrue);
  });

  test('encodeTasks empty → {tasks:[]}', () {
    final bus = TeamBus(launcher: FakeMemberLauncher(), taskQueue: TaskQueue());
    bus.declareMember(AgentNode.test(memberId: 'w'));
    expect(
      jsonDecode(TeammateBusToolFormat.encodeTasks(bus, const [], 'w')),
      {'tasks': <Object>[]},
    );
  });

  test('encodeTaskAssignment is bare task object without ASSIGNED prose', () {
    const task = TeamTask(
      id: 't1',
      seq: 1,
      title: 'ship',
      brief: 'do X',
      createdBy: 'lead',
      createdAt: 1,
      status: TaskStatus.claimed,
      assignee: 'w',
    );
    final raw = TeammateBusToolFormat.encodeTaskAssignment(task);
    expect(raw, isNot(contains('ASSIGNED TASK')));
    final json = jsonDecode(raw) as Map<String, Object?>;
    expect(json['id'], 't1');
    expect(json['title'], 'ship');
    expect(json['brief'], 'do X');
  });

  test('encodeBatch empty → {messages:[]}', () {
    expect(
      jsonDecode(TeammateBusToolFormat.encodeBatch(const [])),
      {'messages': <Object>[]},
    );
  });

  test('encodeMessagePage empty keeps unread fields', () {
    const page = BusMessagePage(
      messages: [],
      hasMore: false,
      totalUnread: 2,
    );
    final json = jsonDecode(
      TeammateBusToolFormat.encodeMessagePage(page),
    ) as Map<String, Object?>;
    expect(json['messages'], isEmpty);
    expect(json['total_unread'], 2);
    expect(json['has_more'], isFalse);
  });

  test('encodeRoster omits machine trio when machineId empty', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(memberId: 'dev'));
    final json = jsonDecode(
      TeammateBusToolFormat.encodeRoster(bus, 'dev'),
    ) as Map<String, Object?>;
    final member = (json['members'] as List).single as Map<String, Object?>;
    expect(member.containsKey('machine'), isFalse);
    expect(member.containsKey('machine_kind'), isFalse);
    expect(member.containsKey('machine_id'), isFalse);
  });

  test('unknownRecipientHint is JSON object', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(memberId: 'a', displayName: 'A'));
    final raw = TeammateBusToolFormat.unknownRecipientHint(bus);
    final json = jsonDecode(raw) as Map<String, Object?>;
    expect(json['known_recipients'], isA<List>());
  });
}
```

Adjust fixtures to match real constructors (`TeamTask`, `AgentNode.test`, `BusMessagePage`) by reading those types before coding — do not invent fields.

- [ ] **Step 2: Run — expect FAIL** (still prose / wrong shape)

Run: `cd client && flutter test test/services/team_bus/mcp/teammate_bus_tool_format_test.dart`

---

### Task 2: Implement JSON encoders

**Files:**
- Modify: `client/lib/services/team_bus/mcp/toolkit/teammate_bus_tool_format.dart`

- [ ] **Step 1: Add helpers at top of class**

```dart
static String _encode(Object? value) => jsonEncode(value);

static Map<String, Object?> _omitEmpty(Map<String, Object?> map) {
  return {
    for (final e in map.entries)
      if (e.value != null &&
          e.value != '' &&
          !(e.value is List && (e.value as List).isEmpty) &&
          !(e.value is Map && (e.value as Map).isEmpty))
        e.key: e.value!,
  };
}
```

Keep required empty collections **outside** `_omitEmpty` (e.g. always include `"tasks": []`).

- [ ] **Step 2: Rewrite `formatTeammate` → `Map`, `encodeRoster` → JSON**

Member map keys (snake_case) per spec. Include machine trio only when `profile.machineId.isNotEmpty`. Set `"self": true` only when `isSelf` (omit when false). Nest `bus: {lifecycle, activity, phase, unread}`.

Roster top-level: `caller`, optional `team` object, `members` list.

- [ ] **Step 3: Rewrite task / message encoders**

- `encodeTasks` → `{"tasks":[...]}`
- `formatTask` → map; `encodeTaskAssignment` → `_encode(formatTask(..., full: true))` with no prose wrapper
- `encodeMessagePage` / `encodeBatch` / `formatMessage` per spec (`kind`: `message`|`idle`)
- `unknownRecipientHint` → always `{"known_recipients":[...]}` (empty roster → `{"known_recipients":[]}`, never `''`)
- `send_message_tool.dart`: append as `'$reason\n${TeammateBusToolFormat.unknownRecipientHint(bus)}'` (newline separator)

- [ ] **Step 4: Run format tests — PASS**

Run: `cd client && flutter test test/services/team_bus/mcp/teammate_bus_tool_format_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team_bus/mcp/toolkit/teammate_bus_tool_format.dart \
  client/test/services/team_bus/mcp/teammate_bus_tool_format_test.dart
git commit -m "feat: emit TeamBus MCP tool payloads as JSON"
```

---

### Task 3: Update MCP handler tests + tool descriptions

**Files:**
- Modify: `client/test/services/team_bus/mcp/teammate_bus_mcp_handler_test.dart`
- Modify: `client/lib/services/team_bus/mcp/tools/list_teammates_tool.dart`
- Modify: `client/lib/services/team_bus/mcp/tools/list_tasks_tool.dart`
- Modify: `client/lib/services/team_bus/mcp/tools/claim_task_tool.dart`
- Modify: `client/lib/services/team_bus/mcp/tools/read_messages_tool.dart`
- Modify: `client/lib/services/team_bus/mcp/tools/wait_for_message_tool.dart`
- Grep for other prose assertions across `test/` (not only MCP): `ASSIGNED TASK`, `--- `, `No teammates`, `Work queue`, `FROM user`

- [ ] **Step 1: Fix handler + integration tests**

Update `mixed_team_bus_comm_tasks_integration_test.dart` wherever it expects `ASSIGNED TASK` / prose `update_task` coaching — assert bare task JSON (`title` / `id` / `brief`) instead.

Example for `list_teammates`:

```dart
final text = (res!.result!['content'] as List).first['text'] as String;
final json = jsonDecode(text) as Map<String, Object?>;
final members = json['members'] as List;
expect(members, hasLength(2));
// find self / unread via maps
```

Example for auto-claim wait:

```dart
final json = jsonDecode(text['text'] as String) as Map<String, Object?>;
expect(json['title'], 'ship it');
expect(json.containsKey('messages'), isFalse);
expect(text['text'], isNot(contains('ASSIGNED TASK')));
```

- [ ] **Step 2: Update descriptions**

- `list_teammates`: returns JSON; members include `machine` / `machine_kind` / `machine_id` / `cwd` when available
- `claim_task`: returns claimed task JSON; then `update_task` → `wait_for_message`
- `wait_for_message`: returns **either** `{"messages":[...]}` **or** a bare task object (`id`/`status`/`title`/`brief`); after handling, call `wait_for_message` again; on task do `update_task` first
- `list_tasks` / `read_messages`: mention JSON envelopes

- [ ] **Step 3: Run handler + format tests**

Run:

```bash
cd client && flutter test \
  test/services/team_bus/mcp/teammate_bus_tool_format_test.dart \
  test/services/team_bus/mcp/teammate_bus_mcp_handler_test.dart
```

Expected: PASS

- [ ] **Step 4: Broader grep + analyze**

```bash
cd client && rg -n "ASSIGNED TASK|No teammates registered|Work queue \(|--- .* ---" test lib/services/team_bus/mcp || true
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/services/team_bus/mcp
```

Fix any remaining prose assertions under MCP.

- [ ] **Step 5: Commit**

```bash
git add client/test/services/team_bus/mcp/teammate_bus_mcp_handler_test.dart \
  client/lib/services/team_bus/mcp/tools/*.dart
git commit -m "test: align TeamBus MCP handlers with JSON tool payloads"
```

---

## Verification

```bash
cd client && flutter test \
  test/services/team_bus/mcp/teammate_bus_tool_format_test.dart \
  test/services/team_bus/mcp/teammate_bus_mcp_handler_test.dart
# Integration (tag): only if environment supports it
# cd client && flutter test --tags integration test/integration/mixed_team_bus_comm_tasks_integration_test.dart
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

## Execution order (multi-plan)

1. Finish [`2026-07-15-list-teammates-machine.md`](./2026-07-15-list-teammates-machine.md) if not done  
2. This plan (Track B)  
3. [`2026-07-15-members-machine-groups.md`](./2026-07-15-members-machine-groups.md) can run in parallel with (1) or (2)
