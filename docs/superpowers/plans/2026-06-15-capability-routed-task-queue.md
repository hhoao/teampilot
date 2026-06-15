# Capability-Routed Task Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route TeamBus mixed-mode work-queue tasks to suitable members via capability tag-set matching, hybrid push/pull claiming, and tiered degradation with capability-aware engagement.

**Architecture:** A pure `TaskRouter` module decides eligibility (`memberCaps ⊇ task.requiredCapabilities`), scores fit against `preferredCapabilities`, and advances a monotonic `RoutingStage` (reserved → matched → widened → open). Both the auto-dispatch path (`TaskQueue.claimNext`) and the new self-pick path (`TaskQueue.claimSpecific` / MCP `claim_task`) funnel through the same synchronous, lock-free atomic claim guarded by `TaskRouter.eligible`. `TeamBus` passes member capabilities into claims, makes worker engagement capability-aware, and drives stage reconciliation on a timer.

**Tech Stack:** Dart / Flutter, `flutter_test`, `fake_async`. All code under `client/lib/services/team_bus/` and tests under `client/test/services/team_bus/`.

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `client/lib/models/team_config.dart` | `TeamMemberConfig.capabilities` persisted field | Modify |
| `client/lib/services/team_bus/teammate_roster_profile.dart` | `TeammateRosterProfile.capabilities` (with agentType/agent derivation) | Modify |
| `client/lib/services/team_bus/agent_node.dart` | `AgentNode.test` accepts `capabilities` | Modify |
| `client/lib/services/team_bus/tasks/team_task.dart` | `RoutingStage`, `RoutingPolicy`, new `TeamTask`/`TeamTaskDraft` fields | Modify |
| `client/lib/services/team_bus/tasks/task_router.dart` | **Pure** eligibility / scoring / stage transitions | Create |
| `client/lib/services/team_bus/tasks/task_log.dart` | `appendEscalate` event in interface | Modify |
| `client/lib/services/team_bus/tasks/file_task_log.dart` | Persist new fields + escalate event | Modify |
| `client/lib/services/team_bus/tasks/in_memory_task_log.dart` | Persist new fields + escalate event | Modify |
| `client/lib/services/team_bus/tasks/task_queue.dart` | `claimNext(id, caps)`, `claimSpecific`, `reconcile` | Modify |
| `client/lib/services/team_bus/team_bus.dart` | Pass caps, capability-aware engagement, reconcile driver | Modify |
| `client/lib/services/team_bus/mcp/teammate_bus_mcp_handler.dart` | `add_tasks` fields, `list_tasks` annotation, `claim_task` tool | Modify |

**Note on existing tests:** `claimNext` and `claimNextTask` change signatures. Tasks 5 and 6 update the existing call sites and tests (`task_queue_test.dart`, `team_bus_tasks_test.dart`) as part of their steps. Empty-capability tasks must remain eligible to everyone so existing behavior is preserved.

---

## Task 1: Member capabilities (model + roster)

**Files:**
- Modify: `client/lib/models/team_config.dart`
- Modify: `client/lib/services/team_bus/teammate_roster_profile.dart`
- Modify: `client/lib/services/team_bus/agent_node.dart`
- Test: `client/test/services/team_bus/teammate_roster_profile_capabilities_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `client/test/services/team_bus/teammate_roster_profile_capabilities_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team_bus/teammate_roster_profile.dart';

