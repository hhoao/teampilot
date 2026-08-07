# Chat & Markdown Flatten Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reusable natural-height block-virtualized markdown view (`FlattenMarkdownView` = `VirtualMarkdownView(flatten: true)`) and a per-surface `ContentDisplayMode` (fold-fixed-height / fold-expand-full / flatten) for chat user messages, code blocks, and the markdown file preview — defaulting to today's behavior.

**Architecture:** A block-level virtualizer reads the **parent** scroll (via `Scrollable.maybeOf` + `RenderAbstractViewport.getOffsetToReveal`) instead of owning a scrollbar, renders `Column([paddingTop, visibleBlocks, paddingBottom])` at natural height, and reuses the existing height-cache/measurement logic. A `MarkdownDisplayModeScope` inherited widget carries `userMessageMode` + `codeBlockMode`; `_MarkdownCodeBlock` and `_ExpandableHistoryMarkdown` honor them.

**Tech Stack:** Flutter, Dart, packages `tp_markdown` + `ai_message_ui` (both inside the main `teampilot` repo — edit directly), app code under `client/lib`.

## Global Constraints

- **Zero regression by default:** all `ContentDisplayMode` defaults are `foldFixedHeight` — today's rendering. Every existing test must stay green.
- **Layering:** `tp_markdown` must not import `ai_message_ui` (block renderers live in tp_markdown). The shared `ContentDisplayMode`/scope live in tp_markdown.
- **Analyze:** repo `flutter analyze --no-fatal-infos --no-fatal-warnings` excludes `packages/**`. For package files use per-file analyze: `flutter analyze <path>`, and run package tests with `flutter test <path>` from `client/`.
- **Test command prefix:** all `flutter test`/`flutter analyze` run from `/home/hhoa/git/hhoa/teampilot/client`.

---
### Task 1: `ContentDisplayMode` + `MarkdownDisplayModeScope` (tp_markdown)

**Files:**
- Create: `client/packages/tp_markdown/lib/src/markdown_display_mode_scope.dart`
- Modify: `client/packages/tp_markdown/lib/tp_markdown.dart` (add export)
- Test: `client/packages/tp_markdown/test/markdown_display_mode_scope_test.dart`

**Interfaces:**
- Produces: `enum ContentDisplayMode { foldFixedHeight, foldExpandFull, flatten }`; `class MarkdownDisplayModeScope extends InheritedWidget` with `userMessageMode` + `codeBlockMode`; `static ContentDisplayMode MarkdownDisplayModeScope.userMessageOf(context)`; `static ContentDisplayMode MarkdownDisplayModeScope.codeBlockOf(context)`; `static MarkdownDisplayModeScope? MarkdownDisplayModeScope.maybeOf(context)`.

- [ ] **Step 1: Write the failing test**

Create `client/packages/tp_markdown/test/markdown_display_mode_scope_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  testWidgets('scope defaults are foldFixedHeight and propagate modes', (tester) async {
    String? readUser;
    String? readCode;
    await tester.pumpWidget(
      MaterialApp(
        home: MarkdownDisplayModeScope(
          userMessageMode: ContentDisplayMode.flatten,
          codeBlockMode: ContentDisplayMode.foldExpandFull,
          child: Builder(
            builder: (context) {
              readUser = MarkdownDisplayModeScope.userMessageOf(context).name;
              readCode = MarkdownDisplayModeScope.codeBlockOf(context).name;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(readUser, 'flatten');
    expect(readCode, 'foldExpandFull');
  });

  testWidgets('absent scope falls back to foldFixedHeight', (tester) async {
    String? user;
    String? code;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            user = MarkdownDisplayModeScope.userMessageOf(context).name;
            code = MarkdownDisplayModeScope.codeBlockOf(context).name;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(user, 'foldFixedHeight');
    expect(code, 'foldFixedHeight');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test packages/tp_markdown/test/markdown_display_mode_scope_test.dart`
Expected: FAIL — `MarkdownDisplayModeScope` undefined.

- [ ] **Step 3: Write the implementation**

Create `client/packages/tp_markdown/lib/src/markdown_display_mode_scope.dart`:

