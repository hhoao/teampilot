# Fade Expand contentPadding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make collapsed fade/chevron masks flush to left/right/bottom edges of every `AiFadeExpandBody` surface while keeping content inset via `contentPadding`.

**Architecture:** Invert padding ownership inside `AiFadeExpandBody`: pad only the clip/scroll body; keep the fade strip `Positioned` at host edges. Call sites remove outer `Padding` and pass the same insets as `contentPadding`. User bubble and shell wrap with `ClipRRect` so the flush strip respects rounded corners (edit card already does).

**Tech Stack:** Flutter / Dart (`ai_message_ui` package), `flutter_test`

**Spec:** `docs/superpowers/specs/2026-08-04-fade-expand-content-padding-design.md`

---

## File map

| File | Role |
|------|------|
| `client/packages/ai_message_ui/lib/src/parts/fade_expand_body.dart` | Add `contentPadding`; wrap clip/scroll body in `Padding` before `_BlockBottomHits` / `Stack` |
| `client/packages/ai_message_ui/test/fade_expand_body_test.dart` | Geometry + padded collapse height tests |
| `client/packages/ai_message_ui/lib/src/ai_message_view.dart` | User bubble: drop outer padding; fade host owns full bubble content + `contentPadding` |
| `client/packages/ai_message_ui/lib/src/shell/shell_tool_card.dart` | Shell panel: `contentPadding: EdgeInsets.all(10)` |
| `client/packages/ai_message_ui/lib/src/edit/edit_tool_card.dart` | No change (already edge-flush, default padding) |

---

### Task 1: Failing tests for contentPadding geometry

**Files:**
- Modify: `client/packages/ai_message_ui/test/fade_expand_body_test.dart`

- [ ] **Step 1: Add flush-strip + padded-host-height tests**

Append to `fade_expand_body_test.dart`:

```dart
  testWidgets(
    'contentPadding: fade strip flush to host left/right/bottom',
    (tester) async {
      const pad = EdgeInsets.symmetric(horizontal: 16, vertical: 10);
      await tester.pumpWidget(_wrap(
        AiFadeExpandBody(
          open: false,
          onToggle: () {},
          fadeColor: Colors.grey,
          contentPadding: pad,
          child: const SizedBox(height: 200, child: Text('tall')),
        ),
      ));
      await tester.pump();

      final hostBox =
          tester.renderObject<RenderBox>(find.byType(AiFadeExpandBody));
      final hostOrigin = hostBox.localToGlobal(Offset.zero);

      final stripFinder = find.descendant(
        of: find.byType(AiFadeExpandBody),
        matching: find.byWidgetPredicate(
          (w) =>
              w is SizedBox &&
              w.height == kAiFadeExpandHitStripHeight &&
              w.width == double.infinity,
        ),
      );
      expect(stripFinder, findsOneWidget);
      final stripBox = tester.renderObject<RenderBox>(stripFinder);
      final stripOrigin = stripBox.localToGlobal(Offset.zero);

      expect(stripOrigin.dx, closeTo(hostOrigin.dx, 0.5));
      expect(stripBox.size.width, closeTo(hostBox.size.width, 0.5));
      expect(
        stripOrigin.dy + stripBox.size.height,
        closeTo(hostOrigin.dy + hostBox.size.height, 0.5),
      );
    },
  );

  testWidgets(
    'contentPadding + collapsed overflow: host height includes padding',
    (tester) async {
      const pad = EdgeInsets.all(10);
      await tester.pumpWidget(_wrap(
        AiFadeExpandBody(
          open: false,
          onToggle: () {},
          fadeColor: Colors.grey,
          contentPadding: pad,
          child: const SizedBox(height: 400, child: Text('tall')),
        ),
      ));
      await tester.pump();

      final box =
          tester.renderObject<RenderBox>(find.byType(AiFadeExpandBody));
      expect(
        box.size.height,
        closeTo(
          kAiFadeExpandCollapsedMaxHeight + pad.vertical,
          1,
        ),
      );
    },
  );
```

- [ ] **Step 2: Run tests — expect RED**

Run:

