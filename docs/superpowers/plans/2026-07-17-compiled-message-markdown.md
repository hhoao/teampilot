# Compiled message markdown — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `AiTextPartView`’s hot-path `MarkdownBody` with a GFM compile → IR → cheap `Text.rich`/lite table/code renderer so history fling frames drop markdown/table layout cost vs `test41.json`.

**Architecture:** `package:markdown` (GFM) → `MessageContentDocument` (cached) → `CompiledTextPartView`; `MarkdownBody` only for `unsupported` slices. No scroll-deferred upgrades in v1. Reasoning/tool chrome cheapening in the same program.

**Tech Stack:** Flutter, `markdown` ^7.3, existing `flutter_markdown_plus` as fallback only, `ai_message_ui` package tests + `analyze_performance_json.dart`.

**Spec:** `docs/superpowers/specs/2026-07-17-compiled-message-markdown-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/ai_message_ui/lib/src/markdown/content_ir.dart` | IR types: document, blocks, inline runs |
| `client/packages/ai_message_ui/lib/src/markdown/content_compiler.dart` | GFM AST → IR + LRU cache |
| `client/packages/ai_message_ui/lib/src/markdown/compiled_markdown_style.dart` | Theme → text/code/table styles |
| `client/packages/ai_message_ui/lib/src/markdown/compiled_text_part_view.dart` | IR → widgets |
| `client/packages/ai_message_ui/lib/src/parts/text_part_view.dart` | Switch entry to compiled path; keep `prepareStreamingMarkdown` |
| `client/packages/ai_message_ui/test/fixtures/markdown_corpus/*` | ≥20 fixtures + gate test |
| `client/packages/ai_message_ui/test/content_compiler_test.dart` | Compiler unit tests |
| `client/packages/ai_message_ui/test/compiled_text_part_view_test.dart` | Widget tests |
| `client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart` | Cheaper collapsed header |
| `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` | Remove `Flexible` from min-row |

---

### Task 1: Content IR types

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/markdown/content_ir.dart`
- Test: `client/packages/ai_message_ui/test/content_ir_test.dart` (optional equality smoke)

- [ ] **Step 1: Write failing test** — construct a `MessageContentDocument` with paragraph + table block; assert block kinds / inline run kinds round-trip equality.

- [ ] **Step 2: Run test — expect fail** (types missing)

```bash
cd client && flutter test packages/ai_message_ui/test/content_ir_test.dart
```

- [ ] **Step 3: Implement IR** — sealed/`enum` block kinds: paragraph, heading(level), list(ordered, items with nested children + optional task checked flag), blockquote, hr, code(language, text), table(headers, rows of cell inline docs), unsupported(rawMarkdown). Inline: text, strong, emphasis, strike, code, link(url, title?).

- [ ] **Step 4: Run test — pass**

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/markdown/content_ir.dart client/packages/ai_message_ui/test/content_ir_test.dart
git commit -m "$(cat <<'EOF'
feat(ai_message_ui): add message content IR for compiled markdown

EOF
)"
```

---

