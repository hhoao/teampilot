# Workspace-scoped root IS_SANDBOX opt-in Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the “Inject IS_SANDBOX for root” trust toggle from per-SSH-target `targets.json` into a single per-workspace flag on `Workspace` / `manifest.json`, with UI in workspace settings and launch reading `activeSession.workspaceId`.

**Architecture:** Persist `Workspace.rootSandboxEnvOptIn` (default `false`, omit when false). Extend the existing workspace-metadata update path. Change `SessionLaunchHost` to query by workspace id; `session_shell_connector` passes that bool into `applyRemoteSshLaunchConstraints`. Delete the SSH dialog tile and all `TargetsRepository` root-sandbox APIs — no migration.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, existing `TpPreferenceRow` / `TpCard` / l10n ARB.

**Spec:** [`docs/superpowers/specs/2026-07-17-workspace-root-sandbox-env-opt-in-design.md`](../specs/2026-07-17-workspace-root-sandbox-env-opt-in-design.md)

---

## File map

| Path | Responsibility |
|------|----------------|
| Modify: `client/lib/models/workspace.dart` | Add `rootSandboxEnvOptIn`; JSON / copyWith / == / hashCode |
| Modify: `client/test/models/workspace_test.dart` | Round-trip + default-off tests |
| Modify: `client/lib/repositories/session_repository.dart` | Persist flag in `updateWorkspaceMetadata` |
| Modify: `client/lib/cubits/chat/session_data_store.dart` | Forward optional flag |
| Modify: `client/lib/cubits/chat_cubit.dart` | Forward flag; replace target-based host method |
| Modify: `client/lib/cubits/chat/session_launch_host.dart` | `isWorkspaceRootSandboxEnvOptIn(workspaceId)` |
| Modify: `client/lib/services/launch/session_shell_connector.dart` | Read via `activeSession.workspaceId` |
| Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb` (+ generated l10n) | `{host}` → `{workspace}` confirm copy |
| Modify: `client/lib/pages/ssh_profiles/ssh_profile_target_config_dialog.dart` | Remove sandbox tile + wrapper class (**before** deleting targets APIs) |
| Modify: `client/lib/services/storage/targets_repository.dart` | Remove root-sandbox field + APIs |
| Modify: `client/test/services/storage/targets_repository_p3c_test.dart` | Drop root-sandbox test |
| Move: `client/lib/pages/ssh_profiles/root_sandbox_env_opt_in_tile.dart` → `client/lib/pages/home_workspace/workspace/root_sandbox_env_opt_in_tile.dart` | Workspace-owned tile; `host` → `workspaceLabel` |
| Modify: `client/lib/pages/home_workspace/workspace/workspace_info_section.dart` | Independent settings card |
| Modify: `client/test/pages/home_workspace/workspace/workspace_info_section_target_test.dart` | Smoke: card title visible |

**Unchanged:** `remote_ssh_launch_constraints.dart` policy logic (only data source of `injectRootSandboxEnv` changes).

**Task order (compile-safe):** 1 model → 2 persist → 3 launch → 4 l10n → 5 SSH UI strip + targets API delete → 6 workspace card → 7 verify.

---

### Task 1: `Workspace.rootSandboxEnvOptIn` model (TDD)

**Files:**
- Modify: `client/test/models/workspace_test.dart`
- Modify: `client/lib/models/workspace.dart`

- [ ] **Step 1: Write the failing tests**

Append to `client/test/models/workspace_test.dart`:

```dart
test('rootSandboxEnvOptIn defaults false and is omitted from toJson', () {
  final ws = Workspace(
    workspaceId: 'p1',
    folders: const [WorkspaceFolder(path: '/tmp/repo')],
    createdAt: 1,
  );
  expect(ws.rootSandboxEnvOptIn, isFalse);
  expect(ws.toJson().containsKey('rootSandboxEnvOptIn'), isFalse);
});

test('rootSandboxEnvOptIn true round-trips', () {
  final ws = Workspace(
    workspaceId: 'p1',
    folders: const [WorkspaceFolder(path: '/tmp/repo')],
    createdAt: 1,
    rootSandboxEnvOptIn: true,
  );
  final json = ws.toJson();
  expect(json['rootSandboxEnvOptIn'], isTrue);
  final restored = Workspace.fromJson(json);
  expect(restored.rootSandboxEnvOptIn, isTrue);
});