```bash
cd client/packages/ai_message_ui && flutter test test/fade_expand_body_test.dart
```

Expected: compile error (`contentPadding` not defined) and/or failing geometry asserts (strip still inset / host height still ~120).

- [ ] **Step 3: Commit failing tests**

```bash
git add client/packages/ai_message_ui/test/fade_expand_body_test.dart
git commit -m "$(cat <<'EOF'
test(ai_message_ui): assert fade strip flush with contentPadding

EOF
)"
```

---

### Task 2: Implement contentPadding on AiFadeExpandBody

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/parts/fade_expand_body.dart`

- [ ] **Step 1: Add API field**

On `AiFadeExpandBody`:

```dart
  const AiFadeExpandBody({
    required this.open,
    required this.onToggle,
    required this.fadeColor,
    required this.child,
    this.collapsedMaxHeight = kAiFadeExpandCollapsedMaxHeight,
    this.expandedMaxHeight = kAiFadeExpandExpandedMaxHeight,
    this.forceChrome = false,
    this.contentPadding = EdgeInsets.zero,
    super.key,
  });

  // ...
  final EdgeInsetsGeometry contentPadding;
```

In `didUpdateWidget`, also rebuild when `contentPadding` changes:

```dart
    if (oldWidget.open != widget.open ||
        oldWidget.forceChrome != widget.forceChrome ||
        oldWidget.collapsedMaxHeight != widget.collapsedMaxHeight ||
        oldWidget.expandedMaxHeight != widget.expandedMaxHeight ||
        oldWidget.contentPadding != widget.contentPadding) {
```

- [ ] **Step 2: Apply padding outside clip/scroll, inside hit-block + Stack**

In `_AiFadeExpandBodyState.build`, after constructing open/closed `body` and **before** `_BlockBottomHits`:

```dart
    final pad = widget.contentPadding;
    if (pad != EdgeInsets.zero) {
      body = Padding(padding: pad, child: body);
    }

    // Keep body text under the fade strip out of hit-testing / selection.
    if (overflows) {
      body = _BlockBottomHits(
        blockedHeight: kAiFadeExpandHitStripHeight,
        child: body,
      );
    }

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        body,
        if (overflows)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SelectionDeadZone(
              child: _FadeChevronHit(
                fadeColor: widget.fadeColor,
                icon: widget.open ? Icons.expand_less : Icons.expand_more,
                onTap: widget.onToggle,
                showFade: !widget.open || needsScroll,
              ),
            ),
          ),
      ],
    );
```

Notes:

- `collapsedMaxHeight` / `expandedMaxHeight` still apply only to the **inner** clip/scroll child (unchanged constructors).
- Host outer height becomes `maxHeight + contentPadding.vertical` when overflowing.
- Fade stays `Positioned(left/right/bottom: 0)` on the Stack → flush to host edges.
- `_BlockBottomHits` wraps the **padded** body so the dead zone matches the flush strip.

- [ ] **Step 3: Run fade_expand_body tests — expect GREEN**

```bash
cd client/packages/ai_message_ui && flutter test test/fade_expand_body_test.dart
```

Expected: all tests PASS (including existing collapse/expand/selection/hover).

- [ ] **Step 4: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/parts/fade_expand_body.dart \
  client/packages/ai_message_ui/test/fade_expand_body_test.dart
git commit -m "$(cat <<'EOF'
feat(ai_message_ui): edge-flush fade via contentPadding

EOF
)"
```

---