```dart
import 'package:flutter/widgets.dart';

/// How oversized content renders inside the parent scroll.
enum ContentDisplayMode {
  /// Collapse to a mask; expand into a fixed-height scroll shell (today).
  foldFixedHeight,
  /// Collapse to a mask; expand to full natural height in the flow.
  foldExpandFull,
  /// Always full natural height in the flow (no mask).
  flatten,
}

/// Carries per-surface display modes down to markdown renderers.
class MarkdownDisplayModeScope extends InheritedWidget {
  const MarkdownDisplayModeScope({
    super.key,
    this.userMessageMode = ContentDisplayMode.foldFixedHeight,
    this.codeBlockMode = ContentDisplayMode.foldFixedHeight,
    required super.child,
  });

  final ContentDisplayMode userMessageMode;
  final ContentDisplayMode codeBlockMode;

  static MarkdownDisplayModeScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<MarkdownDisplayModeScope>();
  }

  static ContentDisplayMode userMessageOf(BuildContext context) =>
      maybeOf(context)?.userMessageMode ?? ContentDisplayMode.foldFixedHeight;

  static ContentDisplayMode codeBlockOf(BuildContext context) =>
      maybeOf(context)?.codeBlockMode ?? ContentDisplayMode.foldFixedHeight;

  @override
  bool updateShouldNotify(MarkdownDisplayModeScope oldWidget) =>
      userMessageMode != oldWidget.userMessageMode ||
      codeBlockMode != oldWidget.codeBlockMode;
}
```

Add to `client/packages/tp_markdown/lib/tp_markdown.dart`:

```dart
export 'src/markdown_display_mode_scope.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test packages/tp_markdown/test/markdown_display_mode_scope_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/packages/tp_markdown/lib/src/markdown_display_mode_scope.dart client/packages/tp_markdown/lib/tp_markdown.dart client/packages/tp_markdown/test/markdown_display_mode_scope_test.dart
git commit -m "feat(markdown): ContentDisplayMode + MarkdownDisplayModeScope"
```

---
### Task 2: `VirtualMarkdownView` flatten mode (tp_markdown) — the core capability

**Files:**
- Modify: `client/packages/tp_markdown/lib/src/render/virtual_markdown_view.dart`
- Test: `client/packages/tp_markdown/test/virtual_markdown_view_test.dart` (append)

**Interfaces:**
- Consumes: `MarkdownDisplayModeScope` is NOT needed here.
- Produces: `VirtualMarkdownView` gains `final bool flatten` (default `false`). When `flatten: true`, it renders at natural height inside the **parent** scroll (no own `SingleChildScrollView`, no `maxHeight`), reading the parent position + its own viewport offset, and mounting only visible blocks.

**Existing structure to extend** (do not rewrite wholesale): `initState` (creates `_scrollController`, computes `_units`, `_syncVisibleRange`, post-frame `_syncVisibleRange`), `_onScroll`, `_syncVisibleRange` (uses `_scrollController`), `_onUnitMeasured`, `_scheduleCorrection`, `build` (wraps the Column in `ConstrainedBox(maxHeight) + SingleChildScrollView(controller)`).

- [ ] **Step 1: Write the failing test (append to `virtual_markdown_view_test.dart`)**

```dart
  testWidgets('flatten renders natural height and only mounts visible blocks', (
    tester,
  ) async {
    // Parent scroll: the flatten view must size naturally and follow THIS scroll.
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: VirtualMarkdownView(
            document: _blockDoc(200),
            tokens: MarkdownTokens.test(),
            flatten: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Natural height: the view is as tall as all 200 blocks, not bounded.
    expect(tester.getSize(find.byType(VirtualMarkdownView)).height, greaterThan(1000));
    // Only visible blocks mounted; far tail not built.
    expect(_blockText('block-0'), findsOneWidget);
    expect(_blockText('block-190'), findsNothing);

    // Scrolling the PARENT reaches the tail.
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(_blockText('block-199'), findsOneWidget);
  });
```

