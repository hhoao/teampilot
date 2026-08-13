# Compose Paste Collapse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a paste makes the compose text exceed 25 lines, collapse the block into a "Pasted text · N lines" badge with a full-screen editor, so the always-visible input never lays out huge text.

**Architecture:** A `ComposeClip` (ChangeNotifier) owns the collapsed block text. `ComposeTriggerField` detects a single controller change whose line count jumps past 25 (paste-only, since typing adds at most one line per keystroke), moves the whole draft into the clip, and clears the visible controller — so build never renders the long text. `WorkspaceComposeCard` renders a badge bar (edit / remove), and a full-screen `ComposePasteEditorPage` edits the block on demand. Parents (`SessionChatView`, `_UnboundComposeBodyState`) own the clip, use `clip.collapsed || !textEmpty` for canSubmit, and submit `clip.composeMessage(controller.text)`.

**Tech Stack:** Dart, Flutter, shared_ui (`Tp*` design system), flutter_bloc, existing widget-test harnesses.

## Global Constraints

- Threshold: collapse when line count (`'\n'` count + 1) **exceeds** 25 (i.e. `> 25`), per spec.
- Line count helper: `ComposeClip.countLines(String)` — single source of truth.
- Badge label uses `粘贴文本` / "Pasted text" (paste-only trigger, per confirmed UX decision).
- Collapsed input stays live for follow-up text; submit joins block + follow-up with `'\n\n'` (block first).
- Editor reuses shared_ui `TpTextareaScrollBehavior` + `tpMultilineInputDecoration`; navigation via `Navigator.push(MaterialPageRoute(fullscreenDialog: true))` (existing repo pattern).
- **Deviation from spec §7 (enhance):** enhance keeps operating on the follow-up input only (`controller.text`), NOT `composeMessage`. Rationale: enhancing the merged message would rewrite the pasted block, and writing the result back would require unsplittable block/follow-up; the block is reference material and must stay untouched in the clip.
- l10n: edit `client/lib/l10n/app_en.arb` + `app_zh.arb` only, then run `cd client && flutter gen-l10n`.
- All new strings must appear in both arb files. `cancel` already exists — reuse `l10n.cancel`.
- Final gate before done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`.

---

### Task 1: `ComposeClip` model + unit tests

**Files:**
- Create: `client/lib/services/compose/compose_clip.dart`
- Test: `client/test/services/compose/compose_clip_test.dart`

**Interfaces:**
- Produces: `class ComposeClip extends ChangeNotifier` with `bool get collapsed`, `String? get text`, `int get lineCount`, `void setPasted(String fullText)`, `void setExpanded(String newText)`, `String composeMessage(String followUp)`, `void clear()`, and `static int countLines(String text)`. Later tasks (3–8) depend on exactly these members.

- [ ] **Step 1: Write the failing unit test**

```dart
// client/test/services/compose/compose_clip_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_clip.dart';

