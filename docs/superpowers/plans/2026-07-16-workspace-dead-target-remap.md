# Workspace Dead-Target Remap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users remap a dead runtime target (`ssh:{deletedProfileId}`) on a workspace so folders, member pins, and session snapshots update together and launch works again.

**Architecture:** Pure `WorkspaceTargetRemap.apply` rewrites folders + pins + sessions. `DefaultTargetLiveness` detects dead SSH targets. `SessionRepository.remapWorkspaceTarget` persists workspace then sessions (logical transaction). One dialog drives Folders, Machines, and launch-error affordances; healthy mixed lock stays intact.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, existing `SessionRepository` / `HomeTargetController` / l10n ARBs.

**Spec:** [`docs/superpowers/specs/2026-07-16-workspace-dead-target-remap-design.md`](../specs/2026-07-16-workspace-dead-target-remap-design.md)

---

## File map

| Path | Responsibility |
|------|----------------|
| Create: `client/lib/services/workspace/workspace_target_remap.dart` | Pure `apply` + usage helpers |
| Create: `client/lib/services/workspace/target_liveness.dart` | `TargetLiveness` + `DefaultTargetLiveness` |
| Create: `client/test/services/workspace/workspace_target_remap_test.dart` | Pure transform matrix |
| Create: `client/test/services/workspace/target_liveness_test.dart` | SSH alive/dead |
| Modify: `client/lib/repositories/session_repository.dart` | `remapWorkspaceTarget` |
| Create: `client/test/repositories/session_repository_target_remap_test.dart` | Persist + init flags |
| Create: `client/lib/widgets/workspace/workspace_dead_target_remap_dialog.dart` | Shared dialog + show helper |
| Create: `client/lib/services/workspace/dead_ssh_target_error.dart` | Parse `No SSH profile for target "…"` |
| Modify: `client/lib/widgets/workspace_folders_editor.dart` | Dead badge + Remap on locked groups |
| Modify: `client/lib/pages/home_workspace/workspace/config/workspace_folders_section.dart` | Persist via remap API + reload |
| Modify: `client/lib/pages/home_workspace/workspace/mixed_workspace_member_placement_panel.dart` | Dead host tile + Remap |
| Modify: `client/lib/pages/chat/session_review_compose_card.dart` (+ call sites) | Remap action on matching launchError |
| Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb` | Remap strings |
| Optional: `client/test/widgets/workspace/workspace_dead_target_remap_dialog_test.dart` | Candidate filtering |

**Not in this plan:** path existence checks on destination; auto-suggest by host:user; bulk remap across workspaces; unlocking healthy mixed retargeting.

---

### Task 1: Pure `WorkspaceTargetRemap.apply` (TDD)

**Files:**
- Create: `client/lib/services/workspace/workspace_target_remap.dart`
- Test: `client/test/services/workspace/workspace_target_remap_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/workspace/workspace_target_remap.dart';

