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
| `workingSessionIds` / session title fan-out | First message / agent turns used to rebuild whole sidebar + `ChatPageShell` → bulk `RenderParagraph` | Leaf-only selects: structure snapshots for list shells, `SessionRowContent` for row/tab text, Running host for membership; never put `workingSessionIds` or full title-bearing `sessions`/`tabs` in page-shell `buildWhen` |
| **Cold `TextStyle` / font family** | First paint shapes glyphs for a new family+size+weight tuple; **monospace on form fields** can cost seconds and rarely shows as a named hotspot in DevTools | Use `TpTextStyles` / warmed host styles only; never hardcode `'monospace'` or ad-hoc `TextStyle` on hot paths — see [Typography and glyph warmup](#typography-and-glyph-warmup) |
| **`RenderParagraph` ≫ 200ms** | Flame/summary hot path on first open — treat as **cold text layout**, not “widget count”. Often mixed spans in one `Text.rich` (e.g. bold UI + mono `` `code` ``), not missing BUILD | Isolate the span mix; extend finite boot warmup (`shapeRich`) — see below. Do not dump unbounded charsets |

## Typography and glyph warmup

**Cold font shaping** can freeze UI for hundreds of ms–seconds while DevTools only
shows `Layout` / `RenderParagraph` / `Build`. Example: launch-config fields on
**monospace** felt broken; same fields on boot-warmed `TpTextStyles.of(context).md`
opened instantly.

**Signal:** first-open timeline with **`RenderParagraph` self-time ≳ 200ms** →
stop chasing defer layers until typography / rich-text mix is ruled out.

### What boot warms

[`UiInteractiveWarmup`](../client/lib/services/app/ui_interactive_warmup.dart):

1. **Style fingerprints** — every style from `textStylesForThemeWarmup`
   (`TpTextStyles` + inputs +
   [`appMarkdownTextStyles`](../client/lib/theme/app_markdown_style_sheet.dart)),
   each laid out once with short [`TpGlyphWarmup.styleProbe`](../client/packages/shared_ui/lib/src/theme/tp_glyph_warmup.dart)
   (`Ag中.`). Key = `(family, size, weight, style)`. **No l10n charset dump** —
   document text is unbounded.
2. **Mixed markdown spans** —
   [`warmMarkdownMixedInlineLayout`](../client/lib/theme/app_markdown_style_sheet.dart)
   via `TpGlyphWarmup.shapeRich`: finite nests (body/bold/italic/h1/h2 × mono
   code, bold × italic). Warming bold **and** mono separately does **not** cover
   both in one `Text.rich`.

Hot-path paint must hit warmed fingerprints; `copyWith(color: …)` is fine,
changing family/size/weight is not. Markdown `forcedStrut` is **off** (A/B: no
reading difference; it amplified mixed-span first-open cost). Line height stays
on `TextStyle.height`.

| Do | Don't |
|----|-------|
| `TpTextStyles` / markdown tokens from warmed sizes | Ad-hoc `TextStyle(fontSize: …)` / `'monospace'` on hot paths |
| Add new size/weight to warmup + keep [`app_markdown_warmup_coverage_test.dart`](../client/test/theme/app_markdown_warmup_coverage_test.dart) green | Expand probe strings to match specific README sentences |
| `shapeRich` for a new **finite** span mix that shows `RenderParagraph` ≫ 200ms | Assume single-style `shapeAll` covers nested bold+code |

**Diagnose:** A/B mono → `.md` on suspect fields; for markdown preview, bisect to
one line (often `` **…`code`…** ``). Probe:
`flutter test test/widgets/run/text_field_mount_cost_probe_test.dart --name cold_six_text_fields`
(one case per process).

**Exceptions:** diff line-height `TextPainter` (must match `CodeEditorStyle`),
proportional monogram glyphs, editor/terminal (warmed separately). Link
`WidgetSpan` cost is mount/layout of nested paragraphs — fix rendering, not
charset warmup.

## Checklist for a new heavy surface

- [ ] Click paints chrome within one frame (placeholder OK).
- [ ] Heavy body is behind `TpDeferredForegroundMount` or equivalent.
- [ ] Sibling lists / forms / fields use staggered `TpDeferredMountShell` (or idle).
- [ ] Empty / landing path skips the full workbench or editor tree.
- [ ] Inactive stack layers use `TpKeepAliveLayer`, not `Offstage`, when layout cost matters.
- [ ] DevTools export + `analyze_performance_json.dart --format summary` shows the expensive work off Frame 0.
- [ ] High-frequency session presence (`workingSessionIds`, attention waiting) is selected only in leaf widgets that render that presence. List shells select structure snapshots only; row/tab text selects row-content snapshots. Do not add `workingSessionIds` or full `sessions` / title-bearing tab snapshots to page-shell `buildWhen`.
- [ ] Form/dialog text uses warmed `TpTextStyles` (see above); defer only after typography is clean.
- [ ] If first-open summary shows `RenderParagraph` ≳ 200ms, check cold / mixed rich text before more deferral.

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
