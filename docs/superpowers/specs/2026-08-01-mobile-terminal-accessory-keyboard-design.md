# Mobile terminal soft keyboard + accessory bar

**Date:** 2026-08-01  
**Status:** design (locked by product owner: best architecture / extensibility; no backward compat)  
**Related:** `flutter_alacritty` IME (`ImeSession`), shared shell `TeampilotAlacrittyTerminal`

## Problem

On TeamPilot mobile / touch shells, tapping the embedded terminal often does **not** reopen the system soft keyboard once focus is already held (classic “attached but dismissed” IME gap). Soft keyboards also lack terminal keys (Esc, Tab, Ctrl, arrows, Home/End). There is no accessory bar today; desktop shortcuts and right-click paste are not a substitute on touch.

ServerBox-style UX is the product reference, but ServerBox’s implementation is **AGPL-3.0 app code** wired to **xterm + Riverpod** — not a reusable library, and incompatible with TeamPilot’s **flutter_alacritty** stack. No suitable pub.dev package plugs into alacritty.

## Goals

1. **Tap → keyboard:** every intentional terminal tap on a touch shell calls focus + **force `TextInput.show()`** even when already attached.
2. **Accessory bar:** ServerBox-like dual-row bar above the system IME with Esc, Alt, Home, ↑, End / Tab, Ctrl, ←, ↓, →, IME toggle.
3. **Sticky modifiers:** Ctrl / Alt latch; merge into the next effective input; **auto-off** after that input (manual tap cancels).
4. **One enablement point** for all embedded terminals via `TeampilotAlacrittyTerminal`.
5. **Extensible** key model + layouts without forking PTY write paths.
6. **No backward-compat shims** for half-working focus-only IME behavior.

## Non-goals

- User-facing key-order settings UI (layout config API yes; settings page later).
- Full F1–F12 row, symbol pads, or replacing the system IME with an on-screen QWERTY.
- Copying ServerBox source or depending on AGPL code.
- Desktop accessory chrome (hardware keyboard remains the path).

## Decisions (locked)

| Topic | Decision |
|-------|----------|
| Soft keyboard + bar | Both |
| Bar shape | Accessory above system IME (ServerBox / Termux style) |
| Default keys | ServerBox dual-row (Esc·Alt·Home·↑·End / Tab·Ctrl·←·↓·→·⌨) |
| Surfaces | All embedded terminals through `TeampilotAlacrittyTerminal` |
| Platform heuristic | All non-desktop touch shells |
| Modifiers | Sticky Ctrl/Alt + auto-off after next effective input |
| Architecture | Layered: alacritty owns IME/latch/inject; app shell enables themed bar |
| Libraries | None; borrow UX only |
| Compat | None required |

## Architecture

```
touch tap / IME / accessory key
            │
            ▼
┌─────────────────────────────────────┐
│ flutter_alacritty                   │
│  ImeSession.ensureVisible()         │  show even if already attached
│  ModifierLatch (ctrl/alt[/shift])   │  sticky + auto-off policy
│  TerminalKeyInjector                │  encodeKey / UTF-8 → engine
│  TerminalView merges latch on       │  IME commit + accessory inject
│    soft/virtual input paths         │  (not hardware onKeyEvent OS mods)
│  TerminalAccessoryKey + Layout      │  extensible data model
│  TerminalAccessoryBar (unstyled)    │  render + long-press repeat
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│ TeampilotAlacrittyTerminal          │  sole product enablement
│  touch shell → show bar + latch     │
│  default layout = ServerBoxDualRow  │
│  Tp / theme styling                 │
└─────────────────────────────────────┘
```

### Package responsibilities (`flutter_alacritty`)

| Module | Responsibility |
|--------|----------------|
| `input/ime_session.dart` | Add `ensureVisible()` / `hide()`; `attach()` keeps show-on-attach; idempotent show when attached |
| `input/modifier_latch.dart` | Sticky ctrl/alt/(optional shift); notify listeners; `consumeAfterSend()` |
| `input/terminal_key_injector.dart` | `injectKey(LogicalKeyboardKey, …)` / `injectText` merging latch + `encodeKey` / commit path |
| `input/terminal_accessory_key.dart` | Sealed/data keys: latch, inject key, inject raw, action |
| `input/terminal_accessory_layout.dart` | Named presets; `serverBoxDualRow` default |
| `ui/terminal_accessory_bar.dart` | Renders layout; selected latch chrome; arrow long-press repeat |
| `ui/terminal_view.dart` | Touch tap → focus + `ensureVisible`; wire latch into key/IME paths; optional accessory slot |

### App shell (`TeampilotAlacrittyTerminal`)

- Detect non-desktop touch shell once; enable accessory + latch.
- Pass themed `TerminalAccessoryBar` (or style overrides) with `serverBoxDualRow`.
- IME toggle key → `ensureVisible` / `hide`.
- Host pages (chat workbench, workspace dock, future embeds) **do not** add their own bars.

### Extension points

- Swap / compose `TerminalAccessoryLayout` without changing inject/IME.
- New keys via `TerminalAccessoryKey.action` (paste, snippets, …).
- Future settings persist a layout id/order only.

## Interaction

1. **Tap terminal (touch):** `requestFocus` + `ensureVisible()`.
2. **Blur:** detach IME; clear or keep latch per policy — **clear latch on blur** (predictable).
3. **⌨:** toggle system soft keyboard visibility; bar stays mounted.
4. **Esc / Tab / Home / End / arrows:** inject via `encodeKey`; arrows support long-press repeat.
5. **Ctrl / Alt:** toggle latch highlight; next effective IME commit or inject merges modifiers then auto-off; second tap clears without sending.
6. **Layout:** `Column(Expanded(terminal), bar)` so the bar sits above the IME; resize with `viewInsets` as today.
7. **Desktop:** no bar; no latch; existing hardware + shortcut paths unchanged.

### Latch merge rules

- Latched Ctrl + IME commit `"c"` → `\x03` (not literal `c`), then clear Ctrl.
- Latched Ctrl + `injectKey(arrowUp)` → CSI with ctrl modifier, then clear.
- Latch toggle while composing: **do not** reset composing; merge applies on commit.
- Esc / navigation inject while composing: `resetComposing` then inject.

## Edge cases

| Case | Behavior |
|------|----------|
| Accessory tap while unfocused | Focus + ensureVisible (if showing IME), then act |
| Engine disposed / not writable | Inject no-ops; no UI exception |
| System steals IME | Next terminal tap calls `ensureVisible` again |
| Rotation / split / insets | Bar follows inset; PTY resize unchanged |
| External keyboard on tablet | Still a touch shell → bar may show; latch only merges virtual/IME paths as specified (hardware modifiers use OS state, not double-applied unless already latched) |

## Testing

1. **Unit (`flutter_alacritty`):** `ensureVisible` shows when attached; latch toggle/merge/auto-off/manual clear; inject+latch byte expectations (`Ctrl+c`, `Ctrl+↑`).
2. **Widget:** touch heuristic shows dual-row bar; desktop heuristic hides; Ctrl highlight → commit `c` → `\x03` + Ctrl off; arrow long-press multi-inject.
3. **App shell:** `TeampilotAlacrittyTerminal` wires bar for touch; chat + workspace dock covered by the same shell.

### Done when

- Touch: tap always opens soft keyboard; bar can send Ctrl+C, Esc, Tab, arrows.
- Desktop: no accessory; no regression vs current input.

## Out of scope follow-ups

- Settings UI for custom key order.
- Clipboard / snippet action keys on the bar.
- iOS-specific IME quirks hardening beyond the shared `ensureVisible` path (fix if discovered).
