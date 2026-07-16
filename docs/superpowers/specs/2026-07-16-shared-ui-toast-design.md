# Shared UI toast (`TpToast`) — absorb toastification

**Status:** Approved  
**Date:** 2026-07-16  
**Parent:** [2026-07-15-shared-ui-design.md](./2026-07-15-shared-ui-design.md)

## Problem

Transient feedback is a first-class design-system concern, but today it lives outside `shared_ui`:

- Engine: vendored `client/packages/toastification` (overlay queue, animation, built-in layouts).
- Product facade: `AppToast` + `app_toast_theme.dart` (variants, durations, Material styling, desktop title-bar inset).
- Side effects in the same facade: `NotificationRecorder` (persist non-`info` toasts) and `AppToast.showGlobal` (router `navigatorKey` + dedupe).

v1 of shared_ui explicitly deferred toast. That leaves the component library without a toast surface, forces every host to re-vendor toastification, and keeps visual policy split across package boundaries.

## Goals

1. Absorb the toastification **engine** into `shared_ui` as a **private** implementation (`lib/src/toast/engine/`).
2. Expose a focused public API: `TpToast`, `TpToastVariant`, `TpToastAction`, `TpToastWrapper`, `TpToastConfig`, `TpToastTheme`.
3. Preserve current TeamPilot UX (flat style, single toast, top-end, pause-on-hover, always close, existing durations/accents).
4. Keep product policy in the client: notification recording, `showGlobal`, desktop title-bar margin.
5. Remove `client/packages/toastification` and the client `toastification` path dependency.
6. No compatibility aliases (`typedef AppToastVariant = TpToastVariant` forbidden).

## Non-goals

- Re-exporting toastification public types or its full `show(...)` knob surface.
- Rewriting the overlay/animation engine from scratch.
- Moving `NotificationRecorder`, notification repository/cubit, or router into `shared_ui`.
- Changing multi-toast stacking policy (`maxToastLimit: 1` stays).
- Localizing toast copy inside `shared_ui` (host supplies strings).

## Decisions

| Topic | Choice | Why |
|-------|--------|-----|
| Engine placement | **Absorb source into `shared_ui`** (not a path dep) | Toast is a design-system primitive; one package, one version |
| Public surface | **`TpToast` + config/theme only**; engine private | Stable contract; avoid leaking upstream API churn |
| Product hooks | **Thin `AppToast` in client** wraps `TpToast` + recorder + global | Honors shared_ui dependency rules |
| Call sites | Keep `AppToast.show` / `dismiss` / `showGlobal`; rename **`AppToastVariant` → `TpToastVariant`**, **`AppToastAction` → `TpToastAction`**, update `showAppToast` | Preserves NotificationRecorder side effect on every non-info show |
| Domain model | `AppNotification.variant` becomes **`TpToastVariant`** | Same enum names (`info`/`success`/`warning`/`error`); avoid duplicate enums |
| Visual defaults | Match current `appToastStyleFor` / `buildAppToastificationConfig` **and** `AppToast._buildTitle` (`TpTextStyles` + action `TextButton` row) | No intentional visual redesign in this change |
| Theme attachment | **`TpToastTheme` on `TpThemeData`** (same pattern as `TpCardTheme`); `TpToast.show` resolves via `TpTheme.of(context).toastTheme` with ColorScheme fallbacks | One theme pattern for planners; no third attachment model |
| Host surface color | Package default: `ColorScheme.surfaceContainer`. **TeamPilot must** pass `TpToastTheme(background: workspaceCard, …)` when building `TpThemeData` | Goal 3 parity; package stays free of `workspace_surface_layers` |

## Architecture

```
MaterialApp
  └─ TpToastWrapper(config: TpToastConfig(...))   // shared_ui
       └─ private toast engine overlay

UI / services
  └─ AppToast.show / showGlobal / dismiss          // client thin facade
       ├─ TpToast.show / dismiss                   // shared_ui
       └─ NotificationRecorder (non-info only)     // client
```

### Public API (`shared_ui`)

| Type | Role |
|------|------|
| `TpToastVariant` | `info`, `success`, `warning`, `error` |
| `TpToastAction` | `{ label, onPressed }` |
| `TpToast.show(context, { message, variant, action, duration })` | Present one toast (dismisses existing first when config says so) |
| `TpToast.dismiss()` | Dismiss visible toasts |
| `TpToastWrapper` | App-root host for the overlay engine |
| `TpToastConfig` | `alignment`, `itemWidth`, `maxToastLimit`, `animationDuration`, `maxTitleLines`, `maxDescriptionLines`, `marginBuilder`, default duration policy hooks as needed |
| `TpToastTheme` | background, foreground, accent(per variant), border, radius, shadow, padding, iconSize — slot on `TpThemeData`; `fromColorScheme` / defaults when unset |

`shared_ui.dart` exports only the public toast files under `components/toast/`. Nothing under `toast/engine/` is exported.

**Content layout (parity):** title row matches current `AppToast._buildTitle` — `TpTextStyles.md` / `mdSemibold` for message and action; action is a compact `TextButton` that dismisses then runs `onPressed`.

### Client facade (`AppToast`)