### Task 2: Compiler — core GFM blocks

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/markdown/content_compiler.dart`
- Test: `client/packages/ai_message_ui/test/content_compiler_test.dart`

- [ ] **Step 1: Failing tests** for: heading, paragraph with bold/link, fenced **and indented** code, GFM table with `**bold**` cell, nested list, task list item (checked + unchecked), blockquote, hr. Assert no `unsupported` in these cases.

- [ ] **Step 2: Run — fail**

```bash
cd client && flutter test packages/ai_message_ui/test/content_compiler_test.dart
```

- [ ] **Step 3: Implement** `compileMessageContent(String markdown)` using `md.Document(extensionSet: md.ExtensionSet.gitHubFlavored)`. Map AST → IR. Images/HTML → `unsupported` slice. Export `prepareStreamingMarkdown` reuse from `text_part_view.dart` (or move prepare helper to shared file to avoid cycles).

- [ ] **Step 4: Run — pass**

- [ ] **Step 5: Commit** `feat(ai_message_ui): compile GFM markdown to content IR`

---

### Task 3: Compiler LRU cache + corpus gate

**Files:**
- Modify: `content_compiler.dart` (cache)
- Create: `client/packages/ai_message_ui/test/fixtures/markdown_corpus/` (≥20 `.md` files)
- Create: `client/packages/ai_message_ui/test/markdown_corpus_gate_test.dart`

- [ ] **Step 1: Failing gate test** — load all corpus files; require `unsupported` blocks count == 0 for ≥95% of files; identical input returns identical cached document instance (or equal + cache hit counter).

- [ ] **Step 2: Run — fail** (corpus missing / no cache)

- [ ] **Step 3: Add corpus fixtures** (synthetic GFM covering must-compile set + 2–3 “real-ish” multi-section samples). Implement LRU (max 64) keyed by prepared markdown string.

- [ ] **Step 4: Run — pass**

- [ ] **Step 5: Commit** `test(ai_message_ui): add markdown corpus gate and compiler cache`

---

### Task 4: CompiledMarkdownStyle + CompiledTextPartView

**Files:**
- Create: `compiled_markdown_style.dart`, `compiled_text_part_view.dart`
- Test: `compiled_text_part_view_test.dart`
- Modify: export if needed from package (internal OK)

- [ ] **Step 1: Failing widget tests** — pump `CompiledTextPartView` with docs for: heading text, ordered/task list text, link tap calls callback, table shows bold cell text, code block shows fence body, SelectionArea can select paragraph text, no `MarkdownBody` in tree for must-compile docs. All text widgets use non-selectable leaves (parent SelectionArea model).

- [ ] **Step 2: Run — fail**

```bash
cd client && flutter test packages/ai_message_ui/test/compiled_text_part_view_test.dart
```

- [ ] **Step 3: Implement renderer** — `CompiledMarkdownStyle.from(ThemeData, AiMessageTheme)` mapping; merge adjacent textual blocks into `Text.rich` where practical; table without `IntrinsicColumnWidth`; code chrome similar to current `_AuiCodeBlockBuilder` look; `unsupported` → existing `MarkdownBody` for that slice only (`selectable: false`). Compiled path also `selectable: false` / plain `Text.rich` under parent SelectionArea.

- [ ] **Step 4: Run — pass** (also keep `markdown_sheet_test` green or update expectations)

- [ ] **Step 5: Commit** `feat(ai_message_ui): render compiled markdown with Text.rich and lite tables`

---

### Task 5: Switch AiTextPartView

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/parts/text_part_view.dart`
- Modify tests: `markdown_cache_test.dart` (retire or retarget to compiler cache), `markdown_sheet_test.dart`

- [ ] **Step 1: Failing/adjust tests** — `AiTextPartView` no longer requires `MarkdownBody` for plain GFM; GFM table + `onTapLink` still work.

- [ ] **Step 2: Run existing markdown tests — observe failures**

```bash
cd client && flutter test packages/ai_message_ui/test/markdown_sheet_test.dart packages/ai_message_ui/test/markdown_cache_test.dart
```

- [ ] **Step 3: Implement switch** — `AiTextPartView.build` → prepare → compile (cached) → `CompiledTextPartView`. Remove or shrink `MarkdownBodyCache` if unused.

- [ ] **Step 4: Full package test**

```bash
cd client && flutter test packages/ai_message_ui/test
```

- [ ] **Step 5: Commit** `feat(ai_message_ui): use compiled markdown path in AiTextPartView`

---

### Task 6: Reasoning / tool chrome

**Files:**
- Modify: `reasoning_part_view.dart`, `tool_call_part_view.dart`
- Test: `collapsed_parts_test.dart` (+ small new asserts)

- [ ] **Step 1: Failing tests** — collapsed reasoning has no `InkWell` and no `AnimatedScale`; collapsed tool row has no `Flexible`.

- [ ] **Step 2: Run — fail**

- [ ] **Step 3: Implement** cheaper header hit target; replace `Flexible` with non-flex layout in min `Row`.

- [ ] **Step 4: Run collapsed + parts tests — pass**

- [ ] **Step 5: Commit** `perf(ai_message_ui): cheapen collapsed reasoning and tool chrome`

---

### Task 7: Verification + perf note

**Files:**
- Optional: `docs/superpowers/specs/2026-07-17-compiled-message-markdown-design.md` (link results)
- Create short note under plan or spec appendix with analyzer numbers

- [ ] **Step 1: Analyze**

```bash
cd client && flutter analyze packages/ai_message_ui --no-fatal-warnings
flutter test packages/ai_message_ui/test
```

- [ ] **Step 2: Manual** — run app, open long history, fling + hover; export DevTools JSON as `test42.json`.

- [ ] **Step 3: Compare**

```bash
cd client && dart run tool/analyze_performance_json.dart ~/Downloads/test42.json --format summary
```

Confirm MarkdownBody absent from top 5; ActionBar still absent; table/markdown self-time ≤50% of test41 where measurable.

- [ ] **Step 4: Commit** docs note if numbers recorded: `docs: note compiled markdown perf vs test41`

---

## Execution handoff

After plan approval, choose:

1. **Subagent-Driven** — fresh subagent per task + review between tasks  
2. **Inline Execution** — this session with executing-plans checkpoints  
