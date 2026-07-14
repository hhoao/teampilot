# Expert Landing Picker Dialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the expert bottom-sheet picker with a centered dialog that uses Expert Hub card grid → detail → Confirm for Landing, automation, and team apply flows.

**Architecture:** Keep `showExpertLandingPickerSheet` / `showExpertApplyPickerSheet` as entry APIs but switch them to `showDialog` + a stateful dialog body that swaps `ExpertHubBody` and picker-mode `ExpertHubDetailOverlay`. Export the existing Expert Hub add/launch handlers so the picker can wire the same secondary actions with the lifecycle from the spec.

**Tech Stack:** Flutter, `flutter_bloc` (`ExpertHubCubit`), existing `AppDialog` / Expert Hub widgets, ARB l10n.

**Spec:** `docs/superpowers/specs/2026-07-14-expert-landing-picker-dialog-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/l10n/app_en.arb`, `app_zh.arb` (+ generated) | `expertHubConfirmSelection` |
| `client/lib/pages/home_workspace/home_workspace_global_section.dart` | Export add/launch handlers (public) for picker reuse |
| `client/lib/pages/expert_hub/expert_hub_cards.dart` | Optional `selected` highlight on `ExpertHubCard` |
| `client/lib/pages/expert_hub/expert_hub_body.dart` | `showCreate`, `selectedKey` passthrough |
| `client/lib/pages/expert_hub/expert_hub_detail_overlay.dart` | Picker mode: Confirm primary + secondary Add/Launch |
| `client/lib/pages/expert_hub/expert_landing_picker_sheet.dart` | Rewrite as dialog (keep function names; rename widget) |
| `client/test/pages/expert_hub/expert_landing_picker_dialog_test.dart` | New picker widget tests |
| `client/test/pages/home_workspace/home_team_tab_add_member_test.dart` | Expect dialog + Confirm before apply |

---

### Task 1: l10n Confirm string

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Modify: generated `app_localizations*.dart` (via `flutter gen-l10n` or hand-sync if project does that)

- [ ] **Step 1: Add ARB keys** near other `expertHub*` strings:

```json
"expertHubConfirmSelection": "Confirm",
```

```json
"expertHubConfirmSelection": "确认",
```

- [ ] **Step 2: Regenerate or update localizations**

Run from `client/`:

```bash
flutter gen-l10n
```

If gen-l10n is not the project workflow, mirror the getter into `app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_zh.dart` like neighboring keys.

- [ ] **Step 3: Commit**

```bash
git add client/lib/l10n/
git commit -m "l10n: add expert hub confirm selection string"
```

---

### Task 2: Export Expert Hub add/launch handlers

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_global_section.dart` (rename `_expertAddToTeam` → `expertHubAddToTeam`, `_expertLaunchInWorkspace` → `expertHubLaunchInWorkspace`; update `ExpertHubPage` wiring)

- [ ] **Step 1: Rename private top-level functions to public**

```dart
Future<void> expertHubAddToTeam(
  BuildContext context,
  ExpertHubCubit cubit,
  DiscoverableMember member,
) async { /* existing body */ }

void expertHubLaunchInWorkspace(
  BuildContext context,
  DiscoverableMember member,
) { /* existing body */ }
```

Update `ExpertHubPage(onAddToTeam: expertHubAddToTeam, onLaunchInWorkspace: expertHubLaunchInWorkspace)`.

- [ ] **Step 2: Analyze**

```bash
cd client && dart analyze lib/pages/home_workspace/home_workspace_global_section.dart
```

Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/home_workspace/home_workspace_global_section.dart
git commit -m "refactor: export expert hub add/launch handlers for picker"
```

---

### Task 3: Card selected highlight + body picker flags

**Files:**
- Modify: `client/lib/pages/expert_hub/expert_hub_cards.dart`
- Modify: `client/lib/pages/expert_hub/expert_hub_body.dart`
- Test: extend `client/test/pages/expert_hub/expert_hub_body_test.dart` or keep coverage in Task 5

