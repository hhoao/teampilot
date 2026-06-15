# Clickable File Paths in the Embedded Terminal — Design

**Date:** 2026-06-15
**Status:** Design pending review
**Scope:** `client/packages/flutter_alacritty` (library seam) + `client/lib/services/terminal` (TeamPilot consumer)

---

## 1. Goal & Non-Goals

**Goal.** When an embedded CLI (Claude Code TUI, codex, etc.) prints a file reference —
`● Read(client/lib/foo.dart)`, `Update(lib/main.dart:42)`, `see ./README.md` — the path
becomes a clickable link in the terminal. Ctrl/Cmd+click opens the file in TeamPilot's in-app
editor (existing `openInEditor`), falling back to the OS handler. A path is rendered as a link
**only after it is confirmed to exist** on the session's filesystem, so non-path text is never
decorated.

This is the terminal-native analogue of the VSCode extension's clickable file references. The
VSCode extension has structured tool-call JSON; TeamPilot embeds a raw TUI, so we detect paths
from rendered text and validate them against the real filesystem.

**Non-Goals.**

- VSCode-style structured "activity feed" panel (rejected during brainstorming — terminal-native chosen).
- Per-CLI special casing. Detection is CLI-agnostic; it lives in one place and works for every CLI.
- Making `flutter_alacritty` do any filesystem IO. The library stays IO-free and embeddable
  (per the Plan 2W library-seam principles). All path/cwd/filesystem/editor logic lives in TeamPilot.
- Bare-token "hover to reveal" mode (rejected — discoverability too poor).
- Remote (SSH) path validation in v1 — see §8 Risks (the validator is filesystem-injected, so SSH
  can follow without a redesign).

## 2. Locked decisions (from brainstorming)

| Area | Decision |
|------|----------|
| Final form | Terminal-native: detect paths in rendered text, decorate clickable, Ctrl+click → editor. |
| False-positive policy | **Validate-before-decorate.** Regex finds candidates; a path is only styled/clickable after async `Filesystem.stat` confirms it exists. Results cached. |
| Library purity | `flutter_alacritty` does NO filesystem IO. It exposes a generic, injectable **link-provider seam**; TeamPilot supplies the path provider. Matches Plan 2W ("url_launcher / clipboard / file drop all live in the consumer; the View only emits callbacks"). |
| Link mechanism unification | No back-compat kept. The Rust engine's hardcoded URL hint regex is **removed**; URL detection moves into the same Dart `linkProvider` seam (library ships a default `UrlLinkProvider`). The engine keeps only **OSC 8** (a real terminal protocol, IO-free, genuinely belongs in the library). One link policy surface, fully injectable. |
| cwd source | **OSC 7 cwd tracking** (pure protocol parse, IO-free → lives in the engine as `engine.cwd`), with the session launch `workingDirectory` as the bootstrap/fallback. |
| Click trigger | Ctrl/Cmd + left-click (consistent with the existing OSC 8 / URL behavior). Hover over a confirmed link shows `SystemMouseCursors.click`. |

**Guiding rule for "does it belong in the library?":** *IO-free and universal → may live in the
library (OSC 8, OSC 7 parse, URL regex default). Needs IO or app context → must go through the
consumer seam (path detection, fs validation, cwd resolution, open-in-editor).*

## 3. Architecture & data flow