test('rootSandboxEnvOptIn ignores non-true json values', () {
  final restored = Workspace.fromJson({
    'workspaceId': 'p1',
    'folders': const [
      {'path': '/tmp/repo', 'targetId': 'local'},
    ],
    'createdAt': 1,
    'rootSandboxEnvOptIn': 'yes',
  });
  expect(restored.rootSandboxEnvOptIn, isFalse);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd client && flutter test test/models/workspace_test.dart --name rootSandboxEnvOptIn
```

Expected: FAIL (undefined getter / named param).

- [ ] **Step 3: Implement minimal model changes**

In `client/lib/models/workspace.dart`:

1. Add field `this.rootSandboxEnvOptIn = false` to private ctor, public factory, and as `final bool rootSandboxEnvOptIn`.
2. `fromJson`: `rootSandboxEnvOptIn: json['rootSandboxEnvOptIn'] == true`.
3. `copyWith`: add `bool? rootSandboxEnvOptIn` with `rootSandboxEnvOptIn: rootSandboxEnvOptIn ?? this.rootSandboxEnvOptIn`.
4. `toJson`: `if (rootSandboxEnvOptIn) 'rootSandboxEnvOptIn': true`.
5. Include in `==` and `hashCode`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd client && flutter test test/models/workspace_test.dart --name rootSandboxEnvOptIn
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/workspace.dart client/test/models/workspace_test.dart
git commit -m "feat(workspace): add rootSandboxEnvOptIn to manifest model"
```

---

### Task 2: Persist via repository + cubit

**Files:**
- Modify: `client/lib/repositories/session_repository.dart` (`updateWorkspaceMetadata`)
- Modify: `client/lib/cubits/chat/session_data_store.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`

- [ ] **Step 1: Extend `SessionRepository.updateWorkspaceMetadata`**

Signature becomes:

```dart
Future<void> updateWorkspaceMetadata(
  String workspaceId, {
  String? display,
  String? defaultProfileId,
  bool? rootSandboxEnvOptIn,
}) async {
  // ...
  final updated = existing.copyWith(
    display: display != null ? display.trim() : existing.display,
    defaultProfileId: defaultProfileId != null
        ? defaultProfileId.trim()
        : existing.defaultProfileId,
    folders: existing.folders,
    rootSandboxEnvOptIn:
        rootSandboxEnvOptIn ?? existing.rootSandboxEnvOptIn,
    updatedAt: now,
  );
  await _writeManifest(fs, updated);
}
```

- [ ] **Step 2: Forward through `SessionDataStore` and `ChatCubit`**

Mirror the optional `bool? rootSandboxEnvOptIn` on both `updateWorkspaceMetadata` methods so UI can call:

```dart
await context.read<ChatCubit>().updateWorkspaceMetadata(
  context.read<SessionRepository>(),
  workspace.workspaceId,
  rootSandboxEnvOptIn: next,
);
```

- [ ] **Step 3: Optional persistence check**

If convenient, extend `client/test/repositories/session_repository_test.dart` (existing `updateWorkspaceMetadata` coverage) to assert `rootSandboxEnvOptIn: true` survives write/reload. Skip if that harness is heavy — Task 1 + UI smoke suffice.

- [ ] **Step 4: Commit**

```bash
git add client/lib/repositories/session_repository.dart \
  client/lib/cubits/chat/session_data_store.dart \
  client/lib/cubits/chat_cubit.dart
git commit -m "feat(workspace): persist rootSandboxEnvOptIn via metadata update"
```

---

### Task 3: Launch path reads workspace flag

**Files:**
- Modify: `client/lib/cubits/chat/session_launch_host.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Modify: `client/lib/services/launch/session_shell_connector.dart`
- Modify: any `SessionLaunchHost` fake that declares the old method (today only `session_prompt_metadata_sync_test.dart` uses `noSuchMethod` — likely no change)

- [ ] **Step 1: Rename host API**

In `session_launch_host.dart` replace:

```dart
/// SSH root-sandbox env injection preference for a runtime target.
Future<bool> isRootSandboxEnvOptIn(String targetId);
```

with:

```dart
/// Workspace opt-in: inject IS_SANDBOX when launching Claude as root over SSH.
Future<bool> isWorkspaceRootSandboxEnvOptIn(String workspaceId);
```

- [ ] **Step 2: Implement on `ChatCubit`**

Replace the `TargetsRepository()` call with:

```dart
@override
Future<bool> isWorkspaceRootSandboxEnvOptIn(String workspaceId) async {
  final id = workspaceId.trim();
  if (id.isEmpty) return false;
  for (final w in state.workspaces) {
    if (w.workspaceId == id) return w.rootSandboxEnvOptIn;
  }
  return false;
}
```

- [ ] **Step 3: Wire connector**

In `session_shell_connector.dart` (~line 347), change:

```dart
if (launchTarget.kind == RuntimeKind.ssh) {
  final injectRootSandboxEnv = await _host.isWorkspaceRootSandboxEnvOptIn(
    activeSession.workspaceId,
  );
  shellLaunch = await applyRemoteSshLaunchConstraints(
    spec: shellLaunch,
    memberTarget: launchTarget,
    memberSession: memberSshSession,
    profile: _host.shellFactory.profileFor(launchTarget),
    injectRootSandboxEnv: injectRootSandboxEnv,
  );
}
```

Do **not** pass `launchTarget.id`.

- [ ] **Step 4: Analyze / compile check**

```bash
cd client && dart analyze lib/cubits/chat/session_launch_host.dart \
  lib/cubits/chat_cubit.dart \
  lib/services/launch/session_shell_connector.dart
```

Expected: no errors related to the renamed method.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat/session_launch_host.dart \
  client/lib/cubits/chat_cubit.dart \
  client/lib/services/launch/session_shell_connector.dart
git commit -m "feat(launch): read root IS_SANDBOX opt-in from workspace"
```

---

### Task 4: l10n confirm copy uses workspace

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Regenerate / update: `app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_zh.dart`

- [ ] **Step 1: Edit ARB**

`app_en.arb`:

```json
"rootSandboxEnvConfirmBody": "TeamPilot will set IS_SANDBOX=1 when launching Claude as root in workspace {workspace}, keeping --dangerously-skip-permissions. Only enable for workspaces you trust.",
"@rootSandboxEnvConfirmBody": { "placeholders": { "workspace": {} } },
```

`app_zh.arb`:

```json
"rootSandboxEnvConfirmBody": "在工作区 {workspace} 中以 root 启动 Claude 时，TeamPilot 将设置 IS_SANDBOX=1 并保留 --dangerously-skip-permissions。请仅对你信任的工作区开启。",
"@rootSandboxEnvConfirmBody": { "placeholders": { "workspace": {} } },
```

Keep title/subtitle/action keys unchanged. No `gen_warmup_glyphs` run needed for these strings.

- [ ] **Step 2: Regenerate localizations**

```bash
cd client && flutter gen-l10n
```

If the project expects hand-synced files, update the three generated Dart files so `rootSandboxEnvConfirmBody(Object workspace)` matches the new placeholder name.

- [ ] **Step 3: Commit**

```bash
git add client/lib/l10n/
git commit -m "l10n: root sandbox confirm refers to workspace"
```

---

### Task 5: Strip SSH dialog, then delete per-target storage API

**Why same task:** `SshProfileRootSandboxEnvOptInTile` calls `TargetsRepository.isRootSandboxEnvOptIn` / `setRootSandboxEnvOptIn`. Remove the UI caller **before** deleting those APIs so each commit still compiles.

**Files:**
- Modify: `client/lib/pages/ssh_profiles/ssh_profile_target_config_dialog.dart`
- Modify: `client/lib/services/storage/targets_repository.dart`
- Modify: `client/test/services/storage/targets_repository_p3c_test.dart`
- Keep (unused until Task 6): `client/lib/pages/ssh_profiles/root_sandbox_env_opt_in_tile.dart` — Task 6 `git mv`s it; do **not** delete here.

- [ ] **Step 1: Strip SSH dialog**

In `ssh_profile_target_config_dialog.dart`:

- Remove import of `root_sandbox_env_opt_in_tile.dart`.
- Remove `SshProfileRootSandboxEnvOptInTile` usage and the entire wrapper class (~lines 96–144).
- Leave `SshProfileCredentialOptInTile` with `showDividerBelow: false`.

Do **not** delete `root_sandbox_env_opt_in_tile.dart` yet if Task 6 will move it; after this step it may be temporarily unused until Task 6. Prefer: `git mv` the tile into the workspace folder in Step 1 of Task 6 immediately after this commit, or perform the move at the end of this task (see Step 5).

- [ ] **Step 2: Delete the root-sandbox repository test**

Remove the entire `test('rootSandboxEnvOptIn defaults off and round-trips', …)` block from `targets_repository_p3c_test.dart`.

- [ ] **Step 3: Strip `TargetsRegistryFile` / `TargetsRepository`**

Remove:

- ctor param / field `rootSandboxEnvOptIn`
- `fromJson` / `toJson` / `copyWith` handling
- `isRootSandboxEnvOptIn` / `setRootSandboxEnvOptIn`

Leave credential / install / cliPathOverrides untouched. Old JSON keys are ignored automatically once `fromJson` stops reading them.

- [ ] **Step 4: Run targets tests**

```bash
cd client && flutter test test/services/storage/targets_repository_p3c_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/ssh_profiles/ssh_profile_target_config_dialog.dart \
  client/lib/services/storage/targets_repository.dart \
  client/test/services/storage/targets_repository_p3c_test.dart
git commit -m "refactor: drop SSH root IS_SANDBOX toggle and targets API"
```

---

### Task 6: Workspace settings UI card

**Files:**
- Move: `client/lib/pages/ssh_profiles/root_sandbox_env_opt_in_tile.dart` → `client/lib/pages/home_workspace/workspace/root_sandbox_env_opt_in_tile.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_info_section.dart`
- Modify: `client/test/pages/home_workspace/workspace/workspace_info_section_target_test.dart`

- [ ] **Step 1: Move and rename tile parameter**

```bash
git mv client/lib/pages/ssh_profiles/root_sandbox_env_opt_in_tile.dart \
  client/lib/pages/home_workspace/workspace/root_sandbox_env_opt_in_tile.dart
```

In the moved file:

- Rename ctor param `host` → `workspaceLabel`.
- `showRootSandboxEnvConfirm(context, workspaceLabel)` calls `l10n.rootSandboxEnvConfirmBody(workspaceLabel)`.
- Fix relative imports for the new path (`../../l10n/...`).

- [ ] **Step 2: Add independent card in `WorkspaceInfoSection`**

Add imports for the moved tile, `SessionRepository`, and `l10n_extensions` / `workspace_display_name` as needed.

Between the basic-info `TpCard` and `WorkspaceFoldersSection`, insert:

```dart
const SizedBox(height: 12),
TpCard.outlined(
  child: WorkspaceRootSandboxEnvOptInCard(workspace: live),
),
```

Implement a small helper (same file or sibling). Prefer reading the live workspace from `ChatCubit` (same pattern as the section’s `live` select) **or** using the constructor `workspace` after the parent already selected `live` — do not double-select confusingly:

```dart
class WorkspaceRootSandboxEnvOptInCard extends StatelessWidget {
  const WorkspaceRootSandboxEnvOptInCard({required this.workspace, super.key});
  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    final live = context.select<ChatCubit, Workspace>(
      (c) => c.state.workspaces.firstWhere(
        (p) => p.workspaceId == workspace.workspaceId,
        orElse: () => workspace,
      ),
    );
    final l10n = context.l10n;
    return RootSandboxEnvOptInTile(
      workspaceLabel: live.localizedName(l10n),
      optedIn: live.rootSandboxEnvOptIn,
      showDividerBelow: false,
      onChanged: (next) async {
        await context.read<ChatCubit>().updateWorkspaceMetadata(
          context.read<SessionRepository>(),
          live.workspaceId,
          rootSandboxEnvOptIn: next,
        );
      },
    );
  }
}
```

`SessionRepository` is already provided in the workspace config shell / existing info-section test.

- [ ] **Step 3: Widget smoke test**

In `workspace_info_section_target_test.dart`, after existing folders assertion, add:

```dart
expect(find.text(l10n.rootSandboxEnvOptInTitle), findsOneWidget);
```

- [ ] **Step 4: Run UI + related tests**

```bash
cd client && flutter test \
  test/models/workspace_test.dart \
  test/pages/home_workspace/workspace/workspace_info_section_target_test.dart \
  test/services/storage/targets_repository_p3c_test.dart \
  test/services/session/remote_ssh_launch_constraints_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/root_sandbox_env_opt_in_tile.dart \
  client/lib/pages/home_workspace/workspace/workspace_info_section.dart \
  client/test/pages/home_workspace/workspace/workspace_info_section_target_test.dart
# ensure old ssh_profiles path is gone (git mv already)
git commit -m "feat(workspace): root IS_SANDBOX opt-in settings card"
```

---

### Task 7: Final verification

- [ ] **Step 1: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no new errors from this change.

- [ ] **Step 2: Targeted tests (if anything still flaky, re-run Task 6 suite)**

```bash
cd client && flutter test \
  test/models/workspace_test.dart \
  test/services/storage/targets_repository_p3c_test.dart \
  test/pages/home_workspace/workspace/workspace_info_section_target_test.dart \
  test/services/session/remote_ssh_launch_constraints_test.dart
```

- [ ] **Step 3: Manual smoke (human)**

1. Open workspace → Manage → Settings: see independent “Inject IS_SANDBOX for root” card.
2. Enable → confirm dialog shows workspace name → persists after leave/re-enter.
3. Settings → SSH Servers → Configure: only credential push remains.
4. SSH session as root with flag on: launch keeps skip-permissions + `IS_SANDBOX=1` (same behavior as before when opted in).

- [ ] **Step 4: Final commit only if uncommitted fixups remain**

Otherwise done.

---

## Execution notes

- Do **not** migrate or read `targets.json` `rootSandboxEnvOptIn`.
- Do **not** change `applyRemoteSshLaunchConstraints` / policy enum behavior.
- Prefer one focused commit per task as listed.
