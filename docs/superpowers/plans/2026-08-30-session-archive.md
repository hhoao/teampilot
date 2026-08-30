# Session Archive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add soft session archive so the workspace sidebar main list hides archived sessions, archive is one-click, and permanent delete only exists in a sidebar archive view (with restore + confirm-dialog delete).

**Architecture:** Persist `AppSession.archived` in `session.json`. Filter helpers split active vs archived lists. `ChatCubit.archiveSession` / `unarchiveSession` flip the flag without closing tabs. `WorkspaceSidebar` local `_showingArchive` swaps the list; `SidebarSessionTile` gains an `archiveMode` for restore + dialog delete.

**Tech Stack:** Flutter / Dart, `flutter_bloc`, existing `SessionRepository` / `ChatCubit`, `shared_ui` (`TpIconButton`, `TpDialog`), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-30-session-archive-design.md`

## Global Constraints

- Spec wins over this plan if they drift.
- Archive / unarchive must **not** disconnect PTY, close tabs, or call `deleteSession` / `onSessionDeleted`.
- Delete remains the existing `ChatCubit.deleteSession` path; UI only invokes it from archive mode after a confirm dialog.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only, then regenerate (`flutter gen-l10n` from `client/`).
- Tests: `cd client && flutter test <files listed in the task>`. Do not run the full suite unless the task says so.
- Do **not** git commit unless the user explicitly asks (repo rule). Skip every Commit step.
- Commands run from `client/` unless noted.
- No new GoRouter route; archive is sidebar-local UI state.

## File map

| File | Role |
|------|------|
| Modify `client/lib/models/app_session.dart` | `archived` field, JSON, copyWith, ==/hashCode |
| Create `client/lib/utils/session/session_archive_filter.dart` | `activeSessions` / `archivedSessions` |
| Modify `client/lib/repositories/session_repository.dart` | `setSessionArchived` |
| Modify `client/lib/cubits/chat_cubit.dart` | `archiveSession` / `unarchiveSession` |
| Modify `client/lib/l10n/app_en.arb`, `app_zh.arb` (+ gen) | Archive / restore / empty copy |
| Modify `client/lib/widgets/sidebar_session_tile.dart` | Active=archive; archiveMode=restore+delete dialog |
| Modify `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart` | `_showingArchive`, entry, filtered lists |
| Modify `workspace_search_dialog.dart` (open helper) | Exclude archived from search hits |
| Modify group / worktree list inputs as needed | Feed active-only session lists |
| Tests | Mirror each unit above |

---

### Task 1: `AppSession.archived` model

**Files:**
- Modify: `client/lib/models/app_session.dart`
- Test: `client/test/models/app_session_archived_test.dart` (create)

**Interfaces:**
- Produces: `AppSession.archived` (`bool`, default `false`); `fromJson` missing → `false`; `toJson` writes `'archived': true` only when true; `copyWith({bool? archived})`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';

void main() {
  test('archived defaults false and missing JSON is false', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
    );
    expect(s.archived, isFalse);
    final restored = AppSession.fromJson({
      'sessionId': 's1',
      'workspaceId': 'w1',
      'createdAt': 1,
    });
    expect(restored.archived, isFalse);
  });

  test('archived true round-trips in JSON', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      archived: true,
    );
    final json = s.toJson();
    expect(json['archived'], isTrue);
    expect(AppSession.fromJson(json).archived, isTrue);
  });

  test('toJson omits archived when false', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
    );
    expect(s.toJson().containsKey('archived'), isFalse);
  });

  test('copyWith can set and clear archived', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
    );
    expect(s.copyWith(archived: true).archived, isTrue);
    expect(s.copyWith(archived: true).copyWith(archived: false).archived, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/app_session_archived_test.dart`

Expected: FAIL (no `archived` named parameter / field).

- [ ] **Step 3: Implement `archived` on `AppSession`**

In `app_session.dart`:

1. Add `this.archived = false` to the public factory and private `._` constructor; add `final bool archived;`.
2. `fromJson`: `archived: json['archived'] as bool? ?? false`.
3. `copyWith`: add `bool? archived` → `archived: archived ?? this.archived`.
4. `toJson`: add `if (archived) 'archived': archived,` (same style as optional fields).
5. Include `archived` in `==` and `hashCode`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/app_session_archived_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

Skip unless the user explicitly asks to commit.