```
flutter_alacritty (IO-free, embeddable)
  TerminalEngine
    ├─ OSC 8 hyperlinks (protocol; unchanged)         hyperlinkAt(r,c) -> String?
    └─ OSC 7 cwd parse (NEW)                           cwd: ValueListenable<String?>
  TerminalView
    ├─ linkProviders: List<TerminalLinkProvider> (NEW seam)
    │     • on each (debounced) grid change, scans visible lines via each provider
    │     • paints underline + hover cursor ONLY on spans the provider reports enabled
    │     • Ctrl+click: cell -> OSC 8 id  OR  enabled provider span -> onLinkActivate(payload)
    ├─ ships default: UrlLinkProvider  (the old Rust URL regex, now Dart, IO-free)
    └─ onLinkActivate(String payload)  ───────────────────────────────┐
                                                                       │
TeamPilot (owns ALL file semantics)                                    │
  FilePathLinkProvider : TerminalLinkProvider   (NEW)                  │
    ├─ scan(line): regex -> candidate spans (payload = raw path text)  │
    ├─ isEnabled(span): sync lookup in _confirmed cache                │
    ├─ async: for unseen candidates, resolve vs cwd + Filesystem.stat, │
    │         update cache, call notifyListeners() -> View repaints    │
    └─ cwd from engine.cwd (OSC 7) ?? session launch workingDirectory  │
  Terminal host (chat_workbench_terminal / workspace_terminal_panel)   │
    onLinkActivate(payload) ◄──────────────────────────────────────────┘
       -> TerminalUriOpener.open(payload, workingDirectory: cwd,
                                 openInEditor: editorCubit.openFile)
```

**Data flow — Claude prints `● Read(client/lib/foo.dart)`:**

1. Bytes reach `engine.feed`; `MirrorGrid` updates; grid `Listenable` notifies.
2. `TerminalView` debounces (~120 ms idle) then, for each visible line, calls
   `FilePathLinkProvider.scan(lineText)` → candidate span `(range, payload="client/lib/foo.dart")`.
3. View asks `provider.isEnabled(span)`. First time → not in cache → **not decorated yet**.
4. The provider, during `scan`, fire-and-forgets validation for unseen payloads:
   resolve `payload` against `cwd` → `Filesystem.stat` → exists & isFile → add to `_confirmed`,
   `notifyListeners()`.
5. Provider notify → View recomputes decorations → the span is now `isEnabled` → painted
   underlined in the hint color; hover shows the click cursor.
6. Ctrl+click on a decorated cell → View resolves the span → `onLinkActivate("client/lib/foo.dart")`.
7. Host → `TerminalUriOpener.open(..., workingDirectory: cwd, openInEditor: ...)` → existing path
   joins cwd, stats, opens in the in-app editor (or OS fallback). **No new path logic needed here —
   `TerminalUriOpener` already does relative-join + editor-open.**

Scroll coherence is automatic: decorations are keyed by **payload string**, not grid coordinates.
Any cell whose candidate payload is confirmed gets underlined, wherever it currently sits.

## 4. Components

### 4.1 Library — `TerminalLinkProvider` seam (NEW)

`lib/links/terminal_link_provider.dart`:

```dart
/// A half-open column range [start, end) on a single visible line, with the
/// opaque payload handed back to the host on activation.
class LinkSpan {
  const LinkSpan({required this.start, required this.end, required this.payload});
  final int start;
  final int end;
  final String payload;
}

/// Host-injectable link source. The View calls [scan] (sync, cheap) on visible
/// lines and [isEnabled] (sync) before decorating. Providers that confirm links
/// asynchronously extend [ChangeNotifier] and notify when their enabled-set changes;
/// the View listens and repaints. The library NEVER does IO on a provider's behalf.
abstract class TerminalLinkProvider extends ChangeNotifier {
  /// Synchronous candidate detection over one rendered line's text.
  Iterable<LinkSpan> scan(String lineText);

  /// Synchronous gate: should this candidate be drawn/clickable now?
  /// Async providers return false until their cache confirms the payload.
  bool isEnabled(LinkSpan span);
}
```

`lib/links/url_link_provider.dart` — `UrlLinkProvider` ships as a library default: the former
Rust hint pattern `(?:https?|ftp|file)://[^\s]+` as a Dart regex; `isEnabled` always true (URLs need
no validation). This replaces the engine-side URL hint pass.

### 4.2 Library — `TerminalView` wiring

- New param: `List<TerminalLinkProvider> linkProviders` (default `const [UrlLinkProvider()]`).
- New state: `_decorations` — a per-frame map of `(row) -> List<(LinkSpan, providerIndex)>` for
  enabled spans only, recomputed on grid change (debounced) and on any provider `notifyListeners`.