void main() {
  test('rewrites folders only', () {
    final result = WorkspaceTargetRemap.apply(
      folders: const [
        WorkspaceFolder(path: '/a', targetId: 'ssh:old'),
        WorkspaceFolder(path: '/b', targetId: 'local'),
      ],
      memberTargetsByTeam: const {},
      sessions: const [],
      fromTargetId: 'ssh:old',
      toTargetId: 'ssh:new',
    );
    expect(result.folders.map((f) => f.targetId), ['ssh:new', 'local']);
    expect(result.sessions, isEmpty);
  });

  test('rewrites pins across teams', () {
    final result = WorkspaceTargetRemap.apply(
      folders: const [WorkspaceFolder(path: '/a', targetId: 'local')],
      memberTargetsByTeam: {
        'team-a': {'lead': 'ssh:old', 'dev': 'local'},
        'team-b': {'lead': 'ssh:old'},
      },
      sessions: const [],
      fromTargetId: 'ssh:old',
      toTargetId: 'ssh:new',
    );
    expect(result.memberTargetsByTeam['team-a'], {
      'lead': 'ssh:new',
      'dev': 'local',
    });
    expect(result.memberTargetsByTeam['team-b'], {'lead': 'ssh:new'});
  });

  test('rewrites session memberTargets and folders; skips unchanged', () {
    final changed = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      folders: const [WorkspaceFolder(path: '/a', targetId: 'ssh:old')],
      memberTargets: const {'lead': 'ssh:old'},
    );
    final untouched = AppSession(
      sessionId: 's2',
      workspaceId: 'w1',
      createdAt: 1,
      folders: const [WorkspaceFolder(path: '/b', targetId: 'local')],
      memberTargets: const {'lead': 'local'},
    );
    final result = WorkspaceTargetRemap.apply(
      folders: const [],
      memberTargetsByTeam: const {},
      sessions: [changed, untouched],
      fromTargetId: 'ssh:old',
      toTargetId: 'ssh:new',
    );
    expect(result.sessions, hasLength(1));
    expect(result.sessions.single.sessionId, 's1');
    expect(result.sessions.single.memberTargets['lead'], 'ssh:new');
    expect(result.sessions.single.folders.single.targetId, 'ssh:new');
  });

  test('from == to is no-op', () {
    final folders = const [
      WorkspaceFolder(path: '/a', targetId: 'ssh:x'),
    ];
    final result = WorkspaceTargetRemap.apply(
      folders: folders,
      memberTargetsByTeam: const {'t': {'m': 'ssh:x'}},
      sessions: const [],
      fromTargetId: 'ssh:x',
      toTargetId: 'ssh:x',
    );
    expect(identical(result.folders, folders) || result.folders == folders, isTrue);
    expect(result.sessions, isEmpty);
  });

  test('usesTarget reports folders ∪ pins ∪ sessions', () {
    expect(
      WorkspaceTargetRemap.usesTarget(
        folders: const [WorkspaceFolder(path: '/a', targetId: 'ssh:old')],
        memberTargetsByTeam: const {},
        sessions: const [],
        targetId: 'ssh:old',
      ),
      isTrue,
    );
    expect(
      WorkspaceTargetRemap.usesTarget(
        folders: const [],
        memberTargetsByTeam: const {'t': {'m': 'ssh:old'}},
        sessions: const [],
        targetId: 'ssh:old',
      ),
      isTrue,
    );
  });
}
```

Adjust `AppSession(...)` constructor args to match the real factory (required fields only — mirror `session_repository_replicas_test.dart`).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/workspace/workspace_target_remap_test.dart`

Expected: FAIL — library / class not found.

- [ ] **Step 3: Implement minimal pure module**

```dart
// client/lib/services/workspace/workspace_target_remap.dart
import '../../models/app_session.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_topology.dart';

class WorkspaceTargetRemapResult {
  const WorkspaceTargetRemapResult({
    required this.folders,
    required this.memberTargetsByTeam,
    required this.sessions,
  });

  final List<WorkspaceFolder> folders;
  final Map<String, MemberTargetAssignments> memberTargetsByTeam;
  final List<AppSession> sessions;
}

abstract final class WorkspaceTargetRemap {
  static bool usesTarget({
    required List<WorkspaceFolder> folders,
    required Map<String, MemberTargetAssignments> memberTargetsByTeam,
    required List<AppSession> sessions,
    required String targetId,
  }) {
    final id = targetId.trim();
    if (id.isEmpty) return false;
    if (folders.any((f) => f.targetId == id)) return true;
    for (final pins in memberTargetsByTeam.values) {
      if (pins.values.any((v) => v == id)) return true;
    }
    for (final s in sessions) {
      if (s.folders.any((f) => f.targetId == id)) return true;
      if (s.memberTargets.values.any((v) => v == id)) return true;
    }
    return false;
  }

  static WorkspaceTargetRemapResult apply({
    required List<WorkspaceFolder> folders,
    required Map<String, MemberTargetAssignments> memberTargetsByTeam,
    required List<AppSession> sessions,
    required String fromTargetId,
    required String toTargetId,
  }) {
    final from = fromTargetId.trim();
    final to = toTargetId.trim();
    if (from.isEmpty || to.isEmpty) {
      throw ArgumentError('fromTargetId and toTargetId must be non-empty');
    }
    if (from == to) {
      return WorkspaceTargetRemapResult(
        folders: folders,
        memberTargetsByTeam: memberTargetsByTeam,
        sessions: const [],
      );
    }

    final nextFolders = [
      for (final f in folders)
        f.targetId == from ? f.copyWith(targetId: to) : f,
    ];

    final nextPins = <String, MemberTargetAssignments>{};
    for (final e in memberTargetsByTeam.entries) {
      nextPins[e.key] = {
        for (final p in e.value.entries)
          p.key: p.value == from ? to : p.value,
      };
    }

    final changedSessions = <AppSession>[];
    for (final s in sessions) {
      final folderHit = s.folders.any((f) => f.targetId == from);
      final pinHit = s.memberTargets.values.any((v) => v == from);
      if (!folderHit && !pinHit) continue;
      changedSessions.add(
        s.copyWith(
          folders: [
            for (final f in s.folders)
              f.targetId == from ? f.copyWith(targetId: to) : f,
          ],
          memberTargets: {
            for (final p in s.memberTargets.entries)
              p.key: p.value == from ? to : p.value,
          },
        ),
      );
    }

    return WorkspaceTargetRemapResult(
      folders: nextFolders,
      memberTargetsByTeam: nextPins,
      sessions: changedSessions,
    );
  }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/services/workspace/workspace_target_remap_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/workspace/workspace_target_remap.dart \
  client/test/services/workspace/workspace_target_remap_test.dart
git commit -m "feat(workspace): pure dead-target remap transform"
```

