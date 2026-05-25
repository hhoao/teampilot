# Button Click Throttle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent duplicate side effects from rapid button/tap clicks across TeamPilot by adding a shared throttle helper, cubit-level in-flight guards where needed, and wiring P0 UI entry points first.

**Architecture:** Reuse existing `Throttles` in `client/lib/utils/debounce/throttles.dart` (leading-edge: first click runs, repeats ignored for N ms). Add thin Flutter helpers (`throttledOnPressed`, `throttledTap`) in a new `button_callbacks.dart` exported from `debounce.dart`. Keep `Debouncer` for text fields only. Complement UI throttle with cubit `globalBusy` / existing `busyIds` for long async work.

**Tech Stack:** Flutter 3.x, `flutter_bloc`, Dart `Timer`, existing `Throttles` / `Debouncer`.

---

## Background (audit summary)

| Layer | Current state |
|-------|----------------|
| `Debounces` / `Debouncer` | Used for **text persist** + log search only |
| `Throttles` | Defined, **0 app usages** |
| Buttons (`onPressed`) | ~115 sites, **none** throttled |
| Highest risk | PTY connect, `updateAll`, ZIP install, credential OAuth, delete without confirm |

**Do not use `Debounces` for buttons** — trailing debounce delays the first action. Buttons need **throttle** (or disable while `busy`).

Default duration: **`Duration(milliseconds: 500)`** for destructive/async actions; **`300ms`** for navigation taps.

---

## File map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `client/lib/utils/debounce/button_callbacks.dart` | `throttledOnPressed`, `throttledTap`, `throttledAsync` |
| Modify | `client/lib/utils/debounce/debounce.dart` | export `button_callbacks.dart` |
| Create | `client/test/utils/throttles_test.dart` | unit tests for `Throttles` + helpers |
| Modify | P0 UI files (see phases below) | wrap handlers |
| Modify | `plugin_cubit.dart`, `skill_cubit.dart`, `chat_cubit.dart` | in-flight guards |

---

## Tag naming convention

```
'<file>_<widget>_<action>'
```

Examples:
- `chat_workbench_session_start`
- `plugin_toolbar_update_all`
- `context_sidebar_new_chat`

Use **one tag per logical action**, not per widget instance, unless actions must be independent (e.g. per-row install: `plugin_install_${plugin.key}`).

---

### Task 1: Throttle helpers + tests

**Files:**
- Create: `client/lib/utils/debounce/button_callbacks.dart`
- Modify: `client/lib/utils/debounce/debounce.dart`
- Create: `client/test/utils/throttles_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// client/test/utils/throttles_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/debounce/debounce.dart';

void main() {
  tearDown(Throttles.cancelAll);

  test('Throttles.throttle ignores second call within duration', () {
    var count = 0;
    Throttles.throttle('t', const Duration(milliseconds: 100), () => count++);
    Throttles.throttle('t', const Duration(milliseconds: 100), () => count++);
    expect(count, 1);
  });

  test('Throttles.throttle allows call after duration', () async {
    var count = 0;
    Throttles.throttle('t', const Duration(milliseconds: 50), () => count++);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    Throttles.throttle('t', const Duration(milliseconds: 50), () => count++);
    expect(count, 2);
  });

  test('throttledOnPressed returns null when throttled', () {
    var count = 0;
    final fn = throttledOnPressed('btn', () => count++);
    fn!();
    expect(fn(), isNull);
    expect(count, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client && flutter test test/utils/throttles_test.dart
```

Expected: FAIL — `throttledOnPressed` not defined.

- [ ] **Step 3: Implement helpers**

```dart
// client/lib/utils/debounce/button_callbacks.dart
import 'package:flutter/foundation.dart';

import 'throttles.dart';

const kDefaultButtonThrottle = Duration(milliseconds: 500);
const kNavigationThrottle = Duration(milliseconds: 300);

/// Sync button handler: first tap runs, repeats ignored until [duration] elapses.
VoidCallback? throttledOnPressed(
  String tag,
  VoidCallback onPressed, {
  Duration duration = kDefaultButtonThrottle,
}) {
  return () {
    Throttles.throttle(tag, duration, onPressed);
  };
}

/// Same for [GestureDetector.onTap] / [InkWell.onTap].
VoidCallback? throttledTap(
  String tag,
  VoidCallback onTap, {
  Duration duration = kNavigationThrottle,
}) {
  return throttledOnPressed(tag, onTap, duration: duration);
}

/// Async handler: throttle only gates *starting* another invocation.
VoidCallback? throttledAsync(
  String tag,
  Future<void> Function() action, {
  Duration duration = kDefaultButtonThrottle,
}) {
  return () {
    Throttles.throttle(tag, duration, () {
      unawaited(action());
    });
  };
}
```