- Painter: extend the existing decoration precedence (focused-match > search-match > OSC8-hyperlink)
  with provider-link as the lowest layer; paints the same gold underline + `hintStart` colors.
- `MouseRegion` hover: cursor = click when the pointer cell is inside an enabled span OR an OSC 8 cell.
- `_onPointerDown` (Ctrl+click): existing `_engine.hyperlinkAt(r,c)` check **first**; if null, hit-test
  `_decorations[r]` for a span covering column `c` → `onLinkActivate(span.payload)`.
- Lifecycle: View `addListener` on each provider in `initState` / `didUpdateWidget`; removes in
  `dispose`. Providers are owned by the host (host disposes them).

### 4.3 Library — OSC 7 cwd (`engine.cwd`)

- Engine parses `OSC 7 ; file://<host>/<path> ST`, exposes `ValueListenable<String?> cwd`
  (null until first OSC 7). Pure parse, no IO. Host reads it; host decides fallback.
- (Rust: handle OSC 7 in the OSC dispatch alongside the existing OSC 8 handling; FRB getter +
  a change event. Mirrors how `title` is already surfaced.)

### 4.4 TeamPilot — `FilePathLinkProvider` (NEW)

`client/lib/services/terminal/file_path_link_provider.dart`:

- `scan(line)`: path regex producing candidates. Pattern accepts: absolute (`/…`, `C:\…`),
  explicitly-relative (`./`, `../`), and `a/b…`-style relative paths, with an optional
  `:line[:col]` suffix; strips trailing punctuation (reuse `TerminalUriOpener.fixup` semantics).
  Payload = the raw matched text (so `:42` is preserved for the editor).
- `isEnabled(span)`: `_confirmed.contains(_key(span.payload))` — sync.
- Async validation: on `scan`, for each candidate not in `_seen`, enqueue
  `TerminalUriOpener.resolveLocalFilePath(payload, workingDirectory: _cwd)` →
  `Filesystem.stat(resolved)`; on `exists && isFile`, add to `_confirmed` + `notifyListeners()`.
  Concurrency-capped (e.g. 8 in flight), de-duplicated via `_seen`.
- Cache: `_confirmed` (positive) kept for the session; negatives kept with a short TTL
  (~5 s) so a file created later becomes clickable on the next scan without re-statting every frame.
- cwd: `_cwd = engine.cwd.value ?? launchWorkingDirectory`. Subscribes to `engine.cwd`; on change,
  clears negatives (positives stay valid as long as absolute) and notifies.

### 4.5 TeamPilot — host wiring

Where `TerminalView` is hosted (`chat_workbench_terminal.dart` / `workspace_terminal_panel.dart`):

- Build `linkProviders: [UrlLinkProvider(), FilePathLinkProvider(engine: ..., launchCwd: session.workingDirectory, fs: AppStorage.fs)]`.
- `onLinkActivate: (payload) => TerminalUriOpener.open(payload, workingDirectory: _cwd, fs: AppStorage.fs, openInEditor: (abs) => editorCubit.openFile(abs))`.
  - `file:`/bare path → editor or OS; `http(s):`/`mailto:` → existing launch path (unchanged).
- Dispose the providers with the session.

## 5. Error handling

- **Stat failure / permission error:** treated as "does not exist" → not decorated. Silent (debug log only).
- **Stale payload after scrollback eviction:** payload still confirmed → `onLinkActivate` runs;
  `TerminalUriOpener` re-stats and no-ops if the file vanished. No crash.
- **Bad regex match (e.g. `1.2.3`):** `Filesystem.stat` says no file → never decorated. This is the
  whole point of validate-before-decorate.
