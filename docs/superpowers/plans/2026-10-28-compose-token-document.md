# Compose Token Document Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make compose tokens first-class atomic objects created only by explicit insertion, so nothing is inferred from text with a regex.

**Architecture:** A `ComposeTextController` owns a `ComposeTokenDocument` (ranges + kind + payload). Every text mutation is diffed into a single splice; ranges shift or dissolve, never re-derive. Rendering (`TpTokenTextField` / `TpTokenChipMirror`) receives explicit ranges instead of a `RegExp`. Tokens are serialized back to plain text for the CLI, so the wire format is unchanged.

**Tech Stack:** Flutter 3.47, Dart, `shared_ui` submodule (`client/packages/shared_ui`), existing compose stack (`ComposeTriggerField`, `WorkspaceComposeCard`).

## Global Constraints

- Never run `flutter test` directly. Use `cd client && dart run tool/run_tests.dart <paths>`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- `shared_ui` is a submodule: commit there first, then bump the parent gitlink in the same parent commit.
- l10n only via `client/lib/l10n/app_en.arb` / `app_zh.arb`.
- Compose message wire format stays plain text (`@path`, `/skill`, `/command`); no markers in the text.
- Pasted text is always plain text. Only explicit insertion creates a token.
- Draft persistence stores `{text, tokens}`; a restored token is kept only when its saved slice still matches the text. Legacy plain-string drafts load without tokens.

---

## File Structure

**Create**

- `client/lib/services/chat/conversation/compose/compose_token_document.dart` — token value types, splice diff, range transform.
- `client/lib/services/chat/conversation/compose/compose_text_controller.dart` — controller that owns the document, exposes insertion APIs, restores documents on undo/redo.
- `client/test/services/chat/conversation/compose/compose_token_document_test.dart`
- `client/test/services/chat/conversation/compose/compose_text_controller_test.dart`

**Modify (app)**

- `client/lib/widgets/compose/compose_trigger_field.dart` — controller type, insert through the document, pass ranges to shared_ui, remove regex.
- `client/lib/widgets/compose/workspace_compose_card.dart` — controller type, at-file chip row from tokens.
- `client/lib/services/chat/conversation/compose/compose_file_attach.dart` — `insertComposeReferences` creates tokens.
- `client/lib/pages/chat/session_chat_view.dart`, `client/lib/pages/chat/session_chat_compose_section.dart`, `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart` — controller type.
- `client/lib/services/chat/conversation/compose/compose_at_file_refs.dart` — add `composeAtFileRefsFromTokens`; keep the regex parser only for legacy tests.
- `client/lib/services/chat/conversation/compose/compose_trigger_token_edit.dart` — delete (no runtime users left).

**Modify (shared_ui submodule)**

- `lib/src/components/token_field/tp_token_text_field.dart`
- `lib/src/components/token_field/tp_token_chip_mirror.dart`
- `lib/src/components/token_field/tp_token_edit.dart`
- `test/components/token_field/tp_token_text_field_test.dart`

---

### Task 1: Compose token document

**Files:**
- Create: `client/lib/services/chat/conversation/compose/compose_token_document.dart`
- Test: `client/test/services/chat/conversation/compose/compose_token_document_test.dart`

**Interfaces:**
- Produces:
  - `enum ComposeTokenKind { fileReference, skill, command }`
  - `class ComposeToken { String id; ComposeTokenKind kind; int start; int end; String payload; }`
  - `class ComposeTokenDocument { List<ComposeToken> tokens; ComposeTokenDocument applyEdit(String oldText, String newText); ComposeTokenDocument add(ComposeToken token); ComposeToken? tokenForBackspace(int offset); ComposeToken? tokenForDelete(int offset); List<TextRange> get ranges; }`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_token_document.dart';

ComposeToken token(int start, int end, {String payload = '@a'}) => ComposeToken(
  id: '$start-$end',
  kind: ComposeTokenKind.fileReference,
  start: start,
  end: end,
  payload: payload,
);

