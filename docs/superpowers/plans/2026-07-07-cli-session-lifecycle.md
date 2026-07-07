# CLI Session Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `CliSessionLifecycleCapability` so mixed-team cursor sessions share a warm tier (`runtime/_shared/cursor/`), gate PTY connect until init phases complete, and cut N× cold indexing that causes embedded `cursor-agent` Reconnecting.

**Architecture:** New registry capability with manifest (`init.json`), session-level shared dirs (projects, cli-config base, auth), and per-member private overlay (chats, bus mcp/rules/hooks). `ConfigProfileService` calls `ensurePersisted` + `initialize`; `SessionLaunchService` consults `gateConnect` before `_connectMemberShell`. Cursor-only in Phase A; other CLIs use no-op default.

**Tech Stack:** Dart 3 / Flutter (`client/`), existing `CliToolRegistry`, `ConfigProfileService`, `CursorHomeProvisioner`, fake filesystem tests under `client/test/`.

**Design input:** [docs/superpowers/specs/2026-07-07-cli-session-lifecycle-design.md](../specs/2026-07-07-cli-session-lifecycle-design.md)

**Out of scope (Phase B/C):** personal standalone cursor, claude/codex lifecycle, workspace跨 session 缓存, UI booting labels, mailbox pull-first, headless pre-index.

---

## Locked implementation decisions

| Open question (spec §14) | Decision for Phase A |
|--------------------------|----------------------|
| Index complete判据 | Leader member PTY runs; poll `worker.log` for `Indexing finished` **or** `Indexing run failed` / timeout → `degraded` |
| `degraded` connect | **Allow** connect + `warnings` (do not block team) |
| Auth session share | **Unix:** symlink member `.config/cursor` → shared auth dir; **Windows:** copy `auth.json` if symlink fails |
| Leader election | First `initialize()` caller that claims empty `index.leaderMemberId`; tie-break by **roster order** in manifest write |
| `destroyCliState` | **Keep** `runtime/_shared/` on destroy (reopen reuse); only remove on explicit future "clear session data" |
| Index skip fast path | If `shared/projects/<slug>/` exists and `index.finishedAtMs != null` in manifest → jump to `ready` without leader PTY |

---

## File map (create / modify)

| File | Responsibility |
|------|----------------|
| `client/lib/services/cli/registry/capabilities/cli_session_lifecycle_capability.dart` | **Create.** Interface, phases, contexts, results, gate decision. |
| `client/lib/services/cli/registry/capabilities/noop_cli_session_lifecycle_capability.dart` | **Create.** Default allow-all for CLIs without lifecycle. |
| `client/lib/services/cli/session_lifecycle/cli_session_manifest.dart` | **Create.** `CliSessionManifest` model + JSON codec. |
| `client/lib/services/cli/session_lifecycle/cli_session_manifest_store.dart` | **Create.** Read/write `init.json` with session lock. |
| `client/lib/services/cli/session_lifecycle/cursor/cursor_cli_config_merger.dart` | **Create.** Merge user global `cli-config` → base; merge base + member permissions. |
| `client/lib/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_paths.dart` | **Create.** Shared/member paths, workspace slug, symlink/copy auth & projects. |
| `client/lib/services/cli/session_lifecycle/cursor/cursor_index_completion_probe.dart` | **Create.** Poll `worker.log` tail for index done/failed. |
| `client/lib/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_capability.dart` | **Create.** Cursor `ensurePersisted` / `initialize` / `gateConnect` / `finalize`. |
| `client/lib/services/storage/workspace_layout.dart` | **Modify.** `sessionRuntimeSharedToolDir`, `sessionLifecycleManifestPath`. |
| `client/lib/services/storage/runtime_layout.dart` | **Modify.** Delegate shared-tool + manifest paths. |
| `client/lib/services/provider/config_profile_service.dart` | **Modify.** Invoke lifecycle after `ensureSessionProfile`. |
| `client/lib/services/provider/cursor/cursor_home_provisioner.dart` | **Modify.** `provisionOverlayOnly` — bus files + permissions merge, no full tree recreate. |
| `client/lib/services/cli/registry/config_profile/cursor_config_profile_capability.dart` | **Modify.** Slim `contributeLaunch` — read manifest paths, delegate overlay to lifecycle. |
| `client/lib/services/cli/registry/tools/cursor_cli_tool.dart` | **Modify.** Register `CursorSessionLifecycleCapability`. |
| `client/lib/cubits/chat/session_launch_service.dart` | **Modify.** `gateConnect` before `_connectMemberShell`; async init hook. |
| `client/lib/cubits/chat/tab_team_bus_coordinator.dart` | **Modify.** `ensureMemberInputReady` respects lifecycle phase (optional defer doorbell). |
| `client/lib/services/cli/registry/capabilities/resume/cursor_resume_strategy.dart` | **Modify.** Read manifest `chatId` before scanning `chats/`. |
| Tests (see tasks) | Manifest, merger, paths, gate, lifecycle integration. |

