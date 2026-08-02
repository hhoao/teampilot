# Markdown Block Margins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace scalar markdown gap fields with per-`MarkdownBlockKind` `EdgeInsets`, CSS-like vertical collapse via `gapBetween`, and host-side sparse `TpScaledEdgeInsets` resolved from window width.

**Architecture:** `tp_markdown` owns resolved `marginOf(kind)` + `gapBetween = max(prev.bottom, next.top)` and applies L/R `Padding` in `MarkdownView`. The app resolves sparse `TpScaledEdgeInsets` anchors in `buildAppMarkdownTokens(..., width:)` and passes plain `EdgeInsets`. Accept visual deltas vs the old priority gap matrix.

**Tech Stack:** Flutter, `tp_markdown`, `shared_ui` (`TpScaledEdgeInsets` / `TpBreakpoints`) in app only.

**Spec:** `docs/superpowers/specs/2026-08-02-markdown-block-margins-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/tp_markdown/lib/src/tokens/markdown_tokens.dart` | `marginOf`, collapse `gapBetween`; drop scalar gap fields |
| `client/packages/tp_markdown/lib/src/render/markdown_view.dart` | Collapse `SizedBox` + optional L/R `Padding` |
| `client/packages/tp_markdown/lib/src/render/inline_spans.dart` | Merged-paragraph `\n\n` height still uses `gapBetween` |
| `client/packages/tp_markdown/test/markdown_gap_test.dart` | Collapse unit matrix |
| `client/packages/tp_markdown/test/markdown_view_gap_test.dart` | Widget gap heights under collapse |
| `client/packages/tp_markdown/test/markdown_view_paragraph_test.dart` | Merged paragraph + L/R padding cases |
| Other `tp_markdown` tests that construct `MarkdownTokens.test(...)` with old scalars | Update constructors |
| `client/lib/theme/app_markdown_style_sheet.dart` | `width` + `TpScaledEdgeInsets` anchors → margins |
| `client/test/theme/app_markdown_style_sheet_test.dart` | Profile + width assertions |
| `client/test/theme/app_markdown_warmup_coverage_test.dart` | Pass fixed `width` |
| Call sites: `file_editor_surface.dart`, `session_chat_view.dart`, `markdown_preview_pane_test.dart` | Pass `MediaQuery` / fixed width |
| Spec docs that still describe scalar priority matrix | Point at new margins spec |

---

### Task 1: Collapse `gapBetween` unit API on `MarkdownTokens`

**Files:**
- Modify: `client/packages/tp_markdown/lib/src/tokens/markdown_tokens.dart`
- Modify: `client/packages/tp_markdown/test/markdown_gap_test.dart`

- [ ] **Step 1: Rewrite failing unit tests for collapse**

Replace priority assertions with collapse. Example shape:

```dart
test('gapBetween collapses adjacent vertical margins', () {
  final t = MarkdownTokens.test(
    paragraphMargin: const EdgeInsets.only(bottom: 16),
    h2Margin: const EdgeInsets.only(top: 36, bottom: 8),
    listMargin: const EdgeInsets.only(bottom: 28),
    codeMargin: const EdgeInsets.only(bottom: 28),
    horizontalRuleMargin: const EdgeInsets.only(bottom: 28),
  );
  expect(gapBetween(null, MarkdownBlockKind.paragraph, t), 0);
  expect(
    gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.heading2, t),
    36, // max(16, 36)
  );
  expect(
    gapBetween(MarkdownBlockKind.heading2, MarkdownBlockKind.list, t),
    8, // max(8, 0)
  );
  expect(
    gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.paragraph, t),
    16, // max(16, 0)
  );
  expect(
    gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.code, t),
    16,
  );
  expect(
    gapBetween(MarkdownBlockKind.heading1, MarkdownBlockKind.paragraph, t),
    // h1 defaults from test factory
    greaterThanOrEqualTo(0),
  );
});

test('gapBetween covers hr and heading→heading', () {
  final t = MarkdownTokens.test(
    paragraphMargin: const EdgeInsets.only(bottom: 16),
    horizontalRuleMargin: const EdgeInsets.only(bottom: 28),
    h1Margin: const EdgeInsets.only(top: 40, bottom: 8),
    h2Margin: const EdgeInsets.only(top: 36, bottom: 8),
  );
  expect(
    gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.horizontalRule, t),
    16,
  );
  expect(
    gapBetween(MarkdownBlockKind.heading1, MarkdownBlockKind.heading2, t),
    36, // max(8, 36)
  );
});
```

