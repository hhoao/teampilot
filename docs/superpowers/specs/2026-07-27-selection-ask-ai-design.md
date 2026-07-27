# Selection → Ask AI (editor + terminal): design

## Problem

Users often want to turn a **text selection** in the file editor or an
Alacritty terminal into the start of a new TeamPilot conversation.

Today:

- The file editor context menu can **Copy as AI context**
  (`formatEditorAiContext` → clipboard).
- There is **no** selection floating chat control, and **no** path that opens
  landing Compose with that context prefilled and launches a session on send.
- Workspace shell and chat-workbench (member) terminals have copy/paste menus
  only — no AI-context copy and no Ask AI entry.

## Goal

On **file editor** and **all Alacritty terminal surfaces** (workspace shell +
session member / chat workbench):

1. Right-click: **Copy as AI context** (clipboard; same formatter as Ask AI).
2. Right-click + selection FAB: **Ask AI…** opens a modal with the **full**
   workspace landing Compose (`WorkspaceChatLanding`), launch params editable.
3. Prefill the compose field with the formatted AI context as an **editable
   message prefix** (`{context}\n\n`, caret after).
4. On submit: reuse `submitWorkspaceLandingMessage` — create conversation,
   connect, deliver the full compose text as the first user message; switch
   workbench to the new session tab. Do **not** steal the main pane via
   `enterNewChat` just to show compose.

## Non-goals

- Context chips / multi-snippet accumulation UI
- Auto-clearing selection on Ask AI
- Changing the primary Chat landing layout (only add `initialText` / dialog host)
- Non-Alacritty selection surfaces (e.g. History `SelectionArea`) in v1
- Rewriting terminal selection hit-testing inside `flutter_alacritty`

## Decisions (from brainstorming)

| Topic | Choice |
|-------|--------|
| Scope | File editor **and** all terminal surfaces |
| Launch params | Selectable in the dialog (full landing Compose) |
| Dialog form | Embed existing `WorkspaceChatLanding` |
| Context presentation | Editable message body prefix (not a separate chip) |
| Architecture preference | Shared coordinator + formatters; modal dialog (not navigate-away) |

## Architecture

```
Selection (editor | terminal)
        │
        ├── format*AiContext  →  clipboard  ("Copy as AI context")
        │
        └── SelectionAskAi.openComposeDialog(aiContext)
                    │
                    ▼
            TpDialog + WorkspaceChatLanding(initialText: context + "\n\n")
                    │
                    ▼
            submitWorkspaceLandingMessage(message, launch)
                    │
                    ▼
            new session tab + connect + first message
```

| Layer | Responsibility |
|-------|----------------|
| `SelectionAiContextFormatter` | Pure formatters: file / terminal → clipboard & prefill string |
| `SelectionAskAi` | Open compose dialog; wire submit → `submitWorkspaceLandingMessage` |
| `SelectionAskAiFabHost` | Listen to selection; position FAB; hide on menu / clear / dialog open |
| Surface menus | Editor toolbar + terminal context menus add AI actions |

### Module placement

| Location | Contents |
|----------|----------|
| `client/lib/services/selection_ai/` | Formatters, `SelectionAskAi`, FAB host, shared menu specs helper |
| `client/lib/services/editor/file_editor_ai_context.dart` | Keep; implement via / delegate to shared file formatter (no duplicate templates) |
| `client/lib/services/editor/file_editor_toolbar.dart` | Add Ask AI; call shared format + `SelectionAskAi` |
| `client/lib/widgets/workspace_terminal_panel.dart` | Shell menu AI items + FAB host |
| `client/lib/pages/chat/chat_workbench_context_menu.dart` | Member terminal AI items |
| `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart` | `initialText` support |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | `selectionAskAi` (+ tooltip if needed); reuse `editorCopyAsAiContext` |

## §1 Selection floating button

**Show when**

- Editor: non-collapsed selection with non-empty selected text.
- Terminal: `selectionActive` and non-empty `readSelectionText()`.
- After pointer-up / selection settles (no FAB flicker while dragging).

**Placement**

- Compact chat / sparkles control near selection end; clamp into the surface
  viewport.
- Editor: selection toolbar anchors.
- Terminal: end-cell screen coords when available; else inner bottom-end of the
  terminal panel.

**Hide when**

- Selection cleared or collapsed.
- Context menu open (restore after dismiss if selection remains).
- Ask AI dialog opened (context already copied into the field).
- Surface tab switch / host unmount.

