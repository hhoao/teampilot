# Session launch failure surface (Chat + Terminal)

## Goal

When a session terminal fails to start, the user must see a clear, actionable failure message on **both** the Chat and Terminal workbench surfaces, with a shared **Retry** action. Failure must not depend on which view the user happens to be on after launch.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Surfaces | **Both** Chat and Terminal show the failure |
| Terminal actions | Error copy + **Retry** |
| Chat actions | Same as Terminal (error + Retry); keep dead-SSH remap when applicable |
| Error source | Existing session-level `ChatTabInfo.launchError` / `ChatState.sessionLaunchError` via `failSessionConnect` / `clearLaunchError` |
| Presentation | Shared `SessionLaunchErrorBanner` driven by a `SessionLaunchFailurePresenter` |
| Terminal chrome | Top-of-pane banner overlay — **not** a full-page `launchFailed` overlay |
| View switching | **Do not** force Chat↔Terminal on failure or retry |
| Retry API | `ChatCubit.retrySessionLaunch(sessionId)` → `connectWorkspaceSession(ExistingSessionConnect…)` with `preserveWorkbenchView: true` |
| Connecting UX | Hide banner while `sessionConnectingId` matches; Terminal may show existing `sessionStarting` spinner |
| Extra channels | No Snackbar/Toast for launch failure (banner only) |
| Team errors | Remain **session-scoped** in v1; Retry targets **selected seat** (same resolution as Terminal toggle reconnect) |

## Non-goals

- Per-member `launchError` map (extensibility reserved; not in v1)
- Auto-switch workbench view on failure
- Replacing terminal `writeToDisplay` diagnostics (banner is the product layer; buffer text stays)
- Changing launch pipeline / `TerminalLaunchController` failure detection itself
- New `ChatWorkbenchOverlay.launchFailed` enum value
- Blocking compose submit solely because of a prior launch error (existing continue/connect paths stay)

## Problem

Launch failures already flow into `launchError` and render inside `SessionReviewComposeCard` on the **Chat** surface. Typical open/launch paths set `SessionWorkbenchView.terminal`, so after `failSessionConnect` the connecting spinner clears and the user stays on Terminal with **no** compose banner. The failure is easy to miss (only optional terminal buffer text via `writeToDisplay`). Chat also lacks a Retry CTA on the existing inline error block.

## Design

### 1. Data flow (unchanged ownership)

```
TerminalLaunchController / SessionShellConnector / launch pipeline
        │
        ▼
ChatConnectStateMixin.failSessionConnect(sessionId, raw)
        │  formatSessionLaunchError(raw)
        ▼
ChatTabInfo.launchError  (open tab)
  or ChatState.sessionLaunchError  (pending / no tab)
        │
        ▼
SessionLaunchFailurePresenter.from(rawMessage)  →  view model
        │
   ┌────┴────┐
   ▼         ▼
 Chat banner   Terminal banner
```

Success path unchanged: `onProcessStarted` / `beginSessionConnect` / `clearLaunchError` clear the message.

### 2. `SessionLaunchFailurePresenter`

Pure (or near-pure) assembler — no Flutter widgets. Input: formatted or raw launch error string (call sites may pass already-formatted tab error). Output:

```dart
final class SessionLaunchFailureView {
  const SessionLaunchFailureView({
    required this.message,
    required this.actions,
  });

  final String message;
  final List<SessionLaunchFailureAction> actions;
}

enum SessionLaunchFailureActionKind { retry, remapDeadSsh }

final class SessionLaunchFailureAction {
  const SessionLaunchFailureAction({
    required this.kind,
    this.deadSshTargetId,
  });

  final SessionLaunchFailureActionKind kind;
  final String? deadSshTargetId;
}
```

Rules:

- Empty / whitespace-only message → no view (callers render nothing).
- Always include `retry` when there is a message.
- If `deadSshTargetIdFromError(message)` is non-null, include `remapDeadSsh` **before** `retry` (remap is the preferred fix when the profile is missing).
- Message text remains the product-facing string already stored on the tab (post-`formatSessionLaunchError`).

Future actions (e.g. open Machines) extend the enum + presenter only; banner maps kinds to buttons.

### 3. `SessionLaunchErrorBanner`

Shared widget under `client/lib/pages/chat/`:

- Visual language: `errorContainer` / `onErrorContainer`, bordered, rounded — match today’s compose inline error.
- Body: multi-line message (already capped by `formatSessionLaunchError`).
- Buttons from presenter actions:
  - `retry` → `sessionRetryButton` / loading when `isRetrying`
  - `remapDeadSsh` → existing `workspaceDeadTargetRemapFromLaunch` callback
