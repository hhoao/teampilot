# Workspace Machine Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users add machines and directories to an already-created workspace of any topology (local / project-remote / mixed) from workspace manage → Settings, and move folders between machines.

**Architecture:** Unlock the existing `WorkspaceFoldersEditor` (drop the hardcoded `lockTargets: true` in `WorkspaceInfoSection` and the mixed-topology lock inside the editor), restore the removed "Add on another machine" + per-group "Change" affordances, and strengthen `SessionRepository.updateWorkspaceFolders` so member placement is reset whenever a mixed workspace's folders change.

**Tech Stack:** Flutter (Material), flutter_bloc, `client/lib/` package `teampilot`. Tests: `flutter_test` widget tests + repo unit tests.

## Global Constraints

- All l10n keys used by the restored UI already exist — do **not** add new keys; only the `workspaceFoldersMixedTargetsLockedHint` key is removed (Task 4).
- Machine switching never moves/copies files: it only re-associates `WorkspaceFolder.targetId`. The directory path must already exist on the destination machine (existing UI copy already communicates this; no confirmation dialog).
- Mixed workspaces keep the member→machine assignment flow: any folder change in a mixed workspace resets `memberPlacementInitializedByTeam`, surfacing the existing "Confirm machine assignment" banner.
- Editor file: `client/lib/widgets/workspace_folders_editor.dart`. Section: `client/lib/pages/home_workspace/workspace/config/workspace_folders_section.dart`. Settings body: `client/lib/pages/home_workspace/workspace/workspace_info_section.dart`. Repo: `client/lib/repositories/session_repository.dart`.
- Run tests from `client/`. Full gate: `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`.

---

### Task 1: Reset member placement on any mixed folder change

**Files:**
- Modify: `client/lib/repositories/session_repository.dart:473-497`
- Test: `client/test/repositories/session_repository_folders_test.dart`

**Interfaces:**
- Consumes: existing `Workspace`, `WorkspaceFolder`, `WorkspaceTopology`, `listEquals` (already imported at session_repository.dart:4).
- Produces: `SessionRepository.updateWorkspaceFolders` now also resets `memberPlacementInitializedByTeam` when the workspace is mixed before or after the change and the folder list actually changed.

- [ ] **Step 1: Write the failing test**

Append to `client/test/repositories/session_repository_folders_test.dart`:

```dart
  test(
    'updateWorkspaceFolders resets init flags when mixed folders move between present machines',
    () async {
      final tmp = await Directory.systemTemp.createTemp('fs_repo_folders_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);

      final ws = await repo.createWorkspace([
        const WorkspaceFolder(path: '/local'),
        const WorkspaceFolder(path: '/a', targetId: 'ssh:p1'),
        const WorkspaceFolder(path: '/b', targetId: 'ssh:p2'),
      ]);
      await repo.updateWorkspaceMemberPlacement(
        ws.workspaceId,
        'team-a',
        targets: const {'team-lead': 'local'},
      );
      expect(
        (await repo.loadWorkspaces())
            .single
            .memberPlacementInitializedByTeam['team-a'],
        isTrue,
      );

      // Move /a from ssh:p1 to ssh:p2: target set {local, ssh:p1, ssh:p2}
      // unchanged, topology stays mixed — only the new rule resets placement.
      await repo.updateWorkspaceFolders(ws.workspaceId, [
        const WorkspaceFolder(path: '/local'),
        const WorkspaceFolder(path: '/a', targetId: 'ssh:p2'),
        const WorkspaceFolder(path: '/b', targetId: 'ssh:p2'),
      ]);

      final reloaded = (await repo.loadWorkspaces()).single;
      expect(reloaded.memberPlacementInitializedByTeam['team-a'], isFalse);
    },
  );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories/session_repository_folders_test.dart -n "resets init flags when mixed folders move between present machines"`