Adjust named args to whatever constructor API Task 1 Step 3 lands (explicit `*Margin` fields or a map). Keep names consistent across tests.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/tp_markdown && flutter test test/markdown_gap_test.dart`

Expected: FAIL (missing `marginOf` / old priority API).

- [ ] **Step 3: Implement `marginOf` + collapse `gapBetween`**

In `markdown_tokens.dart`:

1. Remove scalar fields: `headingBottom`, `paragraphGap`, `blockGap`, `ruleGap`, `h1TopSpacing`…`h6TopSpacing`.
2. Add explicit `EdgeInsets` fields (preferred for clarity): `paragraphMargin`, `h1Margin`…`h6Margin`, `listMargin`, `blockquoteMargin`, `codeMargin`, `tableMargin`, `horizontalRuleMargin`, `imageMargin`, `rawLiteralMargin`.
3. Add:

```dart
EdgeInsets marginOf(MarkdownBlockKind kind) => switch (kind) {
  MarkdownBlockKind.paragraph => paragraphMargin,
  MarkdownBlockKind.heading1 => h1Margin,
  // ...
  MarkdownBlockKind.rawLiteral => rawLiteralMargin,
};
```

4. `MarkdownTokens.test({...})` defaults: headings `EdgeInsets.only(top: 16/12/8…, bottom: 8)`, paragraph `bottom: 12`, other blocks `bottom: 12`, L/R `0`. Allow overriding each `*Margin`.
5. Replace `gapBetween`:

```dart
double gapBetween(
  MarkdownBlockKind? previous,
  MarkdownBlockKind next,
  MarkdownTokens t,
) {
  if (previous == null) return 0;
  return math.max(
    t.marginOf(previous).bottom,
    t.marginOf(next).top,
  );
}
```

Remove `_isHeading` / `_headingLevel` if unused afterward (keep `headingStyle` / level helpers used by render).

- [ ] **Step 4: Run unit test — pass**

Run: `cd client/packages/tp_markdown && flutter test test/markdown_gap_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/tp_markdown/lib/src/tokens/markdown_tokens.dart \
  client/packages/tp_markdown/test/markdown_gap_test.dart
git commit -m "feat(tp_markdown): per-kind margins with CSS-like gap collapse"
```

---

### Task 2: Fix package compile + widget tests for new tokens

**Files:**
- Modify: `client/packages/tp_markdown/test/markdown_view_gap_test.dart`
- Modify: `client/packages/tp_markdown/test/markdown_view_paragraph_test.dart`
- Modify: `client/packages/tp_markdown/test/markdown_view_heading_code_test.dart`
- Modify: `client/packages/tp_markdown/test/selection_list_gap_probe_test.dart`
- Modify: any other package test that copies scalar fields from `MarkdownTokens.test`

- [ ] **Step 1: Update widget gap test to collapse**

`markdown_view_gap_test.dart` — replace headingBottom/blockGap setup:

```dart
testWidgets('heading then list gap uses collapsed margins', (tester) async {
  final tokens = MarkdownTokens.test(
    h2Margin: const EdgeInsets.only(top: 36, bottom: 8),
    listMargin: const EdgeInsets.only(bottom: 28),
  );
  // pump ## Title\n\n- item  (same as today)
  // expect SizedBox height 8 (= max(8, 0)), not 28
});
```

- [ ] **Step 2: Update paragraph tests**

- Merged paragraphs: set `paragraphMargin: EdgeInsets.only(bottom: 17)` instead of `paragraphGap`.
- Paragraph→code: set `paragraphMargin` bottom + `codeMargin` top/bottom so expected `SizedBox` = `max(...)`.

- [ ] **Step 3: Fix remaining `MarkdownTokens(...)` full copies**

In heading_code / selection_list tests, stop forwarding removed scalars; use `marginOf` fields or `MarkdownTokens.test()` + `copyWith` if you add one. Prefer reconstructing via `test()` overrides.

- [ ] **Step 4: Run package tests**

Run: `cd client/packages/tp_markdown && flutter test`

Expected: all PASS. If analyze errors in app (not yet updated), that is OK until Task 4 — but package must be green.

- [ ] **Step 5: Commit**

```bash
git add client/packages/tp_markdown/test
git commit -m "test(tp_markdown): update views for margin collapse tokens"
```

---

### Task 3: `MarkdownView` horizontal Padding + L/R widget test

**Files:**
- Modify: `client/packages/tp_markdown/lib/src/render/markdown_view.dart`
- Modify: `client/packages/tp_markdown/test/markdown_view_paragraph_test.dart` (or new `markdown_view_margin_padding_test.dart`)

- [ ] **Step 1: Failing widget test — non-zero L/R wraps Padding**

```dart
testWidgets('block with horizontal margin is padded', (tester) async {
  final tokens = MarkdownTokens.test(
    paragraphMargin: const EdgeInsets.only(left: 12, right: 8, bottom: 16),
  );
  await tester.pumpWidget(/* MarkdownView with one paragraph */);
  final padding = tester.widgetList<Padding>(find.byType(Padding))
      .map((p) => p.padding)
      .whereType<EdgeInsets>()
      .where((e) => e.left == 12 && e.right == 8 && e.top == 0 && e.bottom == 0);
  expect(padding, isNotEmpty);
});
```

- [ ] **Step 2: Run test — fail**

Run: `cd client/packages/tp_markdown && flutter test test/markdown_view_paragraph_test.dart` (or the new file)

Expected: FAIL (no L/R Padding).

- [ ] **Step 3: Wrap built blocks**

In `MarkdownView`, after `reg.build(...)` / paragraph builders:

```dart
Widget wrapHorizontal(MarkdownBlockKind kind, Widget child) {
  final m = tokens.marginOf(kind);
  if (m.left == 0 && m.right == 0) return child;
  return Padding(
    padding: EdgeInsets.only(left: m.left, right: m.right),
    child: child,
  );
}
```

Apply to both single blocks and merged paragraph runs (`kind` = paragraph). Do **not** put top/bottom on this Padding. Nested `MarkdownView`s already go through the same path.

- [ ] **Step 4: Run tests — pass**

Run: `cd client/packages/tp_markdown && flutter test`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/tp_markdown/lib/src/render/markdown_view.dart \
  client/packages/tp_markdown/test
git commit -m "feat(tp_markdown): apply horizontal block margins as Padding"
```

