# Mobile Terminal Accessory Keyboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On non-desktop touch shells, tapping the terminal always reopens the system soft keyboard, and a ServerBox-style dual-row accessory bar provides Esc/Ctrl/Alt/Tab/arrows/Home/End/IME toggle with sticky modifiers.

**Architecture:** `flutter_alacritty` owns IME `ensureVisible`/`hide`, `ModifierLatch`, `TerminalKeyInjector`, extensible accessory key/layout model, and an unstyled `TerminalAccessoryBar`. `TeampilotAlacrittyTerminal` is the sole product enablement point (touch heuristic → bar + latch). Latch merges into IME commit + inject paths only (not hardware `onKeyEvent` OS modifiers).

**Tech Stack:** Flutter / Dart, `flutter_alacritty`, `flutter_test`, TeamPilot `TeampilotAlacrittyTerminal`.

**Spec:** `docs/superpowers/specs/2026-08-01-mobile-terminal-accessory-keyboard-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/flutter_alacritty/lib/input/ime_session.dart` | `ensureVisible()`, `hide()` |
| `client/packages/flutter_alacritty/lib/input/modifier_latch.dart` | Sticky ctrl/alt/shift + `consumeAfterSend` + `ChangeNotifier` |
| `client/packages/flutter_alacritty/lib/input/terminal_key_injector.dart` | Merge latch + `encodeKey` / UTF-8 → write callback |
| `client/packages/flutter_alacritty/lib/input/terminal_accessory_key.dart` | Sealed key kinds (latch / injectKey / injectRaw / action) |
| `client/packages/flutter_alacritty/lib/input/terminal_accessory_layout.dart` | `serverBoxDualRow` preset + row lists |
| `client/packages/flutter_alacritty/lib/input/touch_shell.dart` | `isTouchShell({TargetPlatform?})` → android \|\| iOS |
| `client/packages/flutter_alacritty/lib/ui/terminal_accessory_bar.dart` | Unstyled bar UI + long-press repeat |
| `client/packages/flutter_alacritty/lib/ui/terminal_view.dart` | Touch tap → `ensureVisible`; optional latch/injector; blur clears latch |
| `client/packages/flutter_alacritty/lib/ui/terminal_view_pointer.dart` | Touch tap also calls `ensureVisible` |
| `client/packages/flutter_alacritty/lib/flutter_alacritty.dart` | Export new public types |
| `client/lib/widgets/terminal/teampilot_alacritty_terminal.dart` | Enable bar+latch on touch shell; theme chrome |
| Tests under `client/packages/flutter_alacritty/test/` and `client/test/widgets/terminal/` | Unit + widget coverage |

**Long-press defaults:** initial delay `400ms`, repeat interval `137ms` (ServerBox-like).

**Touch heuristic:** `TargetPlatform.android || TargetPlatform.iOS` via `defaultTargetPlatform` (injectable for tests). Do **not** use layout width breakpoints.

---

### Task 1: `ImeSession.ensureVisible` / `hide`

**Files:**
- Modify: `client/packages/flutter_alacritty/lib/input/ime_session.dart`
- Test: `client/packages/flutter_alacritty/test/ime_session_test.dart`

- [ ] **Step 1: Write the failing test**

Add a group that uses a fake connection seam. Prefer the smallest change that makes show/hide observable:

Option A (preferred if easy): extract optional `TextInputConnection? Function(TextInputClient, TextInputConfiguration)? attachOverride` for tests — only if existing tests already mock attach.  

Option B: add package-visible hooks:

```dart
@visibleForTesting
int ensureVisibleCallCount = 0; // on a test double subclass
```

Simplest approach that matches existing style: introduce a thin `ImeConnection` interface **only if needed**. Otherwise test via a `TestImeSession` subclass in the test file that overrides `_conn` behavior.

Pragmatic test (no platform channel):

