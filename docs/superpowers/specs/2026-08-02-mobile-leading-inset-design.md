# Mobile leading inset for edge-adjacent controls

**Date:** 2026-08-02  
**Status:** Approved for planning  
**Problem:** On curved-edge phones, leftmost interactive chrome (especially settings hub `BackButton`) sits too close to the physical edge. The home title-bar hamburger already has a comfortable **16px** left spacer on mobile; other leading controls do not share that inset.

**Builds on:** `TpSidebarTrigger` / `HomeTitleBar` mobile leading spacer (`compactChrome ? 16 : 8`), `_settingsChromeShell` AppBar `BackButton`, `WorkspacePaneHeader` back `IconButton`, `WorkspaceChatLanding` positioned back `TpIconButton`, `TpSidebarScope.isMobile`, `WorkspacePanePolicy.narrowBreakpointWidth` (840).

## Goal

Introduce a shared **mobile leading inset** token and a small wrapper in `shared_ui`, then migrate the first wave of leftmost navigation controls so they match the hamburger’s edge comfort on narrow layouts.

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Scope pattern | Token + `TpMobileLeading` wrapper (not AppBar-theme-only, not a one-off Padding) |
| Inset value | **16** logical px — same as home title-bar hamburger spacer |
| When applied | Mobile / narrow only; desktop / wide unchanged |
| Mobile detection | Prefer `TpSidebarScope.maybeOf(context)?.isMobile`; if no scope, fall back to width `< TpMobileChrome.narrowBreakpointWidth` (840, aligned with `WorkspacePanePolicy`); optional `force` for tests / hosts |
| SafeArea | Wrapper adds inset **in addition to** SafeArea; it does not replace system padding |
| First migration (wave B) | Home title-bar token swap; settings AppBar `BackButton`; workspace chat landing back. **Do not** wrap `WorkspacePaneHeader` back when the host already applies `WorkspacePaneInsets.page` (left 44 ≥ inset) |
| Out of scope (v1) | Right-edge actions, non-nav IconButtons, sweeping all left IconButtons, stacking inset on top of existing large page paddings |

## Non-goals

- Redesigning back icons, tap sizes, or AppBar title layout beyond `leadingWidth` when needed
- Changing desktop / wide chrome spacing
- Applying trailing (right) edge insets in v1
- Replacing `TpSidebarTrigger` or inventing a full `TpBackButton` product component
- Persisting or making the inset user-configurable

## Invariants

1. **`TpMobileChrome.leadingInset == 16`** and is the single source of truth for this mobile left spacer.
2. **Wide / non-mobile:** `TpMobileLeading` must not add horizontal padding (unless `force`).
3. **Home hamburger spacer** uses `TpMobileChrome.leadingInset` instead of a magic `16`.
4. **Settings hub detail AppBar** leading back affordance is wrapped so its visual left edge clears the curved edge like the hamburger; `leadingWidth` is raised when the inset would otherwise clip the control.
5. **Landing back** uses the same inset semantics on mobile (left edge ≥ `leadingInset`).
6. **Do not double-inset** controls that already sit inside a host padding ≥ `leadingInset` (e.g. `WorkspacePaneHeader` under `WorkspacePaneInsets.page`).
7. Existing drawer / back navigation behavior is unchanged — only spacing.

## Design

### 1. shared_ui API

Add:

```dart
abstract final class TpMobileChrome {
  /// Left inset for edge-adjacent controls on curved / narrow screens.
  /// Matches home title-bar hamburger spacing.
  static const double leadingInset = 16;

  /// Narrow / mobile width fallback when no [TpSidebarScope] is present.
  /// Keep equal to app `WorkspacePanePolicy.narrowBreakpointWidth`.
  static const double narrowBreakpointWidth = 840;
}

class TpMobileLeading extends StatelessWidget {
  const TpMobileLeading({
    required this.child,
    this.force = false,
    super.key,
  });

  final Widget child;
  final bool force;
}
```

