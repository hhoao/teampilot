# Floating Workspace Terminal Clear and Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add **Find in terminal** and **Clear terminal** to the floating-workspace shell terminal right-click menu, with the existing overlay find bar and an engine clear that wipes scrollback plus the current screen.

**Architecture:** New `TerminalEngine.clearTerminal()` in the `flutter_alacritty` submodule (`ClearMode::Saved` then `ClearMode::All`). TeamPilot extracts the workspace-terminal context menu, adds Find/Clear items, and hosts `TerminalFindBar` via `WorkspaceTerminalFindHost` inside `WorkspaceTerminalPanel`. Chat workbench menus and title-bar buttons stay unchanged.

**Tech Stack:** Flutter / Dart, `flutter_alacritty` (FRB + Rust `alacritty_terminal`), `shared_ui` `TpActionMenu`, ARB l10n.

**Spec:** `docs/superpowers/specs/2026-10-12-floating-terminal-clear-search-design.md`

## Global Constraints

- **Never invoke `flutter test` from `client/`.** Always `cd client && dart run tool/run_tests.dart <paths/options>`.
- flutter_alacritty package tests: run from `client/packages/flutter_alacritty` (separate package cache), not from `client/`.
- **l10n:** edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only; then `cd client && flutter gen-l10n`. Never hand-edit `app_localizations*.dart`.
- Do not send `Ctrl+L` / `reset` to the PTY. Do not kill the process. Do not change `clearHistory()` / `Ctrl+Shift+K`.
- Do not unify chat-workbench and workspace-terminal menus. Do not add Clear to the chat workbench in this plan.
- `flutter_alacritty` is a **git submodule**. Tasks 1–2 commit inside that repo; later TeamPilot commits record the submodule pointer.
- Logging: `AppLogger` only; no `print`.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `client/packages/flutter_alacritty/packages/rust_lib_flutter_alacritty/rust/src/engine.rs` | VT engine; `clear_terminal()` | Modify |
| `client/packages/flutter_alacritty/packages/rust_lib_flutter_alacritty/rust/src/api/terminal.rs` | FRB API `engine_clear_terminal` | Modify |
| `client/packages/flutter_alacritty/lib/src/rust/**`, `frb_generated.rs` | Generated FRB | Regen |
| `client/packages/flutter_alacritty/lib/engine/engine_binding.dart` | `EngineBinding.clearTerminal` + FRB impl | Modify |
| `client/packages/flutter_alacritty/lib/engine/terminal_engine_client.dart` | Binding call + `refreshView()` | Modify |
| `client/packages/flutter_alacritty/lib/engine/terminal_engine.dart` | Public `clearTerminal()` | Modify |
| `client/packages/flutter_alacritty/test/fake_binding.dart` | Fake `clearTerminal` | Modify |
| `client/packages/flutter_alacritty/test/engine_client_test.dart` | Client refresh test + fake methods | Modify |
| `client/packages/flutter_alacritty/test/engine_client_resize_test.dart` | Fake methods | Modify |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | `terminalClear` | Modify |
| `client/lib/widgets/workspace_terminal/workspace_terminal_context_menu.dart` | Extracted right-click menu | Create |
| `client/lib/widgets/workspace_terminal/workspace_terminal_find_host.dart` | Find overlay + shortcuts + tab-change close | Create |
| `client/lib/widgets/workspace_terminal_panel.dart` | Wire menu + find host; drop inline menu | Modify |
| `client/test/widgets/workspace_terminal/workspace_terminal_context_menu_test.dart` | Find/Clear menu actions | Create |
| `client/test/widgets/workspace_terminal/workspace_terminal_find_host_test.dart` | Overlay show/hide/tab change | Create |

---

### Task 1: Rust `clear_terminal`

**Files:**
- Modify: `client/packages/flutter_alacritty/packages/rust_lib_flutter_alacritty/rust/src/engine.rs` (after `clear_history`, ~line 675; test next to `clear_history_drops_scrollback` ~line 2117)
- Test: same file, `#[cfg(test)]` module

**Interfaces:**
- Consumes: existing `clear_history()` / `ClearMode`.
- Produces: `pub fn clear_terminal(&mut self)` — `ClearMode::Saved` then `ClearMode::All`. Task 2's FRB function calls this.

