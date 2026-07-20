# Progressive paint timeline

## Problem

Flutter mounts widget subtrees synchronously on the UI isolate. A “navigate /
open tab” that builds chrome + IDE + lists + `TextField` in one frame feels like
a freeze. Browsers feel instant because shell chrome and document content are
separate pipelines and empty documents are cheap.

## Goals

Reuse one paint timeline for heavy route opens (workspace, large dialogs, IDE
panes):

| Stage | Paint | Mount |
|-------|--------|--------|
| 0 | Route chrome (tab, card shell, dialog frame) | No heavy body |
| 1 | Structural skeleton (pane gutters, list chrome) | Lightweight shell only |
| 2+ | Real content (lists, selectors) | Staggered with `TpDeferredMountShell` |
| Idle | Most expensive controls (`TextField`, terminal, huge lists) | `awaitIdle: true` when needed |

## Primitives (`shared_ui`)

| Widget | Use when |
|--------|----------|
| `TpDeferredForegroundMount` | Tab / route becomes active — Frame 0 shows placeholder chrome, body mounts next frame. Prefer `retainWhenInactive: true` with `TpKeepAliveLayer`. |
| `TpDeferredMountShell` | Stagger siblings inside an already-mounted shell (`delayFrames`, optional `awaitIdle`). |
| `TpDeferredMountAfter` | Wait for a timed animation before mounting a heavy child. |
| `TpKeepAliveLayer` | Multi-tab stacks: keep state, skip layout/paint when inactive (unlike `Offstage`). |

Product chrome placeholders (e.g. `WorkspaceTabDeferredMount` +
`WorkspacePageCardShell`) stay in the app; deferred tools stay in `shared_ui`.

## Rules

1. **Nav-first** — update route / open tab before awaiting hydrate.
2. **Placeholder must look like chrome** — not a blank colored box inside an
   already-built page.
3. **Fast-path empty states** — landing / empty compose must not pay full
   workbench shell cost.
4. **Stagger siblings** — do not reveal list + landing + field on the same
   frame; bump `delayFrames` (e.g. list `1`, landing `2`, field idle).
5. **Do not stack infinite deferrals** — one foreground defer + content
   stagger is enough; more layers rarely help once Editable is the wall.

## Reference

Workspace open: [2026-07-20-browser-like-workspace-open-design.md](./2026-07-20-browser-like-workspace-open-design.md).
