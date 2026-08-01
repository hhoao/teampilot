# Orca-like Markdown Style Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make chat IR and file markdown preview share an airier Orca-like rhythm (line height, block spacing, table chrome) while keeping TeamPilot link color and glyph-warmup-safe `TpTextStyles` sizes.

**Architecture:** Extend `CompiledMarkdownStyle` with configurable table chrome fields (defaults preserve today's look). Host `buildAppCompiledMarkdownStyle` opts into Orca-like tokens. `_CompiledTable` and `toMarkdownStyleSheet()` both read those fields so chat and preview stay aligned.

**Tech Stack:** Flutter / Dart, `ai_message_ui` (`CompiledMarkdownStyle`, `CompiledTextPartView`), host theme in `client/lib/theme/app_markdown_style_sheet.dart`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-01-orca-like-markdown-style-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/ai_message_ui/lib/src/markdown/compiled_markdown_style.dart` | Add table chrome fields + wire `toMarkdownStyleSheet` |
| `client/packages/ai_message_ui/lib/src/markdown/compiled_text_part_view.dart` | `_CompiledTable` consumes new fields |
| `client/lib/theme/app_markdown_style_sheet.dart` | Host Orca-like typography / spacing / table tokens |
| `client/packages/ai_message_ui/test/markdown_sheet_test.dart` | Assert sheet maps new table tokens |
| `client/test/theme/app_markdown_style_sheet_test.dart` | Assert host height / blockSpacing / table padding |
| `client/packages/ai_message_ui/test/selection_list_gap_probe_test.dart` | Sync hard-coded height / blockSpacing if asserted |
| `client/test/theme/app_markdown_warmup_coverage_test.dart` | Should still pass (no new fontSize) — run, don't change unless fail |

No new files. Do not change link color to GitHub blue. Do not add ad-hoc `fontSize`.

---

### Task 1: Package API — table chrome fields on `CompiledMarkdownStyle`

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/markdown/compiled_markdown_style.dart`
- Test: `client/packages/ai_message_ui/test/markdown_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

In `markdown_sheet_test.dart`, extend the existing `toMarkdownStyleSheet` test (or add a sibling) so defaults and overrides are explicit:

```dart
test('CompiledMarkdownStyle table chrome maps to sheet (defaults + override)', () {
  final theme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    useMaterial3: true,
  );
  final defaults = CompiledMarkdownStyle.test(scheme: theme.colorScheme);
  final defaultSheet = defaults.toMarkdownStyleSheet();

  expect(
    defaultSheet.tableCellsPadding,
    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  );
  // tableHeadBackground is Color? — null means resolve to mutedSurface@0.85
  expect(
    (defaultSheet.tableHeadCellsDecoration! as BoxDecoration).color,
    defaults.mutedSurface.withValues(alpha: 0.85),
  );
  expect(defaultSheet.h1Padding, const EdgeInsets.only(top: 16));
  expect(defaultSheet.h2Padding, const EdgeInsets.only(top: 12));
  expect(defaultSheet.h3Padding, const EdgeInsets.only(top: 8));

  const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 8);
  final head = theme.colorScheme.onSurface.withValues(alpha: 0.04);
  // Construct with new named params on test() / constructor — no copyWith.
  final custom = CompiledMarkdownStyle.test(
    scheme: theme.colorScheme,
    tableCellsPadding: padding,
    tableHeadBackground: head,
    tableBodyBackground: Colors.transparent,
  );
  final sheet = custom.toMarkdownStyleSheet();
  expect(sheet.tableCellsPadding, padding);
  expect(
    (sheet.tableHeadCellsDecoration! as BoxDecoration).color,
    head,
  );
  expect(sheet.tableCellsDecoration, isA<BoxDecoration>());
  expect(
    (sheet.tableCellsDecoration! as BoxDecoration).color,
    Colors.transparent,
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client/packages/ai_message_ui && flutter test test/markdown_sheet_test.dart
```

Expected: FAIL — missing fields / still hard-coded padding or muted head color.

- [ ] **Step 3: Implement fields + sheet wiring**

In `compiled_markdown_style.dart`:

1. Add constructor params with defaults matching today's hard-codes:

```dart
this.tableCellsPadding =
    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
this.tableHeadBackground, // nullable → resolve in getters / sheet
this.tableBodyBackground = Colors.transparent,
```

Prefer non-nullable with defaults computed in the constructor body / factory when theme colors are needed. Practical pattern:

```dart
final Color tableHeadBackground;
final Color tableBodyBackground;
final EdgeInsets tableCellsPadding;

// In constructor: require tableHeadBackground OR default in factory.test
// and in host builder. For main const constructor, require the Color
// params (breaking) OR keep optional Color? and resolve:

Color get resolvedTableHeadBackground =>
    tableHeadBackground ?? mutedSurface.withValues(alpha: 0.85);
```

Spec: defaults must equal today's behavior for unrelated call sites. Use:

- `tableCellsPadding` default `EdgeInsets.symmetric(horizontal: 12, vertical: 6)`
- `tableHeadBackground` optional `Color?`; when null, `mutedSurface.withValues(alpha: 0.85)`
- `tableBodyBackground` default `Colors.transparent`

2. Update `toMarkdownStyleSheet()`:

```dart
tableCellsPadding: tableCellsPadding,
tableHeadCellsDecoration: BoxDecoration(
  color: tableHeadBackground ?? mutedSurface.withValues(alpha: 0.85),
),
tableCellsDecoration: BoxDecoration(color: tableBodyBackground),
tableBorder: TableBorder.all(color: borderColor, width: 1),
h1Padding: const EdgeInsets.only(top: 16),
h2Padding: const EdgeInsets.only(top: 12),
h3Padding: const EdgeInsets.only(top: 8),
```

(Heading padding change is host-visible via sheet; package defaults can stay or move to 16/12/8 only when host uses the sheet — apply 16/12/8 in `toMarkdownStyleSheet` as in the spec so preview matches.)

3. Wire the same fields through `CompiledMarkdownStyle.test(...)`.

- [ ] **Step 4: Run test to verify it passes**

```bash
cd client/packages/ai_message_ui && flutter test test/markdown_sheet_test.dart
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/markdown/compiled_markdown_style.dart \
  client/packages/ai_message_ui/test/markdown_sheet_test.dart
git commit -m "$(cat <<'EOF'
feat(ai_message_ui): configurable markdown table chrome tokens

EOF
)"
```

---

### Task 2: `_CompiledTable` consumes style fields

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/markdown/compiled_text_part_view.dart` (`_CompiledTable`, ~414–500)
- Test: extend `client/packages/ai_message_ui/test/markdown_sheet_test.dart` with a widget probe **or** add assertions in an existing table widget test

- [ ] **Step 1: Write the failing widget test**

Add a `testWidgets` that builds `CompiledTextPartView` with a `TableBlock` and a custom `tableCellsPadding` / `tableHeadBackground`, then inspect the `Padding` / `ColoredBox` under `_CompiledTable`:

```dart
testWidgets('CompiledTextPartView table uses style table chrome', (tester) async {
  // Needs: import 'package:ai_message_ui/src/markdown/content_ir.dart';
  // and compiled_text_part_view.dart (same as other package tests).
  final base = CompiledMarkdownStyle.test();
  const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 8);
  final head = const Color(0x14000000); // distinctive for expect
  final style = CompiledMarkdownStyle(
    body: base.body,
    h1: base.h1,
    h2: base.h2,
    h3: base.h3,
    h4: base.h4,
    h5: base.h5,
    h6: base.h6,
    link: base.link,
    inlineCode: base.inlineCode,
    codeBlock: base.codeBlock,
    codeLanguage: base.codeLanguage,
    listBullet: base.listBullet,
    blockquote: base.blockquote,
    tableHead: base.tableHead,
    tableBody: base.tableBody,
    mutedSurface: base.mutedSurface,
    borderColor: base.borderColor,
    codeBlockRadius: base.codeBlockRadius,
    tableCellsPadding: padding,
    tableHeadBackground: head,
    tableBodyBackground: Colors.transparent,
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CompiledTextPartView(
          style: style,
          document: MessageContentDocument(
            blocks: [
              TableBlock(
                headers: [
                  InlineDocument(runs: [TextRun('Doc')]),
                ],
                rows: [
                  [
                    InlineDocument(runs: [TextRun('AGENTS.md')]),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  final headerPad = tester.widgetList<Padding>(find.byType(Padding)).where(
    (p) => p.padding == padding,
  );
  expect(headerPad, isNotEmpty);

  final fills = tester.widgetList<ColoredBox>(find.byType(ColoredBox));
  expect(fills.any((c) => c.color == head), isTrue);
});
```

Adjust imports / `TableBlock` / `InlineDocument` constructors to match `content_ir.dart` exactly (read that file before writing the test).

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client/packages/ai_message_ui && flutter test test/markdown_sheet_test.dart
```

Expected: FAIL — table still hard-codes `12/6` and `mutedSurface@0.85`.

- [ ] **Step 3: Update `_CompiledTable`**

Replace hard-coded padding and header color:

```dart
color: isHeader
    ? (style.tableHeadBackground ??
        style.mutedSurface.withValues(alpha: 0.85))
    : style.tableBodyBackground,
// ...
padding: style.tableCellsPadding,
```

Keep existing border / Column layout.

- [ ] **Step 4: Run tests**

```bash
cd client/packages/ai_message_ui && flutter test test/markdown_sheet_test.dart
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/markdown/compiled_text_part_view.dart \
  client/packages/ai_message_ui/test/markdown_sheet_test.dart
git commit -m "$(cat <<'EOF'
fix(ai_message_ui): drive compiled table chrome from style tokens

EOF
)"
```

---

### Task 3: Host Orca-like tokens in `buildAppCompiledMarkdownStyle`

**Files:**
- Modify: `client/lib/theme/app_markdown_style_sheet.dart`
- Test: `client/test/theme/app_markdown_style_sheet_test.dart`
- Possibly touch: `client/packages/ai_message_ui/test/selection_list_gap_probe_test.dart` (only if values are asserted against host — that probe builds its own style; update local `1.65`/`24` only if the test purpose is “match product rhythm”; otherwise leave probe-specific)

- [ ] **Step 1: Write the failing host test**

Update `app_markdown_style_sheet_test.dart`:

```dart
expect(sheet.p?.height, 1.7);
expect(sheet.blockquote?.height, 1.7);
expect(sheet.blockSpacing, 28);
expect(
  buildAppCompiledMarkdownStyle(theme).listItemSpacing,
  8,
);
expect(
  sheet.tableCellsPadding,
  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
);
expect(sheet.h1?.height, 1.3);
expect(sheet.h1?.letterSpacing, -0.02);
expect(sheet.h2?.height, 1.3);

