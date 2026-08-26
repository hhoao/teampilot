# Compose Model Cascade Menu — Design

Date: 2026-08-26

## Problem

In Simple mode, configuring a custom model for launch is cumbersome:

- The model chip opens a **flat one-level popup** (`buildComposeModelPresetMenuSpecs`):
  same-CLI presets → divider → "Custom…" → "Add preset".
- Choosing **Custom…** opens a full modal dialog (`simple_custom_launch_dialog`)
  with three stacked dependent dropdowns (Provider / Model / Effort).
- Creating a preset requires leaving the moment entirely (manage dialog → edit
  dialog → name → save → reopen chip menu).
- There is no way to browse Provider → Model directly from the chip.

Goal: replace the flat menu + modal flow with a **cascading submenu menu**
opened straight from the chip:

- Landing (Simple launch): CLI → Provider → Model → Effort.
- In-chat (Simple session): Provider → Model → Effort (CLI stays locked to
  `session.cli`).
- Presets stay as a top group; direct drill-down selection applies immediately
  with no modal.

## Confirmed UX decisions

1. **Hierarchy**: landing = CLI → Provider → Model (+ Effort as 4th level);
   in-chat skips the CLI level.
2. **Effort** is a 4th-level submenu on each model row ("默认" leaf included);
   models with no effort candidates are plain leaves.
3. **Presets and drill-down coexist**: preset group at top, drill-down below,
   bottom actions "保存当前为预设…" and "管理预设…".
4. Drill-down selection applies **immediately** — the Custom modal is no longer
   part of this flow.
5. **Custom model ID entry** is supported at the model level when the CLI's
   picker mode allows custom entries (`catalogWithCustomEntry`).
6. Scope: Simple-mode landing chip + in-chat continue chip only. Team-mode
   member chips, persistence formats, and the presets system stay untouched.

## Design

### 1. shared_ui cascade submenu primitive

Extend `client/packages/shared_ui/lib/src/components/action_menu/tp_action_menu.dart`:

```dart
class TpActionMenuSpec {
  // existing .item / .divider unchanged
  const TpActionMenuSpec.submenu({
    Object? value,
    IconData? icon,
    Widget? iconWidget,
    required String label,
    Widget? subtitle,
    bool selected = false,
    bool enabled = true,
    bool searchable = false,
    required this.children,   // List<TpActionMenuSpec>, may nest .submenu again
  });
}
```

Rendering / behavior:

| Concern | Behavior |
|---|---|
| Trigger | Hover ≥150ms expands; tap expands immediately |
| Anchoring | Nested `TpPopover` anchored to the row (child right-center → overlay top-left, offset 4); flips left near right edge; vertically clamped into viewport |
| Mutual exclusion | Opening/hovering a sibling closes the previously open branch at that level; moving into an open child keeps ancestors open |
| Leaf selection | Selecting any leaf closes the entire cascade and reports through the root anchor's normal `onSelect` value path |
| Dismissal | Tap outside closes everything (reuses `closeOnTapOutside`) |
| Height | Each panel `ConstrainedBox(maxHeight ≈ 60% of screen)` + scroll |
| Search | When `searchable: true` and children > 10, panel shows a filter input that filters items live (used for the model level) |
| Keyboard | Minimal v1: ↑/↓ move within level, → enters submenu, ← returns to parent, Enter selects leaf, Esc exits one level |
| Compatibility | `.item` / `.divider` semantics, `estimateTpActionMenuHeight`, and all existing callers unchanged |

### 2. App-layer menu composition

New builder in `client/lib/widgets/compose/compose_model_preset_chip.dart`:
`buildComposeModelCascadeMenuSpecs(...)` replacing the flat builder at its two
call sites (`unbound_compose_body.dart:_autoChipSpecs`, `ComposeModelPresetChip`).
The old flat builder is deleted after migration (its only consumers are these
two sites plus tests).

```
[chip] ─┬─ 我的预设（same-CLI presets, checkmark on current）
        ├─ ────────────────────────────────
        ├─ [landing only] <CLI> rows (CliBrandIcon)
        │      └─ provider submenu → model submenu(searchable) → effort submenu
        ├─ [in-chat] provider submenus directly
        │      └─ Claude 官方 → models… + 「自定义模型 ID…」
        ├─ ────────────────────────────────
        ├─ 保存当前为预设…（preset edit dialog prefilled with current selection）
        └─ 管理预设…（existing manage dialog）
```

