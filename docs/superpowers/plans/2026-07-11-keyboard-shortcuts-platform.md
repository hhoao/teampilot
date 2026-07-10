# Keyboard Shortcuts Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an app-wide command + keybinding platform with VS Code-shaped defaults, terminal passthrough, rebindable settings UI, and migrate compose shortcuts into the same system.

**Architecture:** Portable `KeyChord` + `CommandCatalog` + `CommandBus` + root `ShortcutDispatcher` (`HardwareKeyboard`). User overrides in `<teampilotRoot>/keybindings.json` via `KeybindingRepository` / `ShortcutCubit`. Feature owners register handlers (HomeShell chrome, ChatCubit session tabs, LayoutCubit panes/zoom, compose).

**Tech Stack:** Flutter / Dart, `flutter_bloc`, existing `AppStorage` / `LayoutCubit` / `ChatCubit` / `HomeShell`, ARB l10n.

**Spec:** [docs/superpowers/specs/2026-07-11-keyboard-shortcuts-platform-design.md](../specs/2026-07-11-keyboard-shortcuts-platform-design.md)

**Constraints:** No backward compatibility with `KeyboardShortcutAction`. No command palette in v1. No Flutter parallel `Shortcuts`/`Actions` tree for app commands. Session tab cycle uses explicit **Ctrl+Tab** (not Mod+Tab).

---

## File map (target)

| File | Responsibility |
|------|----------------|
| `client/lib/services/commands/key_chord.dart` | Portable chord model, JSON, platform → `SingleActivator` |
| `client/lib/services/commands/key_chord_formatter.dart` | Display labels (`⌘W` / `Ctrl+W`) |
| `client/lib/services/commands/command_ids.dart` | Stable string id constants |
| `client/lib/services/commands/command_definition.dart` | `CommandCategory`, `ShortcutWhen`, `CommandDefinition` |
| `client/lib/services/commands/command_catalog.dart` | v1 catalog + defaults |
| `client/lib/services/commands/command_bus.dart` | register / unregister / invoke |
| `client/lib/services/commands/shortcut_context.dart` | Context flags + when evaluation |
| `client/lib/services/commands/keybinding_resolver.dart` | Match event → commandId; conflict scan; effective merge |
| `client/lib/services/commands/shortcut_dispatcher.dart` | Root HardwareKeyboard handler; enable/disable for capture UI |
| `client/lib/services/commands/shortcut_focus.dart` | Focus kind tags (compose / terminal / text) |
| `client/lib/repositories/keybinding_repository.dart` | Load/save `keybindings.json` |
| `client/lib/cubits/shortcut_cubit.dart` | Effective bindings + rebind/reset/import for UI + dispatcher |
| `client/lib/pages/home_workspace/workspace_chrome_commands.dart` | Callback host HomeShell registers into CommandBus |
| `client/lib/pages/config/shortcuts_config_section.dart` | Settings section UI |
| `client/lib/widgets/shortcuts/shortcut_cheatsheet_dialog.dart` | Mod+/ cheatsheet |
| `client/lib/widgets/shortcuts/shortcut_rebind_dialog.dart` | Press-to-bind capture modal |
| `client/lib/services/keyboard/compose_keyboard_shortcut_handler.dart` | Retarget to catalog ids / resolver (or thin wrapper) |
| Delete | `client/lib/models/keyboard_shortcut_action.dart`, `keyboard_shortcut_bindings.dart` (after migration) |
| Wire | `app_shell.dart`, `main.dart` / bootstrap, `layout_cubit.dart`, `home_workspace_shell.dart`, `chat_cubit.dart` (or session command registrar), `config_cubit.dart`, `app_router.dart`, `config_workspace.dart`, ARB |

---

### Task 1: `KeyChord` model + formatter (TDD)