final compiled = buildAppCompiledMarkdownStyle(theme);
expect(
  compiled.borderColor,
  theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
);
expect(
  compiled.tableHeadBackground,
  theme.colorScheme.onSurface.withValues(alpha: 0.04),
);
```

Use the actual field accessors once Task 1 lands (`tableHeadBackground` non-null when host sets it).

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client && flutter test test/theme/app_markdown_style_sheet_test.dart
```

Expected: FAIL on height / blockSpacing / padding.

- [ ] **Step 3: Implement host tokens**

In `app_markdown_style_sheet.dart`:

```dart
CompiledMarkdownStyle buildAppCompiledMarkdownStyle(
  ThemeData theme, {
  Color? mutedSurface,
  double codeBlockRadius = 12,
  double blockSpacing = 28,
  double listItemSpacing = 8,
}) {
  // ...
  final body = withUi(styles.mdRelaxed.copyWith(height: 1.7));
  final border = scheme.outlineVariant.withValues(alpha: 0.45);
  final tableHead = scheme.onSurface.withValues(alpha: 0.04);

  return CompiledMarkdownStyle(
    body: body,
    h1: withUi(styles.display.copyWith(height: 1.3, letterSpacing: -0.02)),
    h2: withUi(styles.xl.copyWith(height: 1.3)),
    h3: withUi(styles.lgSemiboldSnug.copyWith(height: 1.3)),
    h4: withUi(styles.lgSnug.copyWith(height: 1.3)),
    h5: withUi(styles.mdSemiboldTightSnug.copyWith(height: 1.3)),
    h6: body,
    link: body.copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary,
    ),
    // ... unchanged mono / code / listBullet ...
    blockquote: withUi(
      styles.mdRelaxed.copyWith(
        color: scheme.onSurfaceVariant,
        height: 1.7,
      ),
    ),
    tableHead: withUi(styles.mdSemibold),
    tableBody: body,
    mutedSurface: muted,
    borderColor: border,
    codeBlockRadius: codeBlockRadius,
    blockSpacing: blockSpacing,
    listItemSpacing: listItemSpacing,
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    tableHeadBackground: tableHead,
    tableBodyBackground: Colors.transparent,
  );
}
```

