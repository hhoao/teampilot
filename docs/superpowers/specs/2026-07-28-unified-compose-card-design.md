# Unified Compose Card

## Goal

Replace the parallel Landing and Session continue compose cards with one
**`WorkspaceComposeCard`** driven by sealed **`ComposeChrome`** (unbound |
bound). File drop, attach, and paste-image share one path. Selection Ask AI
hosts the same card directly instead of nesting `WorkspaceChatLanding`.

Aligns with [unified chat surface](2026-07-21-unified-chat-surface-design.md):
shared bottom compose pipeline; chrome branches by Chat state.

## Product decisions

| Decision | Choice |
|----------|--------|
| Architecture | Single compose card + chrome modes (not a drop-only patch) |
| Bound chrome | Keep full existing capabilities (identity, same-CLI preset, permission, team settings, launch error / dead-SSH remap, `composeEnabled`, floating) |
| Unbound chrome | Keep full existing launch toolbar (conversation mode, preset/team, expert, permission, team settings) |
| Ask AI | Mount unified card + unbound host; no nested Landing page |
| Drop semantics | Insert `@` path references via compose ingestor (unchanged). Terminal path inject stays on `TerminalDropIngestor` |
| Workload | Prefer best extensibility over incremental patch size |

## Architecture

```
Host (Landing / SessionChat / AskAiDialog)
  ├─ draft / submit / enhance / voice / workspaceRoot
  └─ WorkspaceComposeCard
        ├─ ComposeFileDropRegion  →  ComposeFileDropIngestor
        ├─ ComposeFocusShell + ComposeTriggerField
        ├─ chrome toolbar (UnboundComposeChrome | BoundComposeChrome)
        └─ shared trailing actions (attach / enhance / voice / send)
```

| Layer | Responsibility | Not responsible for |
|-------|----------------|---------------------|
| Host | State machine, submit, directory resolution, permission lock | Drop wiring details, field layout |
| `WorkspaceComposeCard` | Unified UI skeleton and drop region | Creating sessions / opening Terminal |
| `ComposeFileDropIngestor` | Files → `@` references into the controller | Terminal path inject |
| DnD primitives | OS / tree drag hit-testing | Compose semantics |

Landing **page** chrome (back, project/worktree header) stays on the Landing
host. Ask AI is card + dismiss only.

## Component API

### `ComposeChrome`

```dart
sealed class ComposeChrome {
  const ComposeChrome();
}

/// New-chat / Ask AI: mode · preset/team · expert · permission · team settings
final class UnboundComposeChrome extends ComposeChrome { /* existing unbound fields */ }

/// Bound continue: identity · same-CLI preset · permission · team settings
/// + optional launchError / remap / floating / composeEnabled
final class BoundComposeChrome extends ComposeChrome { /* existing bound fields */ }
```

### `WorkspaceComposeCard`

| Group | Fields |
|-------|--------|
| Input | `controller`, `focusNode`, `hint`, `onChanged`, `onSubmit`, `canSubmit`, `isSubmitting` |
| Field ecosystem | `workspaceRoot`, skills, plugins, `slashBundle`, `onPasteImage` |
| Drop | **Required** `dropTarget: WorkspaceDropTarget` (host builds `ComposeFileDropIngestor`) |
| Trailing actions | attach / enhance / voice (incl. recording state) / send / optional `submitBlockedTooltip` |
| Chrome | `ComposeChrome chrome` |
| Perf | `deferFieldMount` — `true` only on primary Landing path; Ask AI / Session default `false` |

The card always wraps content in `ComposeFileDropRegion` (`ExternalFileDropRegion` +
`WorkspaceFileDropRegion`). Drop is not optional at the card boundary so new
hosts cannot forget it.

### Drop / attach / paste data flow

