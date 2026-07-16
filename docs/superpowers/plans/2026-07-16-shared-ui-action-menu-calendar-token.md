# shared_ui Action Menu / Calendar / Token Field Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lift TeamPilot action menu, Huji date-range calendar, and token text-field (+ chip mirror/edit helpers) into `shared_ui` as `Tp*` APIs, then remount TeamPilot + Huji onto one published SHA in a single delivery wave.

**Architecture:** Lift-and-rename into `shared_ui/lib/src/components/{action_menu,date_range,token_field}/`. Menu is TeamPilot/`TpPopover` canonical. Calendar rewires Huji `AppPopover`→`TpPopover`, `HoverWidget`→`TpHover`, adds `intl`. Token field owns mirror + edit helpers in-package; TeamPilot keeps product palette wiring only. No typedef aliases for old names.

**Tech Stack:** Flutter, `package:shared_ui`, `intl`, existing `TpPopover` / `TpHover` / `TpTheme`.

**Spec:** [2026-07-16-shared-ui-action-menu-calendar-token-design.md](../specs/2026-07-16-shared-ui-action-menu-calendar-token-design.md)

**Hard gate:** Do not bump TeamPilot/Huji submodule until Task 4 lands on `origin/main` (or agreed published SHA containing all three components).

---

## File map (after)

| Path | Responsibility |
|------|----------------|
| `client/packages/shared_ui/lib/src/components/action_menu/*.dart` | `TpActionMenu*` + overlay + show helpers |
| `client/packages/shared_ui/lib/src/components/action_menu/tp_context_menu_position.dart` | `contextMenuGlobalPosition` (AtTap) |
| `client/packages/shared_ui/lib/src/components/date_range/*.dart` | `TpDateRangePicker`, `TpRangeCalendar`, date utils |
| `client/packages/shared_ui/lib/src/components/token_field/*.dart` | `TpTokenTextField`, chip mirror, edit helpers, palette typedefs |
| `client/packages/shared_ui/lib/shared_ui.dart` | Public exports |
| `client/packages/shared_ui/test/components/{action_menu,date_range,token_field}/` | Widget tests |
| TeamPilot: delete `lib/widgets/menu/`, `lib/widgets/inline_token/`; thin product palette under `services/inline_token/` | Call sites → barrel |
| Huji: delete `lib/widgets/menu/`, `lib/widgets/calendar/`; drop unused `widgets/dropdown/popover/` if orphaned | Call sites → barrel |

### Rename cheat-sheet

| Old | New |
|-----|-----|
| `ActionMenuController` | `TpActionMenuController` |
| `SidebarActionMenu*` | `TpActionMenu*` |
| `ActionMenuPopoverAnchor` | `TpActionMenuAnchor` |
| `showSidebarActionMenu*` / `showFloatingActionMenuOverlay` | `showTpActionMenu*` / `showTpActionMenuOverlay` |
| `AppDateRangePicker` / `AppRangeCalendar` | `TpDateRangePicker` / `TpRangeCalendar` |
| `InlineTokenTextField` / chip mirror / edit | `TpTokenTextField` / `TpTokenChipMirror` / `TpTokenEdit*` (or equivalent) |
| `InlineTokenPalette` / resolver typedefs | `TpTokenPalette` / `TpTokenPaletteResolver` |

---

### Task 1: Lift `TpActionMenu` into shared_ui

**Work in:** `/home/hhoa/git/hhoa/teampilot/client/packages/shared_ui` (feature branch from current `main`)

**Sources:**  
`/home/hhoa/git/hhoa/teampilot/client/lib/widgets/menu/sidebar_action_menu.dart`  
`/home/hhoa/git/hhoa/teampilot/client/lib/widgets/menu/sidebar_action_menu_overlay.dart`  
`/home/hhoa/git/hhoa/teampilot/client/lib/utils/ui/context_menu_position.dart` → only **`contextMenuGlobalPosition`** (not `contextMenuPositionForGlobal`)

- [ ] **Step 1: Create feature branch**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/shared_ui
git fetch origin && git checkout main && git pull --ff-only
git checkout -b feat/tp-action-menu-calendar-token
```

- [ ] **Step 2: Write failing smoke test (menu panel + item tap closes via controller hook)**

Create: `test/components/action_menu/tp_action_menu_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('TpActionMenuItem invokes onPressed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TpActionMenuPanel(
            children: [
              TpActionMenuItem(
                label: 'Do it',
                onPressed: () => pressed = true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Do it'));
    await tester.pump();
    expect(pressed, isTrue);
  });
}
```

Adjust constructors to match lifted API (label vs child — mirror TeamPilot `SidebarActionMenuItem` fields exactly, then rename).

- [ ] **Step 3: Run test — expect FAIL (missing types)**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/shared_ui
flutter test test/components/action_menu/tp_action_menu_test.dart
```

Expected: compile/import failure for `TpActionMenu*`.

- [ ] **Step 4: Copy + rename implementation**

