# Compose `@` file chip row (above input)

**Date:** 2026-07-30  
**Status:** Approved (spec review)  
**Product:** TeamPilot (`client/`)  
**Scope:** Chat / landing compose card (`WorkspaceComposeCard`)

## Problem

Compose treats file references as pure-text `@path` tokens. `TpTokenTextField` paints them as teal inline pills inside the textarea. Paths outside the workspace root (especially paste-imported images under `Documents/TeamPilot/Attachments/…`) become long absolute `@` strings that dominate the input.

Users want those files listed **above** the input as clickable chips (thumbnail / icon + basename), matching common chat composers, while keeping the existing edit/submit model.

## Goals

1. Mirror **all** `@` file references from the compose text into a chip row **above** the input (picker / paste / drop / manual `@` mention).
2. Chip tap opens the file in the workbench editor / image preview via `WorkbenchEditorOpener.openFile`.
3. Keep `@path` in `TextEditingController.text` (editable; Backspace / token delete unchanged).
4. No remove (`×`) control on chips — deletion stays keyboard/text only.
5. Reuse Landing + Session continue compose through `WorkspaceComposeCard`.

## Non-goals

- Structured `List<Attachment>` state or changing the submit wire format (still a prompt string with `@` refs).
- Hiding or shortening inline teal `@` pills in the textarea (possible follow-up).
- Chip `×` / deleting files under `Attachments/` on remove.
- Opening with the OS default app.
- Putting `/skill` tokens in the chip row.
- Changing terminal / fullscreen PTY attach UX.

## Decisions

| Topic | Choice | Why |
|-------|--------|-----|
| Approach | Mirror chips from text (Approach 1) | Matches “keep `@` in text + no ×”; minimal risk to compose pipeline |
| Which refs | All `@` file tokens | Owner choice B |
| Click | Workbench editor / image preview | Owner choice A; `WorkbenchEditorOpener` already handles `isImagePreviewPath` |
| Remove UI | None | Owner choice B |
| Text vs chips | Text keeps full `@path`; chips are a clickable mirror | Owner choice A |
| `/skill` | Stay inline-only | Not file attachments |
| Package | App-layer under `client/lib/widgets/compose/` + `services/compose/` | Product chrome; no shared_ui token-engine change |

## Architecture

```
TextEditingController.text
  → parseComposeAtFileRefs(text, workspaceRoot:)
  → ComposeAtFileChipRow (above ComposeTriggerField)
  → onTap(absolutePath)
  → WorkbenchEditorOpener.openFile(workspaceId, path, preview: true)
```

### Units

| Unit | Role |
|------|------|
| `compose_at_file_refs.dart` | Pure parse: reuse the same boundary-aware token pattern as the textarea (`(?<!\S)(?:@\S+|/\S+)` / `defaultInlineTokenPattern`), keep only `@…` matches; resolve relative → absolute against `workspaceRoot`; dedupe with the same path-key semantics as `compose_file_attach` (Windows case-insensitive); basename for display |
| `ComposeAtFileChipRow` | Horizontal scroll of chips; image → small `Image.file` thumbnail when `isImagePreviewPath`; else file icon; tap → `onOpen` |
| `WorkspaceComposeCard` | Insert chip row above the field when refs non-empty; wire `workspaceId` + open callback (or `context.read<WorkbenchEditorOpener>()`). When opening, pass the workspace `Filesystem` into `openFile(..., fs:)` where hosts already have it (native / WSL / SSH), same as file-tree open paths |

### Data flow (unchanged)

Attach / paste / drop / `@` search still call `insertComposeReferences` / `formatComposeFileReference`. Submit still sends `controller.text`. Chip row is view-only over that text.

### Hosts

- `SessionChatView` — bound compose; has `session.workspaceId`.
- `UnboundComposeBody` — landing; has `workspace.workspaceId` and launch `workspaceRoot`.
- Other `WorkspaceComposeCard` callers: if `workspaceId` / opener available, same behavior; otherwise chips may render with tap no-op (or omit open wiring) without breaking compose.

## UI behavior

- Chip row sits inside the compose focus shell, **above** `ComposeTriggerField`, only when there is at least one `@` file ref.
- Display: basename only (not full path). Images: thumbnail + name; other files: icon + name.
- No `×` on chips.
- Inline teal pills remain in the textarea.
- List updates whenever controller text changes; order follows first occurrence; duplicates collapsed.

## Error handling

| Case | Behavior |
|------|----------|
| Missing file / open failure | Follow existing opener behavior (no new error chrome) |
| Thumbnail load failure | Fall back to generic file icon |
| Relative `@src/foo.dart` | Join with current `workspaceRoot` before open |
| Absolute `@/…/Attachments/….png` | Open as-is |
| Empty / only `/skill` | No chip row |

## Testing

1. **Unit** `compose_at_file_refs_test.dart` — relative vs absolute resolution, `/skill` ignored, dedupe, display name.
2. **Widget** `compose_at_file_chip_row_test.dart` — visibility with/without refs; tap invokes `onOpen`; image vs non-image branch.
3. **Optional** extend `workspace_compose_card_test.dart` — controller with `@file` shows the chip row.

## Out of scope follow-ups

- Approach 2: shorten inline pill labels to basename while keeping full path in text.
- Approach 3: structured attachments that leave the textarea empty of `@` paths until submit.
