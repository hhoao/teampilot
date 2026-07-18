# History review: Claude-aligned light open (IR budget, not ListView)

**Date:** 2026-07-18  
**Status:** Decision + implementation  
**Evidence:** test46/49 (~1.1s `RenderParagraph`), test52/54 (~0.5s after defer+table fold; tip still paragraph)  
**Reference:** Anthropic Claude Code VS Code `2.1.212` webview (`webview/index.js`)

## What Claude Code actually does (installed extension)

| Mechanism | Detail |
|-----------|--------|
| Shell | VS Code **Webview + React** + bundled Monaco; agent is bundled `claude` CLI over stream-json |
| Long content | Component `oYe({ maxHeight = 250 })`: CSS `maxHeight`, truncation gradient, **"Show more" / "Show less"** |
| Measurement | `scrollHeight > maxHeight` → show expand affordance; content still in DOM (cheap for Chromium) |
| Collapse chrome | Widespread `isCollapsed` / Collapsible for tools, trees, folding |
| History volume | Render-layer caps / slicing (historically ~500 tail); not a perfect virtual list |
| Scroll | Browser compositor; **not** Flutter `ListView` |

They feel fast because **open paints clipped/cheap content**, not because they use `ListView.builder`.

## Why we will not switch to `ListView.builder` / `CustomScrollView`

Already falsified in-repo (variable-height rows → mid-scroll `maxScrollExtent` swings). Spacer + `TurnHeightCache` stays. ListView would not fix **in-viewport** `RenderParagraph` cost (test54).

## Why we will not copy CSS `maxHeight` literally

Flutter `ConstrainedBox` + clip **still layouts** all children. Claude can afford full DOM text; we cannot afford full `Text.rich` trees. Equivalent UX must **omit widgets / truncate IR** while collapsed.

## Architecture (chosen)

```
SessionHistoryThread
  VirtualThreadViewport (unchanged spacer model)
    AiHistoryRenderScope
      AiMessageView
        AiTextPartView → ExpandableHistoryMarkdown
          collapsed: truncateMessageContent(budget ≈ 250px)
          expanded: full document
          affordance: Show more / Show less (Claude labels)
```

| Layer | Behavior |
|-------|----------|
| Turn virtualization | Keep |
| Open | Mount **budget-capped** markdown immediately (no blank 2-frame dump of full body) |
| Collapsed budget | ~8 blocks, 6 table rows, ~1200 chars (≈ Claude 250px body) |
| Expand | Full IR; remasure via existing `_MeasuredBox` |
| Live chat | No `AiHistoryRenderScope` → full render |

## Non-goals

- WebView rewrite  
- Silent 500-message drop  
- Replacing spacer viewport with naive `ListView.builder`

## Success

Profile open same session: worst build ≪ test54 ~560ms while collapsed; expand may still be expensive (user-initiated, like Claude).
