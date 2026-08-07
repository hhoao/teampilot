# Desktop clickable cursor + unified pressable primitive

## Problem

On desktop (non-web), Flutter's Material interactives use `WidgetStateMouseCursor.adaptiveClickable`, which resolves to `SystemMouseCursors.basic` (arrow) — not a hand pointer:

```dart
static MouseCursor _adaptiveClickable(Set<WidgetState> states) {
  if (states.contains(WidgetState.disabled)) return SystemMouseCursors.basic;
  return kIsWeb ? SystemMouseCursors.click : SystemMouseCursors.basic;
}
```

So every `InkWell` / `IconButton` / `FilledButton`… that relies on the Material default shows an **arrow** cursor on hover, while the app's own desktop primitives (`TpHover`, `TpIconButton`, `ai_message_ui` parts) explicitly set `SystemMouseCursors.click` and show a **hand** pointer. The chat compose card buttons (send / attach / enhance / voice / team-settings / chips — all bare `InkWell`) are the most visible instance of the inconsistency.

Separately, the codebase mixes two interaction paradigms: mobile-oriented `InkWell` ripple vs. the desktop-oriented `TpHover` (GestureDetector + hover/active color fade + hand cursor). This produces inconsistent hover feedback and cursor affordance across the app.

## Decision

Unify on **one platform-adaptive pressable primitive** in `shared_ui` (the `Tp*` design system), and give Material button families a hand cursor via the theme:

1. **`TpHover` becomes the single pressable entry point** — adaptive per platform:
   - **Desktop** (Linux / macOS / Windows / web): current behavior — `GestureDetector` + hover/active color alpha fade + interactive→hand / disabled→arrow cursor (+ optional press scale).
   - **Touch** (Android / iOS): `Material` + `InkWell` ripple (no cursor / hover).
   - Additive params, backwards compatible: existing 53 `TpHover` call sites change behavior on touch only (they gain ripple), zero source churn.
2. **Material button families get a hand cursor via the app theme** (arrow when disabled) — covers `FilledButton` / `OutlinedButton` / `ElevatedButton` / `TextButton`, plus the currently-unthemed `IconButton` (141 uses) and `Checkbox`. Material buttons keep the M3 ink widget; only their cursor is standardized.
3. **All 44 remaining `InkWell` sites migrate to `TpHover`** — 40 in `client/lib/`, 4 in `shared_ui` (requires committing the submodule and bumping its pointer).

Scope is global (whole app), per explicit user decision.

## Architecture

### 1. `TpHover` adaptive primitive (`client/packages/shared_ui/.../hover/tp_hover.dart`)

New/kept widget API (all additions optional):

- **Existing params (unchanged defaults):** `child`, `hoverColor`, `backgroundColor`, `border`, `onTap`, `onSecondaryTap`, `onSecondaryTapDown`, `onLongPress`, `padding`, `borderRadius`, `duration`, `cursor`, `forceHover`, `onHoverChanged`, `width`, `height`, `enabled`, `pressScale`.
- **New params:**
  - `onTapDown` / `onTapUp` / `onTapCancel` — passthrough (menu rows select on pointer-down).
  - `shape` — `TpPressableShape { rounded, stadium, circle }`, default `rounded`. Desktop derives a `BorderRadius` (stadium/circle → `circular(size/2)`), touch derives a `ShapeBorder` for the `Material` (circle/stadium stay exact).
- **Adaptive build:**
  - `bool get isTouch` ← `defaultTargetPlatform` is `android` / `iOS` (web → desktop path, since cursor/hover matter there).
  - **Desktop path** (current behavior): `MouseRegion(cursor: …)` + `AnimatedContainer` fill (alpha-only fade) + `GestureDetector`. Add `Focus` + `Semantics(button: …)` so keyboard reachability parity with `InkWell` is preserved.
  - **Touch path**: `Material(color: backgroundColor, shape: <shape from `shape`/`borderRadius`>, clipBehavior: antiAlias, child: InkWell(onTap/onTapDown/onLongPress…, customBorder: shape, child: …))`. Cursor is irrelevant (no mouse); hover is not painted.
- **Cursor rule (desktop):** interactive (any tap handler + `enabled`) → `SystemMouseCursors.click`; else `SystemMouseCursors.basic`. `cursor` param still overrides.

