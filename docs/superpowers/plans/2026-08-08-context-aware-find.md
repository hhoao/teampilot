# Context-Aware Mod+F + Chat Find Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Mod+F` a context-aware "find in the focused surface" (editor, chat page), reduce workspace search to double-tap Shift only, and add full-transcript find + jump to the chat page.

**Architecture:** `ShortcutFocus` gains `claims: Set<KeyChord>`; the live `ShortcutContext` unions claims over every `ShortcutFocus` ancestor and `KeybindingResolver.match` skips a global command whose chord is claimed. `Mod+F` is removed from `workspaceSearch` (double-Shift only), so the global dispatcher no longer steals it from re-editor. Chat find scans the **in-memory** seat transcript (`buildTranscriptDoc` over `seat.loadedMessages`), and jumps by expanding the seat's render window (`revealMessage`) + scrolling the virtualized thread via a new `VirtualThreadViewport` reveal API.

**Tech Stack:** Flutter, flutter_bloc, re-editor (editor find), flutter_alacritty (terminal), ai_message_ui (chat thread), shared_ui (`Tp*` design system).

## Global Constraints

- Follow `client/lib/` layering (cubits / services / repositories / pages / widgets); state is `flutter_bloc` only.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` **only**; never hardcode user-facing strings.
- No `print`; diagnostics → `AppLogger`; user errors → l10n.
- Tests: cubit tests touching `AppStorage` use `setUpTestAppStorage()` / `tearDownTestAppStorage()` from `client/test/support/post_frame_test_harness.dart`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`.
- The terminal is **out of scope for key changes**: Ctrl+F passes through to the PTY; terminal scrollback find stays on `Ctrl+Shift+F` / `F3`.
- Spec: `docs/superpowers/specs/2026-08-08-context-aware-find-design.md`.

---

### Task 1: Chord-claim core — `ShortcutFocus.claims`, `ShortcutContext.claimedChords`, resolver skip

**Files:**
- Modify: `client/lib/services/commands/shortcut_focus.dart`
- Modify: `client/lib/services/commands/shortcut_context.dart`
- Modify: `client/lib/services/commands/keybinding_resolver.dart`
- Modify: `client/lib/main.dart` (`_liveShortcutContext` / `_primaryShortcutFocusKind` area, lines ~112-143)
- Test: `client/test/services/commands/keybinding_resolver_test.dart`

**Interfaces:**
- Consumes: existing `KeyChord` (`key_chord.dart`), existing `ShortcutFocus` / `ShortcutFocusKind`.
- Produces:
  - `ShortcutFocus({this.kind, this.claims = const {}, required super.child})` — `kind` becomes **optional** (`ShortcutFocusKind?`), new `final Set<KeyChord> claims`.
  - `static Set<KeyChord> ShortcutFocus.claimsOf(BuildContext context)` — union over every `ShortcutFocus` ancestor of `context` (nearest → root).
  - `ShortcutContext({... this.claimedChords = const {}})` — new `final Set<KeyChord> claimedChords`.
  - `KeybindingResolver.match(...)` skips a command chord when `context.claimedChords.contains(chord)`.
  - `_liveShortcutContext` populates `claimedChords`.

- [ ] **Step 1: Write the failing resolver test**

Add to `client/test/services/commands/keybinding_resolver_test.dart` (inside the `KeybindingResolver.match` group):

```dart
group('claimed chords suppress the global command', () {
  late Map<String, List<KeyChord>> effective;

  setUp(() {
    effective = KeybindingResolver.effectiveBindings(
      catalog: CommandCatalog.v1,
      overrides: {},
    );
  });

  test('a claimed Mod+F does not fire workspaceSearch', () {
    pressModifier(LogicalKeyboardKey.controlLeft);
    addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

    final result = KeybindingResolver.match(
      event: keyDown(LogicalKeyboardKey.keyF),
      effectiveByCommand: effective,
      context: const ShortcutContext(
        hasWorkspace: true,
        claimedChords: {KeyChord(key: 'f', mods: [KeyChordMod.mod])},
      ),
      isMacOS: false,
    );

    expect(result, isNull);
  });

  test('an unclaimed Mod+F still fires workspaceSearch', () {
    pressModifier(LogicalKeyboardKey.controlLeft);
    addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

    final result = KeybindingResolver.match(
      event: keyDown(LogicalKeyboardKey.keyF),
      effectiveByCommand: effective,
      context: const ShortcutContext(hasWorkspace: true),
      isMacOS: false,
    );

    expect(result, CommandIds.workspaceSearch);
  });
});
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `cd client && flutter test test/services/commands/keybinding_resolver_test.dart --plain-name "claimed chords"`
Expected: both tests fail — `KeybindingResolver.match` returns `CommandIds.workspaceSearch` for the claimed case too (the skip does not exist yet).

- [ ] **Step 3: Implement the claim core**

`client/lib/services/commands/shortcut_focus.dart` — add `import 'key_chord.dart';` and `import 'package:flutter/foundation.dart' show setEquals;`, then:

```dart
class ShortcutFocus extends InheritedWidget {
  const ShortcutFocus({
    this.kind,
    this.claims = const {},
    required super.child,
    super.key,
  });

  /// Null when the surface only claims chords and does not change the
  /// `inCompose` / `inTerminal` / `inTextInput` classification (e.g. the
  /// code editor wrapper).
  final ShortcutFocusKind? kind;

  /// Chords this surface owns while its subtree has focus. A global command
  /// whose chord is claimed is skipped by [KeybindingResolver.match]; the
  /// surface's own `Shortcuts` is the single handler for it.
  final Set<KeyChord> claims;

  static ShortcutFocus? maybeOf(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<ShortcutFocus>();
    return element?.widget as ShortcutFocus?;
  }

  /// Union of [claims] over every [ShortcutFocus] ancestor of [context]
  /// (nearest → root). Called outside build() on every key event, so it must
  /// not register a rebuild dependency.
  static Set<KeyChord> claimsOf(BuildContext context) {
    final result = <KeyChord>{};
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is ShortcutFocus) result.addAll(widget.claims);
      return true;
    });
    return result;
  }

  @override
  bool updateShouldNotify(ShortcutFocus oldWidget) =>
      kind != oldWidget.kind || !setEquals(claims, oldWidget.claims);
}
```

`client/lib/services/commands/shortcut_context.dart` — add `import 'key_chord.dart';`, add field + constructor param:

```dart
class ShortcutContext {
  const ShortcutContext({
    this.inTerminal = false,
    this.inCompose = false,
    this.inTextInput = false,
    this.hasWorkspace = false,
    this.hasOpenWorkspaceTabs = false,
    this.hasSessionTab = false,
    this.floatingPanelOpen = false,
    this.claimedChords = const {},
  });