---

### Task 4: Host `buildAppMarkdownTokens` + width scaling

**Files:**
- Modify: `client/lib/theme/app_markdown_style_sheet.dart`
- Modify: `client/test/theme/app_markdown_style_sheet_test.dart`
- Modify: `client/test/theme/app_markdown_warmup_coverage_test.dart`

- [ ] **Step 1: Failing app tests for margins + width**

Update `app_markdown_style_sheet_test.dart`:

```dart
final tokens = buildAppMarkdownTokens(
  theme,
  MarkdownProfile.document,
  width: TpBreakpoints.xxl, // or md — pick one for “full” document anchors
);
expect(tokens.marginOf(MarkdownBlockKind.heading1).top, 40);
expect(tokens.marginOf(MarkdownBlockKind.heading1).bottom, 8);
expect(tokens.marginOf(MarkdownBlockKind.paragraph).bottom, 16);
expect(tokens.marginOf(MarkdownBlockKind.code).bottom, 28);

final compact = buildAppMarkdownTokens(
  theme,
  MarkdownProfile.compact,
  width: TpBreakpoints.xxl,
);
expect(compact.marginOf(MarkdownBlockKind.heading1).top, lessThan(40));

test('document margins scale with width between sm and xxl', () {
  final sm = buildAppMarkdownTokens(theme, MarkdownProfile.document, width: TpBreakpoints.sm);
  final xxl = buildAppMarkdownTokens(theme, MarkdownProfile.document, width: TpBreakpoints.xxl);
  // If anchors differ at sm vs xxl for h1.top:
  expect(sm.marginOf(MarkdownBlockKind.heading1).top,
      lessThan(xxl.marginOf(MarkdownBlockKind.heading1).top));
});
```

If v1 uses **identical** values at sm and xxl for some kinds (constant `TpScaledEdgeInsets(lg: …)`), assert constancy instead — but headings should use at least two stops (sm smaller, xxl = former document tops) per spec intent.

- [ ] **Step 2: Run tests — fail**

Run: `cd client && flutter test test/theme/app_markdown_style_sheet_test.dart`

Expected: FAIL (no `width` / still scalars).

- [ ] **Step 3: Implement host builder**

Signature:

```dart
MarkdownTokens buildAppMarkdownTokens(
  ThemeData theme,
  MarkdownProfile profile, {
  required double width,
  Color? mutedSurface,
  double codeBlockRadius = 12,
})
```

Define sparse anchors per profile (document example):

