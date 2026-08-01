# Semantic Markdown Renderer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace dual-path markdown layout (IR + `flutter_markdown_plus` heuristics) with one kind-based pipeline: `MarkdownPipeline` → `MarkdownDocument` → `MarkdownView`, shared by chat (`compact`) and file preview (`document`).

**Architecture:** Evolve `ai_message_ui` in place. Spacing is only `gapBetween(prevKind, nextKind, tokens)`. No `TextStyle` fingerprinting, no product `MarkdownBody` for GFM bodies, no `toMarkdownStyleSheet`. Host builds `MarkdownTokens` per profile from `TpTextStyles`.

**Tech Stack:** Flutter / Dart, `package:markdown` (GFM), `ai_message_ui`, host theme (`TpTextStyles` / `TpFontTheme`), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-01-markdown-semantic-renderer-design.md`

**Supersedes plan:** `docs/superpowers/plans/2026-08-01-orca-like-markdown-style.md` (do not execute that plan; fold visual numbers into `MarkdownTokens` here).

---

## File map

| Path | Responsibility |
|------|----------------|
| `client/packages/ai_message_ui/lib/src/markdown/ir/markdown_block_kind.dart` | `MarkdownBlockKind` enum + `kind` helpers |
| `client/packages/ai_message_ui/lib/src/markdown/ir/markdown_document.dart` | Sealed blocks / inlines (replaces `content_ir.dart`) |
| `client/packages/ai_message_ui/lib/src/markdown/tokens/markdown_profile.dart` | `MarkdownProfile.document` / `.compact` |
| `client/packages/ai_message_ui/lib/src/markdown/tokens/markdown_tokens.dart` | Typography + chrome + rhythm; `gapBetween` |
| `client/packages/ai_message_ui/lib/src/markdown/compile/markdown_pipeline.dart` | prepare → parse → IR (replaces `content_compiler.dart`) |
| `client/packages/ai_message_ui/lib/src/markdown/compile/streaming_markdown.dart` | Move/keep fence prep |
| `client/packages/ai_message_ui/lib/src/markdown/registry/markdown_resolvers.dart` | link/image callbacks |
| `client/packages/ai_message_ui/lib/src/markdown/registry/block_widget_registry.dart` | type → builder |
| `client/packages/ai_message_ui/lib/src/markdown/render/markdown_view.dart` | Column + gaps + registry (replaces `CompiledTextPartView`) |
| `client/packages/ai_message_ui/lib/src/markdown/render/blocks/*.dart` | paragraph merge, heading, list, table, code, quote, image, hr, raw |
| `client/packages/ai_message_ui/lib/src/markdown/compiled_markdown_chrome.dart` | Retarget extensions from `CompiledMarkdownStyle` → `MarkdownTokens` |
| `client/packages/ai_message_ui/lib/src/theme.dart` | `AiMessageTheme.markdown` becomes `MarkdownTokens` |
| `client/lib/theme/app_markdown_style_sheet.dart` | `buildAppMarkdownTokens(theme, profile)` only |
| `client/lib/pages/workbench/file_editor_surface.dart` | preview → `MarkdownView` + resolvers |
| `client/packages/ai_message_ui/lib/src/parts/text_part_view.dart` | chat → pipeline + `MarkdownView(compact)` |
| Also retarget chrome callers | `tool_call_part_view.dart`, `edit_tool_card.dart`, `reasoning_part_view.dart`, host `session_chat_view.dart` (grep `CompiledMarkdownStyle`) |
| Delete when unused (Task 8) | `content_ir.dart`, `content_compiler.dart`, `compiled_markdown_style.dart`, `compiled_text_part_view.dart` (after renames land) |
| Stop using | product `MarkdownBody` bodies, `toMarkdownStyleSheet`, layout heuristics in `flutter_markdown_plus` for app |

**Numeric targets (document profile)** — publish in Task 1 tests:

| Token | Value |
|-------|------:|
| body / blockquote height | 1.7 |
| `headingTop` h1…h6 | 40 / 36 / 32 / 28 / 28 / 28 |
| `headingBottom` | 8 |
| `paragraphGap` | 16 |
| `blockGap` | 28 |
| `listItemGap` | 8 |
| `listIndent` | 24 |
| `ruleGap` | 28 |
| table cell padding | 14×8 |
| table head fill | `onSurface` @ 0.04 |
| border | `outlineVariant` @ 0.45 |

**Compact profile:** same schema; start from today’s chat feel — `headingTop` ≈ 16/12/8/8/8/8, `headingBottom` 8, `paragraphGap` 12, `blockGap` 12, `listItemGap` 8 (tune only if probes fail).

---

### Task 1: `MarkdownBlockKind` + `gapBetween` + `MarkdownTokens` skeleton

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/markdown/ir/markdown_block_kind.dart`
- Create: `client/packages/ai_message_ui/lib/src/markdown/tokens/markdown_profile.dart`
- Create: `client/packages/ai_message_ui/lib/src/markdown/tokens/markdown_tokens.dart`
- Create: `client/packages/ai_message_ui/test/markdown_gap_test.dart`
- Modify: `client/packages/ai_message_ui/lib/ai_message_ui.dart` (export new tokens/kind)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t = MarkdownTokens.test();

  test('gapBetween priority: first / heading next / after heading / paragraphs', () {
    expect(gapBetween(null, MarkdownBlockKind.paragraph, t), 0);
    expect(
      gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.heading2, t),
      t.headingTop(2),
    );
    expect(
      gapBetween(MarkdownBlockKind.heading2, MarkdownBlockKind.list, t),
      t.headingBottom,
    );
    expect(
      gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.paragraph, t),
      t.paragraphGap,
    );
    expect(
      gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.code, t),
      t.blockGap,
    );
  });

  test('h6-sized body tokens do not change gap rules (kind-based only)', () {
    // Regression: style fingerprint used to treat body as heading.
    final bodyLike = MarkdownTokens.test();
    expect(bodyLike.h6.fontSize, bodyLike.body.fontSize);
    expect(
      gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.paragraph, bodyLike),
      bodyLike.paragraphGap,
    );
  });
}
  test('gapBetween covers hr and heading→paragraph', () {
    expect(
      gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.horizontalRule, t),
      t.ruleGap,
    );
    expect(
      gapBetween(MarkdownBlockKind.heading1, MarkdownBlockKind.paragraph, t),
      t.headingBottom,
    );
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/ai_message_ui && dart test test/markdown_gap_test.dart`

Expected: FAIL (library / symbols missing)

- [ ] **Step 3: Implement minimal API**

`markdown_block_kind.dart` — enum as in spec.

`markdown_profile.dart`:

```dart
enum MarkdownProfile { document, compact }
```

`markdown_tokens.dart` — class with typography/chrome/rhythm fields, `MarkdownTokens.test()` defaults, `headingTop(int level)`, and top-level:

```dart
double gapBetween(
  MarkdownBlockKind? previous,
  MarkdownBlockKind next,
  MarkdownTokens t,
) {
  if (previous == null) return 0;
  if (_isHeading(next)) return t.headingTop(_headingLevel(next));
  if (_isHeading(previous)) return t.headingBottom;
  if (previous == MarkdownBlockKind.paragraph &&
      next == MarkdownBlockKind.paragraph) {
    return t.paragraphGap;
  }
  if (previous == MarkdownBlockKind.horizontalRule ||
      next == MarkdownBlockKind.horizontalRule) {
    return t.ruleGap;
  }
  return t.blockGap;
}
```

Do **not** implement `toMarkdownStyleSheet`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client/packages/ai_message_ui && dart test test/markdown_gap_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/markdown/ir/markdown_block_kind.dart \
  client/packages/ai_message_ui/lib/src/markdown/tokens/ \
  client/packages/ai_message_ui/test/markdown_gap_test.dart \
  client/packages/ai_message_ui/lib/ai_message_ui.dart
git commit -m "feat(markdown): add kind-based gapBetween and MarkdownTokens"
```

---

### Task 2: New IR types (`MarkdownDocument` + Image + RawLiteral)

**Files:**
- Rename in place this task (single commit): `content_ir.dart` → `ir/markdown_document.dart` (update all package imports in the same commit — no dual files)
- Test: `client/packages/ai_message_ui/test/content_ir_test.dart` (or rename to `markdown_document_test.dart`)

**Rename map:**

| Old | New |
|-----|-----|
| `MessageContentDocument` | `MarkdownDocument` |
| `ContentBlock` | `MarkdownBlock` |
| `ParagraphBlock` | `ParagraphBlock` (add `MarkdownBlockKind get kind`) |
| `HeadingBlock` | `HeadingBlock` |
| `UnsupportedBlock` | `RawLiteralBlock` |
| (new) | `ImageBlock` / inline `ImageRun` |

Keep `content_compiler.dart` importing the new IR until Task 3 renames the compiler.

- [ ] **Step 1: Write failing tests for Image + kind**

In `content_ir_test.dart` (or `markdown_document_test.dart`):

```dart
test('HeadingBlock.kind maps level', () {
  expect(const HeadingBlock(level: 2, runs: []).kind, MarkdownBlockKind.heading2);
});

test('ImageBlock is a first-class block', () {
  const b = ImageBlock(src: 'a.png', alt: 'A');
  expect(b.kind, MarkdownBlockKind.image);
  expect(b.src, 'a.png');
});
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement IR with `.kind` on every block; replace `UnsupportedBlock` with `RawLiteralBlock`**

- [ ] **Step 4: Update equality/hash; fix compile errors in package only as needed for green IR tests**

- [ ] **Step 5: Run `dart test test/content_ir_test.dart` (and new doc test) — PASS**

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(markdown): kind-tagged IR with Image and RawLiteral"
```

---

### Task 3: `MarkdownPipeline` compiles images (no MarkdownBody fallback for `![…]`)

**Files:**
- Create/rename: `client/packages/ai_message_ui/lib/src/markdown/compile/markdown_pipeline.dart` (from `content_compiler.dart`, same commit)
- Keep: `streaming_markdown.dart` (move under `compile/` if desired)
- Test: `client/packages/ai_message_ui/test/content_ir_test.dart`, `content_compiler_test.dart`, `markdown_cache_test.dart`
- Fixture: rewrite or retire `21_with_image_unsupported.md` (must no longer require “image stays unsupported”); rename to reflect ImageBlock support or drop from must-compile set
- Modify: call sites of `compileMessageContent` → `compileMarkdown` / `MarkdownPipeline.compile`

- [ ] **Step 1: Failing test**

```dart
test('images compile to ImageBlock not RawLiteral', () {
  final doc = compileMarkdown('![alt](x.png)');
  expect(doc.blocks.single, isA<ImageBlock>());
  expect((doc.blocks.single as ImageBlock).src, 'x.png');
});

test('inline image in paragraph compiles to ImageRun', () {
  final doc = compileMarkdown('hi ![a](b.png) there');
  final p = doc.blocks.single as ParagraphBlock;
  expect(p.runs.whereType<ImageRun>(), isNotEmpty);
});

test('image inside list item compiles (not RawLiteral)', () {
  final doc = compileMarkdown('- ![a](b.png)');
  expect(doc.blocks.whereType<RawLiteralBlock>(), isEmpty);
});
```

Also flip any `content_compiler_test.dart` expectations that currently require `UnsupportedBlock` for images.

- [ ] **Step 2: Run — FAIL (still Unsupported/RawLiteral)**

- [ ] **Step 3: Implement image element → `ImageBlock` / inline `ImageRun`; HTML still → `RawLiteralBlock`**

Preserve LRU cache behavior from today’s compiler.

- [ ] **Step 4: Update corpus gate + fixture 21; keep ≥95% without RawLiteral for must-compile set**

- [ ] **Step 5: `dart test` relevant files — PASS**

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(markdown): compile images into ImageBlock"
```

---

### Task 4a: `MarkdownView` skeleton — Column + `gapBetween` only

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/markdown/registry/markdown_resolvers.dart`
- Create: `client/packages/ai_message_ui/lib/src/markdown/registry/block_widget_registry.dart`
- Create: `client/packages/ai_message_ui/lib/src/markdown/render/markdown_view.dart`
- Test: `client/packages/ai_message_ui/test/markdown_view_gap_test.dart`

- [ ] **Step 1: Failing widget test — heading→list uses headingBottom only**

```dart
testWidgets('heading then list gap is headingBottom not blockGap', (tester) async {
  final tokens = MarkdownTokens.test(
    // explicit: headingBottom: 8, blockGap: 28
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MarkdownView(
          document: MarkdownDocument(blocks: [
            const HeadingBlock(level: 2, runs: [TextRun('Acknowledgements')]),
            ListBlock(ordered: false, items: [
              ContentListItem(runs: [TextRun('File icons')]),
            ]),
          ]),
          tokens: tokens,
        ),
      ),
    ),
  );
  final heights = tester
      .widgetList<SizedBox>(find.byType(SizedBox))
      .map((s) => s.height)
      .whereType<double>();
  expect(heights, contains(tokens.headingBottom));
  expect(heights, isNot(contains(tokens.blockGap)));
});
```

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement `MarkdownView` as Column of registry widgets + `SizedBox` gaps; stub block builders as `Text(block.runtimeType.toString())` except heading/list enough for the test**

- [ ] **Step 4: PASS + commit**

```bash
git commit -m "feat(markdown): MarkdownView skeleton with kind-based gaps"
```

---

### Task 4b: Paragraph merge + headings (no style heuristics)

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/markdown/render/blocks/paragraph_heading.dart` (or split)
- Port strut / selection helpers from `compiled_text_part_view.dart`
- Test: merge + heading never merge

- [ ] **Step 1: Failing tests for paragraph-only merge and heading isolation**
- [ ] **Step 2: Implement `Text.rich` merge using `gapBetween(paragraph, paragraph)` for `\n\n` height; headings are separate widgets**
- [ ] **Step 3: PASS + commit `feat(markdown): paragraph merge and heading widgets`**

---

### Task 4c: List + blockquote recursion

**Files:**
- Create: list / blockquote block widgets
- Nested children reuse the same gap helper / nested `MarkdownView`

- [ ] **Step 1: Failing tests for `listItemGap` and nested quote gaps**
- [ ] **Step 2: Implement**
- [ ] **Step 3: PASS + commit `feat(markdown): list and blockquote widgets`**

---

### Task 4d: Table, code, hr

**Files:**
- Port `_CompiledTable` / code copy chrome / hr from `compiled_text_part_view.dart`
- Consume table tokens from `MarkdownTokens` (no hard-coded padding)

- [ ] **Step 1: Failing chrome tests (table padding / head fill)**
- [ ] **Step 2: Implement**
- [ ] **Step 3: PASS + commit `feat(markdown): table code hr widgets`**

---

### Task 4e: Image + RawLiteral (no `MarkdownBody`)

**Files:**
- Image widget via `MarkdownResolvers.resolveImage`
- RawLiteral → monospace source text
- Update must-compile tests: **zero** `MarkdownBody` in tree

- [ ] **Step 1: Failing tests — ImageBlock renders; RawLiteral has no MarkdownBody**
- [ ] **Step 2: Implement; remove `flutter_markdown_plus` import from render path**
- [ ] **Step 3: PASS + commit `feat(markdown): image and raw literal widgets`**

---

### Task 5: Host `buildAppMarkdownTokens` + `AiMessageTheme`

**Files:**
- Modify: `client/lib/theme/app_markdown_style_sheet.dart`
- Modify: `client/packages/ai_message_ui/lib/src/theme.dart`
- Modify: `client/lib/theme/app_theme.dart` (if wires theme)
- Modify: `client/packages/ai_message_ui/lib/src/markdown/compiled_markdown_chrome.dart` (+ tool/edit/reasoning callers)
- Delete in this task once unused: `compiled_markdown_style.dart` **only if** Task 4e already removed render dependency; otherwise delete in Task 8 with the other legacy files

- [ ] **Step 1: Failing host test**

```dart
test('document profile exposes Orca-like rhythm', () {
  final theme = /* existing Tp harness */;
  final doc = buildAppMarkdownTokens(theme, MarkdownProfile.document);
  expect(doc.body.height, 1.7);
  expect(doc.headingTop(1), 40);
  expect(doc.headingTop(2), 36);
  expect(doc.headingBottom, 8);
  expect(doc.paragraphGap, 16);
  expect(doc.blockGap, 28);
  expect(doc.listItemGap, 8);
});