  /// Chords owned by the focused surface (union over every `ShortcutFocus`
  /// ancestor). A global command whose chord is claimed must not fire.
  final Set<KeyChord> claimedChords;
  // ... existing fields unchanged
}
```

`client/lib/services/commands/keybinding_resolver.dart` — in the `for (final chord in chords)` loop, after the `inTextInput` bare-key block and before `final activator = chord.toActivator(...)`:

```dart
// The focused surface owns this chord (e.g. editor/chat find) — the global
// command must not fire; the surface's own Shortcuts handles it.
if (context.claimedChords.contains(chord)) {
  continue;
}
```

`client/lib/main.dart` — replace `_primaryShortcutFocusKind()` usage. Keep the kind helper, add a claims helper, and populate `claimedChords`:

```dart
ShortcutContext _liveShortcutContext(
  ChatCubit chatCubit,
  WorkspaceChromeCommands workspaceChromeCommands,
  FloatingWorkspaceCubit floatingWorkspaceCubit,
) {
  final location = appRouter.routerDelegate.currentConfiguration.uri.toString();
  final focusKind = _primaryShortcutFocusKind();
  return ShortcutContext(
    inTerminal: focusKind == ShortcutFocusKind.terminal,
    inCompose: focusKind == ShortcutFocusKind.compose,
    inTextInput:
        focusKind == ShortcutFocusKind.compose ||
        focusKind == ShortcutFocusKind.text,
    claimedChords: _primaryClaimedChords(),
    hasWorkspace: location.contains('/home-v2/workspace/'),
    hasOpenWorkspaceTabs: workspaceChromeCommands.openTabCount >= 1,
    hasSessionTab: chatCubit.state.activeSessionId != null,
    floatingPanelOpen:
        floatingWorkspaceCubit.state.visibility == FloatingPanelVisibility.open &&
        !isTpActionMenuOpen,
  );
}

/// Union of `claims` over every `ShortcutFocus` ancestor of the primary focus.
Set<KeyChord> _primaryClaimedChords() {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  if (focusContext == null) return const {};
  return ShortcutFocus.claimsOf(focusContext);
}
```

`main.dart` needs `import 'package:teampilot/services/commands/key_chord.dart';` (check existing imports — add if missing).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd client && flutter test test/services/commands/keybinding_resolver_test.dart`
Expected: all existing + the two new tests PASS.

- [ ] **Step 5: Run the wider command-suite**

Run: `cd client && flutter test test/services/commands/`
Expected: PASS (catalog, dispatcher, key_chord, terminal passthrough).

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/commands/shortcut_focus.dart \
        client/lib/services/commands/shortcut_context.dart \
        client/lib/services/commands/keybinding_resolver.dart \
        client/lib/main.dart \
        client/test/services/commands/keybinding_resolver_test.dart
git commit -m "feat(shortcuts): add chord claims (ShortcutFocus.claims) to suppress global commands"
```

---

### Task 2: Workspace search shortcut → double-Shift only

**Files:**
- Modify: `client/lib/services/commands/command_catalog.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: `client/test/services/commands/shortcut_dispatcher_test.dart`

**Interfaces:**
- Consumes: `KeyChord` from Task 1.
- Produces: `CommandIds.workspaceSearch` with `defaultChords: [KeyChord.doubleTapShift()]`.

- [ ] **Step 1: Change the catalog**

In `client/lib/services/commands/command_catalog.dart`, the `workspaceSearch` definition:

```dart
CommandDefinition(
  id: CommandIds.workspaceSearch,
  category: CommandCategory.navigation,
  defaultChords: [
    KeyChord.doubleTapShift(),
  ],
  when: ShortcutWhen.hasWorkspace,
  terminalPassthrough: true,
  titleL10nKey: 'shortcutsWorkspaceSearch',
),
```

(Remove the `KeyChord(key: 'f', mods: [KeyChordMod.mod])` line.)

- [ ] **Step 2: Update l10n descriptions**

In `client/lib/l10n/app_en.arb`:
```json
"shortcutsWorkspaceSearch": "Search Workspace (double-tap Shift)",
```
In `client/lib/l10n/app_zh.arb`:
```json
"shortcutsWorkspaceSearch": "搜索工作区（双击 Shift）",
```

- [ ] **Step 3: Update the double-Shift test catalog**

In `client/test/services/commands/shortcut_dispatcher_test.dart`, the `searchCatalog` in the `ShortcutDispatcher double Shift` group (lines ~195-207) must drop the `Mod+F` chord so the test matches the real catalog shape:

```dart
final searchCatalog = [
  CommandDefinition(
    id: searchId,
    category: CommandCategory.navigation,
    defaultChords: [
      KeyChord.doubleTapShift(),
    ],
    when: ShortcutWhen.hasWorkspace,
    terminalPassthrough: true,
    titleL10nKey: 'x',
  ),
];
```

- [ ] **Step 4: Add a regression test that Mod+F does not invoke workspaceSearch**

Add to the same `ShortcutDispatcher double Shift` group:

```dart
test('Ctrl+F does not invoke workspace search (Mod+F is surface-owned)', () {
  final bus = CommandBus();
  var called = false;
  bus.register(searchId, () => called = true);
  final dispatcher = ShortcutDispatcher(
    bus: bus,
    effectiveChords: (id) => searchCatalog
        .firstWhere((def) => def.id == id)
        .defaultChords,
    context: () => const ShortcutContext(hasWorkspace: true),
    isMacOS: () => false,
    catalog: searchCatalog,
  );

  pressModifier(LogicalKeyboardKey.controlLeft);
  addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

  final handled = dispatcher.handle(keyDown(LogicalKeyboardKey.keyF));
  expect(handled, isFalse);
  expect(called, isFalse);
});
```

(Confirm the helper names `pressModifier` / `releaseModifier` / `keyDown` exist in this file — they do, same pattern as the resolver test.)

- [ ] **Step 5: Run the tests**

Run: `cd client && flutter test test/services/commands/shortcut_dispatcher_test.dart`
Expected: PASS — double-Shift still invokes, `Ctrl+F` does not.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/commands/command_catalog.dart \
        client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
        client/test/services/commands/shortcut_dispatcher_test.dart
