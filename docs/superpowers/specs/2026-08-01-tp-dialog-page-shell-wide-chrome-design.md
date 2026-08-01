# TpDialogPageShell wide chrome (desktop card restore)

**Date:** 2026-08-01  
**Status:** Approved  
**Product:** TeamPilot (`client/`) + `shared_ui`  
**Amends:** [2026-07-30-mobile-drawer-dialog-design.md](./2026-07-30-mobile-drawer-dialog-design.md) §2 (`TpDialogPageShell` / Wide + `page`)  
**Decision:** Approach B — adaptive `TpDialogPageShell` (not per-host forks; not reverting wide hosts to `presentation: card`)

## Problem

After Appendix A migrated to `showTpDialog(presentation: page)` + `TpDialogPageShell`, **wide (desktop) cards** lost the pre-migration look:

1. **Mobile nav chrome on desktop** — leading chevron + phone-style bar instead of `TpDialogHeader` (title + close).
2. **Forced tall empty body** — PageShell always `Expanded`-fills the outer `TpDialog` `maxHeight`, so short forms (e.g. 新建团队) show a large blank region under the actions.
3. **Tighter host paddings** — many hosts use `fromLTRB(16, 0, 16, 16)` assuming PageShell owns zero outer inset; on wide that replaces the old `kTpDialogContentPadding` (`32/28`).

Narrow full-bleed page behavior is correct and must stay. `TpDialogNavShell` is out of scope (wide dual-pane is intentional). Landing team settings and other NavShell hosts are **out of this wave**.

## Goals

1. Wide + simple page Dialogs restore **desktop card chrome**: `TpDialogHeader` + theme content padding; short content **shrink-wraps** when the host does not use flex fill.
2. Narrow + page unchanged: mobile nav bar, `Expanded` body, SafeArea.
3. Fix lives primarily in **`shared_ui`**; teampilot hosts **must** pass matching `mobileBreakpoint`, set `fillBody` correctly, and **remove duplicate 16 outer paddings** in the same change.
4. Keep `presentation: page` for Appendix A (no split card/page entry points).

## Non-goals

- Changing `TpDialogNavShell` wide/narrow layout.
- Redesigning form field layouts (mode cards, inputs) beyond shell chrome/padding.
- Heuristic “is this large?” detection — hosts still opt into `page` explicitly.
- Changing narrow page route (`showGeneralDialog` fullscreen).
- Forcing every editor to shrink-wrap in this wave (editors that already use `Expanded` + pinned footer keep `fillBody: true`).

## Decisions

| Topic | Choice | Why |
|-------|--------|-----|
| Where to fix | Adaptive `TpDialogPageShell` | One chrome owner; Appendix A already wraps it |
| Wide detection | `MediaQuery.sizeOf(context).width < mobileBreakpoint` | Same rule as `showTpDialog` / NavShell |
| Breakpoint param | Required in practice: teampilot **always** passes `WorkspacePanePolicy.narrowBreakpointWidth` (**840**), identical to the paired `showTpDialog` call | Avoid 768–840 chrome mismatch (fullscreen route + desktop header) |
| Package default | `mobileBreakpoint = 768` (shared_ui default only) | Non-teampilot hosts; teampilot must not rely on default |
| Wide header | `TpDialogHeader(showDividerBelow: false, titleAlignment: …)` | Pre-migration card affordance; divider off is **hard** |
| Wide title alignment | Default `Alignment.topLeft` (matches `TpDialogHeader`); hosts that want centered titles pass `Alignment.center` (新建团队) | Lists/editors stay left-aligned |
| Wide SafeArea | **None** on wide | Card already inset from viewport |
| Wide body size | `fillBody: false` → shrink-wrap; `fillBody: true` → `Expanded` under header | Short scroll forms compact; flex hosts / lists fill |
| Host flex rule | If PageShell `child` contains a vertical `Expanded` / pinned flex footer pattern, host **must** use `fillBody: true` | Otherwise Flutter asserts or layout is undefined |
| Outer `showTpDialog` wide wrap | Keep `TpDialog(contentPadding: EdgeInsets.zero, …)` | Shell owns inset; NavShell shares zero-pad card |
| Host padding | **Same PR hard rule:** strip host outer `fromLTRB(16,…)` (or equivalent) that duplicates shell padding on **wide**; narrow may keep 16 **only if** shell does not pad the body the same way — prefer: shell pads on wide only; on narrow shell does not add theme contentPadding (mobile full-bleed), so host 16 may remain for narrow. Cleanest: gate host padding with the same breakpoint, or move 16 into shell narrow branch as a separate token later. **Minimum for this wave:** on wide, no host+shell double horizontal inset. |
| NavShell | Unchanged | Dual-pane already correct on wide |