- **OSC 7 absent (CLI doesn't emit it):** `engine.cwd` stays null → provider uses launch cwd. Relative
  paths still resolve for the common case (CLI launched at project root).
- **Provider notify storm:** validation notifies are coalesced by the View's existing debounce; the
  per-frame decoration recompute is O(visible lines × providers), bounded.

## 6. Performance

- Detection is Dart-side over the **visible region only** (~50×200), debounced ~120 ms after the last
  grid change. Per-line `scan` results memoized by line-content hash so steady-state repaint is cheap.
- `Filesystem.stat` is async, capped concurrency, de-duplicated by payload, cached. A confirmed path is
  never re-statted within the session.
- Removing the Rust URL hint pass removes per-snapshot regex work in the engine; net engine cost goes
  *down*.

## 7. Testing

**Library (Dart, fake binding — no IO):**

- `UrlLinkProvider.scan` finds `https://…`, `file://…`; `isEnabled` always true.
- A fake async provider: `scan` returns a span; `isEnabled` false → not painted; after the fake flips
  its cache + `notifyListeners`, a pump → span painted + hover cursor + Ctrl+click fires
  `onLinkActivate(payload)`.
- OSC 8 still wins over a provider span on the same cell (precedence).
- `engine.cwd` updates on an OSC 7 feed; null before.

**TeamPilot (`FilePathLinkProvider`, injected fake `Filesystem`):**

- `scan` extracts `client/lib/foo.dart`, `./README.md`, `/abs/x`, `C:\a\b`, and `lib/main.dart:42`
  (payload keeps `:42`); rejects `1.2.3`, prose words.
- Candidate not in cache → `isEnabled` false; after fake `stat` returns exists → enabled + notified.
- Non-existent path → fake `stat` not-exists → never enabled.
- cwd: `engine.cwd` value preferred over launch cwd; relative payload resolved against it.

**Host (widget):** `onLinkActivate("foo.dart")` → `TerminalUriOpener.open` called with the session cwd
and `openInEditor` (spy). (Reuse existing `terminal_view_callback_test.dart` patterns.)

**Manual smoke:** run Claude in an embedded session, ask it to read/edit a file, confirm the path
underlines shortly after printing and Ctrl+click opens it in the editor; confirm a made-up path
(`zzz/nope.dart`) never underlines.

## 8. Risks & open questions

| Risk | Mitigation |
|------|------------|
| Path regex noise / over-matching | Validate-before-decorate is the backstop; only real files ever decorate. Regex tuned to require a separator or known extension. |
| Debounce makes links feel laggy | 120 ms after output settles; during a stream the link appears once the line stops changing — acceptable, matches how humans read. Tunable. |
| Filesystem on the UI isolate | `stat` is async + capped + cached; visible-region only. If profiling shows jank, move validation to a background isolate behind the same provider interface (no API change). |
| SSH sessions: `AppStorage.fs` is `SftpFilesystem` | The provider takes an injected `Filesystem`; SSH "just works" but remote stat latency is higher — start with desktop/native, gate SSH behind a flag if latency hurts. (Not in v1 scope.) |
| Removing the Rust URL regex changes a shipped behavior | Intentional (no back-compat). `UrlLinkProvider` default preserves URL clickability for every consumer, including the example app. |
| Two link mechanisms (OSC 8 engine-side, providers view-side) | Acceptable and principled: OSC 8 is protocol data the engine already owns; text-scan links are policy the consumer owns. Painter merges them with documented precedence. |

## 9. Files (by layer)

```
flutter_alacritty/lib/
  links/terminal_link_provider.dart   NEW  LinkSpan + TerminalLinkProvider
  links/url_link_provider.dart        NEW  default URL provider (ex-Rust regex)
  ui/terminal_view.dart               linkProviders param, decoration recompute,
                                      hover + Ctrl+click hit-test, provider listen/dispose
  render/terminal_painter.dart        provider-link decoration layer (lowest precedence)
  engine/terminal_engine.dart         cwd: ValueListenable<String?>
  rust + frb                          OSC 7 parse + cwd event; REMOVE URL hint pass
flutter_alacritty/                    docs/library-api.md: document the link-provider seam

client/lib/services/terminal/
  file_path_link_provider.dart        NEW  path regex + async fs validation + cache + cwd
  (terminal_uri_opener.dart)          reused as-is for resolve + open
client/lib/pages/chat/chat_workbench_terminal.dart      wire providers + onLinkActivate
client/lib/widgets/workspace_terminal_panel.dart        (same, where it hosts TerminalView)
```