git commit -m "feat(shortcuts): workspace search is double-tap Shift only (Mod+F unbound)"
```

---

### Task 3: Code editor claims Mod+F

**Files:**
- Modify: `client/lib/pages/workbench/file_editor_surface.dart` (imports + `_CodeEditorPane.build`)

**Interfaces:**
- Consumes: `ShortcutFocus`, `KeyChord`, `KeyChordMod` from Task 1.
- Produces: `_CodeEditorPane.build` wraps its returned widget in `ShortcutFocus(claims: {Mod+F})`.

- [ ] **Step 1: Wrap the editor pane in a claim**

In `client/lib/pages/workbench/file_editor_surface.dart`, add imports:
```dart
import '../../services/commands/key_chord.dart';
import '../../services/commands/shortcut_focus.dart';
```

In `_CodeEditorPaneState.build`, the method currently ends with:
```dart
return ListenableBuilder(
  listenable: _menuOpen,
  child: codeEditor,
  builder: (context, child) {
    return SelectionAskAiFabHost(/* ... */);
  },
);
```

Wrap that returned value:
```dart
return ShortcutFocus(
  // The code editor owns Mod+F (re-editor find); document the claim so any
  // future global command binding Mod+F is suppressed here.
  claims: {const KeyChord(key: 'f', mods: [KeyChordMod.mod])},
  child: ListenableBuilder(
    listenable: _menuOpen,
    child: codeEditor,
    builder: (context, child) {
      return SelectionAskAiFabHost(/* ... unchanged ... */);
    },
  ),
);
```

(`kind` is intentionally omitted — the editor already drives `inTextInput` through its own text input, and adding `ShortcutFocusKind.text` here would change bare-key behavior.)

- [ ] **Step 2: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/workbench/file_editor_surface.dart`
Expected: no new issues.

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/workbench/file_editor_surface.dart
git commit -m "feat(editor): claim Mod+F on the code editor pane"
```

---

### Task 4: `AiHistorySeat.revealMessage`

**Files:**
- Modify: `client/lib/cubits/ai_history_seat.dart` (add method near `loadOlder`, ~line 639)
- Test: `client/test/cubits/ai_history_seat_no_blank_test.dart` (existing seat harness)

**Interfaces:**
- Consumes: existing `_allMessages`, `_visibleCount`, `_commitAll()`, `_emitReadyWindow(...)`, `state`.
- Produces: `void revealMessage(int index)` — expands the committed + visible window so `_allMessages[index]` is rendered, no file IO.

- [ ] **Step 1: Write the failing test**

Add to `client/test/cubits/ai_history_seat_no_blank_test.dart` a new group. Use the existing `messages(count)`, `session()`, `ctx(...)`, `loader`, `seat` from `setUp`; the loader adapter is driven by `holderMessages` (a `_HolderAdapter`), so set `holderMessages = messages(40)` and `bumpCacheToken()` before `load`.

```dart
group('revealMessage', () {
  test('expands the visible window to include a not-yet-loaded index', () async {
    holderMessages = messages(40);
    bumpCacheToken();
    await seat.load(session: session(), memberId: '', launchContext: ctx(session()));

    // Initial window covers only the tail (kSessionHistoryInitialTurns).
    final before = seat.loadedMessages;
    expect(before.length, lessThan(40));

    seat.revealMessage(5);
    final after = seat.loadedMessages;
    expect(after.length, 40);
    expect(after.first.id, 'm-0');
    expect(after[5].id, 'm-5');
    expect(seat.state.hasOlder, isFalse);
  });

  test('no-op when the index is already visible', () async {
    holderMessages = messages(10);
    bumpCacheToken();
    await seat.load(session: session(), memberId: '', launchContext: ctx(session()));

    seat.revealMessage(0);
    expect(seat.loadedMessages.length, 10);
  });

  test('ignores out-of-range indices', () async {
    holderMessages = messages(10);
    bumpCacheToken();
    await seat.load(session: session(), memberId: '', launchContext: ctx(session()));

    seat.revealMessage(-1);
    seat.revealMessage(100);
    expect(seat.loadedMessages.length, 10);
  });
});
```

(`kSessionHistoryInitialTurns` is small (a handful of turns); if the first assertion is brittle because `loadedMessages.length` is already 40 for tiny lists, assert instead that `seat.loadedMessages.any((m) => m.id == 'm-5')` is false before reveal and true after.)

- [ ] **Step 2: Run it to make sure it fails**

Run: `cd client && flutter test test/cubits/ai_history_seat_no_blank_test.dart --plain-name "revealMessage"`
Expected: FAIL — `revealMessage` is not defined.

- [ ] **Step 3: Implement `revealMessage`**

In `client/lib/cubits/ai_history_seat.dart`, right after `loadOlder()`:

```dart
/// Expands the committed + visible render window so the message at [index]
/// (0-based into the full loaded transcript) is rendered. No-op when already
/// visible or out of range. Used by chat find to jump to a match without
/// iterating `loadOlder` (the full transcript is already in memory).
void revealMessage(int index) {
  if (isClosed) return;
  if (index < 0 || index >= _allMessages.length) return;
  _commitAll();
  final need = _allMessages.length - index;
  if (_visibleCount >= need) return;
  _visibleCount = need;
  _emitReadyWindow(state.sessionId, state.memberId);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd client && flutter test test/cubits/ai_history_seat_no_blank_test.dart`
Expected: PASS (existing + new).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/ai_history_seat.dart client/test/cubits/ai_history_seat_no_blank_test.dart
git commit -m "feat(chat-history): add AiHistorySeat.revealMessage to expand the render window"
```

---

### Task 5: `VirtualThreadViewport` reveal API

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/virtual_thread_viewport.dart`
- Test: `client/packages/ai_message_ui/test/virtual_thread_viewport_reveal_test.dart`

**Interfaces:**
- Consumes: existing `TurnHeightCache.offsetBefore(_turns, index)`, `_turns` (`ThreadTurn` with `messageIds`).
- Produces:
  - `VirtualThreadViewport({... this.revealMessageId, this.revealEpoch = 0, this.onRevealOffset})`
  - `String? revealMessageId` — the message to reveal.
  - `int revealEpoch` — monotonic; reveal fires when `(revealMessageId, revealEpoch)` changes.
  - `void Function(double offset)? onRevealOffset` — called post-frame with the pixel offset of the turn containing `revealMessageId` (estimate-based until measured).

- [ ] **Step 1: Write the failing package test**

Create `client/packages/ai_message_ui/test/virtual_thread_viewport_reveal_test.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:ai_message_ui/src/virtual_thread_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<AiMessage> _messages(int count) => [
  for (var i = 0; i < count; i++)
    AiMessage(
      id: 'm-$i',
      role: AiRole.user,
      parts: [AiTextPart(text: 'msg-$i')],
    ),
];

void main() {
  testWidgets('revealing a message emits its pixel offset post-frame', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final offsets = <double>[];
    var epoch = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          controller: controller,
          child: VirtualThreadViewport(
            messages: _messages(20),
            scrollController: controller,
            mountTurns: true,
            fillDataWindow: true,
            messageBuilder: (context, message) => SizedBox(
              height: 40,
              child: Text(message.id),
            ),
            onRevealOffset: offsets.add,
            revealMessageId: 'm-15',
            revealEpoch: ++epoch,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(offsets, isNotEmpty);
    expect(offsets.last, greaterThan(0));
  });
}
```

(If `VirtualThreadViewport` is not exported from `package:ai_message_ui/ai_message_ui.dart`, import from `package:ai_message_ui/src/virtual_thread_viewport.dart` — used in the test above as a fallback.)

- [ ] **Step 2: Run it to make sure it fails**

Run: `cd client/packages/ai_message_ui && flutter test test/virtual_thread_viewport_reveal_test.dart`
Expected: FAIL — the constructor params `revealMessageId`/`revealEpoch`/`onRevealOffset` do not exist.

- [ ] **Step 3: Implement the reveal API**

In `client/packages/ai_message_ui/lib/src/virtual_thread_viewport.dart`:

Add three fields to the constructor + class:
```dart
/// When [revealEpoch] changes and [revealMessageId] is non-null and present in
/// [messages], compute the pixel offset of its turn and call [onRevealOffset]
/// post-frame (estimate-based until that turn is measured). Host jumps the
/// scroll controller; the normal measurement-correction path then refines.
final String? revealMessageId;
final int revealEpoch;
final void Function(double offset)? onRevealOffset;
```

Track the last seen reveal in state:
```dart
String? _lastRevealMessageId;
int _lastRevealEpoch = 0;
```

In `didUpdateWidget`, after `_syncVisibleRange();`:
```dart
if (widget.revealMessageId != _lastRevealMessageId ||
    widget.revealEpoch != _lastRevealEpoch) {
  _lastRevealMessageId = widget.revealMessageId;
  _lastRevealEpoch = widget.revealEpoch;
  final targetId = widget.revealMessageId;
  final onOffset = widget.onRevealOffset;
  if (targetId != null && onOffset != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final turnIndex = _turns.indexWhere((t) => t.messageIds.contains(targetId));
      if (turnIndex < 0) return;
      onOffset(_cache.offsetBefore(_turns, turnIndex));
    });
  }
}
```

In `initState`, initialize `_lastRevealMessageId = widget.revealMessageId; _lastRevealEpoch = widget.revealEpoch;` so the first frame does not re-fire.

- [ ] **Step 4: Run the package tests**

Run: `cd client/packages/ai_message_ui && flutter test`
Expected: PASS (existing + new).

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/virtual_thread_viewport.dart \
        client/packages/ai_message_ui/test/virtual_thread_viewport_reveal_test.dart
git commit -m "feat(ai-message-ui): add reveal-by-message-id API to VirtualThreadViewport"
```