## API

```dart
class TpDialogPageShell extends StatelessWidget {
  const TpDialogPageShell({
    required this.title,
    required this.child,
    this.onClose,
    this.trailing,
    this.mobileBreakpoint = 768,
    this.fillBody = false,
    this.titleAlignment = Alignment.topLeft,
    super.key,
  });

  final String title;
  final Widget child;
  final VoidCallback? onClose;
  final Widget? trailing;
  /// Must match the paired [showTpDialog] `mobileBreakpoint` when used inside it.
  final double mobileBreakpoint;
  /// Wide only: expand body under header. Narrow always expands (ignored).
  /// Required `true` when [child] uses vertical [Expanded].
  final bool fillBody;
  /// Wide header only; narrow keeps centered mobile title.
  final Alignment titleAlignment;
}
```

Update dartdoc: PageShell is chrome for **simple page Dialogs on both narrow and wide**, not “narrow only”.

### Wide layout structure (normative)

`h` = `dialogTheme.contentHorizontalInset` (32)  
`vTop` / `vBottom` = vertical components of `dialogTheme.contentPadding` (28 / 28)  
`close` = `onClose ?? () => Navigator.of(context).pop()`

```text
// WIDE (width >= mobileBreakpoint)
Column(
  crossAxisAlignment: stretch,
  mainAxisSize: fillBody ? max : min,
  children: [
    Padding(
      padding: EdgeInsets.fromLTRB(h, vTop, h, 0),
      child: TpDialogHeader(
        title: title,
        onClose: close,
        titleAlignment: titleAlignment,
        showDividerBelow: false,   // hard
        trailing: trailing,
        horizontalInset: 0,        // already padded by parent
      ),
    ),
    if (!fillBody)
      Padding(
        padding: EdgeInsets.fromLTRB(h, /* gap below header */ 20, h, vBottom),
        child: child,              // host should be scrollable if tall
      )
    else
      Expanded(
        child: Padding(
          padding: EdgeInsets.fromLTRB(h, 0, h, vBottom),
          child: child,            // host may use Expanded inside
        ),
      ),
  ],
)
```

```text
// NARROW — unchanged
Column(
  children: [
    TpDialogMobileNavBar(...),
    Expanded(child: SafeArea(top: false, child: child)),
  ],
)
```

### `fillBody: false` sizing contract (normative)

Wide shell does **not** put `child` in `Expanded` / `Flexible`. For the card to
shrink-wrap, `child` must report an **intrinsic** height under bounded max
constraints:

- Prefer `Column(mainAxisSize: MainAxisSize.min, …)` (no outer expanding scroll).
- Do **not** put a default `SingleChildScrollView` as the wide PageShell `child` —
  under a bounded `TpDialog.maxHeight` it expands to the max and recreates a tall
  empty card. (`SingleChildScrollView` has no `shrinkWrap`; use `Column(min)` on
  wide, and scroll only inside narrow `Expanded` or a host that already `fillBody`s.)

If content may exceed `maxHeight` on wide, either raise scrolling inside a
`fillBody: true` pinned layout, or accept overflow for rare short viewports.

## Host policy (teampilot)

**Contract:** every `TpDialogPageShell` call passes `mobileBreakpoint:` equal to that dialog’s `showTpDialog(..., mobileBreakpoint:)`.

