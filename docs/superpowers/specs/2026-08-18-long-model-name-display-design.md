# Long Model / Preset Name Display Design

**Date:** 2026-08-18
**Status:** Approved
**Scope:** shared_ui + preset manage/edit/landing compose surfaces

## Problem

Long model names (e.g. `deepseek-v4-pro[1m]`, `cursor-grok-4.6-high`) and preset
names are hard to read in three surfaces:

| Surface | Current behavior |
|---------|------------------|
| Preset edit dialog model dropdown (`TpSelect` header) | Truncated with `…`, no way to reveal the full name |
| Preset manage list (`_PresetRow`) | Name wraps / summary line truncates, no full-text reveal |
| Compose preset chip (`ComposeToolbarChip`) | Not truncated — long names push the chip very wide |

## Goals

- Every place a long name gets visually truncated must be able to reveal the
  full text.
- One reusable primitive in `shared_ui`; no per-page tooltip plumbing.
- Works on desktop (hover) and mobile (long-press) with zero per-use config.
- Tooltips appear **only when text actually overflows** (no tooltip noise on
  short names).

## Non-goals

- Long-press-to-copy of the model id.
- Expandable list rows / alternate display aliases.
- Backward-compatibility shims — normalize the affected widgets in place.

## Design

### 1. New primitive: `TpEllipsisText` (shared_ui)

New file: `client/packages/shared_ui/lib/src/components/text/tp_ellipsis_text.dart`.

A `StatelessWidget` that renders a single/multi-line `Text` with ellipsis and —
**only when the text overflows its width at the requested `maxLines`** — wraps
it in a Material `Tooltip(message: fullText)`.

- Measures overflow with a `LayoutBuilder` + `TextPainter`
  (`didExceedMaxLines`) using the text style and incoming max width.
- `maxLines: null` (unbounded) → returns plain `Text`, no tooltip.
- Uses Material `Tooltip` (not the hover-only `TpTooltip`) so it is
  platform-adaptive out of the box: hover on desktop, long-press on touch,
  no custom trigger plumbing.
- API mirrors `Text` for the fields we need:

```dart
TpEllipsisText(
  this.text, {
  Key? key,
  TextStyle? style,
  int? maxLines = 1,
  TextAlign? textAlign,
  TextOverflow? overflow,
  TextDirection? textDirection,
  bool softWrap = true,
})
```

### 2. Integrate into `TpSelect` — fixes all dropdown headers + list items

File: `client/packages/shared_ui/lib/src/components/select/tp_select.dart`.

- `_buildItemChild`'s fallback `Text` (used for both the closed header and the
  open menu rows when no custom `itemBuilder`/`listItemBuilder` is supplied)
  becomes `TpEllipsisText(itemLabel(item), style, maxLines, softWrap: false)`.
- This single change covers:
  - preset edit dialog model/provider/CLI dropdowns,
  - team default preset / member launch selects,
  - any other `TpSelect`-backed picker.
- Builder-supplied rows are caller-owned (they already control truncation);
  not touched.

### 3. Preset manage list row

File: `client/lib/pages/home_workspace/workspace/config/cli_presets_manage_dialog.dart`
(`_PresetRow`).

- Name `Text(preset.name, styles.lgColored(...))` → `TpEllipsisText(preset.name)`
  with `maxLines: 1` (currently wraps).
- Summary `'$cliName · $subtitle'` (already `maxLines: 1` + ellipsis) →
  `TpEllipsisText` with the full string, keeping the same style.

### 4. Compose preset chip

File: `client/lib/widgets/compose/compose_menu_chip.dart`
(`ComposeToolbarChip`).

- Label `Text(label, style: labelStyle)` → `TpEllipsisText(label)` inside a
  `ConstrainedBox(maxWidth: labelMaxWidth)`, keeping the chip stadium-shaped
  and capped (~200 logical px; new optional `labelMaxWidth` ctor param,
  default 200).
- Applies to both the landing chip and the bound history-continue chrome
  (same component).

## Mobile behavior

- No extra code: Material `Tooltip` triggers on long-press on touch devices and
  on hover on desktop.
- The open picker list (`TpSelect`) is already searchable and shows the full
  item text; that remains the primary full-text surface on narrow screens.

## Testing (flow-level)

Per project convention, keep tests focused on the **flows**, not trivial widget
pings.

**shared_ui `TpSelect` (+ `TpEllipsisText`):**
- `TpEllipsisText` unit: short text → no `Tooltip` ancestor; long text →
  `Tooltip.message` equals full text.
- `TpSelect` header flow: long item truncates and the closed header carries a
  `Tooltip` with the full label; short item does **not**.

**App flows (`cli_preset_edit_dialog_test.dart` + manage/list + landing):**
- Edit-dialog flow (existing tests kept): rename + change model → saved to
  cubit/disk and shown on reopen.
- Manage list flow: a preset with a long name renders one line and reveals the
  full name via `Tooltip.message`.
- Edit-dialog dropdown flow: a long model name renders truncated in the picker
  header with the full model id on the header `Tooltip`.
- Landing compose flow: a long preset name chip stays capped in width and
  reveals the full label via `Tooltip.message`.

## Out of scope (explicitly cut for this iteration)

- Long-press copy of model ids.
- Expandable/collapsible manage rows on mobile.
- Display aliases for known long model ids.