test('compact profile is tighter than document headings', () {
  final theme = /* … */;
  final c = buildAppMarkdownTokens(theme, MarkdownProfile.compact);
  final d = buildAppMarkdownTokens(theme, MarkdownProfile.document);
  expect(c.headingTop(1), lessThan(d.headingTop(1)));
});
```

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement host builders; `AiMessageTheme.markdown` type = `MarkdownTokens` (compact for chat). Preview builds document tokens at call site.**

- [ ] **Step 4: Grep-delete `CompiledMarkdownStyle` / `buildAppMarkdownStyleSheet` / `toMarkdownStyleSheet`**

- [ ] **Step 5: `cd client && flutter test test/theme/app_markdown_style_sheet_test.dart` — PASS**

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(theme): buildAppMarkdownTokens for document and compact"
```

---

### Task 6: Wire chat (`AiTextPartView`) to `MarkdownView`

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/parts/text_part_view.dart`
- Preserve: `content_truncate.dart` + expandable history path (truncate IR, then `MarkdownView`)
- Test: existing text/history markdown tests

- [ ] **Step 1: Failing test if any still expect `CompiledTextPartView` / `MarkdownBody`**

- [ ] **Step 2: Switch compile + render; profile compact via `AiMessageTheme.markdown`**

- [ ] **Step 3: Run `cd client/packages/ai_message_ui && dart test` — PASS**

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(chat): render markdown via MarkdownView compact profile"
```