```bash
mkdir -p lib/src/components/action_menu
# Copy menu + overlay from TeamPilot sources into action_menu/
# Rename symbols per cheat-sheet
# Move contextMenuGlobalPosition into tp_context_menu_position.dart
# Replace app imports with package:shared_ui relative/src imports (TpPopover, TpTextStyles, TpIconSizes, TpIconButton, …)
# Remove re-export of TpAnchor from old menu file — anchors already via tp_popover.dart
```

Split if a single file stays >~600–800 lines: `tp_action_menu.dart` (widgets), `tp_action_menu_show.dart` (show helpers), `tp_action_menu_overlay.dart`, `tp_context_menu_position.dart`.

- [ ] **Step 5: Export from barrel**

Modify `lib/shared_ui.dart` — add exports for action_menu public files.

- [ ] **Step 6: Run test — expect PASS; full package tests**

```bash
flutter test test/components/action_menu/tp_action_menu_test.dart
flutter test
```

Expected: green.

- [ ] **Step 7: Commit**

```bash
git add lib test
git commit -m "feat: add TpActionMenu over TpPopover"
```

---

### Task 2: Lift `TpDateRangePicker` / `TpRangeCalendar`

**Sources:**  
`/home/hhoa/git/hhoa/huji/huji-app/lib/widgets/calendar/{app_date_range_picker,app_range_calendar,calendar_date_utils}.dart`

**Required rewires (spec):**

| Huji | Package |
|------|---------|
| `AppPopover` / `AppPopoverController` / `AppAnchor` | `TpPopover` / `TpPopoverController` / `TpAnchor*` |
| `HoverWidget` | `TpHover` |
| `SidebarActionMenuMetrics.panelDecoration` | `TpActionMenuMetrics.panelDecoration` |
| `package:intl` `DateFormat.yMMMM` | keep — **add `intl` to `pubspec.yaml`** |

- [ ] **Step 1: Add `intl` dependency**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/shared_ui
# Add intl: (compatible constraint; match Flutter SDK / existing apps)
```

- [ ] **Step 2: Write failing test**

Create: `test/components/date_range/tp_date_range_picker_test.dart` — pump `TpRangeCalendar` with fixed `firstDate`/`lastDate`, tap two days, expect `onChanged` range (or pump picker with a `TextButton` trigger and open popover). Keep smoke-level.

- [ ] **Step 3: Run — expect FAIL**

```bash
flutter test test/components/date_range/tp_date_range_picker_test.dart
```

- [ ] **Step 4: Copy + rewire**

```bash
mkdir -p lib/src/components/date_range
# Copy three Huji files; rename App* → Tp*
# Rewire popover/hover/metrics as table above
# Keep clear label '清除' for this wave (documented follow-up)
```

- [ ] **Step 5: Export + tests**

```bash
# export from shared_ui.dart
flutter test test/components/date_range/
flutter test
```

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: add TpDateRangePicker and TpRangeCalendar"
```

---

### Task 3: Lift `TpTokenTextField` (+ mirror / edit)

**Sources:**  
`/home/hhoa/git/hhoa/teampilot/client/lib/widgets/inline_token/inline_token_text_field.dart`  
`/home/hhoa/git/hhoa/teampilot/client/lib/services/inline_token/inline_token_chip_mirror.dart`  
`/home/hhoa/git/hhoa/teampilot/client/lib/services/inline_token/inline_token_edit.dart`  
`/home/hhoa/git/hhoa/teampilot/client/lib/services/inline_token/inline_token_palette.dart` (typedefs only — **not** `resolveSlashAtTokenPalette`)

- [ ] **Step 1: Write failing test**

Create: `test/components/token_field/tp_token_text_field_test.dart` — field with controller text containing a match for a simple `RegExp`, custom resolver returning fixed colors; expect mirror/chip path does not throw and field builds.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement under `lib/src/components/token_field/`**

Move field + chip mirror + edit helpers + palette **typedefs**. Rename to `Tp*`. Ensure **zero** imports of TeamPilot. Product `resolveSlashAtTokenPalette` stays in TeamPilot (Task 5).

- [ ] **Step 4: Export + `flutter test`**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: add TpTokenTextField with chip mirror helpers"
```

- [ ] **Step 6: README**

Update `client/packages/shared_ui/README.md` component table for action menu / date range / token field. Commit:

```bash
git commit -m "docs: document TpActionMenu, date range, token field"
```

---

### Task 4: Publish shared_ui `main` (hard gate)

- [ ] **Step 1: Verify**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/shared_ui
flutter test
test -d lib/src/components/action_menu
test -d lib/src/components/date_range
test -d lib/src/components/token_field
```

- [ ] **Step 2: Push + PR + merge**

```bash
git push -u origin feat/tp-action-menu-calendar-token
gh pr create --base main --head feat/tp-action-menu-calendar-token \
  --title "feat: TpActionMenu, TpDateRangePicker, TpTokenTextField" \
  --body "$(cat <<'EOF'
## Summary
- TpActionMenu (TeamPilot menu lift, TpPopover)
- TpDateRangePicker / TpRangeCalendar (Huji lift, TpPopover/TpHover/intl)
- TpTokenTextField + chip mirror/edit helpers

## Test plan
- [ ] flutter test in shared_ui
EOF
)"
gh pr merge --merge
```