Add to `debounce.dart`:

```dart
export 'button_callbacks.dart';
```

- [ ] **Step 4: Run tests**

```bash
cd client && flutter test test/utils/throttles_test.dart
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/utils/debounce/button_callbacks.dart \
        client/lib/utils/debounce/debounce.dart \
        client/test/utils/throttles_test.dart
git commit -m "feat(client): add throttled button callback helpers"
```

---

### Task 2: Chat / terminal P0

**Files:**
- Modify: `client/lib/pages/chat_workbench.dart`
- Modify: `client/lib/pages/chat_page.dart`
- Modify: `client/lib/widgets/right_tools_panel.dart`
- Modify: `client/lib/widgets/context_sidebar.dart`
- Modify: `client/lib/cubits/chat_cubit.dart` (guard only)

- [ ] **Step 1: Guard `connectSession` at cubit entry**

In `chat_cubit.dart` `connectSession`, after null-repo checks:

```dart
if (state.isActiveSessionConnecting) return;
```

- [ ] **Step 2: Disable start button while connecting**

In `chat_workbench.dart` `_TerminalPlaceholder`, change:

```dart
FilledButton.icon(
  onPressed: sessionConnectInProgress ? null : throttledOnPressed(
    'chat_workbench_session_start',
    onConnect,
  ),
  // ...
)
```

Pass `sessionConnectInProgress` into `_TerminalPlaceholder` from parent (already available in builder).

- [ ] **Step 3: Throttle chat toolbar actions**

`chat_page.dart`:

```dart
import '../utils/debounce/debounce.dart';

onPressed: throttledOnPressed('chat_open_team_lead', () { /* existing body */ }),
onPressed: throttledAsync('chat_launch_all_members', () async {
  await context.read<ChatCubit>().launchAllMembers(team);
}),
```

- [ ] **Step 4: Throttle right panel launch-all**

`right_tools_panel.dart` — wrap `onLaunchAll`:

```dart
onPressed: onLaunchAll == null ? null : throttledOnPressed('right_tools_launch_all', onLaunchAll!),
```

(Adjust if `onLaunchAll` is non-nullable `VoidCallback`.)

- [ ] **Step 5: Throttle sidebar new chat + destructive confirms**

`context_sidebar.dart`:

```dart
onTap: throttledAsync('context_sidebar_new_chat', () => _startNewChat(context)),
```

Dialog confirm buttons:

```dart
onPressed: throttledAsync('context_sidebar_delete_project', () async {
  await context.read<ChatCubit>().deleteProject(repo, project.projectId);
  if (ctx.mounted) Navigator.of(ctx).pop();
}),
```

Apply same pattern for `deleteSession` / `renameSession` dialogs.

- [ ] **Step 6: Run analyzer + tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags integration
```

- [ ] **Step 7: Commit**

```bash
git commit -m "fix(client): throttle chat session and sidebar actions"
```

---

### Task 3: Plugin / Skill P0 + cubit guards

**Files:**
- Modify: `client/lib/cubits/plugin_cubit.dart`
- Modify: `client/lib/cubits/skill_cubit.dart`
- Modify: `client/lib/pages/plugin_management_page.dart`
- Modify: `client/lib/pages/skill_management_page.dart`

- [ ] **Step 1: Add `toolbarBusy` to state (both cubits)**

`PluginState` / `SkillState`:

```dart
final bool toolbarBusy;
```

Default `false`. Set `true` at start of `updateAll`, `installFromZip`, `importUnmanaged`, `checkUpdates`; clear in `finally`.

- [ ] **Step 2: Early-return in cubit methods**

```dart
Future<void> updateAll() async {
  if (state.toolbarBusy) return;
  emit(state.copyWith(toolbarBusy: true, clearError: true));
  try {
    // existing loop
  } finally {
    emit(state.copyWith(toolbarBusy: false));
  }
}
```

Mirror for `installFromZip` (both cubits). Add `busyIds` to `skill_cubit.uninstall` (plugin already has it).

- [ ] **Step 3: Wire toolbar buttons**

`plugin_management_page.dart`:

```dart
import '../../utils/debounce/debounce.dart';

onPressed: (state.updates.isEmpty || state.toolbarBusy)
    ? null
    : throttledOnPressed('plugin_update_all', cubit.updateAll),