**Files:**
- Create: `client/lib/services/commands/key_chord.dart`
- Create: `client/lib/services/commands/key_chord_formatter.dart`
- Create: `client/test/services/commands/key_chord_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/key_chord.dart';
import 'package:teampilot/services/commands/key_chord_formatter.dart';

void main() {
  test('round-trips JSON', () {
    const chord = KeyChord(key: 'w', mods: [KeyChordMod.mod]);
    expect(KeyChord.fromJson(chord.toJson()), chord);
  });

  test('mod resolves to meta on macOS target, control otherwise', () {
    final activator = const KeyChord(
      key: 'w',
      mods: [KeyChordMod.mod],
    ).toActivator(isMacOS: true);
    expect(activator, isA<SingleActivator>());
    final mac = activator as SingleActivator;
    expect(mac.trigger, LogicalKeyboardKey.keyW);
    expect(mac.meta, isTrue);
    expect(mac.control, isFalse);

    final win = const KeyChord(
      key: 'w',
      mods: [KeyChordMod.mod],
    ).toActivator(isMacOS: false) as SingleActivator;
    expect(win.control, isTrue);
    expect(win.meta, isFalse);
  });

  test('explicit ctrl stays ctrl on macOS', () {
    final a = const KeyChord(
      key: 'tab',
      mods: [KeyChordMod.ctrl],
    ).toActivator(isMacOS: true) as SingleActivator;
    expect(a.control, isTrue);
    expect(a.meta, isFalse);
  });

  test('formatter uses symbols on macOS', () {
    expect(
      formatKeyChord(
        const KeyChord(key: 'w', mods: [KeyChordMod.mod]),
        isMacOS: true,
      ),
      '⌘W',
    );
    expect(
      formatKeyChord(
        const KeyChord(key: 'w', mods: [KeyChordMod.mod]),
        isMacOS: false,
      ),
      'Ctrl+W',
    );
  });

  test('hasModifiers is false only for bare keys', () {
    expect(const KeyChord(key: 'enter').hasModifiers, isFalse);
    expect(
      const KeyChord(key: 'enter', mods: [KeyChordMod.mod]).hasModifiers,
      isTrue,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/commands/key_chord_test.dart`

Expected: FAIL (library not found)

- [ ] **Step 3: Implement `KeyChord` + formatter**

Implement:
- `enum KeyChordMod { mod, shift, alt, ctrl, meta }`
- `class KeyChord` with `key` string (`tab`, `w`, `equal`, `minus`, `digit0`, `enter`, `slash`, `arrowLeft`, `arrowRight`, `numpadAdd`, `numpadSubtract`, …), `mods`, `==`/`hashCode`, `toJson`/`fromJson`, `hasModifiers`, `toActivator({required bool isMacOS})`
- Map key strings ↔ `LogicalKeyboardKey`
- `formatKeyChord(KeyChord, {required bool isMacOS})`

Use injectable `isMacOS` (do not call `Platform.isMacOS` inside match hot path without a seam — default helper `bool defaultIsMacOS() => !kIsWeb && Platform.isMacOS` in the same file is fine for production callers).

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/services/commands/key_chord_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/commands/key_chord.dart \
  client/lib/services/commands/key_chord_formatter.dart \
  client/test/services/commands/key_chord_test.dart
git commit -m "$(cat <<'EOF'
feat(commands): add portable KeyChord model and formatter

EOF
)"
```

---

### Task 2: Command ids, definitions, catalog (TDD)

**Files:**
- Create: `client/lib/services/commands/command_ids.dart`
- Create: `client/lib/services/commands/command_definition.dart`
- Create: `client/lib/services/commands/command_catalog.dart`
- Create: `client/test/services/commands/command_catalog_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_catalog.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/key_chord.dart';

