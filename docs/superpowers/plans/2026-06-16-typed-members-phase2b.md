# Typed Members Phase 2b — UI (replicas) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface replica pods in the running workbench (flat rows `Builder #0`, `Builder #1` with per-pod presence) and let users set `replicas` from the member-config form.

**Architecture:** Phase 2a already keyed shells / bus nodes / bindings / config-profile by instance id, and `runtimeRosterMembers(team)` returns one projected `TeamMemberConfig` per pod. Phase 2b feeds those projections to the existing flat members panel and the presence poller (swap `team.members` → `runtimeRosterMembers(team)`), and adds a small integer Replicas stepper to the member-config advanced section. Singletons (`replicas == 1`) project to the type id, so the UI is unchanged for existing teams.

**Tech Stack:** Dart / Flutter, `flutter_test`. Files under `client/lib/widgets/right_tools/`, `client/lib/cubits/`, `client/lib/pages/team_config/`, `client/lib/l10n/`.

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `client/lib/widgets/right_tools/right_tools_panel.dart` | members panel lists pods; selection/actions resolve instance ids | Modify |
| `client/lib/cubits/member_presence_cubit.dart` | presence computed per pod | Modify |
| `client/lib/pages/team_config/team_config_member_section.dart` | Replicas stepper on the type | Modify |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | `memberReplicas` / `memberReplicasSubtitle` | Modify |

**Note on UI testing:** the panel/presence wiring is glue over the already-tested pure helper `runtimeRosterMembers` (covered by `test/models/member_instance_test.dart`). Where a full widget test would require a heavy provider harness, this plan gates on `flutter analyze` + the existing cubit/widget suites (no regression) + a documented golden-path manual check, per the repo's AGENTS.md convention.

---

## Task 1: Members panel + presence show pods

**Files:**
- Modify: `client/lib/widgets/right_tools/right_tools_panel.dart`
- Modify: `client/lib/cubits/member_presence_cubit.dart`

- [ ] **Step 1: Feed the members panel instance projections**

In `client/lib/widgets/right_tools/right_tools_panel.dart`:

Add the import with the other model imports:
```dart
import '../../models/member_instance.dart';
```

Replace the `members` list source (around line 101-107):
```dart
    final members = team == null
        ? const <TeamMemberConfig>[]
        : ([...team.members]..sort((a, b) {
            if (TeamMemberNaming.isTeamLead(a)) return -1;
            if (TeamMemberNaming.isTeamLead(b)) return 1;
            return a.name.compareTo(b.name);
          }));
```
with (hoist the projected roster so the callbacks can resolve instance ids against it):
```dart
    final runtimeMembers =
        team == null ? const <TeamMemberConfig>[] : runtimeRosterMembers(team);
    final members = [...runtimeMembers]..sort((a, b) {
      if (TeamMemberNaming.isTeamLead(a)) return -1;
      if (TeamMemberNaming.isTeamLead(b)) return 1;
      return a.name.compareTo(b.name);
    });
```

- [ ] **Step 2: Resolve selection/action callbacks against the projected roster**

In the same file, within the same `build` method, every callback currently does
`team.members.firstWhere((m) => m.id == id)` (the `onSelected`, `onOpen`, `onViewDetail`,
`onOpenConfigDir`, and any other `…firstWhere((m) => m.id == id)` in this MembersPanel
block — there are several). Replace **each** occurrence of `team.members.firstWhere((m) => m.id == id)`
in this build method with:
```dart
runtimeMembers.firstWhere((m) => m.id == id)
```
The selected `id` is now an instance id (e.g. `builder-0`), and `runtimeMembers` contains the
matching projection. The resolved projection is passed to `cubit.openMemberTab(team, member, …)`
/ `showMemberDetailDialog(member: member, …)` exactly as before — connecting that specific pod
(its shell/config-profile are keyed by the instance id).

- [ ] **Step 3: Compute presence per pod**

In `client/lib/cubits/member_presence_cubit.dart`:

Add the import with the other model imports:
```dart
import '../models/member_instance.dart';
```
Change the presence compute call (around line 178-183) from `members: team.members,` to:
```dart
        members: runtimeRosterMembers(team),
```
(Leave everything else in that `compute(...)` call unchanged.)

- [ ] **Step 4: Analyze + regression suites**

Run:
```
cd client && flutter analyze lib/widgets/right_tools/right_tools_panel.dart lib/cubits/member_presence_cubit.dart
cd client && flutter test test/cubits test/widget_test.dart
```
Expected: analyze `No issues found!`; suites PASS. For a single-instance team,
`runtimeRosterMembers` yields the same ids as `team.members`, so existing behavior is
unchanged. If any test fails, judge NEW vs pre-existing (the repo has known-failing
cli-presets tests from a concurrent refactor) and report.

- [ ] **Step 5: Golden-path manual check (document, do not skip)**

Record this manual check in the commit body: with a mixed team whose `builder` has
`replicas: 2`, open a project session → the Members panel lists `Builder #0` and `Builder #1`
as separate rows, each selectable, each with its own presence dot; selecting one opens that
pod's terminal. A singleton team is visually unchanged.

- [ ] **Step 6: Commit**