void main() {
  TeamConfig team() => const TeamConfig(
        id: 'team-1',
        name: 'Team One',
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
      );

  test('explicit member capabilities flow into the roster profile', () {
    final member = const TeamMemberConfig(
      id: 'dev',
      name: 'Dev',
      capabilities: {'backend', 'rust'},
    );
    final profile = TeammateRosterProfile.fromMember(
      member: member,
      team: team(),
      cliTeamName: 'team-1-1',
      cwd: '/tmp',
    );
    expect(profile.capabilities, {'backend', 'rust'});
  });

  test('empty capabilities derive from agentType then agent', () {
    final fromType = TeammateRosterProfile.fromMember(
      member: const TeamMemberConfig(id: 'fe', name: 'FE', agentType: 'frontend'),
      team: team(),
      cliTeamName: 'team-1-1',
      cwd: '/tmp',
    );
    expect(fromType.capabilities, {'frontend'});

    final fromAgent = TeammateRosterProfile.fromMember(
      member: const TeamMemberConfig(id: 'qa', name: 'QA', agent: 'tester'),
      team: team(),
      cliTeamName: 'team-1-1',
      cwd: '/tmp',
    );
    expect(fromAgent.capabilities, {'tester'});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/team_bus/teammate_roster_profile_capabilities_test.dart`
Expected: FAIL — `capabilities` is not a parameter of `TeamMemberConfig` / `TeammateRosterProfile`.

- [ ] **Step 3: Add `capabilities` to `TeamMemberConfig`**

In `client/lib/models/team_config.dart`, inside `class TeamMemberConfig`:

Add to the constructor parameter list (after `this.agentType = '',`):

```dart
    this.capabilities = const {},
```

Add to `fromJson` (after the `agentType:` line):

```dart
      capabilities: {
        for (final c in (json['capabilities'] as List?) ?? const [])
          if (c is String && c.trim().isNotEmpty) c.trim(),
      },
```

Add the field declaration (after `final String agentType;` block):

```dart
  /// Capability tags used by TeamBus task routing (mixed mode). Empty ⇒ derived
  /// from [agentType]/[agent] in [TeammateRosterProfile]. Subset-matched against
  /// a task's required capabilities.
  final Set<String> capabilities;
```

Add to `copyWith` parameters and body:

```dart
    Set<String>? capabilities,
```
and in the returned `TeamMemberConfig(...)`:
```dart
      capabilities: capabilities ?? this.capabilities,
```

Add to `toJson` (find the method; mirror the `agentType` guarded entry):

```dart
      if (capabilities.isNotEmpty) 'capabilities': capabilities.toList(),
```

Add `capabilities` to the `==` operator and `hashCode` (mirror existing `agentType` entries — for the set use `const SetEquality<String>().equals(capabilities, other.capabilities)` is overkill; instead compare via `capabilities.length == other.capabilities.length && capabilities.containsAll(other.capabilities)`). Concretely, in `operator ==` add:

```dart
            capabilities.length == other.capabilities.length &&
            capabilities.containsAll(other.capabilities) &&
```

and in `hashCode` add `Object.hashAllUnordered(capabilities)` to the `Object.hash(...)` argument list.

- [ ] **Step 4: Add `capabilities` to `TeammateRosterProfile`**

In `client/lib/services/team_bus/teammate_roster_profile.dart`:

Add to the main constructor (after `this.backendType = '',`):

```dart
    this.capabilities = const {},
```

Add to the `minimal` factory's returned object (after `agentType:` line):

```dart
      capabilities: const {},
```

In `fromMember`, before the `return TeammateRosterProfile(`, compute derived caps:

```dart
    final caps = member.capabilities.isNotEmpty
        ? member.capabilities
        : <String>{
            if (member.agentType.trim().isNotEmpty)
              member.agentType.trim()
            else if (member.agent.trim().isNotEmpty)
              member.agent.trim(),
          }..removeWhere((c) => c.isEmpty);
```

Add to the `fromMember` returned object (after `backendType:` line):

```dart
      capabilities: caps,
```

Add the field declaration (after `final String backendType;`):

```dart
  /// Capability tags for TeamBus task routing. Derived from [TeamMemberConfig].
  final Set<String> capabilities;
```

- [ ] **Step 5: Add `capabilities` to `AgentNode.test`**

In `client/lib/services/team_bus/agent_node.dart`, the `AgentNode.test` factory: add parameter `Set<String> capabilities = const {},` and pass it into `TeammateRosterProfile.minimal` by adding a `capabilities` argument. First, give `minimal` a `capabilities` parameter:

In `teammate_roster_profile.dart` `minimal` factory signature add `Set<String> capabilities = const {},` and set `capabilities: capabilities,` in its returned object (replacing the `const {}` from Step 4).

Then in `agent_node.dart` `AgentNode.test`:

```dart
  factory AgentNode.test({
    required String memberId,
    MemberLifecycle lifecycle = MemberLifecycle.declared,
    MemberActivity activity = MemberActivity.none,
    String? displayName,
    String? cli,
    bool isTeamLead = false,
    Set<String> capabilities = const {},
  }) {
    return AgentNode(
      profile: TeammateRosterProfile.minimal(
        memberId,
        displayName: displayName,
        cli: cli,
        isTeamLead: isTeamLead,
        capabilities: capabilities,
      ),
      lifecycle: lifecycle,
      activity: activity,
    );
  }
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd client && flutter test test/services/team_bus/teammate_roster_profile_capabilities_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add client/lib/models/team_config.dart client/lib/services/team_bus/teammate_roster_profile.dart client/lib/services/team_bus/agent_node.dart client/test/services/team_bus/teammate_roster_profile_capabilities_test.dart
git commit -m "feat(team-bus): add capability tags to member config and roster profile"
```

---

## Task 2: Routing types on TeamTask

**Files:**
- Modify: `client/lib/services/team_bus/tasks/team_task.dart`
- Test: `client/test/services/team_bus/tasks/team_task_routing_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `client/test/services/team_bus/tasks/team_task_routing_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';

void main() {
  test('task defaults: no caps, matched stage, no preferred assignee', () {
    const t = TeamTask(
      id: 't0',
      seq: 0,
      title: 'a',
      brief: 'b',
      createdBy: 'lead',
      createdAt: 0,
    );
    expect(t.requiredCapabilities, isEmpty);
    expect(t.preferredCapabilities, isEmpty);
    expect(t.preferredAssignee, isNull);
    expect(t.routing.stage, RoutingStage.matched);
  });

  test('copyWith replaces the routing policy', () {
    const t = TeamTask(
      id: 't0', seq: 0, title: 'a', brief: 'b', createdBy: 'lead', createdAt: 0,
    );
    final r = t.copyWith(
      routing: t.routing.copyWith(stage: RoutingStage.open, escalatedAt: 5),
    );
    expect(r.routing.stage, RoutingStage.open);
    expect(r.routing.escalatedAt, 5);
    expect(t.routing.stage, RoutingStage.matched); // original unchanged
  });

  test('draft carries routing inputs', () {
    const d = TeamTaskDraft(
      title: 'a',
      brief: 'b',
      requiredCapabilities: {'backend'},
      preferredCapabilities: {'rust'},
      preferredAssignee: 'dev2',
    );
    expect(d.requiredCapabilities, {'backend'});
    expect(d.preferredCapabilities, {'rust'});
    expect(d.preferredAssignee, 'dev2');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/team_bus/tasks/team_task_routing_test.dart`
Expected: FAIL — `RoutingStage`/`routing`/`requiredCapabilities` undefined.

- [ ] **Step 3: Add routing types and fields**

In `client/lib/services/team_bus/tasks/team_task.dart`, add at the top (after the imports/`TaskStatus` enum):

```dart
/// 任务路由阶段（单调推进，永不收窄）。reserved 仅 [TeamTask.preferredAssignee]
/// 可领;matched 按能力子集匹配;widened 放宽到 preferredCapabilities;open 全员可领。
enum RoutingStage { reserved, matched, widened, open }

/// 任务的路由策略:当前阶段 + 进入该阶段的时间戳 + 三个升级时间窗。
class RoutingPolicy {
  const RoutingPolicy({
    this.stage = RoutingStage.matched,
    this.escalatedAt = 0,
    this.reserveWindowMs = 45 * 1000,
    this.widenAfterMs = 120 * 1000,
    this.openAfterMs = 300 * 1000,
  });

  final RoutingStage stage;

  /// 进入当前 [stage] 的时刻;每次阶段迁移重置,使各时间窗从阶段起点计。
  final int escalatedAt;
  final int reserveWindowMs;
  final int widenAfterMs;
  final int openAfterMs;

  RoutingPolicy copyWith({
    RoutingStage? stage,
    int? escalatedAt,
    int? reserveWindowMs,
    int? widenAfterMs,
    int? openAfterMs,
  }) {
    return RoutingPolicy(
      stage: stage ?? this.stage,
      escalatedAt: escalatedAt ?? this.escalatedAt,
      reserveWindowMs: reserveWindowMs ?? this.reserveWindowMs,
      widenAfterMs: widenAfterMs ?? this.widenAfterMs,
      openAfterMs: openAfterMs ?? this.openAfterMs,
    );
  }

  static RoutingStage parseStage(String? raw) {
    for (final s in RoutingStage.values) {
      if (s.name == raw) return s;
    }
    return RoutingStage.matched;
  }
}
```

In `class TeamTask`, add constructor params (after `this.dependsOn = const [],`):

```dart
    this.requiredCapabilities = const {},
    this.preferredCapabilities = const {},
    this.preferredAssignee,
    this.routing = const RoutingPolicy(),
```

Add field declarations (after `final List<String> dependsOn;`):

```dart
  /// 硬性能力要求(子集匹配):`member.capabilities ⊇ requiredCapabilities` 才合格。
  /// 空集 = 可互换,谁都能干。
  final Set<String> requiredCapabilities;

  /// 软性偏好能力:多个合格者之间打分排序用,不参与硬过滤。
  final Set<String> preferredCapabilities;

  /// 点名优先认领者(memberId);驱动 [RoutingStage.reserved] 阶段。
  final String? preferredAssignee;

  /// 路由阶段与时间窗。
  final RoutingPolicy routing;
```

Update `copyWith` — add params:

```dart
    Set<String>? requiredCapabilities,
    Set<String>? preferredCapabilities,
    String? preferredAssignee,
    RoutingPolicy? routing,
```

and in the returned `TeamTask(...)` add:

```dart
      requiredCapabilities: requiredCapabilities ?? this.requiredCapabilities,
      preferredCapabilities: preferredCapabilities ?? this.preferredCapabilities,
      preferredAssignee: preferredAssignee ?? this.preferredAssignee,
      routing: routing ?? this.routing,
```

In `class TeamTaskDraft`, add constructor params (after `this.dependsOn = const [],`):

```dart
    this.requiredCapabilities = const {},
    this.preferredCapabilities = const {},
    this.preferredAssignee,
```

and fields:

```dart
  final Set<String> requiredCapabilities;
  final Set<String> preferredCapabilities;
  final String? preferredAssignee;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/team_bus/tasks/team_task_routing_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team_bus/tasks/team_task.dart client/test/services/team_bus/tasks/team_task_routing_test.dart
git commit -m "feat(team-bus): add capability and routing fields to TeamTask"
```

---

## Task 3: TaskRouter pure module

**Files:**
- Create: `client/lib/services/team_bus/tasks/task_router.dart`
- Test: `client/test/services/team_bus/tasks/task_router_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `client/test/services/team_bus/tasks/task_router_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/tasks/task_router.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';

TeamTask task({
  Set<String> required = const {},
  Set<String> preferred = const {},
  String? assignee,
  RoutingStage stage = RoutingStage.matched,
  int escalatedAt = 0,
}) {
  return TeamTask(
    id: 't', seq: 0, title: 'a', brief: 'b', createdBy: 'lead', createdAt: 0,
    requiredCapabilities: required,
    preferredCapabilities: preferred,
    preferredAssignee: assignee,
    routing: RoutingPolicy(stage: stage, escalatedAt: escalatedAt),
  );
}

void main() {
  group('eligible', () {
    test('empty requirements ⇒ anyone eligible at matched', () {
      expect(TaskRouter.eligible('w1', const {}, task()), isTrue);
    });

    test('subset match required at matched stage', () {
      final t = task(required: {'backend'});
      expect(TaskRouter.eligible('w1', {'backend', 'rust'}, t), isTrue);
      expect(TaskRouter.eligible('w2', {'frontend'}, t), isFalse);
    });

    test('reserved stage admits only the preferred assignee', () {
      final t = task(required: {'backend'}, assignee: 'dev2',
          stage: RoutingStage.reserved);
      expect(TaskRouter.eligible('dev2', {'backend'}, t), isTrue);
      expect(TaskRouter.eligible('other', {'backend'}, t), isFalse);
    });

    test('widened stage relaxes required to preferred', () {
      final t = task(required: {'backend'}, preferred: {'rust'},
          stage: RoutingStage.widened);
      // no longer needs backend; needs preferred (rust)
      expect(TaskRouter.eligible('w1', {'rust'}, t), isTrue);
      expect(TaskRouter.eligible('w2', {'go'}, t), isFalse);
    });

    test('open stage admits everyone', () {
      final t = task(required: {'backend'}, stage: RoutingStage.open);
      expect(TaskRouter.eligible('w1', const {}, t), isTrue);
    });
  });

  group('score', () {
    test('counts overlap with preferred capabilities', () {
      final t = task(preferred: {'rust', 'async', 'db'});
      expect(TaskRouter.score({'rust', 'db', 'frontend'}, t), 2);
      expect(TaskRouter.score(const {}, t), 0);
    });
  });

  group('nextStage', () {
    test('reserved → matched after reserve window', () {
      final t = task(assignee: 'd', stage: RoutingStage.reserved, escalatedAt: 0);
      expect(TaskRouter.nextStage(t, 44 * 1000, true), RoutingStage.reserved);
      expect(TaskRouter.nextStage(t, 45 * 1000, true), RoutingStage.matched);
    });

    test('matched stays while an eligible live member exists', () {
      final t = task(required: {'backend'}, escalatedAt: 0);
      expect(TaskRouter.nextStage(t, 999 * 1000, true), RoutingStage.matched);
    });

    test('matched → widened after widen window with no eligible live member', () {
      final t = task(required: {'backend'}, escalatedAt: 0);
      expect(TaskRouter.nextStage(t, 119 * 1000, false), RoutingStage.matched);
      expect(TaskRouter.nextStage(t, 120 * 1000, false), RoutingStage.widened);
    });

    test('widened → open after open window with no eligible live member', () {
      final t = task(stage: RoutingStage.widened, escalatedAt: 0);
      expect(TaskRouter.nextStage(t, 299 * 1000, false), RoutingStage.widened);
      expect(TaskRouter.nextStage(t, 300 * 1000, false), RoutingStage.open);
    });

    test('open is terminal', () {
      final t = task(stage: RoutingStage.open, escalatedAt: 0);
      expect(TaskRouter.nextStage(t, 999 * 1000, false), RoutingStage.open);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/team_bus/tasks/task_router_test.dart`
Expected: FAIL — `task_router.dart` does not exist.

- [ ] **Step 3: Create the TaskRouter module**

Create `client/lib/services/team_bus/tasks/task_router.dart`:

```dart
import 'team_task.dart';

/// 任务路由的**纯函数**核心:合格性、打分、阶段迁移。无 IO、无自有时钟(时间由调用
/// 方传入)。push([TaskQueue.claimNext])、pull([TaskQueue.claimSpecific])、reconcile
/// 三条路径共用同一套判定,保证语义一致。
class TaskRouter {
  const TaskRouter._();

  /// 任务在**当前阶段**实际要求的能力集合。matched 用硬性 required;widened 放宽到
  /// preferred;open 无要求;reserved 同 matched(再叠加点名门控,见 [eligible])。
  static Set<String> effectiveRequiredCaps(TeamTask t) {
    switch (t.routing.stage) {
      case RoutingStage.reserved:
      case RoutingStage.matched:
        return t.requiredCapabilities;
      case RoutingStage.widened:
        return t.preferredCapabilities;
      case RoutingStage.open:
        return const {};
    }
  }

  /// 成员对任务是否合格:reserved 阶段仅点名者;其余阶段按 `caps ⊇ 当前要求` 判定。
  static bool eligible(String memberId, Set<String> memberCaps, TeamTask t) {
    if (t.routing.stage == RoutingStage.reserved) {
      final assignee = t.preferredAssignee;
      if (assignee != null && assignee != memberId) return false;
    }
    final required = effectiveRequiredCaps(t);
    for (final cap in required) {
      if (!memberCaps.contains(cap)) return false;
    }
    return true;
  }

  /// 适配度打分:与 preferredCapabilities 的交集大小。越大越合适。
  static int score(Set<String> memberCaps, TeamTask t) {
    var n = 0;
    for (final cap in t.preferredCapabilities) {
      if (memberCaps.contains(cap)) n++;
    }
    return n;
  }

  /// 给定当前时间与「是否存在合格的在线成员」,算出下一阶段(单调,不回退)。
  /// 只有在**无合格在线成员**且超过对应时间窗时才降级要求,实现「先拉人、后放宽」。
  static RoutingStage nextStage(TeamTask t, int now, bool hasEligibleLiveMember) {
    final r = t.routing;
    final elapsed = now - r.escalatedAt;
    switch (r.stage) {
      case RoutingStage.reserved:
        return elapsed >= r.reserveWindowMs
            ? RoutingStage.matched
            : RoutingStage.reserved;
      case RoutingStage.matched:
        return (!hasEligibleLiveMember && elapsed >= r.widenAfterMs)
            ? RoutingStage.widened
            : RoutingStage.matched;
      case RoutingStage.widened:
        return (!hasEligibleLiveMember && elapsed >= r.openAfterMs)
            ? RoutingStage.open
            : RoutingStage.widened;
      case RoutingStage.open:
        return RoutingStage.open;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/team_bus/tasks/task_router_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team_bus/tasks/task_router.dart client/test/services/team_bus/tasks/task_router_test.dart
git commit -m "feat(team-bus): add pure TaskRouter (eligibility, scoring, stage transitions)"
```

---

## Task 4: Persist routing fields in the task log

**Files:**
- Modify: `client/lib/services/team_bus/tasks/task_log.dart`
- Modify: `client/lib/services/team_bus/tasks/file_task_log.dart`
- Modify: `client/lib/services/team_bus/tasks/in_memory_task_log.dart`
- Test: `client/test/services/team_bus/tasks/file_task_log_routing_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `client/test/services/team_bus/tasks/file_task_log_routing_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/memory_filesystem.dart';
import 'package:teampilot/services/team_bus/tasks/file_task_log.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';

void main() {
  test('add persists caps + routing; escalate replays the stage', () async {
    final fs = MemoryFilesystem();
    final log = FileTaskLog(queueRoot: '/q', fs: fs);

    await log.appendAdd(const TeamTask(
      id: 't0', seq: 0, title: 'a', brief: 'b', createdBy: 'lead', createdAt: 1,
      requiredCapabilities: {'backend'},
      preferredCapabilities: {'rust'},
      preferredAssignee: 'dev2',
      routing: RoutingPolicy(stage: RoutingStage.reserved, escalatedAt: 1),
    ));
    await log.appendEscalate('t0', RoutingStage.open, 99);

    final loaded = await log.load();
    final t = loaded.single;
    expect(t.requiredCapabilities, {'backend'});
    expect(t.preferredCapabilities, {'rust'});
    expect(t.preferredAssignee, 'dev2');
    expect(t.routing.stage, RoutingStage.open);
    expect(t.routing.escalatedAt, 99);
  });
}
```

If `MemoryFilesystem` does not exist under that import path, find the in-memory filesystem used elsewhere in tests:
Run: `cd client && grep -rl "implements Filesystem" test lib | head` and use that class + import. Adjust the import line accordingly.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/team_bus/tasks/file_task_log_routing_test.dart`
Expected: FAIL — `appendEscalate` undefined; caps/routing not persisted.

- [ ] **Step 3: Add `appendEscalate` to the interface**

In `client/lib/services/team_bus/tasks/task_log.dart`, add (after `appendReclaim`):

```dart
  /// 追加一条路由阶段升级事件(单调推进)。
  Future<void> appendEscalate(String taskId, RoutingStage stage, int at);
```

- [ ] **Step 4: Persist in FileTaskLog**

In `client/lib/services/team_bus/tasks/file_task_log.dart`:

Replace `appendAdd` body's map with one that includes the new fields:

```dart
  @override
  Future<void> appendAdd(TeamTask task) {
    return _append({
      't': 'add',
      'seq': task.seq,
      'id': task.id,
      'title': task.title,
      'brief': task.brief,
      'by': task.createdBy,
      'deps': task.dependsOn,
      'createdAt': task.createdAt,
      'reqCaps': task.requiredCapabilities.toList(),
      'prefCaps': task.preferredCapabilities.toList(),
      'assignee': task.preferredAssignee,
      'stage': task.routing.stage.name,
      'escalatedAt': task.routing.escalatedAt,
      'reserveWindowMs': task.routing.reserveWindowMs,
      'widenAfterMs': task.routing.widenAfterMs,
      'openAfterMs': task.routing.openAfterMs,
    });
  }
```

Add the new method (after `appendReclaim`):

```dart
  @override
  Future<void> appendEscalate(String taskId, RoutingStage stage, int at) {
    return _append(
        {'t': 'escalate', 'id': taskId, 'stage': stage.name, 'at': at});
  }
```

In `load()`, replace the `case 'add':` block to read the new fields:

```dart
        case 'add':
          byId[id] = TeamTask(
            id: id,
            seq: (e['seq'] as num?)?.toInt() ?? 0,
            title: e['title'] as String? ?? '',
            brief: e['brief'] as String? ?? '',
            createdBy: e['by'] as String? ?? '',
            createdAt: (e['createdAt'] as num?)?.toInt() ?? 0,
            dependsOn: [
              for (final d in (e['deps'] as List?) ?? const [])
                if (d is String) d,
            ],
            requiredCapabilities: {
              for (final c in (e['reqCaps'] as List?) ?? const [])
                if (c is String) c,
            },
            preferredCapabilities: {
              for (final c in (e['prefCaps'] as List?) ?? const [])
                if (c is String) c,
            },
            preferredAssignee: e['assignee'] as String?,
            routing: RoutingPolicy(
              stage: RoutingPolicy.parseStage(e['stage'] as String?),
              escalatedAt: (e['escalatedAt'] as num?)?.toInt() ?? 0,
              reserveWindowMs:
                  (e['reserveWindowMs'] as num?)?.toInt() ?? 45 * 1000,
              widenAfterMs: (e['widenAfterMs'] as num?)?.toInt() ?? 120 * 1000,
              openAfterMs: (e['openAfterMs'] as num?)?.toInt() ?? 300 * 1000,
            ),
          );
```

Add a new case in the `switch (e['t'])` (after `case 'reclaim':`):

```dart
        case 'escalate':
          final t = byId[id];
          if (t != null) {
            byId[id] = t.copyWith(
              routing: t.routing.copyWith(
                stage: RoutingPolicy.parseStage(e['stage'] as String?),
                escalatedAt: (e['at'] as num?)?.toInt(),
              ),
            );
          }
```

- [ ] **Step 5: Persist in InMemoryTaskLog**

In `client/lib/services/team_bus/tasks/in_memory_task_log.dart`, add (after `appendReclaim`):

```dart
  @override
  Future<void> appendEscalate(String taskId, RoutingStage stage, int at) async {
    final t = _tasks[taskId];
    if (t == null) return;
    _tasks[taskId] = t.copyWith(
      routing: t.routing.copyWith(stage: stage, escalatedAt: at),
    );
  }
```

(`appendAdd` already stores the full `TeamTask`, so caps/routing round-trip with no change.)

- [ ] **Step 6: Run test to verify it passes**

Run: `cd client && flutter test test/services/team_bus/tasks/file_task_log_routing_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/team_bus/tasks/task_log.dart client/lib/services/team_bus/tasks/file_task_log.dart client/lib/services/team_bus/tasks/in_memory_task_log.dart client/test/services/team_bus/tasks/file_task_log_routing_test.dart
git commit -m "feat(team-bus): persist capability and routing fields in the task log"
```

---

## Task 5: Capability-aware TaskQueue (claimNext, claimSpecific, reconcile)

**Files:**
- Modify: `client/lib/services/team_bus/tasks/task_queue.dart`
- Modify: `client/test/services/team_bus/task_queue_test.dart`
- Test: `client/test/services/team_bus/task_queue_routing_test.dart` (create)

- [ ] **Step 1: Update existing queue tests to the new `claimNext` signature**

In `client/test/services/team_bus/task_queue_test.dart`, every `claimNext('wX')` call becomes `claimNext('wX', const {})` (empty caps ⇒ eligible to all, preserving FIFO behavior). There are calls on lines for `w1`/`w2`/`w3` in the FIFO, double-claim, dependency, and reclaim tests. Replace each:

```dart
    final first = q.claimNext('w1', const {});
    final second = q.claimNext('w2', const {});
    expect(q.claimNext('w3', const {}), isNull);
```
and similarly in every other test (`claimNext('w1', const {})`, `claimNext('w2', const {})`, etc.). Also update the `rehydrate` test's `q1.claimNext('w1', const {})`.

- [ ] **Step 2: Write the new failing routing test**

Create `client/test/services/team_bus/task_queue_routing_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/tasks/task_queue.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';

void main() {
  late int idSeq;
  late int now;

  TaskQueue makeQueue() {
    idSeq = 0;
    now = 1000;
    return TaskQueue(ids: () => 't${idSeq++}', clock: () => now);
  }

  test('claimNext skips tasks the member is not eligible for', () {
    final q = makeQueue();
    q.addTasks('lead', [
      const TeamTaskDraft(title: 'fe', brief: 'b', requiredCapabilities: {'frontend'}),
      const TeamTaskDraft(title: 'be', brief: 'b', requiredCapabilities: {'backend'}),
    ]);

    final claimed = q.claimNext('w1', {'backend'});
    expect(claimed!.title, 'be'); // skips the frontend task at seq 0
    expect(q.claimNext('w1', {'backend'}), isNull); // nothing else eligible
  });

  test('claimNext orders eligible tasks by score then seq', () {
    final q = makeQueue();
    q.addTasks('lead', [
      const TeamTaskDraft(title: 'low', brief: 'b', preferredCapabilities: {'rust'}),
      const TeamTaskDraft(title: 'high', brief: 'b',
          preferredCapabilities: {'rust', 'async'}),
    ]);
    // worker has both preferred caps for 'high' (score 2) vs 'low' (score 1)
    final claimed = q.claimNext('w1', {'rust', 'async'});
    expect(claimed!.title, 'high');
  });

  test('reserved task is claimable only by the preferred assignee', () {
    final q = makeQueue();
    q.addTasks('lead', [
      const TeamTaskDraft(title: 'a', brief: 'b', preferredAssignee: 'dev2'),
    ]);
    expect(q.claimNext('other', const {}), isNull); // reserved for dev2
    expect(q.claimNext('dev2', const {})!.title, 'a');
  });

  test('claimSpecific enforces eligibility and atomicity', () {
    final q = makeQueue();
    final id = q
        .addTasks('lead', [
          const TeamTaskDraft(title: 'be', brief: 'b',
              requiredCapabilities: {'backend'})
        ])
        .single
        .id;

    expect(q.claimSpecific(id, 'w1', {'frontend'}), isNull); // ineligible
    final ok = q.claimSpecific(id, 'w2', {'backend'});
    expect(ok!.assignee, 'w2');
    expect(q.claimSpecific(id, 'w3', {'backend'}), isNull); // already claimed
  });

  test('reconcile escalates reserved → matched after the reserve window', () {
    final q = makeQueue();
    q.addTasks('lead', [
      const TeamTaskDraft(title: 'a', brief: 'b', preferredAssignee: 'dev2'),
    ]);
    expect(q.list().single.routing.stage, RoutingStage.reserved);

    now += 45 * 1000;
    final changed = q.reconcile(now, (_) => true);
    expect(changed.single.routing.stage, RoutingStage.matched);
    // now any worker can claim
    expect(q.claimNext('anyone', const {})!.title, 'a');
  });

  test('reconcile widens then opens when no eligible live member exists', () {
    final q = makeQueue();
    q.addTasks('lead', [
      const TeamTaskDraft(title: 'a', brief: 'b', requiredCapabilities: {'backend'}),
    ]);

    now += 120 * 1000;
    expect(q.reconcile(now, (_) => false).single.routing.stage,
        RoutingStage.widened);

    now += 300 * 1000;
    expect(q.reconcile(now, (_) => false).single.routing.stage,
        RoutingStage.open);
    expect(q.claimNext('anyone', const {})!.title, 'a'); // fungible fallback
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd client && flutter test test/services/team_bus/task_queue_routing_test.dart`
Expected: FAIL — `claimNext` arity, `claimSpecific`, `reconcile` undefined.

- [ ] **Step 4: Rewrite the queue claim/reconcile logic**

In `client/lib/services/team_bus/tasks/task_queue.dart`:

Add the import at the top (after the existing `import 'team_task.dart';`):

```dart
import 'task_router.dart';
```

In `addTasks`, set the initial routing stage from the draft. Replace the `final task = TeamTask(...)` construction inside the loop with:

```dart
      final stage = d.preferredAssignee != null
          ? RoutingStage.reserved
          : RoutingStage.matched;
      final task = TeamTask(
        id: _ids(),
        seq: _nextSeq++,
        title: d.title.trim(),
        brief: d.brief,
        createdBy: createdBy,
        createdAt: _clock(),
        dependsOn: List.unmodifiable(d.dependsOn),
        requiredCapabilities: d.requiredCapabilities,
        preferredCapabilities: d.preferredCapabilities,
        preferredAssignee: d.preferredAssignee,
        routing: RoutingPolicy(stage: stage, escalatedAt: _clock()),
      );
```

Replace the whole `claimNext` method with capability-aware selection plus a shared `_markClaimed`, and add `claimSpecific`:

```dart
  /// 原子认领下一个**对该成员合格**的可执行任务(deps 全 done)。合格集内按
  /// (score 降序, seq 升序)排序。无可认领返回 null。
  /// **此方法体内不得有 await**——保证选择 + 标记在同一微任务内完成。
  TeamTask? claimNext(String memberId, Set<String> memberCaps) {
    final candidates = _tasks.values
        .where((t) => t.isClaimable && _depsSatisfied(t))
        .toList()
      ..sort((a, b) {
        final sa = TaskRouter.score(memberCaps, a);
        final sb = TaskRouter.score(memberCaps, b);
        if (sa != sb) return sb.compareTo(sa);
        return a.seq.compareTo(b.seq);
      });
    for (final t in candidates) {
      if (!TaskRouter.eligible(memberId, memberCaps, t)) continue;
      return _markClaimed(t, memberId);
    }
    return null;
  }

  /// pull 式自取:认领一个指定任务(worker 主动从看板挑)。不存在/已被领/被依赖卡住/
  /// 不合格则返回 null。同样同步原子。
  TeamTask? claimSpecific(String taskId, String memberId, Set<String> memberCaps) {
    final t = _tasks[taskId];
    if (t == null || !t.isClaimable || !_depsSatisfied(t)) return null;
    if (!TaskRouter.eligible(memberId, memberCaps, t)) return null;
    return _markClaimed(t, memberId);
  }

  TeamTask _markClaimed(TeamTask t, String memberId) {
    final claimed = t.copyWith(
      status: TaskStatus.claimed,
      assignee: memberId,
      claimedAt: _clock(),
    );
    _tasks[t.id] = claimed;
    _persist(() => _log?.appendClaim(t.id, memberId, claimed.claimedAt!));
    return claimed;
  }
```

Add the `reconcile` method (place it after `reclaimExpired`):

```dart
  /// 推进每个 pending 任务的路由阶段(单调)。[hasEligibleLiveMember] 由调用方注入,
  /// 表示「当前是否存在能领该任务的在线成员」——为 false 且超时才降级要求。返回阶段
  /// 发生变化的任务,并唤醒等待者(让更宽的合格 worker 来认领)。
  List<TeamTask> reconcile(
    int now,
    bool Function(TeamTask) hasEligibleLiveMember,
  ) {
    final changed = <TeamTask>[];
    for (final t in _tasks.values.toList()) {
      if (t.status != TaskStatus.pending) continue;
      final next = TaskRouter.nextStage(t, now, hasEligibleLiveMember(t));
      if (next == t.routing.stage) continue;
      final updated =
          t.copyWith(routing: t.routing.copyWith(stage: next, escalatedAt: now));
      _tasks[t.id] = updated;
      _persist(() => _log?.appendEscalate(t.id, next, now));
      changed.add(updated);
    }
    if (changed.isNotEmpty) _wake();
    return changed;
  }
```

Note: `claimableCount` / `hasClaimable` stay as-is (they ignore capabilities — used only as a coarse "is there any pending work" signal; per-member eligibility is enforced in `claimNext`).

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && flutter test test/services/team_bus/task_queue_test.dart test/services/team_bus/task_queue_routing_test.dart`
Expected: PASS (existing FIFO tests still green with `const {}` caps; new routing tests green).

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/team_bus/tasks/task_queue.dart client/test/services/team_bus/task_queue_test.dart client/test/services/team_bus/task_queue_routing_test.dart
git commit -m "feat(team-bus): capability-aware claimNext, self-pick claimSpecific, reconcile"
```

---

## Task 6: TeamBus integration (caps, engagement, reconcile driver)

**Files:**
- Modify: `client/lib/services/team_bus/team_bus.dart`
- Modify: `client/test/services/team_bus/team_bus_tasks_test.dart`
- Test: `client/test/services/team_bus/team_bus_routing_test.dart` (create)

- [ ] **Step 1: Update existing bus task tests to the new internal signatures**

In `client/test/services/team_bus/team_bus_tasks_test.dart`, `bus.claimNextTask('w1')` calls stay the same (the public `claimNextTask` keeps a single-arg signature — it resolves caps internally). No change needed for those calls; they remain valid because declared `AgentNode.test` workers have empty caps ⇒ eligible to all. Confirm by re-running after Step 4.

- [ ] **Step 2: Write the new failing routing test**

Create `client/test/services/team_bus/team_bus_routing_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/tasks/task_queue.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import 'support/fake_member_launcher.dart';

TeamBus _busWithQueue(FakeMemberLauncher launcher) =>
    TeamBus(launcher: launcher, taskQueue: TaskQueue());

AgentNode _declared(String id, Set<String> caps) =>
    AgentNode.test(memberId: id, capabilities: caps);

AgentNode _atPrompt(String id, Set<String> caps) => AgentNode.test(
      memberId: id,
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.turnDoneReady,
      capabilities: caps,
    );

void main() {
  test('engagement cold-starts the capability-matched declared worker', () {
    fakeAsync((async) {
      final launcher = FakeMemberLauncher();
      final bus = _busWithQueue(launcher);
      bus.declareMember(_declared('fe', {'frontend'}));
      bus.declareMember(_declared('be', {'backend'}));

      bus.addTasks('lead', [
        const TeamTaskDraft(title: 'api', brief: 'b',
            requiredCapabilities: {'backend'}),
      ]);
      async.flushMicrotasks();

      expect(launcher.materialized.single.memberId, 'be'); // not 'fe'
    });
  });

  test('engagement doorbells the capability-matched at-prompt worker', () {
    fakeAsync((async) {
      final launcher = FakeMemberLauncher();
      final bus = _busWithQueue(launcher);
      bus.declareMember(_atPrompt('fe', {'frontend'}));
      bus.declareMember(_atPrompt('be', {'backend'}));

      bus.addTasks('lead', [
        const TeamTaskDraft(title: 'api', brief: 'b',
            requiredCapabilities: {'backend'}),
      ]);
      async.flushMicrotasks();

      expect(launcher.woken.single.memberId, 'be');
      expect(launcher.materialized, isEmpty);
    });
  });

  test('reconcileTasks opens a task when no capable member exists', () {
    fakeAsync((async) {
      final bus = _busWithQueue(FakeMemberLauncher());
      // Only a frontend worker exists; the backend task can never match it.
      bus.declareMember(_declared('fe', {'frontend'}));
      bus.addTasks('lead', [
        const TeamTaskDraft(title: 'api', brief: 'b',
            requiredCapabilities: {'backend'}),
      ]);
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 130)); // past widen window
      bus.reconcileTasks();
      async.elapse(const Duration(seconds: 310)); // past open window
      bus.reconcileTasks();

      expect(bus.listTasks(status: TaskStatus.pending).single.routing.stage,
          RoutingStage.open);
      // now the frontend worker can claim it as a fungible fallback
      final claimed = bus.claimNextTask('fe');
      expect(claimed!.title, 'api');
    });
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd client && flutter test test/services/team_bus/team_bus_routing_test.dart`
Expected: FAIL — engagement not capability-aware; `reconcileTasks` undefined.

- [ ] **Step 4: Wire capabilities, engagement, and reconcile into TeamBus**

In `client/lib/services/team_bus/team_bus.dart`:

Add the import (after `import 'tasks/task_queue.dart';`):

```dart
import 'tasks/task_router.dart';
```

In `receiveWork`, replace the queue-claim line. Find:

```dart
        if (queue != null) {
          final task = queue.claimNext(memberId);
          if (task != null) return TaskWork(task);
        }
```
Replace with:

```dart
        if (queue != null) {
          final task = queue.claimNext(memberId, node.profile.capabilities);
          if (task != null) return TaskWork(task);
        }
```

Replace `claimNextTask` to resolve caps from the member and add a pull entry point:

```dart
  /// 原子认领下一个对该成员合格的任务([receiveWork] 内部复用;无可认领返回 null)。
  TeamTask? claimNextTask(String memberId) =>
      _taskQueue?.claimNext(memberId, _capsOf(memberId));

  /// pull 式自取:worker 主动认领指定任务(MCP `claim_task` 落点)。
  TeamTask? claimSpecificTask(String taskId, String memberId) =>
      _taskQueue?.claimSpecific(taskId, memberId, _capsOf(memberId));

  Set<String> _capsOf(String memberId) =>
      _members[memberId]?.profile.capabilities ?? const {};
```

Rewrite `_engageWorkersForQueue` to be per-task capability-aware. Replace the entire existing method body with:

```dart
  /// 入队后按需「叫醒」合格的非 leader worker 去认领,覆盖其全部生命周期状态。
  /// 逐个 pending 任务处理:已有 parked 合格 worker 的任务交给 queue._wake;否则优先
  /// doorbell 一个合格的 running/atPrompt worker(便宜),再冷启动一个合格的 declared
  /// worker。无合格成员可上线的任务留给 [reconcileTasks] 最终降级。
  Future<void> _engageWorkersForQueue(String createdBy) async {
    final queue = _taskQueue;
    if (queue == null) return;
    final workers =
        _members.values.where((n) => !n.profile.isTeamLead).toList();
    for (final task in queue.list(status: TaskStatus.pending)) {
      if (_hasParkedEligibleWorker(workers, task)) continue;

      // 第一轮:敲已在跑、停在 prompt 的合格 worker(无冷启动)。
      AgentNode? running;
      for (final n in workers) {
        if (n.lifecycle != MemberLifecycle.running) continue;
        if (n.activity != MemberActivity.turnDoneReady) continue;
        if (n.doorbelled) continue;
        if (!TaskRouter.eligible(n.memberId, n.profile.capabilities, task)) {
          continue;
        }
        running = n;
        break;
      }
      if (running != null) {
        running.doorbelled = true;
        _launcher.wake(running.memberId, taskDoorbellNotice);
        continue;
      }

      // 第二轮:冷启动尚未上线、合格的 declared worker。
      AgentNode? declared;
      for (final n in workers) {
        if (n.lifecycle != MemberLifecycle.declared) continue;
        if (!TaskRouter.eligible(n.memberId, n.profile.capabilities, task)) {
          continue;
        }
        declared = n;
        break;
      }
      if (declared != null) {
        await _bringOnline(
          declared,
          TeamMessage(
            id: _env.ids(),
            from: createdBy,
            to: declared.memberId,
            content: taskDoorbellNotice,
          ),
        );
      }
    }
  }

  bool _hasParkedEligibleWorker(List<AgentNode> workers, TeamTask task) {
    for (final n in workers) {
      if (!n.waitingForMessage) continue;
      if (TaskRouter.eligible(n.memberId, n.profile.capabilities, task)) {
        return true;
      }
    }
    return false;
  }

  /// 推进任务路由阶段(定时 + 事件驱动)。降级后重新尝试 engage。
  List<TeamTask> reconcileTasks() {
    final queue = _taskQueue;
    if (queue == null) return const [];
    final changed = queue.reconcile(_env.clock(), _hasEligibleLiveMember);
    if (changed.isNotEmpty) {
      unawaited(_engageWorkersForQueue(_teamLeadMemberId() ?? ''));
    }
    return changed;
  }

  /// 是否存在能领该任务的**在线**(running/materializing)非 leader 成员。declared
  /// 不算「在线」——它要靠 engage 拉起;拉不起来才该降级。
  bool _hasEligibleLiveMember(TeamTask task) {
    for (final n in _members.values) {
      if (n.profile.isTeamLead) continue;
      if (!n.ptyRunning) continue;
      if (TaskRouter.eligible(n.memberId, n.profile.capabilities, task)) {
        return true;
      }
    }
    return false;
  }
```

Add a reconcile timer driven by the bus clock. In the constructor body (inside the `{ ... }` after `_coordination` assignment), add:

```dart
    if (_taskQueue != null) {
      _reconcileTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => reconcileTasks(),
      );
    }
```

Add the field (near the other final fields, but non-final since nullable + assigned conditionally):

```dart
  Timer? _reconcileTimer;
```

In `dispose`, cancel it. Find the `dispose()` method and add at the top of its body:

```dart
    _reconcileTimer?.cancel();
```

(`Timer` comes from `dart:async`, already imported at the top of the file.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && flutter test test/services/team_bus/team_bus_routing_test.dart test/services/team_bus/team_bus_tasks_test.dart`
Expected: PASS — new routing tests green; existing task tests still green (empty-caps workers remain eligible to all, so engagement/materialization assertions are unchanged).

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/team_bus/team_bus.dart client/test/services/team_bus/team_bus_routing_test.dart
git commit -m "feat(team-bus): capability-aware engagement and routing reconcile driver"
```

---

## Task 7: MCP surface (add_tasks fields, list_tasks annotation, claim_task)

**Files:**
- Modify: `client/lib/services/team_bus/mcp/teammate_bus_mcp_handler.dart`
- Modify: `client/test/services/team_bus/mcp/teammate_bus_mcp_handler_test.dart`

- [ ] **Step 1: Read the existing handler test to match style**

Run: `cd client && flutter test test/services/team_bus/mcp/teammate_bus_mcp_handler_test.dart`
Expected: PASS (baseline green before changes). Open the file to see how it constructs the handler and calls `_callTool` / `handle`, then mirror that in Step 2.

- [ ] **Step 2: Write the failing tests**

Append to `client/test/services/team_bus/mcp/teammate_bus_mcp_handler_test.dart` (inside `main()`, reusing whatever bus/handler setup helper the file already defines — replace `makeHandler()` / `callTool(...)` below with the file's existing helpers if named differently):

```dart
  test('add_tasks parses capabilities and preferred assignee', () async {
    final harness = makeHandler(); // existing helper: returns handler + bus
    final res = await harness.callTool('lead', 'add_tasks', {
      'tasks': [
        {
          'title': 'api',
          'brief': 'build it',
          'required_capabilities': ['backend'],
          'preferred_capabilities': ['rust'],
          'preferred_assignee': 'dev2',
        }
      ],
    });
    expect(res.isError, isFalse);
    final task = harness.bus.listTasks().single;
    expect(task.requiredCapabilities, {'backend'});
    expect(task.preferredCapabilities, {'rust'});
    expect(task.preferredAssignee, 'dev2');
  });

  test('claim_task lets an eligible worker self-pick; rejects ineligible', () async {
    final harness = makeHandler();
    harness.bus.declareMember(AgentNode.test(
      memberId: 'be', lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active, capabilities: {'backend'},
    ));
    harness.bus.declareMember(AgentNode.test(
      memberId: 'fe', lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active, capabilities: {'frontend'},
    ));
    final id = harness.bus
        .addTasks('lead', [
          const TeamTaskDraft(title: 'api', brief: 'b',
              requiredCapabilities: {'backend'})
        ])
        .single
        .id;

    final bad = await harness.callTool('fe', 'claim_task', {'task_id': id});
    expect(bad.text, contains('not eligible'));

    final ok = await harness.callTool('be', 'claim_task', {'task_id': id});
    expect(ok.isError, isFalse);
    expect(harness.bus.listTasks(status: TaskStatus.claimed).single.assignee, 'be');
  });
```

Add any missing imports at the top of the test file: `agent_node.dart`, `tasks/team_task.dart`, `tasks/task_queue.dart`. If the file's existing helper does not expose `bus`, extend the helper to return it (small, local test-only change).

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd client && flutter test test/services/team_bus/mcp/teammate_bus_mcp_handler_test.dart`
Expected: FAIL — `add_tasks` ignores the new fields; `claim_task` is an unknown tool.

- [ ] **Step 4: Extend `add_tasks` schema and parsing**

In `client/lib/services/team_bus/mcp/teammate_bus_mcp_handler.dart`, in `_taskToolDefs` → `add_tasks` → `inputSchema` → `properties` → `tasks` → `items` → `properties`, add the new properties alongside `title`/`brief`/`depends_on`:

```dart
                'required_capabilities': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
                'preferred_capabilities': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
                'preferred_assignee': {'type': 'string'},
```

Update the `add_tasks` description string to mention routing, e.g. append:

```
' Optionally route by capability: required_capabilities (hard filter — only '
'members with all of them claim it), preferred_capabilities (ranking), and '
'preferred_assignee (member id given first dibs).'
```

In `_callTool`'s `case 'add_tasks':`, extend the `TeamTaskDraft` construction to read the new fields:

```dart
              TeamTaskDraft(
                title: item['title'] as String? ?? '',
                brief: item['brief'] as String? ?? '',
                dependsOn: [
                  for (final d in (item['depends_on'] as List?) ?? const [])
                    if (d is String) d,
                ],
                requiredCapabilities: {
                  for (final c
                      in (item['required_capabilities'] as List?) ?? const [])
                    if (c is String && c.trim().isNotEmpty) c.trim(),
                },
                preferredCapabilities: {
                  for (final c
                      in (item['preferred_capabilities'] as List?) ?? const [])
                    if (c is String && c.trim().isNotEmpty) c.trim(),
                },
                preferredAssignee:
                    (item['preferred_assignee'] as String?)?.trim().isEmpty ?? true
                        ? null
                        : (item['preferred_assignee'] as String).trim(),
              ),
```

- [ ] **Step 5: Add the `claim_task` tool definition**

In `_taskToolDefs`, add a new entry after `list_tasks`:

```dart
    {
      'name': 'claim_task',
      'description':
          'Worker: self-pick a specific task you are eligible for from the '
          'board (use list_tasks to see eligible_for_you/match_score). Claims '
          'it atomically; fails if it is gone, already claimed, blocked, or you '
          'are not eligible.',
      'inputSchema': {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'task_id': {'type': 'string'},
        },
        'required': ['task_id'],
      },
    },
```

In `_callTool`, add a case after `case 'list_tasks':`:

```dart
      case 'claim_task':
        if (!_bus.hasTaskQueue) {
          return JsonRpcResponse.error(req.id, -32602, 'No task queue');
        }
        final taskId = (args['task_id'] as String?)?.trim() ?? '';
        final claimed = _bus.claimSpecificTask(taskId, memberId);
        if (claimed == null) {
          return _toolError(
            req.id,
            'Could not claim "$taskId" (gone, already claimed, blocked, or you '
            'are not eligible).',
          );
        }
        return _ok(req.id, _encodeTaskAssignment(claimed));
```

If `_toolError` is not in scope here, reuse the same error helper already used by `send_message` in this file (it calls `_toolError(req.id, ...)`), so it is available.

- [ ] **Step 6: Annotate `list_tasks` output with eligibility**

Change `list_tasks` to pass the calling member through to the encoder. In `_callTool`'s `case 'list_tasks':`, replace the final return with:

```dart
        return _ok(req.id, _encodeTasks(_bus.listTasks(status: status), memberId));
```

Update `_encodeTasks` and `_formatTask` to accept the member and annotate. Replace the `_encodeTasks` signature and body:

```dart
  String _encodeTasks(List<TeamTask> tasks, String memberId) {
    if (tasks.isEmpty) return 'No tasks on the queue.';
    final caps = _bus.capabilitiesOf(memberId);
    final buffer = StringBuffer('Work queue (${tasks.length}):\n\n');
    buffer.write(
        tasks.map((t) => _formatTask(t, memberCaps: caps, memberId: memberId)).join('\n\n'));
    return buffer.toString().trimRight();
  }
```

Update `_formatTask` to take optional annotation args and append `eligible_for_you` / `match_score` when provided. Add these parameters to its signature (`{bool full = false, Set<String>? memberCaps, String? memberId}`) and, when `memberCaps != null && memberId != null`, add to its `lines`:

```dart
      'eligible_for_you: ${TaskRouter.eligible(memberId, memberCaps, t)}',
      'match_score: ${TaskRouter.score(memberCaps, t)}',
```

Add the import to the handler file (top, with the other `tasks/` imports):

```dart
import '../tasks/task_router.dart';
```

Add a small accessor on `TeamBus` so the handler can read caps without reaching into members. In `team_bus.dart` add:

```dart
  /// 成员能力(MCP `list_tasks` 标注 eligible_for_you / match_score 用)。
  Set<String> capabilitiesOf(String memberId) => _capsOf(memberId);
```

The internal `_encodeTaskAssignment` is reused unchanged for `claim_task` (it already says "ASSIGNED TASK ...").

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd client && flutter test test/services/team_bus/mcp/teammate_bus_mcp_handler_test.dart`
Expected: PASS (existing handler tests + 2 new tests).

- [ ] **Step 8: Commit**

```bash
git add client/lib/services/team_bus/mcp/teammate_bus_mcp_handler.dart client/lib/services/team_bus/team_bus.dart client/test/services/team_bus/mcp/teammate_bus_mcp_handler_test.dart
git commit -m "feat(team-bus): MCP add_tasks routing fields, list_tasks annotation, claim_task tool"
```

---

## Task 8: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No errors. Fix any analyzer errors surfaced by the new code (unused imports, missing `Set` equality, etc.) before proceeding.

- [ ] **Step 2: Run the full team_bus test suite**

Run: `cd client && flutter test test/services/team_bus`
Expected: PASS — all existing and new tests.

- [ ] **Step 3: Run the full non-integration suite**

Run: `cd client && flutter test --exclude-tags integration`
Expected: PASS. Investigate and fix any failures caused by the `TeamMemberConfig`/`TeamTask` changes (e.g. other JSON round-trip tests).

- [ ] **Step 4: Commit any fixups**

```bash
git add -A
git commit -m "test(team-bus): fixups from full-suite verification for capability routing"
```

---

## Self-Review notes (already applied)

- **Spec coverage:** capability model (Task 1–2), `TaskRouter` (Task 3), persistence (Task 4), claimNext/claimSpecific/reconcile (Task 5), capability-aware engagement + tiered degradation + reconcile driver (Task 6), MCP add_tasks/list_tasks/claim_task (Task 7). Each spec section maps to a task.
- **Signature consistency:** `claimNext(memberId, Set<String>)`, `claimSpecific(taskId, memberId, Set<String>)`, `reconcile(now, bool Function(TeamTask))`, `TeamBus.claimNextTask(memberId)` (single-arg public, resolves caps), `TeamBus.claimSpecificTask(taskId, memberId)`, `TaskRouter.eligible(memberId, memberCaps, task)` / `score(memberCaps, task)` / `nextStage(task, now, hasEligibleLiveMember)` used identically across tasks.
- **No placeholders:** every code step shows the code; every test step shows the test; every run step shows the command and expected result.
- **Liveness:** "live" excludes `declared` members so an un-startable eligible member cannot block widening forever; the `open` terminal stage guarantees any worker can claim.