void main() {
  test('v1 catalog contains required command ids', () {
    final ids = CommandCatalog.v1.map((c) => c.id).toSet();
    expect(ids, containsAll([
      CommandIds.workspaceNextTab,
      CommandIds.sessionNextTab,
      CommandIds.sessionCloseTab,
      CommandIds.zoomIn,
      CommandIds.composeSubmit,
      CommandIds.showCheatsheet,
      CommandIds.toggleSidebar,
    ]));
  });

  test('session next tab defaults to explicit ctrl+tab', () {
    final def = CommandCatalog.v1.singleWhere(
      (c) => c.id == CommandIds.sessionNextTab,
    );
    expect(def.defaultChords, [
      const KeyChord(key: 'tab', mods: [KeyChordMod.ctrl]),
    ]);
    expect(def.terminalPassthrough, isTrue);
  });

  test('compose submit is unmodified enter, not passthrough', () {
    final def = CommandCatalog.v1.singleWhere(
      (c) => c.id == CommandIds.composeSubmit,
    );
    expect(def.defaultChords, [const KeyChord(key: 'enter')]);
    expect(def.terminalPassthrough, isFalse);
    expect(def.when, ShortcutWhen.inCompose);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement catalog matching the spec tables exactly**

Include all v1 commands from the spec (workspace, session, view, zoom with dual chords for numpad, compose, cheatsheet). Use string title/description keys as constants for now (e.g. `shortcutsWorkspaceNextTab`) — ARB wired in Task 10.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/commands/command_*.dart \
  client/test/services/commands/command_catalog_test.dart
git commit -m "$(cat <<'EOF'
feat(commands): add v1 command catalog

EOF
)"
```

---

### Task 3: `CommandBus` + `KeybindingResolver` (TDD)

**Files:**
- Create: `client/lib/services/commands/command_bus.dart`
- Create: `client/lib/services/commands/shortcut_context.dart`
- Create: `client/lib/services/commands/keybinding_resolver.dart`
- Create: `client/test/services/commands/keybinding_resolver_test.dart`
- Create: `client/test/services/commands/command_bus_test.dart`

- [ ] **Step 1: Write failing resolver + bus tests**

Cover:
1. `effectiveBindings`: missing override → default; `[]` override → unbound; non-empty override replaces.
2. Match Ctrl+Tab → `sessionNextTab` with `hasWorkspace: true`.
3. Match ignored when `when` unsatisfied.
4. Match ignored when `inTerminal` and `terminalPassthrough: false`.
5. Match allowed when `inTerminal` and passthrough true.
6. Bare Enter ignored when `inCompose: false`; matched when true.
7. **`inTextInput: true`:** modifier chords (e.g. Mod+W) still match; unmodified keys never match except compose Enter with `inCompose: true`.
8. Duplicate chord → first catalog order wins (optional log not asserted).
9. `findConflicts(effectiveMap)` returns pairs sharing a chord.
10. Bus: register → invoke calls handler; unregister → invoke no-ops; never throws.

Use the same `HardwareKeyboard` keyDown helper pattern as `keyboard_shortcut_bindings_test.dart`.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

```dart
// KeybindingResolver.match signature sketch:
String? match({
  required KeyEvent event,
  required Map<String, List<KeyChord>> effectiveByCommand,
  required ShortcutContext context,
  required bool isMacOS,
  List<CommandDefinition> catalog = CommandCatalog.v1,
});
```

`ShortcutContext` is a plain immutable data class with the flags from the spec. `ShortcutWhen.evaluate(context)` lives next to it.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/commands/command_bus.dart \
  client/lib/services/commands/shortcut_context.dart \
  client/lib/services/commands/keybinding_resolver.dart \
  client/test/services/commands/*.dart
git commit -m "$(cat <<'EOF'
feat(commands): add CommandBus and KeybindingResolver

EOF
)"
```

---

### Task 4: `KeybindingRepository` + `ShortcutCubit` (TDD)

**Files:**
- Create: `client/lib/repositories/keybinding_repository.dart`
- Create: `client/lib/cubits/shortcut_cubit.dart`
- Create: `client/test/repositories/keybinding_repository_test.dart`
- Create: `client/test/cubits/shortcut_cubit_test.dart`

- [ ] **Step 1: Write failing tests**

Repository (use `setUpTestAppStorage` / `tearDownTestAppStorage` from `client/test/support/post_frame_test_harness.dart`):
- Missing file → empty overrides
- Save + load round-trip
- Unknown command ids dropped on load
- Path is `p.join(AppStorage.appDataRoot, 'keybindings.json')`
- On-disk shape exactly:

```json
{ "version": 1, "bindings": { "<commandId>": [ { "key": "w", "mods": ["mod"] } ] } }
```

Empty override list `[]` means intentionally unbound. Missing command key means default.

Cubit:
- Starts with defaults as effective
- `rebind(id, chords)` persists and updates effective
- `unbind(id)` stores `[]`
- `resetCommand(id)` removes override key
- `resetAll()` clears file
- `importOverrides(map, {replaceConflicts: true})` applies Replace-all semantics after conflict scan
- `conflicts` getter reflects current effective map

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement repository + cubit**

`ShortcutState` holds `Map<String, List<KeyChord>> overrides` and exposes `Map<String, List<KeyChord>> get effective`.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/keybinding_repository.dart \
  client/lib/cubits/shortcut_cubit.dart \
  client/test/repositories/keybinding_repository_test.dart \
  client/test/cubits/shortcut_cubit_test.dart
git commit -m "$(cat <<'EOF'
feat(commands): persist keybinding overrides in ShortcutCubit

EOF
)"
```

---

### Task 5: `ShortcutDispatcher` + app shell wiring (TDD)

**Files:**
- Create: `client/lib/services/commands/shortcut_dispatcher.dart`
- Create: `client/test/services/commands/shortcut_dispatcher_test.dart`
- Modify: `client/lib/app/app_shell.dart` (provide `CommandBus`, `ShortcutCubit`, install dispatcher)
- Modify: bootstrap / `main.dart` as needed so cubit loads on startup

- [ ] **Step 1: Write failing dispatcher tests**

```dart
test('returns true and invokes when chord matches', () { … });
test('returns true even when bus has no handler', () { … });
test('returns false when disabled (capture mode)', () { … });
test('returns false when no match', () { … });
```

Dispatcher API sketch:

```dart
class ShortcutDispatcher {
  ShortcutDispatcher({
    required CommandBus bus,
    required List<KeyChord> Function(String commandId) effectiveChords,
    required ShortcutContext Function() context,
    required bool Function() isMacOS,
  });
  bool enabled = true;
  bool handle(KeyEvent event);
  void attach(); // HardwareKeyboard.instance.addHandler
  void detach();
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement dispatcher; wire in app shell**

- Construct `CommandBus` as a long-lived singleton/service on `AppShell`.
- `ShortcutCubit` load in bootstrap; `BlocProvider.value`.
- Create dispatcher after first frame or in a small `ShortcutDispatcherHost` StatefulWidget that `attach`/`detach` in init/dispose and rebuilds context closure from `GoRouter` + focus + cubits.
- Context builder must read: route has workspace id → `hasWorkspace`; HomeShell open tab count (Task 9 host); `ChatCubit` active session → `hasSessionTab`; focus flags via:

```dart
// client/lib/services/commands/shortcut_focus.dart
enum ShortcutFocusKind { compose, terminal, text }
```

**Until Task 6:** keep `inCompose: false` in the live context builder (or exclude `compose.*` ids from root match) so bare Enter is not claimed as a handled no-op before compose handlers exist. Stub `inTerminal: false` until Task 11 tags terminals; view/zoom/session commands still work outside the PTY.

- [ ] **Step 4: Run dispatcher unit tests PASS; smoke `flutter analyze` on touched files**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/commands/shortcut_dispatcher.dart \
  client/lib/services/commands/shortcut_focus.dart \
  client/test/services/commands/shortcut_dispatcher_test.dart \
  client/lib/app/app_shell.dart
git commit -m "$(cat <<'EOF'
feat(commands): install root ShortcutDispatcher

EOF
)"
```

---

### Task 6: Migrate compose to command catalog

**Chosen dispatch path (only this — do not dual-path):**  
**Root `ShortcutDispatcher` owns compose.** The focused compose field registers/unregisters `compose.submit` / `compose.newline` bus handlers on focus/unfocus. Remove compose matching from `Focus.onKeyEvent` (no parallel focus-node matcher). Tag the field with `ShortcutFocusKind.compose` so `inCompose` is true.

**Files:**
- Modify: `client/lib/services/keyboard/compose_keyboard_shortcut_handler.dart` — become helpers (`insertNewlineAtSelection`) + optional thin “register handlers for this field” API; delete action-enum matching
- Modify: `client/lib/widgets/compose/compose_trigger_field.dart` (and any other compose key entry points)
- Modify: `client/test/services/keyboard/compose_keyboard_shortcut_handler_test.dart`
- Delete after green: `client/lib/models/keyboard_shortcut_action.dart`, `client/lib/services/keyboard/keyboard_shortcut_bindings.dart`, `client/test/services/keyboard/keyboard_shortcut_bindings_test.dart`

- [ ] **Step 1: Rewrite compose tests for bus-handler registration**

Assert:
- On focus, registering handlers then synthesizing Enter via dispatcher invokes `onSubmit`
- Mod+Enter inserts newline
- On unfocus, handlers gone (Enter no longer submits that field)

- [ ] **Step 2: Implement registration API + wire compose field; remove old enum path**

- [ ] **Step 3: Delete old enum/bindings files; fix imports**

- [ ] **Step 4: Run** `cd client && flutter test test/services/keyboard/ test/services/commands/`

- [ ] **Step 5: Commit**

```bash
git add -A client/lib/services/keyboard client/lib/models/keyboard_shortcut_action.dart \
  client/lib/widgets/compose client/test/services/keyboard client/test/services/commands
git commit -m "$(cat <<'EOF'
refactor(compose): migrate shortcuts onto command catalog

EOF
)"
```

---

### Task 7: Layout zoom + view toggle handlers

**Files:**
- Modify: `client/lib/cubits/layout_cubit.dart` — add `zoomIn()`, `zoomOut()`, `zoomReset()`, `toggleSidebar()`, `toggleRightTools()`, `toggleWorkspaceTerminal()`
- Create: `client/lib/services/commands/layout_command_registrar.dart` (or register from app shell)
- Create: `client/test/cubits/layout_cubit_zoom_test.dart` (or extend existing layout tests)

- [ ] **Step 1: Write failing zoom step tests**

Zoom in/out: switch to `custom`, step multiplier by `0.1`. **Production clamp:** effective zoom `baseline × multiplier` must stay within `kUiZoomMin`/`kUiZoomMax` (pass baseline into the helper, or read current device baseline from the same path `UiZoom` uses). Tests may use `baseline: 1.0` but must call the same clamp helper. Reset → `standard`.

Toggles: flip the three visibility flags.

- [ ] **Step 2: Implement methods + register on CommandBus at bootstrap**

```text
CommandIds.zoomIn → layout.zoomIn
CommandIds.toggleSidebar → layout.toggleSidebar
…
```

- [ ] **Step 3: Tests PASS**

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(commands): wire layout zoom and pane toggle commands

EOF
)"
```