```dart
test('ensureVisible calls show when already attached', () {
  final session = ImeSession(
    onCommit: (_) {},
    onPreeditChanged: (_) {},
    onBackspace: () {},
  );
  // Use TestDefaultBinaryMessenger / mock TextInput if the package already
  // does for lifecycle tests; otherwise add:
  // session.debugForceAttachedConnection(FakeConn())
  // ...
  session.ensureVisible();
  expect(fake.showCount, 1);
  session.ensureVisible();
  expect(fake.showCount, 2);
});

test('hide calls connection hide without detach', () {
  // attached → hide → still isAttached, hideCount==1
});
```

If mocking `TextInput.attach` is heavy, add:

```dart
@visibleForTesting
void debugBindConnection(TextInputConnection conn) { _conn = conn; }
```

and a minimal fake implementing `show`/`hide`/`attached`/`close`/`setEditingState`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/flutter_alacritty && flutter test test/ime_session_test.dart --name ensureVisible`  
Expected: FAIL (method missing)

- [ ] **Step 3: Implement**

```dart
/// Force the soft keyboard visible. Safe when already attached (unlike [attach]).
void ensureVisible() {
  if (!isAttached) {
    attach();
    return;
  }
  _conn!.show();
}

/// Hide the soft keyboard without closing the TextInput client.
void hide() {
  _conn?.hide();
}
```

Keep `attach()` showing on first attach. Do not early-return from `ensureVisible` when attached.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client/packages/flutter_alacritty && flutter test test/ime_session_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/packages/flutter_alacritty/lib/input/ime_session.dart \
  client/packages/flutter_alacritty/test/ime_session_test.dart
git commit -m "feat(alacritty): ImeSession ensureVisible and hide"
```

---

### Task 2: `ModifierLatch`

**Files:**
- Create: `client/packages/flutter_alacritty/lib/input/modifier_latch.dart`
- Test: `client/packages/flutter_alacritty/test/modifier_latch_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_alacritty/input/modifier_latch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toggle ctrl and consumeAfterSend clears only used flags', () {
    final latch = ModifierLatch();
    latch.toggleCtrl();
    expect(latch.ctrl, isTrue);
    latch.consumeAfterSend();
    expect(latch.ctrl, isFalse);
  });

  test('second toggleCtrl clears without consume', () {
    final latch = ModifierLatch();
    latch.toggleCtrl();
    latch.toggleCtrl();
    expect(latch.ctrl, isFalse);
  });

  test('clear resets all', () {
    final latch = ModifierLatch();
    latch.toggleCtrl();
    latch.toggleAlt();
    latch.clear();
    expect(latch.ctrl, isFalse);
    expect(latch.alt, isFalse);
  });

  test('notifies listeners on change', () {
    final latch = ModifierLatch();
    var n = 0;
    latch.addListener(() => n++);
    latch.toggleCtrl();
    expect(n, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/flutter_alacritty && flutter test test/modifier_latch_test.dart`  
Expected: FAIL (library not found)

- [ ] **Step 3: Implement**

```dart
import 'package:flutter/foundation.dart';

/// Sticky virtual modifiers for touch accessory keys.
class ModifierLatch extends ChangeNotifier {
  bool ctrl = false;
  bool alt = false;
  bool shift = false;

  void toggleCtrl() {
    ctrl = !ctrl;
    notifyListeners();
  }

  void toggleAlt() {
    alt = !alt;
    notifyListeners();
  }

  void toggleShift() {
    shift = !shift;
    notifyListeners();
  }

  void clear() {
    if (!ctrl && !alt && !shift) return;
    ctrl = false;
    alt = false;
    shift = false;
    notifyListeners();
  }

  /// Auto-off after an effective send that consumed the latch.
  void consumeAfterSend() => clear();
}
```

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/flutter_alacritty/lib/input/modifier_latch.dart \
  client/packages/flutter_alacritty/test/modifier_latch_test.dart
