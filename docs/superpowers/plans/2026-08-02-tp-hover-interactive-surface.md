# TpHover Interactive Surface + Click-Cursor Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strengthen `TpHover`/`TpHoverRow` as the canonical clickable-chrome primitive (click cursor + huji-parity knobs), recompose `TpTabChip` on it, and migrate eligible hand-rolled hover surfaces across the TeamPilot app and `ai_message_ui`.

**Architecture:** Lean `TpHover` owns interaction only (cursor, hover/idle fill, enabled, long-press, secondary-tap-down, optional press scale). Selected borders/accents/shadows stay in specialized widgets; hosts pass selected idle fill via `backgroundColor`. Migration replaces bare `MouseRegion`+`_hovered` stacks on clickable chrome; exclude drag/resize/terminal/vendored/hover-only probes.

**Tech Stack:** Flutter / Dart, `shared_ui` (`TpTheme`, `TpTextStyles`), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-02-tp-hover-interactive-surface-design.md`

**Commits:** Only when the user asks (if `shared_ui` is a submodule, commit there first, then the app).

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/shared_ui/lib/src/components/hover/tp_hover.dart` | Canonical interactive chrome wrapper |
| `client/packages/shared_ui/lib/src/components/hover/tp_hover_row.dart` | Full-width row + trailing-on-hover; forwards new `TpHover` knobs |
| `client/packages/shared_ui/lib/src/components/tab/tp_tab_chip.dart` | Chip shell composes `TpHover`; owns accent/border/chrome fade |
| `client/packages/shared_ui/test/components/hover/tp_hover_test.dart` | New widget tests for `TpHover` |
| `client/packages/shared_ui/test/components/hover/tp_hover_row_test.dart` | New/extended `TpHoverRow` tests |
| `client/packages/shared_ui/test/components/tab/tp_tab_chip_test.dart` | Extend chip tests (cursor, secondary, chrome) |
| `client/packages/shared_ui/README.md` | Convention: prefer `TpHover` for onTap chrome |
| App / `ai_message_ui` files listed in Tasks 5–9 | Migrate eligible `_hovered` / bare `MouseRegion` sites |

**Reference implementation:** huji `huji-app/packages/shared_ui/lib/src/components/hover/tp_hover.dart` (parity minus TeamPilot-only `onSecondaryTapDown`).

---

### Task 1: Extend `TpHover` (TDD)

**Files:**
- Create: `client/packages/shared_ui/test/components/hover/tp_hover_test.dart`
- Modify: `client/packages/shared_ui/lib/src/components/hover/tp_hover.dart`