```bash
git add client/lib/widgets/right_tools/right_tools_panel.dart client/lib/cubits/member_presence_cubit.dart
git commit -m "feat(ui): show replica pods as rows in the members panel with per-pod presence"
```

---

## Task 2: Replicas stepper in the member-config form

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/pages/team_config/team_config_member_section.dart`

- [ ] **Step 1: Add l10n strings**

In `client/lib/l10n/app_en.arb`, add after the `memberExtraArgsSubtitle` entry:
```json
  "memberReplicas": "Replicas",
  "memberReplicasSubtitle": "Run this role as N interchangeable instances (pods) that share its task queue. 1 = a single instance.",
```
In `client/lib/l10n/app_zh.arb`, add after its `memberExtraArgsSubtitle` entry:
```json
  "memberReplicas": "副本数",
  "memberReplicasSubtitle": "把该角色作为 N 个可互换实例(pod)运行,共享其任务队列。1 = 单实例。",
```

- [ ] **Step 2: Regenerate l10n + warmup glyphs**

Run:
```
cd client && flutter pub get
cd client && dart run tool/gen_warmup_glyphs.dart
```
Expected: `app_localizations*.dart` regenerated (now exposes `l10n.memberReplicas` /
`l10n.memberReplicasSubtitle`); `lib/widgets/warmup_glyphs.g.dart` rewritten.

- [ ] **Step 3: Add the stepper widget**

In `client/lib/pages/team_config/team_config_member_section.dart`, add this private widget at
the end of the file (after the existing `TeamMemberConfigFormState` class closes):
```dart
class _ReplicasStepper extends StatelessWidget {
  const _ReplicasStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '-',
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 28,
          child: Text('$value', textAlign: TextAlign.center),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '+',
          onPressed: () => onChanged(value + 1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Show the stepper in the advanced section (non-lead members only)**

In the same file, in the `SettingsAdvancedExpansion`'s `children:` list, add a Replicas row
immediately before the `memberExtraArgs` row (`SettingsLabeledStackedRow(title: l10n.memberExtraArgs, …)`):
```dart
              if (!TeamMemberNaming.isTeamLead(m))
                SettingsLabeledRow(
                  title: l10n.memberReplicas,
                  subtitle: l10n.memberReplicasSubtitle,
                  trailing: _ReplicasStepper(
                    value: m.replicas,
                    onChanged: (v) => _update(m.copyWith(replicas: v)),
                  ),
                  showDividerBelow: true,
                ),
```
(`m` is the current `widget.member`; `_update`, `SettingsLabeledRow`, and
`TeamMemberNaming` are already used/imported in this file. The team-lead is always a
singleton, so the stepper is hidden for it.)

- [ ] **Step 5: Analyze + suites**

Run:
```
cd client && flutter analyze lib/pages/team_config/team_config_member_section.dart
cd client && flutter test test/pages test/cubits
```
Expected: analyze `No issues found!`; suites PASS (report NEW vs pre-existing for any failure).

- [ ] **Step 6: Golden-path manual check (document in commit body)**

In a team's member config, the advanced section shows a **Replicas** stepper for non-lead
members (hidden for team-lead); +/- adjusts the count (min 1); the value persists
(`m.replicas` round-trips through `copyWith` → `TeamCubit.updateMember`).

- [ ] **Step 7: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/lib/pages/team_config/team_config_member_section.dart client/lib/widgets/warmup_glyphs.g.dart
git commit -m "feat(ui): add a Replicas stepper to the member-config form"
```

---

## Task 3: Verification

**Files:** none (verification only)

- [ ] **Step 1: Analyze all touched files**

Run:
```
cd client && flutter analyze lib/widgets/right_tools/right_tools_panel.dart lib/cubits/member_presence_cubit.dart lib/pages/team_config/team_config_member_section.dart
```
Expected: `No issues found!`

- [ ] **Step 2: Run the affected suites**

Run: `cd client && flutter test test/cubits test/pages test/widget_test.dart test/models`
Expected: PASS (report NEW vs pre-existing for any failure).

- [ ] **Step 3: Commit any fixups (only if Steps 1-2 surfaced issues)**

```bash
git add -A
git commit -m "fix(ui): phase-2b verification fixups"
```

---

## Self-Review notes (already applied)

- **Spec coverage (Phase 2b):** members panel shows pods + per-pod presence (Task 1, flat
  rows per the approved UX); Replicas stepper + l10n (Task 2). Per-instance provider
  isolation is confirmed already-correct (the projection carries the type's `provider`,
  resolved per-pod at launch) and is intentionally not re-touched here.
- **Consistency:** uses `runtimeRosterMembers(team)` (Phase 2a) everywhere a pod list is
  needed; selection callbacks resolve the instance id against the same `runtimeMembers`
  list they were built from.
- **Non-breaking:** `replicas == 1 → instanceId == typeId`, so the panel, presence, and
  selection are byte-identical for existing single-instance teams; the stepper is hidden for
  the team-lead.
- **Testing posture:** pure-UI glue over the already-tested `runtimeRosterMembers`; gated on
  analyze + existing suites + documented golden-path checks (AGENTS.md allows this where CI
  cannot cover UI wiring).