void main() {
  test('insert after token shifts nothing and keeps the token', () {
    final doc = ComposeTokenDocument.empty.add(token(0, 2)); // '@a hello'
    final next = doc.applyEdit('@a ', '@a b');
    expect(next.tokens.single.range, const TextRange(start: 0, end: 2));
  });

  test('insert before token shifts the token', () {
    final doc = ComposeTokenDocument.empty.add(token(2, 4)); // 'x @a'
    final next = doc.applyEdit('x @a', 'xy @a');
    expect(next.tokens.single.range, const TextRange(start: 3, end: 5));
  });

  test('typing inside a token dissolves it', () {
    final doc = ComposeTokenDocument.empty.add(token(0, 3)); // '@ab'
    final next = doc.applyEdit('@ab', '@aXb');
    expect(next.tokens, isEmpty);
  });

  test('typing at token end keeps the token', () {
    final doc = ComposeTokenDocument.empty.add(token(0, 3));
    final next = doc.applyEdit('@ab', '@abX');
    expect(next.tokens.single.range, const TextRange(start: 0, end: 3));
  });

  test('deleting the trailing space keeps the token', () {
    final doc = ComposeTokenDocument.empty.add(token(0, 3));
    final next = doc.applyEdit('@ab ', '@ab');
    expect(next.tokens.single.range, const TextRange(start: 0, end: 3));
  });

  test('deleting into the token dissolves it', () {
    final doc = ComposeTokenDocument.empty.add(token(0, 3));
    final next = doc.applyEdit('@ab', '@b');
    expect(next.tokens, isEmpty);
  });

  test('replacing text after a token keeps it', () {
    final doc = ComposeTokenDocument.empty.add(token(0, 3));
    final next = doc.applyEdit('@ab old', '@ab new');
    expect(next.tokens.single.range, const TextRange(start: 0, end: 3));
  });

  test('clearing text drops every token', () {
    final doc = ComposeTokenDocument.empty
        .add(token(0, 3))
        .add(token(5, 8, payload: '@c'));
    expect(doc.applyEdit('@ab @c ', '').tokens, isEmpty);
  });

  test('backspace/delete boundaries resolve whole token', () {
    final doc = ComposeTokenDocument.empty.add(token(2, 5));
    expect(doc.tokenForBackspace(5)?.range, const TextRange(start: 2, end: 5));
    expect(doc.tokenForBackspace(2), isNull);
    expect(doc.tokenForDelete(2)?.range, const TextRange(start: 2, end: 5));
    expect(doc.tokenForDelete(5), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart test/services/chat/conversation/compose/compose_token_document_test.dart
```
Expected: compile error, `compose_token_document.dart` not found.

- [ ] **Step 3: Write the implementation**

```dart
import 'dart:math' as math;

import 'package:flutter/services.dart';

enum ComposeTokenKind { fileReference, skill, command }

class ComposeToken {
  const ComposeToken({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
    required this.payload,
  });

  final String id;
  final ComposeTokenKind kind;
  final int start;
  final int end;
  final String payload;

  TextRange get range => TextRange(start: start, end: end);

  ComposeToken shift(int delta) => ComposeToken(
    id: id,
    kind: kind,
    start: start + delta,
    end: end + delta,
    payload: payload,
  );
}

/// Ranges of tokens created by explicit insertion. Text is the only storage;
/// ranges are the authority for rendering and atomic edits.
class ComposeTokenDocument {
  const ComposeTokenDocument._(this.tokens);

  static const empty = ComposeTokenDocument._(<ComposeToken>[]);

  final List<ComposeToken> tokens;

  List<TextRange> get ranges => [for (final token in tokens) token.range];

  ComposeTokenDocument add(ComposeToken token) {
    final next = [...tokens, token]..sort((a, b) => a.start.compareTo(b.start));
    return ComposeTokenDocument._(next);
  }

  ComposeToken? tokenForBackspace(int offset) {
    for (final token in tokens) {
      if (offset > token.start && offset <= token.end) return token;
    }
    return null;
  }

  ComposeToken? tokenForDelete(int offset) {
    for (final token in tokens) {
      if (offset >= token.start && offset < token.end) return token;
    }
    return null;
  }

  /// Applies one text change. Insertions strictly inside a token, and any
  /// deletion that touches a token, dissolve it — the user edited the token's
  /// text, so it is no longer the object that was inserted.
  ComposeTokenDocument applyEdit(String oldText, String newText) {
    if (oldText == newText) return this;
    final splice = _singleSplice(oldText, newText);
    final replaceStart = splice.start;
    final replaceEnd = splice.start + splice.removed;
    final out = <ComposeToken>[];
    for (final token in tokens) {
      final intersects = splice.removed == 0
          ? token.start < replaceStart && replaceStart < token.end
          : replaceStart < token.end && token.start < replaceEnd;
      if (intersects) continue;
      out.add(replaceEnd <= token.start ? token.shift(splice.delta) : token);
    }
    return ComposeTokenDocument._(out);
  }
}

class _Splice {
  const _Splice(this.start, this.removed, this.inserted);

  final int start;
  final int removed;
  final String inserted;

  int get delta => inserted.length - removed;
}

_Splice _singleSplice(String oldText, String newText) {
  final maxPrefix = math.min(oldText.length, newText.length);
  var prefix = 0;
  while (prefix < maxPrefix &&
      oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < maxPrefix - prefix &&
      oldText.codeUnitAt(oldText.length - 1 - suffix) ==
          newText.codeUnitAt(newText.length - 1 - suffix)) {
    suffix++;
  }
  return _Splice(
    prefix,
    oldText.length - prefix - suffix,
    newText.substring(prefix, newText.length - suffix),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd client && dart run tool/run_tests.dart test/services/chat/conversation/compose/compose_token_document_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/conversation/compose/compose_token_document.dart \
  client/test/services/chat/conversation/compose/compose_token_document_test.dart
git commit -m "feat(compose): add token document with splice-based range tracking"
```

---

### Task 2: Compose text controller

**Files:**
- Create: `client/lib/services/chat/conversation/compose/compose_text_controller.dart`
- Test: `client/test/services/chat/conversation/compose/compose_text_controller_test.dart`

**Interfaces:**
- Consumes: `ComposeToken`, `ComposeTokenKind`, `ComposeTokenDocument` from Task 1.
- Produces:
  - `class ComposeTextController extends TextEditingController`
  - `ComposeTokenDocument get document`
  - `List<TextRange> get tokenRanges`
  - `void insertToken({required int start, required int end, required String tokenText, String suffix = ' ', required ComposeTokenKind kind, required String payload})`
  - `void insertReferences(Iterable<String> references)`
  - history: typing back a previous full text restores that text's document (undo/redo).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_text_controller.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_token_document.dart';

void main() {
  test('typed @text is not a token', () {
    final controller = ComposeTextController();
    controller.text = '@src/main.dart hello';
    expect(controller.document.tokens, isEmpty);
    expect(controller.tokenRanges, isEmpty);
  });

  test('insertToken registers range and keeps the suffix outside', () {
    final controller = ComposeTextController();
    controller.text = '/pl';
    controller.selection = const TextSelection.collapsed(offset: 3);
    controller.insertToken(
      start: 0,
      end: 3,
      tokenText: '/plan',
      kind: ComposeTokenKind.skill,
      payload: 'plan',
    );
    expect(controller.text, '/plan ');
    expect(controller.tokenRanges, [const TextRange(start: 0, end: 5)]);
  });

  test('insertToken at end of an existing token keeps both', () {
    final controller = ComposeTextController();
    controller.text = '@a ';
    controller.selection = const TextSelection.collapsed(offset: 3);
    controller.insertToken(
      start: 0,
      end: 2,
      tokenText: '@a',
      kind: ComposeTokenKind.fileReference,
      payload: '@a',
    );
    expect(controller.tokenRanges, [const TextRange(start: 0, end: 2)]);
  });

  test('typing after a token does not extend it', () {
    final controller = ComposeTextController();
    controller.text = '/plan';
    controller.selection = const TextSelection.collapsed(offset: 5);
    controller.insertToken(
      start: 0,
      end: 5,
      tokenText: '/plan',
      suffix: '',
      kind: ComposeTokenKind.command,
      payload: 'plan',
    );
    controller.text = '/plan帮我看看';
    expect(controller.tokenRanges, [const TextRange(start: 0, end: 5)]);
  });

  test('insertReferences creates one token per reference with separators', () {
    final controller = ComposeTextController();
    controller.text = 'run';
    controller.selection = const TextSelection.collapsed(offset: 3);
    controller.insertReferences(['@a.txt', '@b.txt']);
    expect(controller.text, 'run @a.txt @b.txt ');
    expect(controller.tokenRanges, [
      const TextRange(start: 4, end: 10),
      const TextRange(start: 11, end: 17),
    ]);
  });

  test('undo restores the token document for a previous text', () {
    final controller = ComposeTextController();
    controller.text = '/pl';
    controller.selection = const TextSelection.collapsed(offset: 3);
    controller.insertToken(
      start: 0,
      end: 3,
      tokenText: '/plan',
      kind: ComposeTokenKind.skill,
      payload: 'plan',
    );
    controller.text = '';
    expect(controller.tokenRanges, isEmpty);
    controller.text = '/plan ';
    expect(controller.tokenRanges, [const TextRange(start: 0, end: 5)]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart test/services/chat/conversation/compose/compose_text_controller_test.dart
```
Expected: compile error, controller not found.

- [ ] **Step 3: Write the implementation**

```dart
import 'dart:collection';

import 'package:flutter/services.dart';

import 'compose_token_document.dart';

/// Compose text controller that keeps explicit token ranges in sync with the
/// text. Nothing is inferred from the text: a token exists only because
/// [insertToken] / [insertReferences] created it.
class ComposeTextController extends TextEditingController {
  ComposeTextController({super.text});

  static const _historyLimit = 200;

  ComposeTokenDocument _document = ComposeTokenDocument.empty;
  var _nextTokenId = 0;
  final _history = <String, ComposeTokenDocument>{};
  final _historyOrder = Queue<String>();

  ComposeTokenDocument get document => _document;

  List<TextRange> get tokenRanges => _document.ranges;

  @override
  set value(TextEditingValue newValue) {
    final oldText = super.value.text;
    if (newValue.text != oldText) {
      final restored = _history[newValue.text];
      _document = restored ?? _document.applyEdit(oldText, newValue.text);
      _remember(newValue.text, _document);
    }
    super.value = newValue;
  }

  /// Replaces [start]..[end] with [tokenText] + [suffix] and records a token
  /// covering exactly [tokenText]. The suffix stays plain text.
  void insertToken({
    required int start,
    required int end,
    required String tokenText,
    String suffix = ' ',
    required ComposeTokenKind kind,
    required String payload,
  }) {
    final old = super.value;
    final replacement = '$tokenText$suffix';
    final next = old.copyWith(
      text: old.text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
      composing: TextRange.empty,
    );
    final shifted = _document.applyEdit(old.text, next.text);
    final token = ComposeToken(
      id: '${_nextTokenId++}',
      kind: kind,
      start: start,
      end: start + tokenText.length,
      payload: payload,
    );
    _document = shifted.add(token);
    _remember(next.text, _document);
    super.value = next;
  }

  /// Inserts `@` references as tokens, separated by one space, with a leading
  /// separator when the caret is not already at a space.
  void insertReferences(Iterable<String> references) {
    final refs = references
        .map((reference) => reference.trim())
        .where((reference) => reference.isNotEmpty)
        .toList(growable: false);
    if (refs.isEmpty) return;

    final old = super.value;
    final selection = old.selection.isValid
        ? old.selection
        : TextSelection.collapsed(offset: old.text.length);
    final wantsPrefix =
        selection.start > 0 && old.text[selection.start - 1] != ' ';
    final buffer = StringBuffer();
    var offset = selection.start + (wantsPrefix ? 1 : 0);
    final tokens = <ComposeToken>[];
    if (wantsPrefix) buffer.write(' ');
    for (var index = 0; index < refs.length; index++) {
      if (index > 0) {
        buffer.write(' ');
        offset++;
      }
      tokens.add(
        ComposeToken(
          id: '${_nextTokenId++}',
          kind: ComposeTokenKind.fileReference,
          start: offset,
          end: offset + refs[index].length,
          payload: refs[index],
        ),
      );
      buffer.write(refs[index]);
      offset += refs[index].length;
    }
    buffer.write(' ');
    final replacement = buffer.toString();
    final next = old.copyWith(
      text: old.text.replaceRange(selection.start, selection.end, replacement),
      selection: TextSelection.collapsed(
        offset: selection.start + replacement.length,
      ),
      composing: TextRange.empty,
    );
    var nextDocument = _document.applyEdit(old.text, next.text);
    for (final token in tokens) {
      nextDocument = nextDocument.add(token);
    }
    _document = nextDocument;
    _remember(next.text, _document);
    super.value = next;
  }

  void _remember(String text, ComposeTokenDocument document) {
    if (_history.containsKey(text)) {
      _historyOrder.remove(text);
    }
    _history[text] = document;
    _historyOrder.addLast(text);
    while (_historyOrder.length > _historyLimit) {
      _history.remove(_historyOrder.removeFirst());
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd client && dart run tool/run_tests.dart test/services/chat/conversation/compose/compose_text_controller_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/conversation/compose/compose_text_controller.dart \
  client/test/services/chat/conversation/compose/compose_text_controller_test.dart
git commit -m "feat(compose): add token-owning compose controller"
```

---

### Task 3: shared_ui consumes ranges instead of a regex

**Files (submodule `client/packages/shared_ui`):**
- Modify: `lib/src/components/token_field/tp_token_edit.dart`
- Modify: `lib/src/components/token_field/tp_token_chip_mirror.dart`
- Modify: `lib/src/components/token_field/tp_token_text_field.dart`
- Modify: `test/components/token_field/tp_token_text_field_test.dart`

**Interfaces:**
- Produces:
  - `TpTokenRange({int start, int end})` unchanged.
  - `Iterable<TpTokenRange> tpTokenRanges(String text, RegExp pattern)` stays (test helper).
  - `TpTokenRange? tpTokenRangeForBackspace(Iterable<TpTokenRange> ranges, int offset)`
  - `TpTokenRange? tpTokenRangeForDelete(Iterable<TpTokenRange> ranges, int offset)`
  - `TextEditingValue? applyTpTokenBackspace(TextEditingValue value, Iterable<TpTokenRange> ranges)`
  - `TextEditingValue? applyTpTokenDelete(TextEditingValue value, Iterable<TpTokenRange> ranges)`
  - `TpTokenTextField.tokenRanges: List<TpTokenRange>`
  - `TpTokenChipMirror.tokenRanges: List<TpTokenRange>`
  - `buildTpTokenMirrorLayoutSpans({required List<TpTokenRange> tokenRanges, ...})`
  - `buildTpTokenPillOverlays({required List<TpTokenRange> tokenRanges, ...})`

- [ ] **Step 1: Write the failing test**

Add to `test/components/token_field/tp_token_text_field_test.dart`:

```dart
test('applyTpTokenBackspace uses explicit ranges only', () {
  const value = TextEditingValue(
    text: '@a typed',
    selection: TextSelection.collapsed(offset: 2),
  );
  // '@a' typed by hand: no ranges -> plain backspace.
  expect(applyTpTokenBackspace(value, const []), isNull);

  final deleted = applyTpTokenBackspace(
    const TextEditingValue(
      text: '@a typed',
      selection: TextSelection.collapsed(offset: 2),
    ),
    const [TpTokenRange(start: 0, end: 2)],
  );
  expect(deleted?.text, ' typed');
});

test('buildTpTokenMirrorLayoutSpans paints only explicit ranges', () {
  const style = TextStyle(fontSize: 14, color: Colors.black);
  final spans = buildTpTokenMirrorLayoutSpans(
    text: '@a typed',
    baseStyle: style,
    tokenRanges: const [TpTokenRange(start: 0, end: 2)],
    colorScheme: const ColorScheme.light(),
    resolvePalette: (token, scheme) =>
        (background: Colors.blue, foreground: Colors.white),
  );
  expect((spans.first as TextSpan).text, '@a');
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client/packages/shared_ui && flutter test test/components/token_field/tp_token_text_field_test.dart
```
Expected: compile errors for unknown named parameters / argument types.
(Submodule tests are run with `flutter test` inside the package; this is not `client/`, so the `tool/run_tests.dart` rule does not apply.)

- [ ] **Step 3: Change `tp_token_edit.dart` to range inputs**

Replace the bodies that take `RegExp pattern` with range inputs:

```dart
TpTokenRange? tpTokenRangeForBackspace(
  Iterable<TpTokenRange> ranges,
  int offset,
) {
  for (final token in ranges) {
    if (offset > token.start && offset <= token.end) return token;
  }
  return null;
}

TpTokenRange? tpTokenRangeForDelete(
  Iterable<TpTokenRange> ranges,
  int offset,
) {
  for (final token in ranges) {
    if (offset >= token.start && offset < token.end) return token;
  }
  return null;
}

TextRange expandRangeToTpTokens({
  required int start,
  required int end,
  required Iterable<TpTokenRange> tokenRanges,
}) {
  var expandedStart = start;
  var expandedEnd = end;
  for (final token in tokenRanges) {
    if (token.end <= expandedStart || token.start >= expandedEnd) continue;
    if (token.start < expandedStart) expandedStart = token.start;
    if (token.end > expandedEnd) expandedEnd = token.end;
  }
  return TextRange(start: expandedStart, end: expandedEnd);
}
```

Update `tpTokenSelectionForBackspace`, `tpTokenSelectionForDelete`,
`applyTpTokenBackspace`, and `applyTpTokenDelete` to take
`Iterable<TpTokenRange> ranges` and call the range helpers (drop the `pattern`
argument and the `text` argument from `expandRangeToTpTokens` calls).

`tpTokenRanges(String text, RegExp pattern)` stays unchanged for tests and
legacy callers.

- [ ] **Step 4: Change the mirror to ranges**

In `tp_token_chip_mirror.dart`:

- Replace `final RegExp tokenPattern;` with
  `final List<TpTokenRange> tokenRanges;` on `TpTokenChipMirror`.
- `buildTpTokenMirrorLayoutSpans`:

```dart
List<InlineSpan> buildTpTokenMirrorLayoutSpans({
  required String text,
  required TextStyle baseStyle,
  required List<TpTokenRange> tokenRanges,
  ColorScheme? colorScheme,
  TpTokenPaletteResolver? resolvePalette,
}) {
  if (text.isEmpty) return [TextSpan(text: '', style: baseStyle)];
  final sorted = [...tokenRanges]..sort((a, b) => a.start.compareTo(b.start));
  final spans = <InlineSpan>[];
  var start = 0;
  for (final range in sorted) {
    if (range.start < start) continue; // defensive: ignore overlap
    if (range.start > start) {
      spans.add(TextSpan(text: text.substring(start, range.start), style: baseStyle));
    }
    final token = text.substring(range.start, range.end);
    final foreground = (colorScheme != null && resolvePalette != null)
        ? resolvePalette(token, colorScheme).foreground
        : (baseStyle.color ?? Colors.black);
    spans.add(TextSpan(text: token, style: baseStyle.copyWith(color: foreground)));
    start = range.end;
  }
  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start), style: baseStyle));
  }
  return spans;
}
```

- `buildTpTokenPillOverlays` iterates `tokenRanges` instead of
  `tokenPattern.allMatches(text)`; each `range` replaces `match.start` /
  `match.end` and `token` becomes `text.substring(range.start, range.end)`.
- `TpTokenChipMirror` passes `tokenRanges` through.

- [ ] **Step 5: Change `TpTokenTextField` to ranges**

- Replace the `tokenPattern` field with `final List<TpTokenRange> tokenRanges;`.
- `_buildEditorStack`: `final showChipMirror = widget.tokenRanges.isNotEmpty;`
- Backspace/Delete: `applyTpTokenBackspace(widget.controller.value, widget.tokenRanges)` and the delete variant.
- Mirror: `tokenRanges: widget.tokenRanges`.
- The `token` passed to `resolveTokenPalette` inside the mirror is the substring
  (already handled in Step 4).

- [ ] **Step 6: Update shared_ui tests and run them**

Replace every `tokenPattern: / pattern:` argument in the token-field tests with
an explicit range list built from the same pattern:

```dart
final ranges = tpTokenRanges(text, pattern)
    .map((range) => TpTokenRange(start: range.start, end: range.end))
    .toList();
```

Run:

```bash
cd client/packages/shared_ui && flutter test test/components/token_field/
```
Expected: `All tests passed!`

- [ ] **Step 7: Commit the submodule**

```bash
cd client/packages/shared_ui
git add lib test
git commit -m "feat(token-field): render explicit token ranges instead of regex matches"
cd ../../..
git add client/packages/shared_ui
git commit -m "chore: bump shared_ui for explicit token ranges"
```

---

### Task 4: Compose field uses the controller document

**Files:**
- Modify: `client/lib/widgets/compose/compose_trigger_field.dart`
- Modify: `client/test/widgets/compose/compose_trigger_field_test.dart`

**Interfaces:**
- Consumes: `ComposeTextController.document`, `.tokenRanges`, `.insertToken(...)`.
- Produces: `ComposeTriggerField.controller` is `ComposeTextController`.

- [ ] **Step 1: Update the test harness and add failing cases**

Change `required TextEditingController controller` to
`required ComposeTextController controller` in `pumpField`, and every
`TextEditingController()` in the file to `ComposeTextController()`.
Add:

```dart
testWidgets('a hand-typed @mention never becomes a chip', (tester) async {
  final controller = ComposeTextController();
  await pumpField(... controller: controller ...);
  controller.text = '@src/main.dart';
  await tester.pump();
  expect(controller.tokenRanges, isEmpty);
});

testWidgets('selected token keeps its chip when typing after a space', (tester) async {
  final controller = ComposeTextController();
  await pumpField(... controller: controller ...);
  await tester.enterText(find.byType(TextField), '/pl');
  await tester.pumpAndSettle(const Duration(milliseconds: 200));
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
  expect(controller.tokenRanges, [const TextRange(start: 0, end: 5)]);
  controller.text = '/plan 你好';
  await tester.pump();
  expect(controller.tokenRanges, [const TextRange(start: 0, end: 5)]);
});
```

- [ ] **Step 2: Run and verify failure**

```bash
cd client && dart run tool/run_tests.dart test/widgets/compose/compose_trigger_field_test.dart
```
Expected: type errors (`TextEditingController` is not a `ComposeTextController`).

- [ ] **Step 3: Implement**

- Change the widget field type to `ComposeTextController`.
- `_selectSuggestion`:

```dart
final (tokenText, suffix, kind, payload) = switch (suggestion) {
  ComposeTriggerFileSuggestion(:final candidate) => (
    candidate.insertText,
    ' ',
    ComposeTokenKind.fileReference,
    candidate.insertText,
  ),
  ComposeTriggerSlashSuggestion(:final candidate) => (
    candidate.insertText,
    candidate.insertionSuffix,
    candidate.kind == ComposeSlashCandidateKind.skill
        ? ComposeTokenKind.skill
        : ComposeTokenKind.command,
    candidate.insertText,
  ),
};
widget.controller.insertToken(
  start: trigger.triggerStart,
  end: trigger.triggerEnd,
  tokenText: tokenText,
  suffix: suffix,
  kind: kind,
  payload: payload,
);
```

Remove the `replaceComposeTrigger` import and call.
- Pass `tokenRanges: widget.controller.tokenRanges
    .map((range) => TpTokenRange(start: range.start, end: range.end))
    .toList()` to `TpTokenTextField`.
- Import `compose_text_controller.dart` and `compose_token_document.dart`.

- [ ] **Step 4: Run the field tests**

```bash
cd client && dart run tool/run_tests.dart test/widgets/compose/compose_trigger_field_test.dart
```
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/compose/compose_trigger_field.dart \
  client/test/widgets/compose/compose_trigger_field_test.dart
git commit -m "feat(compose): insert tokens through the document model"
```

---

### Task 5: Attach / drop / parents create tokens

**Files:**
- Modify: `client/lib/services/chat/conversation/compose/compose_file_attach.dart`
- Modify: `client/lib/widgets/compose/workspace_compose_card.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Modify: `client/lib/pages/chat/session_chat_compose_section.dart`
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`
- Test: `client/test/widgets/compose/workspace_compose_card_test.dart`,
  `client/test/services/chat/conversation/compose/compose_file_attach_test.dart`

**Interfaces:**
- Produces: `void insertComposeReferences(ComposeTextController controller, Iterable<String> references)`.
- Produces: `List<ComposeAtFileRef> composeAtFileRefsFromTokens({required List<ComposeToken> tokens, required String workspaceRoot, required bool usesPosixPaths})` in `compose_at_file_refs.dart`.

- [ ] **Step 1: Write the failing test**

In `test/services/chat/conversation/compose/compose_file_attach_test.dart` add:

```dart
test('insertComposeReferences registers file tokens', () {
  final controller = ComposeTextController();
  controller.text = 'run';
  controller.selection = const TextSelection.collapsed(offset: 3);
  insertComposeReferences(controller, ['@a.txt', '@b.txt']);
  expect(controller.text, 'run @a.txt @b.txt ');
  expect(controller.document.tokens.length, 2);
  expect(
    controller.document.tokens.every(
      (token) => token.kind == ComposeTokenKind.fileReference,
    ),
    isTrue,
  );
});
```

- [ ] **Step 2: Run and verify failure**

```bash
cd client && dart run tool/run_tests.dart test/services/chat/conversation/compose/compose_file_attach_test.dart
```
Expected: type error (`ComposeTextController` not accepted).

- [ ] **Step 3: Implement**

- `insertComposeReferences(ComposeTextController controller, Iterable<String> references)` → `controller.insertReferences(references);` (delete the old manual string build).
- Change `pickAndInsertComposeFileReferences`, `pasteComposeImageAttachment`,
  `resolveComposeFileReference` callers to pass `ComposeTextController`.
- `WorkspaceComposeCard.controller` → `ComposeTextController`.
- `SessionChatComposeSection.composeController` → `ComposeTextController` and
  the helper at line 685.
- `SessionChatView._controller` / `UnboundComposeBody._controller` →
  `ComposeTextController()`.
- `SessionVoiceController.composeController` may stay `TextEditingController`
  (it only writes values, and the override still runs).
- In `WorkspaceComposeCard`, replace the `parseComposeAtFileRefs(...)` block:

```dart
final refs = composeAtFileRefsFromTokens(
  tokens: controller.document.tokens
      .where((token) => token.kind == ComposeTokenKind.fileReference)
      .toList(growable: false),
  workspaceRoot: workspaceRoot,
  usesPosixPaths: homeStorageOf(context).usesPosixPaths,
);
```

- Add `composeAtFileRefsFromTokens` to `compose_at_file_refs.dart`:

```dart
List<ComposeAtFileRef> composeAtFileRefsFromTokens({
  required List<ComposeToken> tokens,
  required String workspaceRoot,
  required bool usesPosixPaths,
}) {
  final seen = <String>{};
  final out = <ComposeAtFileRef>[];
  for (final token in tokens) {
    if (token.kind != ComposeTokenKind.fileReference) continue;
    final body = token.payload.startsWith('@')
        ? token.payload.substring(1)
        : token.payload;
    final absolute = resolveComposeAtFileAbsolutePath(
      body,
      workspaceRoot: workspaceRoot,
      usesPosixPaths: usesPosixPaths,
    );
    if (absolute.isEmpty) continue;
    if (!seen.add(_pathKey(absolute))) continue;
    out.add(
      ComposeAtFileRef(
        absolutePath: absolute,
        displayName: p.basename(absolute),
      ),
    );
  }
  return out;
}
```

- [ ] **Step 4: Update fakes/stubs in tests and run**

Run:

```bash
cd client && dart run tool/run_tests.dart test/widgets/compose/ \
  test/services/chat/conversation/compose/ \
  test/pages/chat/session_chat_workspace_bundle_test.dart
```
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/conversation/compose client/lib/widgets/compose \
  client/lib/pages/chat client/lib/pages/home_workspace/workspace/unbound_compose_body.dart \
  client/test
git commit -m "feat(compose): create file tokens from attach, drop and paste"
```

---

### Task 6: Remove runtime regex token paths

**Files:**
- Delete: `client/lib/services/chat/conversation/compose/compose_trigger_token_edit.dart`
- Modify: `client/lib/services/inline_token/inline_token_palette.dart` (keep the
  pattern only as a documented legacy parser, or delete if unused)
- Modify: `client/lib/services/chat/conversation/compose/compose_at_file_refs.dart`
- Test: `client/test/services/inline_token/inline_token_chip_mirror_test.dart`,
  `client/test/services/chat/conversation/compose/compose_at_file_refs_test.dart`

**Interfaces:**
- `defaultInlineTokenPattern` remains exported only as a compatibility helper;
  no runtime compose path calls it.

- [ ] **Step 1: Prove no runtime users remain**

```bash
cd client && grep -rn "defaultInlineTokenPattern\|composeTokenRanges\|parseComposeAtFileRefs" lib
```
Expected: only `inline_token_palette.dart` (definition) and legacy helpers.

- [ ] **Step 2: Delete `compose_trigger_token_edit.dart` and its imports/tests**

```bash
rm client/lib/services/chat/conversation/compose/compose_trigger_token_edit.dart
grep -rn "compose_trigger_token_edit" client/lib client/test
```
Remove every import; delete the tests that only exercised regex helpers.

- [ ] **Step 3: Run the affected suites**

```bash
cd client && dart run tool/run_tests.dart test/services/inline_token/ \
  test/services/chat/conversation/compose/ test/widgets/compose/
```
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add -A client/lib client/test
git commit -m "refactor(compose): drop regex-derived tokens from the runtime path"
```

---

### Task 7: Regression coverage and full verification

**Files:**
- Modify: `client/test/widgets/compose/compose_trigger_field_test.dart`
- Modify: `client/test/widgets/compose/workspace_compose_card_test.dart`

- [ ] **Step 1: Add the end-to-end regressions**

```dart
testWidgets('pasted absolute path stays plain text', (tester) async {
  final controller = ComposeTextController();
  await pumpField(... controller: controller ...);
  await tester.enterText(
    find.byType(TextField),
    '/home/me/report.pdf 帮我总结',
  );
  await tester.pump();
  expect(controller.tokenRanges, isEmpty);
});

testWidgets('backspace deletes an inserted token as one unit', (tester) async {
  final controller = ComposeTextController();
  await pumpField(... controller: controller ...);
  await tester.enterText(find.byType(TextField), '/pl');
  await tester.pumpAndSettle(const Duration(milliseconds: 200));
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
  controller.selection = const TextSelection.collapsed(offset: 5);
  await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
  await tester.pump();
  expect(controller.text, '');
  expect(controller.tokenRanges, isEmpty);
});
```

- [ ] **Step 2: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```
Expected: no new issues in touched files.

- [ ] **Step 3: Full suite (background)**

```bash
cd client && dart run tool/run_tests.dart
```
Expected: all pass except pre-existing failures unrelated to compose
(`managed_provider_usage_panel_test.dart` is known-red in this worktree).

- [ ] **Step 4: Commit**

```bash
git add client/test
git commit -m "test(compose): cover token document regressions"
```

---

### Task 8: Persist token ranges and polish interaction

**Files:**
- Add: `client/lib/services/chat/conversation/compose/compose_draft.dart`
- Modify: `compose_draft_cache.dart`, `compose_draft_store.dart`,
  `compose_text_controller.dart`, `session_chat_view.dart`,
  `unbound_compose_body.dart`
- Modify (shared_ui): arrow-key token skip + stadium chip radius.

- [x] Draft JSON stores `{text, tokens}`; legacy strings still decode.
- [x] `ComposeTextController.restoreDocument` validates slices and drops stale
  tokens.
- [x] Left/Right (and Shift+Left/Right) step over a whole token.
- [x] Chip pill radius is half its height (stadium), not a fixed 6px.

- [ ] **Step 2: Grep docs for stale regex claims**

```bash
cd /home/hhoa/git/hhoa/teampilot && grep -rn "tokenPattern\|@.*token\|inline token" docs README.md client/docs 2>/dev/null
```
Update any sentence that claims compose tokens are regex-derived.

- [ ] **Step 3: Commit**

```bash
git add client/lib/services/chat/conversation/compose/compose_draft_cache.dart docs
git commit -m "docs(compose): record explicit-token and plain-text-draft invariant"
```

---

## Self-Review Notes

- Spec coverage: atomic token creation (Tasks 1-4), insertion paths (Task 4-5), no regex at runtime (Task 6), regressions (Task 7), draft semantics (Task 8).
- Intentional non-goals: rich-text node editor, atomic arrow navigation (add later), token-aware undo beyond text-snapshot restore, draft token persistence.
- Type consistency: `ComposeTextController` is the only controller type passed to compose widgets and file-attachment helpers; `TpTokenRange` is the only shared_ui token input after Task 3.
