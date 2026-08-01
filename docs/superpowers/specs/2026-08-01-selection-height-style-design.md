# Selection height style (browser-like SelectionArea highlight)

**Date:** 2026-08-01  
**Status:** implemented (mandatory Flutter SDK patch + TeamPilot wiring + CI)  
**Upstream:** [flutter/flutter#161010](https://github.com/flutter/flutter/issues/161010)

## Problem

Chat markdown uses `SelectionArea` + plain `Text`. Flutter paints selection with
`BoxHeightStyle.tight` (glyph ink bounds only). Changing `TextStyle.height` widens
line spacing but **does not** grow the selection highlight. Browser / Cursor-style
UIs paint the full line box (including line spacing).

## Decision

Follow the Flutter team’s recommended architecture:

1. Add `selectionHeightStyle` to `DefaultSelectionStyle` (ambient, one place).
2. Plumb through `Text` → `RichText` → `RenderParagraph`.
3. `_SelectableFragment.paint` uses that style in `getBoxesForSelection`.
4. TeamPilot chat wraps `SelectionArea` with
   `DefaultSelectionStyle(selectionHeightStyle: BoxHeightStyle.includeLineSpacingMiddle)`
   via `AiLineSpacedSelectionStyle`.

Do **not** replace `SelectionArea` with per-leaf `SelectableText` (breaks
cross-block selection). Do **not** invent an app-only paint overlay.

The patch is **mandatory** for all developers and CI until upstream ships the API.
Operational convention (apply / add / refresh / CI): [docs/flutter-patches.md](../../flutter-patches.md).

## Automation

| Piece | Location |
|-------|----------|
| Patches | `tool/flutter_patches/*.patch` |
| Apply script (idempotent) | `tool/flutter_patches/apply_flutter_patches.sh` |
| CI composite action | `.github/actions/apply-flutter-patches` |
| Wired in | `client-verify.yml`, `release.yml` (after every `flutter-action`) |

**Adding another patch:** put a new `*.patch` under `tool/flutter_patches/` (sorted name order). No script or CI edits. See [docs/flutter-patches.md](../../flutter-patches.md).

Local / after Flutter upgrade:

```bash
./tool/flutter_patches/apply_flutter_patches.sh
```

## TeamPilot

| Piece | Location |
|-------|----------|
| Wrapper | `client/packages/ai_message_ui/lib/src/selection_height_style.dart` |
| Live thread | `AiThread` |
| History thread | `SessionHistoryThread` |

Reading rhythm (paragraph spacing / body `height`) stays in
`buildAppCompiledMarkdownStyle` — independent of selection paint style.

## Upstream

Contribute the same API change to Flutter; once landed on stable:

1. Drop `selection_height_style.patch` and the apply step from CI.
2. Keep `AiLineSpacedSelectionStyle` (still the product opt-in for chat).
