# Personal ACP Idle Reclaim Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking. Tests ONLY via
> `cd client && dart run tool/run_tests.dart <paths>` (never raw `flutter test`).
>
> **Status (2026-10-22):** implemented. Unit + integration coverage:
> `test/cubits/chat/tab_member_reclaim_watch_test.dart`,
> `test/services/chat/launch/session_launch_acp_discard_test.dart`,
> `test/integration/personal_acp_reclaim_integration_test.dart`.

**Goal:** Let a terminal-less **personal ACP** session (`isAcpChatSession`) participate in the
existing idle reclaim ("回收空闲终端"), so a backgrounded personal ACP agent process is closed to
free memory and transparently re-attached when the session becomes active again.

**Spec / prior art:** `docs/superpowers/specs/2026-10-15-acp-idle-reclaim-and-resume-design.md`
(D1–D7). That spec deliberately excluded personal ACP (D1). This plan lifts D1 with a visibility
gate and a restore trigger; resume (`session/load`) already exists.

**Architecture:** `TabMemberReclaimWatch` already enumerates `ChatTab.memberAcpRuntimes`, and the
personal runtime is stored in that same map under the session id. Today the personal tab is
skipped outright (`// D1`). Replace the skip with a personal-aware snapshot whose `isDisplayed`
uses **tab centre-active** state instead of `selectedMemberId`. Discard goes through a new
`SessionLaunchService.discardPersonalAcpRuntime`; restore is **lazy on send** — the composer
(`SessionChatView.onSubmit`) re-connects before delivering, exactly like a simple PTY session
whose shell is not spawned by viewing the tab.

## Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| P1 | Reclaim scope = personal ACP tabs whose **session is not centre-active**. | A personal ACP seat *is* the visible surface while its tab is active, so "active" replaces the D1 exclusion. Reclaiming an active tab would be thrash. |
| P2 | Threshold = the existing ACP policy (`reclaimIdleTerminalAfterSeconds * 2`), same `reclaimIdleTerminals` switch. | No new setting (mirrors D2). |
| P3 | Visibility = `activeSessionId == tab.info.id` (bar-derived, `ChatCubit.activeTab`). | Single source of truth for "the operator is looking at this session"; covers other workspaces / non-session tabs. |
| P4 | Restore = **lazy on send only**: `SessionChatView.onSubmit` re-connects (`retrySessionLaunch`) then delivers; no reconnect from merely viewing the tab. | Matches **simple PTY** semantics — its shell is not spawned by opening the tab either (`ensureMemberTerminalForView` is a no-op for simple sessions). Reading a reclaimed session's stored transcript costs no agent process; a mismatched auto-reconnect would spawn on every glance. A stopped/failed agent keeps the existing Retry affordance. |
| P5 | Protection set reused: launching, ended, in-turn, pending permission/ask/plan, pinned, live seat lease, session agent-active, delivery in flight. | Same guarantees as mixed seats. |
| P6 | Default on with the shared switch. | Users who do not want it turn "回收空闲终端" off. Flagged in release notes; a dedicated switch can be added later. |

## Global Constraints

- Member placement / roster rules untouched; no `if (cli == …)` branches.
- Logging via `appLogger`; the reclaim pass already logs `[reclaim-watch]`.
- No new l10n keys: restore is silent, failures surface through the existing launch-error banner.
- Soft limits: services ~600 lines, cubits ~500 lines.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.

---

### Task 1: Reclaim an idle background personal ACP runtime

**Files:**
- Modify: `client/lib/services/chat/session/chat_tab.dart`
- Modify: `client/lib/services/chat/runtime/tab_member_reclaim_watch.dart`
- Modify: `client/lib/services/chat/runtime/tab_session_runtime_coordinator.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/cubits/chat/tab_member_reclaim_watch_test.dart`