Selection values use typed sentinel objects so the single `onSelect` path can
be decoded unambiguously:

- Preset id (existing `String`)
- `CascadeModelSelection(cli, providerId, modelId)` — model row chosen
  directly: effort stays **empty** (identical to submitting today's Custom
  dialog without touching Effort)
- `CascadeEffortSelection(cli, providerId, modelId, effort)` — a concrete
  effort leaf; the submenu's candidates come from `effortCandidates` verbatim
  plus one leading "默认" entry that resolves to the same empty-effort value
- Existing `ComposeModelPresetChipAction.manage`
- New `ComposeModelPresetChipAction.savePreset`
- New `ComposeModelCustomModelIdRequest(cli, providerId)` — opens the input popover

### 3. Data sources (capability-driven, no `if (cli == …)`)

| Level | Source |
|---|---|
| Providers | `AppProviderCubit.state.providersFor(cli)`, sorted by category then name |
| Models | `ProviderCapability.modelCandidates(provider:, providerId:, currentModel:)`; refreshable CLIs fire `refreshModelCatalog` when their model submenu opens (cache shows first, refresh updates in place) |
| Effort | `effortCandidates(model:, provider:)`; empty or `isApplicable(model) == false` → model row is a direct leaf |
| Custom model entry | Shown only when `pickerMode(provider)` == `catalogWithCustomEntry`; submits via small anchored text-input popover |
| Save-as-preset | Opens the existing preset edit dialog prefilled with the current four-tuple |

### 4. Selection data flow (no new persistence)

- **Landing**: leaf selection writes `_selectedCli / _selectedProvider /
  _selectedModel / _selectedEffort` draft state → existing landing draft
  resolution & submit unchanged.
- **In-chat**: leaf selection routes to the existing
  `ChatCubit.setSessionContinueCustom` path; running sessions keep the existing
  `_offerRestartAfterIdentitySwitch` confirm dialog.
- Chip label continues to render via `simpleLaunchChipLabel`.

### 5. Error handling

- Model catalog empty/failed: model submenu shows a disabled "暂无模型目录"
  row; 「自定义模型 ID…」 remains available.
- No providers configured: provider level shows the existing empty-state hint
  row; no drill-down rendered.
- All new strings go to `app_en.arb` / `app_zh.arb`.

### 6. Tests

1. shared_ui widget tests: submenu expand (hover delay + tap), sibling mutual
   exclusion, edge flip/clamp, search filtering, leaf-select-closes-all,
   keyboard navigation basics.
2. Spec-builder unit tests: presets+providers+models → specs mapping, effort
   leaf degradation, custom-entry visibility condition, save-preset/manage
   sentinels.
3. Landing/in-chat integration: selecting a leaf updates draft state /
   `setSessionContinueCustom` (existing cubit tests extended, not replaced).
4. Regression: existing compose chip tests updated;
   `flutter analyze --no-fatal-infos --no-fatal-warnings`;
   `dart run tool/run_tests.dart`.

## Files

- Edit `client/packages/shared_ui/lib/src/components/action_menu/tp_action_menu.dart`
  (submenu spec type + nested popover rendering) and export surface if needed
- Edit `client/lib/widgets/compose/compose_model_preset_chip.dart`
  (cascade builder + sentinels; delete flat builder after migration)
- Edit `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`
  (landing CLI→provider→model wiring, custom-model-ID popover, save-preset)
- Edit `client/lib/pages/chat/session_chat_compose_section.dart` +
  `client/lib/widgets/compose/workspace_compose_card.dart` /
  `compose_chrome.dart` (thread new props through Bound/Unbound chrome)
- Edit `client/lib/l10n/app_en.arb`, `app_zh.arb`
- Tests under `client/packages/shared_ui/test/…` and `client/test/widgets/compose/…`

## Known trade-offs

- True hover cascading needs careful intent handling; 150ms delay + sibling
  exclusion mitigates mis-fires but touch devices rely on tap-to-expand only.
- Keyboard support is minimal v1 (no type-ahead beyond the search box).
- The Custom modal dialog remains for other callers (team member editing);
  Simple mode simply stops routing through it.