- [ ] **Step 1: Write the failing Rust test**

In `engine.rs`, immediately after `clear_history_drops_scrollback`, add:

```rust
    #[test]
    fn clear_terminal_drops_scrollback_and_viewport() {
        let mut e = TerminalEngine::new(10, 2, EngineConfig::defaults());
        e.advance(b"a\r\nb\r\nc\r\nd\r\ne\r\nf\r\n".to_vec());
        e.scroll_lines(100);
        let before = e.full_snapshot();
        assert!(before.display_offset > 0 || before.history_size > 0);
        let filled = before
            .lines
            .iter()
            .any(|l| (0..l.len()).any(|c| l.cell(c).codepoint == b'a' as u32
                || l.cell(c).codepoint == b'b' as u32
                || l.cell(c).codepoint == b'c' as u32
                || l.cell(c).codepoint == b'd' as u32
                || l.cell(c).codepoint == b'e' as u32
                || l.cell(c).codepoint == b'f' as u32));
        assert!(filled, "precondition: viewport/history must contain letters");

        e.clear_terminal();

        let after = e.full_snapshot();
        assert_eq!(after.display_offset, 0);
        assert_eq!(after.history_size, 0);
        let leftover = after.lines.iter().any(|l| {
            (0..l.len()).any(|c| {
                let cp = l.cell(c).codepoint;
                cp == b'a' as u32
                    || cp == b'b' as u32
                    || cp == b'c' as u32
                    || cp == b'd' as u32
                    || cp == b'e' as u32
                    || cp == b'f' as u32
            })
        });
        assert!(!leftover, "clear_terminal must blank letter cells");
    }
```

Leave `clear_history_drops_scrollback` unchanged.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client/packages/flutter_alacritty/packages/rust_lib_flutter_alacritty/rust
cargo test --lib clear_terminal_drops_scrollback_and_viewport -- --exact
```

Expected: compile error `no method named clear_terminal`.

- [ ] **Step 3: Implement `clear_terminal`**

Immediately after `clear_history` in `engine.rs`:

```rust
    pub fn clear_history(&mut self) {
        use alacritty_terminal::vte::ansi::{ClearMode, Handler};
        self.term.clear_screen(ClearMode::Saved);
    }

    pub fn clear_terminal(&mut self) {
        use alacritty_terminal::vte::ansi::{ClearMode, Handler};
        self.term.clear_screen(ClearMode::Saved);
        self.term.clear_screen(ClearMode::All);
    }
```

Do not change `clear_history`.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd client/packages/flutter_alacritty/packages/rust_lib_flutter_alacritty/rust
cargo test --lib clear_history_drops_scrollback -- --exact
cargo test --lib clear_terminal_drops_scrollback_and_viewport -- --exact
```

Expected: both PASS. If `history_size` is not zero because of how alacritty counts the live grid, drop the `history_size` assertion and keep `display_offset == 0` plus the leftover-letter check — do not weaken the letter check.

- [ ] **Step 5: Commit in the flutter_alacritty submodule**

```bash
cd client/packages/flutter_alacritty
git add packages/rust_lib_flutter_alacritty/rust/src/engine.rs
git commit -m "$(cat <<'EOF'
feat: add clear_terminal for scrollback and screen

EOF
)"
```

---

### Task 2: Dart / FRB `clearTerminal` wiring

**Files:**
- Modify: `client/packages/flutter_alacritty/packages/rust_lib_flutter_alacritty/rust/src/api/terminal.rs` (after `engine_clear_history`, ~line 199)
- Regen: FRB outputs under `client/packages/flutter_alacritty/lib/src/rust/` and `packages/rust_lib_flutter_alacritty/rust/src/frb_generated.rs`
- Modify: `client/packages/flutter_alacritty/lib/engine/engine_binding.dart` (`EngineBinding` ~line 35, `FrbEngineBinding` ~line 187)
- Modify: `client/packages/flutter_alacritty/lib/engine/terminal_engine_client.dart` (~line 385)
- Modify: `client/packages/flutter_alacritty/lib/engine/terminal_engine.dart` (~line 396)
- Modify: `client/packages/flutter_alacritty/test/fake_binding.dart` (~line 233)
- Modify: `client/packages/flutter_alacritty/test/engine_client_test.dart` (three fakes + new test)
- Modify: `client/packages/flutter_alacritty/test/engine_client_resize_test.dart` (two fakes)