- Props: `SessionLaunchFailureView view`, `VoidCallback? onRetry`, `VoidCallback? onRemapDeadTarget`, `bool isRetrying`.

### 4. Visibility matrix

| State | Chat | Terminal |
|-------|------|----------|
| Connecting (`sessionConnectingId` == active session) | Banner hidden (Chat stay-mounted continue unchanged) | `sessionStarting` full overlay; banner hidden |
| Failed + idle (`launchError` set, not connecting) | Banner above compose | Top banner over workbench; terminal may be empty/offstage |
| Running / no error | None | None |

Do **not** add `ChatWorkbenchOverlay.launchFailed`. Keep overlay enum as-is; banner is an independent layer in the workbench `Stack` (Terminal) or compose column (Chat).

### 5. Chat mount

- Replace the inline error `DecoratedBox` inside `SessionReviewComposeCard` with `SessionLaunchErrorBanner`.
- Wire `onRetry` → `ChatCubit.retrySessionLaunch(sessionId)`.
- Keep `onRemapDeadTarget` path from workbench (unchanged remap flow).
- `isRetrying` derived from active session connecting id (or a local submitting flag if cubit connect is in flight for that id).

### 6. Terminal mount

In `chat_workbench.dart` terminal `Stack` (alongside chat / starting / remote provision):

- When workbench is Terminal (overlay `none` or terminal visible) **and** `launchError` is non-null **and** not connecting → paint `SessionLaunchErrorBanner` at the **top** of the pane (padding via Tp spacing).
- Do not cover the full pane; leave room for any mounted terminal / empty surface beneath.
- Same retry / remap callbacks as Chat.

### 7. `ChatCubit.retrySessionLaunch`

Thin, testable entry used by both banners (and optionally later by other chrome):

1. Resolve open tab + `AppSession` for `sessionId`.
2. Resolve team/member the same way as `SessionWorkbenchViewToggle` when switching Chat→Terminal and the shell is not running:
   - Simple → no team/member
   - Team → `selectedMemberId`, else lead, else first member
3. Call `connectWorkspaceSession(ExistingSessionConnect(..., preserveWorkbenchView: true))`.
4. Do not change `workbenchView`.

Optional cleanup: extract shared “resolve ExistingSessionConnect for open tab” helper used by the toggle and `retrySessionLaunch` to avoid drift.

### 8. Dead SSH

Unchanged remap UX from Chat workbench (`onRemapDeadTargetFromLaunch`). Presenter only decides button presence/order; remap implementation stays in workbench.

### 9. Extensibility notes

| Future need | Hook |
|-------------|------|
| Per-member errors | Store map on tab; Presenter filters by selected seat; banner API unchanged |
| Extra CTAs | New `SessionLaunchFailureActionKind` + presenter rule |
| Full-page failure | Optional overlay enum later — not required while top banner + buffer exist |
| Localized coded errors | Extend `formatSessionLaunchError` / presenter; UI stays dumb |

## Testing

1. **Presenter unit** — normal message → retry only; dead-SSH text → remap then retry; empty → null/empty.
2. **Visibility** — connecting hides banner; failed+chat and failed+terminal show banner; running clears.
3. **Widget** — banner Retry invokes callback; remap button only when action present.
4. **Cubit** — `retrySessionLaunch` issues `ExistingSessionConnect` with `preserveWorkbenchView: true` and correct member resolution.
5. **Regression** — `formatSessionLaunchError` tests; dead-SSH remap from launch; Terminal toggle reconnect still works.

## File map (expected)

| File | Role |
|------|------|
| `client/lib/pages/chat/session_launch_failure_presenter.dart` | View model + action rules |
| `client/lib/pages/chat/session_launch_error_banner.dart` | Shared banner UI |
| `client/lib/pages/chat/session_review_compose_card.dart` | Use shared banner + Retry |
| `client/lib/pages/chat_workbench.dart` | Terminal top banner mount + retry wiring |
| `client/lib/cubits/chat_cubit.dart` (+ launch service if needed) | `retrySessionLaunch` |
| `client/lib/pages/chat/session_workbench_view_toggle.dart` | Optional: share connect resolution helper |
| Tests under `client/test/pages/chat/` and `client/test/cubits/chat/` | Presenter, visibility, retry |

## Out of scope follow-ups

- Per-member launch error surface in Members panel
- Auto-navigate to Machines / SSH settings beyond existing remap
- l10n of every raw CLI spawn string (keep formatter truncation; improve codes opportunistically)