---

### Task 2: `TargetLiveness` (TDD)

**Files:**
- Create: `client/lib/services/workspace/target_liveness.dart`
- Test: `client/test/services/workspace/target_liveness_test.dart`

- [ ] **Step 1: Write failing tests**

Use a temp `SshProfileRepository(rootDir: tmp.path)` with one profile saved; assert `ssh:missing` dead, `ssh:present` alive, `local` alive, unknown `wsl:Ubuntu` alive (YAGNI probe — treat as alive).

```dart
test('ssh missing profile is dead', () async {
  final tmp = await Directory.systemTemp.createTemp('liveness_');
  addTearDown(() => tmp.deleteSync(recursive: true));
  final ssh = SshProfileRepository(rootDir: tmp.path);
  final liveness = DefaultTargetLiveness(sshProfiles: ssh);
  expect(await liveness.isAlive('ssh:gone'), isFalse);
});

test('ssh present profile is alive', () async {
  // save one SshProfile(id: 'p1', ...) then:
  expect(await liveness.isAlive('ssh:p1'), isTrue);
});

test('local is always alive', () async {
  expect(await liveness.isAlive('local'), isTrue);
});
```

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client && flutter test test/services/workspace/target_liveness_test.dart`

- [ ] **Step 3: Implement**

```dart
// client/lib/services/workspace/target_liveness.dart
import '../../models/runtime_target.dart';
import '../../repositories/ssh_profile_repository.dart';

abstract class TargetLiveness {
  Future<bool> isAlive(String targetId);
}

class DefaultTargetLiveness implements TargetLiveness {
  DefaultTargetLiveness({required SshProfileRepository sshProfiles})
    : _sshProfiles = sshProfiles;

  final SshProfileRepository _sshProfiles;