---

### Task 7: Wire file preview + resolvers

**Files:**
- Modify: `client/lib/pages/workbench/file_editor_surface.dart` (`_MarkdownPreviewPane`)
- Possibly: `client/lib/services/editor/markdown_preview_link_handler.dart` (reuse for `onLinkTap`)
- Test: add `client/test/pages/workbench/markdown_preview_pane_test.dart` (or nearest existing editor test)

- [ ] **Step 1: Failing test — preview pumps README-like markdown without `MarkdownBody`**

```dart
expect(find.byType(MarkdownBody), findsNothing);
expect(find.byType(MarkdownView), findsOneWidget);
```

- [ ] **Step 2: Implement**

```dart
MarkdownView(
  document: compileMarkdown(controller.text),
  tokens: buildAppMarkdownTokens(theme, MarkdownProfile.document),
  resolvers: MarkdownResolvers(
    onLinkTap: /* existing handler */,
    resolveImage: /* workspace / http policy */,
  ),
)
```

Keep `SelectionArea` **inside** scrollable content.

- [ ] **Step 3: Manual note in commit body: open README.md preview, check heading→list gap and paragraph gaps**

- [ ] **Step 4: Widget test — same fixture IR under document vs compact yields different headingTop SizedBox heights (no drift of structure)**

