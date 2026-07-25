# TeamPilot patches on window_manager 0.5.2

Vendored from pub.dev `window_manager` 0.5.2. Upstream:
https://github.com/leanflutter/window_manager

## Windows: auto-hide taskbar with custom title bar

**Symptom:** Maximized `TitleBarStyle.hidden` / frameless windows block the
auto-hide taskbar (Shell treats them as fullscreen). Upstream:
https://github.com/leanflutter/window_manager/issues/438

**Fix:** `SetProp(hwnd, L"NonRudeHWND", TRUE)` when showing / applying custom
chrome; clear on true fullscreen; remove on destroy. See
`ITaskbarList2::MarkFullscreenWindow` remarks.

## Windows: ghost borders while resizing

**Symptom:** Live resize leaves previous frame borders visible. Using
`WVR_REDRAW` clears them but forces a full-window invalidate every size tick,
so Flutter lags and ghosts linger ("slow").

**Root cause:** `WM_NCCALCSIZE` returning `0` lets USER BitBlt the old client
into the new client while custom chrome also shrinks the client by the 8px
resize border.

**Fix:** Return `WVR_VALIDRECTS` with empty source/destination rects so USER
skips the blit without a full redraw. After live resize ends, cheap
`InvalidateRect` on the HWND + Flutter child (not the +1px `ForceChildRefresh`
dance).