Do **not** change link color away from `scheme.primary`. Do **not** add new `fontSize`s.

- [ ] **Step 4: Run host + warmup tests**

```bash
cd client && flutter test \
  test/theme/app_markdown_style_sheet_test.dart \
  test/theme/app_markdown_warmup_coverage_test.dart
```

Expected: PASS. If warmup fails, you introduced an uncovered size — revert that size to a `TpTextStyles` token.

- [ ] **Step 5: Commit**

```bash
git add client/lib/theme/app_markdown_style_sheet.dart \
  client/test/theme/app_markdown_style_sheet_test.dart
git commit -m "$(cat <<'EOF'
feat(theme): adopt Orca-like markdown spacing and table chrome

EOF
)"
```

---

### Task 4: Sync probes + package regression sweep

**Files:**
- Modify only if needed: `client/packages/ai_message_ui/test/selection_list_gap_probe_test.dart`
- Run: package + theme tests

- [ ] **Step 1: Decide probe sync**

`selection_list_gap_probe_test` builds a **local** style with `height: 1.65` and `blockSpacing: 24` to probe strut behavior — not host product tokens. **Leave those values** unless the test explicitly documents “must match app markdown”. Do not churn it for cosmetics.

- [ ] **Step 2: Run broader verification**

```bash
cd client/packages/ai_message_ui && flutter test
cd client && flutter test test/theme/app_markdown_style_sheet_test.dart \
  test/theme/app_markdown_warmup_coverage_test.dart
```

Expected: PASS

- [ ] **Step 3: Manual check (implementer)**

Open TeamPilot markdown preview on `README.md` and a chat message with a table: airier body, light table header, no full-table gray wash, primary-colored links.

- [ ] **Step 4: Commit only if probe files changed**; otherwise skip.

---

## Execution notes

- Work from repo root `teampilot`; package tests from `client/packages/ai_message_ui`.
- Prefer optional named params with legacy defaults so `CompiledMarkdownStyle(` call sites in probes keep compiling.
- Glyph warmup: height / letterSpacing ignored by `shapeKey` — no `gen_warmup_glyphs` for this change.
- SelectionArea / Flutter patch work is **out of scope** (separate spec).