- [ ] **Step 3: Record SHA**

```bash
git fetch origin main
git rev-parse origin/main   # → SHARED_UI_MAIN_SHA
```

Write SHA into Task 5/6 commits / PR bodies.

---

### Task 5: Remount TeamPilot

**Work in:** `/home/hhoa/git/hhoa/teampilot` on a feature branch (do not leave `main` broken mid-wave).

- [ ] **Step 1: Bump submodule**

```bash
cd client/packages/shared_ui
git fetch origin && git checkout SHARED_UI_MAIN_SHA
cd ../../..
git add client/packages/shared_ui
cd client && flutter pub get
```

- [ ] **Step 2: Mechanical rename / imports**

```bash
cd client
rg -l "SidebarActionMenu|showSidebarActionMenu|showFloatingActionMenuOverlay|ActionMenuController|ActionMenuPopoverAnchor" lib --glob '*.dart'
# Replace with Tp* / showTp*; import package:shared_ui/shared_ui.dart
# Delete lib/widgets/menu/
```

- [ ] **Step 3: Token field remount**

- Replace `InlineTokenTextField` → `TpTokenTextField`
- Point `compose_trigger_chip_style.dart` / any chip-mirror imports at package
- Keep `services/inline_token/inline_token_palette.dart` product resolvers; typedefs may re-export or wrap `TpTokenPalette*`
- Delete `lib/widgets/inline_token/`
- Trim `services/inline_token/` files that fully moved (mirror/edit) — leave thin product-only modules

- [ ] **Step 4: Position util**

If nothing else needs `contextMenuPositionForGlobal`, keep it in app util; switch AtTap/menu callers to package `contextMenuGlobalPosition` (or drop local duplicate of Global).

- [ ] **Step 5: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | rg "error •" | head -40
```

Expected: 0 errors.

- [ ] **Step 6: Acceptance grep**

```bash
rg "SidebarActionMenu|showSidebarActionMenu|showFloatingActionMenuOverlay|InlineTokenTextField" lib --glob '*.dart' || true
```

Expected: empty (product palette file names OK).

- [ ] **Step 7: Commit**

```bash
git add -A client/lib client/packages/shared_ui client/pubspec.lock
git commit -m "feat(ui): remount action menu and token field onto shared_ui"
```

---

### Task 6: Remount Huji

**Work in:** `/home/hhoa/git/hhoa/huji` on feature branch.

- [ ] **Step 1: Bump submodule to same `SHARED_UI_MAIN_SHA`**

```bash
cd huji-app/packages/shared_ui
git fetch origin && git checkout SHARED_UI_MAIN_SHA
cd ../../..
git add huji-app/packages/shared_ui
cd huji-app && flutter pub get
```

- [ ] **Step 2: Remount menu + calendar**

```bash
rg -l "SidebarActionMenu|showSidebarActionMenu|AppDateRangePicker|AppRangeCalendar" lib --glob '*.dart'
# → TpActionMenu* / TpDateRangePicker / TpRangeCalendar
# Delete lib/widgets/menu/, lib/widgets/calendar/
```

- [ ] **Step 3: Orphan cleanup**

```bash
rg "AppPopover|widgets/dropdown/popover|HoverWidget|widgets/controls/hover_widget" lib --glob '*.dart' || true
```

If only calendar used them: delete `widgets/dropdown/popover/` and `widgets/controls/hover_widget.dart` if unused. Keep `ChromeIconButton` / other controls still referenced by non-menu code.

- [ ] **Step 4: Analyze + grep**

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | rg "error •" | head -40
rg "SidebarActionMenu|AppDateRangePicker|AppRangeCalendar" lib --glob '*.dart' || true
```

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(ui): remount action menu and date range onto shared_ui"
```

---

### Task 7: Cross-repo verify

- [ ] **Step 1: shared_ui tests**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/shared_ui && flutter test
```

- [ ] **Step 2: Both apps analyze**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd /home/hhoa/git/hhoa/huji/huji-app && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 3: Smoke (manual / optional)**

- TeamPilot: workspace tab overflow / chat context menu
- Huji: task date-range filter
- TeamPilot: compose token field

- [ ] **Step 4: Doc note**

Update spec status to Landed + `SHARED_UI_MAIN_SHA` when merged; commit docs if needed.

---

## Acceptance checklist (from spec)

- [ ] `shared_ui` `main` exports `TpActionMenu*`, `TpDateRangePicker`/`TpRangeCalendar`, `TpTokenTextField` (+ mirror/edit)
- [ ] TeamPilot + Huji submodule SHA match that `main`
- [ ] No app-local menu / Huji calendar / TeamPilot inline_token widget duplicates
- [ ] No `typedef` aliases for old names
- [ ] Analyze clean on both apps; package tests green

## Notes for implementers

- Prefer TeamPilot menu behavior over Huji `PopupMenuEntry` fork.
- Do not move `resolveSlashAtTokenPalette` into the package.
- Calendar clear label may stay hardcoded `清除` this wave.
- If Task 4 blocked, stop — do not pin unpublished SHAs into app `main`.