---

### Task 8: Session tab commands on ChatCubit

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart` — add `selectNextSessionTab()`, `selectPreviousSessionTab()` if missing (wrap `selectTab` with wraparound; no-op when `activeTabCount == 0`)
- Create: `client/lib/services/commands/session_command_registrar.dart`
- Modify: workspace “new tab” → `enterComposeMode(activeWorkspaceId)`
- Test: `client/test/cubits/chat_cubit_session_shortcut_test.dart` (or extend existing chat cubit tests)

- [ ] **Step 1: Failing tests**

Required cases (match spec semantics):
1. next/prev wrap across session tabs when a session is active
2. no-op when `activeTabCount == 0` (compose-only, no tabs)
3. **compose landing + open tabs still exist:** `composeActive == true` and `activeTabCount > 0` → next/prev still call `selectTab` from current `activeTabIndex` (which clears compose and shows that session) — do **not** no-op merely because compose is showing
4. close active session tab
5. new tab → `enterComposeMode`

- [ ] **Step 2: Implement + register handlers** (handlers need active workspace id from cubit state / tab store)

- [ ] **Step 3: PASS + commit**

```bash
git commit -m "$(cat <<'EOF'
feat(commands): wire session tab navigation commands

EOF
)"
```

---

### Task 9: Workspace chrome commands (HomeShell)

**Files:**
- Create: `client/lib/pages/home_workspace/workspace_chrome_commands.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_shell.dart`
- Modify: shortcut context builder to read `hasOpenWorkspaceTabs` from chrome host
- Test: widget or unit test for next/prev wrap / close / reopen with a fake host

- [ ] **Step 1: Define**

```dart
class WorkspaceChromeCommands {
  void Function()? nextWorkspaceTab;
  void Function()? prevWorkspaceTab;
  void Function()? closeActiveWorkspaceTab;
  void Function()? reopenClosedWorkspaceTab;
  int openTabCount = 0;
}
```

Provide via `InheritedWidget` or a service on `CommandBus` side held by shell.

- [ ] **Step 2: HomeShell initState registers bus handlers that call the private methods; dispose unregisters. Update `openTabCount` whenever `_openTabs` changes.**

`reopenClosed`: if `_recentlyClosed` is empty, no-op; else reopen the most recently closed entry (same ordering as the title-bar reopen UI) via existing `_reopenClosedTab(tabKey)`.

- [ ] **Step 3: Context `hasOpenWorkspaceTabs: openTabCount >= 1`**

- [ ] **Step 4: Manual sanity or widget test; commit**

```bash
git commit -m "$(cat <<'EOF'
feat(commands): wire HomeShell workspace tab commands

