# Compose draft cache (in-memory)

## Problem

Compose input text is lost when the user navigates away from the compose host and back. Each compose surface owns its `TextEditingController` inside a `State` that is disposed on unmount:

- **Workspace "New Chat" landing** — `_UnboundComposeBodyState._controller` (`unbound_compose_body.dart`).
- **Session workbench compose** — `_SessionChatViewState._controller` (`session_chat_view.dart`).

Current keep-alive behavior:

| Scenario | Today |
|----------|-------|
| Workspace tab switch / global views (`?global=…`) | State kept alive via `TpKeepAliveLayer` → text survives |
| Session chat ↔ terminal toggle | `SessionChatView` unmounts → text lost |
| Navigate out of `HomeShell` (`/config/*`, `/providers/*`, `/team-config/*`, `/skills/*`, …) | Entire `HomeShell` subtree unmounts → text lost |
| Landing submit → session launch → back to New Chat | `UnboundComposeBody` unmounts → text lost |

The launch settings (`LandingLaunchContext`) are already persisted per workspace (`landing_draft_resolver.dart`), but the **typed message text** is not.

## Decision

Introduce a small **app-scoped, in-memory `ComposeDraftCache`** shared instance. Compose hosts restore their text from the cache on init, sync the cache on every text change, and clear the entry once the text is consumed (sent). No disk persistence; drafts survive any widget unmount/remount within the app run but are dropped on app restart.

Cache keys are per surface identity:

| Surface | Key |
|---------|-----|
| Landing compose | `workspaceId` |
| Session compose | `sessionId` |

Rejected alternatives:

- **Store drafts in `ChatCubit`** — couples transient UI draft to chat state; `ChatCubit` is already large; no benefit over a dedicated service.
- **Keep-alive only** — does not fix out-of-`HomeShell` navigation, which unmounts every compose host; more invasive than a cache.
- **Disk persistence** — user asked for in-memory only; avoids repeated writes of possibly-sensitive draft text.

## API

New file: `client/lib/services/compose/compose_draft_cache.dart`.

```dart
/// In-memory compose input draft cache, keyed by workspace (landing compose)
/// or session (session compose). Survives compose host unmounts so switching
/// away and back does not lose typed text. Not persisted to disk.
class ComposeDraftCache {
  ComposeDraftCache({Map<String, String>? store}) : _store = store ?? {};

  final Map<String, String> _store;

  static const _landingPrefix = 'landing:';
  static const _sessionPrefix = 'session:';

  // Landing compose (workspace "New Chat").
  String? landingDraft(String workspaceId);
  void setLandingDraft(String workspaceId, String text);
  void clearLandingDraft(String workspaceId);

  // Session compose (session workbench).
  String? sessionDraft(String sessionId);
  void setSessionDraft(String sessionId, String text);
  void clearSessionDraft(String sessionId);

  /// Test helper / app teardown.
  @visibleForTesting
  void clear();
}
```

Rules:

- Writing text whose `trim()` is empty **removes** the entry instead of storing it — a fully cleared input must not resurrect stale text on remount.
- The shared instance is a module-level `final` so compose hosts (which already reference services directly) can use it without DI plumbing; the class stays constructor-injectable for unit tests.

```dart
/// Shared app-scoped instance.
final ComposeDraftCache composeDraftCache = ComposeDraftCache();
```

## Integration

### Landing compose — `_UnboundComposeBodyState` (`unbound_compose_body.dart`)

- **Restore (initState):** only when `widget.initialText == null` (the normal New Chat flow). If `composeDraftCache.landingDraft(workspaceId)` is non-empty, set the controller text (selection collapsed at end). `initialText` is non-null only for Selection → Ask AI, which is a one-shot input and must neither read nor write the landing draft.
- **Sync:** add a `_controller` listener that writes the current text to the cache on every change (covers typing, voice insert, enhance, programmatic edits). The listener must **not** call `setState`.
- **Clear on consume:** the workspace chat pane (`workspace_chat_pane.dart::_submit`) passes an `onSessionOpened` callback into `submitWorkspaceLandingMessage` that calls `composeDraftCache.clearLandingDraft(workspace.workspaceId)`. The callback fires once the session tab is staged (`SessionOpenStatus.opened`), so the draft is cleared only after the message is actually consumed; on a failed launch the draft stays so the user can retry. The Selection → Ask AI caller keeps its own `onSessionOpened` (dialog dismiss) and does **not** clear the landing draft — its message is separate and the user's New Chat draft is unconsumed.

### Session compose — `_SessionChatViewState` (`session_chat_view.dart`)

- **Restore (initState):** if `composeDraftCache.sessionDraft(widget.session.sessionId)` is non-empty, set the controller text before any user interaction.
- **Sync:** in the existing `_onComposeChanged` listener, write the current text to the cache.
- **Restore-guard:** the restore sets the controller value inside `initState`, which synchronously notifies `_onComposeChanged`; guard that listener's `setState` with a `_restoringDraft` flag (set during restore) to avoid `setState` during mount.
- **Clear on send:** automatic — `_controller.clear()` on send notifies the listener → empty text removes the cache entry. On a failed send the text is restored (`_controller..text = text`) → the listener writes it back. No explicit clear needed.

### Lifecycle cleanup

Drafts must not outlive the thing they belong to:

- `ChatCubit.deleteSession(repo, sessionId)` → `composeDraftCache.clearSessionDraft(sessionId)`. `ChatCubit.deleteWorkspace` already calls `deleteSession` for every session id, so clearing the session draft there covers each session of a deleted workspace.
- `ChatCubit.deleteWorkspace(repo, workspaceId)` → `composeDraftCache.clearLandingDraft(workspaceId)` for the removed workspace.

## Data flow

```
User types ──► controller listener ──► composeDraftCache.set*Draft(key, text)
                                              │
Navigate away (host unmounts, controller disposed)
                                              │
Navigate back (host remounts)
                                              ▼
initState: draft = composeDraftCache.*Draft(key)
           controller.value = draft          (restoringDraft guard → no setState)
User hits send ──► controller.clear() / session opened
                                              │
                                              ▼
composeDraftCache.clear*Draft(key)
```

## Edge cases

- **Empty input:** writing trimmed-empty removes the entry; nothing is restored on remount.
- **Failed send:** session compose rolls the text back and the listener re-writes it; landing keeps its entry until a session actually opens.
- **Selection → Ask AI:** `initialText != null` → no read and no write of the landing draft, so Ask AI cannot clobber the user's New Chat draft.
- **Member switch within a session:** `SessionChatView` state is reused across seat changes; the cache is keyed by session only, so the draft follows the session.
- **Memory:** entries are removed on send and on session/workspace deletion; otherwise bounded by the number of workspaces/sessions touched this run.

## Testing

- **Unit** — `ComposeDraftCache` get/set/clear, trimmed-empty write removes the entry, `clear()` resets all.
- **Widget** — landing compose restores a cached draft on mount and does not touch the cache when `initialText` is provided; session compose restores its draft; send clears the cache entry (or, for landing, session-open clears it).
  - Reference mount harness: `workspace_chat_landing_initial_text_test.dart`, `workspace_compose_card_test.dart`.
  - Reset the shared instance in `setUp` (`composeDraftCache.clear()`) so tests do not leak state into each other.

## Non-goals

- Ask AI one-shot compose.
- Disk persistence / surviving app restart.
- Voice recording session state (baseline text is already handled in memory by the compose hosts).