**Interfaces:**
- Consumes: Task 1 `TerminalEngine.clear_terminal`.
- Produces: `void EngineBinding.clearTerminal()`; `TerminalEngineClient.clearTerminal()` (binding + `refreshView()`); `TerminalEngine.clearTerminal()` no-op until bound. TeamPilot Task 5 calls `entry.session.engine.clearTerminal()`.

- [ ] **Step 1: Write the failing Dart client test**

In `engine_client_test.dart`, add `int clearTerminalCalls = 0;` and `@override void clearTerminal() { clearTerminalCalls++; }` on `_FakeBinding` (next to `clearHistory`). On `_SearchFake` and `_SlowFakeBinding` add `@override void clearTerminal() {}` next to each `clearHistory`.

Append inside `main()`:

```dart
  test('clearTerminal calls binding and refreshes the view', () {
    final binding = _FakeBinding();
    final grid = MirrorGrid();
    grid.initializeEmpty(1, 1);
    final client = TerminalEngineClient(binding: binding, grid: grid);
    final gen0 = grid.generation;

    client.clearTerminal();

    expect(binding.clearTerminalCalls, 1);
    expect(grid.generation, greaterThan(gen0));
  });
```

In `fake_binding.dart` and `engine_client_resize_test.dart`, add `@override void clearTerminal() {}` next to every `clearHistory()` so those files still compile once the interface gains the method.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client/packages/flutter_alacritty
flutter test test/engine_client_test.dart --name "clearTerminal calls binding"
```

Expected: compile error `The method 'clearTerminal' isn't defined for the type 'TerminalEngineClient'` (and/or `EngineBinding`).

- [ ] **Step 3: Add the FRB rust entry**

In `api/terminal.rs`, immediately after `engine_clear_history`:

```rust
#[frb(sync)]
pub fn engine_clear_history(engine: &mut TerminalEngine) {
    engine.clear_history();
}

#[frb(sync)]
pub fn engine_clear_terminal(engine: &mut TerminalEngine) {
    engine.clear_terminal();
}
```

From `client/packages/flutter_alacritty`:

```bash
flutter_rust_bridge_codegen generate
```

Confirm generated Dart exports `engineClearTerminal` (same shape as `engineClearHistory` in `lib/src/rust/api/terminal.dart`).

- [ ] **Step 4: Implement Dart layers**

`EngineBinding` — add next to `clearHistory()`:

```dart
  void clearHistory();
  void clearTerminal();
```

`FrbEngineBinding`:

```dart
  @override
  void clearHistory() => engineClearHistory(engine: _engine);

  @override
  void clearTerminal() => engineClearTerminal(engine: _engine);
```

`TerminalEngineClient`, next to `clearHistory`:

```dart
  void clearHistory() {
    _binding.clearHistory();
    refreshView();
  }

  void clearTerminal() {
    _binding.clearTerminal();
    refreshView();
  }
```

`TerminalEngine`, next to `clearHistory`:

```dart
  /// Clear scrollback history (alacritty ClearHistory). No-op until bound.
  void clearHistory() => _client?.clearHistory();

  /// Clear scrollback and the current screen. Does not write to the PTY.
  /// No-op until bound.
  void clearTerminal() => _client?.clearTerminal();
```

- [ ] **Step 5: Run the Dart tests**

```bash
cd client/packages/flutter_alacritty
flutter test test/engine_client_test.dart --name "clearTerminal calls binding"
```

Expected: PASS.

- [ ] **Step 6: Commit in the flutter_alacritty submodule**

```bash
cd client/packages/flutter_alacritty
git add packages/rust_lib_flutter_alacritty/rust/src/api/terminal.rs \
  packages/rust_lib_flutter_alacritty/rust/src/frb_generated.rs \
  lib/src/rust lib/engine/engine_binding.dart \
  lib/engine/terminal_engine_client.dart lib/engine/terminal_engine.dart \
  test/fake_binding.dart test/engine_client_test.dart \
  test/engine_client_resize_test.dart
git commit -m "$(cat <<'EOF'
feat: expose clearTerminal through FRB and Dart engine

EOF
)"
```