`TpMobileLeading` behavior:

- If `force` **or** mobile (sidebar scope / width `< narrowBreakpointWidth`): wrap `child` with `Padding(padding: EdgeInsets.only(left: TpMobileChrome.leadingInset))`.
- Else: return `child` unchanged.
- Does not change icon size, button min size, tooltips, or SafeArea.

Export from `shared_ui`.

Prefer reading sidebar scope when present so hosts that already decided mobile stay consistent.

### 2. First migration call sites

| Location | Change |
|----------|--------|
| `home_workspace_title_bar.dart` | Replace magic `16` in `SizedBox(width: compactChrome ? 16 : 8)` with `TpMobileChrome.leadingInset` |
| `app_router.dart` `_settingsChromeShell` | When `hideDrawer`, wrap `BackButton` in `TpMobileLeading`; set `AppBar.leadingWidth` to default leading width **+** `leadingInset` so the icon is not clipped |
| `workspace_chat_landing.dart` | On mobile, ensure the positioned back control’s left edge respects at least `leadingInset` (e.g. `left: max(spacing.md, leadingInset)` when mobile, or wrap with `TpMobileLeading` inside the `Positioned`) |
| `workspace_pane_header.dart` | **No wrap in v1** when used under `WorkspacePaneInsets.page` (left 44). Android hub detail already uses AppBar back via `_settingsChromeShell`. Revisit only if a host places the header flush to the screen edge |

Do **not** change the hamburger/`TpSidebarTrigger` itself beyond the title-bar spacer token swap; drawer open behavior stays the same.

### 3. AppBar leadingWidth

Material `AppBar` default `leadingWidth` is insufficient once an extra 16px precedes the back control. For the settings chrome path that uses `TpMobileLeading` + `BackButton`, set:

`leadingWidth ≈ kToolbarHeight (or current effective leading width) + TpMobileChrome.leadingInset`

so the back icon retains full tap target and is not horizontally compressed.

When the AppBar shows `TpSidebarTrigger` instead of back, keep current leading layout (no forced extra inset on that path beyond what the trigger’s parent already provides, if any).

### 4. Testing

**shared_ui**

- `TpMobileLeading` with `force: true` → left padding equals `leadingInset`.
- Non-mobile width, `force: false`, no sidebar mobile → no extra left padding.
- Mobile via scope or narrow width → left padding equals `leadingInset`.
- Assert `TpMobileChrome.leadingInset == 16`.

**app**

- Settings chrome hub-detail: still finds `BackButton`; leading uses `TpMobileLeading` (or measured left edge ≥ inset); back icon not clipped (`leadingWidth`).
- Landing back on narrow width: left edge respects inset.
- Existing `android_settings_chrome_drawer_test` and landing chrome tests continue to pass; extend assertions as needed.
- No requirement to wrap `WorkspacePaneHeader` in v1.

### 5. Manual check

- Narrow phone / emulator, settings detail: back control is inset similarly to home hamburger.
- Wide layout: no extra dead space before back / pane header back / landing back.

## File map (expected)

| File | Role |
|------|------|
| `client/packages/shared_ui/lib/src/…/tp_mobile_chrome.dart` (or under `components/chrome/`) | Token + `TpMobileLeading` |
| `client/packages/shared_ui/lib/shared_ui.dart` | Export |
| `client/packages/shared_ui/test/…` | Wrapper / token tests |
| `client/lib/pages/home_workspace/home_workspace_title_bar.dart` | Token swap |
| `client/lib/router/app_router.dart` | Settings AppBar leading + `leadingWidth` |
| `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart` | Mobile left inset |
| Related widget tests under `client/test/` | Assertions |

## Follow-ups (not v1)

- Migrate other leftmost mobile controls discovered later onto `TpMobileLeading`.
- Optional trailing inset for right-edge curved screens.
- Optional dedicated `TpBackButton` if product wants one control for all back affordances.