- [ ] **Step 1: Write failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('click cursor when onTap set', (tester) async {
    await tester.pumpWidget(
      wrap(TpHover(onTap: () {}, child: const Text('x'))),
    );
    final region = tester.widget<MouseRegion>(find.byType(MouseRegion));
    expect(region.cursor, SystemMouseCursors.click);
  });

  testWidgets('basic cursor when non-interactive', (tester) async {
    await tester.pumpWidget(wrap(const TpHover(child: Text('x'))));
    final region = tester.widget<MouseRegion>(find.byType(MouseRegion));
    expect(region.cursor, SystemMouseCursors.basic);
  });

  testWidgets('basic cursor when disabled even with onTap', (tester) async {
    await tester.pumpWidget(
      wrap(TpHover(enabled: false, onTap: () {}, child: const Text('x'))),
    );
    final region = tester.widget<MouseRegion>(find.byType(MouseRegion));
    expect(region.cursor, SystemMouseCursors.basic);
  });

  testWidgets('backgroundColor shows when not hovered', (tester) async {
    await tester.pumpWidget(
      wrap(
        TpHover(
          backgroundColor: const Color(0xFF112233),
          child: const SizedBox(width: 40, height: 20),
        ),
      ),
    );
    final box = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    final deco = box.decoration! as BoxDecoration;
    expect(deco.color, const Color(0xFF112233));
  });

  testWidgets('onHoverChanged and hover fill', (tester) async {
    final events = <bool>[];
    await tester.pumpWidget(
      wrap(
        TpHover(
          hoverColor: const Color(0xFF445566),
          onHoverChanged: events.add,
          onTap: () {},
          child: const SizedBox(width: 40, height: 20, key: Key('target')),
        ),
      ),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byKey(const Key('target'))));
    await tester.pumpAndSettle();
    expect(events, contains(true));
    final box = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    expect((box.decoration! as BoxDecoration).color, const Color(0xFF445566));
  });

  testWidgets('forceHover shows hover fill without pointer', (tester) async {
    await tester.pumpWidget(
      wrap(
        TpHover(
          forceHover: true,
          hoverColor: const Color(0xFF778899),
          child: const SizedBox(width: 40, height: 20),
        ),
      ),
    );
    final box = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    expect((box.decoration! as BoxDecoration).color, const Color(0xFF778899));
  });

  testWidgets('enabled false ignores hover enter', (tester) async {
    final events = <bool>[];
    await tester.pumpWidget(
      wrap(
        TpHover(
          enabled: false,
          backgroundColor: const Color(0xFF112233),
          hoverColor: const Color(0xFF445566),
          onHoverChanged: events.add,
          onTap: () {},
          child: const SizedBox(width: 40, height: 20, key: Key('target')),
        ),
      ),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byKey(const Key('target'))));
    await tester.pumpAndSettle();
    expect(events, isEmpty);
    final box = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    expect((box.decoration! as BoxDecoration).color, const Color(0xFF112233));
  });

  testWidgets('onSecondaryTapDown delivers details', (tester) async {
    TapDownDetails? details;
    await tester.pumpWidget(
      wrap(
        TpHover(
          onSecondaryTapDown: (d) => details = d,
          child: const SizedBox(width: 80, height: 40, key: Key('target')),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const Key('target')),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    expect(details, isNotNull);
  });

  testWidgets('onLongPress fires', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      wrap(
        TpHover(
          onLongPress: () => pressed = true,
          child: const SizedBox(width: 80, height: 40, key: Key('target')),
        ),
      ),
    );
    await tester.longPress(find.byKey(const Key('target')));
    expect(pressed, isTrue);
  });

  testWidgets('pressScale wraps with AnimatedScale when not 1.0', (tester) async {
    await tester.pumpWidget(
      wrap(
        TpHover(
          pressScale: 0.97,
          onTap: () {},
          child: const Text('x'),
        ),
      ),
    );
    expect(find.byType(AnimatedScale), findsOneWidget);
  });
}
```

Add `import 'package:flutter/foundation.dart';` only if needed; use `import 'dart:ui' show PointerDeviceKind;` and `import 'package:flutter/gestures.dart';` for `kSecondaryButton`.

- [ ] **Step 2: Run tests — expect FAIL** (missing params / old fill always transparent when not hovered)

```bash
cd client/packages/shared_ui && flutter test test/components/hover/tp_hover_test.dart
```

Expected: compile errors and/or assertion failures on `backgroundColor` / `enabled` / `onSecondaryTapDown`.

- [ ] **Step 3: Implement `TpHover` to match spec**

Port huji behavior and add `onSecondaryTapDown`:

- Fields: `backgroundColor`, `enabled`, `onLongPress`, `onSecondaryTapDown`, `pressScale`
- `_interactive` when `enabled` and any of `onTap` / `onSecondaryTap` / `onSecondaryTapDown` / `onLongPress` non-null
- Fill: disabled ⇒ never hover fill; else hover/`forceHover` ⇒ `hoverColor ?? defaultHoverColor`; else `backgroundColor ?? transparent`
- `GestureDetector`: wire `onSecondaryTapDown`, `onLongPress`, press scale tap down/up/cancel
- `MouseRegion`: `onEnter` only if `enabled`; clear pressed on exit; set `cursor`

- [ ] **Step 4: Re-run tests — expect PASS**

```bash
cd client/packages/shared_ui && flutter test test/components/hover/tp_hover_test.dart
```

- [ ] **Step 5: Commit only if user requested**

---

### Task 2: Forward knobs on `TpHoverRow` + tests

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/hover/tp_hover_row.dart`
- Create: `client/packages/shared_ui/test/components/hover/tp_hover_row_test.dart`

- [ ] **Step 1: Write failing/extended tests**

Cover:
1. Trailing appears after mouse enter (desktop).
2. `forceShowTrailing: true` shows trailing without hover.
3. On Android (`debugDefaultTargetPlatformOverride = TargetPlatform.android`), trailing stays visible without hover when `showTrailingOnMobile: true`.
4. `backgroundColor` / `enabled: false` / `onLongPress` / `onSecondaryTapDown` are accepted and forwarded (tap-down or long-press smoke).