---

### Task 3: l10n `terminalClear`

**Files:**
- Modify: `client/lib/l10n/app_en.arb` (next to `"terminalFind"`)
- Modify: `client/lib/l10n/app_zh.arb` (next to `"terminalFind"`)

**Interfaces:**
- Consumes: nothing.
- Produces: `AppLocalizations.terminalClear` — en `Clear terminal`, zh `清除终端`. Task 4 reads `context.l10n.terminalClear`.

- [ ] **Step 1: Add ARB keys**

In `app_en.arb`, immediately after `"terminalFindNoResults"`:

```json
  "terminalFind": "Find in terminal",
  "terminalFindNoResults": "No results",
  "terminalClear": "Clear terminal",
```

In `app_zh.arb`:

```json
  "terminalFind": "在终端中查找",
  "terminalFindNoResults": "无匹配",
  "terminalClear": "清除终端",
```

- [ ] **Step 2: Generate l10n**

```bash
cd client && flutter gen-l10n
```

Expected: `terminalClear` appears on `AppLocalizations`. Do not edit `app_localizations*.dart` by hand.

- [ ] **Step 3: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart
git commit -m "$(cat <<'EOF'
feat: add terminalClear l10n string

EOF
)"
```

---

### Task 4: Workspace terminal context menu (Find + Clear)

**Files:**
- Create: `client/lib/widgets/workspace_terminal/workspace_terminal_context_menu.dart`
- Modify: `client/lib/widgets/workspace_terminal_panel.dart` (replace `_showContextMenu` ~427–531 with a call to the extracted function)
- Test: `client/test/widgets/workspace_terminal/workspace_terminal_context_menu_test.dart`

**Interfaces:**
- Consumes: Task 3 `l10n.terminalClear`; existing `l10n.terminalFind`.
- Produces: `Future<void> showWorkspaceTerminalContextMenu({...})` with `onFindRequested` and `onClearTerminal`. Task 5 passes those callbacks.

- [ ] **Step 1: Write the failing widget tests**

Create `client/test/widgets/workspace_terminal/workspace_terminal_context_menu_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/workspace_terminal/workspace_terminal_context_menu.dart';

import '../../support/rust_lib_test_init.dart';