---

### Task 2: Archive filter helpers

**Files:**
- Create: `client/lib/utils/session/session_archive_filter.dart`
- Test: `client/test/utils/session/session_archive_filter_test.dart` (create)

**Interfaces:**
- Consumes: `AppSession.archived`
- Produces:
  - `List<AppSession> activeSessions(List<AppSession> sessions)`
  - `List<AppSession> archivedSessions(List<AppSession> sessions)`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/utils/session/session_archive_filter.dart';

AppSession _s(String id, {bool archived = false}) => AppSession(
      sessionId: id,
      workspaceId: 'w',
      createdAt: 1,
      archived: archived,
    );

void main() {
  test('activeSessions excludes archived', () {
    final all = [_s('a'), _s('b', archived: true), _s('c')];
    expect(activeSessions(all).map((s) => s.sessionId), ['a', 'c']);
  });

  test('archivedSessions keeps only archived', () {
    final all = [_s('a'), _s('b', archived: true)];
    expect(archivedSessions(all).map((s) => s.sessionId), ['b']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/session/session_archive_filter_test.dart`

Expected: FAIL (library missing).

- [ ] **Step 3: Implement helpers**

```dart
import '../../models/app_session.dart';

List<AppSession> activeSessions(List<AppSession> sessions) => [
      for (final s in sessions)
        if (!s.archived) s,
    ];

List<AppSession> archivedSessions(List<AppSession> sessions) => [
      for (final s in sessions)
        if (s.archived) s,
    ];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/utils/session/session_archive_filter_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

Skip unless the user explicitly asks to commit.

---

### Task 3: `SessionRepository.setSessionArchived`

**Files:**
- Modify: `client/lib/repositories/session_repository.dart` (near `toggleSessionPin`, ~1051)
- Test: `client/test/repositories/session_repository_test.dart` (add cases)

**Interfaces:**
- Consumes: `AppSession.copyWith(archived:)`, `_withSessionFile`, `_writeSession`
- Produces: `Future<AppSession?> setSessionArchived(String sessionId, bool archived)` — updates `archived` + `updatedAt`, returns written session or `null` if missing

- [ ] **Step 1: Write the failing test**

Add to `session_repository_test.dart`:

```dart
test('setSessionArchived persists archived flag', () async {
  final tmp = await Directory.systemTemp.createTemp('repo_archive_test_');
  final repo = SessionRepository(rootDir: tmp.path);
  final ws = await repo.createWorkspace([WorkspaceFolder(path: '/p')]);
  final created = await repo.createSession(ws.workspaceId);
  expect(created.session.archived, isFalse);

  final archived = await repo.setSessionArchived(created.session.sessionId, true);
  expect(archived!.archived, isTrue);

  final reloaded = await repo.loadSessions();
  expect(
    reloaded.singleWhere((s) => s.sessionId == created.session.sessionId).archived,
    isTrue,
  );

  final restored = await repo.setSessionArchived(created.session.sessionId, false);
  expect(restored!.archived, isFalse);
  await tmp.delete(recursive: true);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories/session_repository_test.dart --name setSessionArchived`

Expected: FAIL (method missing).

- [ ] **Step 3: Implement repository method**

Mirror `toggleSessionPin`:

```dart
Future<AppSession?> setSessionArchived(String sessionId, bool archived) {
  return _withSessionFile(sessionId, () async {
    final fs = await _fs();
    final existing = await _findSession(fs, sessionId);
    if (existing == null) return null;
    if (existing.archived == archived) return existing;
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = existing.copyWith(archived: archived, updatedAt: now);
    await _writeSession(fs, updated);
    return updated;
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories/session_repository_test.dart --name setSessionArchived`

Expected: PASS

- [ ] **Step 5: Commit**

Skip unless the user explicitly asks to commit.

---

### Task 4: `ChatCubit` archive / unarchive

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart` (near `toggleSessionPin`)
- Test: `client/test/cubits/chat_cubit_test.dart` (add group)

**Interfaces:**
- Consumes: `SessionRepository.setSessionArchived`, `replaceSessionSnapshot`
- Produces:
  - `Future<void> archiveSession(String sessionId)`
  - `Future<void> unarchiveSession(String sessionId)`
- Must **not** call `deleteSession`, tab remove, or workbench `onSessionDeleted`

- [ ] **Step 1: Write the failing test**

```dart
group('archiveSession / unarchiveSession', () {
  test('archiveSession sets archived without removing session', () async {
    final tmp = await Directory.systemTemp.createTemp('chat_cubit_archive_');
    final repo = SessionRepository(rootDir: tmp.path);
    final postFrame = PostFrameTestHarness();
    final cubit = ChatCubit(
      executableResolver: () => 'true',
      automationRepository: testAutomationRepository(),
      sessionRepository: repo,
      postFrameScheduler: postFrame.scheduler,
    );
    _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);

    final ws = await repo.createWorkspace([WorkspaceFolder(path: '/p')]);
    final created = await repo.createSession(ws.workspaceId);
    await cubit.loadWorkspaceIndex(repo);
    await cubit.ensureSessionsForWorkspace(ws.workspaceId);

    await cubit.archiveSession(created.session.sessionId);

    final patched = cubit.state.sessions.singleWhere(
      (s) => s.sessionId == created.session.sessionId,
    );
    expect(patched.archived, isTrue);
    expect(cubit.state.sessions, hasLength(1));
  });

  test('unarchiveSession clears archived', () async {
    final tmp = await Directory.systemTemp.createTemp('chat_cubit_unarchive_');
    final repo = SessionRepository(rootDir: tmp.path);
    final postFrame = PostFrameTestHarness();
    final cubit = ChatCubit(
      executableResolver: () => 'true',
      automationRepository: testAutomationRepository(),
      sessionRepository: repo,
      postFrameScheduler: postFrame.scheduler,
    );
    _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);

    final ws = await repo.createWorkspace([WorkspaceFolder(path: '/p')]);
    final created = await repo.createSession(ws.workspaceId);
    await cubit.loadWorkspaceIndex(repo);
    await cubit.ensureSessionsForWorkspace(ws.workspaceId);
    await cubit.archiveSession(created.session.sessionId);
    await cubit.unarchiveSession(created.session.sessionId);

    final patched = cubit.state.sessions.singleWhere(
      (s) => s.sessionId == created.session.sessionId,
    );
    expect(patched.archived, isFalse);
  });
});
```

(Reuse the same imports / `_registerTempCubitCleanup` already in `chat_cubit_test.dart`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/cubits/chat_cubit_test.dart --name archiveSession`

Expected: FAIL (methods missing).

- [ ] **Step 3: Implement cubit methods**

Next to `toggleSessionPin`:

```dart
Future<void> archiveSession(String sessionId) async {
  final repo = _sessionRepository;
  if (repo == null) return;
  final updated = await repo.setSessionArchived(sessionId, true);
  if (updated != null) replaceSessionSnapshot(updated);
}

Future<void> unarchiveSession(String sessionId) async {
  final repo = _sessionRepository;
  if (repo == null) return;
  final updated = await repo.setSessionArchived(sessionId, false);
  if (updated != null) replaceSessionSnapshot(updated);
}
```

Do not add optimistic updates that leave a lying UI on persist failure — wait for repo result (same as pin).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/cubits/chat_cubit_test.dart --name archiveSession`

Expected: PASS

- [ ] **Step 5: Commit**

Skip unless the user explicitly asks to commit.

---

### Task 5: l10n strings

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Regenerated: `app_localizations*.dart` via `flutter gen-l10n`

**Interfaces:**
- Produces getters:
  - `archiveConversation` — action + tooltip
  - `restoreConversation` — restore action
  - `sessionArchiveTitle` — archive view header
  - `sessionArchiveEmpty` — empty placeholder
  - `sessionArchiveEntryTooltip` — header entry button

Reuse existing `deleteConversation` / `deleteConversationConfirm(name)` / `cancel` / `delete` for the delete dialog.

- [ ] **Step 1: Add arb keys**

`app_en.arb` (near `deleteConversation`):

```json
"archiveConversation": "Archive",
"restoreConversation": "Restore",
"sessionArchiveTitle": "Archive",
"sessionArchiveEmpty": "No archived conversations",
"sessionArchiveEntryTooltip": "Archived conversations"
```

`app_zh.arb`:

```json
"archiveConversation": "归档",
"restoreConversation": "恢复",
"sessionArchiveTitle": "归档",
"sessionArchiveEmpty": "暂无归档会话",
"sessionArchiveEntryTooltip": "归档会话"
```

- [ ] **Step 2: Regenerate**

Run: `flutter gen-l10n`

Expected: new getters on `AppLocalizations` / en / zh.

- [ ] **Step 3: Smoke-check analyze on l10n**

Run: `flutter analyze lib/l10n --no-fatal-infos --no-fatal-warnings`

Expected: no errors related to the new keys.

- [ ] **Step 4: Commit**

Skip unless the user explicitly asks to commit.

---

### Task 6: `SidebarSessionTile` archive mode

**Files:**
- Modify: `client/lib/widgets/sidebar_session_tile.dart`
- Test: `client/test/widgets/sidebar_session_tile_test.dart` (extend)

**Interfaces:**
- Consumes: `ChatCubit.archiveSession` / `unarchiveSession` / `deleteSession`; l10n keys from Task 5
- Produces: `SidebarSessionTile(..., {bool archiveMode = false})`
  - `archiveMode == false`: trailing Archive (one click); overflow Archive (no Delete); remove arm-delete trash
  - `archiveMode == true`: trailing Restore + Delete; Delete opens confirm dialog using `deleteConversationConfirm`; overflow Restore + Delete

- [ ] **Step 1: Write failing widget tests**

Add tests that:

1. Default tile hover shows archive control (tooltip / icon), not delete trash arming.
2. In `archiveMode: true`, tapping delete opens a dialog with `deleteConversationConfirm`; cancel does not call delete; confirm does.

Sketch (adapt to existing harness in `sidebar_session_tile_test.dart` — same providers as other tests in that file):

```dart
testWidgets('active mode archives on action tap', (tester) async {
  // pump SidebarSessionTile with ChatCubit + SessionRepository mocks/real temp
  // hover or reveal actions, tap archive
  // expect cubit.state session.archived == true
});

testWidgets('archiveMode delete confirms then deletes', (tester) async {
  // session with archived: true, archiveMode: true
  // tap delete → dialog visible
  // tap cancel → session still present
  // tap delete again → confirm → session gone
});
```

Follow existing provider wiring in that test file (`_pump` helpers). Prefer real temp `SessionRepository` + `ChatCubit` like neighboring tests when available; otherwise mock with a thin fake that records calls.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/sidebar_session_tile_test.dart --name archive`

Expected: FAIL (no `archiveMode` / still delete-arm UI).

- [ ] **Step 3: Implement tile mode**

1. Add `final bool archiveMode;` default `false` to `SidebarSessionTile`.
2. Remove `_deleteArmed` / `_SessionDeleteAction` arm flow from **active** mode.
3. Active trailing: `TpIconButton` / icon `Icons.archive_outlined` → `chatCubit.archiveSession(id)`; tooltip `l10n.archiveConversation`.
4. Active overflow + context menu: replace `delete` item with `archive` (label `archiveConversation`, non-destructive).
5. Archive mode trailing: Restore (`Icons.unarchive_outlined` → `unarchiveSession`) + Delete (`Icons.delete_outline`).
6. Archive delete:

```dart
Future<void> _confirmAndDelete(BuildContext context) async {
  final l10n = context.l10n;
  final name = widget.session.resolveDisplayTitle(l10n.defaultNewChatSessionTitle);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => TpDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: l10n.deleteConversation,
            onClose: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(height: 16),
          Text(l10n.deleteConversationConfirm(name)),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.delete),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !mounted) return;
  await _executeDelete();
}
```

Pattern matches `confirmDeleteTeam` in `team_delete_confirm_dialog.dart`.

7. Archive overflow/context: Restore + Delete (Delete → same confirm). Keep existing non-delete menu items (rename, pin, reference, …); swap only the delete entry for archive (active) or restore+delete (archive mode).

If the file grows past the soft limit, extract `_SessionArchiveActions` / `_SessionActiveActions` private widgets in the same file first; split file only if still unwieldy.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/sidebar_session_tile_test.dart`

Expected: PASS (including new archive cases; update any tests that asserted delete-arm trash).

- [ ] **Step 5: Commit**

Skip unless the user explicitly asks to commit.

---

### Task 7: `WorkspaceSidebar` archive view + list filtering

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_search_dialog.dart` (`showWorkspaceSearchDialog` sessions line)
- Modify: any group/worktree builders that take full workspace sessions without going through the sidebar host (e.g. `session_group_section.dart` add-sessions dialog, `_ConversationListHost` / structure inputs) — filter with `activeSessions(...)` for main UI
- Test: `client/test/pages/home_workspace/workspace/workspace_sidebar_archive_test.dart` (create) and/or extend `workspace_sidebar_manual_groups_test.dart`

**Interfaces:**
- Consumes: `activeSessions` / `archivedSessions`, `SidebarSessionTile.archiveMode`, l10n
- Produces: `_showingArchive` UI swap; main list uses active-only; archive list uses archived-only + empty placeholder; entry control always visible

- [ ] **Step 1: Write failing sidebar test**

```dart
// Pump WorkspaceSidebar with 1 active + 1 archived session.
// Expect only active tile in main list.
// Tap archive entry → expect archived tile + empty not shown.
// Expect back returns to active-only list.
```

Use existing sidebar test harness patterns (`workspace_sidebar_manual_groups_test.dart`).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/pages/home_workspace/workspace/workspace_sidebar_archive_test.dart`

Expected: FAIL (no archive entry / archived still in main list).

- [ ] **Step 3: Wire filtering + view swap**

1. In `_WorkspaceSidebarState`, add `bool _showingArchive = false;`.

2. Conversations header row (~135–192):
   - When `!_showingArchive`: keep sort / new group / worktree buttons; add `TpIconButton` (`Icons.inventory_2_outlined` or `Icons.archive_outlined`) with `tooltip: l10n.sessionArchiveEntryTooltip`, `onTap: () => setState(() => _showingArchive = true)`.
   - When `_showingArchive`: replace that header with back + `l10n.sessionArchiveTitle` only (hide new-group / worktree create / sort).

3. Prefer hiding the top action block in archive for clarity:

```dart
if (!_showingArchive) ...[
  WorkspaceAutomationsSection(...),
  // new chat + search tiles
],
```

4. `_ConversationListHost` / structure select:
   - Main: `activeSessions(sessionsForWorkspace(...))` before `SessionListStructure.fromSessions` and before worktree/project grouping.
   - Archive: build a simple list of `archivedSessions(sessionsForWorkspace(...))` sorted with the same `AppSessionSort` (or `recentlyUpdated`); each row `SidebarSessionTile(..., archiveMode: true, ...)`. Empty → centered `Text(l10n.sessionArchiveEmpty)`.

5. `_RunningSessionsHost`: keep showing running sessions even if archived (user chose keep-running). Do **not** require filtering here.

6. Search open helper:

```dart
final sessions = activeSessions(
  sessionsForWorkspace(workspace, chatCubit.state.sessions),
);
```

7. Session group “add sessions” dialog: filter `activeSessions` so archived ids are not offered.

- [ ] **Step 4: Run tests**

Run:

```bash
flutter test test/pages/home_workspace/workspace/workspace_sidebar_archive_test.dart
flutter test test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart
flutter test test/widgets/sidebar_session_tile_test.dart
```

Expected: PASS

- [ ] **Step 5: Focused analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings lib/models/app_session.dart lib/utils/session/session_archive_filter.dart lib/repositories/session_repository.dart lib/cubits/chat_cubit.dart lib/widgets/sidebar_session_tile.dart lib/pages/home_workspace/workspace/workspace_sidebar.dart lib/pages/home_workspace/workspace/workspace_search_dialog.dart`

Expected: clean for touched files.

- [ ] **Step 6: Commit**

Skip unless the user explicitly asks to commit.

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `archived` on `AppSession` / JSON | 1 |
| Soft flag only (no dir move) | 1–4 |
| `activeSessions` / `archivedSessions` | 2 |
| Main list excludes archived | 7 |
| Search / groups / worktree exclude archived | 7 |
| `setSessionArchived` + cubit archive/unarchive | 3–4 |
| No disconnect on archive | 4 (explicit) |
| Sidebar `_showingArchive` + back + empty | 7 |
| Active row Archive one-click; no delete | 6 |
| Archive row Restore + Delete dialog | 6 |
| l10n EN/ZH | 5 |
| Delete = existing `deleteSession` | 6 |
| Running strip may still show archived-open | 7 |

## Plan self-review

- No TBD / “similar to Task N” gaps left for implementers.
- Signatures consistent: `setSessionArchived` → cubit → tile.
- Out-of-scope items (bulk archive, `archivedAt`, badge counts) not scheduled.
