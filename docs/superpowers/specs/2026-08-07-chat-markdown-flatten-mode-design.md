# Chat & markdown flatten mode: natural-height block virtualization with per-content display modes

## Problem

Rendering a very long message or markdown file currently relies on **bounded panels with internal scrolling**, which is unlike how editors/previews (VS Code markdown preview) handle long content — they render at **natural height in the parent scroll** and stay smooth:

1. **Expanded huge messages use a bounded panel.** A huge user message expands into `VirtualMarkdownView` capped at ~70% viewport height with its own internal scrollbar (`_ExpandableHistoryMarkdown`, `text_part_view.dart`). Users must scroll *inside* the panel instead of the thread; the panel is a fixed-height box, not a flowing document.

2. **Code blocks use a mask + internal scroll.** `_MarkdownCodeBlock` collapses oversized code to a fade + chevron; expanding opens a fixed-height (~420 px) scroll shell. There is no way to show code at full natural height in the flow.

3. **The markdown file preview is non-virtualized.** `file_editor_surface.dart` preview mode renders the whole file through a plain `MarkdownView` (a full `Column` of every block) — a large `.md` file freezes layout on open.

The root gap: the chat/file preview have **no reusable capability to render arbitrary-length markdown at natural height in the parent scroll** while only laying out visible blocks. The turn-level thread virtualizer (`VirtualThreadViewport`) does this for *messages*, but not *within* a message.

## Decision

Build the missing capability as a reusable widget — **`FlattenMarkdownView`** — a block-level virtualizer that renders at **natural height inside the parent scroll** (no own scrollbar, no max-height), mounting only the blocks visible in the parent viewport and reporting its true total height up so the parent scroll extent is correct.

Make the rendering mode **configurable per surface × content type** with a uniform 3-state enum, **defaulting to today's behavior** (fold + fixed-height scroll):

- `ContentDisplayMode.foldFixedHeight` — collapse to a mask; expand into a fixed-height scroll shell (today).
- `ContentDisplayMode.foldExpandFull` — collapse to a mask; expand to **full natural height in the flow**.
- `ContentDisplayMode.flatten` — always **full natural height in the flow**, no mask/collapse.

Three config keys (stored in layout preferences):

| Config | Surface | Content | Default |
|--------|---------|---------|---------|
| `chat.userMessageMode` | chat preview | user message | `foldFixedHeight` |
| `chat.codeBlockMode` | chat preview | code block | `foldFixedHeight` |
| `file.codeBlockMode` | markdown file preview | code block | `foldFixedHeight` |

The **markdown file preview whole-file** always uses `FlattenMarkdownView` (decision, not a toggle) so large files stop janking. **Assistant prose** stays inline-only (no config).

## Architecture

### 1. `FlattenMarkdownView` (tp_markdown) — the reusable capability

Refactor of the existing `VirtualMarkdownView` (`tp_markdown/lib/src/render/virtual_markdown_view.dart`):

- **Remove its own `SingleChildScrollView` / `ScrollController`.** It becomes a natural-height render box: `Column([paddingTop, visibleBlocks…, paddingBottom])`.
- **Read the parent scroll.** It needs the nearest ancestor viewport and its own offset inside it:
  - parent `ScrollController` passed in (or found via `PrimaryScrollController` / a scope);
  - own offset via `RenderAbstractViewport.of(context)` + `getOffsetToReveal(renderObject, 0)`.
  - visible block range = blocks whose cumulative height span `[parentScroll - myOffset, parentScroll - myOffset + parentViewportHeight]` (+ overscan).
- **Report true total height.** The natural height (sum of all block heights from the cache) is what the parent lays out, so the parent scroll extent includes the full content.
- Reuses the existing height cache / `_BlockMeasuredBox` measurement / scroll-correction logic unchanged.

### 2. Content display modes (tp_markdown)

```dart
enum ContentDisplayMode { foldFixedHeight, foldExpandFull, flatten }
```

A small `MarkdownDisplayModeScope` (InheritedWidget) in tp_markdown carries both modes — `userMessageMode` and `codeBlockMode` (both `ContentDisplayMode`, default `foldFixedHeight`). `_MarkdownCodeBlock` reads `codeBlockMode`; ai_message_ui's `_ExpandableHistoryMarkdown` reads `userMessageMode`.

`_MarkdownCodeBlock` behavior per mode:
- `foldFixedHeight`: today — fade mask; expand into ~420 px scroll shell.
- `foldExpandFull`: fade mask; expand renders the **full code at natural height** (no scroll shell, one layout when visible).
- `flatten`: always render the full code at natural height (no mask).