EOF
)"
```

---

### Task 10: Settings UI + cheatsheet + routes + l10n

**Files:**
- Create: `client/lib/pages/config/shortcuts_config_section.dart`
- Create: `client/lib/widgets/shortcuts/shortcut_cheatsheet_dialog.dart`
- Create: `client/lib/widgets/shortcuts/shortcut_rebind_dialog.dart` (press-to-bind; disables dispatcher while open)
- Modify: `client/lib/cubits/config_cubit.dart` — add `ConfigSection.shortcuts`
- Modify: `client/lib/router/app_router.dart` — `/config/shortcuts`
- Modify: `client/lib/pages/config/config_workspace.dart` — dialog + hub entries
- Modify: `client/lib/router/android_shell_chrome.dart` — title
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb` — all shortcut titles + settings strings
- Run: `dart run tool/gen_warmup_glyphs.dart` after ARB if required by project convention
- Register `CommandIds.showCheatsheet` → open cheatsheet dialog (needs `navigatorKey` / context from shell)

- [ ] **Step 1: Add l10n keys for every catalog command title + settings chrome**

- [ ] **Step 2: Build settings section** (search, grouped list, Change/Reset/Unbind, Reset all, Export/Import)

Export/Import: use existing file-picker / share patterns in the repo if any; otherwise write JSON to a user-chosen path via `file_selector` / `AppStorage` dialog helpers already used elsewhere — **search codebase for import/export prefs** and match that pattern.

