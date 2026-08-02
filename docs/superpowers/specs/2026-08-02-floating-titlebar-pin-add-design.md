# Floating title bar tabs + add (Orca-style)

**Date:** 2026-08-02  
**Status:** implemented  
**Scope:** `floating_workspace_panel.dart` / `floating_workspace_tab_bar.dart`

## Behavior (matches Orca TabBar)

- Tabs live in a horizontal scroll viewport; **"+" is a sibling outside that viewport**.
- Tabs strip shrink-wraps (`flex: 0 1 auto` equivalent): when tabs fit, "+" sits immediately after the last tab.
- When tabs hit the max lane width, only the strip scrolls; "+" stays just after the strip (not inside the scroll, not relocated beside window chrome).
- Window chrome (maximize / minimize) stays flush-right; empty space between "+" and chrome is title-drag (Stack underlay).

## Non-goals

- Chevron overflow buttons / scroll fade (optional follow-up).
- Workbench center strip changes.
