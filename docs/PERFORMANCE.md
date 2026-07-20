# Performance optimization

How TeamPilot keeps heavy UI opens feeling instant. For measuring jank with
DevTools exports, see [PERFORMANCE_ANALYSIS.md](PERFORMANCE_ANALYSIS.md).

## Goals

1. **Perceived latency first** — after a click, the next frame must show
   recognizable chrome (tab, card, dialog frame). Absolute millisecond budgets
   matter less than “something opened.”
2. **No opaque freezes** — never mount IDE + full lists + `TextField` in one
   synchronous frame.
3. **Measure before/after** — debug inflates costs (especially `RenderEditable`);
   use the same mode (debug vs profile) when comparing, and prefer profile for
   absolute claims.

Flutter mounts widget subtrees on a single UI isolate. Browsers feel free because
shell chrome and document content are separate pipelines and empty documents are
cheap. Progressive paint is how we recreate that split.

## Progressive paint timeline

Reuse this for heavy route opens (workspace tabs, large dialogs, IDE panes):

| Stage | Paint | Mount |
|-------|--------|--------|
| 0 | Route chrome (tab, card shell, dialog frame) | No heavy body |
| 1 | Structural skeleton (pane gutters, list chrome) | Lightweight shell only |
| 2+ | Real content (lists, selectors) | Stagger with `TpDeferredMountShell` |
| Idle | Most expensive controls (`TextField`, terminal, huge lists) | `awaitIdle: true` when needed |

### Primitives (`shared_ui`)

| Widget | Use when |
|--------|----------|
| `TpDeferredForegroundMount` | Tab/route becomes active — Frame 0 = placeholder chrome; body next frame. Prefer `retainWhenInactive: true` with `TpKeepAliveLayer`. |
| `TpDeferredMountShell` | Stagger siblings inside an already-mounted shell (`delayFrames`, optional `awaitIdle`). |
| `TpDeferredMountAfter` | Wait for a timed animation before mounting a heavy child. |
| `TpKeepAliveLayer` | Multi-tab stacks: keep state, skip layout/paint when inactive (unlike `Offstage`). |

Product chrome placeholders (e.g. `WorkspaceTabDeferredMount` +
`WorkspacePageCardShell`) stay in the app; deferred tools stay in `shared_ui`.

### Rules

1. **Nav-first** — update route / open tab before awaiting hydrate.
2. **Placeholder must look like chrome** — not a blank box inside an already-built page.
3. **Fast-path empty states** — landing / empty compose must not pay full workbench shell cost.
4. **Stagger siblings** — do not reveal list + landing + field on the same frame (e.g. list `delayFrames: 1`, landing `2`, field idle).
5. **Do not stack infinite deferrals** — one foreground defer + content stagger is enough; more layers rarely help once Editable is the wall.

### Reference implementation

Expected open sequence after that work:

1. Title tab + empty card chrome  
2. IdeShell + sidebar/landing skeletons  
3. Real session list, then landing body (staggered)  
4. Idle compose `TextField` (`RenderEditable` last)

## Known hotspots

| Cost | Notes | Typical response |
|------|--------|------------------|
| `RenderEditable` / multiline `TextField` | First layout is expensive in debug; profile is cheaper | Defer with `awaitIdle`; do not autofocus on open; avoid mounting token fields until needed |
| `WorkspaceIdeShell` / `MultiPane` | First mount of split panes + tools providers | Foreground defer + skeletons; compose fast-path without `ChatPageShell` |
| Title-bar `AnimatedOpacity` / tab chrome | High rebuild counts on open | Prefer not animating whole tab strips on every open; keep rebuilds local |
| `Offstage` keep-alive tabs | Still layouts inactive children | Use `TpKeepAliveLayer` instead |

## Checklist for a new heavy surface

- [ ] Click paints chrome within one frame (placeholder OK).
- [ ] Heavy body is behind `TpDeferredForegroundMount` or equivalent.
- [ ] Sibling lists / forms / fields use staggered `TpDeferredMountShell` (or idle).
- [ ] Empty / landing path skips the full workbench or editor tree.
- [ ] Inactive stack layers use `TpKeepAliveLayer`, not `Offstage`, when layout cost matters.
- [ ] DevTools export + `analyze_performance_json.dart --format summary` shows the expensive work off Frame 0.

## Measuring

```bash
cd client
dart run tool/analyze_performance_json.dart ~/Downloads/snapshot.json --format summary
```

Capture and CLI details: [PERFORMANCE_ANALYSIS.md](PERFORMANCE_ANALYSIS.md).  
Jank debugging process: [DEBUGGING.md](DEBUGGING.md).

## Related docs

| Doc | Topic |
|-----|--------|
| [PERFORMANCE_ANALYSIS.md](PERFORMANCE_ANALYSIS.md) | Offline DevTools JSON analysis |
| [CODE_QUALITY.md](CODE_QUALITY.md) | Layering, file size, tests |
| [DEBUGGING.md](DEBUGGING.md) | Systematic debugging |
| [AGENTS.md](../AGENTS.md) | Architecture map |