---

### Task 6: `SessionHistoryThread` reveal + highlight

**Files:**
- Modify: `client/lib/pages/chat/session_history_thread.dart`
- Modify: `client/lib/pages/chat/session_history_review_messages.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart` (only to pass the new params through — wiring happens in Task 8)

**Interfaces:**
- Consumes: `VirtualThreadViewport.revealMessageId/revealEpoch/onRevealOffset` from Task 5.
- Produces:
  - `SessionHistoryReviewMessages({... this.highlightMessageId, this.revealRequest})` — `String? highlightMessageId`; `ChatRevealController? revealRequest`.
  - `SessionHistoryThread({... this.highlightMessageId, this.revealRequest})` — same fields.
  - `class ChatRevealController extends ChangeNotifier { String? targetMessageId; int epoch; void reveal(String id); void clear(); }` — created in this task (file: `client/lib/pages/chat/chat_reveal_controller.dart`).

- [ ] **Step 1: Create `ChatRevealController`**

Create `client/lib/pages/chat/chat_reveal_controller.dart`:

```dart
import 'package:flutter/foundation.dart';

/// Carries the "scroll to this message and highlight it" intent from the chat
/// find host down to [SessionHistoryThread]. [epoch] lets re-selecting the
/// same message re-trigger the reveal.
class ChatRevealController extends ChangeNotifier {
  String? targetMessageId;
  int epoch = 0;

  void reveal(String messageId) {
    targetMessageId = messageId;
    epoch++;
    notifyListeners();
  }

  void clear() {
    targetMessageId = null;
    epoch++;
    notifyListeners();
  }
}
```

- [ ] **Step 2: Thread — listen, stick-off, forward to viewport, highlight**

In `client/lib/pages/chat/session_history_thread.dart`:

Add widget fields:
```dart
final String? highlightMessageId;
final ChatRevealController? revealRequest;
```

State additions:
```dart
String? _revealTargetId;
int _revealEpoch = 0;
ChatRevealController? _boundReveal;

void _onRevealRequestChanged() {
  if (!mounted) return;
  final request = widget.revealRequest;
  if (request != null) {
    _revealTargetId = request.targetMessageId;
    _revealEpoch = request.epoch;
  }
  _setStickToEnd(false);
  setState(() {});
}
```

In `initState` (after `_scrollController = ...`):
```dart
_boundReveal = widget.revealRequest;
_boundReveal?.addListener(_onRevealRequestChanged);
```

In `didUpdateWidget`, after the existing `if (oldWidget.runtime != widget.runtime) {...}`:
```dart
if (oldWidget.revealRequest != widget.revealRequest) {
  _boundReveal?.removeListener(_onRevealRequestChanged);
  _boundReveal = widget.revealRequest;
  _boundReveal?.addListener(_onRevealRequestChanged);
  _onRevealRequestChanged();
}
```

In `dispose`, before `super.dispose()`:
```dart
_boundReveal?.removeListener(_onRevealRequestChanged);
```

In the `VirtualThreadViewport(...)` call, add:
```dart
revealMessageId: _revealTargetId,
revealEpoch: _revealEpoch,
onRevealOffset: (offset) {
  if (!_scrollController.hasClients || offset < 0) return;
  final max = _scrollController.position.maxScrollExtent;
  _jumpTo(offset > max ? max : offset);
},
```

In `messageBuilder`, wrap the target message in a highlight ring. Right after `final messageChild = AiMessageView(...)`, before the `tightenForRunning` return, add:

```dart
if (ai.id == widget.highlightMessageId) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 2),
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: cs.primary, width: 1.5),
    ),
    child: messageChild,
  );
}
```

(Place it after the `tightenForRunning` computation so highlight wins over the spacing tweak; the `tightenForRunning` `Theme` variant is only for a trailing running tip, which find never targets.)

Import `chat_reveal_controller.dart` in the thread file.

- [ ] **Step 3: Pass-through in `SessionHistoryReviewMessages`**

In `client/lib/pages/chat/session_history_review_messages.dart`, add optional fields to the widget + forward them in the `SessionHistoryThread(...)` call:

```dart
final String? highlightMessageId;
final ChatRevealController? revealRequest;
```

```dart
child: SessionHistoryThread(
  runtime: runtime,
  hasOlder: state.hasOlder,
  isLoadingOlder: state.isLoadingOlder,
  onLoadOlder: onLoadOlder,
  liveChrome: liveChrome,
  highlightMessageId: highlightMessageId,
  revealRequest: revealRequest,
),
```

- [ ] **Step 4: Wire the params in `SessionChatView` (compile-only; full behavior in Task 8)**

In `client/lib/pages/chat/session_chat_view.dart`, pass the two new params at the `SessionHistoryReviewMessages(...)` call site (around line 1574) so the tree compiles:
```dart
child: SessionHistoryReviewMessages(
  state: state,
  runtime: historySeat.runtime,
  onRetry: () => _loadHistory(force: true),
  onLoadOlder: historySeat.loadOlder,
  liveChrome: liveChrome,
  highlightMessageId: null,
  revealRequest: null,
),
```

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/chat/`
Expected: no new issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/chat/chat_reveal_controller.dart \
        client/lib/pages/chat/session_history_thread.dart \
        client/lib/pages/chat/session_history_review_messages.dart \
        client/lib/pages/chat/session_chat_view.dart
git commit -m "feat(chat): thread reveal + bubble highlight plumbing"
```

---

### Task 7: `ChatTranscriptFindController` (all-match scan over the in-memory transcript)

**Files:**
- Modify: `client/lib/services/session/workspace_session_content_index.dart` (make `messageIndexAt` + `snippetAround` public statics)
- Create: `client/lib/services/session/chat_transcript_find_controller.dart`
- Test: `client/test/services/session/chat_transcript_find_controller_test.dart`

**Interfaces:**
- Consumes: `buildTranscriptDoc(...)` and `caseInsensitiveIndexOf(...)` from `workspace_session_content_index.dart`; `AiMessage` / `AiTextPart` from `ai_message_core`.
- Produces:
  - `class TranscriptHit { final int messageIndex; final String messageId; final String snippet; }`
  - `class ChatTranscriptFindController extends ChangeNotifier`:
    - `ChatTranscriptFindController({required List<AiMessage> Function() messagesProvider})`
    - `String get query`
    - `List<TranscriptHit> get hits`
    - `int get currentIndex` (`-1` when none)
    - `TranscriptHit? get current`
    - `bool get hasQuery`
    - `void search(String query)`
    - `void next()` / `void previous()` (wrap)
    - `void clear()`

- [ ] **Step 1: Promote the two helpers to public statics**

In `client/lib/services/session/workspace_session_content_index.dart`, rename `_messageIndexAt` → `messageIndexAt` and `_snippetAround` → `snippetAround` (update their two internal call sites). Update the `static` signatures:

```dart
static int messageIndexAt(List<int> starts, int offset) { ... }

static String snippetAround(String text, int start, int queryLength, {int lead = 48, int trail = 96}) { ... }
```

- [ ] **Step 2: Write the failing controller test**

Create `client/test/services/session/chat_transcript_find_controller_test.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/chat_transcript_find_controller.dart';

List<AiMessage> _messages(List<String> texts) => [
  for (final (i, text) in texts.indexed)
    AiMessage(
      id: 'm-$i',
      role: i.isEven ? AiRole.user : AiRole.assistant,
      parts: [AiTextPart(text: text)],
    ),
];

void main() {
  late List<AiMessage> messages;
  late ChatTranscriptFindController controller;

  setUp(() {
    messages = _messages([
      'Plan the alpha feature.',
      'Let me grep for alpha in config.',
      'Alpha is now implemented.',
      'Also fix the beta bug.',
    ]);
    controller = ChatTranscriptFindController(messagesProvider: () => messages);
  });

  tearDown(controller.dispose);

  test('empty query yields no hits', () {
    controller.search('   ');
    expect(controller.hasQuery, isFalse);
    expect(controller.hits, isEmpty);
    expect(controller.currentIndex, -1);
  });

  test('finds all case-insensitive matches across messages', () {
    controller.search('alpha');
    expect(controller.hits.length, 3);
    expect(controller.hits[0].messageIndex, 0);
    expect(controller.hits[1].messageIndex, 1);
    expect(controller.hits[2].messageIndex, 2);
    expect(controller.hits[0].messageId, 'm-0');
    expect(controller.hits[0].snippet.toLowerCase(), contains('alpha'));
  });

  test('next/previous wrap around the result list', () {
    controller.search('alpha');
    expect(controller.currentIndex, 0);
    controller.previous();
    expect(controller.currentIndex, 2);
    controller.next();
    expect(controller.currentIndex, 0);
    controller.next();
    expect(controller.currentIndex, 1);
  });

  test('snippet stays within the matching message', () {
    controller.search('beta');
    expect(controller.hits.single.messageIndex, 3);
    expect(controller.hits.single.snippet, contains('beta'));
  });

  test('clear resets state', () {
    controller.search('alpha');
    controller.clear();
    expect(controller.query, isEmpty);
    expect(controller.hits, isEmpty);
    expect(controller.currentIndex, -1);
  });
}
```

- [ ] **Step 3: Run it to make sure it fails**

Run: `cd client && flutter test test/services/session/chat_transcript_find_controller_test.dart`
Expected: FAIL — class not defined.

- [ ] **Step 4: Implement the controller**