### 3. Chat integration (ai_message_ui)

`_ExpandableHistoryMarkdown` (user message path) reads the user-message mode:
- `foldFixedHeight`: today — mask; expand → bounded `VirtualMarkdownView`.
- `foldExpandFull`: mask; expand → `FlattenMarkdownView` (natural height in thread flow).
- `flatten`: no mask — always `FlattenMarkdownView`.

The thread (`VirtualThreadViewport`) is unchanged: it still windows turns; a flattened message is one turn whose measured height is its natural full height (reported by `FlattenMarkdownView` up through the turn measurer).

### 4. File preview integration (app)

`file_editor_surface.dart` preview mode renders the file with `FlattenMarkdownView` (whole file, virtualized) instead of `MarkdownView`. File code blocks follow `file.codeBlockMode`.

### 5. Config plumbing

- Add the three `ContentDisplayMode` prefs to layout preferences (`LayoutCubit`).
- Chat: provide `MarkdownDisplayModeScope(userMessageMode: chat.userMessageMode, codeBlockMode: chat.codeBlockMode)` around the chat markdown rendering.
- File editor: provide `MarkdownDisplayModeScope(userMessageMode: .foldFixedHeight, codeBlockMode: file.codeBlockMode)` around the preview (file preview has no user-message concept).
- Defaults = `foldFixedHeight` → **today's rendering, no regression**.

### 6. Config UI

App settings (`/config/*`, layout/rendering section): three segmented/dropdown controls grouped by surface:

- Chat — 用户消息: 折叠·固定高度 / 折叠·全部展开 / 铺平
- Chat — 代码块: 折叠·固定高度 / 折叠·全部展开 / 铺平
- 文件预览 — 代码块: 折叠·固定高度 / 折叠·全部展开 / 铺平

## Behavior matrix

| Mode | User message (chat) | Code block (chat & file) |
|------|--------------------|--------------------------|
| `foldFixedHeight` | mask → bounded panel | mask → 420 px scroll shell |
| `foldExpandFull` | mask → natural height in flow | mask → natural height in flow |
| `flatten` | always natural height (no mask) | always natural height (no mask) |

- A "flattened" huge message/code block still virtualizes: only visible blocks/code are laid out; the parent scroll drives it.
- A truly huge single code block at full height is one layout when it scrolls into view (cost bounded by its size) — accepted.

## Testing

1. **Default regression:** with all modes at `foldFixedHeight`, existing behavior and tests stay green (chat + tp_markdown + ai_message_ui suites).
2. **`FlattenMarkdownView`:** natural-height render inside a parent scroll (no own scrollbar); only visible blocks mounted; scrolling reaches the tail; total height reported correctly (parent scroll extent).
3. **Per-mode:** user message `foldExpandFull`/`flatten` expands to natural height (no bounded panel); code block three modes each render correctly; file preview whole-file uses `FlattenMarkdownView`.
4. **End-to-end:** real 785 KB user message — `flatten` renders natural height in thread and scrolls smoothly; large `.md` file preview no longer janks.
5. `flutter analyze --no-fatal-infos --no-fatal-warnings` clean; full `flutter test --exclude-tags integration`.

## Files

| File | Change |
|------|--------|
| `packages/tp_markdown/lib/src/render/virtual_markdown_view.dart` | refactor into `FlattenMarkdownView` (parent-scroll driven, natural height) |
| `packages/tp_markdown/lib/src/render/table_code_hr_blocks.dart` | `_MarkdownCodeBlock` reads `ContentDisplayMode` (3 modes) |
| `packages/tp_markdown/lib/src/markdown_display_mode_scope.dart` | new `ContentDisplayMode` enum + `MarkdownDisplayModeScope` |
| `packages/tp_markdown/lib/tp_markdown.dart` | export new scope/enum + `FlattenMarkdownView` |
| `packages/ai_message_ui/lib/src/parts/text_part_view.dart` | user-message path honors mode (bounded panel / flatten) |
| `client/lib/pages/workbench/file_editor_surface.dart` | preview uses `FlattenMarkdownView` |
| `client/lib/cubits/layout_cubit.dart` (+ prefs model) | three `ContentDisplayMode` prefs |
| app settings UI (`/config/*`) | three controls (chat user msg / chat code / file code) |
| tests | per-mode + `FlattenMarkdownView` + file preview tests |
