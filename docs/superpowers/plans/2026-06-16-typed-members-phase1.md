# Typed Members Phase 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a member's own id an implicit routing capability and route the Superpowers Quartet by member/type name, so the read-only reviewer can no longer auto-claim implementation tasks off the shared queue.

**Architecture:** A member id becomes one of its capabilities in `TeammateRosterProfile` (`capabilities = {memberId} ∪ explicit tags`), replacing the unused agentType/agent derivation. The committed `TaskRouter` engine is unchanged — routing by `required_capabilities: ["builder"]` now matches the member whose id is `builder`. The Quartet template drops its explicit capability tags and the team-lead playbook routes by member name, gating review behind implementation with `depends_on`.

**Tech Stack:** Dart / Flutter, `flutter_test`. Files under `client/lib/services/team_bus/`, `client/lib/services/team_hub/`, and their tests.

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `client/lib/services/team_bus/teammate_roster_profile.dart` | `capabilities` always includes member id | Modify |
| `client/test/services/team_bus/teammate_roster_profile_capabilities_test.dart` | id-as-capability assertions | Modify |
| `client/test/services/team_bus/team_bus_routing_test.dart` | end-to-end: cross-type claim rejected | Modify |
| `client/lib/services/team_hub/builtin_team_templates.dart` | Quartet routes by type name; drop explicit tags | Modify |
| `client/test/services/team_hub/builtin_team_templates_test.dart` | assert name-routing, no explicit caps | Modify |

---

## Task 1: Member id is an implicit capability

**Files:**
- Modify: `client/lib/services/team_bus/teammate_roster_profile.dart`
- Modify: `client/test/services/team_bus/teammate_roster_profile_capabilities_test.dart`
- Modify: `client/test/services/team_bus/team_bus_routing_test.dart`

- [ ] **Step 1: Replace the roster-profile capability test**