void main() {
  group('ComposeClip', () {
    test('starts empty and not collapsed', () {
      final clip = ComposeClip();
      expect(clip.collapsed, isFalse);
      expect(clip.text, isNull);
      expect(clip.lineCount, 1);
    });

    test('setPasted collapses with the block and line count', () {
      final clip = ComposeClip();
      clip.setPasted('a\nb\nc');
      expect(clip.collapsed, isTrue);
      expect(clip.text, 'a\nb\nc');
      expect(clip.lineCount, 3);
    });

    test('composeMessage joins block and follow-up with a blank line', () {
      final clip = ComposeClip();
      clip.setPasted('block');
      expect(clip.composeMessage(''), 'block');
      expect(clip.composeMessage('why?'), 'block\n\nwhy?');
    });

    test('composeMessage with empty clip returns follow-up only', () {
      final clip = ComposeClip();
      expect(clip.composeMessage('why?'), 'why?');
    });

    test('setExpanded updates text but stays collapsed', () {
      final clip = ComposeClip();
      clip.setPasted('a\nb');
      clip.setExpanded('a\nb\nc\nd');
      expect(clip.collapsed, isTrue);
      expect(clip.lineCount, 4);
    });

    test('clear resets to empty', () {
      final clip = ComposeClip();
      clip.setPasted('text');
      clip.clear();
      expect(clip.collapsed, isFalse);
      expect(clip.text, isNull);
    });

    test('countLines counts newlines + 1', () {
      expect(ComposeClip.countLines(''), 1);
      expect(ComposeClip.countLines('a'), 1);
      expect(ComposeClip.countLines('a\nb\nc'), 3);
      expect(ComposeClip.countLines('a\nb\n'), 3);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/compose/compose_clip_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:teampilot/services/compose/compose_clip.dart'`.

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/services/compose/compose_clip.dart
import 'package:flutter/foundation.dart';

/// Holds a paste-collapsed block of text that is kept out of the visible
/// compose field (which would otherwise lay out every line). Owned by the
/// compose parent (e.g. `SessionChatView`) and threaded down through the
/// compose card into `ComposeTriggerField`.
class ComposeClip extends ChangeNotifier {
  String _text = '';

  bool get collapsed => _text.isNotEmpty;

  /// The full block text, or null when not collapsed.
  String? get text => _text.isEmpty ? null : _text;

  /// Line count (newline count + 1) of the block, or 1 when empty.
  int get lineCount => countLines(_text);

  /// Collapse with the whole current draft (e.g. right after an oversized
  /// paste). The caller clears the visible controller afterwards.
  void setPasted(String fullText) {
    if (_text == fullText) return;
    _text = fullText;
    notifyListeners();
  }

  /// Write-back from the full-screen editor. Stays collapsed; line count may
  /// change.
  void setExpanded(String newText) {
    if (_text == newText) return;
    _text = newText;
    notifyListeners();
  }

  /// Final message: non-empty parts joined with a blank line (block first).
  String composeMessage(String followUp) {
    final block = _text.trim();
    final tail = followUp.trim();
    if (block.isEmpty) return tail;
    if (tail.isEmpty) return block;
    return '$block\n\n$tail';
  }

  void clear() {
    if (_text.isEmpty) return;
    _text = '';
    notifyListeners();
  }

  /// Line count = `'\n'` count + 1. Deterministic and O(n) — matches the
  /// reference mockup's "152 lines" counting and never needs text layout.
  static int countLines(String text) {
    if (text.isEmpty) return 1;
    var count = 1;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0a) count++;
    }
    return count;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/compose/compose_clip_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/compose/compose_clip.dart client/test/services/compose/compose_clip_test.dart
git commit -m "feat(compose): add ComposeClip paste-collapse model"
```

---

### Task 2: l10n strings

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`

**Interfaces:**
- Produces generated getters on `AppLocalizations` (used by Tasks 3–4): `composePasteClipLabel`, `composePasteClipLines(int lines)`, `composePasteClipEdit`, `composePasteClipRemove`, `composePasteEditorTitle(int lines)`, `composePasteEditorDone`, `composePasteEditorRemove`. `cancel` already exists.

- [ ] **Step 1: Add keys to `app_en.arb`**

Insert (alphabetically near the other `compose*` keys; exact position does not matter, but keep it out of the `@@locale` header block):

```json
"composePasteClipLabel": "Pasted text",
"composePasteClipLines": "{lines} lines",
"@composePasteClipLines": {
  "placeholders": {
    "lines": { "type": "int" }
  }
},
"composePasteClipEdit": "Edit pasted text",
"composePasteClipRemove": "Remove pasted text",
"composePasteEditorTitle": "Edit pasted text · {lines} lines",
"@composePasteEditorTitle": {
  "placeholders": {
    "lines": { "type": "int" }
  }
},
"composePasteEditorDone": "Done",
"composePasteEditorRemove": "Remove"
```

- [ ] **Step 2: Add the matching keys to `app_zh.arb`**

```json
"composePasteClipLabel": "粘贴文本",
"composePasteClipLines": "{lines} 行",
"@composePasteClipLines": {
  "placeholders": {
    "lines": { "type": "int" }
  }
},
"composePasteClipEdit": "编辑已粘贴文本",
"composePasteClipRemove": "移除已粘贴文本",
"composePasteEditorTitle": "编辑已粘贴文本 · {lines} 行",
"@composePasteEditorTitle": {
  "placeholders": {
    "lines": { "type": "int" }
  }
},
"composePasteEditorDone": "完成",
"composePasteEditorRemove": "移除"
```

- [ ] **Step 3: Regenerate localizations**

Run: `cd client && flutter gen-l10n`
Expected: exits 0; `client/lib/l10n/app_localizations.dart` now contains `composePasteClipLabel`, `composePasteClipLines`, `composePasteClipEdit`, `composePasteClipRemove`, `composePasteEditorTitle`, `composePasteEditorDone`, `composePasteEditorRemove`.

- [ ] **Step 4: Verify generation**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new errors (the generated file compiles).

- [ ] **Step 5: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart
git commit -m "feat(l10n): compose paste collapse strings"
```

---

### Task 3: `ComposePasteClipBar` widget + test

**Files:**
- Create: `client/lib/widgets/compose/compose_paste_clip_bar.dart`
- Test: `client/test/widgets/compose/compose_paste_clip_bar_test.dart`

**Interfaces:**
- Consumes: `ComposeClip` (Task 1), l10n keys (Task 2).
- Produces: `class ComposePasteClipBar extends StatelessWidget` with `{required ComposeClip clip, required VoidCallback onEdit, required VoidCallback onRemove}`. Used by Task 6.

- [ ] **Step 1: Write the failing widget test**

```dart
// client/test/widgets/compose/compose_paste_clip_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/compose/compose_clip.dart';
import 'package:teampilot/widgets/compose/compose_paste_clip_bar.dart';

void main() {
  testWidgets('shows pasted label with line count and fires callbacks', (
    tester,
  ) async {
    final clip = ComposeClip()..setPasted('a\nb\nc');
    var editFired = false;
    var removeFired = false;
    addTearDown(clip.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ComposePasteClipBar(
            clip: clip,
            onEdit: () => editFired = true,
            onRemove: () => removeFired = true,
          ),
        ),
      ),
    );

    // "Pasted text · 3 lines" — the · separator makes exact text fragile.
    expect(find.textContaining('Pasted text'), findsOneWidget);
    expect(find.textContaining('3 lines'), findsOneWidget);

    await tester.tap(find.textContaining('Pasted text'));
    expect(editFired, isTrue);

    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(removeFired, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/widgets/compose/compose_paste_clip_bar_test.dart`
Expected: FAIL — URI does not exist for `compose_paste_clip_bar.dart`.

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/widgets/compose/compose_paste_clip_bar.dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
import '../../services/compose/compose_clip.dart';

/// Compact bar shown above the compose field when an oversized paste has been
/// collapsed into a [ComposeClip]: a "Pasted text · N lines" badge plus a
/// remove affordance. Clicking the badge opens the full editor.
class ComposePasteClipBar extends StatelessWidget {
  const ComposePasteClipBar({
    required this.clip,
    required this.onEdit,
    required this.onRemove,
    super.key,
  });

  final ComposeClip clip;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspaceChatLandingPalette(Theme.of(context).colorScheme);
    final spacing = context.tpSpacing;
    final l10n = context.l10n;
    final icons = context.tpIconSizes;
    final styles = TpTextStyles.of(context);
    final label =
        '${l10n.composePasteClipLabel} · ${l10n.composePasteClipLines(clip.lineCount)}';

    final badge = Material(
      color: palette.chipFill,
      shape: StadiumBorder(side: BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.content_paste_rounded,
                size: icons.sm,
                color: palette.muted,
              ),
              SizedBox(width: spacing.xs),
              Text(label, style: styles.smColored(palette.muted)),
              SizedBox(width: spacing.xs),
              Icon(
                Icons.open_in_full,
                size: icons.sm,
                color: palette.muted,
              ),
            ],
          ),
        ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(message: l10n.composePasteClipEdit, child: badge),
        SizedBox(width: spacing.xs),
        Tooltip(
          message: l10n.composePasteClipRemove,
          child: TpHover(
            shape: TpPressableShape.circle,
            width: 28,
            height: 28,
            backgroundColor: Colors.transparent,
            onTap: onRemove,
            child: Center(
              child: Icon(
                Icons.close_rounded,
                size: icons.sm,
                color: palette.muted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/widgets/compose/compose_paste_clip_bar_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/compose/compose_paste_clip_bar.dart client/test/widgets/compose/compose_paste_clip_bar_test.dart
git commit -m "feat(compose): paste clip badge bar"
```

---

### Task 4: `ComposePasteEditorPage` + test

**Files:**
- Create: `client/lib/widgets/compose/compose_paste_editor_dialog.dart`
- Test: `client/test/widgets/compose/compose_paste_editor_dialog_test.dart`

**Interfaces:**
- Consumes: `ComposeClip`, l10n keys, shared_ui `TpTextareaScrollBehavior` + `tpMultilineInputDecoration`.
- Produces: `Future<void> showComposePasteEditor(BuildContext context, ComposeClip clip)` (pushes a `MaterialPageRoute(fullscreenDialog: true)` to `ComposePasteEditorPage`). Used by Task 6.

- [ ] **Step 1: Write the failing widget test**

```dart
// client/test/widgets/compose/compose_paste_editor_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/compose/compose_clip.dart';
import 'package:teampilot/widgets/compose/compose_paste_editor_dialog.dart';

void main() {
  Future<void> pumpEditor(
    WidgetTester tester,
    ComposeClip clip,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showComposePasteEditor(context, clip),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Done commits edits and stays collapsed', (tester) async {
    final clip = ComposeClip()..setPasted('a\nb\nc');
    addTearDown(clip.dispose);

    await pumpEditor(tester, clip);
    expect(find.textContaining('3 lines'), findsOneWidget); // title

    await tester.enterText(find.byType(TextField), 'new\ncontent\nmore');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(clip.text, 'new\ncontent\nmore');
    expect(clip.collapsed, isTrue);
  });

  testWidgets('Cancel discards edits', (tester) async {
    final clip = ComposeClip()..setPasted('original');
    addTearDown(clip.dispose);

    await pumpEditor(tester, clip);
    await tester.enterText(find.byType(TextField), 'changed');
    await tester.tap(find.byIcon(Icons.close_rounded)); // leading close = cancel
    await tester.pumpAndSettle();

    expect(clip.text, 'original');
  });

  testWidgets('Remove clears the clip', (tester) async {
    final clip = ComposeClip()..setPasted('original');
    addTearDown(clip.dispose);

    await pumpEditor(tester, clip);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(clip.collapsed, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/widgets/compose/compose_paste_editor_dialog_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/widgets/compose/compose_paste_editor_dialog.dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/compose/compose_clip.dart';

/// Opens the full-screen editor for a collapsed [ComposeClip]. Returns when
/// the page pops. Callers should `unawaited(...)` the returned future.
Future<void> showComposePasteEditor(
  BuildContext context,
  ComposeClip clip,
) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ComposePasteEditorPage(clip: clip),
    ),
  );
}

/// Full-screen page for viewing/editing the collapsed paste block. Seeded
/// from [ComposeClip.text]; commits via [ComposeClip.setExpanded] on Done,
/// discards on close, or clears via [ComposeClip.clear] on Remove.
class ComposePasteEditorPage extends StatefulWidget {
  const ComposePasteEditorPage({required this.clip, super.key});

  final ComposeClip clip;

  @override
  State<ComposePasteEditorPage> createState() => _ComposePasteEditorPageState();
}

class _ComposePasteEditorPageState extends State<ComposePasteEditorPage> {
  late final TextEditingController _editor;

  @override
  void initState() {
    super.initState();
    _editor = TextEditingController(text: widget.clip.text ?? '');
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  void _commit() {
    widget.clip.setExpanded(_editor.text);
    Navigator.of(context).pop();
  }

  void _remove() {
    widget.clip.clear();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.tpSpacing;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.composePasteEditorTitle(widget.clip.lineCount)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: l10n.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: _remove,
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(l10n.composePasteEditorRemove),
          ),
          FilledButton(
            onPressed: _commit,
            child: Text(l10n.composePasteEditorDone),
          ),
          SizedBox(width: spacing.lg),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: ScrollConfiguration(
          behavior: const TpTextareaScrollBehavior(),
          child: TextField(
            controller: _editor,
            autofocus: true,
            expands: true,
            minLines: null,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: tpMultilineInputDecoration(context),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/widgets/compose/compose_paste_editor_dialog_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/compose/compose_paste_editor_dialog.dart client/test/widgets/compose/compose_paste_editor_dialog_test.dart
git commit -m "feat(compose): full-screen paste block editor"
```

---

### Task 5: `ComposeTriggerField` paste detection

**Files:**
- Modify: `client/lib/widgets/compose/compose_trigger_field.dart` (add `clip` param; detection in `_handleControllerChanged`)
- Test: `client/test/widgets/compose/compose_trigger_field_test.dart` (append cases to the existing file)

**Interfaces:**
- Consumes: `ComposeClip` (Task 1).
- Produces: new optional ctor param `ComposeClip? clip` on `ComposeTriggerField`. On collapse it calls `clip.setPasted(controller.text)`, `controller.clear()`, then `widget.onChanged(controller.text)` (so the parent's `onComposeChanged` → `setState` fires even though the clear was programmatic). Used by Tasks 6–8.

- [ ] **Step 1: Write the failing widget tests**

Append to `client/test/widgets/compose/compose_trigger_field_test.dart` inside `main()`:

```dart
  group('paste collapse', () {
    Future<void> pumpWithClip(
      WidgetTester tester, {
      required TextEditingController controller,
      required FocusNode focusNode,
      required ComposeClip clip,
    }) async {
      final bus = CommandBus();
      await tester.pumpWidget(
        RepositoryProvider<CommandBus>.value(
          value: bus,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ComposeTriggerField(
                controller: controller,
                focusNode: focusNode,
                hint: 'Ask anything',
                enabled: true,
                onChanged: (_) {},
                onSubmit: () {},
                canSubmit: () => true,
                workspaceRoot: '/tmp',
                skills: const [],
                plugins: const [],
                slashBundle: const ConfigBundle(),
                mutedColor: Colors.black,
                hintColor: Colors.grey,
                clip: clip,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('oversized single insert collapses into the clip and clears',
        (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final clip = ComposeClip();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(clip.dispose);

      await pumpWithClip(tester, controller: controller, focusNode: focusNode, clip: clip);

      final longText = List.generate(30, (i) => 'line $i').join('\n');
      controller.text = longText;
      controller.selection = TextSelection.collapsed(offset: longText.length);
      await tester.pump();

      expect(clip.collapsed, isTrue);
      expect(clip.text, longText);
      expect(controller.text, isEmpty);
    });

    testWidgets('small paste does not collapse', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final clip = ComposeClip();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(clip.dispose);

      await pumpWithClip(tester, controller: controller, focusNode: focusNode, clip: clip);

      controller.text = 'small\npaste';
      await tester.pump();

      expect(clip.collapsed, isFalse);
      expect(controller.text, 'small\npaste');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/widgets/compose/compose_trigger_field_test.dart`
Expected: FAIL — `clip` is not a named parameter of `ComposeTriggerField`.

- [ ] **Step 3: Implement the detection**

In `client/lib/widgets/compose/compose_trigger_field.dart`:

3a. Add the ctor param (after `this.onPasteImage`):

```dart
    this.skillSyntax,
    this.onPasteImage,
    this.clip,
    super.key,
  });
```

And the field:

```dart
  final Future<bool> Function()? onPasteImage;

  /// Optional paste-collapse buffer. When set and a single change pushes the
  /// line count past [kComposePasteCollapseLines], the whole draft moves into
  /// the clip and the visible controller is cleared.
  final ComposeClip? clip;
```

Add the import near the other `services/compose` imports:

```dart
import '../../services/compose/compose_clip.dart';
```

3b. Add the threshold constant + state field at the top of `_ComposeTriggerFieldState`:

```dart
class _ComposeTriggerFieldState extends State<ComposeTriggerField> {
  static const _pasteCollapseLines = 25;
  late int _lastLineCount;
```

3c. Initialize in `initState` (before the controller listener is added):

```dart
  @override
  void initState() {
    super.initState();
    _lastLineCount = ComposeClip.countLines(widget.controller.text);
    widget.controller.addListener(_handleControllerChanged);
```

3d. Re-init when the controller swaps in `didUpdateWidget`:

```dart
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _lastLineCount = ComposeClip.countLines(widget.controller.text);
    }
```

3e. Call detection first in `_handleControllerChanged`:

```dart
  void _handleControllerChanged() {
    _maybeCollapseOversizedPaste();
    _refreshSuggestions();
    _scheduleMenuAnchorUpdate();
  }
```

3f. Add the detection method:

```dart
  /// Collapses a single oversized insert (a paste) into the clip. Typing adds
  /// at most one line per change, so only a large single insert crosses the
  /// threshold. Undo that restores the long text re-crosses it (self-heals).
  void _maybeCollapseOversizedPaste() {
    final clip = widget.clip;
    if (clip == null) return;
    final count = ComposeClip.countLines(widget.controller.text);
    final crossed =
        _lastLineCount <= _pasteCollapseLines && count > _pasteCollapseLines;
    _lastLineCount = count;
    if (!crossed) return;
    clip.setPasted(widget.controller.text);
    widget.controller.clear();
    // Programmatic clear() does not fire TextField.onChanged, so ping the
    // parent's onComposeChanged (setState) so canSubmit recomputes.
    widget.onChanged(widget.controller.text);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/widgets/compose/compose_trigger_field_test.dart`
Expected: PASS (existing tests + 2 new).

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/compose/compose_trigger_field.dart client/test/widgets/compose/compose_trigger_field_test.dart
git commit -m "feat(compose): collapse oversized pastes into ComposeClip"
```

---

### Task 6: `WorkspaceComposeCard` badge integration

**Files:**
- Modify: `client/lib/widgets/compose/workspace_compose_card.dart`
- Test: `client/test/widgets/compose/workspace_compose_card_test.dart` (append cases)

**Interfaces:**
- Consumes: `ComposeClip`, `ComposePasteClipBar` (Task 3), `showComposePasteEditor` (Task 4).
- Produces: new optional ctor param `ComposeClip? clip` on `WorkspaceComposeCard`. Used by Tasks 7–8.

- [ ] **Step 1: Write the failing widget tests**

Append to `client/test/widgets/compose/workspace_compose_card_test.dart`:

```dart
  testWidgets('renders paste clip bar only while clip is collapsed', (
    tester,
  ) async {
    final clip = ComposeClip();
    addTearDown(clip.dispose);

    await tester.pumpWidget(
      pumpCard(chrome: unboundChrome, clip: clip),
    );
    expect(find.byType(ComposePasteClipBar), findsNothing);

    clip.setPasted('a\nb\nc');
    await tester.pump();
    expect(find.byType(ComposePasteClipBar), findsOneWidget);
    expect(find.textContaining('3 lines'), findsOneWidget);

    clip.clear();
    await tester.pump();
    expect(find.byType(ComposePasteClipBar), findsNothing);
  });

  testWidgets('at-file chips scan the collapsed block text', (tester) async {
    final clip = ComposeClip();
    addTearDown(clip.dispose);

    await tester.pumpWidget(
      pumpCard(chrome: unboundChrome, clip: clip),
    );
    clip.setPasted('see @lib/main.dart inside the block');
    await tester.pump();

    expect(find.byType(ComposeAtFileChipRow), findsOneWidget);
  });
```

Update the `pumpCard` helper signature in that file to accept and forward `clip`:

```dart
  Widget pumpCard({
    required ComposeChrome chrome,
    bool deferFieldMount = false,
    TextEditingController? controller,
    FocusNode? focusNode,
    ValueChanged<String>? onOpenAtFile,
    ComposeClip? clip,
  }) {
    ...
        body: WorkspaceComposeCard(
          ...
          clip: clip,
        ),
```

Add the import:

```dart
import 'package:teampilot/services/compose/compose_clip.dart';
import 'package:teampilot/widgets/compose/compose_paste_clip_bar.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/widgets/compose/workspace_compose_card_test.dart`
Expected: FAIL — `clip` not a named parameter; `ComposePasteClipBar` import missing.

- [ ] **Step 3: Implement the integration**

In `client/lib/widgets/compose/workspace_compose_card.dart`:

3a. Add imports:

```dart
import 'dart:async';

import '../../services/compose/compose_clip.dart';
import 'compose_paste_clip_bar.dart';
import 'compose_paste_editor_dialog.dart';
```

3b. Add the ctor param and field:

```dart
    this.submitBlockedTooltip,
    this.deferFieldMount = false,
    this.onOpenAtFile,
    this.clip,
    super.key,
  });
```

```dart
  final ValueChanged<String>? onOpenAtFile;

  /// Optional paste-collapse buffer. When collapsed, a badge bar is rendered
  /// above the field and canSubmit/submit/references account for the block.
  final ComposeClip? clip;
```

3c. In `build`, before `final shell = ComposeFocusShell(...)`, add a merged listenable and the badge row. Replace the two inner `ListenableBuilder(listenable: controller, ...)` blocks (at-file refs and actions row) to listen to the merged listenable and account for the clip.

Replace:

```dart
    final shell = ComposeFocusShell(
```

…nothing above it changes, but inside the `Column.children`, insert the badge builder as the first child after the launch-error banner, and update the refs + actions builders:

```dart
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (chrome is BoundComposeChrome)
                  ..._launchErrorBanner(context, chrome, spacing),
                if (clip != null)
                  ListenableBuilder(
                    listenable: clip!,
                    builder: (context, _) {
                      if (!clip!.collapsed) return const SizedBox.shrink();
                      return Padding(
                        padding: EdgeInsets.only(bottom: spacing.md),
                        child: ComposePasteClipBar(
                          clip: clip!,
                          onEdit: () =>
                              unawaited(showComposePasteEditor(context, clip!)),
                          onRemove: clip!.clear,
                        ),
                      );
                    },
                  ),
                ListenableBuilder(
                  listenable: Listenable.merge([
                    controller,
                    if (clip != null) clip!,
                  ]),
                  builder: (context, _) {
                    final refs = parseComposeAtFileRefs(
                      clip?.composeMessage(controller.text) ??
                          controller.text,
                      workspaceRoot: workspaceRoot,
                    );
                    if (refs.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: EdgeInsets.only(bottom: spacing.md),
                      child: ComposeAtFileChipRow(
                        refs: refs,
                        onOpen: onOpenAtFile ?? (_) {},
                      ),
                    );
                  },
                ),
                field,
                SizedBox(height: spacing.md),
                ListenableBuilder(
                  listenable: Listenable.merge([
                    controller,
                    if (clip != null) clip!,
                  ]),
                  builder: (context, _) {
                    final hasText =
                        controller.text.trim().isNotEmpty ||
                        (clip?.collapsed ?? false);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: isVoiceListening
                          ? _voiceRecordingActions(
                              context: context,
                              palette: palette,
                              spacing: spacing,
                              hasText: hasText,
                            )
                          : _idleActions(
                              context,
                              chrome: chrome,
                              palette: palette,
                              spacing: spacing,
                              hasText: hasText,
                            ),
                    );
                  },
                ),
              ],
            ),
```

Note: `Listenable.merge` may return the same listenable unchanged when there is a single element, so the existing `listenable: controller` behavior is preserved for callers without a clip.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/widgets/compose/workspace_compose_card_test.dart`
Expected: PASS (existing + 2 new).

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/compose/workspace_compose_card.dart client/test/widgets/compose/workspace_compose_card_test.dart
git commit -m "feat(compose): integrate paste clip badge into compose card"
```

---

### Task 7: Session continue compose integration

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Modify: `client/lib/pages/chat/session_chat_compose_section.dart`

**Interfaces:**
- Consumes: `ComposeClip` (Task 1) and `WorkspaceComposeCard.clip` (Task 6).
- Produces: `SessionChatComposeSection` gains `ComposeClip? clip`; the chat compose now submits `clip.composeMessage(controller.text.trim())` and computes canSubmit with `clip.collapsed`.

- [ ] **Step 1: Wire `_clip` into `SessionChatView`**

In `client/lib/pages/chat/session_chat_view.dart`:

1a. Add import:

```dart
import '../../services/compose/compose_clip.dart';
```

1b. Add the field next to `_controller`:

```dart
  final _controller = TextEditingController();
  final _clip = ComposeClip();
```

1c. Dispose it next to `_controller.dispose()` (line ~322):

```dart
    _clip.dispose();
    _controller.dispose();
```

1d. Pass it to the section (line ~1168, next to `composeController: _controller`):

```dart
                                            composeController: _controller,
                                            composeClip: _clip,
```

1e. Clear the clip on every submit-clear / restore. In `_handleComposeSubmit`'s `onEnqueue` (line ~793) next to `_controller.clear()`:

```dart
        _controller.clear();
        _clip.clear();
```

In `_deliverComposeMessage` (line ~828) next to the optimistic `_controller.clear()`:

```dart
    _controller.clear();
    _clip.clear();
```

On the failure restore (line ~840), clear the stale clip before restoring the composed text (the detection will re-collapse it if >25 lines):

```dart
    if (!result.ok) {
      _cancelAwaitingIdleGrace();
      if (optimisticPty) seat.removePendingMatching(text);
      _clip.clear();
      _controller
        ..text = text
        ..selection = TextSelection.collapsed(offset: text.length);
```

- [ ] **Step 2: Wire `clip` into `SessionChatComposeSection`**

In `client/lib/pages/chat/session_chat_compose_section.dart`:

2a. Add import:

```dart
import '../../services/compose/compose_clip.dart';
```

2b. Add the ctor param + field (near `composeController`). Make it **optional**
(nullable, `this.composeClip`) so existing construction sites / tests that do
not know about the clip keep compiling:

```dart
    required this.composeController,
    required this.composeFocusNode,
    this.composeClip,
```

```dart
  final TextEditingController composeController;
  final FocusNode composeFocusNode;

  /// Optional paste-collapse buffer. The visible controller holds only the
  /// follow-up text while collapsed; canSubmit and the submitted message
  /// account for the block.
  final ComposeClip? composeClip;
```

2c. Update `composeTextEmpty` (line ~166) and the submit closure (line ~324):

```dart
    final composeTextEmpty =
        composeController.text.trim().isEmpty &&
        !(composeClip?.collapsed ?? false);
```

```dart
                          onSubmit: () => unawaited(
                            onSubmit(
                              composeClip?.composeMessage(
                                    composeController.text.trim(),
                                  ) ??
                                  composeController.text.trim(),
                            ),
                          ),
```

- [ ] **Step 3: Verify compile + existing tests**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new errors.

Run: `cd client && flutter test --exclude-tags integration test/pages/chat test/widgets/compose`
Expected: PASS (existing session-compose chrome and submit-gate tests).

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/chat/session_chat_view.dart client/lib/pages/chat/session_chat_compose_section.dart
git commit -m "feat(compose): wire paste collapse into session continue compose"
```

---

### Task 8: Landing compose integration

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`

**Interfaces:**
- Consumes: `ComposeClip` (Task 1) and `WorkspaceComposeCard.clip` (Task 6).

- [ ] **Step 1: Wire `_clip` into `_UnboundComposeBodyState`**

In `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`:

1a. Add import (near the other `services/compose` imports):

```dart
import '../../../services/compose/compose_clip.dart';
```

1b. Add the field next to `_controller` (line ~106):

```dart
  final _controller = TextEditingController();
  final _clip = ComposeClip();
```

1c. Dispose it (line ~342):

```dart
    _controller.removeListener(_syncComposeDraft);
    _clip.dispose();
    _controller.dispose();
```

1d. Pass it to `WorkspaceComposeCard` (line ~1408, next to `controller: _controller`):

```dart
    final composeCard = WorkspaceComposeCard(
      controller: _controller,
      clip: _clip,
```

- [ ] **Step 2: Update `_canSubmit` and `_submitAfterLaunchGate`**

2a. `_canSubmit` (line ~892) — allow a collapsed block alone:

```dart
  bool get _canSubmit {
    if (widget.disabled || widget.isSubmitting) return false;
    if (_controller.text.trim().isEmpty && !_clip.collapsed) return false;
```

2b. `_submitAfterLaunchGate` (line ~919) — compose the merged message, and clear the clip after submit (the landing does not clear its controller in-state; the clip must not outlive a successful launch):

```dart
  Future<void> _submitAfterLaunchGate() async {
    final text = _clip.composeMessage(_controller.text.trim());
    if (text.isEmpty || widget.disabled || widget.isSubmitting) return;
```

and after the final `widget.onSubmit(text, _currentDraft());` (line ~1023):

```dart
    widget.onSubmit(text, _currentDraft());
    _clip.clear();
```

- [ ] **Step 3: Verify compile + existing tests**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new errors.

Run: `cd client && flutter test --exclude-tags integration test/pages/home_workspace/workspace test/widgets/compose`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/unbound_compose_body.dart
git commit -m "feat(compose): wire paste collapse into landing compose"
```

---

### Task 9: Full verification

- [ ] **Step 1: Run analyze + full non-integration test suite**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: both green.

- [ ] **Step 2: Manual smoke (desktop)**

Launch the app, open a session, paste ~30 lines into the compose field:
- Field collapses to the badge "粘贴文本 · 30 行" and the empty input shows the hint; typing a follow-up is live.
- Send button is enabled with only the block (empty follow-up) and with a follow-up.
- Clicking the badge opens the full-screen editor; Done updates the badge count; Remove clears it.
- Sent message contains the block followed by `\n\n` + follow-up.
- Pasting < 25 lines behaves exactly as before.
- Verify the same on the landing (new conversation) input.

- [ ] **Step 3: Commit any fix-ups**

```bash
git add -A
git commit -m "fix(compose): polish paste collapse after smoke test"
```

---