Note: `_harness` currently wraps the child in `Align(topLeft)` inside a `SizedBox(400,300)`. For flatten, wrap the `VirtualMarkdownView` in a `SingleChildScrollView` (the flatten view scrolls WITH that). Add a `_blockDoc` helper if not present (alternating paragraph/heading as in the existing test).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test packages/tp_markdown/test/virtual_markdown_view_test.dart`
Expected: FAIL — the flatten view is bounded/never virtualizes by parent scroll.

- [ ] **Step 3: Implement flatten mode**

In `virtual_markdown_view.dart`:

Add widget fields + constructor params:

```dart
  final double maxHeight;
  final double estimateHeight;
  final int overscan;
  final bool flatten;

  // in constructor:
  this.flatten = false,
```

Add state fields and parent-scroll binding:

```dart
  ScrollPosition? _parentPosition;
  bool _layoutHandled = false;
```

Add a `didChangeDependencies` that binds to the parent scroll (also called when the Scrollable appears):

```dart
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindParentScroll();
  }

  void _bindParentScroll() {
    if (!widget.flatten) {
      if (_parentPosition != null) {
        _parentPosition!.removeListener(_onScroll);
        _parentPosition = null;
      }
      return;
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _parentPosition)) return;
    _parentPosition?.removeListener(_onScroll);
    _parentPosition = position;
    _parentPosition?.addListener(_onScroll);
  }
```

Change `_syncVisibleRange` to dispatch by mode:

```dart
  void _syncVisibleRange() {
    if (!mounted || _units.isEmpty) return;
    if (widget.flatten) {
      _syncFlattenRange();
      return;
    }
    // ...existing bounded logic unchanged...
  }

  void _syncFlattenRange() {
    final renderObject = context.findRenderObject();
    if (renderObject == null || !renderObject.hasSize) {
      final count = widget.overscan.clamp(1, _units.length);
      _applyRange(
        _BlockVisibleRange(
          firstIndex: 0,
          lastIndex: count - 1,
          paddingTop: 0,
          paddingBottom:
              _cache.totalExtent(_units.length) -
              _cache.offsetBefore(_units.length, count),
        ),
      );
      return;
    }
    final viewport = RenderAbstractViewport.of(renderObject);
    if (viewport == null) return;
    final pixels = _parentPosition?.pixels ?? 0.0;
    final revealed = viewport.getOffsetToReveal(renderObject, 0.0);
    final visibleTop = pixels - revealed.offset;
    final range = _cache.visibleRange(
      unitCount: _units.length,
      scrollPixels: visibleTop,
      viewportHeight: viewport.size.height,
      overscan: widget.overscan,
    );
    _applyRange(range);
  }
```

Update `initState` post-frame to re-sync after layout (so the flatten offset is valid) — the existing post-frame already calls `_syncVisibleRange()`; add a second one for flatten-layout settle:

```dart
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncVisibleRange();
      if (widget.flatten) {
        _layoutHandled = true;
        _syncVisibleRange();
      }
    });
```

Update `build` to skip the bounded wrapper in flatten mode (the Column content is shared):

```dart
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [ /* existing children unchanged */ ],
    );
    if (widget.flatten) {
      return MarkdownStringsScope(strings: strings, child: content);
    }
    return MarkdownStringsScope(
      strings: strings,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: SingleChildScrollView(
          controller: _scrollController,
          child: content,
        ),
      ),
    );
```

In `dispose`, remove the parent listener:

```dart
  @override
  void dispose() {
    _parentPosition?.removeListener(_onScroll);
    // ...existing dispose...
  }
```

Update `_onUnitMeasured`: in flatten mode, do not correct the parent scroll (the thread's turn machinery handles height shifts); only re-sync. Guard the correction path with `if (!widget.flatten && delta.abs() >= 0.5 && _scrollController.hasClients)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test packages/tp_markdown/test/virtual_markdown_view_test.dart`
Expected: PASS (existing 3 tests + new flatten test).

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/packages/tp_markdown/lib/src/render/virtual_markdown_view.dart client/packages/tp_markdown/test/virtual_markdown_view_test.dart
git commit -m "feat(markdown): VirtualMarkdownView flatten (natural-height) mode"
```

---
### Task 3: `_MarkdownCodeBlock` honors `codeBlockMode` (tp_markdown)

**Files:**
- Modify: `client/packages/tp_markdown/lib/src/render/table_code_hr_blocks.dart`
- Test: `client/packages/tp_markdown/test/markdown_view_heading_code_test.dart` (append)

