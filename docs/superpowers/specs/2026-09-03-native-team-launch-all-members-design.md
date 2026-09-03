# Native Team Launch All Members — Design Spec

**Date:** 2026-09-03
**Status:** Approved (pending implementation)

## Problem

Native teams (`TeamMode.native`, where the CLI coordinates its own roster)
break when any member shell is missing on connect — the team becomes
dysfunctional until every member is manually started. Today the app only
launches all members when the global "Start all members on connect"
preference (`autoLaunchAllMembersOnConnect`) is enabled, and that
preference defaults to `false`. Even when enabled, native-team full launch
partly relies on a chained trigger: the first member shell must attach
successfully before the remaining members are scheduled.

## Decision

- **Native teams always launch every valid member on Connect and Restart.**
  The `autoLaunchAllMembersOnConnect` preference no longer applies to them.
- **Mixed teams keep the existing behavior**: Connect/Restart launches all
  members only when the preference is enabled; otherwise only the selected
  member starts.
- The preference remains in Settings → Session, with its description
  narrowed to mixed teams only.

## Design

### 1. Core predicate

Add a pure function next to `shouldSerializeConnect` in
`client/lib/services/launch/session_launch_pipeline.dart`, marked
`@visibleForTesting`:

```dart
/// Whether connecting this team must launch every valid member shell.
///
/// Native teams break when any member is missing (the CLI coordinates the
/// roster itself), so they always launch all members regardless of the
/// user preference. Mixed teams honor [autoLaunchAllMembersOnConnect].
@visibleForTesting
bool shouldLaunchAllMembers({
  required TeamProfile team,
  required bool autoLaunchAllMembersOnConnect,
}) => team.teamMode != TeamMode.mixed || autoLaunchAllMembersOnConnect;
```

The pipeline keeps its existing `bool Function() autoLaunchAllMembersOnConnect`
constructor parameter; the gate sites below call the predicate with its
result.

### 2. Gate sites (all in the launch layer)

| Site | File / line (approx) | Current | New |
|------|----------------------|---------|-----|
| Connect entry | `session_launch_pipeline.dart` `_connectTeamSession` (~548) | `if (_autoLaunchAllMembersOnConnect())` → `_runLaunchAllMembers` | `shouldLaunchAllMembers(...)` — native always takes the all-members path |
| Restart entry | `session_launch_pipeline.dart` `_restartTeamSession` (~584) | same gate before full-shell disconnect + `_runLaunchAllMembers` | native always restarts all members |
| Post-materialize scheduling | `session_launch_pipeline.dart` `_runLaunchAllMembers` mixed-only branch (~396) | only `TeamMode.mixed` schedules `_scheduleMemberConnect` per member | native also schedules each member (no longer solely dependent on the first member's shell) |
| Chained fallback | `session_launch_service.dart` `_scheduleShellConnect` attach callback (~418) | preference-gated `_launchRemainingMembersForTab` | native calls it unconditionally — the fallback for the existing-tab / existing-session path |

`_runOpenMemberTab` (single member tab open path) is intentionally
unchanged: it is the explicit "open one member's tab" entry point and its
semantics are single-member.

`materializeTeamSession`'s `memberForInitialShell` stays `validMembers.first`
on the all-members path; the first shell is opened by materialization and
the remaining members are scheduled by the post-materialize branch — the
same shape mixed teams use today.

### 3. Preference semantics & copy

`autoLaunchAllMembersOnConnect` is preserved but now applies to mixed teams
only:

- `client/lib/l10n/app_en.arb` `autoLaunchAllMembersDescription` →
  "Mixed teams only: when enabled, Connect and Restart launch every valid
  member shell; native teams always launch all members."
- `client/lib/l10n/app_zh.arb` → “仅对混合团队生效：开启后连接或重启会为每个有效成员
  启动终端；native 团队始终全员启动。”

### 4. Error handling

No new mechanisms; existing behavior is reused:

- Per-member connect failure is already isolated in
  `SessionMemberConnectScheduler.schedule`: error text is written to that
  member's shell, `failSessionConnect` is called, and `markMemberReady`
  unblocks materialize waiters. One member failing does not block the
  others (each member schedules independently post-frame).
- `shouldSerializeConnect` semantics are unchanged (same-session
  double-connect guard).

### 5. Testing

- New unit tests for `shouldLaunchAllMembers`: native × pref on/off, mixed ×
  pref on/off (4 cases).
- Pipeline-level tests: native team Connect and Restart each invoke
  `_scheduleMemberConnect` once per valid member.
- Update existing tests that construct the pipeline with
  `autoLaunchAllMembersOnConnect: () => false` and assume native
  single-member behavior (e.g.
  `client/test/services/launch/session_launch_pipeline_stable_task_id_test.dart`).

## Out of scope

- Per-team member-launch configuration (rejected in brainstorming).
- Changing the default value of the global preference (native teams bypass
  it instead).
- TeamBus/native architecture changes.