Expected: FAIL — the flag stays `true` (target set and topology are unchanged, so the existing reset conditions don't fire).

- [ ] **Step 3: Implement the reset rule**

In `client/lib/repositories/session_repository.dart`, replace the block at lines 484-489:

```dart
    final nextInitialized = (becameMixed || targetSetChanged)
        ? <String, bool>{
            for (final teamId in existing.memberTargetsByTeam.keys)
              if (teamId.trim().isNotEmpty) teamId.trim(): false,
          }
        : existing.memberPlacementInitializedByTeam;
```

with:

```dart
    final foldersChanged = !listEquals(nextFolders, existing.folders);
    final mixedInvolved =
        previousTopology == WorkspaceTopology.mixed ||
        nextTopology == WorkspaceTopology.mixed;
    final nextInitialized =
        (becameMixed || targetSetChanged || (foldersChanged && mixedInvolved))
        ? <String, bool>{
            for (final teamId in existing.memberTargetsByTeam.keys)
              if (teamId.trim().isNotEmpty) teamId.trim(): false,
          }
        : existing.memberPlacementInitializedByTeam;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories/session_repository_folders_test.dart`

Expected: all tests in the file PASS (existing ones included).

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/session_repository.dart client/test/repositories/session_repository_folders_test.dart
git commit -m "fix(session): reset member placement on any mixed folder change"
```

---

### Task 2: Restore machine-editing affordances in the folders editor

**Files:**
- Modify: `client/lib/widgets/workspace_folders_editor.dart`
- Test: `client/test/widgets/workspace_folders_editor_test.dart` (create)

**Interfaces:**
- Consumes: `workspaceTargetIds` from `../models/workspace_topology.dart` (already imported), `RuntimeTarget`, `WorkspaceFolder`, `HomeTargetController.listSelectable()`, l10n keys `workspaceFoldersChangeTarget`, `workspaceFoldersAddOnAnotherMachine`, `workspaceFoldersPickTarget` (all exist).
- Produces: `_WorkspaceFoldersEditorState` with:
  - `_targetsLocked` getter = `widget.lockTargets` only (mixed no longer locks).
  - `_unusedTargetCandidates(List<RuntimeTarget> targets)` → `List<RuntimeTarget>`.
  - `_addFolderOnAnotherMachine()` → Future<void>.
  - `_setTargetForGroup(String targetId, String newTargetId)` and `_pickTargetForGroup(String targetId)` → Future<void>.
  - `_MachineFolderCard` gains `required this.targetEditable` (bool) and `required this.onPickTargetForGroup` (VoidCallback).

- [ ] **Step 1: Write the failing widget test**

Create `client/test/widgets/workspace_folders_editor_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';
import 'package:teampilot/widgets/workspace_folders_editor.dart';

import '../support/in_memory_filesystem.dart';

Future<HomeTargetController> _controllerWithSshProfiles(
  List<SshProfile> profiles,
) async {
  const root = '/tp-test-editor';
  final sshRepo = SshProfileRepository(rootDir: root, fs: InMemoryFilesystem());
  for (final p in profiles) {
    await sshRepo.save(p);
  }
  return HomeTargetController(
    registry: RuntimeTargetRegistry(
      repo: TargetsRepository(rootDir: root, fs: InMemoryFilesystem()),
      sshProfileRepo: sshRepo,
      isWindows: false,
      isAndroid: false,
    ),
    current: RuntimeTarget.local,
    switchTo: (_) async {},
  );
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required HomeTargetController controller,
  required List<WorkspaceFolder> folders,
  bool lockTargets = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RepositoryProvider<HomeTargetController>.value(
        value: controller,
        child: Scaffold(
          body: WorkspaceFoldersEditor(
            folders: folders,
            lockTargets: lockTargets,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await tester.pump();
}

void main() {
  final serverA = SshProfile(
    id: 'p1',
    name: 'Server A',
    host: '10.0.0.1',
    username: 'root',
  );
  final serverB = SshProfile(
    id: 'p2',
    name: 'Server B',
    host: '10.0.0.2',
    username: 'root',
  );

  testWidgets(
    'locked editor hides Change and Add-on-another-machine',
    (tester) async {
      final controller = await _controllerWithSshProfiles([serverA, serverB]);
      await _pumpEditor(
        tester,
        controller: controller,
        folders: const [WorkspaceFolder(path: '/proj')],
        lockTargets: true,
      );

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.text(l10n.workspaceFoldersChangeTarget),
        findsNothing,
      );
      expect(
        find.text(l10n.workspaceFoldersAddOnAnotherMachine),
        findsNothing,
      );
    },
  );

  testWidgets(
    'unlocked editor shows Change; group picker lists all machines',
    (tester) async {
      final controller = await _controllerWithSshProfiles([serverA, serverB]);
      await _pumpEditor(
        tester,
        controller: controller,
        folders: const [WorkspaceFolder(path: '/proj')],
      );

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.workspaceFoldersChangeTarget), findsOneWidget);

      await tester.tap(find.text(l10n.workspaceFoldersChangeTarget));
      await tester.pumpAndSettle();
      expect(find.text(l10n.workspaceFoldersPickTarget), findsOneWidget);
      expect(find.text('This device'), findsOneWidget);
      expect(find.text('Server A'), findsOneWidget);
      expect(find.text('Server B'), findsOneWidget);
    },
  );

  testWidgets(
    'Add on another machine picker lists unused machines only',
    (tester) async {
      final controller = await _controllerWithSshProfiles([serverA, serverB]);
      await _pumpEditor(
        tester,
        controller: controller,
        folders: const [WorkspaceFolder(path: '/proj')],
      );

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.workspaceFoldersAddOnAnotherMachine));
      await tester.pumpAndSettle();
      expect(find.text('Server A'), findsOneWidget);
      expect(find.text('Server B'), findsOneWidget);
      // 'This device' is already used by /proj, so it is not a candidate.
      expect(find.text('This device'), findsNothing);
    },
  );

  testWidgets('mixed workspace is not locked', (tester) async {
    final controller = await _controllerWithSshProfiles([serverA, serverB]);
    await _pumpEditor(
      tester,
      controller: controller,
      folders: const [
        WorkspaceFolder(path: '/local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ],
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.workspaceFoldersChangeTarget), findsNWidgets(2));
    expect(
      find.text(l10n.workspaceFoldersAddOnAnotherMachine),
      findsOneWidget,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/workspace_folders_editor_test.dart`

Expected: FAIL — `workspaceFoldersChangeTarget` / `workspaceFoldersAddOnAnotherMachine` text never appears (removed affordances + mixed still locked).

- [ ] **Step 3: Remove the mixed lock**

In `client/lib/widgets/workspace_folders_editor.dart`:

Replace `_targetsLocked` (currently lines 232-234):

```dart
  bool get _targetsLocked =>
      widget.lockTargets ||
      workspaceTopologyOf(_folders) == WorkspaceTopology.mixed;
```

with:

```dart
  bool get _targetsLocked => widget.lockTargets;
```

In `build`, replace `allowRowTargetChange` (currently lines 288-291):

```dart
                    allowRowTargetChange:
                        !lockTargets &&
                        workspaceTopologyOf(_folders) !=
                            WorkspaceTopology.mixed,
```

with:

```dart
                    allowRowTargetChange: !lockTargets,
```

- [ ] **Step 4: Restore group-level machine switch**

In `client/lib/widgets/workspace_folders_editor.dart`, add right after `_pickTargetForRow` (after line 182):

```dart
  void _setTargetForGroup(String targetId, String newTargetId) {
    if (!widget.enabled || _targetsLocked || targetId == newTargetId) return;
    _emit([
      for (final f in _folders)
        f.targetId == targetId ? f.copyWith(targetId: newTargetId) : f,
    ]);
  }

  Future<void> _pickTargetForGroup(String targetId) async {
    if (!widget.enabled || _targetsLocked) return;
    final chosen = await _pickTargetDialog(current: targetId);
    if (chosen != null) {
      _setTargetForGroup(targetId, chosen);
    }
  }
```

Add after `_addFolderOnTarget` (after line 230):

```dart
  List<RuntimeTarget> _unusedTargetCandidates(List<RuntimeTarget> targets) {
    final used = workspaceTargetIds(_folders).toSet();
    return targets.where((t) => !used.contains(t.id)).toList(growable: false);
  }

  Future<void> _addFolderOnAnotherMachine() async {
    if (!widget.enabled || _targetsLocked) return;
    final targets = await (_targets ?? _loadTargets());
    if (!mounted) return;
    final candidates = _unusedTargetCandidates(targets);
    if (candidates.isEmpty) return;
    final chosen = candidates.length == 1
        ? candidates.first
        : await showDialog<RuntimeTarget>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: Text(context.l10n.workspaceFoldersPickTarget),
              children: [
                for (final t in candidates)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, t),
                    child: Row(
                      children: [
                        Icon(
                          t.kind == RuntimeKind.ssh
                              ? Icons.cloud_outlined
                              : Icons.computer_outlined,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(t.label)),
                      ],
                    ),
                  ),
              ],
            ),
          );
    if (chosen == null || !mounted) return;
    await _addFolderOnTarget(chosen.id);
  }