- [ ] **Step 5: `flutter test` for new/updated preview test — PASS**

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(preview): render markdown files with MarkdownView document profile"
```

---

### Task 8: Remove legacy markdown APIs + `flutter_markdown_plus` product deps

**Files:**
- Delete if still present: `content_ir.dart`, `content_compiler.dart`, `compiled_markdown_style.dart`, `compiled_text_part_view.dart`
- `client/packages/ai_message_ui/pubspec.yaml` — drop `flutter_markdown_plus` if unused
- `client/pubspec.yaml` — drop if unused
- Grep: `flutter_markdown_plus` / `MarkdownBody` / `CompiledMarkdownStyle` / `compileMessageContent` under `client/lib` and `ai_message_ui`
- Submodule: remove app dependency; delete submodule only if nothing else needs it

- [ ] **Step 1: Grep must be empty for product paths**

```bash
rg "flutter_markdown_plus|MarkdownBody|CompiledMarkdownStyle|compileMessageContent|toMarkdownStyleSheet" \
  client/lib client/packages/ai_message_ui/lib
```

Expected: no matches

- [ ] **Step 2: Remove deps + dead files; run analyzer**

```bash
cd client && flutter pub get && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 3: Commit**

```bash
git commit -m "chore: drop legacy markdown dual-path and flutter_markdown_plus"
```