```dart
// Document — map former scalars; scale tops between sm/xxl if desired.
final h1 = TpScaledEdgeInsets(
  sm: const EdgeInsets.only(top: 24, bottom: 8),
  xxl: const EdgeInsets.only(top: 40, bottom: 8),
).forWidth(width);
// h2…h6 similarly from former tops; bottom 8
final paragraph = TpScaledEdgeInsets(
  sm: const EdgeInsets.only(bottom: 12),
  xxl: const EdgeInsets.only(bottom: 16),
).forWidth(width);
final block = TpScaledEdgeInsets(
  sm: const EdgeInsets.only(bottom: 16),
  xxl: const EdgeInsets.only(bottom: 28),
).forWidth(width);
final rule = TpScaledEdgeInsets(
  sm: const EdgeInsets.only(bottom: 16),
  xxl: const EdgeInsets.only(bottom: 28),
).forWidth(width);
```

Compact: smaller sm/xxl pairs (former compact scalars at xxl).

Pass into `MarkdownTokens(... *Margin: ...)`.

Warmup helpers without context:

```dart
List<TextStyle> appMarkdownTextStyles(ThemeData theme) {
  return buildAppMarkdownTokens(
    theme,
    MarkdownProfile.document,
    width: TpBreakpoints.md, // warmup ignores margins
  ).textStylesForWarmup;
}
```

Same for `buildAppAiMessageTheme` / `warmMarkdownMixedInlineLayout` — fixed `TpBreakpoints.md` with a one-line comment that warmup path margins are unused.

- [ ] **Step 4: Fix warmup coverage tests to pass `width: TpBreakpoints.md`**

- [ ] **Step 5: Run theme tests — pass**

Run: `cd client && flutter test test/theme/app_markdown_style_sheet_test.dart test/theme/app_markdown_warmup_coverage_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/theme/app_markdown_style_sheet.dart \
  client/test/theme/app_markdown_style_sheet_test.dart \
  client/test/theme/app_markdown_warmup_coverage_test.dart
git commit -m "feat(theme): resolve markdown margins with TpScaledEdgeInsets"
```

---

### Task 5: Wire call sites with window width

**Files:**
- Modify: `client/lib/pages/workbench/file_editor_surface.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Modify: `client/test/pages/workbench/markdown_preview_pane_test.dart`
- Grep: `buildAppMarkdownTokens(` for any remaining callers

- [ ] **Step 1: Grep remaining callers**

Run: `rg -n "buildAppMarkdownTokens\\(" client`

Expected: only style sheet + surfaces + tests.

- [ ] **Step 2: Pass window width at UI call sites**

File preview (comment: v1 uses window width, not pane):

```dart
tokens: buildAppMarkdownTokens(
  theme,
  MarkdownProfile.document,
  width: MediaQuery.sizeOf(context).width,
),
```

Chat theme override: same with `MarkdownProfile.compact`.

Tests without real MediaQuery: `width: TpBreakpoints.md` (or pump a sized `MediaQuery`).

- [ ] **Step 3: Analyze + targeted tests**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test test/theme/ test/pages/workbench/markdown_preview_pane_test.dart
cd packages/tp_markdown && flutter test
```

Expected: no errors from missing `width`; tests PASS.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/workbench/file_editor_surface.dart \
  client/lib/pages/chat/session_chat_view.dart \
  client/test/pages/workbench/markdown_preview_pane_test.dart
# plus any other callers fixed
git commit -m "fix(markdown): pass window width into markdown token builder"
```

---

### Task 6: Docs + block audit + final verify

**Files:**
- Modify: `docs/superpowers/specs/2026-08-01-markdown-semantic-renderer-design.md` (spacing section → point at margins spec / collapse)
- Modify: `docs/superpowers/specs/2026-08-02-tp-markdown-package-design.md` (tokens row)
- Modify: `client/packages/tp_markdown/README.md` (pipeline line)
- Audit: block widgets under `client/packages/tp_markdown/lib/src/render/` for outer top/bottom `Padding`/`SizedBox` that duplicate gaps

- [ ] **Step 1: Update design docs** — replace scalar priority list with “see `2026-08-02-markdown-block-margins-design.md`; `gapBetween` = collapse”.

- [ ] **Step 2: Audit block widgets** — code/table/blockquote/list must not add outer vertical margins; internal chrome only. Fix if any duplicate found.

- [ ] **Step 3: Full client verify**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`

Expected: PASS (or only pre-existing failures unrelated to this change — do not claim green without checking).

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs client/packages/tp_markdown/README.md \
  client/packages/tp_markdown/lib/src/render
git commit -m "docs(markdown): document margin collapse; audit block chrome"
```

---

## Execution notes

- Do **not** reintroduce priority branches to match old `headingBottom` vs `blockGap` asymmetries.
- `listItemGap` / `listIndent` / `tableCellsPadding` / file-editor `_markdownPadding` stay unchanged.
- Prefer frequent commits as listed; do not push unless asked.