- [ ] **Step 1: Add `selected` to `ExpertHubCard`**

```dart
const ExpertHubCard({
  ...
  this.selected = false,
});

final bool selected;
```

In `build`, when `selected`, use primary-tinted border (e.g. `cs.primary.withValues(alpha: 0.65)`) even when not hovered; optional small check icon is fine but not required.

- [ ] **Step 2: Add picker flags to `ExpertHubBody`**

```dart
const ExpertHubBody({
  ...
  this.showCreate = true,
  this.selectedKey,
});

final bool showCreate;
final String? selectedKey;
```

- Hide Create `FilledButton.tonalIcon` when `!showCreate`.
- Pass `selected: m.key == selectedKey` into each `ExpertHubCard`.

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/expert_hub/expert_hub_cards.dart client/lib/pages/expert_hub/expert_hub_body.dart
git commit -m "feat(expert-hub): support picker create hide and selected card"
```

---

### Task 4: Detail overlay picker mode

**Files:**
- Modify: `client/lib/pages/expert_hub/expert_hub_detail_overlay.dart`

- [ ] **Step 1: Extend API**

```dart
const ExpertHubDetailOverlay({
  ...
  this.pickerMode = false,
  this.onConfirm,
});

final bool pickerMode;
final VoidCallback? onConfirm;
```

- [ ] **Step 2: CTA column behavior**

When `pickerMode`:
1. **Confirm** — `FilledButton`, label `l10n.expertHubConfirmSelection`, `onPressed: onConfirm` (disabled if `adding`).
2. **Add to team** — `OutlinedButton` (was filled), existing `onAddToTeam`.
3. **Launch in workspace** — `OutlinedButton`, existing `onLaunchInWorkspace`.

When `!pickerMode`, keep today’s layout (filled Add + outlined Launch).

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/expert_hub/expert_hub_detail_overlay.dart
git commit -m "feat(expert-hub): add picker confirm CTA on detail overlay"
```

---

### Task 5: Rewrite landing picker as dialog (TDD)

**Files:**
- Create: `client/test/pages/expert_hub/expert_landing_picker_dialog_test.dart`
- Modify: `client/lib/pages/expert_hub/expert_landing_picker_sheet.dart` (implement dialog; keep export names)
- Modify: `client/test/pages/home_workspace/home_team_tab_add_member_test.dart`

- [ ] **Step 1: Write failing widget tests**

Cover:
1. Open via `showExpertLandingPickerSheet` → `ExpertLandingPickerDialog` (or renamed widget) visible; tap card → detail shows Confirm; Confirm completes with key.
2. Tap card alone does **not** pop with a key.
3. Dismiss dialog → `null`.
4. Apply mode: Confirm calls `onApply` with the member.
5. Prefer `PopScope`/back: when detail open, first back returns to grid (if easy to drive in test; otherwise manual note).

Use the same fake `ExpertHubCubit` / `_FakeSource` pattern as `expert_hub_body_test.dart` / `home_team_tab_add_member_test.dart`. Pump a large surface (`Size(1200, 900)`).

- [ ] **Step 2: Run tests — expect fail**

```bash
cd client && flutter test test/pages/expert_hub/expert_landing_picker_dialog_test.dart
```

- [ ] **Step 3: Implement dialog**

Replace bottom sheet implementation:

```dart
Future<String?> showExpertLandingPickerSheet(
  BuildContext context, {
  String? selectedKey,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => ExpertLandingPickerDialog(selectedKey: selectedKey),
  );
}

Future<void> showExpertApplyPickerSheet(
  BuildContext context, {
  required ValueChanged<DiscoverableMember> onApply,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => ExpertLandingPickerDialog(onApply: onApply),
  );
}
```