Replace the entire body of `client/test/services/team_bus/teammate_roster_profile_capabilities_test.dart` with:

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

  TeammateRosterProfile profile(TeamMemberConfig m) =>
      TeammateRosterProfile.fromMember(
        member: m,
        team: team(),
        cliTeamName: 'team-1-1',
        cwd: '/tmp',
      );

  test('member id is always an implicit capability', () {
    expect(
      profile(const TeamMemberConfig(id: 'builder', name: 'Builder')).capabilities,
      {'builder'},
    );
  });

  test('explicit capabilities are unioned with the member id', () {
    final caps = profile(const TeamMemberConfig(
      id: 'dev',
      name: 'Dev',
      capabilities: {'backend', 'rust'},
    )).capabilities;
    expect(caps, {'dev', 'backend', 'rust'});
  });

  test('minimal profile carries its member id as a capability', () {
    expect(TeammateRosterProfile.minimal('reviewer').capabilities, {'reviewer'});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/team_bus/teammate_roster_profile_capabilities_test.dart`
Expected: FAIL — current `fromMember` derives from agentType/agent (not member id), and `minimal` returns empty capabilities.

- [ ] **Step 3: Make member id an implicit capability in `fromMember`**

In `client/lib/services/team_bus/teammate_roster_profile.dart`, replace the `caps` computation inside `fromMember` (the `final caps = member.capabilities.isNotEmpty ? ... ;` block):

```dart
    final caps = <String>{rosterName, ...member.capabilities};
```

(`rosterName` is already defined above as `member.id`.)

- [ ] **Step 4: Make member id an implicit capability in `minimal`**

In the `minimal` factory, the returned object currently sets `capabilities: capabilities,`. Replace that line with:

```dart
      capabilities: {memberId, ...capabilities},
```

- [ ] **Step 5: Run the roster-profile test to verify it passes**

Run: `cd client && flutter test test/services/team_bus/teammate_roster_profile_capabilities_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Add an end-to-end cross-type claim test**

In `client/test/services/team_bus/team_bus_routing_test.dart`, add this test inside `main()` (after the existing `reconcileTasks` test, before the closing `}`):

```dart
  test('a member cannot claim a task routed to another type', () {
    final bus = _busWithQueue(FakeMemberLauncher());
    // ids become capabilities: builder→{builder}, reviewer→{reviewer}
    bus.declareMember(AgentNode.test(
      memberId: 'builder',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    ));
    bus.declareMember(AgentNode.test(
      memberId: 'reviewer',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    ));
    bus.addTasks('lead', [
      const TeamTaskDraft(title: 'impl', brief: 'b',
          requiredCapabilities: {'builder'}),
    ]);

    // reviewer is ineligible for builder-routed work
    expect(bus.claimNextTask('reviewer'), isNull);
    // builder claims it
    expect(bus.claimNextTask('builder')!.title, 'impl');
  });
```

- [ ] **Step 7: Run the routing test to verify it passes**

Run: `cd client && flutter test test/services/team_bus/team_bus_routing_test.dart`
Expected: PASS (existing 3 tests + the new one).

- [ ] **Step 8: Commit**

```bash
git add client/lib/services/team_bus/teammate_roster_profile.dart client/test/services/team_bus/teammate_roster_profile_capabilities_test.dart client/test/services/team_bus/team_bus_routing_test.dart
git commit -m "feat(team-bus): make member id an implicit routing capability"
```

---

## Task 2: Quartet routes by type name

**Files:**
- Modify: `client/lib/services/team_hub/builtin_team_templates.dart`
- Modify: `client/test/services/team_hub/builtin_team_templates_test.dart`

- [ ] **Step 1: Replace the two capability-related template tests**

In `client/test/services/team_hub/builtin_team_templates_test.dart`, replace the two tests added previously (`'quartet members carry routing capabilities'` and `'lead routes tasks by required_capabilities and gates review'`) with:

```dart
  test('quartet workers carry no explicit capabilities (routed by type name)',
      () {
    for (final m in kSuperpowersTrioTeamTemplate.members) {
      expect(m.capabilities, isEmpty);
    }
  });

  test('lead routes tasks to member types by name and gates review', () {
    final lead = kSuperpowersTrioTeamTemplate.members
        .firstWhere((m) => TeamMemberNaming.isTeamLeadName(m.name));
    final text = '${lead.prompt}\n${lead.playbook}';
    expect(text, contains('["architect"]'));
    expect(text, contains('["builder"]'));
    expect(text, contains('["reviewer"]'));
    expect(text, contains('depends_on'));
  });
```

- [ ] **Step 2: Run the template test to verify it fails**

Run: `cd client && flutter test test/services/team_hub/builtin_team_templates_test.dart`
Expected: FAIL — members still have explicit capabilities (`{'design'}` etc.) and the lead playbook routes by `["design"]`/`["implement"]`/`["review"]`, not member names.

- [ ] **Step 3: Remove the explicit capability tags from the three workers**

In `client/lib/services/team_hub/builtin_team_templates.dart`, delete these three lines:

```dart
      capabilities: {'design'},
```
(under `name: 'architect',`)

```dart
      capabilities: {'implement'},
```
(under `name: 'builder',`)

```dart
      capabilities: {'review'},
```
(under `name: 'reviewer',`)

- [ ] **Step 4: Route the lead playbook by member type name**

In the same file, replace the team-lead `playbook:` string with this version (routes by member type name, not free-form tags):

```dart
      playbook:
          'Idle loop: wait_for_message only. Enqueue work with add_tasks and '
          'ROUTE every task by required_capabilities to the member TYPE (its '
          'name) so only that role can claim it — never leave a task untagged '
          '(untagged work is claimable by anyone, including the reviewer): '
          'design+plan → required_capabilities ["architect"]; implementation → '
          '["builder"]; review → ["reviewer"] AND depends_on the implementation '
          'task ids, so review unlocks only after the build is done. Honor '
          'phase gates (design approved → plan ready → implementation done → '
          'review pass): do not enqueue implementation before the plan is '
          'ready, nor a review task before its implementation tasks exist. Use '
          'send_message only to relay clarifying questions and blockers between '
          'members and the user, and update_task to track gates (Skill / '
          'workflow / Write / Edit / Bash are disabled here). Never stand down; '
          'escalate blockers to the user.',
```

- [ ] **Step 5: Bump the template `updatedAt`**

In the same file, replace the `updatedAt:` line:

```dart
  updatedAt: 1_781_568_000_000, // 2026-06-16 — stable sort bump when edited
```
with:
```dart
  updatedAt: 1_781_654_400_000, // 2026-06-17 — stable sort bump when edited
```

- [ ] **Step 6: Run the template test to verify it passes**

Run: `cd client && flutter test test/services/team_hub/builtin_team_templates_test.dart`
Expected: PASS (all tests, including the unchanged clone/delegate-only tests).

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/team_hub/builtin_team_templates.dart client/test/services/team_hub/builtin_team_templates_test.dart
git commit -m "feat(team-hub): route the Superpowers Quartet by member type name"
```

---

## Task 3: Verification

**Files:** none (verification only)

- [ ] **Step 1: Run the affected suites**

Run: `cd client && flutter test test/services/team_bus test/services/team_hub test/models`
Expected: PASS — all team_bus, team_hub, and model tests green.

- [ ] **Step 2: Analyze the touched files**

Run: `cd client && flutter analyze lib/services/team_bus/teammate_roster_profile.dart lib/services/team_hub/builtin_team_templates.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit any fixups (only if Step 1 or 2 surfaced issues)**

```bash
git add -A
git commit -m "fix(team-bus): phase-1 verification fixups"
```

---

## Self-Review notes (already applied)

- **Spec coverage (Phase 1):** id-as-capability in `TeammateRosterProfile` (Task 1); Quartet routes by type name, lead playbook with `depends_on` gating, explicit tags dropped (Task 2). Phase 2 (replicas, instance expansion, UI) is intentionally out of scope for this plan.
- **Consistency:** `capabilities = {memberId} ∪ explicit` used identically in `fromMember` and `minimal`; routing tests rely on `AgentNode.test(memberId: …)` deriving caps from the id (no explicit `capabilities:` arg needed).
- **No placeholders:** every step shows the exact old/new code and the command + expected result.
- **Behavioral check:** the agentType/agent derivation is removed (it never fired for these templates); any future need for agentType-based caps is superseded by explicit tags + id.