**Click**

- Format current selection → `SelectionAskAi.openComposeDialog`.
- Do not clear selection; after dialog close, FAB may reappear if still selected.

## §2 AI context text format

Shared formatters; clipboard and dialog prefill must be byte-identical for the
same selection.

**File (existing template)**

```
rel/path.dart:10-12
```dart
selected code
```
```

- Collapsed selection + Copy as AI context: current line (existing behavior).
- Relative path: `editorRelativePath`.

**Terminal**

```
terminal:<surface-label> L<a>-<b>
```text
selected plain text (ANSI stripped by engine selectionText)
```
```

- Shell label: `workspace-shell`.
- Member label: `session/<sessionId>/<memberNameOrTaskId>`.
- Omit `L<a>-<b>` when line range is unavailable.
- Copy as AI context / Ask AI enabled only when selection text is non-empty
  (no “current line” fallback for terminals).

**Compose prefill**

- `{aiContext}\n\n`; caret after the blank line.
- Submit sends the full field text as-is (no second rewrite).

**Extension**

- `AiContextSource` (file / terminal / future) → `formatAiContext(source)`.

## §3 Compose dialog and submit

**API**

```dart
SelectionAskAi.openComposeDialog(
  context, {
  required String aiContext,
  required Workspace workspace,
  required String tabScopeId,
});
```

**Dialog**

- Large `TpDialog` hosting `WorkspaceChatLanding` with `initialText`.
- Shares landing draft persistence (identity, cwd, permissions, etc.).
- Escape / barrier dismiss: no session create; clipboard unchanged.
- Does **not** call `enterNewChat` (stay on editor/terminal visually).

**Submit**

1. Same validation / launch gates as Chat landing.
2. `submitWorkspaceLandingMessage(..., message: fieldText, launch: …)`.
3. Success: close dialog → new session tab + connect + first message.
4. Failure: keep dialog open; existing toast / status handling.

## §4 Context menus and surface wiring

| Surface | Copy as AI context | Ask AI… | FAB host |
|---------|--------------------|---------|----------|
| File editor | existing, shared formatter | new | yes |
| Workspace shell terminal | new | new | yes |
| Chat workbench member terminal | new | new | yes |

- Terminal menus: enable AI actions when `hasSelection` (same pattern as Copy).
- Shared helper builds the two AI `TpActionMenuSpec`s for both terminal menus.
- l10n: reuse `editorCopyAsAiContext`; add `selectionAskAi` (zh:「用 AI 提问…」).

## §5 Testing and acceptance

**Unit**

- File formatter: existing template tests; dialog prefill uses same function.
- Terminal formatter: with/without line range; shell vs member labels; empty → empty.
- Prefill join: `context + '\n\n'`.

**Widget / integration (mocked submit)**

- FAB host: show / hide / click payload.
- Dialog `initialText` lands in controller; submit forwards message + launch.
- Editor and terminal menus expose both AI actions; disabled without selection
  on terminals.

**Manual**

1. File drag-select → FAB → dialog prefill → change launch params → send → new
   session starts with context in first message.
2. File Copy as AI context clipboard matches Ask AI prefill body (sans trailing
   `\n\n`).
3. Workspace shell and member terminals same flow.
4. Dismiss dialog: selection and focus preserved; FAB can return.
5. Tab switch: no orphan FAB.

## Error handling

- Empty context: do not open dialog; FAB not shown; menu actions disabled.
- Submit / expert / mixed-create failures: unchanged landing feedback; dialog stays.
- Missing workspace / tab scope in host context: no-op + diagnostic log
  (`AppLogger`), no crash.

## Risks

| Risk | Mitigation |
|------|------------|
| Large Landing inside Dialog height | Constrained scrollable dialog body; match settings-dialog sizing patterns |
| Terminal selection coords unreliable | Fallback anchor to panel corner |
| Duplicate format strings | Single shared formatter module |
| `WorkspaceChatLanding` stateful init vs `initialText` | Apply in `initState` once; document no mid-flight overwrite |

## Implementation order (for planning)

1. Shared formatters + tests (terminal + prefill join; wire file through shared).
2. `WorkspaceChatLanding.initialText` + dialog host `SelectionAskAi`.
3. Editor menu Ask AI + FAB host.
4. Shell terminal menu + FAB.
5. Member terminal menu + FAB.
6. l10n + manual pass.
)