Retain `AppToast` as a **product** entry (not a design-system type):

- `show` / `showGlobal` / `dismiss` → `TpToast` + existing empty-message / mounted guards.
- `showGlobal`: navigatorKey lookup, 2s message dedupe (unchanged).
- After present: if `variant != info`, `NotificationRecorder.maybeCurrent?.record(...)`.
- Wire `TpToastWrapper` in `main.dart` with a `marginBuilder` that adds `kDesktopWindowTitleBarHeight` when using the custom desktop title bar (same behavior as today).
- **Required for parity:** when constructing `TpThemeData`, set toast theme background to `scheme.workspaceCard` (and keep other accents/borders matching today’s `appToastStyleFor`).

Delete engine-mapping helpers from `app_toast_theme.dart` once moved into `TpToastTheme` / config factories. Prefer deleting `app_toast_theme.dart` if nothing product-specific remains beyond wrapper config construction (e.g. `buildTeamPilotToastConfig()` living next to `AppToast`).

### Package layout

```
shared_ui/lib/
  shared_ui.dart
  src/
    components/toast/
      tp_toast.dart
      tp_toast_action.dart          # or co-located in tp_toast.dart
      tp_toast_wrapper.dart
      tp_toast_config.dart
      tp_toast_theme.dart
    toast/engine/                   # absorbed toastification (private)
      ...                           # keep structure; fix imports to package-private paths
```

### Dependencies

Add to `shared_ui/pubspec.yaml` (from current toastification):

- `collection`, `equatable`, `pausable_timer`, `uuid`

Remove from `client/pubspec.yaml`:

- `toastification: path: packages/toastification`

Delete directory `client/packages/toastification` after the absorb lands and analyzes clean.

## Behavioral defaults (parity)

| Knob | Value |
|------|-------|
| Style | Flat (engine flat layout) |
| Alignment | `AlignmentDirectional.topEnd` |
| Max toasts | `1` (show dismisses previous without delay animation, matching today) |
| Animation | ~200ms |
| Pause on hover | true |
| Drag to close | false |
| Close button | always |
| Show icon | true |
| Max title lines | 3 |
| Max description lines | 1 |
| Item width | 400 (desktop) |
| Durations | success 2s, info 3s, warning 4s, error 5s; with action 8s |
| Accents | info/warning → `primary`, success → `secondary`, error → `error` |

## Migration

1. Copy toastification sources into `shared_ui/lib/src/toast/engine/`; rewrite imports; add deps; ensure engine is not barrel-exported.
2. Implement `TpToast*` public layer + widget/unit tests (show, dismiss, theme accents, config margin/width).
3. Client: replace `ToastificationWrapper` with `TpToastWrapper`; slim `AppToast` to wrap `TpToast`; replace `AppToastVariant` / `AppToastAction` with `TpToastVariant` / `TpToastAction` everywhere (UI + `AppNotification` + `showAppToast` + tests); wire `TpToastTheme` with `workspaceCard` on `TpThemeData`.
4. Remove `toastification` dependency and delete `packages/toastification`.
5. Update docs: parent shared-ui spec amendment, `shared_ui` README component table, `CODE_QUALITY.md` / `AGENTS.md` if they still say toast stays client-only.

## Testing & acceptance

### Testing

- `shared_ui`: toast show/dismiss; variant accent colors; config `marginBuilder` / `itemWidth`; theme `fromColorScheme` defaults.
- `client`: existing notification / idle / cubit tests updated for `TpToastVariant`; thin test that non-info `AppToast.show` still records when a recorder is present (if not already covered).
- Gate: `cd client/packages/shared_ui && flutter test`; `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`.

### Acceptance

- [ ] `import 'package:shared_ui/shared_ui.dart'` exposes `TpToast` / `TpToastWrapper` / `TpToastConfig` / `TpToastTheme` / `TpToastVariant`
- [ ] No `package:toastification` imports in client or shared_ui public API
- [ ] `packages/toastification` removed
- [ ] Non-info toasts still appear in the notification center
- [ ] Desktop top margin still clears the custom title bar
- [ ] TeamPilot toast background uses `workspaceCard` via `TpToastTheme`
- [ ] No `AppToastVariant` / `AppToastAction` types remain

## Risks

| Risk | Mitigation |
|------|------------|
| Engine import / visibility mistakes leak types | Barrel export audit + analyze; engine under `src/toast/engine` only |
| Notification recording regression | Keep recording in `AppToast`, not in call-site `TpToast` migration |
| Visual drift (`workspaceCard` vs `surfaceContainer`) | Client supplies `TpToastTheme` override in wrapper wiring |
| shared_ui size growth | Acceptable; document engine as vendored private code; no upstream sync automation required for v1 |

## Amendment to parent specs

- [2026-07-15-shared-ui-design.md](./2026-07-15-shared-ui-design.md): toast moves from “explicitly out of package” to this follow-up; strike “leave toast theme entirely in client for v1” as superseded for toast **engine + TpToast**.
- [2026-07-15-shared-ui-theme-consolidation-design.md](./2026-07-15-shared-ui-theme-consolidation-design.md): toast theme ownership updates from “host-owned” to “`TpToastTheme` in package; host may override surfaces”.