**Interfaces:**
- Consumes: `MarkdownDisplayModeScope.codeBlockOf(context)` (Task 1).

- [ ] **Step 1: Write the failing tests (append to `markdown_view_heading_code_test.dart`)**

```dart
  testWidgets('foldExpandFull code expands to full natural height (no shell)', (
    tester,
  ) async {
    final code = List.generate(400, (i) => 'line $i ${'x' * 40}').join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: MarkdownDisplayModeScope(
          codeBlockMode: ContentDisplayMode.foldExpandFull,
          child: Scaffold(
            body: SingleChildScrollView(
              child: MarkdownView(
                document: MarkdownDocument(
                  blocks: [CodeBlock(language: 'dart', text: code)],
                ),
                tokens: MarkdownTokens.test(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Masked by default; expand chevron present, tail absent.
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(find.textContaining('line 399'), findsNothing);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();

    // Full natural height: the full code is mounted (no fixed shell).
    expect(find.textContaining('line 399'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget); // only the outer one
  });

  testWidgets('flatten code renders full natural height with no mask', (tester) async {
    final code = List.generate(400, (i) => 'line $i ${'x' * 40}').join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: MarkdownDisplayModeScope(
          codeBlockMode: ContentDisplayMode.flatten,
          child: Scaffold(
            body: SingleChildScrollView(
              child: MarkdownView(
                document: MarkdownDocument(
                  blocks: [CodeBlock(language: 'dart', text: code)],
                ),
                tokens: MarkdownTokens.test(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No mask chevron; full code mounted.
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    expect(find.textContaining('line 399'), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test packages/tp_markdown/test/markdown_view_heading_code_test.dart`
Expected: FAIL — no scope handling (always current mask behavior).

- [ ] **Step 3: Implement**

In `table_code_hr_blocks.dart`, in `_MarkdownCodeBlockState.build`, read the mode and branch:

```dart
  @override
  Widget build(BuildContext context) {
    final strings = MarkdownStrings.of(context);
    final muted = widget.tokens.mutedSurface;
    final radius = widget.tokens.codeBlockRadius;
    final borderColor = widget.tokens.borderColor;
    final lang = widget.language.isEmpty
        ? strings.code
        : widget.language.toLowerCase();
    final mode = MarkdownDisplayModeScope.codeBlockOf(context);
    final huge = widget.code.length > _kCollapseChars;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ...header DecoratedBox unchanged...
        if (!huge || mode == ContentDisplayMode.flatten)
          DecoratedBox(
            decoration: BoxDecoration(
              color: muted,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
              border: Border.all(color: borderColor),
            ),
            child: _codeText(widget.code),
          )
        else if (mode == ContentDisplayMode.foldExpandFull)
          _buildMaskedBody(context, strings, muted, radius, borderColor,
              expandFull: true)
        else
          _buildMaskedBody(context, strings, muted, radius, borderColor,
              expandFull: false),
      ],
    );
  }
```

Add the `expandFull` parameter to `_buildMaskedBody` and change the expanded render:

```dart
  Widget _buildMaskedBody(BuildContext context, MarkdownStrings strings,
      Color muted, double radius, Color borderColor,
      {required bool expandFull}) {
    final code = _expanded ? widget.code : widget.code.substring(0, _kPreviewChars);
    final iconColor =
        (widget.tokens.codeBlock.color ?? Colors.black54).withValues(alpha: 0.6);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: muted,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
        border: Border.all(color: borderColor),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: _expanded && !expandFull
                  ? _kExpandedMaxHeight
                  : _kCollapsedMaxHeight,
            ),
            child: (_expanded && !expandFull)
                ? SingleChildScrollView(child: _codeText(code))
                : _codeText(code),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _MaskFadeChevron(
              icon: _expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              tooltip: _expanded ? strings.showLess : strings.showMore,
              fadeColor: muted,
              iconColor: iconColor,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
          ),
        ],
      ),
    );
  }
```

