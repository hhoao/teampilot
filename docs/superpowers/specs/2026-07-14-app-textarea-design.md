# AppTextarea — Design

**Date:** 2026-07-14  
**Status:** Approved  
**Source:** Adapted from `client/packages/flutter-shadcn-ui` `ShadTextarea` behavior (min/max height, resize grip, line-count from height), without depending on `shadcn_ui`.

## Goal

Add a Teampilot multiline text control that matches `ShadTextarea` interaction (height-bounded, optionally user-resizable) while using Material `TextField` + existing app outline styling. Expose a composable **shell** so chat compose can reuse height/resize without replacing inline-token editing. Migrate form-style multiline fields and compose onto this stack.

## Non-goals

- Do not add a `shadcn_ui` path dependency to the client.
- Do not port `ShadInput`, `ShadDecoration`, or `ShadTheme`.
- Do not merge `ComposeFocusShell` (assistant-ui chrome) with form outline decoration.
- Do not migrate every form to `AppForm` in this change (only swap multiline controls; use `AppTextareaFormField` where the parent already uses `AppForm`).
- Do not change display-only `Text(..., maxLines: …)` truncation.

## Architecture

Two layers:

1. **`AppTextareaShell`** — owns `minHeight` / `maxHeight`, drag-resize + grip, derives visible line count from current height + text style, applies multiline-safe decoration (overrides global single-line `InputDecorationTheme.constraints.tightFor(height)`).
2. **Content slot** — plain path: `TextField` via `AppTextarea`; compose path: `InlineTokenTextField` with shell-injected equal `minLines`/`maxLines`.

`AppTextareaFormField` = `AppFormField<String>` + `AppTextarea` (control only; validation stays on `AppFormField`).

```
AppTextareaFormField
  └─ AppFormFieldLayout
       └─ AppTextarea
            └─ AppTextareaShell
                 └─ TextField

Compose cards today wrap ComposeTriggerField in ComposeFocusShell.
Intended editor stack (do not re-parent the shell into ComposeTriggerField):

ComposeFocusShell                   # existing focus/shadow chrome (parent)
  └─ … toolbar / layout …
       └─ AppTextareaShell          # height + resize (inside ComposeTriggerField or sibling wrap)
            └─ InlineTokenTextField
```

## Placement

```
client/lib/widgets/textarea/
  app_textarea_shell.dart       # height, resize, line count, decoration override
  app_textarea.dart             # Shell + TextField
  app_textarea_form_field.dart  # AppFormField + AppTextarea
  app_textarea_resize_grip.dart # default diagonal grip painter
```

Tests under `client/test/widgets/textarea/`.

## API

### `AppTextareaShell`

- `minHeight` (default ~80), `maxHeight` (default ~500), `resizable` (default `true`), `onHeightChanged`.
- `resizeHandleBuilder` optional; default grip in bottom-trailing corner.
- Exposes derived `lineCount` (clamped) to the child via a small callback/builder or inherited value so content can set `minLines`/`maxLines` equal to that count (same approach as `ShadTextarea` → `ShadInput`).
- Owns height/resize chrome only. Outline / `InputDecoration` overrides belong on the **`AppTextarea`** path; compose keeps borderless `InlineTokenTextField` decoration under `ComposeFocusShell`.
- Does **not** depend on `ShadTheme`.

### `AppTextarea`

- Familiar `TextField` surface: `controller` / `initialValue` (mutually exclusive), `focusNode`, `onChanged`, `enabled`, `readOnly`, `maxLength`, `decoration` / hint, `style`, etc.
- Height/resize params forwarded to the shell.
- Keyboard type: multiline.
- Explicit decoration merge that clears fixed single-line height constraints from the global outline theme; horizontal padding follows `AppControlTheme` (+ existing input inset tweak); vertical padding suitable for multiline (not the single-line track).

### `AppTextareaFormField`

- Same form contract as other `AppFormField`s: `id`, `label`, `description`, `validator`, `onChanged`, `enabled`, `readOnly`, focus.
- Builder control is `AppTextarea`; label/error/description come from `AppFormFieldLayout` (not from `InputDecoration.labelText` when used inside `AppForm`).

### Resize grip

- Port the diagonal grip painter idea from `ShadDefaultResizeGrip` / `ShadResizeGripPainter`, renamed `App*`, colored from `ColorScheme` (e.g. outline / primary ring), not `ShadTheme.colorScheme.ring`.

## Compose integration

- Keep `ComposeFocusShell` for border radius, focus-within edge, and light/dark shadows.
- Inside it, wrap the editor with `AppTextareaShell`. Default min/max height should approximate today’s ~3–6 line compose extent (derived from compose text style line height, not hard-coded forever as `minLines` alone).
- `InlineTokenTextField` keeps token chips, overlay, and key handling; it receives shell-driven equal `minLines`/`maxLines`.
- Default `resizable: true` for compose; callers may disable.
- Do **not** subclass `AppTextarea` for compose.
- **UX change (intentional, matches `ShadTextarea`):** equal `minLines`/`maxLines` from height replaces content auto-grow (e.g. compose 3→6, git 1→4). Viewport height is fixed until the user drags the grip (or props change). Do not reintroduce content-driven auto-grow in this migration.

## Call-site migration

Replace multiline editable `TextField` / `TextFormField` usages with `AppTextarea` (or `AppTextareaFormField` when already under `AppForm`).

**Inventory rule:** The table below is the known set at spec time. Implementation planning **must** start with a fresh repo-wide grep for multiline inputs (`minLines:` / `maxLines:` > 1 on `TextField` / `TextFormField`) and treat any additional hits as in-scope unless they are display-only `Text` or clearly single-line.

| Location | Notes |
|----------|--------|
| `app_provider_form_sheet.dart` | JSON block (tall min/max), notes |
| `expert_editor_dialog.dart` | prompt, playbook |
| `automation_editor_dialog.dart` | message |
| `hub_publish_wizard_steps.dart` | description |
| `mcp_oauth_connect_dialog.dart` | callback URL |
| `mcp_form_page.dart` | description (`maxLines: 2`), JSON (`maxLines: 12`) |
| `team_config_info_section.dart` | team description (`maxLines: 3`) |
| `home_workspace_team_generate_section.dart` | team gen description |
| `launch_config_schema_form.dart` | multiline string fields / `scriptText` |
| `git_source_control_panel.dart` | commit message |
| `ssh_profile_setup_page.dart` | private key (`maxLines: 4`) |
| `compose_trigger_field.dart` + `inline_token_text_field.dart` | shell integration as above |

Leave single-line fields unchanged. Prefer sensible `minHeight`/`maxHeight` per surface (JSON editor taller than notes).

## Theme interaction

Global `buildAppOutlineInputDecorationTheme` keeps `constraints: BoxConstraints.tightFor(height: control.height)` for **single-line** controls. `AppTextarea` / shell must override `InputDecoration.constraints` (and multiline content padding) locally so multiline fields are not crushed to button-track height.

## Tests

- Shell: height clamp on prop change; drag updates height and fires `onHeightChanged`; line count stays in range.
- `AppTextarea`: typing; disabled; decoration does not inherit single-line tight height.
- `AppTextareaFormField`: validate failure + value in `AppFormState`.
- Compose path: after resize, text input and token chip rendering still work.

## Attribution

File headers note adaptation from `flutter-shadcn-ui` Textarea; public names are `App*`.