---

## Phase flow (reference)

```
ensureSessionProfile (existing)
  → lifecycle.ensurePersisted
  → lifecycle.initialize (per member, before connect)
scheduleMemberConnect
  → lifecycle.gateConnect → deny: stay booting / retry
  → _connectMemberShell (existing)
```

---

### Task 1: Core types + no-op capability

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/cli_session_lifecycle_capability.dart`
- Create: `client/lib/services/cli/registry/capabilities/noop_cli_session_lifecycle_capability.dart`
- Test: `client/test/services/cli/registry/noop_cli_session_lifecycle_capability_test.dart`

- [ ] **Step 1: Write failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/noop_cli_session_lifecycle_capability.dart';

void main() {
  test('no-op gateConnect always allows', () {
    const cap = NoopCliSessionLifecycleCapability();
    expect(
      cap.gateConnect(const CliSessionGateContext(
        workspaceId: 'w',
        sessionId: 's',
        memberId: 'm',
        tool: CliTool.claude,
      )).allowed,
      isTrue,
    );
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client && flutter test test/services/cli/registry/noop_cli_session_lifecycle_capability_test.dart`

- [ ] **Step 3: Implement types + no-op**

Define `CliSessionPhase` enum: `persisted`, `auth`, `config`, `overlay`, `indexing`, `resume`, `ready`, `degraded`.

Define `CliSessionGateDecision({required bool allowed, String? reason})`.

Define contexts (`CliSessionPersistContext`, `CliSessionInitContext`, `CliSessionGateContext`, `CliSessionFinalizeContext`) with `workspaceId`, `sessionId`, `memberId`, `CliTool tool`, `ConfigProfileDelegate paths`, optional `TeamProfile`, `MemberBusIdleEndpoint? busIdle`, `workingDirectory`.

`NoopCliSessionLifecycleCapability`: all methods no-op; `gateConnect` → `allowed: true`.

- [ ] **Step 4: Run test — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/cli_session_lifecycle_capability.dart \
        client/lib/services/cli/registry/capabilities/noop_cli_session_lifecycle_capability.dart \
        client/test/services/cli/registry/noop_cli_session_lifecycle_capability_test.dart
git commit -m "feat(cli): add CliSessionLifecycleCapability scaffold and no-op default"
```

---

### Task 2: Layout path APIs

**Files:**
- Modify: `client/lib/services/storage/workspace_layout.dart`
- Modify: `client/lib/services/storage/runtime_layout.dart`
- Test: `client/test/services/storage/workspace_layout_session_shared_test.dart`

- [ ] **Step 1: Write failing test**

```dart
test('sessionRuntimeSharedToolDir is under runtime/_shared', () {
  final layout = WorkspaceLayout(teampilotRoot: '/tp', fs: LocalFilesystem());
  final path = layout.sessionRuntimeSharedToolDir('ws', 'sess', 'cursor');
  expect(path, contains('/runtime/_shared/cursor'));
  expect(path, isNot(contains('/team-lead/')));
});
```

- [ ] **Step 2: Run test — expect FAIL**

- [ ] **Step 3: Implement**

```dart
// workspace_layout.dart
String sessionRuntimeSharedToolDir(
  String workspaceId,
  String sessionId,
  String tool,
) => _ctx.join(
  sessionRuntimeDir(workspaceId, sessionId),
  '_shared',
  tool.trim(),
);