Add the import to `table_code_hr_blocks.dart`: `import '../markdown_display_mode_scope.dart';`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test packages/tp_markdown/test/markdown_view_heading_code_test.dart`
Expected: PASS (existing mask test + 2 new mode tests). Also run the full package: `flutter test packages/tp_markdown/test/`.

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/packages/tp_markdown/lib/src/render/table_code_hr_blocks.dart client/packages/tp_markdown/test/markdown_view_heading_code_test.dart
git commit -m "feat(markdown): code block honors ContentDisplayMode (3 modes)"
```

---
### Task 4: Chat user-message path honors `userMessageMode` (ai_message_ui)

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/parts/text_part_view.dart`
- Test: `client/packages/ai_message_ui/test/history_render_perf_test.dart` (append)

**Interfaces:**
- Consumes: `MarkdownDisplayModeScope.userMessageOf(context)` (Task 1); `VirtualMarkdownView(flatten: true)` (Task 2).
- Produces: `_ExpandableHistoryMarkdown` renders the user message per mode: `foldFixedHeight` (bounded panel), `foldExpandFull` (mask → natural-height flatten), `flatten` (no mask, always flatten).

- [ ] **Step 1: Write the failing tests (append to `history_render_perf_test.dart`)**

```dart
  testWidgets('user message foldExpandFull expands to natural height (no bounded panel)', (
    tester,
  ) async {
    final message = AiMessage(
      id: 'u2',
      role: AiRole.user,
      parts: [AiTextPart(text: tableMarkdown(20))],
    );
    await tester.pumpWidget(
      wrap(
        MarkdownDisplayModeScope(
          userMessageMode: ContentDisplayMode.foldExpandFull,
          child: AiMessageView(message: message, showActionBar: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.expand_more), findsOneWidget); // masked first
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(find.text('c19-a'), findsOneWidget);
    // Natural height: no bounded VirtualMarkdownView panel.
    expect(find.byType(VirtualMarkdownView), findsNothing);
  });

  testWidgets('user message flatten renders natural height with no mask', (
    tester,
  ) async {
    final message = AiMessage(
      id: 'u3',
      role: AiRole.user,
      parts: [AiTextPart(text: tableMarkdown(20))],
    );
    await tester.pumpWidget(
      wrap(
        MarkdownDisplayModeScope(
          userMessageMode: ContentDisplayMode.flatten,
          child: AiMessageView(message: message, showActionBar: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.expand_more), findsNothing); // no mask
    expect(find.text('c19-a'), findsOneWidget); // full table visible
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test packages/ai_message_ui/test/history_render_perf_test.dart`
Expected: FAIL — mode not read (always bounded/masked).

- [ ] **Step 3: Implement**

In `text_part_view.dart`:

(a) `_AiTextPartViewState`: capture the mode and stop clipping when flatten. Add a field + capture in `didChangeDependencies`:

```dart
  var _userMessageMode = ContentDisplayMode.foldFixedHeight;
```

In `didChangeDependencies`, read and store it (alongside `_role`), and include it in the early-return guard:

```dart
    final userMode = MarkdownDisplayModeScope.userMessageOf(context);
    if (_initialized &&
        streaming == _lastStreaming &&
        inHistory == _inHistoryScope &&
        role == _role &&
        userMode == _userMessageMode) {
      return;
    }
    _lastStreaming = streaming;
    _inHistoryScope = inHistory;
    _role = role;
    _userMessageMode = userMode;
```

In `_previewSource`, do not clip when flatten (full doc needed immediately):

```dart
  String _previewSource(String text) {
    if (text.length <= _kHardCompileThreshold) return text;
    if (_lastStreaming ?? false) return text;
    if (!_inHistoryScope) return text;
    if (_role != AiRole.user) return text;
    if (_userMessageMode == ContentDisplayMode.flatten) return text;
    return text.substring(0, _kPreviewCompileChars);
  }
```

(b) `_ExpandableHistoryMarkdown.build` — read the mode and branch the user path:

```dart
    // User message: whole-message collapse, per mode.
    final userMode = MarkdownDisplayModeScope.userMessageOf(context);

    if (userMode == ContentDisplayMode.flatten) {
      // Always natural height in the flow — no mask, no bounded panel.
      final flattened = widget.clipped
          ? (_fullDocument ?? widget.document)
          : widget.document;
      return _buildFlattenMarkdown(context, flattened);
    }

    final truncated = truncateMessageContent(
      widget.document,
      budget: widget.budget,
    );
    if (!widget.clipped && !truncated.wasTruncated) {
      return _ChatMarkdownView(
        document: widget.document,
        onTapLink: widget.onTapLink,
      );
    }

    if (!_expanded) {
      return AiFadeExpandBody(
        open: false,
        onToggle: _toggle,
        fadeColor: AiMessageTheme.of(context).resolveUserBubble(
          Theme.of(context).colorScheme,
        ),
        collapsedMaxHeight: kMaskCollapsedMaxHeight,
        forceChrome: true,
        child: _ChatMarkdownView(
          document: truncated.wasTruncated ? truncated.document : widget.document,
          onTapLink: widget.onTapLink,
        ),
      );
    }

    // Expanded.
    final expandedDoc = widget.clipped
        ? (_fullDocument ?? widget.document)
        : widget.document;
    final Widget body;
    if (userMode == ContentDisplayMode.foldExpandFull) {
      body = _buildFlattenMarkdown(context, expandedDoc);
    } else {
      final bool huge =
          widget.clipped ||
          expandedDoc.blocks.length >= kVirtualizeMarkdownBlockThreshold;
      body = huge
          ? VirtualMarkdownView(
              document: expandedDoc,
              tokens: AiMessageTheme.of(context).markdown,
              resolvers: _chatResolvers(widget.onTapLink),
              strings: _chatMarkdownStrings(context),
              maxHeight: (MediaQuery.sizeOf(context).height * 0.7).clamp(
                240.0,
                800.0,
              ),
            )
          : _ChatMarkdownView(
              document: expandedDoc,
              onTapLink: widget.onTapLink,
            );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        body,
        _MaskCollapseBar(
          onTap: _toggle,
          fadeColor: AiMessageTheme.of(context).resolveUserBubble(
            Theme.of(context).colorScheme,
          ),
        ),
      ],
    );
  }

  Widget _buildFlattenMarkdown(BuildContext context, MarkdownDocument doc) {
    return VirtualMarkdownView(
      document: doc,
      tokens: AiMessageTheme.of(context).markdown,
      resolvers: _chatResolvers(widget.onTapLink),
      strings: _chatMarkdownStrings(context),
      flatten: true,
    );
  }
```

Add the import `import '../markdown_display_mode_scope.dart';`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test packages/ai_message_ui/test/history_render_perf_test.dart`
Expected: PASS. Also run the full package: `flutter test packages/ai_message_ui/test/`.

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/packages/ai_message_ui/lib/src/parts/text_part_view.dart client/packages/ai_message_ui/test/history_render_perf_test.dart
git commit -m "feat(chat): user message honors ContentDisplayMode (mask/flatten)"
```

---
### Task 5: App chat — layout prefs + scope wiring

**Files:**
- Modify: `client/lib/models/layout_preferences.dart` (add 3 fields + copyWith + fromJson/toJson)
- Modify: `client/lib/cubits/layout_cubit.dart` (add 3 setters, pattern at line 370)
- Modify: `client/lib/pages/chat/session_chat_view.dart` (wrap thread with `MarkdownDisplayModeScope`; it already selects `LayoutCubit` via `BlocSelector` at line 1269)
- Test: `client/test/pages/chat/session_history_thread_test.dart`

**Interfaces:**
- Consumes: `MarkdownDisplayModeScope` (Task 1).
- Produces: `LayoutPreferences` gains `chatUserMessageMode`, `chatCodeBlockMode`, `fileCodeBlockMode` (`ContentDisplayMode`, defaults `foldFixedHeight`), persisted via the existing `fromJson`/`toJson`/`copyWith`. `session_chat_view.dart` provides `MarkdownDisplayModeScope` around the history thread.

- [ ] **Step 1: Write the failing test**

In `client/test/pages/chat/session_history_thread_test.dart`, extend `_harness` to accept an optional `ContentDisplayMode userMessageMode` and wrap the thread in `MarkdownDisplayModeScope`, then assert a `flatten` user message renders with no mask:

```dart
  testWidgets('flatten user message via scope renders no mask', (tester) async {
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages([
        AiMessage(id: 'huge', role: AiRole.user, parts: [
          AiTextPart(text: '| A |\n| --- |\n${List.generate(12, (i) => '| c$i |').join('\n')}'),
        ]),
      ]);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: ThemeData(extensions: [AiMessageTheme.test()]),
        home: Scaffold(
          body: MarkdownDisplayModeScope(
            userMessageMode: ContentDisplayMode.flatten,
            child: SizedBox(width: 600, height: 400, child: SessionHistoryThread(runtime: store, hasOlder: false, isLoadingOlder: false, onLoadOlder: () {})),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/chat/session_history_thread_test.dart`
Expected: FAIL — the thread's message path is masked (mode not honored end-to-end because the scope is absent in the app wiring OR `_ExpandableHistoryMarkdown` reads it — it does after Task 4; the test verifies the scope reaches the thread).

- [ ] **Step 3: Implement**

In `client/lib/models/layout_preferences.dart`, add the three fields (defaults `foldFixedHeight`), following the exact pattern of `cotExpandToolsOnOpen` (constructor default at line 72, `fromJson` at line 153, field at line 227, `copyWith` at line 268/340):

```dart
  final ContentDisplayMode chatUserMessageMode;   // default ContentDisplayMode.foldFixedHeight
  final ContentDisplayMode chatCodeBlockMode;     // default ContentDisplayMode.foldFixedHeight
  final ContentDisplayMode fileCodeBlockMode;     // default ContentDisplayMode.foldFixedHeight
```

`fromJson`: `ContentDisplayMode.values.asNameMap()[json['chatUserMessageMode']] ?? ContentDisplayMode.foldFixedHeight` (same for the other two). `toJson`: store `.name`. `copyWith`: `ContentDisplayMode?` params with `?? this.x`.

In `client/lib/cubits/layout_cubit.dart`, add three setters following line 370:

```dart
  void setChatUserMessageMode(ContentDisplayMode value) =>
      _save(state.preferences.copyWith(chatUserMessageMode: value));
  void setChatCodeBlockMode(ContentDisplayMode value) =>
      _save(state.preferences.copyWith(chatCodeBlockMode: value));
  void setFileCodeBlockMode(ContentDisplayMode value) =>
      _save(state.preferences.copyWith(fileCodeBlockMode: value));
```

In `client/lib/pages/chat/session_chat_view.dart`, wrap the thread area (the `SessionHistoryReviewMessages` inside `AiHistoryRenderScope`'s subtree) with `MarkdownDisplayModeScope`, reading the three prefs via the existing `LayoutCubit` select at line 1269:

```dart
    final layout = context.select<LayoutCubit, ({ContentDisplayMode userMsg, ContentDisplayMode chatCode, ContentDisplayMode fileCode})>(
      (c) => (
        userMsg: c.preferences.chatUserMessageMode,
        chatCode: c.preferences.chatCodeBlockMode,
        fileCode: c.preferences.fileCodeBlockMode,
      ),
    );
    // wrap the history thread:
    MarkdownDisplayModeScope(
      userMessageMode: layout.userMsg,
      codeBlockMode: layout.chatCode,
      child: /* the existing history thread widget */,
    )
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/pages/chat/session_history_thread_test.dart`
Expected: PASS. Also `flutter analyze lib/pages/chat/session_chat_view.dart lib/cubits/layout_cubit.dart lib/models/layout_preferences.dart`.

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/models/layout_preferences.dart client/lib/cubits/layout_cubit.dart client/lib/pages/chat/session_chat_view.dart client/test/pages/chat/session_history_thread_test.dart
git commit -m "feat(chat): layout prefs + chat MarkdownDisplayModeScope wiring"
```

---
### Task 6: File preview uses flatten + scope (app)

**Files:**
- Modify: `client/lib/pages/workbench/file_editor_surface.dart` (preview mode around line 646)
- Test: `client/test/pages/workbench/file_editor_surface_test.dart` if present (otherwise add a widget test asserting the preview builds `VirtualMarkdownView` with `flatten: true`)

**Interfaces:**
- Consumes: `VirtualMarkdownView(flatten: true)`, `MarkdownDisplayModeScope` (Tasks 1–2).

- [ ] **Step 1: Write the failing test**

In a file-editor test, render the preview mode with a large document and assert:

```dart
    // preview mode:
    expect(find.byType(VirtualMarkdownView), findsOneWidget);
    final vm = tester.widget<VirtualMarkdownView>(find.byType(VirtualMarkdownView));
    expect(vm.flatten, isTrue);
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — preview uses `MarkdownView`, not `VirtualMarkdownView`.

- [ ] **Step 3: Implement**

In `file_editor_surface.dart`, the preview branch currently does:

```dart
                child: MarkdownView(
                  document: compileMarkdown(_data),
                  tokens: ...,
                ),
```

Replace with a flatten virtualized view wrapped in the file scope:

```dart
              child: MarkdownDisplayModeScope(
                userMessageMode: ContentDisplayMode.foldFixedHeight,
                codeBlockMode: fileCodeBlockMode,
                child: VirtualMarkdownView(
                  document: compileMarkdown(_data),
                  tokens: ...,
                  flatten: true,
                ),
              ),
```

`fileCodeBlockMode` comes from the same `LayoutPreferences`/`LayoutCubit` (Task 5). Read it via the existing cubit access in that file (grep how the file editor reads preferences).

- [ ] **Step 4: Run test to verify it passes + no regression**

Run the file-editor tests and `flutter analyze lib/pages/workbench/file_editor_surface.dart`.

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/pages/workbench/file_editor_surface.dart <test files>
git commit -m "feat(editor): markdown file preview uses flatten virtualized view"
```

---
### Task 7: Config UI

**Files:**
- Modify: `client/lib/pages/config/layout_appearance_in_layout_section.dart` (where `cotExpandToolsOnOpen` is toggled)
- Modify: `client/lib/l10n/app_en.arb` + `client/lib/l10n/app_zh.arb` (labels)
- Test: `client/test/pages/config/layout_appearance_in_layout_section_test.dart` if present; otherwise add one

**Interfaces:**
- Consumes: the three prefs (Task 5).

- [ ] **Step 1: Write the failing test**

Assert the settings UI renders three `ContentDisplayMode` selectors (chat user message / chat code block / file code block) and updates the cubit.

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — controls missing.

- [ ] **Step 3: Implement**

Add a "渲染" (rendering) section in the settings page with three dropdown/segmented controls, one per pref, using l10n keys added to `client/lib/l10n/app_en.arb` + `app_zh.arb` (run `flutter gen-l10n` if the project uses it — follow the existing l10n workflow in AGENTS.md: edit `app_en.arb`/`app_zh.arb` only). Each control calls the cubit's update method.

- [ ] **Step 4: Run to verify it passes**

Run the settings tests + `flutter analyze`.

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add <settings page> <l10n arb files> <generated l10n if any> <test files>
git commit -m "feat(settings): content display mode controls (chat/file)"
```

---
### Task 8: Final verification

**Files:** none (verification only).

- [ ] **Step 1: Run all suites**

Run: `cd client && flutter test packages/tp_markdown/test/ && flutter test packages/ai_message_ui/test/ && flutter test test/pages/chat/ && flutter test --exclude-tags integration`
Expected: all pass.

- [ ] **Step 2: Run analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues (package files excluded; per-file analyzes were done in each task).

- [ ] **Step 3: End-to-end with real data**

Temporarily add a local test that loads the 785 KB user message (path `~/.local/share/com.hhoa.teampilot/workspace/workspaces/d938aa90-e26f-46bd-be4a-427faea59e5f/sessions/f6636678-3245-450b-a0a4-ae93adfe11d4/runtime/claude/projects/-home-hhoa-git-hhoa-teampilot/f6636678-3245-450b-a0a4-ae93adfe11d4.jsonl` line 201), render it with `userMessageMode: flatten`, and assert it mounts fast and reaches the tail by scrolling. Remove the temp test afterward.

- [ ] **Step 4: Commit any stragglers**

```bash
cd /home/hhoa/git/hhoa/teampilot
git status
git add -A && git commit -m "chore: flatten mode verification"  # only if there are uncommitted changes
```
