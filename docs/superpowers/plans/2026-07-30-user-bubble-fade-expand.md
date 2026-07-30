# User Bubble Fade-Expand Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add shared `AiFadeExpandBody` (120px collapsed fade + chevron, 320px expanded scroll) and wire it into History user bubbles plus edit/shell tool card bodies.

**Architecture:** New controlled widget measures full child height, gates chrome on collapsed max only, owns clip/scroll/fade/chevron. User bubbles hold local `_open`; edit/shell reuse existing `open`/`onToggle` and keep `AiExpandableToolCard` whole-card tap. Fade/chevron uses opaque child `GestureDetector` so tool cards toggle once.

**Tech Stack:** Dart / Flutter; package `ai_message_ui` (depends on `ai_message_core`).

**Spec:** `docs/superpowers/specs/2026-07-30-user-bubble-fade-expand-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/ai_message_ui/lib/src/parts/fade_expand_body.dart` | `AiFadeExpandBody`, height constants, hit-strip constant; measure + clip + fade + chevron |
| `client/packages/ai_message_ui/lib/src/parts/expandable_tool_card.dart` | Keep `AiExpandableToolCard`; set `kAiToolCardExpandedMaxHeight = kAiFadeExpandExpandedMaxHeight` (re-export / alias); leave `previewToolCardText` for now if tests still use it |
| `client/packages/ai_message_ui/lib/src/ai_message_view.dart` | Stateful host around `_UserBubble` parts → `AiFadeExpandBody` |
| `client/packages/ai_message_ui/lib/src/edit/edit_tool_card.dart` | Mount full hunk lines; wrap body in `AiFadeExpandBody`; remove local 320 `ConstrainedBox` |
| `client/packages/ai_message_ui/lib/src/shell/shell_tool_card.dart` | Mount full output; wrap terminal column in `AiFadeExpandBody`; remove local 320 box + collapsed `previewToolCardText` on this path |
| `client/packages/ai_message_ui/lib/ai_message_ui.dart` | Export fade-expand API |
| `client/packages/ai_message_ui/test/fade_expand_body_test.dart` | Shell unit/widget tests |
| `client/packages/ai_message_ui/test/user_bubble_fade_expand_test.dart` | User bubble integration |
| `client/packages/ai_message_ui/test/tool_call_edit_target_test.dart` | Fade chevron + no double toggle; full body when collapsed |
| `client/packages/ai_message_ui/test/tool_call_shell_target_test.dart` | Same for shell |

**Measurement strategy (locked):** `AiFadeExpandBody` is stateful. Measure full child height **without letting the probe contribute to parent layout size**. Do **not** put a non-positioned `Offstage(tallChild)` in a `Stack` — Offstage still participates in Stack sizing and would expand the collapsed host to full content height.

Use one of these (pick in Task 1; prefer A):

- **A (recommended):** `Stack` + `Positioned(left:0, top:0, width: maxWidth, height: 0, child: OverflowBox(maxHeight: infinity, alignment: topLeft, child: _ReportSize(...)))` so the probe has zero Stack contribution.
- **B:** Single custom `RenderBox` that lays out child unbounded-in-height, records height, then sizes itself to the clipped viewport and paints the child clipped.

`_ReportSize` calls `onSize` after `performLayout` (post-frame). **Clip-until-measured:** until `_childHeight != null`, visible path uses collapsed max clip (no full-height flash).

**Duplicate child in tree:** probe + visible both mount `child`, so `find.textContaining` may hit **2** widgets — tests must use `findsAtLeastNWidgets(1)` / `findsWidgets`, not `findsOneWidget`.

**Chevron placement when expanded and `120 < h ≤ 320`:** Put `expand_less` in a **bottom overlay** strip (same 32px hit strip; light fade optional). Do not insert a separate row below content beyond the strip.

**Chevron disambiguation (edit/shell):** Header already shows `Icons.expand_more`. Body fade strip adds another. Tests **must** target the body icon via `find.descendant(of: find.byType(AiFadeExpandBody), matching: find.byIcon(Icons.expand_more))` (or a `ValueKey('ai-fade-expand-chevron')` on the fade hit icon). Never bare `find.byIcon(Icons.expand_more)` after migration.

---