- [ ] **Step 2: Run — expect FAIL** on new constructor params

```bash
cd client/packages/shared_ui && flutter test test/components/hover/tp_hover_row_test.dart
```

- [ ] **Step 3: Extend `TpHoverRow` API**

Add and forward to inner `TpHover`:

- `backgroundColor`
- `enabled` (default `true`)
- `onLongPress`
- `onSecondaryTap`
- `onSecondaryTapDown`
- `cursor` (optional)
- `forceHover` (optional; useful when menu open keeps row tint)

Keep existing trailing visibility logic.

- [ ] **Step 4: Re-run — expect PASS**

- [ ] **Step 5: Commit only if user requested**

---

### Task 3: Recompose `TpTabChip` on `TpHover`

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/tab/tp_tab_chip.dart`
- Modify: `client/packages/shared_ui/test/components/tab/tp_tab_chip_test.dart`

**Locked active-hover behavior:** when `active`, set both `backgroundColor` and `hoverColor` to `cs.surfaceContainerHigh` so the fill does not flash on hover. When inactive: `backgroundColor: null`, `hoverColor: cs.onSurface.withValues(alpha: 0.05)`.

- [ ] **Step 1: Extend chip tests**

Add:
1. Outer `MouseRegion` (via `TpHover`) uses `SystemMouseCursors.click`.
2. `onSecondaryTapDown` fires with details.
3. `forceShowChrome: true` keeps close icon hittable / opacity visible without hover.
4. Existing tap/close + preview tests still pass.

- [ ] **Step 2: Run — may FAIL or still PASS until recompose; keep tests red/green intentional**

```bash
cd client/packages/shared_ui && flutter test test/components/tab/tp_tab_chip_test.dart
```

- [ ] **Step 3: Replace outer `MouseRegion`/`GestureDetector`/`Material`/`InkWell` with:**

```dart
return Tooltip(
  message: widget.tooltip ?? widget.title,
  waitDuration: const Duration(milliseconds: 500),
  child: TpHover(
    onTap: widget.onTap,
    onSecondaryTapDown: widget.onSecondaryTapDown,
    onLongPress: widget.onLongPress,
    backgroundColor: active ? cs.surfaceContainerHigh : null,
    hoverColor: active
        ? cs.surfaceContainerHigh
        : cs.onSurface.withValues(alpha: 0.05),
    borderRadius: BorderRadius.circular(8),
    onHoverChanged: (hovered) => setState(() => _hovered = hovered),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active
              ? cs.outlineVariant.withValues(alpha: 0.7)
              : Colors.transparent,
        ),
      ),
      child: ConstrainedBox(
        // ... existing padding + Row (accent / leading / title / actions / close)
      ),
    ),
  ),
);
```

Remove duplicate `InkWell` `onTap`. Keep `_TpTabCloseButton` on inner `TpHover`. Keep chrome / accent alpha formulas using `_hovered`.

- [ ] **Step 4: Re-run chip + hover tests — expect PASS**

```bash
cd client/packages/shared_ui && flutter test test/components/hover/ test/components/tab/tp_tab_chip_test.dart
```

- [ ] **Step 5: Commit only if user requested**

---

### Task 4: Document convention in README

**Files:**
- Modify: `client/packages/shared_ui/README.md`

- [ ] **Step 1: Update Layout / chrome row** to mention click cursor, idle `backgroundColor`, prefer over bare `GestureDetector`/`MouseRegion` for onTap UI; selected fill via `backgroundColor` (no `selected` flag).

Example blurb:

> `TpHover` / `TpHoverRow` — click cursor when interactive; animated hover fill; optional idle `backgroundColor`, `enabled`, `onLongPress`, `onSecondaryTapDown`, `pressScale`. Prefer these over bare `MouseRegion`+`GestureDetector` for onTap chrome. Selected idle fill = pass `backgroundColor`; do not add a `selected` API to `TpHover`.

- [ ] **Step 2: No test; visual review of README**

- [ ] **Step 3: Commit only if user requested**

---

### Task 5: Migration backlog grep + hub/workspace cards

**Files (expected migrate set — confirm with grep):**
- `client/lib/pages/home_workspace/workspace_card.dart`
- `client/lib/pages/my_experts/my_experts_card.dart`
- `client/lib/pages/my_teams/my_teams_card.dart`
- `client/lib/pages/expert_hub/expert_hub_cards.dart`
- `client/lib/pages/team_hub/team_hub_cards.dart`
- `client/lib/pages/team_hub/team_landing_picker_local_card.dart`

- [ ] **Step 1: Build backlog**

```bash
cd client && rg -n '_hovered|MouseRegion\(' lib packages/ai_message_ui/lib --glob '*.dart' \
  | rg -v 'window_|resizable_|terminal|toast/engine|flutter-shadcn|flutter_alacritty'