  @override
  Future<bool> isAlive(String targetId) async {
    final id = targetId.trim();
    if (id.isEmpty) return false;
    switch (runtimeKindOfId(id)) {
      case RuntimeKind.local:
        return true;
      case RuntimeKind.wsl:
        // Future: probe distro list; until then assume alive if well-formed.
        return wslDistroOfId(id)?.isNotEmpty == true;
      case RuntimeKind.ssh:
        final profileId = sshProfileIdOfId(id);
        if (profileId == null || profileId.isEmpty) return false;
        return (await _sshProfiles.findById(profileId)) != null;
    }
  }
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/workspace/target_liveness.dart \
  client/test/services/workspace/target_liveness_test.dart
git commit -m "feat(workspace): target liveness for dead SSH profiles"
```

---

### Task 3: `SessionRepository.remapWorkspaceTarget` (TDD)

**Files:**
- Modify: `client/lib/repositories/session_repository.dart`
- Test: `client/test/repositories/session_repository_target_remap_test.dart`

- [ ] **Step 1: Write failing repository test**

Pattern from `session_repository_folders_test.dart` / `session_repository_replicas_test.dart`:

1. `createWorkspace` with folders on `ssh:old` + `local`.
2. `updateWorkspaceMemberPlacement` pinning a member to `ssh:old`; confirm init flag true.
3. `createSession` (or write session with `memberTargets` / folders containing `ssh:old`).
4. Call `remapWorkspaceTarget(..., from: ssh:old, to: ssh:new, liveness: AlwaysAlive())`.
5. Assert:
   - folders `ssh:old` → `ssh:new`
   - `memberTargetsByTeam` rewritten
   - `memberPlacementInitializedByTeam` **unchanged** (still true)
   - session folders + `memberTargets` rewritten
6. Extra cases: `from` unused → throws; `to` dead via stub liveness → throws before write.

Stub:

```dart
class _FixedLiveness implements TargetLiveness {
  _FixedLiveness(this._alive);
  final Set<String> _alive;
  @override
  Future<bool> isAlive(String targetId) async => _alive.contains(targetId);
}
```

- [ ] **Step 2: Run — expect FAIL** (method missing)

Run: `cd client && flutter test test/repositories/session_repository_target_remap_test.dart`

- [ ] **Step 3: Implement repository method**

Add after `updateWorkspaceMemberPlacement` block (~line 555):

```dart
Future<Workspace> remapWorkspaceTarget(
  String workspaceId, {
  required String fromTargetId,
  required String toTargetId,
  required TargetLiveness liveness,
}) async {
  final from = fromTargetId.trim();
  final to = toTargetId.trim();
  if (from.isEmpty || to.isEmpty) {
    throw ArgumentError('fromTargetId and toTargetId must be non-empty');
  }
  final fs = await _fs();
  final existing = await _readManifest(fs, workspaceId);
  if (existing == null) {
    throw StateError('Workspace "$workspaceId" not found');
  }
  final sessions = await loadSessionsForWorkspace(workspaceId);
  if (!WorkspaceTargetRemap.usesTarget(
    folders: existing.folders,
    memberTargetsByTeam: existing.memberTargetsByTeam,
    sessions: sessions,
    targetId: from,
  )) {
    throw StateError('Nothing to remap for target "$from"');
  }
  if (from != to && !await liveness.isAlive(to)) {
    throw StateError('Destination target "$to" is not available');
  }

  final applied = WorkspaceTargetRemap.apply(
    folders: existing.folders,
    memberTargetsByTeam: existing.memberTargetsByTeam,
    sessions: sessions,
    fromTargetId: from,
    toTargetId: to,
  );
  final now = DateTime.now().millisecondsSinceEpoch;
  final updated = existing.copyWith(
    folders: applied.folders,
    memberTargetsByTeam: applied.memberTargetsByTeam,
    // Keep placement init flags — pin keys unchanged, only host ids.
    updatedAt: now,
  );
  await _writeManifest(fs, updated);
  await _provisionWorkspaceTrust(fs, updated);

  for (final session in applied.sessions) {
    try {
      await _writeSession(fs, session.copyWith(updatedAt: now));
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[workspace] remap session write failed '
        'workspace=$workspaceId session=${session.sessionId}',
        error: error,
        stackTrace: stackTrace,
      );
      // Best-effort: workspace already rewritten; surface via rethrow after loop
      // or collect failures — prefer rethrow first failure after logging.
      rethrow;
    }
  }
  return updated;
}
```

Import `workspace_target_remap.dart` and `target_liveness.dart`.

**Do not** call `updateWorkspaceFolders` (it clears placement init when target set changes).

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/session_repository.dart \
  client/test/repositories/session_repository_target_remap_test.dart
git commit -m "feat(workspace): persist dead-target remap in SessionRepository"
```

---