| Surface | `fillBody` | `titleAlignment` | Why / padding |
|---------|------------|------------------|---------------|
| `home_workspace_new_team_dialog` | `false` | `center` | Wide: `Column(min)` only; narrow: `SingleChildScrollView` inside Expanded; drop wide duplicate 16 |
| `mcp_oauth_connect_dialog` | `false` | `topLeft` | No vertical Expanded; ensure intrinsic height; drop wide duplicate 16 |
| `automation_editor_dialog` | `true` | `topLeft` | `Expanded` + scroll + pinned actions |
| `expert_editor_dialog` | `true` | `topLeft` | same |
| `ssh_profile_form_dialog` | `true` | `topLeft` | same |
| `run_config_editor_dialog` | `true` | `topLeft` | same |
| `automations_dialog` | `true` | `topLeft` | list panel; keep `trailing` |
| `run_configurations_dialog` | `true` | `topLeft` | list panel |
| `workspace_search_dialog` | `true` | `topLeft` | search panel |

**Same-PR padding rule:** for each row above, remove or breakpoint-gate outer `EdgeInsets.fromLTRB(16, …)` so wide horizontal inset is shell `h` only (≈32), not 32+16.

## Spec amendments to 2026-07-30 (paste-ready)

Replace § `TpDialogPageShell` hard rules with:

- Used **only** for simple (non-NavShell) page Dialogs.
- **Narrow:** fills the fullscreen overlay; `TpDialogMobileNavBar`; `Expanded` + `SafeArea(top: false)` body; no theme contentPadding from the shell.
- **Wide:** desktop card chrome via the **same** widget — `TpDialogHeader` (`showDividerBelow: false`), theme content padding as in the wide layout tree above; default shrink-wrap unless `fillBody: true`.
- Never wrap `TpDialogNavShell`.
- `mobileBreakpoint` must match the paired `showTpDialog` call.

Replace § Wide + `page` bullet with:

- Outer route remains constrained `TpDialog` with **zero** content padding.
- Simple pages rely on `TpDialogPageShell`’s wide branch for header, padding, and height behavior.
- Dual-pane: `TpDialogNavShell` unchanged.

Add parent-spec note: **Amended by** `2026-08-01-tp-dialog-page-shell-wide-chrome-design.md`.

## Tests

### `shared_ui`

1. Narrow (`width < breakpoint`): `TpDialogMobileNavBar` present; no `TpDialogHeader`; body Expanded/fills.
2. Wide + `fillBody: false` + short **intrinsic** child (`Column(min)` or `SingleChildScrollView(shrinkWrap: true)`): `TpDialogHeader` present; shell height ≪ outer `maxHeight` (no large empty band). Do **not** use default `SingleChildScrollView` as the short-content fixture.
3. Wide + `fillBody: true`: body expands under header within outer max constraints; host `Expanded` child does not assert.
4. Wide header padding: title not flush to dialog edge (≈ horizontal inset 32).
5. Close pops in both modes (header close + mobile leading).
6. `trailing` on wide appears in header row (smoke).
7. **Breakpoint mismatch guard (documentation test or comment + host audit):** teampilot call sites must pass the same breakpoint; optional widget test documenting that `showTpDialog(840)` + `PageShell(768)` at width 800 is unsupported / fails chrome expectations.

### teampilot (required)

1. **新建团队 wide:** no mobile chevron bar; no large empty band under actions; horizontal gutter ≈ theme content padding after padding strip.
2. Automations list wide + `fillBody`: still tall/usable; `trailing` actions work; update existing page test if it assumed mobile chrome on wide.

## Risks

| Risk | Mitigation |
|------|------------|
| Double padding | Same-PR host strip / breakpoint-gate |
| Editors stay tall on desktop | Accepted this wave (`fillBody: true`); optional later refactor to pinned-layout shrink |
| Breakpoint drift 768 vs 840 | Mandatory matching params; call-site audit in PR |
| Tall `fillBody: false` overflow | Host must scroll with intrinsic sizing; covered in sizing contract |
| `fillBody: false` + default ScrollView | Still fills maxHeight; mitigate via sizing contract + new-team same-PR fix |

## Implementation sketch (not a plan)

1. TDD: PageShell wide/narrow / fillBody tests in `shared_ui`.
2. Implement adaptive build + params; update README dartdoc.
3. Wire teampilot hosts per Host policy table; strip wide duplicate 16 padding.
4. Amend 2026-07-30 spec with Amended-by + hard-rule replace.
5. If `shared_ui` is published as a separate git commit/submodule from the app tree, bump the pointer; otherwise land as one workspace change.