```
OS or file-tree drag
  → ComposeFileDropRegion
  → ComposeFileDropIngestor(workspaceRoot, onInsertReferences)
  → insertComposeReferences(controller)
  → host setState + focus

Attach button / paste image
  → pickAndInsert… / pasteComposeImageAttachment (existing host helpers)
  → same controller
```

### Host wiring

| Host | Chrome | `workspaceRoot` for drop | Submit |
|------|--------|--------------------------|--------|
| `WorkspaceChatLanding` | `UnboundComposeChrome` | `_activeLaunchDirectory()` | Existing landing submit |
| `SessionChatView` | `BoundComposeChrome` | `_workspaceRoot` | Existing continue submit |
| `_SelectionAskAiDialog` | `UnboundComposeChrome` via shared unbound host | Same as Landing | Existing Ask AI submit; **no** nested `WorkspaceChatLanding` |

### `UnboundComposeHost`

Extract Landing draft/enhance/voice/attach/drop/paste controller logic into a
shared host helper (mixin or small controller) used by Landing and Ask AI so
Ask AI does not re-copy state.

Rename: `ComposeLandingDropIngestor` → `ComposeFileDropIngestor`.

## Migration

1. Rename ingestor; add `ComposeFileDropRegion`; update unit tests.
2. Introduce `WorkspaceComposeCard` + `ComposeChrome`; move toolbars from the two cards.
3. Extract `UnboundComposeHost`; wire Landing and Ask AI.
4. Wire Session with required drop target.
5. Delete `WorkspaceChatLandingComposeCard` and `SessionReviewComposeCard`.
6. Remove Ask AI’s use of `showLandingChrome: false`. If that flag exists only for
   Ask AI, delete it; otherwise keep only as an internal Landing layout switch
   unused by Ask AI.

## Success criteria

- Landing, Session continue, and Ask AI share one card implementation.
- Drop / attach / paste-image insert `@` references consistently on all three.
- Unbound and bound toolbars keep today’s capabilities (including error remap and
  `composeEnabled`).
- Ask AI remains a single-card dialog without embedding full Landing chrome.
- A fourth host only needs: choose chrome + provide host callbacks.

## Non-goals

- Changing `TerminalDropIngestor` or terminal drop quoting.
- Merging Landing page header or Chat transcript UI.
- Changing Chat ↔ Terminal submit preference behavior.
- Redesigning toolbar product behavior or visuals beyond unification.
- Preference / enum renames from the unified-chat-surface doc (already done or
  tracked elsewhere).

## Testing

| Area | Action |
|------|--------|
| Ingestor | Rename tests; keep resolve / skip-directory coverage |
| `WorkspaceComposeCard` | Unbound vs bound chrome visibility; drop region always mounted |
| Session | Drop wiring smoke (ingestor inserts refs into controller) |
| Ask AI | Assert `WorkspaceComposeCard`; stop depending on Landing compose type / `showLandingChrome: false` |
| Call-site updates | `session_history_continue_chrome`, `expert_landing_chip`, `session_chat_submit_gate`, landing chrome, selection ask AI tests |
| Gate | `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` and the compose / selection_ai / session / landing tests above |

## File map (expected)

| File | Role |
|------|------|
| `client/lib/widgets/compose/workspace_compose_card.dart` | Unified card |
| `client/lib/widgets/compose/compose_chrome.dart` | Sealed chrome types |
| `client/lib/widgets/compose/compose_file_drop_region.dart` | External + workspace drop wrap |
| `client/lib/services/compose/compose_file_drop_ingestor.dart` | Renamed ingestor |
| `client/lib/services/compose/unbound_compose_host.dart` (name flexible) | Shared unbound state helpers |
| `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart` | Host unbound card + page chrome |
| `client/lib/pages/chat/session_chat_view.dart` | Host bound card |
| `client/lib/services/selection_ai/selection_ask_ai.dart` | Host unbound card in dialog |
| Delete | `workspace_chat_landing_compose_card.dart`, `session_review_compose_card.dart` |