Rebind dialog: listen raw keys; Escape cancel; Backspace unbind; on chord detect run conflict → Replace confirm.

- [ ] **Step 3: Cheatsheet dialog** — read-only grouped list of effective chords; opened by command + button on settings page

- [ ] **Step 4: Wire routes + ConfigSection**

- [ ] **Step 5: `flutter gen-l10n` (if needed) + analyze

- [ ] **Step 6: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(commands): add shortcuts settings page and cheatsheet

EOF
)"
```

---

### Task 11: Terminal focus tagging + passthrough verification

**Files:**
- Modify: agent terminal / workspace shell terminal focus wrappers (e.g. `chat_workbench_terminal.dart`, workspace terminal pane) to set `ShortcutFocusKind.terminal`
- Add: `client/test/services/commands/shortcut_context_terminal_test.dart` or widget test proving Mod+B / Ctrl+Tab match while `inTerminal: true`

- [ ] **Step 1: Tag terminal focus**

- [ ] **Step 2: Test passthrough commands match; compose.submit does not while inTerminal**

- [ ] **Step 3: If alacritty/engine eats keys first, add pre-filter in terminal key path that asks dispatcher/resolver for passthrough hit and returns handled — document in code comment why

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
fix(commands): honor terminal passthrough for workbench shortcuts

EOF
)"
```

---

### Task 12: Final verification + cleanup

**Files:** any stragglers referencing deleted shortcut types

- [x] **Step 1: Search and remove dead references**

```bash
cd client && rg "KeyboardShortcutAction|KeyboardShortcutBindings\.compose" -g '*.dart'
```

Expected: no matches

- [x] **Step 2: Run full quality gate**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  && flutter test --exclude-tags integration
```

Expected: analyze clean enough for CI norms; tests green

- [x] **Step 3: Update spec status line to Implemented (optional) and commit**

```bash
git commit -m "$(cat <<'EOF'
test(commands): verify keyboard shortcuts platform end-to-end gate

EOF
)"
```

---

## Execution notes

- Prefer **TDD** on Tasks 1–4, 6–8; UI tasks use widget tests where cheap.
- Keep files focused; do not dump settings UI into `command_catalog.dart`.
- Commit after each task as indicated.
- @superpowers:subagent-driven-development or @superpowers:executing-plans for implementation.
