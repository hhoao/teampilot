# Clickable File Paths in the Embedded Terminal — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make file paths printed by embedded CLIs (e.g. Claude Code's `● Read(lib/foo.dart)`) clickable in the terminal — Ctrl/Cmd+click opens the file in TeamPilot's in-app editor — but only after the path is confirmed to exist on the session filesystem.

**Architecture:** `flutter_alacritty` gains an IO-free, host-injectable **link-provider seam** (`TerminalLinkProvider`): the View scans visible lines via providers, decorates only spans a provider reports *enabled*, and emits `onLinkActivate(payload)` on Ctrl+click. The library ships a default `UrlLinkProvider` (replacing the Rust URL hint regex; the engine keeps only OSC 8). The engine also parses **OSC 7** into `engine.cwd`. TeamPilot supplies `FilePathLinkProvider`, which does the path regex + async `Filesystem.stat` validation + cwd resolution, and routes activation through the existing `TerminalUriOpener` → editor.

**Tech Stack:** Dart / Flutter, `flutter_bloc`, `flutter_alacritty` (Rust engine via flutter_rust_bridge), `package:path`.

**Spec:** `docs/superpowers/specs/2026-06-15-clickable-file-paths-design.md`

**Pre-flight (per CODE_QUALITY):** After any Rust/FRB change, run `cd client && flutter build linux --debug` (or the platform's build) before `flutter test`, because widget/engine tests load the native lib. Library tests live under `client/packages/flutter_alacritty/test/`; TeamPilot tests under `client/test/`.

---

## File Structure

```
flutter_alacritty/lib/
  links/terminal_link_provider.dart   NEW  LinkSpan + TerminalLinkProvider (ChangeNotifier)
  links/url_link_provider.dart        NEW  default URL provider (ex-Rust regex)
  links/link_overlay.dart             NEW  LinkOverlay: per-frame enabled-cell lookup for the painter
  render/terminal_painter.dart        MOD  consult LinkOverlay alongside kFlagHyperlink
  ui/terminal_view.dart               MOD  linkProviders param; decoration recompute (debounced);
                                           hover + Ctrl+click hit-test; provider listen/dispose
  engine/terminal_engine.dart         MOD  cwd: ValueListenable<String?>  (+ OSC 7 wiring)
  flutter_alacritty.dart              MOD  export the new link/* symbols
  example/example_app.dart            MOD  pass linkProviders: [UrlLinkProvider()]
  rust/src/engine.rs + api/terminal.rs MOD  remove URL hint pass; emit OSC 7 cwd event

client/lib/services/terminal/
  file_path_link_provider.dart        NEW  path regex + async fs validation + cache + cwd
  (terminal_uri_opener.dart)          REUSED as-is (resolveLocalFilePath + open + openInEditor)
client/lib/pages/chat/chat_workbench_terminal.dart   MOD  build providers + onLinkActivate
client/lib/widgets/workspace_terminal_panel.dart     MOD  same wiring where it hosts TerminalView
```

---

## PHASE 1 — Library link-provider seam (Dart only)

### Task 1: `LinkSpan` + `TerminalLinkProvider`

**Files:**
- Create: `client/packages/flutter_alacritty/lib/links/terminal_link_provider.dart`
- Test: `client/packages/flutter_alacritty/test/links/terminal_link_provider_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/links/terminal_link_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubProvider extends TerminalLinkProvider {
  final Set<String> enabled = {};
  @override
  Iterable<LinkSpan> scan(String lineText) =>
      lineText.contains('X') ? [const LinkSpan(start: 0, end: 1, payload: 'X')] : const [];
  @override
  bool isEnabled(LinkSpan span) => enabled.contains(span.payload);
  void confirm(String p) { enabled.add(p); notifyListeners(); }
}

void main() {
  test('LinkSpan holds range + payload', () {
    const s = LinkSpan(start: 2, end: 5, payload: 'a/b.dart');
    expect(s.start, 2);
    expect(s.end, 5);
    expect(s.payload, 'a/b.dart');
    expect(s.contains(3), isTrue);
    expect(s.contains(5), isFalse); // half-open [start, end)
  });

  test('provider scan + isEnabled gate, notifies on confirm', () {
    final p = _StubProvider();
    final span = p.scan('aXb').single;
    expect(p.isEnabled(span), isFalse);
    var notified = 0;
    p.addListener(() => notified++);
    p.confirm('X');
    expect(notified, 1);
    expect(p.isEnabled(span), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/flutter_alacritty && flutter test test/links/terminal_link_provider_test.dart`
Expected: FAIL — `terminal_link_provider.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:flutter/foundation.dart';

/// A half-open column range `[start, end)` on a single visible line, with an
/// opaque [payload] handed back to the host on activation.
@immutable
class LinkSpan {
  const LinkSpan({required this.start, required this.end, required this.payload});

  final int start;
  final int end;
  final String payload;

  /// Whether column [col] falls inside this span (half-open).
  bool contains(int col) => col >= start && col < end;
}

/// Host-injectable link source for [TerminalView].
///
/// The View calls [scan] (sync, cheap) over each visible line's text and
/// [isEnabled] (sync) before decorating a span. Providers that confirm links
/// asynchronously (e.g. filesystem validation) mutate their own state and call
/// [notifyListeners]; the View listens and recomputes decorations.
///
/// The library performs NO IO on a provider's behalf — keeping
/// flutter_alacritty embeddable and IO-free (Plan 2W library-seam principle).
abstract class TerminalLinkProvider extends ChangeNotifier {
  /// Synchronous candidate detection over one rendered line's text.
  Iterable<LinkSpan> scan(String lineText);

  /// Synchronous gate: should this candidate be drawn/clickable *now*?
  /// Async providers return false until their cache confirms the payload.
  bool isEnabled(LinkSpan span);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client/packages/flutter_alacritty && flutter test test/links/terminal_link_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/flutter_alacritty/lib/links/terminal_link_provider.dart \
        client/packages/flutter_alacritty/test/links/terminal_link_provider_test.dart
git commit -m "feat(alacritty): add TerminalLinkProvider seam"
```

---

### Task 2: `UrlLinkProvider` (library default)

**Files:**
- Create: `client/packages/flutter_alacritty/lib/links/url_link_provider.dart`
- Test: `client/packages/flutter_alacritty/test/links/url_link_provider_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_alacritty/links/url_link_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const p = UrlLinkProvider();

  test('detects http/https/ftp/file URLs with correct ranges', () {
    final spans = p.scan('see https://x.io/p and file:///a/b done').toList();
    expect(spans.map((s) => s.payload),
        containsAll(['https://x.io/p', 'file:///a/b']));
    final url = spans.firstWhere((s) => s.payload == 'https://x.io/p');
    expect('see https://x.io/p and file:///a/b done'.substring(url.start, url.end),
        'https://x.io/p');
  });

  test('no scheme => no spans', () {
    expect(p.scan('just plain words here'), isEmpty);
  });

  test('URLs are always enabled (no validation)', () {
    final span = p.scan('https://x.io').single;
    expect(p.isEnabled(span), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/flutter_alacritty && flutter test test/links/url_link_provider_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'terminal_link_provider.dart';

/// Default link provider shipped by the library: detects bare URLs in rendered
/// text. Replaces the engine's former Rust hint-regex pass. Always enabled —
/// URLs need no filesystem validation. Activation handling (launching) is the
/// host's job via `TerminalView.onLinkActivate`.
class UrlLinkProvider extends TerminalLinkProvider {
  UrlLinkProvider();

  // Same pattern the Rust hint pass used (alacritty default subset).
  static final RegExp _pattern =
      RegExp(r'(?:https?|ftp|file)://[^\s]+', caseSensitive: false);

  @override
  Iterable<LinkSpan> scan(String lineText) sync* {
    for (final m in _pattern.allMatches(lineText)) {
      yield LinkSpan(start: m.start, end: m.end, payload: m.group(0)!);
    }
  }

  @override
  bool isEnabled(LinkSpan span) => true;
}
```

Note: `UrlLinkProvider` extends a `ChangeNotifier` but never notifies — that is fine; it is a stable provider.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client/packages/flutter_alacritty && flutter test test/links/url_link_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/flutter_alacritty/lib/links/url_link_provider.dart \
        client/packages/flutter_alacritty/test/links/url_link_provider_test.dart
git commit -m "feat(alacritty): UrlLinkProvider as library default link source"
```

---

### Task 3: `LinkOverlay` + painter consults it

**Files:**
- Create: `client/packages/flutter_alacritty/lib/links/link_overlay.dart`
- Test: `client/packages/flutter_alacritty/test/links/link_overlay_test.dart`
- Modify: `client/packages/flutter_alacritty/lib/render/terminal_painter.dart` (the two `kFlagHyperlink` checks at lines ~66 and ~196-205)

- [ ] **Step 1: Write the failing test for `LinkOverlay`**

```dart
import 'package:flutter_alacritty/links/link_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('overlay reports enabled cells per row, half-open ranges', () {
    final o = LinkOverlay({
      0: const [LinkCellRange(start: 4, end: 9)],
    });
    expect(o.isLinkCell(0, 4), isTrue);
    expect(o.isLinkCell(0, 8), isTrue);
    expect(o.isLinkCell(0, 9), isFalse);
    expect(o.isLinkCell(0, 3), isFalse);
    expect(o.isLinkCell(1, 5), isFalse);
  });

  test('empty overlay is a const sentinel', () {
    expect(LinkOverlay.empty.isLinkCell(0, 0), isFalse);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client/packages/flutter_alacritty && flutter test test/links/link_overlay_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement `LinkOverlay`**

```dart
/// A confirmed link column range on one viewport row (half-open `[start, end)`).
class LinkCellRange {
  const LinkCellRange({required this.start, required this.end});
  final int start;
  final int end;
  bool contains(int col) => col >= start && col < end;
}

/// Immutable per-frame map of viewport-row -> enabled link ranges. Built by
/// [TerminalView] from enabled provider spans and read by [TerminalPainter] so
/// host-provided links underline like OSC 8 hyperlinks without touching grid flags.
class LinkOverlay {
  const LinkOverlay(this._rows);
  final Map<int, List<LinkCellRange>> _rows;

  static const LinkOverlay empty = LinkOverlay(<int, List<LinkCellRange>>{});

  bool isLinkCell(int row, int col) {
    final ranges = _rows[row];
    if (ranges == null) return false;
    for (final r in ranges) {
      if (r.contains(col)) return true;
    }
    return false;
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd client/packages/flutter_alacritty && flutter test test/links/link_overlay_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire the painter to consult the overlay**

In `terminal_painter.dart`:
1. Add a field + constructor param: `final LinkOverlay linkOverlay;` defaulting to `LinkOverlay.empty` (import `../links/link_overlay.dart`).
2. The `effectiveFgBg` helper (line ~57-66) currently keys hyperlink styling off `flags & kFlagHyperlink`. Extend the call sites in `paint()` (lines ~147 and ~176) to OR in the overlay: compute a local `final bool linkCell = (flags & kFlagHyperlink != 0) || linkOverlay.isLinkCell(row, col);` and pass an effective flag. Simplest: just before the decoration block (line ~196), compute `final int effFlags = linkCell ? (flags | kFlagHyperlink) : flags;` and use `effFlags` for BOTH the `effectiveFgBg` precedence call and the underline check at lines ~196-205. Do not mutate the grid; `effFlags` is a local.

Concretely, replace the underline gate:
```dart
// was: if (flags & (kFlagUnderline | kFlagStrikeout | kFlagHyperlink) != 0) {
final bool overlayLink = linkOverlay.isLinkCell(row, col);
final int effFlags = overlayLink ? (flags | kFlagHyperlink) : flags;
if (effFlags & (kFlagUnderline | kFlagStrikeout | kFlagHyperlink) != 0) {
```
and use `effFlags` in the `effectiveFgBg(...)` call for this cell.

3. `shouldRepaint`: add `|| oldDelegate.linkOverlay != linkOverlay`.

- [ ] **Step 6: Add a painter unit test for overlay decoration**

In an existing painter test file (`test/terminal_painter_test.dart`), add a case asserting that a cell with no `kFlagHyperlink` but covered by `LinkOverlay({row:[range]})` takes the hint fg/bg via `effectiveFgBg`-equivalent. (Follow the existing `_withSearch`/precedence test pattern in that file.)

- [ ] **Step 7: Run painter tests**

Run: `cd client/packages/flutter_alacritty && flutter test test/terminal_painter_test.dart test/links/link_overlay_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add client/packages/flutter_alacritty/lib/links/link_overlay.dart \
        client/packages/flutter_alacritty/lib/render/terminal_painter.dart \
        client/packages/flutter_alacritty/test/links/link_overlay_test.dart \
        client/packages/flutter_alacritty/test/terminal_painter_test.dart
git commit -m "feat(alacritty): painter consults LinkOverlay for host links"
```

---

### Task 4: `TerminalView` — providers, decoration recompute, hover, Ctrl+click

**Files:**
- Modify: `client/packages/flutter_alacritty/lib/ui/terminal_view.dart`
- Test: `client/packages/flutter_alacritty/test/terminal_view_callback_test.dart` (extend)

- [ ] **Step 1: Add the `linkProviders` param and lifecycle**

In `TerminalView`:
```dart
/// Host-injectable link sources. Defaults to a single URL provider so plain
/// xterm consumers keep clickable URLs for free. Pass `const []` to disable.
final List<TerminalLinkProvider> linkProviders;
```
Constructor default: `this.linkProviders = const [UrlLinkProvider()]` (import the two link files + `link_overlay.dart`).

In `_TerminalViewState`:
- Field `LinkOverlay _linkOverlay = LinkOverlay.empty;` and `Timer? _linkDebounce;`.
- `initState`: `for (final p in widget.linkProviders) p.addListener(_recomputeLinksNow);` and listen to the grid (`_engine.grid` / mirror `Listenable`) to schedule recompute: in the existing grid listener add `_scheduleLinkRecompute();`.
- `didUpdateWidget`: if `widget.linkProviders` identity changed, remove old listeners + add new.
- `dispose`: `_linkDebounce?.cancel(); for (final p in oldProviders) p.removeListener(_recomputeLinksNow);` (do NOT dispose providers — the host owns them).

- [ ] **Step 2: Implement debounced recompute**

```dart
void _scheduleLinkRecompute() {
  _linkDebounce?.cancel();
  _linkDebounce = Timer(const Duration(milliseconds: 120), _recomputeLinksNow);
}

void _recomputeLinksNow() {
  if (!mounted || widget.linkProviders.isEmpty) {
    if (_linkOverlay != LinkOverlay.empty) setState(() => _linkOverlay = LinkOverlay.empty);
    return;
  }
  final rows = <int, List<LinkCellRange>>{};
  for (var row = 0; row < _grid.rows; row++) {
    final text = _lineText(row);
    if (text.trim().isEmpty) continue;
    final ranges = <LinkCellRange>[];
    for (final provider in widget.linkProviders) {
      for (final span in provider.scan(text)) {
        if (provider.isEnabled(span)) {
          ranges.add(LinkCellRange(start: span.start, end: span.end));
        }
      }
    }
    if (ranges.isNotEmpty) rows[row] = ranges;
  }
  final next = LinkOverlay(rows);
  setState(() => _linkOverlay = next);
}

String _lineText(int row) {
  final sb = StringBuffer();
  for (var c = 0; c < _grid.columns; c++) {
    final cp = _grid.codepointAt(row, c);
    sb.writeCharCode(cp == 0 ? 32 : cp);
  }
  return sb.toString();
}
```
Pass `linkOverlay: _linkOverlay` into the `TerminalPainter(...)` construction in `build()`.

- [ ] **Step 3: Hover cursor for overlay links**

`_updateHoverCursor(local)` currently derives `hyperlink` from `_engine.hyperlinkAt(r,c) != null` (see `_cursorFor`/line ~67). Extend it to also be true when `_linkOverlay.isLinkCell(r, c)`:
```dart
final (r, c, _) = _cellAt(local);
final isLink = _engine.hyperlinkAt(r, c) != null || _linkOverlay.isLinkCell(r, c);
// feed isLink where the existing code passed the OSC8 hyperlink bool
```

- [ ] **Step 4: Ctrl+click hit-test for overlay links**

In `_onPointerDown` (line ~870-878), after the existing OSC 8 branch returns nothing, fall through to overlay resolution:
```dart
if ((hw.isControlPressed || hw.isMetaPressed) && e.buttons & kPrimaryButton != 0) {
  final (r, c, _) = _cellAt(e.localPosition);
  final uri = _engine.hyperlinkAt(r, c);
  if (uri != null) { widget.onLinkActivate?.call(uri); return; }
  final payload = _payloadAt(r, c);     // NEW
  if (payload != null) { widget.onLinkActivate?.call(payload); return; }
}
```
where:
```dart
String? _payloadAt(int row, int col) {
  if (!_linkOverlay.isLinkCell(row, col)) return null;
  final text = _lineText(row);
  for (final provider in widget.linkProviders) {
    for (final span in provider.scan(text)) {
      if (provider.isEnabled(span) && span.contains(col)) return span.payload;
    }
  }
  return null;
}
```

- [ ] **Step 5: Write/extend the widget test**

In `terminal_view_callback_test.dart`, add: pump a `TerminalView` with a stub provider whose `scan` returns a span for a known line and `isEnabled` returns true; feed the engine that line; pump past 120ms; Ctrl+click the span's cell → assert `onLinkActivate` fired with the payload. Add a second case: `isEnabled` false → Ctrl+click does nothing. (Reuse the fake binding + existing pump helpers in that test file.)

- [ ] **Step 6: Run**

Run: `cd client/packages/flutter_alacritty && flutter test test/terminal_view_callback_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/packages/flutter_alacritty/lib/ui/terminal_view.dart \
        client/packages/flutter_alacritty/test/terminal_view_callback_test.dart
git commit -m "feat(alacritty): TerminalView link providers + overlay decoration/click"
```

---

### Task 5: Remove the Rust URL hint pass; export new symbols; example app default

**Files:**
- Modify: `client/packages/flutter_alacritty/rust/src/engine.rs` (`engine_full_snapshot_searched` hint pass) + `rust/src/api/terminal.rs`
- Modify: `client/packages/flutter_alacritty/lib/flutter_alacritty.dart` (exports)
- Modify: `client/packages/flutter_alacritty/lib/example/example_app.dart`

- [ ] **Step 1: Remove the URL auto-detect hint pass in Rust**

In `engine.rs`, delete the hint-regex pass added by Plan 2K (the `RegexIter`/`hint_regex` block in `engine_full_snapshot_searched` that ORs `FLAG_HYPERLINK` onto regex-matched cells) and the `hint_regex` field + its construction. **Keep** OSC 8 hyperlink interning (`hyperlinks` / `hyperlink_ids` / `cell.hyperlink()`), `cell_data` id assignment, and `engine_resolve_hyperlink`. URL detection now lives in `UrlLinkProvider`.

- [ ] **Step 2: Regenerate FRB + build**

Run: `cd client/packages/flutter_alacritty && flutter_rust_bridge_codegen generate` (or the repo's codegen task), then `cd client && flutter build linux --debug`.
Expected: builds clean; engine still exposes `engine_resolve_hyperlink`.

- [ ] **Step 3: Export new symbols**

In `flutter_alacritty.dart` add:
```dart
export 'links/terminal_link_provider.dart';
export 'links/url_link_provider.dart';
export 'links/link_overlay.dart';
```

- [ ] **Step 4: Example app passes the default provider**

In `example_app.dart`, where it builds `TerminalView(...)`, the default already supplies `[UrlLinkProvider()]`; make it explicit for the reference: `linkProviders: [UrlLinkProvider()]`. Ensure the existing `onLinkActivate: (uri) => launchUrl(...)` still launches URLs (unchanged).

- [ ] **Step 5: Run the library suite**

Run: `cd client/packages/flutter_alacritty && flutter test`
Expected: PASS. Update any Rust unit test that asserted URL auto-detect (it moves to `url_link_provider_test.dart`); delete the now-obsolete Rust hint-pass test.

- [ ] **Step 6: Manual smoke (Linux)**

Type `https://example.com` into the example app terminal → underlines gold; Ctrl+click opens it. (URLs still work via the new provider.)

- [ ] **Step 7: Commit**

```bash
git add client/packages/flutter_alacritty/rust client/packages/flutter_alacritty/lib
git commit -m "refactor(alacritty): move URL detection to UrlLinkProvider; engine keeps OSC 8 only"
```

---

## PHASE 2 — OSC 7 cwd tracking

### Task 6: `engine.cwd` ValueListenable + OSC 7 parse (Dart side)

**Files:**
- Modify: `client/packages/flutter_alacritty/lib/engine/terminal_engine.dart`
- Test: `client/packages/flutter_alacritty/test/terminal_engine_test.dart` (extend)

- [ ] **Step 1: Write the failing test**

```dart
test('engine.cwd is null until OSC 7, then exposes the parsed path', () {
  final engine = TerminalEngine.fromBinding(fakeBinding); // existing test ctor
  expect(engine.cwd.value, isNull);
  // OSC 7: ESC ] 7 ; file://host/home/user/proj ST
  engine.feed(utf8Bytes('\x1b]7;file://localhost/home/user/proj\x07'));
  expect(engine.cwd.value, '/home/user/proj');
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client/packages/flutter_alacritty && flutter test test/terminal_engine_test.dart -n cwd`
Expected: FAIL — `cwd` getter missing.

- [ ] **Step 3: Implement**

Add to `TerminalEngine`:
```dart
final ValueNotifier<String?> _cwd = ValueNotifier<String?>(null);
ValueListenable<String?> get cwd => _cwd;
```
Wire it from the OSC 7 event the binding surfaces (Step in Task 7 makes the Rust side emit it). On receiving the OSC 7 payload string `file://host/path`, parse to a local path (strip scheme + host; on Windows convert `/C:/...`); set `_cwd.value`. Dispose `_cwd` in `dispose()`.

For the pure-Dart test before Rust lands, parse OSC 7 in Dart from the fed bytes via the existing OSC dispatch hook the binding exposes (mirror how `title` / OSC 2 is surfaced today). Helper:
```dart
String? _parseOsc7(String payload) {
  final uri = Uri.tryParse(payload.trim());
  if (uri == null || uri.scheme != 'file') return null;
  final path = uri.toFilePath(windows: defaultTargetPlatform == TargetPlatform.windows);
  return path.isEmpty ? null : path;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd client/packages/flutter_alacritty && flutter test test/terminal_engine_test.dart -n cwd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/flutter_alacritty/lib/engine/terminal_engine.dart \
        client/packages/flutter_alacritty/test/terminal_engine_test.dart
git commit -m "feat(alacritty): engine.cwd ValueListenable from OSC 7"
```

---

### Task 7: Rust OSC 7 dispatch → event

**Files:**
- Modify: `client/packages/flutter_alacritty/rust/src/engine.rs`, `rust/src/api/terminal.rs`

- [ ] **Step 1: Emit an OSC 7 event mirroring OSC 2 (title)**

In the OSC dispatch (where OSC 0/2 set the title and OSC 8 sets hyperlinks), add an OSC 7 arm that captures the payload string and pushes an `EngineEvent::Cwd(String)` (add the variant next to the existing title/bell events). Follow the EXACT pattern of the existing title event: same channel, same FRB event enum, same Dart-side decode. This is pure protocol parsing — no IO.

- [ ] **Step 2: Regenerate FRB + build**

Run: `cd client/packages/flutter_alacritty && flutter_rust_bridge_codegen generate && cd ../../ && flutter build linux --debug`
Expected: clean build; the Dart binding now delivers OSC 7 payloads, and `TerminalEngine` sets `_cwd` from them (replace the temporary Dart-only parse hook from Task 6 with the real event if needed).

- [ ] **Step 3: Rust unit test**

Add a Rust test feeding `\x1b]7;file://localhost/tmp/x\x1b\\` and asserting the engine queued a `Cwd("/tmp/x")`-equivalent event. Run: `cd client/packages/flutter_alacritty/rust && cargo test`.
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add client/packages/flutter_alacritty/rust
git commit -m "feat(alacritty): parse OSC 7 cwd into an engine event"
```

---

## PHASE 3 — TeamPilot `FilePathLinkProvider` + wiring

### Task 8: Path regex (`scan`)

**Files:**
- Create: `client/lib/services/terminal/file_path_link_provider.dart`
- Test: `client/test/services/terminal/file_path_link_provider_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_alacritty/links/terminal_link_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/file_path_link_provider.dart';

void main() {
  late FilePathLinkProvider p;
  setUp(() => p = FilePathLinkProvider(fs: _NeverFs(), launchCwd: '/proj'));

  List<String> payloads(String line) => p.scan(line).map((s) => s.payload).toList();

  test('detects relative, dotted, absolute, and windows paths', () {
    expect(payloads('Read(client/lib/foo.dart)'), contains('client/lib/foo.dart'));
    expect(payloads('see ./README.md now'), contains('./README.md'));
    expect(payloads('open ../a/b.txt'), contains('../a/b.txt'));
    expect(payloads('at /etc/hosts here'), contains('/etc/hosts'));
  });

  test('keeps :line[:col] suffix in the payload', () {
    expect(payloads('Update(lib/main.dart:42)'), contains('lib/main.dart:42'));
  });

  test('rejects non-paths', () {
    expect(payloads('version 1.2.3 shipped'), isEmpty);
    expect(payloads('just plain english words'), isEmpty);
  });
}

class _NeverFs implements Filesystem { /* throws on any call; scan must not touch fs */
  // ... use the project's existing in-test fake or `noSuchMethod`
  @override dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/services/terminal/file_path_link_provider_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement `scan` (regex only; validation in Task 9)**

```dart
import 'package:flutter_alacritty/links/terminal_link_provider.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart' show TerminalEngine; // for cwd, Task 10
import '../io/filesystem.dart';

class FilePathLinkProvider extends TerminalLinkProvider {
  FilePathLinkProvider({required this.fs, required this.launchCwd, this.engine});

  final Filesystem fs;
  final String launchCwd;
  final TerminalEngine? engine; // wired in Task 10

  // Matches: optional ./ ../ /, then path-ish chars with at least one separator
  // or a dotted extension, plus optional :line[:col].
  static final RegExp _pattern = RegExp(
    r'(?:\.{1,2}/|/|[A-Za-z]:[\\/])?'      // optional anchor
    r'[\w.\-]+(?:[\\/][\w.\-]+)*'          // segments
    r'(?::\d+(?::\d+)?)?',                 // optional :line[:col]
  );

  @override
  Iterable<LinkSpan> scan(String lineText) sync* {
    for (final m in _pattern.allMatches(lineText)) {
      final raw = m.group(0)!;
      if (!_looksLikePath(raw)) continue;
      yield LinkSpan(start: m.start, end: m.end, payload: raw);
    }
  }

  bool _looksLikePath(String s) {
    final core = s.split(':').first;             // drop :line[:col] for the shape test
    if (core.contains('/') || core.contains(r'\')) return true;
    if (core.startsWith('./') || core.startsWith('../')) return true;
    // single token: require a real file extension, and reject pure version-ish
    final ext = RegExp(r'\.[A-Za-z][A-Za-z0-9]{0,8}$');
    return ext.hasMatch(core) && !RegExp(r'^\d+(\.\d+)+$').hasMatch(core);
  }

  @override
  bool isEnabled(LinkSpan span) => false; // Task 9 makes this real
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd client && flutter test test/services/terminal/file_path_link_provider_test.dart`
Expected: PASS (scan/regex cases). `isEnabled` cases come in Task 9.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/terminal/file_path_link_provider.dart \
        client/test/services/terminal/file_path_link_provider_test.dart
git commit -m "feat(terminal): FilePathLinkProvider path detection"
```

---

### Task 9: Async validation + cache + notify

**Files:**
- Modify: `client/lib/services/terminal/file_path_link_provider.dart`
- Modify: `client/test/services/terminal/file_path_link_provider_test.dart`

- [ ] **Step 1: Write the failing test (fake Filesystem)**

```dart
test('candidate becomes enabled after fs confirms existence, notifies', () async {
  final fs = _FakeFs({'/proj/client/lib/foo.dart': FsEntityKind.file});
  final p = FilePathLinkProvider(fs: fs, launchCwd: '/proj');
  final span = p.scan('Read(client/lib/foo.dart)')
      .firstWhere((s) => s.payload == 'client/lib/foo.dart');
  expect(p.isEnabled(span), isFalse);        // not validated yet
  var notified = 0;
  p.addListener(() => notified++);
  // scan triggers validation; give microtasks/timers a turn
  p.scan('Read(client/lib/foo.dart)').toList();
  await Future<void>.delayed(const Duration(milliseconds: 10));
  expect(notified, greaterThan(0));
  expect(p.isEnabled(span), isTrue);
});

test('non-existent path never enables', () async {
  final fs = _FakeFs(const {}); // stat => notFound
  final p = FilePathLinkProvider(fs: fs, launchCwd: '/proj');
  final span = p.scan('Read(nope/x.dart)').first;
  p.scan('Read(nope/x.dart)').toList();
  await Future<void>.delayed(const Duration(milliseconds: 10));
  expect(p.isEnabled(span), isFalse);
});

// _FakeFs: stat(path) -> FsStat(kind: map[path] ?? notFound); other methods unimplemented.
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/services/terminal/file_path_link_provider_test.dart -n enables`
Expected: FAIL — `isEnabled` always false.

- [ ] **Step 3: Implement validation + cache**

Replace the stub `isEnabled` and add validation. Use `TerminalUriOpener.resolveLocalFilePath` for cwd-joining so behavior matches activation exactly.

```dart
import 'terminal_uri_opener.dart';

final Set<String> _confirmed = {};            // payload keys known to exist (positive)
final Map<String, DateTime> _negativeUntil = {}; // payload -> TTL expiry (negatives)
final Set<String> _inFlight = {};
static const _negativeTtl = Duration(seconds: 5);
static const _maxConcurrent = 8;

String _cwd() => engine?.cwd.value ?? launchCwd;     // Task 10 refines subscription
String _key(String payload) => '${_cwd()} $payload';

@override
bool isEnabled(LinkSpan span) => _confirmed.contains(_key(span.payload));

@override
Iterable<LinkSpan> scan(String lineText) sync* {
  for (final m in _pattern.allMatches(lineText)) {
    final raw = m.group(0)!;
    if (!_looksLikePath(raw)) continue;
    _maybeValidate(raw);                       // fire-and-forget
    yield LinkSpan(start: m.start, end: m.end, payload: raw);
  }
}

void _maybeValidate(String payload) {
  final key = _key(payload);
  if (_confirmed.contains(key) || _inFlight.contains(key)) return;
  final neg = _negativeUntil[key];
  if (neg != null && DateTime.now().isBefore(neg)) return;
  if (_inFlight.length >= _maxConcurrent) return; // best-effort; next scan retries
  _inFlight.add(key);
  () async {
    try {
      final resolved =
          TerminalUriOpener.resolveLocalFilePath(payload, workingDirectory: _cwd());
      if (resolved == null) { _negativeUntil[key] = DateTime.now().add(_negativeTtl); return; }
      final stat = await fs.stat(resolved);
      if (stat.exists && stat.isFile) {
        _confirmed.add(key);
        notifyListeners();
      } else {
        _negativeUntil[key] = DateTime.now().add(_negativeTtl);
      }
    } catch (_) {
      _negativeUntil[key] = DateTime.now().add(_negativeTtl);
    } finally {
      _inFlight.remove(key);
    }
  }();
}
```
Note: `resolveLocalFilePath` should strip the `:line[:col]` suffix before stat — extend `FilePathLinkProvider` to pass `payload.replaceFirst(RegExp(r':\d+(?::\d+)?$'), '')` into `resolveLocalFilePath`, but keep the full `payload` (with suffix) as the span payload for activation.

- [ ] **Step 4: Run to verify it passes**

Run: `cd client && flutter test test/services/terminal/file_path_link_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/terminal/file_path_link_provider.dart \
        client/test/services/terminal/file_path_link_provider_test.dart
git commit -m "feat(terminal): FilePathLinkProvider async validation + cache"
```

---

### Task 10: cwd subscription (OSC 7 + launch fallback)

**Files:**
- Modify: `client/lib/services/terminal/file_path_link_provider.dart`
- Modify: `client/test/services/terminal/file_path_link_provider_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('prefers engine.cwd (OSC 7) over launch cwd; clears negatives on change', () async {
  final fs = _FakeFs({'/run/app/lib/a.dart': FsEntityKind.file});
  final engine = TerminalEngine.fromBinding(fakeBinding);
  final p = FilePathLinkProvider(fs: fs, launchCwd: '/proj', engine: engine);
  final span = p.scan('Read(lib/a.dart)').first;
  p.scan('Read(lib/a.dart)').toList();
  await Future<void>.delayed(const Duration(milliseconds: 10));
  expect(p.isEnabled(span), isFalse);            // /proj/lib/a.dart doesn't exist
  engine.feed(utf8Bytes('\x1b]7;file://localhost/run/app\x07'));
  await Future<void>.delayed(const Duration(milliseconds: 10));
  p.scan('Read(lib/a.dart)').toList();
  await Future<void>.delayed(const Duration(milliseconds: 10));
  expect(p.isEnabled(p.scan('Read(lib/a.dart)').first), isTrue); // /run/app/lib/a.dart exists
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/services/terminal/file_path_link_provider_test.dart -n OSC`
Expected: FAIL — provider doesn't react to `engine.cwd`.

- [ ] **Step 3: Implement subscription**

In the constructor, if `engine != null`, `engine!.cwd.addListener(_onCwdChanged)`. Add:
```dart
void _onCwdChanged() {
  _negativeUntil.clear();   // re-evaluate candidates under the new cwd
  _inFlight.clear();
  notifyListeners();        // View recomputes; scan re-triggers validation
}
@override
void dispose() {
  engine?.cwd.removeListener(_onCwdChanged);
  super.dispose();
}
```
`_cwd()` already reads `engine?.cwd.value ?? launchCwd`, and `_key` namespaces the cache by cwd, so positives under the old cwd stay valid and new-cwd lookups re-validate.

- [ ] **Step 4: Run to verify it passes**

Run: `cd client && flutter test test/services/terminal/file_path_link_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/terminal/file_path_link_provider.dart \
        client/test/services/terminal/file_path_link_provider_test.dart
git commit -m "feat(terminal): FilePathLinkProvider tracks OSC 7 cwd with launch fallback"
```

---

### Task 11: Host wiring (providers + `onLinkActivate`)

**Files:**
- Modify: `client/lib/pages/chat/chat_workbench_terminal.dart`
- Modify: `client/lib/widgets/workspace_terminal_panel.dart`
- Test: `client/test/pages/chat/chat_workbench_terminal_test.dart` (or nearest existing host test)

- [ ] **Step 1: Build providers where `TerminalView` is constructed**

Find the `TerminalView(...)` (or wrapper) construction in `chat_workbench_terminal.dart`. Create the providers once (e.g. in the State's `initState`, stored in fields so they're disposed):
```dart
late final _urlProvider = UrlLinkProvider();
late final _fileProvider = FilePathLinkProvider(
  fs: AppStorage.fs,
  launchCwd: widget.session.workingDirectory, // the session's launch cwd
  engine: _engine,                            // the TerminalEngine for this view
);
```
Pass `linkProviders: [_urlProvider, _fileProvider]` to `TerminalView`. Dispose both in `dispose()`.

- [ ] **Step 2: Route `onLinkActivate`**

```dart
onLinkActivate: (payload) async {
  await TerminalUriOpener.open(
    payload,
    workingDirectory: _fileProvider.engine?.cwd.value ?? widget.session.workingDirectory,
    fs: AppStorage.fs,
    openInEditor: (abs) => context.read<EditorCubit>().openFile(abs),
  );
},
```
(Use the project's actual editor-open entry point — confirm the method name in `editor_cubit.dart`; the spec references `openInEditor`.) URLs/`mailto:` fall through `TerminalUriOpener`'s existing branches unchanged.

- [ ] **Step 3: Repeat the wiring in `workspace_terminal_panel.dart`**

Apply the same provider construction + `onLinkActivate` where that widget hosts `TerminalView`. If both hosts share a builder, factor a small helper `buildTerminalLinkProviders(engine, session)` in `file_path_link_provider.dart` to avoid duplication (DRY).

- [ ] **Step 4: Widget test**

Add a host test: pump the terminal host with a fake editor cubit + a fake `Filesystem` that confirms one path; feed the engine a line containing that path; pump > 120ms; Ctrl+click the cell; assert `EditorCubit.openFile` was called with the resolved absolute path.

- [ ] **Step 5: Run**

Run: `cd client && flutter test test/pages/chat/chat_workbench_terminal_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/chat/chat_workbench_terminal.dart \
        client/lib/widgets/workspace_terminal_panel.dart \
        client/lib/services/terminal/file_path_link_provider.dart \
        client/test/pages/chat/chat_workbench_terminal_test.dart
git commit -m "feat(terminal): wire file-path links into terminal hosts"
```

---

### Task 12: Full verification + manual smoke

- [ ] **Step 1: Static analysis + full test suite**

Run:
```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  && flutter test --exclude-tags integration
cd client/packages/flutter_alacritty && flutter test
cd client/packages/flutter_alacritty/rust && cargo test
```
Expected: all green.

- [ ] **Step 2: Manual smoke (desktop, real Claude session)**

- Open a project workbench, launch a Claude session.
- Ask: "read client/lib/main.dart and tell me the first import."
- Confirm the printed `client/lib/main.dart` underlines shortly (~<0.5s) after the line settles; hover shows the click cursor; Ctrl+click opens it in the in-app editor.
- Ask Claude to mention a made-up path `zzz/does-not-exist.dart`; confirm it never underlines.
- Confirm a plain `https://…` in output is still clickable (UrlLinkProvider).
- `cd` into a subdir inside the shell, print a relative path that exists there; confirm OSC 7 cwd tracking makes it resolve (if the shell emits OSC 7).

- [ ] **Step 3: Update docs**

In `client/packages/flutter_alacritty/docs/library-api.md`, document the `linkProviders` seam (LinkSpan / TerminalLinkProvider / UrlLinkProvider / LinkOverlay) and `engine.cwd`. Commit.

```bash
git add client/packages/flutter_alacritty/docs/library-api.md
git commit -m "docs(alacritty): document link-provider seam + engine.cwd"
```

---

## Self-Review notes (spec coverage)

- §3/§4.1 seam → Tasks 1, 4. §4 UrlLinkProvider → Task 2. Painter decoration → Task 3.
- §2 "remove Rust URL regex, engine keeps OSC 8" → Task 5.
- §4.3 / §2 OSC 7 cwd → Tasks 6–7.
- §4.4 FilePathLinkProvider (scan / validate / cache / cwd) → Tasks 8–10.
- §4.5 host wiring + reuse of `TerminalUriOpener`/`openInEditor` → Task 11.
- §5 error handling (stat failure, stale payload, bad match, OSC 7 absent) → covered by Task 9 catch/negative-TTL + Task 10 fallback + Task 12 smoke.
- §6 performance (debounce, visible-region only, capped/ cached validation) → Task 4 debounce + Task 9 cache/concurrency.
- §7 testing → per-task tests + Task 12 full run.
```