```

Classify each hit: **migrate** / **exclude (hover-only)** / **exclude (special cursor)** / **already TpHover**.

- [ ] **Step 2: Migrate each card** to outer `TpHover(onTap: …, …)`  
  Keep card-specific `Decoration` (shadow, border) on the child. Use `onHoverChanged` only if the card still needs local hover for non-fill effects (e.g. stronger shadow). Prefer deleting `_hovered` when `TpHover` fill is enough.

- [ ] **Step 3: Smoke-check with analyze on touched files**

```bash
cd client && dart analyze lib/pages/home_workspace/workspace_card.dart \
  lib/pages/my_experts/my_experts_card.dart lib/pages/my_teams/my_teams_card.dart \
  lib/pages/expert_hub/expert_hub_cards.dart lib/pages/team_hub/
```

- [ ] **Step 4: Commit only if user requested**

---

### Task 6: Migrate sidebar / list / session rows

**Files:**
- `client/lib/widgets/sidebar_session_tile.dart`
- `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart`
- `client/lib/pages/home_workspace/home_workspace_sidebar.dart`
- `client/lib/pages/home_workspace/workspace_list_tile.dart`
- `client/lib/pages/home_workspace/workspace/workspace_automations_section.dart`
- `client/lib/pages/home_workspace/workspace/worktree_group_section.dart`
- `client/lib/pages/home_workspace/workspace/workspace_landing_selectors.dart`
- Prefer `TpHoverRow` when trailing-on-hover is the pattern; else `TpHover`.

- [ ] **Step 1: Migrate session / sidebar tiles** — wire `onSecondaryTapDown` through `TpHover` where context menus need position.

- [ ] **Step 2: Migrate remaining list rows in this task’s file list**

- [ ] **Step 3: Analyze touched paths**

```bash
cd client && dart analyze lib/widgets/sidebar_session_tile.dart \
  lib/pages/home_workspace/workspace/workspace_sidebar.dart \
  lib/pages/home_workspace/home_workspace_sidebar.dart \
  lib/pages/home_workspace/workspace_list_tile.dart