### Task 1: `AiFadeExpandBody` + constants (TDD)

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/parts/fade_expand_body.dart`
- Create: `client/packages/ai_message_ui/test/fade_expand_body_test.dart`
- Modify: `client/packages/ai_message_ui/lib/src/parts/expandable_tool_card.dart` (alias expanded height)
- Modify: `client/packages/ai_message_ui/lib/ai_message_ui.dart` (export)

- [ ] **Step 1: Write failing tests**

```dart
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('short child: no expand_more', (tester) async {
    await tester.pumpWidget(_wrap(
      AiFadeExpandBody(
        open: false,
        onToggle: () {},
        fadeColor: Colors.grey,
        child: const SizedBox(height: 40, child: Text('short')),
      ),
    ));
    await tester.pump(); // measure
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });

  testWidgets('overflow collapsed: expand_more; tap toggles once', (tester) async {
    var toggles = 0;
    await tester.pumpWidget(_wrap(
      AiFadeExpandBody(
        open: false,
        onToggle: () => toggles++,
        fadeColor: Colors.grey,
        child: const SizedBox(height: 200, child: Text('tall')),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-fade-expand-chevron')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-fade-expand-chevron')));
    await tester.pump();
    expect(toggles, 1);
  });

  testWidgets('overflow expanded mid-height: expand_less present; no scroll viewport', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(
      AiFadeExpandBody(
        open: true,
        onToggle: () {},
        fadeColor: Colors.grey,
        child: const SizedBox(height: 200, child: Text('mid')),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-fade-expand-chevron')), findsOneWidget);
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('overflow expanded tall: scrolls under 320 and shows expand_less', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(
      SizedBox(
        width: 300,
        child: AiFadeExpandBody(
          open: true,
          onToggle: () {},
          fadeColor: Colors.grey,
          child: const SizedBox(height: 500, child: Text('very-tall')),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final box = tester.renderObject<RenderBox>(find.byType(AiFadeExpandBody));
    expect(box.size.height, lessThanOrEqualTo(kAiFadeExpandExpandedMaxHeight + 1));
  });

  testWidgets('opaque chevron does not also fire parent card tap', (tester) async {
    var bodyToggles = 0;
    var cardToggles = 0;
    await tester.pumpWidget(_wrap(
      AiExpandableToolCard(
        open: false,
        onToggle: () => cardToggles++,
        child: AiFadeExpandBody(
          open: false,
          onToggle: () => bodyToggles++,
          fadeColor: Colors.grey,
          child: const SizedBox(height: 200, child: Text('inside-card')),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-fade-expand-chevron')));
    await tester.pump();
    expect(bodyToggles, 1);
    expect(cardToggles, 0); // opaque child absorbs
  });

  testWidgets('collapsed host height stays at collapsed max, not full child', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(
      AiFadeExpandBody(
        open: false,
        onToggle: () {},
        fadeColor: Colors.grey,
        child: const SizedBox(height: 400, child: Text('probe-size')),
      ),
    ));
    await tester.pump();
    final box = tester.renderObject<RenderBox>(find.byType(AiFadeExpandBody));
    expect(box.size.height, closeTo(kAiFadeExpandCollapsedMaxHeight, 1));
  });
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));
```

- [ ] **Step 2: Run tests — expect FAIL**

Run:

```bash
cd client/packages/ai_message_ui && flutter test test/fade_expand_body_test.dart
```

Expected: compilation failure / missing `AiFadeExpandBody`.

- [ ] **Step 3: Implement `fade_expand_body.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

const kAiFadeExpandCollapsedMaxHeight = 120.0;
const kAiFadeExpandExpandedMaxHeight = 320.0;
const kAiFadeExpandHitStripHeight = 32.0;

class AiFadeExpandBody extends StatefulWidget {
  const AiFadeExpandBody({
    required this.open,
    required this.onToggle,
    required this.fadeColor,
    required this.child,
    this.collapsedMaxHeight = kAiFadeExpandCollapsedMaxHeight,
    this.expandedMaxHeight = kAiFadeExpandExpandedMaxHeight,
    super.key,
  });

  final bool open;
  final VoidCallback onToggle;
  final Color fadeColor;
  final Widget child;
  final double collapsedMaxHeight;
  final double expandedMaxHeight;

  @override
  State<AiFadeExpandBody> createState() => _AiFadeExpandBodyState();
}

class _AiFadeExpandBodyState extends State<AiFadeExpandBody> {
  double? _childHeight;

  void _onMeasured(Size size) {
    if (_childHeight == size.height) return;
    setState(() => _childHeight = size.height);
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final measured = _childHeight;
    final overflows = measured != null && measured > widget.collapsedMaxHeight;

    // Clip-until-measured: avoid one-frame full flash.
    // Probe must NOT inflate Stack size (see File map measurement strategy A).
    Widget probe(double maxWidth) => Positioned(
          left: 0,
          top: 0,
          width: maxWidth,
          height: 0,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: maxWidth,
            maxWidth: maxWidth,
            minHeight: 0,
            maxHeight: double.infinity,
            child: _ReportSize(onSize: _onMeasured, child: child),
          ),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        if (measured == null) {
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              probe(maxW),
              SizedBox(
                height: widget.collapsedMaxHeight,
                width: double.infinity,
                child: ClipRect(
                  child: Align(alignment: Alignment.topLeft, child: child),
                ),
              ),
            ],
          );
        }

        if (!overflows) {
          return Stack(
            children: [
              probe(maxW),
              child,
            ],
          );
        }

        if (!widget.open) {
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              probe(maxW),
              SizedBox(
                height: widget.collapsedMaxHeight,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRect(
                      child: Align(alignment: Alignment.topLeft, child: child),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _FadeChevronHit(
                        fadeColor: widget.fadeColor,
                        icon: Icons.expand_more,
                        onTap: widget.onToggle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final needsScroll = measured > widget.expandedMaxHeight;
        Widget body = child;
        if (needsScroll) {
          body = ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.expandedMaxHeight),
            child: SingleChildScrollView(child: child),
          );
        }

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            probe(maxW),
            body,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _FadeChevronHit(
                fadeColor: widget.fadeColor,
                icon: Icons.expand_less,
                onTap: widget.onToggle,
                showFade: needsScroll,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FadeChevronHit extends StatelessWidget {
  const _FadeChevronHit({
    required this.fadeColor,
    required this.icon,
    required this.onTap,
    this.showFade = true,
  });

  final Color fadeColor;
  final IconData icon;
  final VoidCallback onTap;
  final bool showFade;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: kAiFadeExpandHitStripHeight,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (showFade)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      fadeColor.withValues(alpha: 0),
                      fadeColor,
                    ],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            Icon(
              icon,
              key: const ValueKey('ai-fade-expand-chevron'),
              size: 18,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportSize extends SingleChildRenderObjectWidget {
  const _ReportSize({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportSize(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderReportSize renderObject) {
    renderObject.onSize = onSize;
  }
}

class _RenderReportSize extends RenderProxyBox {
  _RenderReportSize(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(
      BoxConstraints(maxWidth: constraints.maxWidth),
      parentUsesSize: true,
    );
    size = child.size;
    if (_last != size) {
      _last = size;
      WidgetsBinding.instance.addPostFrameCallback((_) => onSize(size));
    }
  }
}
```

In `expandable_tool_card.dart`, change expanded constant to alias:

```dart
import 'fade_expand_body.dart';

const kAiToolCardPreviewLines = 5;
const kAiToolCardExpandedMaxHeight = kAiFadeExpandExpandedMaxHeight;
```

Export from `ai_message_ui.dart`:

```dart
export 'src/parts/fade_expand_body.dart';
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client/packages/ai_message_ui && flutter test test/fade_expand_body_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/parts/fade_expand_body.dart \
  client/packages/ai_message_ui/lib/src/parts/expandable_tool_card.dart \
  client/packages/ai_message_ui/lib/ai_message_ui.dart \
  client/packages/ai_message_ui/test/fade_expand_body_test.dart
git commit -m "$(cat <<'EOF'
feat(ai_message_ui): add AiFadeExpandBody shared fade-expand shell

EOF
)"
```

---

### Task 2: Wire user bubble

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/ai_message_view.dart` (`_UserBubble`)
- Create: `client/packages/ai_message_ui/test/user_bubble_fade_expand_test.dart`

- [ ] **Step 1: Failing integration tests**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _lines(int n) => List.generate(n, (i) => 'line-$i').join('\n');

void main() {
  testWidgets('short user bubble has no expand_more', (tester) async {
    await tester.pumpWidget(_app(AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: const [AiTextPart(text: 'hi')],
    )));
    await tester.pump();
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });

  testWidgets('tall user bubble expands and collapses via chevron', (tester) async {
    await tester.pumpWidget(_app(AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: [AiTextPart(text: _lines(40))],
    )));
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-fade-expand-chevron')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-fade-expand-chevron')));
    await tester.pump();
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-fade-expand-chevron')));
    await tester.pump();
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
  });

  testWidgets('message text change resets to collapsed', (tester) async {
    final msg1 = AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: [AiTextPart(text: _lines(40))],
    );
    await tester.pumpWidget(_app(msg1));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-fade-expand-chevron')));
    await tester.pump();
    expect(find.byIcon(Icons.expand_less), findsOneWidget);

    final msg2 = AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: [AiTextPart(text: '${_lines(40)}\nextra')],
    );
    await tester.pumpWidget(_app(msg2));
    await tester.pump();
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
  });
}

Widget _app(AiMessage message) => MaterialApp(
  home: Scaffold(body: AiMessageView(message: message)),
);
```

- [ ] **Step 2: Run — expect FAIL** (no chevron on tall bubble)

```bash
cd client/packages/ai_message_ui && flutter test test/user_bubble_fade_expand_test.dart
```

- [ ] **Step 3: Implement host + wrap in `_UserBubble`**

Convert the bubble body to a small stateful host (keep `_UserBubble` API or replace internals):

```dart
// Inside _UserBubble build, where `Flexible(child: parts)` is today:
Flexible(
  child: _UserBubbleFadeHost(
    messageId: message.id,
    textSignature: message.parts
        .whereType<AiTextPart>()
        .map((p) => p.text)
        .join('\u0000'),
    fadeColor: aiTheme.resolveUserBubble(scheme),
    child: parts,
  ),
),
```

```dart
class _UserBubbleFadeHost extends StatefulWidget {
  const _UserBubbleFadeHost({
    required this.messageId,
    required this.textSignature,
    required this.fadeColor,
    required this.child,
  });

  final String messageId;
  final String textSignature;
  final Color fadeColor;
  final Widget child;

  @override
  State<_UserBubbleFadeHost> createState() => _UserBubbleFadeHostState();
}

class _UserBubbleFadeHostState extends State<_UserBubbleFadeHost> {
  var _open = false;

  @override
  void didUpdateWidget(covariant _UserBubbleFadeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageId != widget.messageId ||
        oldWidget.textSignature != widget.textSignature) {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AiFadeExpandBody(
      open: _open,
      onToggle: () => setState(() => _open = !_open),
      fadeColor: widget.fadeColor,
      child: widget.child,
    );
  }
}
```

Import `parts/fade_expand_body.dart` from `ai_message_view.dart`.

- [ ] **Step 4: Run — expect PASS**

```bash
cd client/packages/ai_message_ui && flutter test test/user_bubble_fade_expand_test.dart test/user_bubble_mailbox_marker_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/ai_message_view.dart \
  client/packages/ai_message_ui/test/user_bubble_fade_expand_test.dart
git commit -m "$(cat <<'EOF'
feat(ai_message_ui): fade-expand long History user bubbles

EOF
)"
```

---

### Task 3: Migrate edit tool card body

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/edit/edit_tool_card.dart`
- Modify: `client/packages/ai_message_ui/test/tool_call_edit_target_test.dart`

- [ ] **Step 1: Extend / adjust edit tests**

1. Replace any “only first 5 lines mounted” assertions with full-mount checks: `expect(find.textContaining('late-line'), findsAtLeastNWidgets(1))` (probe may duplicate).
2. Tap body fade chevron via `find.descendant(of: find.byType(AiFadeExpandBody), matching: find.byKey(const ValueKey('ai-fade-expand-chevron')))` — **not** bare `find.byIcon(Icons.expand_more)` (header chevron also uses that icon). Expect `onToggle` +1 once.
3. Basename tap still opens file and does not toggle (existing).
4. Update any existing `tester.tap(find.byIcon(Icons.expand_more))` in this file to the descendant/key finder above.

- [ ] **Step 2: Run relevant edit tests — note failures**

```bash
cd client/packages/ai_message_ui && flutter test test/tool_call_edit_target_test.dart
```

- [ ] **Step 3: Migrate `_EditDiffPanel` / `EditToolCard`**

In `EditToolCard.build`:

```dart
// was: final visibleLines = open ? hunk.lines : previewEditHunkLines(hunk.lines);
final visibleLines = hunk.lines;
```

In `_EditDiffPanel.build`:

- Remove the `if (open && hunk.lines.length > kAiToolCardPreviewLines) { ConstrainedBox...}` block.
- Wrap `lineList` (after building the Column of lines) with:

```dart
lineList = AiFadeExpandBody(
  open: open,
  onToggle: onToggle, // thread onToggle into _EditDiffPanel from EditToolCard / Host
  fadeColor: panelColor,
  child: lineList,
);
```

Thread `onToggle` from `EditToolCardHost` → `EditToolCard` → `_EditDiffPanel`. Host already has `onToggle` for `AiExpandableToolCard`; pass the same callback into the presentational card.

Keep header chevron visual; do not remove unless tests require it.

`previewEditHunkLines` may remain in file for unit tests of preference logic until unused — if nothing calls it, delete in a follow-up within this task or leave with a short comment. Prefer **delete callers only**; keep helper if edit tests still unit-test it.

- [ ] **Step 4: Run edit tests — PASS**

```bash
cd client/packages/ai_message_ui && flutter test test/tool_call_edit_target_test.dart test/fade_expand_body_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/edit/edit_tool_card.dart \
  client/packages/ai_message_ui/test/tool_call_edit_target_test.dart
git commit -m "$(cat <<'EOF'
feat(ai_message_ui): use AiFadeExpandBody on edit tool card body

EOF
)"
```

---

### Task 4: Migrate shell tool card body

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/shell/shell_tool_card.dart`
- Modify: `client/packages/ai_message_ui/test/tool_call_shell_target_test.dart`

- [ ] **Step 1: Update shell tests**

1. Replace 5-line preview assertions: late output line → `findsAtLeastNWidgets(1)`.
2. Body fade chevron: same descendant/`ValueKey('ai-fade-expand-chevron')` finder as Task 3; expect single toggle (card counter unchanged when tapping body chevron).
3. Update any bare `find.byIcon(Icons.expand_more)` taps in this file.
4. Whole-card tap still toggles (existing).
5. Expanded body selectable / collapsed disabled (existing selection tests if any).

- [ ] **Step 2: Run shell tests — note failures**

```bash
cd client/packages/ai_message_ui && flutter test test/tool_call_shell_target_test.dart
```

- [ ] **Step 3: Migrate `_ShellTerminalBody`**

```dart
// Always full output:
final output = hasOutput ? rawOutput! : null;

// Remove ConstrainedBox(maxHeight: kAiToolCardExpandedMaxHeight) branch.

// Wrap the inner Column (command + output) with:
AiFadeExpandBody(
  open: open,
  onToggle: onToggle, // thread from ShellToolCardHost
  fadeColor: panelColor,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text.rich(...), // $ command
      if (output != null) ...[
        const SizedBox(height: 8),
        Text(output, style: ...),
      ],
    ],
  ),
)
```

Thread `onToggle` through `ShellToolCard` → `_ShellTerminalBody`. Keep collapsed `SelectionContainer.disabled` wrapping as today.

Stop calling `previewToolCardText` from this path.

- [ ] **Step 4: Run shell + edit + fade tests — PASS**

```bash
cd client/packages/ai_message_ui && flutter test \
  test/tool_call_shell_target_test.dart \
  test/tool_call_edit_target_test.dart \
  test/fade_expand_body_test.dart \
  test/user_bubble_fade_expand_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/shell/shell_tool_card.dart \
  client/packages/ai_message_ui/test/tool_call_shell_target_test.dart
git commit -m "$(cat <<'EOF'
feat(ai_message_ui): use AiFadeExpandBody on shell tool card body

EOF
)"
```

---

### Task 5: Package verification + cleanup

**Files:**
- Possibly delete unused `previewEditHunkLines` call sites only (already done); keep `previewToolCardText` if `expandable_tool_card_test.dart` still covers it
- No app-host changes required (package-local)

- [ ] **Step 1: Full package test**

```bash
cd client/packages/ai_message_ui && flutter test
```

Expected: all PASS.

- [ ] **Step 2: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings packages/ai_message_ui
```

Expected: no new errors in touched files.

- [ ] **Step 3: Commit only if cleanup diffs exist**

```bash
git add -u client/packages/ai_message_ui
git commit -m "$(cat <<'EOF'
chore(ai_message_ui): cleanup after fade-expand migration

EOF
)"
```

Skip empty commit if nothing to stage.

---

## Done when

- [ ] `AiFadeExpandBody` exported; constants 120 / 320 / 32 locked
- [ ] Long user bubbles fade + expand/collapse; short unchanged
- [ ] Edit/shell bodies use full content + shared shell; no nested 320 viewport
- [ ] Fade chevron opaque (no double toggle with whole-card tap)
- [ ] Package tests green