### Task 4: l10n strings

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`

- [ ] **Step 1: Add keys** (near existing `workspaceFolders*` keys)

| Key | EN | ZH |
|-----|----|----|
| `workspaceDeadTargetBadge` | Missing machine | 机器不可用 |
| `workspaceDeadTargetRemap` | Remap… | 重新映射… |
| `workspaceDeadTargetRemapTitle` | Remap machine | 重新映射机器 |
| `workspaceDeadTargetRemapBody` | Replace {from} with another machine. Directory paths are not changed — they must already exist on the destination. | 将 {from} 替换为另一台机器。目录路径不会改动，目标机器上必须已有相同路径。 |
| `workspaceDeadTargetRemapPickFrom` | Dead machine | 失效机器 |
| `workspaceDeadTargetRemapPickTo` | Replacement machine | 替换为 |
| `workspaceDeadTargetRemapConfirm` | Remap | 重新映射 |
| `workspaceDeadTargetRemapNothing` | Nothing to remap. | 没有可映射的目标。 |
| `workspaceDeadTargetRemapFailed` | Could not remap machine. | 无法重新映射机器。 |
| `workspaceDeadTargetRemapFromLaunch` | Remap machine… | 重新映射机器… |

- [ ] **Step 2: Regenerate artifacts**

Flutter gen-l10n runs on build — do not hand-edit `app_localizations*.dart`. After ARB edits, run:

`cd client && dart run tool/gen_warmup_glyphs.dart`

- [ ] **Step 3: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb
git commit -m "l10n: dead-target remap strings"
```

---

### Task 5: Shared remap dialog + error parse helper

**Files:**
- Create: `client/lib/widgets/workspace/workspace_dead_target_remap_dialog.dart`
- Create: `client/lib/services/workspace/dead_ssh_target_error.dart`
- Test (optional but preferred): `client/test/services/workspace/dead_ssh_target_error_test.dart`

- [ ] **Step 1: Error parse helper (TDD)**

```dart
/// Returns `ssh:…` when [message] matches provision/connect missing-profile text.
String? deadSshTargetIdFromError(String? message) {
  if (message == null) return null;
  final match = RegExp(
    r'No SSH profile for target "(ssh:[^"]+)"',
  ).firstMatch(message);
  return match?.group(1);
}
```

Test with exact string from `workspace_provisioner.dart` / `remote_cli_readiness.dart`.

- [ ] **Step 2: Dialog API**

```dart
/// Returns selected `toTargetId`, or null if cancelled.
/// When [fromTargetId] is null, user picks among [deadTargetIds] first.
Future<String?> showWorkspaceDeadTargetRemapDialog({
  required BuildContext context,
  required String? fromTargetId,
  required List<String> deadTargetIds,
  required List<RuntimeTarget> selectable,
  required TargetLiveness liveness,
}) async { … }
```

Candidate filter for `to`:

- Include only targets where `await liveness.isAlive(t.id)`
- Exclude `fromTargetId`
- Prefer `HomeTargetController.listSelectable()` results passed in by caller

UI: `AlertDialog` / `Tp`-styled dialog with dropdown(s) + Confirm using l10n keys from Task 4. Warn paths unchanged in body.

- [ ] **Step 3: Commit**

```bash
git add client/lib/widgets/workspace/workspace_dead_target_remap_dialog.dart \
  client/lib/services/workspace/dead_ssh_target_error.dart \
  client/test/services/workspace/dead_ssh_target_error_test.dart
git commit -m "feat(workspace): dead-target remap dialog and error parse"
```

---

### Task 6: Wire Folders section + editor

**Files:**
- Modify: `client/lib/widgets/workspace_folders_editor.dart`
- Modify: `client/lib/pages/home_workspace/workspace/config/workspace_folders_section.dart`

- [ ] **Step 1: Extend editor**

Add optional callbacks / flags:

```dart
final Set<String> deadTargetIds; // default {}
final ValueChanged<String>? onRemapDeadTarget; // fromTargetId
```

On `_MachineFolderCard` when `deadTargetIds.contains(targetId)`:

- Show error-colored badge with `workspaceDeadTargetBadge`
- Show text button `workspaceDeadTargetRemap` calling `onRemapDeadTarget!(targetId)`
- Keep `allowRowTargetChange: false` when mixed-locked — Remap is **separate** from row target picker

- [ ] **Step 2: Section orchestrates remap**

In `WorkspaceFoldersSection`:

1. Resolve `DefaultTargetLiveness(sshProfiles: context.read<SshProfileRepository>())`.
2. Compute dead ids among `workspaceTargetIds(live.folders)` (async; cache in state).
3. Pass into editor.
4. `onRemapDeadTarget`:
   - `listSelectable()` → dialog → `repo.remapWorkspaceTarget`
   - `chat.invalidateWorkspaceProvision(updated)`
   - `await chat.loadWorkspaceData(repo)`
   - Best-effort dispose of old context: `RuntimeContextRegistry` is **not** currently a `context.read` provider — pass it from `AppShell` / bootstrap if convenient, or skip dispose (safe; cache will miss after reload). Never fail the remap UX on dispose.
   - On error: toast / snackbar with `workspaceDeadTargetRemapFailed`

Confirm `SshProfileRepository` is provided (`RepositoryProvider` in `main.dart`).

- [ ] **Step 3: Manual smoke** (or widget test if cheap): mixed workspace with fake dead id shows Remap; healthy mixed still cannot change row targets.

- [ ] **Step 4: Commit**

```bash
git add client/lib/widgets/workspace_folders_editor.dart \
  client/lib/pages/home_workspace/workspace/config/workspace_folders_section.dart
git commit -m "feat(workspace): remap dead folder hosts from Folders UI"
```

---

### Task 7: Wire Machines panel

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/mixed_workspace_member_placement_panel.dart`

- [ ] **Step 1: Mark dead hosts in left list**

For each `targetId` in `workspaceTargetIds`, if dead:

- Suffix / chip with `workspaceDeadTargetBadge`
- Trailing `TextButton` / menu → same `showWorkspaceDeadTargetRemapDialog` → `SessionRepository.remapWorkspaceTarget` → reload workspace (callback `onWorkspaceChanged` or `ChatCubit.loadWorkspaceData` like Folders)

Keep placement increment/decrement behavior unchanged for live hosts. Selecting a dead host still shows placement counts (read-only remapping is separate).

- [ ] **Step 2: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/mixed_workspace_member_placement_panel.dart
git commit -m "feat(workspace): remap dead hosts from Machines panel"
```

---

### Task 8: Launch-error Remap affordance

**Files:**
- Modify: `client/lib/pages/chat/session_review_compose_card.dart`
- Modify callers that pass `launchError` (`chat_workbench.dart` / landing compose) to also pass `Workspace?` + remap callback **or** handle remap inside the card via `context.read`

Preferred minimal approach:

1. Add optional `VoidCallback? onRemapDeadTarget` / `String? deadTargetIdFromLaunchError`.
2. In error banner `Column`/`Row`: if `deadSshTargetIdFromError(launchError) != null`, show `TextButton` labeled `workspaceDeadTargetRemapFromLaunch`.
3. Parent (`chat_workbench` / landing) implements: open dialog with that `from`, call repo, invalidate + reload, clear launch error.

Keep parsing in `dead_ssh_target_error.dart` — do not duplicate regex in UI.

- [ ] **Step 1: Implement banner action + parent handler**

- [ ] **Step 2: Quick test for parse helper already covers string; optional widget pump for button visibility**

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/chat/session_review_compose_card.dart \
  client/lib/pages/chat_workbench.dart \
  # (+ any landing compose file touched)
git commit -m "feat(workspace): offer remap from missing SSH profile launch errors"
```

---

### Task 9: Verification

- [ ] **Step 1: Analyze + unit tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test \
  test/services/workspace/workspace_target_remap_test.dart \
  test/services/workspace/target_liveness_test.dart \
  test/services/workspace/dead_ssh_target_error_test.dart \
  test/repositories/session_repository_target_remap_test.dart
```

Expected: no errors; all listed tests PASS.

- [ ] **Step 2: Manual checklist**

1. Mixed workspace with folders on `ssh:deleted` → Folders shows badge + Remap → pick live SSH → launch succeeds.
2. Healthy mixed workspace → still cannot change folder row targets.
3. Machines panel shows dead chip + Remap.
4. Delete profile, try connect → launch error shows Remap action.

- [ ] **Step 3: Final commit only if Step 1 left dirty fixes**

---

## Execution notes

- Prefer **not** changing `updateWorkspaceFolders` behavior.
- Merging onto an existing workspace host id is **allowed** (two folder groups → one `targetId`).
- After remap, always `invalidateWorkspaceProvision` + `loadWorkspaceData`.
- `RuntimeContextRegistry.dispose(from)` is best-effort; never block remap success on dispose failure.