```

- [ ] **Step 4: Commit only if user requested**

---

### Task 7: Migrate status bar / notifications / title chrome (eligible only)

**Files:**
- `client/lib/widgets/workspace_status_bar/ssh_hosts_status_item.dart`
- `client/lib/widgets/workspace_status_bar/ssh_hosts_panel.dart`
- `client/lib/widgets/workspace_status_bar/resource_usage_status_item.dart`
- `client/lib/widgets/workspace_status_bar/resource_manager_panel.dart`
- `client/lib/widgets/workspace_status_bar/resource_manager_tree.dart`
- `client/lib/widgets/workspace_status_bar/progress_activities_status_item.dart`
- `client/lib/widgets/notification/notification_bell_button.dart`
- `client/lib/pages/home_workspace/home_workspace_title_bar.dart` (only clickable tab/action chips — **not** window drag regions)
- `client/lib/pages/home_workspace/home_workspace_content_header.dart`
- `client/lib/pages/home_workspace/workspaces_tab.dart`
- `client/lib/pages/home_workspace/home_workspace_team_tab.dart`
- `client/lib/pages/automations/automations_management_tab.dart`
- `client/lib/pages/home_workspace/workspace/workspace_search_dialog.dart`
- `client/lib/pages/home_workspace/home_workspace_new_team_dialog.dart`
- `client/lib/widgets/settings/theme_color_preset_picker.dart` (if clickable swatch rows lack cursor)

**Exclude:** `client/lib/widgets/window_chrome_controls.dart`, resize handles, `mobile_workspace_drawer_host` edge-drag if not tap chrome.

- [ ] **Step 1: Migrate status / notification clickable items to `TpHover`**

- [ ] **Step 2: Migrate remaining home chrome from the list (skip drag/caption)**

- [ ] **Step 3: Analyze**

```bash
cd client && dart analyze lib/widgets/workspace_status_bar/ lib/widgets/notification/
```

- [ ] **Step 4: Commit only if user requested**

---

### Task 8: File tree + git rows (drag-safe)

**Files:**
- `client/lib/widgets/file_tree_node.dart`
- `client/lib/widgets/git/git_change_tile.dart`
- `client/lib/widgets/git/git_change_folder_tile.dart`

- [ ] **Step 1: Inspect drag ownership** (`Draggable` / `LongPressDraggable` ancestors).  
  If `TpHover`’s `GestureDetector` would fight drag: **only** add `cursor: SystemMouseCursors.click` on the existing `MouseRegion` and/or use `TpHover` without competing by keeping drag as the gesture owner (spec: migrate cursor/`onHoverChanged` only when ambiguous). Prefer wrapping the **non-drag** hit child when structure allows.

- [ ] **Step 2: Apply the safer path per file; delete redundant `_hovered` only when fill is fully owned by `TpHover`**

- [ ] **Step 3: Analyze**

```bash
cd client && dart analyze lib/widgets/file_tree_node.dart lib/widgets/git/
```

- [ ] **Step 4: Commit only if user requested**

---

### Task 9: `ai_message_ui` action chrome + leftover app sites

**Files:**
- Migrate: `client/packages/ai_message_ui/lib/src/message_action_bar.dart` (**action buttons only**)
- Grep leftovers under `client/packages/ai_message_ui/lib` for `_hovered` / bare interactive `MouseRegion`
- **Exclude** hover-only probes (`fade_expand_body`, reveal-on-hover without tap)
- Any remaining **migrate** hits from Task 5 backlog not yet done (incl. any floating_workspace leftovers classified migrate)

- [ ] **Step 1: Migrate tappable action chrome only**  
  In `message_action_bar.dart`, outer `MouseRegion` that **reveals** the bar is a hover-only probe — **do not** replace it with `TpHover`. Put `TpHover` (or click cursor) on `_LiteIconAction` / equivalent **button** children that handle taps.

- [ ] **Step 2: Re-run backlog greps; classify every leftover**

```bash
cd client && rg -n 'var _hovered|bool _hovered' lib packages/ai_message_ui/lib --glob '*.dart'
cd client && rg -n 'MouseRegion\(' lib packages/ai_message_ui/lib --glob '*.dart' \
  | rg -v 'window_|resizable_|terminal|toast/engine|flutter-shadcn|flutter_alacritty'
```

Every hit: migrate / exclude (hover-only) / exclude (special cursor) / already OK.

- [ ] **Step 3: Commit only if user requested**

---

### Task 10: Full verification

- [ ] **Step 1: shared_ui tests**

```bash
cd client/packages/shared_ui && flutter test
```

Expected: all PASS.

- [ ] **Step 2: App analyze + unit tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  && flutter test --exclude-tags integration
```

Expected: analyze clean enough per project norms; tests PASS (fix any host tests broken by widget structure changes).

- [ ] **Step 3: Manual desktop smoke (if running UI)**  
  Hover a tab chip, sidebar session row, hub card, status item — cursor is hand; click still works; right-click menus still position correctly.

- [ ] **Step 4: Mark spec status** in `docs/superpowers/specs/2026-08-02-tp-hover-interactive-surface-design.md` to `implemented` when done.

- [ ] **Step 5: Commit only if user requested**

---

## Migration pattern cheat-sheet

**Before:**
```dart
return MouseRegion(
  onEnter: (_) => setState(() => _hovered = true),
  onExit: (_) => setState(() => _hovered = false),
  child: GestureDetector(
    onTap: onTap,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: _hovered ? hoverTint : Colors.transparent,
      ),
      child: child,
    ),
  ),
);
```

**After:**
```dart
return TpHover(
  onTap: onTap,
  hoverColor: hoverTint,
  child: child,
);
```

**Selected row:**
```dart
TpHover(
  onTap: onTap,
  backgroundColor: selected ? cs.surfaceContainerHigh : null,
  child: child, // border/shadow still on child if needed
)
```