`TpHoverRow` (the row variant) keeps working; it delegates to the same adaptive core if it wraps `TpHover`.

### 2. Theme — hand cursor for Material buttons (`client/lib/theme/app_button_theme.dart` + `app_theme.dart`)

- In `buildAppButtonThemes`, add to the merged `ButtonStyle`:
  ```dart
  mouseCursor: WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.disabled)
        ? SystemMouseCursors.basic
        : SystemMouseCursors.click,
  )
  ```
  covering `filled` / `outlined` / `elevated` / `text`.
- Add an `iconButtonTheme` (currently unset → Material default arrow) in `_applyTypography` (both the test-fallback and runtime branches) with the same cursor rule.
- Add `checkboxTheme` with the same cursor rule (single `Checkbox` use; cheap, consistent).
- Both light and dark themes flow through `_applyTypography`, so one insertion point per theme covers both.

### 3. Migrate `InkWell` → `TpHover` (44 sites)

Mechanical per-site mapping:

| Current | Replacement |
|---|---|
| `InkWell(onTap:…, child:…)` inside `Material(color: fill, shape: StadiumBorder…, clipBehavior: antiAlias)` | `TpHover(backgroundColor: fill, shape: stadium, border: Border.all(…), onTap:…, child:…)` |
| `Material(color: …CircleBorder())` + `InkWell(customBorder: CircleBorder())` (36×36 compose/voice buttons) | `TpHover(width: 36, height: 36, shape: circle, backgroundColor:…, onTap:…)` |
| `InkWell(onTapDown:…, onTap:…, onHover:…)` (compose trigger suggestion rows) | `TpHover(onTapDown:…, onTap:…, onHoverChanged:(v)=>…, …)` |
| Window control buttons (`hoverColor/splashColor/highlightColor: transparent`) | `TpHover(hoverColor: Colors.transparent, …)` — keep zero-feedback behavior |
| Disabled state (`onTap: null`) | `TpHover(enabled: false, …)` — stays arrow on desktop |

Keep all existing sizes, colors, `Tooltip` wrappers, and `Semantics` where present. Tooltips remain as-is (`TpHover` already composes with them).

Covered files: `client/lib/` (34 files, incl. `widgets/compose/workspace_compose_card.dart`, `widgets/compose/compose_menu_chip.dart`, `widgets/compose/compose_at_file_chip_row.dart`, `widgets/compose/compose_trigger_field.dart`, `pages/chat/session_history_thread.dart`, `pages/chat/session_cli_task_panel.dart`, `pages/home_workspace/…`, title bar, window chrome controls, diff/board/notification/git/run widgets, …) and `shared_ui` (`components/icon_button/tp_icon_button.dart`, `components/dialog/tp_dialog_nav_shell.dart`, `toast/…/close_button.dart`).

Submodule handling: `shared_ui` changes are committed in the submodule repo first, then the parent bumps the pointer. `client/packages/shared_ui` stays a submodule.

## Testing

- **Unit/widget**: no new pure logic to test beyond `TpHover`'s adaptive build. Add `flutter test` widget cases:
  - `TpHover` desktop: interactive → `SystemMouseCursors.click`; `enabled: false` → `basic`; `shape: circle` renders a circular fill.
  - `TpHover` touch: builds `Material`/`InkWell` (assert `find.byType(InkWell)`), no `MouseRegion` cursor dependency.
  - Theme: `buildLightTheme()` / `buildDarkTheme()` resolve `mouseCursor` to `click` for enabled / `basic` for disabled on a `FilledButton`/`IconButton`.
- **Gate**: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`.
- **Manual (desktop)**: hover over compose send/attach/enhance/voice/chips → hand pointer; disabled send (empty input) → arrow; hover color fades; keyboard tab + enter still activates buttons.
- **Manual (touch)**: taps show ripple, no crash, hover not painted.

## Risks / notes

- Desktop cursor now matches the app's existing hand-cursor convention app-wide; any surface that *intentionally* wanted an arrow on a clickable element must opt out by not using `TpHover` (or passing `cursor`).
- `TpHover` touch path gains ripple — a visual behavior change on Android/iOS for the 53 existing call sites; intended per the platform-adaptive decision.
- Material buttons keep M3 ink on desktop; we do **not** restyle Material internals, only cursor (and optionally a fainter splash later — out of scope).
- No l10n strings, no model/service changes, no routing changes.