**Interfaces:**
- Produces:
  - `ChatTab.reclaimedAcpRuntime` (`bool`, personal only): set when the personal cubit is
    discarded, cleared when it attaches.
  - `TabMemberReclaimWatch({..., String? Function()? activeSessionId, void Function(String sessionId)? onDiscardPersonalAcp})`.
  - `TabSessionRuntimeCoordinator({..., void Function(String sessionId)? onReclaimPersonalAcp})`
    (reuses its existing `activeSessionId`).

- [x] **Step 1: Failing tests**
  - `personal ACP hidden behind another tab is reclaimed`
  - `personal ACP tab that is centre-active is never reclaimed`
  - `personal ACP in turn / with a pending permission is never reclaimed`
  - `personal ACP with a live seat lease or pinned session is never reclaimed`
  - flip `never reclaims the selected, personal, or launching ACP seat` → personal is now
    reclaimable when hidden (keep selected + launching protected).

- [x] **Step 2:** `ChatTab.reclaimedAcpRuntime` field + doc comment.

- [x] **Step 3:** Watch: replace the `// D1` skip with a personal-aware branch — iterate the map as
  today, but for `isAcpChatSession(tab.persistedSession)` compute:
  - `memberId` = map key (session id), `isDisplayed = activeSessionId?.call() == tab.info.id`
  - `hasActiveLeases = _seatHasActiveLeases(sessionId, AcpChatRuntimeCubit.acpMemberId)`
  - `inTurn` also folds `sessionBusyFromAttention` / `sessionBusyFromDeliveryInFlight`
  - discard → `onDiscardPersonalAcp(sessionId)`; keep the shared `_idleSince` key.

- [x] **Step 4:** Thread `activeSessionId` + `onReclaimPersonalAcp` through the coordinator factory.

- [x] **Step 5:** `ChatCubit` wiring: `onReclaimPersonalAcp: _launchService.discardPersonalAcpRuntime`.

---

### Task 2: Discard + restore

**Files:**
- Modify: `client/lib/services/chat/launch/session_launch_service.dart`
- Modify: `client/lib/services/chat/launch/connect/acp_runtime_attach.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/cubits/chat/...` (restore tick) where the harness allows.

**Interfaces:**
- Produces: `void SessionLaunchService.discardPersonalAcpRuntime(String sessionId)`.

- [x] **Step 1:** `discardPersonalAcpRuntime`: null the personal cubit, set `reclaimedAcpRuntime`,
  `unawaited(cubit.close())` (persists transcript + agent id, kills the process, releases the
  background lease / attention), clear the agent-status seat (attention/lease under `'acp'`,
  status-lookup under the session id), `updateTabRunning`.
- [x] **Step 2:** `AcpRuntimeAttach.attachAcpRuntime`: clear `reclaimedAcpRuntime` on both the
  early-return (already attached) and post-attach paths.
- [x] **Step 3:** No auto-reconnect on tab activation (simple-PTY parity, P4):`_onIdleWatchTick`
  deliberately does **not** re-attach; restore is the composer's connect-then-send only.

---

### Task 3: Composer connect-then-send

**Files:**
- Modify: `client/lib/pages/chat_workbench.dart`
- Test: `client/test/pages/...` (existing chat workbench compose tests).

- [x] **Step 1:** In `onSubmit`, before the `hideTerminalToggle → failed()` escape: for a personal
  ACP session with a null runtime, `await chatCubit.retrySessionLaunch(sessionId)` (resolves after
  the attach settles), re-look-up the runtime, then `sendPrompt`. Only then fall back to `.failed()`.
  This is the *only* restore trigger (P4).

---

### Task 4: Docs + verification

- [x] **Step 1:** Note personal ACP scope in
  `docs/superpowers/specs/2026-10-12-mixed-team-acp-session-design.md` and the ACP reclaim spec
  (D1 now conditional).
- [x] **Step 2:** `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`.
- [x] **Step 3:** `cd client && dart run tool/run_tests.dart` (background; one full run before done).