Create `client/lib/services/session/chat_transcript_find_controller.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/foundation.dart';
import 'workspace_session_content_index.dart';

/// Result-cap for the find results list.
const int kChatFindMaxResults = 50;

/// One match in the transcript: the message it lives in (index into the full
/// loaded message list + its id) and a snippet around the first occurrence.
class TranscriptHit {
  const TranscriptHit({
    required this.messageIndex,
    required this.messageId,
    required this.snippet,
  });

  final int messageIndex;
  final String messageId;
  final String snippet;
}

/// Full-transcript find for one chat seat. Builds a `SessionTranscriptDoc`
/// from the seat's **in-memory** `loadedMessages` (indices align 1:1), scans
/// every case-insensitive occurrence, and tracks a current match (n/N).
///
/// The doc is cached and rebuilt only when the message-list instance changes,
/// so repeated keystrokes scan text without re-projecting messages.
class ChatTranscriptFindController extends ChangeNotifier {
  ChatTranscriptFindController({required this.messagesProvider});

  final List<AiMessage> Function() messagesProvider;

  String _query = '';
  List<TranscriptHit> _hits = const [];
  int _currentIndex = -1;

  SessionTranscriptDoc? _doc;
  List<AiMessage>? _docMessages;

  String get query => _query;
  List<TranscriptHit> get hits => _hits;
  int get currentIndex => _hits.isEmpty ? -1 : _currentIndex;
  bool get hasQuery => _query.trim().isNotEmpty;
  TranscriptHit? get current =>
      _hits.isEmpty || _currentIndex < 0 ? null : _hits[_currentIndex];

  void search(String value) {
    final query = value.trim();
    if (query == _query) return;
    _query = query;
    if (query.isEmpty) {
      _hits = const [];
      _currentIndex = -1;
      notifyListeners();
      return;
    }
    final messages = messagesProvider();
    final doc = _docFor(messages);
    _hits = _scan(query, doc, messages);
    _currentIndex = _hits.isEmpty ? -1 : 0;
    notifyListeners();
  }

  void next() {
    if (_hits.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % _hits.length;
    notifyListeners();
  }

  void previous() {
    if (_hits.isEmpty) return;
    _currentIndex = (_currentIndex - 1 + _hits.length) % _hits.length;
    notifyListeners();
  }

  void clear() => search('');

  SessionTranscriptDoc _docFor(List<AiMessage> messages) {
    if (identical(_docMessages, messages)) return _doc ?? buildTranscriptDoc(messages);
    _doc = buildTranscriptDoc(messages);
    _docMessages = messages;
    return _doc!;
  }

  static List<TranscriptHit> _scan(
    String query,
    SessionTranscriptDoc doc,
    List<AiMessage> messages,
  ) {
    final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
    final hits = <TranscriptHit>[];
    for (final match in pattern.allMatches(doc.text)) {
      if (hits.length >= kChatFindMaxResults) break;
      final index = match.start;
      final messageIndex = WorkspaceSessionContentIndex.messageIndexAt(
        doc.messageStarts,
        index,
      );
      if (messageIndex < 0 || messageIndex >= messages.length) continue;
      hits.add(
        TranscriptHit(
          messageIndex: messageIndex,
          messageId: messages[messageIndex].id,
          snippet: WorkspaceSessionContentIndex.snippetAround(
            doc.text,
            index,
            query.length,
          ),
        ),
      );
    }
    return hits;
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd client && flutter test test/services/session/chat_transcript_find_controller_test.dart && flutter test test/services/session/workspace_search_indexes_test.dart` (if the latter exists; otherwise run `flutter test test/services/session/`)
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/session/workspace_session_content_index.dart \
        client/lib/services/session/chat_transcript_find_controller.dart \
        client/test/services/session/chat_transcript_find_controller_test.dart
git commit -m "feat(chat): ChatTranscriptFindController full-transcript all-match scan"
```

---

### Task 8: Chat find bar UI + `SessionChatView` wiring

**Files:**
- Create: `client/lib/pages/chat/chat_find_bar.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/chat/session_chat_view_find_test.dart`

**Interfaces:**
- Consumes: `ChatTranscriptFindController`/`TranscriptHit` (Task 7), `ChatRevealController` (Task 6), `ShortcutFocus`/`KeyChord` (Task 1), `AiHistorySeat.revealMessage` (Task 4).
- Produces: `SessionChatView` toggles a find bar on `Mod+F`, searches the in-memory transcript, navigates n/N, reveals + highlights the match, closes on Esc / close.

- [ ] **Step 1: Add l10n strings**

`client/lib/l10n/app_en.arb`:
```json
"chatFindHint": "Find in conversation",
"chatFindNoResults": "No matches",
"chatFindResults": "Matches",
"chatFindLoading": "Loading conversation…",
"chatFindPrevious": "Previous match",
"chatFindNext": "Next match",
"chatFindClose": "Close find",
```

`client/lib/l10n/app_zh.arb`:
```json
"chatFindHint": "在对话中查找",
"chatFindNoResults": "无匹配",
"chatFindResults": "匹配结果",
"chatFindLoading": "正在加载对话…",
"chatFindPrevious": "上一个匹配",
"chatFindNext": "下一个匹配",
"chatFindClose": "关闭查找",
```

- [ ] **Step 2: Create `ChatFindBar`**

Create `client/lib/pages/chat/chat_find_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ShortcutActivator, SingleActivator, Intent, CallbackAction
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/session/chat_transcript_find_controller.dart';
import '../../services/session/workspace_session_content_index.dart';
import '../../utils/debounce/debounce.dart';

/// Find bar for the chat page: query field + n/N counter + prev/next + close,
/// plus a collapsible results list. Driven by [ChatTranscriptFindController].
class ChatFindBar extends StatefulWidget {
  const ChatFindBar({
    required this.controller,
    required this.queryController,
    required this.focusNode,
    required this.onNavigate,
    required this.onClose,
    super.key,
  });

  final ChatTranscriptFindController controller;
  final TextEditingController queryController;
  final FocusNode focusNode;

  /// Called with the hit to reveal+highlight when the user picks a result or
  /// steps next/prev.
  final void Function(TranscriptHit hit) onNavigate;
  final VoidCallback onClose;

  @override
  State<ChatFindBar> createState() => _ChatFindBarState();
}

class _ChatFindCloseIntent extends Intent {
  const _ChatFindCloseIntent();
}

class _ChatFindBarState extends State<ChatFindBar> {
  static const double _rowHeight = 34;
  static const double _width = 420;

  @override
  void dispose() {
    Debounces.cancel('chat_find_bar_${identityHashCode(this)}');
    super.dispose();
  }

  void _onChanged(String value) {
    Debounces.debounce(
      'chat_find_bar_${identityHashCode(this)}',
      const Duration(milliseconds: 120),
      () {
        if (mounted) widget.controller.search(value);
      },
    );
  }

  void _navigateCurrent() {
    final hit = widget.controller.current;
    if (hit != null) widget.onNavigate(hit);
  }