```

- [ ] **Step 5: Add the toolbar row and wire the machine card**

In `build`, insert the toolbar as the first child of the `Column` (before the `if (!hasDirectory && groups.length == 1)` at line 252):

```dart
            if (widget.enabled &&
                !lockTargets &&
                _unusedTargetCandidates(targets).isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _addFolderOnAnotherMachine,
                  icon: Icon(
                    Icons.add_circle_outline,
                    size: context.tpIconSizes.md,
                  ),
                  label: Text(l10n.workspaceFoldersAddOnAnotherMachine),
                ),
              ),
              const SizedBox(height: 12),
            ],
```

In the first `_MachineFolderCard(...)` call site (the `groups.length == 1` branch at lines 253-273), add before the `onAddDirectory` line:

```dart
                    targetEditable: !lockTargets,
                    onPickTargetForGroup: () =>
                        _pickTargetForGroup(groups.first.targetId),
```

In the second `_MachineFolderCard(...)` call site (the `for (final group in groups)` branch at lines 275-301), add before the `onAddDirectory` line:

```dart
                    targetEditable: !lockTargets,
                    onPickTargetForGroup: () =>
                        _pickTargetForGroup(group.targetId),
```

- [ ] **Step 6: Extend `_MachineFolderCard`**

In `_MachineFolderCard`:

- Constructor: add `required this.targetEditable` and `required this.onPickTargetForGroup`.
- Fields:

```dart
  final bool targetEditable;
  final VoidCallback onPickTargetForGroup;