Widget _harness({
  required TerminalController controller,
  required TerminalEngine engine,
  required VoidCallback onFind,
  required VoidCallback onClear,
}) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                onPressed: () {
                  showWorkspaceTerminalContextMenu(
                    context: context,
                    menuContext: context,
                    terminalController: controller,
                    engine: engine,
                    globalPosition: const Offset(80, 80),
                    cellOffset: null,
                    onFindRequested: onFind,
                    onClearTerminal: onClear,
                    onOpenLink: (_) async {},
                    onAskAi: (_) async {},
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(initRustLibForTests);

  late TerminalEngine engine;
  late TerminalController controller;

  setUp(() {
    engine = TerminalEngine(config: TerminalConfig.defaults());
    controller = TerminalController()..attach(engine);
  });

  tearDown(() {
    controller.dispose();
    engine.dispose();
  });

  testWidgets('menu lists Find and Clear', (tester) async {
    await tester.pumpWidget(
      _harness(
        controller: controller,
        engine: engine,
        onFind: () {},
        onClear: () {},
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Find in terminal'), findsOneWidget);
    expect(find.text('Clear terminal'), findsOneWidget);
  });

  testWidgets('choosing Find calls onFindRequested', (tester) async {
    var findCalls = 0;
    await tester.pumpWidget(
      _harness(
        controller: controller,
        engine: engine,
        onFind: () => findCalls++,
        onClear: () {},
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find in terminal'));
    await tester.pumpAndSettle();
    expect(findCalls, 1);
  });

  testWidgets('choosing Clear calls onClearTerminal', (tester) async {
    var clearCalls = 0;
    await tester.pumpWidget(
      _harness(
        controller: controller,
        engine: engine,
        onFind: () {},
        onClear: () => clearCalls++,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear terminal'));
    await tester.pumpAndSettle();
    expect(clearCalls, 1);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd client && dart run tool/run_tests.dart \
  test/widgets/workspace_terminal/workspace_terminal_context_menu_test.dart
```

Expected: compile error — `workspace_terminal_context_menu.dart` does not exist.

- [ ] **Step 3: Implement the extracted menu**

Create `client/lib/widgets/workspace_terminal/workspace_terminal_context_menu.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/input/paste.dart' as alacritty_paste;
import 'package:flutter_alacritty/input/term_mode.dart' show anyMouse;
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/selection_ai/selection_ai_context.dart';
import '../../services/selection_ai/selection_ai_menu_specs.dart';

/// Right-click menu for the floating workspace shell terminal.
Future<void> showWorkspaceTerminalContextMenu({
  required BuildContext context,
  required BuildContext menuContext,
  required TerminalController terminalController,
  required TerminalEngine engine,
  required Offset globalPosition,
  required CellOffset? cellOffset,
  required VoidCallback onFindRequested,
  required VoidCallback onClearTerminal,
  required Future<void> Function(String link) onOpenLink,
  required Future<void> Function(String aiContext) onAskAi,
}) async {
  final mloc = MaterialLocalizations.of(menuContext);
  final hasSelection = terminalController.selectionActive;
  final selectionText = terminalController.readSelectionText() ?? '';
  final aiContext = buildTerminalAiContextClipboardText(
    surfaceLabel: 'workspace-shell',
    text: selectionText,
  );
  final hasAi = aiContext.isNotEmpty;
  final mouseReporting = anyMouse(engine.grid.modeFlags);
  final linkUri = cellOffset != null
      ? engine.hyperlinkAt(cellOffset.row, cellOffset.column)
      : null;
  final specs = <TpActionMenuSpec>[
    TpActionMenuSpec.item(
      value: 'find',
      icon: Icons.search,
      label: context.l10n.terminalFind,
    ),
    TpActionMenuSpec.item(
      value: 'clear',
      icon: Icons.cleaning_services_outlined,
      label: context.l10n.terminalClear,
    ),
    if (linkUri != null)
      TpActionMenuSpec.item(
        value: 'openLink',
        icon: Icons.link,
        label: context.l10n.terminalOpenLink,
      ),
    if (linkUri != null) const TpActionMenuSpec.divider(),
    TpActionMenuSpec.item(
      value: 'paste',
      icon: Icons.content_paste,
      label: mloc.pasteButtonLabel,
    ),
    TpActionMenuSpec.item(
      value: 'copy',
      icon: Icons.content_copy,
      label: (!hasSelection && mouseReporting)
          ? menuContext.l10n.terminalCopySelectHint
          : mloc.copyButtonLabel,
      enabled: hasSelection,
    ),
    ...selectionAiMenuSpecs(
      l10n: menuContext.l10n,
      copyEnabled: hasAi,
      askAiEnabled: hasAi,
      onCopyAsAiContext: () {
        unawaited(Clipboard.setData(ClipboardData(text: aiContext)));
      },
      onAskAi: () {
        unawaited(onAskAi(aiContext));
      },
    ),
    TpActionMenuSpec.item(
      value: 'selectAll',
      icon: Icons.select_all,
      label: mloc.selectAllButtonLabel,
    ),
  ];

  final selected = await showTpActionMenuFromSpecs<String>(
    context: menuContext,
    globalPosition: globalPosition,
    popUpAnimationStyle: const AnimationStyle(duration: Duration.zero),
    specs: specs,
  );
  if (!menuContext.mounted) return;
  switch (selected) {
    case 'find':
      onFindRequested();
    case 'clear':
      onClearTerminal();
    case 'openLink':
      if (linkUri != null) {
        await onOpenLink(linkUri);
      }
    case 'paste':
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text != null && text.isNotEmpty) {
        terminalController.onTerminalInputStart();
        engine.write(
          alacritty_paste.pasteBytes(text, modeFlags: engine.grid.modeFlags),
        );
        terminalController.clearSelection();
      }
    case 'copy':
      final text = terminalController.readSelectionText();
      if (text != null && text.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: text));
      }
    case 'selectAll':
      await terminalController.selectAll();
    default:
      break;
  }
}
```

Replace `_showContextMenu` in `workspace_terminal_panel.dart` with:

```dart
  Future<void> _showContextMenu(
    BuildContext menuContext,
    WorkspaceTerminalEntry entry,
    Offset globalPosition,
    CellOffset? cellOffset,
  ) async {
    final homeFs = context.read<HomeStorage>().fs;
    _menuOpen.value = true;
    try {
      await showWorkspaceTerminalContextMenu(
        context: context,
        menuContext: menuContext,
        terminalController: entry.controller,
        engine: entry.session.engine,
        globalPosition: globalPosition,
        cellOffset: cellOffset,
        onFindRequested: () {},
        onClearTerminal: () {
          entry.controller.clearSelection();
          entry.controller.searchClear();
          entry.session.engine.clearTerminal();
        },
        onOpenLink: (link) => TerminalUriOpener.open(
          link,
          workingDirectory: entry.cwd,
          fs: homeFs,
        ),
        onAskAi: _openAskAi,
      );
    } finally {
      if (mounted) _menuOpen.value = false;
    }
    if (!menuContext.mounted) return;
    _refocusTerminal();
  }
```

Task 5 replaces `onFindRequested: () {}` with `_findHostKey.currentState?.openFind()`. Do **not** leave `_showContextMenu` inline in the panel.

Remove unused imports from the panel that only the extracted menu needed (`alacritty_paste`, `anyMouse`, `selection_ai_menu_specs`, `Clipboard` if unused). Keep `HomeStorage`, `TerminalUriOpener`, `selection_ai_context` if `_openAskAi` still needs them.

- [ ] **Step 4: Run the widget tests**

```bash
cd client && dart run tool/run_tests.dart \
  test/widgets/workspace_terminal/workspace_terminal_context_menu_test.dart
```

Expected: PASS.

- [ ] **Step 5: Analyze the touched Dart**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/widgets/workspace_terminal/workspace_terminal_context_menu.dart \
  lib/widgets/workspace_terminal_panel.dart \
  test/widgets/workspace_terminal/workspace_terminal_context_menu_test.dart
```

Expected: no issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/widgets/workspace_terminal/workspace_terminal_context_menu.dart \
  client/lib/widgets/workspace_terminal_panel.dart \
  client/test/widgets/workspace_terminal/workspace_terminal_context_menu_test.dart \
  client/packages/flutter_alacritty
git commit -m "$(cat <<'EOF'
feat: add find and clear to workspace terminal menu

EOF
)"
```

---

### Task 5: Find overlay host + panel wiring

**Files:**
- Create: `client/lib/widgets/workspace_terminal/workspace_terminal_find_host.dart`
- Modify: `client/lib/widgets/workspace_terminal_panel.dart` (`build` active-session branch ~599–625)
- Test: `client/test/widgets/workspace_terminal/workspace_terminal_find_host_test.dart`

**Interfaces:**
- Consumes: Task 2 `engine.clearTerminal()` (already called from the menu callback); existing `TerminalFindBar` / `TerminalFindShortcuts`.
- Produces: `WorkspaceTerminalFindHostState.openFind()`; changing `activeEntryId` or `controller` closes Find and `searchClear()`s the previous controller. Shortcuts: `Ctrl+Shift+F`, `F3`, `Shift+F3`, `Esc`. Overlay insets `top/left/right: 8` (not chat's `top: 48`).

- [ ] **Step 1: Write the failing find-host tests**

Create `client/test/widgets/workspace_terminal/workspace_terminal_find_host_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/terminal_find_bar.dart';
import 'package:teampilot/widgets/workspace_terminal/workspace_terminal_find_host.dart';

import '../../support/rust_lib_test_init.dart';

Widget _harness({
  required GlobalKey<WorkspaceTerminalFindHostState> key,
  required TerminalEngine engine,
  required TerminalController controller,
  required String activeEntryId,
}) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: Scaffold(
        body: WorkspaceTerminalFindHost(
          key: key,
          engine: engine,
          controller: controller,
          activeEntryId: activeEntryId,
          child: const SizedBox.expand(child: Text('term')),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(initRustLibForTests);

  late TerminalEngine engine;
  late TerminalController controller;
  final key = GlobalKey<WorkspaceTerminalFindHostState>();

  setUp(() {
    engine = TerminalEngine(config: TerminalConfig.defaults());
    controller = TerminalController()..attach(engine);
  });

  tearDown(() {
    controller.dispose();
    engine.dispose();
  });

  testWidgets('openFind shows TerminalFindBar', (tester) async {
    await tester.pumpWidget(
      _harness(
        key: key,
        engine: engine,
        controller: controller,
        activeEntryId: 'a',
      ),
    );
    expect(find.byType(TerminalFindBar), findsNothing);
    key.currentState!.openFind();
    await tester.pumpAndSettle();
    expect(find.byType(TerminalFindBar), findsOneWidget);
    expect(find.text('Find in terminal'), findsOneWidget);
  });

  testWidgets('close hides TerminalFindBar', (tester) async {
    await tester.pumpWidget(
      _harness(
        key: key,
        engine: engine,
        controller: controller,
        activeEntryId: 'a',
      ),
    );
    key.currentState!.openFind();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(TerminalFindBar), findsNothing);
  });

  testWidgets('changing activeEntryId hides the bar', (tester) async {
    await tester.pumpWidget(
      _harness(
        key: key,
        engine: engine,
        controller: controller,
        activeEntryId: 'a',
      ),
    );
    key.currentState!.openFind();
    await tester.pumpAndSettle();
    expect(find.byType(TerminalFindBar), findsOneWidget);

    await tester.pumpWidget(
      _harness(
        key: key,
        engine: engine,
        controller: controller,
        activeEntryId: 'b',
      ),
    );
    await tester.pump();
    expect(find.byType(TerminalFindBar), findsNothing);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd client && dart run tool/run_tests.dart \
  test/widgets/workspace_terminal/workspace_terminal_find_host_test.dart
```

Expected: compile error — `workspace_terminal_find_host.dart` does not exist.

- [ ] **Step 3: Implement `WorkspaceTerminalFindHost`**

Create `client/lib/widgets/workspace_terminal/workspace_terminal_find_host.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../l10n/l10n_extensions.dart';
import '../terminal_find_bar.dart';

/// Overlay find bar + shortcuts for one workspace-terminal session.
class WorkspaceTerminalFindHost extends StatefulWidget {
  const WorkspaceTerminalFindHost({
    required this.engine,
    required this.controller,
    required this.activeEntryId,
    required this.child,
    super.key,
  });

  final TerminalEngine engine;
  final TerminalController controller;
  final String activeEntryId;
  final Widget child;

  @override
  State<WorkspaceTerminalFindHost> createState() =>
      WorkspaceTerminalFindHostState();
}

class WorkspaceTerminalFindHostState extends State<WorkspaceTerminalFindHost> {
  var _findVisible = false;

  bool get findVisible => _findVisible;

  void openFind() {
    if (_findVisible) return;
    setState(() => _findVisible = true);
  }

  void _closeFind({required TerminalController controller}) {
    controller.searchClear();
    if (!_findVisible) return;
    setState(() => _findVisible = false);
  }

  @override
  void didUpdateWidget(WorkspaceTerminalFindHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final entryChanged = oldWidget.activeEntryId != widget.activeEntryId;
    final controllerChanged = oldWidget.controller != widget.controller;
    if (entryChanged || controllerChanged) {
      oldWidget.controller.searchClear();
      _findVisible = false;
    }
  }

  @override
  void dispose() {
    widget.controller.searchClear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TerminalFindShortcuts(
      findVisible: _findVisible,
      onToggleFind: openFind,
      onFindNext: () {
        widget.controller.searchNext();
        setState(() {});
      },
      onFindPrevious: () {
        widget.controller.searchPrev();
        setState(() {});
      },
      onCloseFind: () => _closeFind(controller: widget.controller),
      child: Stack(
        children: [
          widget.child,
          if (_findVisible)
            Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: TerminalFindBar(
                engine: widget.engine,
                controller: widget.controller,
                searchLabel: context.l10n.terminalFind,
                noResultsLabel: context.l10n.terminalFindNoResults,
                onClose: () => _closeFind(controller: widget.controller),
              ),
            ),
        ],
      ),
    );
  }
}
```

In `workspace_terminal_panel.dart` `build`, wrap the active-session `terminalBody` (the `ValueListenableBuilder` / `SelectionAskAiFabHost` tree) with:

```dart
        terminalBody = WorkspaceTerminalFindHost(
          key: _findHostKey,
          engine: active.session.engine,
          controller: active.controller,
          activeEntryId: active.id,
          child: ValueListenableBuilder<bool>(
            valueListenable: _menuOpen,
            child: terminalView,
            builder: (context, menuOpen, child) {
              return SelectionAskAiFabHost(
                listenable: active.controller,
                selectionActive: () => active.controller.selectionActive,
                readAiContext: () => buildTerminalAiContextClipboardText(
                  surfaceLabel: 'workspace-shell',
                  text: active.controller.readSelectionText() ?? '',
                ),
                onAskAi: _openAskAi,
                menuOpen: menuOpen,
                child: child!,
              );
            },
          ),
        );
```

On `_WorkspaceTerminalPanelState` add:

```dart
  final _findHostKey = GlobalKey<WorkspaceTerminalFindHostState>();
```

Change the Task 4 `onFindRequested: () {}` to:

```dart
        onFindRequested: () => _findHostKey.currentState?.openFind(),
```

Import the find host. Do not put Find UI inside `terminal_floating_surface.dart`.

- [ ] **Step 4: Run find-host and context-menu tests**

```bash
cd client && dart run tool/run_tests.dart \
  test/widgets/workspace_terminal/workspace_terminal_find_host_test.dart
cd client && dart run tool/run_tests.dart \
  test/widgets/workspace_terminal/workspace_terminal_context_menu_test.dart
```

Expected: both PASS.

- [ ] **Step 5: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/widgets/workspace_terminal/workspace_terminal_find_host.dart \
  lib/widgets/workspace_terminal_panel.dart \
  test/widgets/workspace_terminal/
```

Expected: no issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/widgets/workspace_terminal/workspace_terminal_find_host.dart \
  client/lib/widgets/workspace_terminal_panel.dart \
  client/test/widgets/workspace_terminal/workspace_terminal_find_host_test.dart
git commit -m "$(cat <<'EOF'
feat: overlay find bar on floating workspace terminals

EOF
)"
```

---

### Task 6: Final verification

**Files:** none new.

**Interfaces:** none.

- [ ] **Step 1: Analyze the client**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no issues.

- [ ] **Step 2: Full test suite (background, once)**

```bash
cd client && dart run tool/run_tests.dart
```

Expected: suite completes with no new failures. Do not claim done until this finishes.

- [ ] **Step 3: Manual check (if a desktop build is available)**

1. Open a floating workspace terminal.
2. Right-click: **Find in terminal** and **Clear terminal** at the top.
3. Find opens the overlay; `Ctrl+Shift+F` / `Esc` work; matches highlight in this tab only.
4. Clear wipes scrollback and the visible screen; the shell process keeps running.
5. Chat workbench terminal menu is unchanged (still has Find, still has no Clear).

---

## Spec coverage

| Spec requirement | Task |
|---|---|
| Right-click Find | Task 4 |
| Right-click Clear | Task 4 |
| Clear = scrollback + current screen, no PTY write | Tasks 1–2, menu callback in Task 4 |
| `clearHistory` / Ctrl+Shift+K unchanged | Task 1 (untouched) |
| Overlay find bar + Ctrl+Shift+F / F3 / Esc | Task 5 |
| Overlay `top: 8` (not 48) | Task 5 |
| Tab change closes Find + searchClear | Task 5 `didUpdateWidget` |
| After clear: clear selection + searchClear, bar stays | Task 4 `onClearTerminal` |
| l10n `terminalClear` | Task 3 |
| Extract menu out of panel | Task 4 |
| No title-bar buttons / no chat-menu unify | omitted |
| Rust + Dart engine tests | Tasks 1–2 |
| Menu + find-host widget tests | Tasks 4–5 |
| analyze + full `run_tests.dart` | Task 6 |