  void _navigateIndex(int index) {
    final hits = widget.controller.hits;
    if (index < 0 || index >= hits.length) return;
    widget.onNavigate(hits[index]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    // Escape closes find. Mounted only while find is visible, so Escape can
    // never open it. (Mirrors TerminalFindShortcuts' Esc handling.)
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.escape): const _ChatFindCloseIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ChatFindCloseIntent: CallbackAction<_ChatFindCloseIntent>(
            onInvoke: (_) {
              widget.onClose();
              return null;
            },
          ),
        },
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
        final controller = widget.controller;
        final total = controller.hits.length;
        final current = controller.currentIndex;
        final counter = total == 0
            ? ''
            : '${current + 1}/$total';
        final hasQuery = controller.hasQuery;
        final loading = hasQuery && total == 0;

        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(6),
              clipBehavior: Clip.antiAlias,
              color: cs.surfaceContainerHighest,
              child: SizedBox(
                width: _width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: _rowHeight,
                      child: Row(
                        children: [
                          _input(context),
                          SizedBox(
                            width: 44,
                            child: Text(
                              counter,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          TpIconButton(
                            icon: Icons.keyboard_arrow_up,
                            size: TpIconButton.kCompactSize,
                            compact: true,
                            color: cs.onSurfaceVariant,
                            tooltip: l10n.chatFindPrevious,
                            enabled: total > 0,
                            onTap: () {
                              controller.previous();
                              _navigateCurrent();
                            },
                          ),
                          TpIconButton(
                            icon: Icons.keyboard_arrow_down,
                            size: TpIconButton.kCompactSize,
                            compact: true,
                            color: cs.onSurfaceVariant,
                            tooltip: l10n.chatFindNext,
                            enabled: total > 0,
                            onTap: () {
                              controller.next();
                              _navigateCurrent();
                            },
                          ),
                          TpIconButton(
                            icon: Icons.close,
                            size: TpIconButton.kCompactSize,
                            compact: true,
                            color: cs.onSurfaceVariant,
                            tooltip: l10n.chatFindClose,
                            onTap: widget.onClose,
                          ),
                        ],
                      ),
                    ),
                    if (hasQuery)
                      total > 0
                          ? _ResultsList(
                              hits: controller.hits,
                              currentIndex: current,
                              query: controller.query,
                              onTap: _navigateIndex,
                            )
                          : Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                loading
                                    ? l10n.chatFindLoading
                                    : l10n.chatFindNoResults,
                                style: TpTextStyles.of(
                                  context,
                                ).smColored(cs.onSurfaceVariant),
                              ),
                            ),
                  ],
                ),
              ),
            ),
          ),
        );
          },
        ),
      ),
    );
  }

  Widget _input(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 220,
      height: _rowHeight,
      child: TextField(
        controller: widget.queryController,
        focusNode: widget.focusNode,
        maxLines: 1,
        autofocus: true,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: context.l10n.chatFindHint,
          hintStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          filled: true,
          fillColor: cs.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: cs.primary),
          ),
          suffixIcon: widget.queryController.text.isNotEmpty
              ? TpIconButton(
                  icon: Icons.clear,
                  compact: true,
                  size: TpIconButton.kCompactSize,
                  onTap: () {
                    widget.queryController.clear();
                    widget.controller.clear();
                  },
                )
              : null,
        ),
        onChanged: _onChanged,
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.hits,
    required this.currentIndex,
    required this.query,
    required this.onTap,
  });

  final List<TranscriptHit> hits;
  final int currentIndex;
  final String query;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: hits.length,
        itemBuilder: (context, index) {
          final hit = hits[index];
          final selected = index == currentIndex;
          return Material(
            color: selected ? cs.primary.withValues(alpha: 0.10) : Colors.transparent,
            child: InkWell(
              onTap: () => onTap(index),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _HighlightedSnippet(text: hit.snippet, query: query)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One-to-two line snippet with the first case-insensitive [query] occurrence
/// in bold (mirrors `workspace_search_dialog.dart`).
class _HighlightedSnippet extends StatelessWidget {
  const _HighlightedSnippet({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TpTextStyles.of(context).smColored(cs.onSurfaceVariant);
    final idx = WorkspaceSessionContentIndex.caseInsensitiveIndexOf(text, query);
    if (idx == null) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: style);
    }
    final end = idx + query.trim().length;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, end),
            style: style.copyWith(fontWeight: FontWeight.w600, color: cs.primary),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
```

- [ ] **Step 3: Wire the find bar + claims + shortcuts into `SessionChatView`**

In `client/lib/pages/chat/session_chat_view.dart`:

Add imports:
```dart
import 'package:flutter/services.dart'; // LogicalKeyboardKey, SingleActivator, Intent, CallbackAction

import '../../services/commands/key_chord.dart';
import '../../services/commands/shortcut_focus.dart';
import '../../services/session/chat_transcript_find_controller.dart';
import 'chat_find_bar.dart';
import 'chat_reveal_controller.dart';
```

Add a private toggle intent + action (file-private, top-level in the file):
```dart
class _ChatFindToggleIntent extends Intent {
  const _ChatFindToggleIntent();
}
```

> Note: Escape is **not** bound here — it is handled inside `ChatFindBar` (see Step 2's `_ChatFindBarState`), which is only mounted while find is visible, so Escape reliably closes and can never open find.

Add state fields in `_SessionChatViewState`:
```dart
final _findQueryController = TextEditingController();
final _findFocusNode = FocusNode(debugLabel: 'session_chat_find');
final _findController = ChatTranscriptFindController(
  messagesProvider: () => _seat?.loadedMessages ?? const [],
);
final _revealController = ChatRevealController();
bool _findVisible = false;
String? _findHighlightId;
```

Dispose them in `dispose()`:
```dart
_findQueryController.dispose();
_findFocusNode.dispose();
_findController.dispose();
_revealController.dispose();
```

Add handlers:
```dart
void _toggleFind() {
  setState(() => _findVisible = !_findVisible);
  if (_findVisible) {
    _findFocusNode.requestFocus();
  } else {
    _closeFind();
  }
}

void _closeFind() {
  _findController.clear();
  _findQueryController.clear();
  setState(() {
    _findVisible = false;
    _findHighlightId = null;
  });
  _revealController.clear();
}

void _navigateFindTo(TranscriptHit hit) {
  final seat = _seat;
  if (seat != null) {
    seat.revealMessage(hit.messageIndex);
  }
  setState(() => _findHighlightId = hit.messageId);
  // Reveal after the frame so the seat's window update has reached the thread
  // and the target message is in `displayMessages` when the offset is computed.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _revealController.reveal(hit.messageId);
  });
}
```

In `build`, wrap the returned `ColoredBox` (`return ColoredBox(color: cs.surface, ...)`) with `ShortcutFocus` + `Shortcuts`/`Actions`:

```dart
return ShortcutFocus(
  claims: {const KeyChord(key: 'f', mods: [KeyChordMod.mod])},
  child: Shortcuts(
    shortcuts: <ShortcutActivator, Intent>{
      // Ctrl+F (Linux/Windows) and Cmd+F (macOS) both toggle the find bar;
      // only the platform-matching activator fires for a given key press.
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): const _ChatFindToggleIntent(),
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): const _ChatFindToggleIntent(),
    },
    child: Actions(
      actions: <Type, Action<Intent>>{
        _ChatFindToggleIntent: CallbackAction<_ChatFindToggleIntent>(
          onInvoke: (_) {
            _toggleFind();
            return null;
          },
        ),
      },
      child: ColoredBox(
        color: cs.surface,
        child: /* ... existing body ... */,
      ),
    ),
  ),
);
```

Inside the body, the thread area is the `Expanded(child: AiToolFileActionsScope(...))`. Wrap that `Expanded`'s child in a `Stack` so the find bar can overlay the thread:

```dart
Expanded(
  child: Stack(
    children: [
      Positioned.fill(
        child: AiToolFileActionsScope(
          /* ... existing thread subtree unchanged ... */
        ),
      ),
      if (_findVisible)
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: ChatFindBar(
            controller: _findController,
            queryController: _findQueryController,
            focusNode: _findFocusNode,
            onNavigate: _navigateFindTo,
            onClose: _closeFind,
          ),
        ),
    ],
  ),
),
```

Finally, pass the highlight + reveal to the thread via `SessionHistoryReviewMessages` (replacing the `highlightMessageId: null, revealRequest: null` from Task 6):

```dart
child: SessionHistoryReviewMessages(
  state: state,
  runtime: historySeat.runtime,
  onRetry: () => _loadHistory(force: true),
  onLoadOlder: historySeat.loadOlder,
  liveChrome: liveChrome,
  highlightMessageId: _findHighlightId,
  revealRequest: _revealController,
),
```

- [ ] **Step 4: Add a widget test for toggle + search + navigate**

Create `client/test/pages/chat/session_chat_view_find_test.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/services/session/chat_transcript_find_controller.dart';
import 'package:teampilot/pages/chat/chat_find_bar.dart';