---

### Task 9: Selection + corpus + warmup verification

**Files:**
- `client/packages/ai_message_ui/test/selection_list_gap_probe_test.dart` (update token field names)
- `client/packages/ai_message_ui/test/markdown_corpus_gate_test.dart`
- `client/test/theme/app_markdown_warmup_coverage_test.dart`
- Delete obsolete: `markdown_sheet_test` cases for `toMarkdownStyleSheet` / `h*Padding`

- [ ] **Step 1: Run full package + host markdown-related tests**

```bash
cd client/packages/ai_message_ui && dart test
cd client && flutter test test/theme/app_markdown_style_sheet_test.dart \
  test/theme/app_markdown_warmup_coverage_test.dart \
  --exclude-tags integration
```

- [ ] **Step 2: Fix failures without reintroducing style heuristics**

- [ ] **Step 3: Commit**

```bash
git commit -m "test(markdown): align probes with kind-based MarkdownView"
```

---

### Task 10: Final gate

- [ ] **Step 1:**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && \
  flutter test --exclude-tags integration
```

- [ ] **Step 2: Confirm success criteria from spec**

- One renderer for chat + preview
- Zero `_spanLooksLikeHeading` (or equivalent) in product code
- Grep clean of `toMarkdownStyleSheet` / product `MarkdownBody`

- [ ] **Step 3: Commit any leftover fixes; stop**

---

## Parallelism note

Tasks 1→2→3→4a→4b→4c→4d→4e are sequential. Task 5 can start after Task 1 (tokens shape stable) but must finish after 4e before Task 6. Tasks 6–7 need 4e+5. Task 8 after 6–7. Task 9–10 last.

## Out of scope (do not sneak in)

- KaTeX / Mermaid widgets (registry hooks only if trivial)
- WYSIWYG editor
- Preserving `MarkdownStyleSheet` compatibility shims