```

- In `build`, insert between the `Expanded(child: Text(targetLabel, ...))` and the `if (isDead)` block:

```dart
                if (targetEditable && enabled)
                  TextButton(
                    onPressed: onPickTargetForGroup,
                    child: Text(l10n.workspaceFoldersChangeTarget),
                  ),
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `flutter test test/widgets/workspace_folders_editor_test.dart`

Expected: all 4 tests PASS.

- [ ] **Step 8: Commit**

```bash
git add client/lib/widgets/workspace_folders_editor.dart client/test/widgets/workspace_folders_editor_test.dart
git commit -m "feat(workspace): restore machine editing in folders editor"
```

---

### Task 3: Unlock machine editing in workspace settings

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_info_section.dart:100`
- Test: `client/test/pages/home_workspace/workspace/workspace_info_section_target_test.dart`

**Interfaces:**
- Consumes: `WorkspaceFoldersSection` (unchanged API — `lockTargets` param).
- Produces: workspace manage → Settings renders the folders editor with `lockTargets: false`, so the restored machine affordances are live for every workspace topology.

- [ ] **Step 1: Write the failing test**

In `client/test/pages/home_workspace/workspace/workspace_info_section_target_test.dart`, extend the existing test body. Inside the `runAsync` block, right after `final sshRepo = SshProfileRepository(rootDir: tmp.path, fs: fs);`, add a saved profile:

```dart
      await sshRepo.save(
        const SshProfile(
          id: 'p1',
          name: 'Server A',
          host: '10.0.0.1',
          username: 'root',
        ),
      );