void main() {
  testWidgets('ChatFindBar shows counter and navigates through hits', (tester) async {
    final messages = <AiMessage>[
      for (var i = 0; i < 4; i++)
        AiMessage(
          id: 'm-$i',
          role: i.isEven ? AiRole.user : AiRole.assistant,
          parts: [AiTextPart(text: i == 3 ? 'fix the alpha bug' : 'alpha note $i')],
        ),
    ];
    final controller = ChatTranscriptFindController(messagesProvider: () => messages);
    addTearDown(controller.dispose);
    final query = TextEditingController();
    final focus = FocusNode();
    addTearDown(query.dispose);
    addTearDown(focus.dispose);
    final navigated = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatFindBar(
            controller: controller,
            queryController: query,
            focusNode: focus,
            onNavigate: (hit) => navigated.add(hit.messageId),
            onClose: () {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pumpAndSettle();

    expect(controller.hits.length, 4);
    expect(find.text('1/4'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();
    expect(controller.currentIndex, 1);
    expect(find.text('2/4'), findsOneWidget);
    expect(navigated.last, 'm-1');
  });
}
```

(The `ChatFindBar` widget test is the fast, stable one; the full `SessionChatView` integration relies on the existing harness in `session_chat_view_draft_cache_test.dart` — if you extend that harness, verify the find bar toggles on Mod+F via `tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft)` + `keyF`.)

- [ ] **Step 5: Run the tests**

Run: `cd client && flutter test test/pages/chat/session_chat_view_find_test.dart test/services/session/chat_transcript_find_controller_test.dart`
Expected: PASS.

- [ ] **Step 6: Run analyzer**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

- [ ] **Step 7: Commit**

```bash
git add client/lib/pages/chat/chat_find_bar.dart \
        client/lib/pages/chat/session_chat_view.dart \
        client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
        client/test/pages/chat/session_chat_view_find_test.dart
git commit -m "feat(chat): Mod+F find bar with full-transcript search, reveal and highlight"
```

---

### Task 9: Full verification

**Files:** none.

- [ ] **Step 1: Analyze the whole client**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors / new warnings.

- [ ] **Step 2: Run the full test suite (non-integration)**

Run: `cd client && flutter test --exclude-tags integration`
Expected: all green. Pay attention to `test/services/commands/`, `test/cubits/ai_history_seat_no_blank_test.dart`, and `client/packages/ai_message_ui` (run its package tests separately: `cd client/packages/ai_message_ui && flutter test`).

- [ ] **Step 3: Manual smoke (desktop)**

Launch the app, open a workspace with a code file and a chat session:
- In the **code editor**, press `Mod+F` → the inline re-editor find bar opens, the workspace search dialog does **not**.
- Press double-tap **Shift** → the workspace search dialog opens.
- Open a **chat** session, press `Mod+F` → the chat find bar opens; type a term that appears in old history → results list shows matches; click/next → the thread scrolls to that message and highlights the bubble.
- In a **terminal**, press `Mod+F` → the key is **not** intercepted (it passes to the PTY, e.g. `cat` shows nothing); `Ctrl+Shift+F` still opens scrollback find.

- [ ] **Step 4: Commit any residual fixes**

```bash
git add -A
git commit -m "fix: verification fixes for context-aware find"
```

---

## Self-review notes

- **Spec coverage:** chord claims (Task 1), double-Shift-only workspace search (Task 2), editor claim (Task 3), chat in-memory find (Tasks 4–8), reveal-by-window-expansion (Task 4), viewport reveal (Task 5), thread reveal + highlight (Task 6), all-match scan (Task 7), find bar UI (Task 8), l10n (Tasks 2, 8), tests throughout. The terminal is intentionally untouched (see spec "Terminal" section — pass-through).
- **Placeholder scan:** every step has concrete code or an exact command; no TBD.
- **Type consistency:** `ChatRevealController.targetMessageId/epoch` (Task 6) is consumed by the thread and produced by `SessionChatView` (Task 8); `ChatTranscriptFindController.current.messageId` (Task 7) feeds `onNavigate` (Task 8); `VirtualThreadViewport.revealMessageId/revealEpoch/onRevealOffset` (Task 5) is wired by the thread (Task 6); `messageIndexAt`/`snippetAround` public statics (Task 7) reused by the controller and find bar.