### Task 3: User bubble call site

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/ai_message_view.dart`

- [ ] **Step 1: Restructure `_UserBubble` surface**

Inside the existing `Flexible` → `ConstrainedBox(maxWidth: bubbleMax)`, replace only the `DecoratedBox` + outer `Padding` layer (keep the outer `Row` / action bar unchanged) with:

```dart
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(aiTheme.userBubbleRadius),
                    child: ColoredBox(
                      color: aiTheme.resolveUserBubble(scheme),
                      child: _UserBubbleFadeHost(
                        messageId: message.id,
                        textSignature: message.parts
                            .whereType<AiTextPart>()
                            .map((p) => p.text)
                            .join('\u0000'),
                        fadeColor: aiTheme.resolveUserBubble(scheme),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: DefaultTextStyle.merge(
                          style: aiTheme.markdown.userBubble(
                            aiTheme.resolveUserForeground(scheme),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (message.deliveryChannel == 'mailbox')
                                Padding(
                                  padding:
                                      const EdgeInsets.only(right: 6, top: 2),
                                  child: Icon(
                                    Icons.mail_outline,
                                    key: const ValueKey(
                                      'ai-user-bubble-mailbox-marker',
                                    ),
                                    size: 13,
                                    color: aiTheme
                                        .resolveUserForeground(scheme),
                                  ),
                                ),
                              Flexible(child: parts),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
```

Remove the old outer `Padding` and the inner `Flexible` wrapping only the fade host. `ClipRRect` keeps the flush mask inside the rounded corners.

- [ ] **Step 2: Thread `contentPadding` through `_UserBubbleFadeHost`**

```dart
class _UserBubbleFadeHost extends StatefulWidget {
  const _UserBubbleFadeHost({
    required this.messageId,
    required this.textSignature,
    required this.fadeColor,
    required this.contentPadding,
    required this.child,
  });

  final String messageId;
  final String textSignature;
  final Color fadeColor;
  final EdgeInsetsGeometry contentPadding;
  final Widget child;
  // ...
}

  @override
  Widget build(BuildContext context) {
    return AiFadeExpandBody(
      open: _open,
      onToggle: () => setState(() => _open = !_open),
      fadeColor: widget.fadeColor,
      contentPadding: widget.contentPadding,
      child: widget.child,
    );
  }
```

- [ ] **Step 3: Regression tests**

```bash
cd client/packages/ai_message_ui && flutter test \
  test/user_bubble_fade_expand_test.dart \
  test/user_bubble_mailbox_marker_test.dart
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/ai_message_view.dart
git commit -m "$(cat <<'EOF'
fix(ai_message_ui): flush user-bubble fade to rounded edges

EOF
)"
```

---

### Task 4: Shell tool card call site

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/shell/shell_tool_card.dart`

- [ ] **Step 1: Move padding into AiFadeExpandBody + ClipRRect**

Change the body construction and return:

```dart
    final body = AiFadeExpandBody(
      open: open,
      onToggle: onToggle,
      fadeColor: panelColor,
      contentPadding: const EdgeInsets.all(10),
      child: Column(
        // ... unchanged command/output children ...
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: panelColor,
        child: body,
      ),
    );
```

Remove the previous `DecoratedBox` + outer `Padding(all: 10)` wrapper.

- [ ] **Step 2: Regression tests**

```bash
cd client/packages/ai_message_ui && flutter test \
  test/tool_call_shell_target_test.dart \
  test/tool_call_edit_target_test.dart \
  test/edit_tool_card_style_fingerprint_test.dart
```

Expected: PASS (edit unchanged).

- [ ] **Step 3: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/shell/shell_tool_card.dart
git commit -m "$(cat <<'EOF'
fix(ai_message_ui): flush shell-card fade via contentPadding

EOF
)"
```

---

### Task 5: Package verification

- [ ] **Step 1: Run full ai_message_ui test suite**

```bash
cd client/packages/ai_message_ui && flutter test
```

Expected: all PASS.

- [ ] **Step 2: Analyze package**

```bash
cd client/packages/ai_message_ui && dart analyze --fatal-infos
```

Expected: no issues (or only pre-existing infos if analyzer flags differ — do not introduce new ones).

- [ ] **Step 3: Manual acceptance checklist** (if UI available)

- Tall collapsed user bubble: gradient flush to bottom + sides; text still 16×10 inset; chevron works.
- Shell card: same flush with 10px content inset.
- Edit card: unchanged visual.

---

## Execution notes

- @superpowers:test-driven-development — Task 1 RED before Task 2 GREEN.
- Do not change edit card unless a regression forces a one-line `contentPadding: EdgeInsets.zero` (YAGNI).
- Prefer `ColoredBox` + `ClipRRect` over `DecoratedBox` when the only decoration is solid color + radius (matches edit card).