```

Add imports at the top of the file (alphabetical): `package:teampilot/models/ssh_profile.dart`.

After the existing `expect(find.text(l10n.rootSandboxEnvOptInTitle), findsOneWidget);`, add:

```dart
      expect(find.text(l10n.workspaceFoldersAddOnAnotherMachine), findsOneWidget);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/pages/home_workspace/workspace/workspace_info_section_target_test.dart`

Expected: FAIL — `workspaceFoldersAddOnAnotherMachine` text not found while `lockTargets: true` hides the toolbar.

- [ ] **Step 3: Unlock**

In `client/lib/pages/home_workspace/workspace/workspace_info_section.dart:100`:

```dart
          WorkspaceFoldersSection(workspace: live, lockTargets: true),
```

→

```dart
          WorkspaceFoldersSection(workspace: live, lockTargets: false),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/pages/home_workspace/workspace/workspace_info_section_target_test.dart`

Expected: PASS.

- [ ] **Step 5: Run the folders section tests**

Run: `flutter test test/pages/home_workspace/workspace/workspace_folders_section_test.dart`

Expected: PASS (it uses an empty SSH catalog, so no toolbar appears and its assertions are unaffected).

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_info_section.dart client/test/pages/home_workspace/workspace/workspace_info_section_target_test.dart
git commit -m "feat(workspace): unlock machine editing in workspace settings"
```

---

### Task 4: Drop the mixed-lock hint and its l10n key

**Files:**
- Modify: `client/lib/widgets/workspace_folders_editor.dart:17-30`
- Modify: `client/lib/pages/home_workspace/workspace/config/workspace_folders_section.dart:166-170`
- Modify: `client/lib/l10n/app_en.arb:1232`, `client/lib/l10n/app_zh.arb:1162`
- Modify: `client/lib/l10n/app_localizations.dart:5147-5152`, `client/lib/l10n/app_localizations_en.dart:2842-2844`, `client/lib/l10n/app_localizations_zh.dart:2715-2717`

**Interfaces:**
- Consumes: existing l10n keys `workspaceFoldersEditorHint` and `workspaceFoldersPersonalTargetsLockedHint`.
- Produces: `workspaceFoldersEditorHint(AppLocalizations l10n, {required bool lockTargets})` — the `folders` parameter is removed. Key `workspaceFoldersMixedTargetsLockedHint` is removed everywhere.

- [ ] **Step 1: Verify the key has no remaining usages**

Run: `rg -n "workspaceFoldersMixedTargetsLockedHint" client/lib client/test`

Expected: matches only in `client/lib/l10n/app_en.arb`, `app_zh.arb`, `app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_zh.dart`, and the hint function in `workspace_folders_editor.dart` (about to change).

- [ ] **Step 2: Remove the mixed branch from the hint**

In `client/lib/widgets/workspace_folders_editor.dart`, replace `workspaceFoldersEditorHint` (lines 17-30):

```dart
String workspaceFoldersEditorHint(
  AppLocalizations l10n,
  List<WorkspaceFolder> folders, {
  required bool lockTargets,
}) {
  final topology = workspaceTopologyOf(folders);
  if (topology == WorkspaceTopology.mixed) {
    return l10n.workspaceFoldersMixedTargetsLockedHint;
  }
  if (lockTargets) {
    return l10n.workspaceFoldersPersonalTargetsLockedHint;
  }
  return l10n.workspaceFoldersEditorHint;
}
```

with:

```dart
String workspaceFoldersEditorHint(
  AppLocalizations l10n, {
  required bool lockTargets,
}) {
  if (lockTargets) {
    return l10n.workspaceFoldersPersonalTargetsLockedHint;
  }
  return l10n.workspaceFoldersEditorHint;
}
```

- [ ] **Step 3: Update the call site**

In `client/lib/pages/home_workspace/workspace/config/workspace_folders_section.dart:166`:

```dart
            subtitle: workspaceFoldersEditorHint(
              l10n,
              live.folders,
              lockTargets: widget.lockTargets,
            ),
```

→

```dart
            subtitle: workspaceFoldersEditorHint(
              l10n,
              lockTargets: widget.lockTargets,
            ),
```

- [ ] **Step 4: Remove the l10n key**

Remove the `workspaceFoldersMixedTargetsLockedHint` entry from all five files:

- `client/lib/l10n/app_en.arb:1232` — the whole `"workspaceFoldersMixedTargetsLockedHint": "..."` line plus its trailing comma.
- `client/lib/l10n/app_zh.arb:1162` — the whole `"workspaceFoldersMixedTargetsLockedHint": "..."` line plus its trailing comma.
- `client/lib/l10n/app_localizations.dart` — the doc comment block (`/// No description provided for @workspaceFoldersMixedTargetsLockedHint.` … `///` … `/// In en, this message translates to:` … `///` … `/// **'Mixed workspace: folder machines are fixed…'**`) and the `String get workspaceFoldersMixedTargetsLockedHint;` line.
- `client/lib/l10n/app_localizations_en.dart` — the getter block:

```dart
  String get workspaceFoldersMixedTargetsLockedHint =>
      'Mixed workspace: folder machines are fixed. Add paths on existing machines above; use Assign to change member machine assignment.';
```

- `client/lib/l10n/app_localizations_zh.dart` — the getter block:

```dart
  String get workspaceFoldersMixedTargetsLockedHint =>
      '混合工作区：各目录所在机器已固定。可在上方现有机器上添加路径；成员分配请使用下方「分配」按钮。';
```

- [ ] **Step 5: Verify no stale references and run analyze**

Run: `rg -n "workspaceFoldersMixedTargetsLockedHint" client/`

Expected: no matches.

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no errors introduced.

- [ ] **Step 6: Commit**

```bash
git add client/lib/widgets/workspace_folders_editor.dart client/lib/pages/home_workspace/workspace/config/workspace_folders_section.dart client/lib/l10n/
git commit -m "refactor(workspace): drop mixed-lock hint text and l10n key"
```

---

### Task 5: Remove orphaned settings view + details dialog and run the full gate

**Files:**
- Delete: `client/lib/pages/home_workspace/workspace/workspace_settings_view.dart`
- Delete: `client/lib/widgets/workspace_details_dialog.dart`

**Interfaces:**
- Consumes: nothing (both files are unreferenced since commit `9d4c1333`).
- Produces: no remaining unlocked-editor duplicates.

- [ ] **Step 1: Confirm both files are unreferenced**

Run:

```bash
rg -n "WorkspaceSettingsView|showWorkspaceDetailsDialog|WorkspaceDetailsDialog|workspace_details_dialog|workspace_settings_view" client/lib client/test
```

Expected: matches only inside the two files being deleted.

- [ ] **Step 2: Delete the files**

```bash
git rm client/lib/pages/home_workspace/workspace/workspace_settings_view.dart client/lib/widgets/workspace_details_dialog.dart
```

- [ ] **Step 3: Run analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no errors related to the deleted files.

- [ ] **Step 4: Run the full test gate**

Run: `flutter test --exclude-tags integration`

Expected: all tests PASS (in particular `test/pages/home_workspace/workspace/workspace_folders_section_test.dart`, `test/pages/home_workspace/workspace/workspace_info_section_target_test.dart`, `test/widgets/workspace_folders_editor_test.dart`, `test/repositories/session_repository_folders_test.dart`).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(workspace): remove orphaned settings view and details dialog"
```