onPressed: state.toolbarBusy ? null : throttledAsync('plugin_import_zip', () => _onInstallZip(context)),
```

Same for `skill_management_page.dart` with tags `skill_*`.

- [ ] **Step 4: Throttle add-repo button (~line 1351)**

```dart
onPressed: throttledAsync('skill_add_repo', () async { /* existing */ }),
```

- [ ] **Step 5: Run tests + commit**

```bash
cd client && flutter test --exclude-tags integration
git commit -m "fix(client): guard plugin/skill toolbar async actions"
```

---

### Task 4: Provider / credentials / team / file P0

**Files:**
- Modify: `client/lib/widgets/app_provider/claude_official_credential_actions.dart`
- Modify: `client/lib/widgets/app_provider/app_provider_form_sheet.dart`
- Modify: `client/lib/widgets/app_provider/app_provider_list_panel.dart`
- Modify: `client/lib/pages/llm_config_workspace.dart` (delete / save confirm only)
- Modify: `client/lib/pages/team_config_page.dart`
- Modify: `client/lib/widgets/file_tree_node.dart`

- [ ] **Step 1: Credential actions — local `_running` flag**

`claude_official_credential_actions.dart` → convert to `StatefulWidget` or extract `_CredentialActionsBody`:

```dart
var _running = false;
Future<void> _run(BuildContext context, Future<bool> Function() action) async {
  if (_running) return;
  setState(() => _running = true);
  try {
    // existing snackbar logic
  } finally {
    if (mounted) setState(() => _running = false);
  }
}
```

Disable buttons when `_running`.

- [ ] **Step 2: Provider form save**

Wrap save `onPressed` with `throttledOnPressed('app_provider_form_save', () { ... })` and disable after first valid save until sheet closes.

- [ ] **Step 3: LLM delete buttons**

```dart
onPressed: throttledOnPressed('llm_delete_provider_${provider.name}', () => widget.onDelete(provider.name)),
```

- [ ] **Step 4: Team member delete — add confirm + throttle**

`team_config_page.dart` `IconButton`:

```dart
onPressed: !canDelete ? null : throttledOnPressed('team_delete_member_${member.id}', () async {
  final ok = await showDialog<bool>(/* confirm */);
  if (ok == true) await cubit.deleteMember(member.id);
}),
```

- [ ] **Step 5: File tree delete**

```dart
onPressed: throttledOnPressed('file_tree_delete_$targetPath', () {
  Navigator.pop(ctx);
  cubit.deletePath(targetPath);
}),
```

- [ ] **Step 6: Analyze, test, commit**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags integration
git commit -m "fix(client): throttle provider, team, and file-tree actions"
```

---

### Task 5: P1 navigation taps (optional follow-up)

**Files:**
- Modify: `client/lib/widgets/context_sidebar.dart` (session row tap, team select)
- Modify: `client/lib/pages/config_workspace.dart`
- Modify: `client/lib/pages/team_config_page.dart`
- Modify: `client/lib/pages/plugin_management_page.dart` (section `onTap`)
- Modify: `client/lib/pages/skill_management_page.dart`
- Modify: `client/lib/pages/llm_config_workspace.dart` (provider list `onTap`)

- [ ] **Step 1: Wrap section/session navigation with `throttledTap`**

Example:

```dart
onTap: throttledTap('config_section_$id', () => onSelectSection(section)),
```

- [ ] **Step 2: Commit**

```bash
git commit -m "fix(client): throttle settings and sidebar navigation taps"
```

---

### Task 6: Verification & docs

**Files:**
- Modify: `client/.cursor/rules/teampilot-development-guide.mdc` OR add note in plan only (skip unless team wants doc)

- [ ] **Step 1: Full client verification**

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags integration
```

Expected: 0 failures.

- [ ] **Step 2: Manual smoke checklist**

| Action | Expected |
|--------|----------|
| Double-click「开始会话」 | Only one PTY spawn |
| Double-click「Open Team」 | One `launchAllMembers` wave |
| Double-click「Update all」plugins/skills | One update pass; button disabled while busy |
| Double-click Claude OAuth login | One auth flow |
| Double-click delete member | Confirm once; single delete |

- [ ] **Step 3: Final commit if doc added**

---

## Out of scope (YAGNI)

- P2: dialog Cancel, clipboard copy, `setState` toggles, terminal find bar
- Renaming `ratelimts.dart` typo (separate cleanup)
- Rewriting all ~115 `onPressed` in one PR — use phased PRs per task above

## PR split recommendation

| PR | Tasks |
|----|-------|
| PR1 | Task 1 (helpers + tests) |
| PR2 | Task 2 (chat/terminal) |
| PR3 | Task 3 (plugin/skill) |
| PR4 | Task 4 (provider/team/file) |
| PR5 | Task 5 (P1 navigation, optional) |

---

## Self-review

| Spec item | Task |
|-----------|------|
| Shared throttle utility | Task 1 |
| PTY / chat duplicate connect | Task 2 |
| Plugin/skill `updateAll` / ZIP | Task 3 |
| Credentials / delete / LLM | Task 4 |
| Navigation tap polish | Task 5 |
| Verification | Task 6 |

No placeholders. Types consistent (`VoidCallback?`, `toolbarBusy` on both cubits).