git commit -m "feat(alacritty): ModifierLatch for sticky virtual modifiers"
```

---

### Task 3: `TerminalKeyInjector`

**Files:**
- Create: `client/packages/flutter_alacritty/lib/input/terminal_key_injector.dart`
- Test: `client/packages/flutter_alacritty/test/terminal_key_injector_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_alacritty/input/key_input.dart';
import 'package:flutter_alacritty/input/modifier_latch.dart';
import 'package:flutter_alacritty/input/terminal_key_injector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('injectText with ctrl latch sends Ctrl+C then clears', () {
    final writes = <Uint8List>[];
    final latch = ModifierLatch()..toggleCtrl();
    final inj = TerminalKeyInjector(
      latch: latch,
      modeFlags: () => 0,
      write: writes.add,
      resetComposing: () {},
      isComposing: () => false,
    );
    inj.injectText('c');
    expect(writes.single, Uint8List.fromList([0x03]));
    expect(latch.ctrl, isFalse);
  });

  test('injectKey arrowUp with ctrl latch sends CSI with mod then clears', () {
    final writes = <Uint8List>[];
    final latch = ModifierLatch()..toggleCtrl();
    final inj = TerminalKeyInjector(
      latch: latch,
      modeFlags: () => 0,
      write: writes.add,
      resetComposing: () {},
      isComposing: () => false,
    );
    inj.injectKey(LogicalKeyboardKey.arrowUp);
    final expected = encodeKey(
      LogicalKeyboardKey.arrowUp,
      null,
      ctrl: true,
      modeFlags: 0,
    )!;
    expect(writes.single, expected);
    expect(latch.ctrl, isFalse);
  });

  test('injectKey while composing resets composing first', () {
    var resets = 0;
    final inj = TerminalKeyInjector(
      latch: ModifierLatch(),
      modeFlags: () => 0,
      write: (_) {},
      resetComposing: () => resets++,
      isComposing: () => true,
    );
    inj.injectKey(LogicalKeyboardKey.escape);
    expect(resets, 1);
  });

  test('multi-byte UTF-8 commit with latch writes UTF-8 and clears latch', () {
    final writes = <Uint8List>[];
    final latch = ModifierLatch()..toggleCtrl();
    final inj = TerminalKeyInjector(
      latch: latch,
      modeFlags: () => 0,
      write: writes.add,
      resetComposing: () {},
      isComposing: () => false,
    );
    inj.injectText('你');
    expect(writes.single, Uint8List.fromList(utf8.encode('你')));
    expect(latch.ctrl, isFalse);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

`injectText` rules:
- If latch has ctrl/alt/shift **and** `text` is a single BMP letter/digit/symbol that `encodeKey` can control-encode (prefer: length==1 and code unit in printable ASCII), call `encodeKey(LogicalKeyboardKey keyFromChar, char, ctrl/alt/shift from latch, modeFlags)`.
- Else write `utf8.encode(text)`.
- If any latch flag was set before send, `consumeAfterSend()`.

`injectKey`:
- If composing → `resetComposing()`.
- `encodeKey(key, null, shift/alt/ctrl from latch, modeFlags)`; write if non-null; consume latch if any was set.

No-op when write would throw — caller passes safe write. Injector itself should not catch broadly; `write` callback may no-op if engine dead.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/flutter_alacritty/lib/input/terminal_key_injector.dart \
  client/packages/flutter_alacritty/test/terminal_key_injector_test.dart
git commit -m "feat(alacritty): TerminalKeyInjector merges modifier latch"
```

---

### Task 4: Accessory key model + `serverBoxDualRow` layout + touch heuristic

**Files:**
- Create: `client/packages/flutter_alacritty/lib/input/terminal_accessory_key.dart`
- Create: `client/packages/flutter_alacritty/lib/input/terminal_accessory_layout.dart`
- Create: `client/packages/flutter_alacritty/lib/input/touch_shell.dart`
- Test: `client/packages/flutter_alacritty/test/terminal_accessory_layout_test.dart`
- Test: `client/packages/flutter_alacritty/test/touch_shell_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// touch_shell_test.dart
test('android and iOS are touch shells', () {
  expect(isTouchShell(platform: TargetPlatform.android), isTrue);
  expect(isTouchShell(platform: TargetPlatform.iOS), isTrue);
  expect(isTouchShell(platform: TargetPlatform.linux), isFalse);
  expect(isTouchShell(platform: TargetPlatform.macOS), isFalse);
  expect(isTouchShell(platform: TargetPlatform.windows), isFalse);
});

// terminal_accessory_layout_test.dart
test('serverBoxDualRow has two rows with expected keys', () {
  final layout = TerminalAccessoryLayout.serverBoxDualRow;
  expect(layout.rows.length, 2);
  expect(layout.rows[0].map((k) => k.id), ['esc', 'alt', 'home', 'up', 'end']);
  expect(layout.rows[1].map((k) => k.id),
      ['tab', 'ctrl', 'left', 'down', 'right', 'ime']);
});
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement sealed/data keys**

```dart
enum TerminalAccessoryActionId { toggleIme }

sealed class TerminalAccessoryKey {
  const TerminalAccessoryKey({required this.id, this.label, this.icon});
  final String id;
  final String? label;
  final IconData? icon;
}

final class AccessoryLatchKey extends TerminalAccessoryKey {
  const AccessoryLatchKey.ctrl() : this._('ctrl', ModifierKind.ctrl, label: 'Ctrl');
  // alt, shift similarly
  final ModifierKind kind;
}

final class AccessoryInjectKey extends TerminalAccessoryKey {
  const AccessoryInjectKey({
    required super.id,
    required this.logicalKey,
    super.label,
    super.icon,
    this.repeatable = false,
  });
  final LogicalKeyboardKey logicalKey;
  final bool repeatable;
}

final class AccessoryInjectRaw extends TerminalAccessoryKey {
  const AccessoryInjectRaw({
    required super.id,
    required this.bytes,
    super.label,
    super.icon,
  });
  final List<int> bytes;
}

final class AccessoryActionKey extends TerminalAccessoryKey {
  const AccessoryActionKey({
    required super.id,
    required this.action,
    super.label,
    super.icon,
  });
  final TerminalAccessoryActionId action;
}

class TerminalAccessoryLayout {
  const TerminalAccessoryLayout(this.rows);
  final List<List<TerminalAccessoryKey>> rows;

  static final serverBoxDualRow = TerminalAccessoryLayout([
    [
      AccessoryInjectKey(id: 'esc', logicalKey: LogicalKeyboardKey.escape, label: 'Esc'),
      AccessoryLatchKey.alt(),
      AccessoryInjectKey(id: 'home', logicalKey: LogicalKeyboardKey.home, label: 'Home'),
      AccessoryInjectKey(id: 'up', logicalKey: LogicalKeyboardKey.arrowUp, icon: Icons.arrow_upward, repeatable: true),
      AccessoryInjectKey(id: 'end', logicalKey: LogicalKeyboardKey.end, label: 'End'),
    ],
    [
      AccessoryInjectKey(id: 'tab', logicalKey: LogicalKeyboardKey.tab, label: 'Tab'),
      AccessoryLatchKey.ctrl(),
      AccessoryInjectKey(id: 'left', logicalKey: LogicalKeyboardKey.arrowLeft, icon: Icons.arrow_back, repeatable: true),
      AccessoryInjectKey(id: 'down', logicalKey: LogicalKeyboardKey.arrowDown, icon: Icons.arrow_downward, repeatable: true),
      AccessoryInjectKey(id: 'right', logicalKey: LogicalKeyboardKey.arrowRight, icon: Icons.arrow_forward, repeatable: true),
      AccessoryActionKey(id: 'ime', action: TerminalAccessoryActionId.toggleIme, icon: Icons.keyboard),
    ],
  ]);
}
```

```dart
// touch_shell.dart
import 'package:flutter/foundation.dart';

bool isTouchShell({TargetPlatform? platform}) {
  final p = platform ?? defaultTargetPlatform;
  return p == TargetPlatform.android || p == TargetPlatform.iOS;
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/flutter_alacritty/lib/input/terminal_accessory_key.dart \
  client/packages/flutter_alacritty/lib/input/terminal_accessory_layout.dart \
  client/packages/flutter_alacritty/lib/input/touch_shell.dart \
  client/packages/flutter_alacritty/test/terminal_accessory_layout_test.dart \
  client/packages/flutter_alacritty/test/touch_shell_test.dart
git commit -m "feat(alacritty): accessory key model and touch shell heuristic"
```

---

### Task 5: Wire IME ensureVisible into touch tap + blur clears latch

**Files:**
- Modify: `client/packages/flutter_alacritty/lib/ui/terminal_view.dart`
- Modify: `client/packages/flutter_alacritty/lib/ui/terminal_view_pointer.dart`
- Test: `client/packages/flutter_alacritty/test/terminal_touch_ime_test.dart` (new)

- [ ] **Step 1: Write failing widget/unit test**

Extend lifecycle/IME tests if a focus+tap harness exists (`terminal_lifecycle_test.dart`). New focused test:

```dart
testWidgets('touch tap calls ensureVisible even when already focused', (tester) async {
  // Pump TerminalView with FakeEngine; attach IME via focus;
  // spy ensureVisible via debug counter on ImeSession or wrapper;
  // tap terminal; expect ensureVisible >= 1 while hasFocus stays true.
});
```

Also unit-level: after `_handleImeFocusChange` loses focus, latch is cleared — test by exposing `modifierLatchForTest` when latch is non-null.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

1. Add optional `ModifierLatch? modifierLatch` on `TerminalView` (host enables).
2. Create `TerminalKeyInjector?` in state when latch != null.
3. `__pointerOnTouchTap`: keep `requestFocus`; add `_ime.ensureVisible()`.
4. `_handleImeFocusChange` else branch: `_ime.detach(); widget.modifierLatch?.clear();`
5. `_writeCommittedText`: if injector present, `injector.injectText(t)` else existing UTF-8 write.
6. Hardware `_onKeyFallback`: **do not** OR latch flags (OS modifiers only).

Expose for tests:

```dart
@visibleForTesting
ImeSession get imeForTest => _ime; // already exists
@visibleForTesting
ModifierLatch? get modifierLatchForTest => widget.modifierLatch;
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/flutter_alacritty/lib/ui/terminal_view.dart \
  client/packages/flutter_alacritty/lib/ui/terminal_view_pointer.dart \
  client/packages/flutter_alacritty/test/terminal_touch_ime_test.dart
git commit -m "feat(alacritty): touch tap ensureVisible and latch on blur"
```

---

### Task 6: `TerminalAccessoryBar` widget

**Files:**
- Create: `client/packages/flutter_alacritty/lib/ui/terminal_accessory_bar.dart`
- Test: `client/packages/flutter_alacritty/test/terminal_accessory_bar_test.dart`

- [ ] **Step 1: Write failing test**

```dart
testWidgets('ctrl tap toggles latch highlight', (tester) async {
  final latch = ModifierLatch();
  final injected = <LogicalKeyboardKey>[];
  await tester.pumpWidget(MaterialApp(
    home: TerminalAccessoryBar(
      layout: TerminalAccessoryLayout.serverBoxDualRow,
      latch: latch,
      onInjectKey: injected.add,
      onToggleIme: () {},
    ),
  ));
  await tester.tap(find.text('Ctrl'));
  await tester.pump();
  expect(latch.ctrl, isTrue);
  await tester.tap(find.text('Esc'));
  await tester.pump();
  expect(injected, [LogicalKeyboardKey.escape]);
});

testWidgets('repeatable arrow starts periodic inject on long press', (tester) async {
  // long-press up; advance 400ms + 2*137ms; expect inject count >= 3
});
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement unstyled bar**

- `Column` of `Row`s from `layout.rows`
- Each key: `InkWell` / `GestureDetector`
  - latch → toggle + rebuild via `ListenableBuilder`
  - inject → `onInjectKey` (parent routes through injector: focus + inject)
  - ime action → `onToggleIme`
- Long-press: `Timer` after 400ms, then `Timer.periodic(137ms)` while down; cancel on up/cancel
- Selected latch: use `ColorScheme.primary` when Material present; fallback `Colors.blue`

Keep styling minimal — TeamPilot can wrap with `Theme` / decoration later.

API:

```dart
class TerminalAccessoryBar extends StatefulWidget {
  const TerminalAccessoryBar({
    required this.layout,
    required this.latch,
    required this.onInjectKey,
    required this.onToggleIme,
    this.onBeforeKey,
    this.heightPerRow = 36,
    super.key,
  });
  // onBeforeKey: optional () { requestFocus(); ensureVisible(); }
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/flutter_alacritty/lib/ui/terminal_accessory_bar.dart \
  client/packages/flutter_alacritty/test/terminal_accessory_bar_test.dart
git commit -m "feat(alacritty): TerminalAccessoryBar with sticky and repeat"
```

---

### Task 7: Export public API + compose accessory under `TerminalView` (optional slot)

**Files:**
- Modify: `client/packages/flutter_alacritty/lib/flutter_alacritty.dart`
- Modify: `client/packages/flutter_alacritty/lib/ui/terminal_view.dart` (optional `showAccessoryBar` / `accessoryLayout`)

**Decision for clean architecture:** Prefer **composition outside** `TerminalView` in the TeamPilot shell (`Column(Expanded(TerminalView), bar)`), so `TerminalView` stays grid-only. Do **not** bake the bar into `TerminalView.build` unless tests prove focus/`viewInsets` require it.

Exports to add:

```dart
export 'input/modifier_latch.dart';
export 'input/terminal_key_injector.dart';
export 'input/terminal_accessory_key.dart';
export 'input/terminal_accessory_layout.dart';
export 'input/touch_shell.dart';
export 'ui/terminal_accessory_bar.dart';
```

Still pass `modifierLatch` into `TerminalView` so IME commit merges.

- [ ] **Step 1: Add export + a smoke test that imports from package root**

- [ ] **Step 2–4: Implement exports; run `flutter test` for new files**

- [ ] **Step 5: Commit**

```bash
git add client/packages/flutter_alacritty/lib/flutter_alacritty.dart
git commit -m "feat(alacritty): export accessory keyboard public API"
```

---

### Task 8: Enable in `TeampilotAlacrittyTerminal`

**Files:**
- Modify: `client/lib/widgets/terminal/teampilot_alacritty_terminal.dart`
- Create: `client/test/widgets/terminal/teampilot_alacritty_terminal_accessory_test.dart`

- [ ] **Step 1: Write failing test**

`TeampilotAlacrittyTerminal` requires `ShortcutCubit` + `SessionPreferencesCubit` (via `context.watch`). Wrap with `MultiBlocProvider` in the test, **or** extract a private/public `TeampilotTerminalAccessoryHost` (Column + latch + bar) and test that host with `debugDefaultTargetPlatformOverride` while keeping the shell as thin wiring.

```dart
testWidgets('shows accessory bar on android touch shell', (tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  // Pump host or full terminal with MultiBlocProvider stubs;
  // expect find.text('Ctrl') / find.text('Esc').
});

testWidgets('hides accessory bar on linux desktop', (tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  // expect find.text('Ctrl'), findsNothing);
});
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

Convert `TeampilotAlacrittyTerminal` to `StatefulWidget` (or wrap with a private `StatefulWidget`) when `isTouchShell()`:

```dart
final latch = ModifierLatch();
return Column(
  children: [
    Expanded(
      child: ShortcutFocus(
        kind: ShortcutFocusKind.terminal,
        child: TerminalWithHistoryScrollbar(
          ...
          child: TerminalView(..., modifierLatch: latch, ...),
        ),
      ),
    ),
    TerminalAccessoryBar(
      layout: TerminalAccessoryLayout.serverBoxDualRow,
      latch: latch,
      onBeforeKey: () {
        // request focus via TerminalViewState key if available
        terminalViewKey... ensureVisible via public method if added
      },
      onInjectKey: (key) { /* need injector access */ },
      onToggleIme: () { /* show/hide */ },
    ),
  ],
);
```

**Focus/inject bridge:** Add on `TerminalViewState`:

```dart
void ensureKeyboardVisible() => _ime.ensureVisible();
void hideKeyboard() => _ime.hide();
void injectLogicalKey(LogicalKeyboardKey key) => _injector?.injectKey(key)
    ?? /* encode without latch */;
bool get isKeyboardAttached => _ime.isAttached;
```

Expose via `GlobalKey<TerminalViewState>` already used as `terminalViewKey` in places — type the key as `GlobalKey<TerminalViewState>` when accessory enabled, or add a small `TerminalInputHandle` passed from view state upward.

Cleaner: create `TerminalInputHandle` owned by state, passed to bar:

```dart
abstract class TerminalInputHandle {
  void ensureKeyboardVisible();
  void hideKeyboard();
  void injectKey(LogicalKeyboardKey key);
  void injectText(String text);
  bool get isComposing;
}
```

`TerminalView` constructs handle wrapping injector+ime; host holds it via callback `onInputHandleCreated`.

Minimal path for this task: `GlobalKey<TerminalViewState>` + public methods on state (package already exposes `imeForTest` pattern).

IME toggle:

```dart
var imeShown = true;
onToggleIme: () {
  if (imeShown) {
    key.currentState?.hideKeyboard();
    imeShown = false;
  } else {
    key.currentState?.ensureKeyboardVisible();
    imeShown = true;
  }
}
```

Theme: wrap bar in `Material(color: theme.colorScheme.surfaceContainerHigh)` + `SafeArea(top: false)`.

- [ ] **Step 4: Run app + package tests — expect PASS**

Run:
```bash
cd client/packages/flutter_alacritty && flutter test test/modifier_latch_test.dart test/terminal_key_injector_test.dart test/terminal_accessory_bar_test.dart test/terminal_accessory_layout_test.dart test/touch_shell_test.dart test/ime_session_test.dart
cd client && flutter test test/widgets/terminal/teampilot_alacritty_terminal_accessory_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/terminal/teampilot_alacritty_terminal.dart \
  client/test/widgets/terminal/teampilot_alacritty_terminal_accessory_test.dart \
  client/packages/flutter_alacritty/lib/ui/terminal_view.dart
git commit -m "feat(terminal): enable touch accessory bar in TeampilotAlacrittyTerminal"
```

---

### Task 9: Verification sweep

- [ ] **Step 1: Run package tests**

```bash
cd client/packages/flutter_alacritty && flutter test
```

Expected: PASS (or only pre-existing failures unrelated — do not ignore new failures)

- [ ] **Step 2: Run client analyze + targeted tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/widgets/terminal/ --exclude-tags integration
```

- [ ] **Step 3: Manual checklist (Android device/emulator)**

1. Open session terminal → tap → soft keyboard opens  
2. Dismiss keyboard → tap again → opens again  
3. Ctrl then `c` → process interrupt (`\x03`)  
4. Esc / Tab / arrows work in `vim`/`less` or shell readline  
5. ⌨ toggles keyboard; bar remains  
6. Desktop Linux build: no bar  

- [ ] **Step 4: Final commit if any fixes**

```bash
git commit -m "fix(terminal): polish touch accessory keyboard edge cases"
```

---

## Notes for implementers

- Do **not** copy ServerBox source (AGPL).
- Latch applies to **IME commit + accessory inject** only; hardware `onKeyEvent` keeps OS modifiers.
- Chat workbench and workspace dock both use `TeampilotAlacrittyTerminal` — no per-page bars.
- Prefer small files; avoid growing `terminal_view.dart` further without extracting injector wiring to a private extension/part if the diff exceeds ~80 lines of new logic in one method cluster.