Dialog body (`ExpertLandingPickerDialog`):
- `AppDialog` maxWidth ~960, maxHeight `MediaQuery.sizeOf(context).height * 0.85`.
- Header: `AppDialogHeader(title: l10n.expertHubTitle)`.
- **Must** wrap the list/detail body in `BlocConsumer<ExpertHubCubit, ExpertHubState>` (mirror `ExpertHubPage`): `ExpertHubBody` does **not** subscribe to the cubit itself — without a parent `watch`/`BlocBuilder`, load/search/filter/favorites/`adding` will not rebuild. Also toast on `state.errorMessage` like the page.
- Expanded child: if `_detail == null` → `ExpertHubBody(showCreate: false, selectedKey: …, inset: 16, onOpen: set detail)`; else → `ExpertHubDetailOverlay(pickerMode: true, inset: 16, favorited/adding/installedDepIds from state, onBack, onToggleFavorite, onConfirm, onAddToTeam, onLaunchInWorkspace)` — wire the same detail fields `ExpertHubPage` passes, not only picker-mode extras.
- On init: load cubit if needed (same as old sheet).
- **Confirm:** if `onApply != null` → `onApply(member); Navigator.pop()`; else `Navigator.pop(member.key)`.
- **Add to team:** `await expertHubAddToTeam(context, cubit, member)`; on success `setState(() => _detail = null)` (dialog stays open). Use try/catch for `MemberAddException` + toast like `ExpertHubPage` if the exported helper does not already toast (today’s helper toasts on success; page also catches failures — mirror page error toast).
- **Launch:** capture outer context in `show*`: pass `hostContext` into the dialog. On Launch: `Navigator.of(dialogContext).pop()` first (null / no apply), then `expertHubLaunchInWorkspace(hostContext, member)` — never use the dismissed dialog’s context after pop.
- Wrap with `PopScope(canPop: _detail == null, onPopInvokedWithResult: …)` so Android back clears detail first.

Remove old list-tile sheet UI / recent-only sections (hub body already covers favorites/filters). Keep “browse all” footer **out** — user is already in the picker; deep-link to full Expert Hub page is optional YAGNI (omit unless trivial TextButton).

- [ ] **Step 4: Update `home_team_tab_add_member_test`**

- Expect `ExpertLandingPickerDialog` (new type) instead of `ExpertLandingPickerSheet`.
- After tapping expert name/card, expect dialog **still** open and members length still 1.
- Tap Confirm (`find.text` for 确认 / Confirm depending on locale — test uses default en → `Confirm`).
- Then expect dialog gone and member added.

- [ ] **Step 5: Run tests**

```bash
cd client && flutter test \
  test/pages/expert_hub/expert_landing_picker_dialog_test.dart \
  test/pages/home_workspace/home_team_tab_add_member_test.dart \
  test/pages/expert_hub/expert_hub_body_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/expert_hub/expert_landing_picker_sheet.dart \
  client/test/pages/expert_hub/expert_landing_picker_dialog_test.dart \
  client/test/pages/home_workspace/home_team_tab_add_member_test.dart
git commit -m "feat: expert hub-style landing picker dialog with confirm"
```

---

### Task 6: Verification

- [ ] **Step 1: Analyze + focused tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/pages/expert_hub/ \
  lib/pages/home_workspace/home_workspace_global_section.dart \
  lib/l10n/
flutter test test/pages/expert_hub/ test/pages/home_workspace/home_team_tab_add_member_test.dart
```

- [ ] **Step 2: Manual smoke (if desktop available)**

Landing Simple mode → expert chip → Browse all → dialog grid → card → Confirm → chip label updates.

- [ ] **Step 3: Final commit only if leftover fixes**

---

## Notes for implementers

- Do **not** change Landing chip dropdown items.
- Call sites of `showExpertLandingPickerSheet` / `showExpertApplyPickerSheet` should need **no** signature changes.
- Prefer renaming the widget to `ExpertLandingPickerDialog` inside the existing file; keep sheet function names for greppability with the old API.
- After Launch pops the dialog, never use the dismissed dialog’s `BuildContext` for `go` / toasts.
