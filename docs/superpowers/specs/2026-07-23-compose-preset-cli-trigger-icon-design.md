# Compose preset chip trigger: CLI brand icon

## Goal

Session chat continue compose: the **preset chip trigger** shows the agent CLI brand icon (`CliBrandIcon`) instead of the generic `Icons.terminal_outlined`.

## Scope

- In: Landing simple-mode auto/preset chip trigger + session continue `ComposeModelPresetChip`.
- Out: Team-mode auto chip (still groups/autorenew), menu row icons (already `CliBrandIcon`), other toolbar chips.

## Behavior

1. Resolve CLI from selected preset in `sameCliPresets`, else from the sole CLI of that list when all presets share one CLI (session lock), else fall back to `Icons.terminal_outlined`.
2. Render via existing `CliBrandIcon` (SVG brand when available).
3. Size/border match menu icons: `context.tpIconSizes.sm`, `borderRadius: 4`, `showBorder: false`.

## Approach

Add optional `Widget? leading` to `ComposeToolbarChip` and `ComposeMenuChip`. When non-null, use it instead of `Icon(icon)`. `ComposeModelPresetChip` passes `CliBrandIcon` for the resolved CLI.