String sessionLifecycleManifestPath(
  String workspaceId,
  String sessionId,
  String tool,
) => _ctx.join(
  sessionRuntimeSharedToolDir(workspaceId, sessionId, tool),
  'init.json',
);
```

Mirror delegates on `RuntimeLayout`.

- [ ] **Step 4: Run test — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(storage): add session shared tool dir and lifecycle manifest paths"
```

---

### Task 3: Manifest model + store

**Files:**
- Create: `client/lib/services/cli/session_lifecycle/cli_session_manifest.dart`
- Create: `client/lib/services/cli/session_lifecycle/cli_session_manifest_store.dart`
- Test: `client/test/services/cli/session_lifecycle/cli_session_manifest_store_test.dart`

- [ ] **Step 1: Write failing round-trip test**

Use in-memory / temp dir via existing test filesystem helpers (`setUpTestAppStorage` pattern if needed).

Assert: write manifest with `phase: persisted`, read back equal; `updatePhase` mutates `phaseUpdatedAtMs`.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

`CliSessionManifest` fields per spec §7 (`schemaVersion`, `tool`, `workspaceId`, `sessionId`, `workspaceSlug`, `phase`, `shared`, `index`, `members`).

`CliSessionManifestStore`:
- `Future<CliSessionManifest?> read(...)`
- `Future<void> write(...)` — atomic via `fs.atomicWrite`
- Session-level lock: static `Map<String, Future<void>>` keyed by `workspaceId|sessionId|tool` or reuse `synchronized` package if already in pubspec (else simple `Completer` chain like `RuntimeLayout` locks).

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(cli): add CliSessionManifest store for session lifecycle"
```

---

### Task 4: Cursor cli-config merger

**Files:**
- Create: `client/lib/services/cli/session_lifecycle/cursor/cursor_cli_config_merger.dart`
- Test: `client/test/services/cli/session_lifecycle/cursor/cursor_cli_config_merger_test.dart`

- [ ] **Step 1: Write failing tests**

Cases:
1. `extractWarmTier` copies `serverConfigCache` + `network` from user json, strips `permissions.allow` bus entries.
2. `mergeMemberConfig` combines base + `Mcp(teammate-bus:*)` without duplicating.
3. Missing keys in base → member still valid `{}` version.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

Pure functions; use `CursorCliConfigPolicy.applyMixedTeamSessionPolicy` for member permissions.

```dart
abstract final class CursorCliConfigMerger {
  static Map<String, Object?> extractWarmTier(Map<String, Object?> userConfig) { ... }
  static Map<String, Object?> mergeMemberConfig({
    required Map<String, Object?> base,
    required Map<String, Object?> memberOverrides,
  }) { ... }
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(cursor): add cli-config warm-tier merge helpers"
```

---

### Task 5: Cursor lifecycle paths + symlink helpers

**Files:**
- Create: `client/lib/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_paths.dart`
- Test: `client/test/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_paths_test.dart`

- [ ] **Step 1: Write failing tests**

Use fake `Filesystem` if available in `client/test/support/`, else temp directory.

Cases:
1. `memberHomeRoot` → `runtime/{memberId}/cursor/home`
2. `sharedProjectsDir(slug)` → `runtime/_shared/cursor/projects/{slug}`
3. `ensureMemberProjectsLink` creates symlink on Unix (skip on Windows CI → copy fallback)

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

Reuse `CursorWorkspaceTrust.workspaceSlugForDirectory(workingDirectory)` for slug.

Methods:
- `sharedRoot`, `sharedAuthDir`, `sharedProjectsDir`, `memberHomeRoot`, `memberCursorDir`
- `Future<void> ensureSharedDirs()`
- `Future<void> ensureMemberHomeLayout({required String memberId})` — dirs + projects link
- `Future<void> linkOrCopyAuth({required String memberHome})`

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(cursor): add session lifecycle path and symlink helpers"
```

---

### Task 6: `gateConnect` logic (cursor)

**Files:**
- Create: `client/lib/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_capability.dart` (partial — gate only first)
- Test: `client/test/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_gate_test.dart`

- [ ] **Step 1: Write failing gate tests**

| phase | member | leader | overlayGen | expected |
|-------|--------|--------|------------|----------|
| ready | any | — | match | allow |
| indexing | leader | self | match | allow |
| indexing | other | architect | match | deny |
| degraded | any | — | match | allow |
| ready | any | — | stale | deny (reason: overlay) |

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement `gateConnect` + manifest read**

Constructor injects `CliSessionManifestStore`, `CursorSessionLifecyclePaths`.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(cursor): add lifecycle gateConnect phase rules"
```

---

### Task 7: `ensurePersisted` (cursor)

**Files:**
- Modify: `client/lib/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_capability.dart`
- Test: `client/test/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_persist_test.dart`

- [ ] **Step 1: Write failing test**

Given mixed team with members `[team-lead, architect]`, after `ensurePersisted`:
- `init.json` exists with `phase: persisted`
- Both member `home/.cursor/projects` links point to shared slug dir
- `shared/projects/{slug}/` directory exists

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement `ensurePersisted`**

1. Resolve `workspaceSlug` from `ctx.workingDirectory`.
2. `ensureSharedDirs`.
3. For each roster member (or single `ctx.memberId` if provided): `ensureMemberHomeLayout`.
4. Create/update manifest (`members[memberId].homeRoot`).

Idempotent: second call no error, manifest unchanged except new members added.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(cursor): implement lifecycle ensurePersisted with shared projects"
```

---

### Task 8: Overlay-only provisioner

**Files:**
- Modify: `client/lib/services/provider/cursor/cursor_home_provisioner.dart`
- Test: `client/test/services/provider/cursor/cursor_home_provisioner_overlay_test.dart`

- [ ] **Step 1: Write failing test**

`provisionOverlayOnly` writes only paths in `CursorAuthArtifacts.busGenerated` + merged `cli-config.json`; does **not** delete `chats/` or shared projects.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Refactor**

Extract from `provision`:
- `provisionOverlayOnly({memberHome, member, busIdle, forceTeamLeadDelegateMode, cliConfigJson})`
- Keep `provision` calling overlay + legacy paths for non-lifecycle callers until Task 11 removes duplication.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor(cursor): add provisionOverlayOnly for lifecycle bus files"
```

---

### Task 9: `initialize` phases auth → config → overlay → resume

**Files:**
- Modify: `client/lib/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_capability.dart`
- Test: `client/test/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_initialize_test.dart`

- [ ] **Step 1: Write failing tests**

With fake filesystem + stub credentials service (inject interface):
1. After `initialize`, `shared/cli-config.base.json` contains `serverConfigCache` from fixture user config.
2. Member `cli-config.json` includes `Mcp(teammate-bus:*)`.
3. `mcp.json` contains `X-Member` header.
4. Phase ends at `resume` or `ready` when index fast-path applies.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

**auth:** session-level `CursorProviderCredentialsService.syncAuthToMemberHome` once into `shared/auth/`; link/copy to member.

**config:** read `~/.cursor/cli-config.json` via `Platform.environment['HOME']` + `CursorHomeLayout.cliConfig`; write base.

**overlay:** `CursorHomeProvisioner.provisionOverlayOnly`.

**resume:** if manifest has `chatId`, keep; else no-op (capture on finalize).

Update manifest phase after each step.

**index fast-path:** if `index.finishedAtMs != null` and projects dir non-empty → set `ready` and return.

Else set `indexing`, assign `leaderMemberId` if empty (current member if lowest roster index among pending).

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(cursor): implement lifecycle initialize through overlay"
```

---

### Task 10: Index completion probe + phase transition

**Files:**
- Create: `client/lib/services/cli/session_lifecycle/cursor/cursor_index_completion_probe.dart`
- Modify: `cursor_session_lifecycle_capability.dart`
- Modify: `client/lib/cubits/chat/session_launch_service.dart`
- Test: `client/test/services/cli/session_lifecycle/cursor/cursor_index_completion_probe_test.dart`

- [ ] **Step 1: Write probe unit test**

Fixture `worker.log` snippet with `Indexing finished` → `IndexProbeResult.done`; with `Indexing run failed` → `failed`.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement probe**

```dart
enum IndexProbeResult { pending, done, failed }

abstract final class CursorIndexCompletionProbe {
  static IndexProbeResult scan(String logTail);
}
```

**Leader connect path** in `session_launch_service.dart`:

After leader shell connects, start periodic timer (e.g. 2s) reading:
`{memberHome}/.cursor/projects/{slug}/worker.log` (path from `CursorSessionLifecyclePaths` — align with actual cursor layout under projects).

On `done` → manifest `phase: ready`, `index.finishedAtMs = now`.

On `failed` or 10min timeout → `phase: degraded`.

Non-leader members: `gateConnect` denies until `ready|degraded`.

- [ ] **Step 4: Run unit tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(cursor): index completion probe and leader phase transition"
```

---

### Task 11: Wire `ConfigProfileService`

**Files:**
- Modify: `client/lib/services/provider/config_profile_service.dart`
- Test: extend `client/test/services/provider/config_profile_service_test.dart` or new lifecycle integration test

- [ ] **Step 1: Write failing test**

When `ensureSessionProfile` called for cursor mixed member, manifest file is created (mock lifecycle or real).

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

After existing `cap.ensureSessionProfile` block (~line 344):

```dart
final lifecycle = _cliRegistry.capability<CliSessionLifecycleCapability>(cli);
if (lifecycle != null) {
  await lifecycle.ensurePersisted(CliSessionPersistContext(...));
}
```

Add helper on registry:

```dart
CliSessionLifecycleCapability lifecycleFor(CliTool cli) =>
  capability<CliSessionLifecycleCapability>(cli) ??
  const NoopCliSessionLifecycleCapability();
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(cli): invoke lifecycle ensurePersisted from config profile service"
```

---

### Task 12: Wire `SessionLaunchService` gate + initialize

**Files:**
- Modify: `client/lib/cubits/chat/session_launch_service.dart`
- Test: `client/test/cubits/chat/session_launch_lifecycle_gate_test.dart`

- [ ] **Step 1: Write failing test**

Mock `CliSessionLifecycleCapability` with `gateConnect → deny`; assert `_scheduleMemberConnect` does not call connect (shell stays not connecting).

Use test harness / inject registry stub if available; otherwise extract package-private hook `@visibleForTesting`.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

In `_scheduleMemberConnect` before `_connectMemberShell` (~line 1965):

```dart
final cli = SessionMemberCliResolver.resolve(...);
final lifecycle = _h.cliRegistry.lifecycleFor(cli);
final initCtx = CliSessionInitContext(...);
await lifecycle.initialize(initCtx);
final gate = lifecycle.gateConnect(CliSessionGateContext(...));
if (!gate.allowed) {
  appLogger.d('[session-launch] lifecycle gate deny member=${member.id} reason=${gate.reason}');
  tab.membersPendingConnect.remove(member.id);
  _h.finishSessionConnect(tab.info.id); // stay booting, coordinator may retry
  return;
}
```

Ensure `SessionLaunchService` has access to `CliToolRegistry` (likely via `_h.lifecycle` or `app_shell` — follow existing `cursorAgentModelsService` injection pattern).

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(session-launch): gate member connect on cli session lifecycle"
```

---

### Task 13: Register capability + slim cursor config profile

**Files:**
- Modify: `client/lib/services/cli/registry/tools/cursor_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/config_profile/cursor_config_profile_capability.dart`
- Modify: `client/lib/services/cli/registry/capabilities/resume/cursor_resume_strategy.dart`

- [ ] **Step 1: Register lifecycle on CursorCliTool**

```dart
final class CursorCliTool implements CliToolDefinition {
  CursorCliTool({
    ...
    this.sessionLifecycle = const CursorSessionLifecycleCapability(),
  });
  final CliSessionLifecycleCapability sessionLifecycle;

  @override
  Iterable<CliCapability> get capabilities => [
    ...
    sessionLifecycle,
  ];
}
```

- [ ] **Step 2: Slim `_contributeTeamLaunch`**

Remove duplicate `CursorHomeProvisioner.provision` when lifecycle already ran overlay via `initialize` in launch path.

`contributeLaunch` reads manifest for `memberHome` path; returns `CursorLaunchEnvironment.forMixed(homeRoot: ...)`.

Keep workspace trust in `contributeLaunch` (or move to `ensurePersisted` — either is fine; prefer **once** in lifecycle `ensurePersisted`).

- [ ] **Step 3: Resume reads manifest first**

In `CursorResumeStrategy.detectNativeId`, if manifest store returns `members[memberId].chatId`, return it.

- [ ] **Step 4: Run affected tests**

Run: `cd client && flutter test test/services/cli/ test/services/provider/cursor/ --exclude-tags integration`

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(cursor): register session lifecycle and slim config profile launch"
```

---

### Task 14: `finalize` + overlay generation bump

**Files:**
- Modify: `cursor_session_lifecycle_capability.dart`
- Modify: `client/lib/cubits/chat/tab_team_bus_coordinator.dart` (on bus remount / tunnel rebuild)

- [ ] **Step 1: Implement `finalize`**

On member dispose / session close: scan chats for latest `chatId`, write manifest `members[memberId].chatId` + `resumeCapturedAtMs`.

- [ ] **Step 2: Bump `overlayGeneration`**

When `MemberBusIdleEndpoint` port/token changes (gateway re-register, SSH tunnel rebuild), increment manifest `overlayGeneration` and force `phase` back to `overlay` for affected members.

Hook: `TabTeamBusCoordinator.installBusForTab` after `gateway.register`.

- [ ] **Step 3: Test overlay stale gate**

Unit test: `overlayGeneration` mismatch → `gateConnect` deny until `initialize` refreshes overlay.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(cursor): lifecycle finalize and overlay generation on bus remount"
```

---

### Task 15: Integration test (2× cursor, gate + shared projects)

**Files:**
- Create: `client/test/integration/cursor_session_lifecycle_integration_test.dart`
- Tag: `@Tags(['integration'])` only if touches real PTY; prefer **fake filesystem + mock lifecycle** unit integration first.

- [ ] **Step 1: Write integration test (filesystem level)**

Simulate:
1. `ensurePersisted` for two members.
2. Member A `initialize` → becomes leader, `indexing`.
3. Member B `gateConnect` → denied.
4. Manifest update to `ready`.
5. Member B `gateConnect` → allowed.
6. Assert single shared `projects/` directory.

- [ ] **Step 2: Run**

Run: `cd client && flutter test test/services/cli/session_lifecycle/ test/integration/cursor_session_lifecycle_integration_test.dart`

- [ ] **Step 3: Commit**

```bash
git commit -m "test(cursor): session lifecycle shared projects and connect gate"
```

---

### Task 16: Full verification + doc update

**Files:**
- Modify: `docs/superpowers/specs/2026-07-07-cli-session-lifecycle-design.md` (status → Phase A implemented)

- [ ] **Step 1: Run analyzer + unit tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```

Expected: no errors.

- [ ] **Step 2: Manual smoke (mixed 2×cursor)**

1. Open Superpowers Quartet or 2-member cursor team.
2. Confirm only one `worker.log` active indexing under `runtime/_shared/cursor/projects/`.
3. Second member shows booting until first finishes.
4. Reopen session → no full merkle replay (log line count stable).

- [ ] **Step 3: Update spec status header**

`状态：**Phase A 已落地**`

- [ ] **Step 4: Commit**

```bash
git commit -m "docs: mark cli session lifecycle Phase A implemented"
```

---

## Dependency graph

```
Task 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 12 → 13 → 14 → 15 → 16
         └──────────────────────────────────────────────────┘
                    Tasks 6–9 can parallelize after Task 5
```

**Recommended serial order for one agent:** 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 12 → 13 → 14 → 15 → 16.

**Parallelizable:** Task 4 (merger) ∥ Task 3 (manifest) after Task 2; Task 8 (provisioner) after Task 4.

---

## Risk mitigations

| Risk | Mitigation |
|------|------------|
| Symlink on Windows | `linkOrCopyAuth` + projects directory junction/copy fallback |
| `worker.log` path differs by cursor version | Log probe uses suffix match; fallback `degraded` after timeout |
| Launch service registry access | Add `CliToolRegistry` to launch harness deps (mirror `ChatCubit` bootstrap) |
| Double provision | Lifecycle owns overlay; remove from `contributeLaunch` in Task 13 |
| SSH remote paths | All lifecycle IO via work-plane `ConfigProfileDelegate` paths — **no** `Directory.current` |

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-07-cli-session-lifecycle.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — one subagent per task (1–16), review between tasks (@superpowers:subagent-driven-development).

2. **Inline Execution** — implement Tasks 1–16 in this session with checkpoints after Tasks 5, 10, 13, 16 (@superpowers:executing-plans).

Which approach do you want?
