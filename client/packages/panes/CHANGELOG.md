## 1.3.0

- ✨ **Dynamic Pane Management**: Added ability to add, remove, and update panes at runtime via `PaneController` (@simonpham)
  - New methods: `addPane`, `addPanes`, `removePane`, `updatePane`.
  - Automatic state cleanup when panes are removed.
- ✨ **PaneSize Equality**: Added `operator ==` and `hashCode` to `PaneSize` subclasses for easier configuration comparisons.

## 1.2.0

- ✨ Implement zero-space resizer layout handling by @simonpham

- ✨ Add cascade resize support by @khoadng

- 💥 BREAKING: Add animationProgress to PaneBuilder & IdePaneBuilder by @simonpham

## 1.1.1

- 🐛 Fix various resize and auto hide issues (#1) – thanks to @khoadng

## 1.1.0

### Features

- **Drag-to-Reveal** - Continue dragging past the auto-hide threshold to reveal a hidden pane.
- **Edge Drag Reveal** - Drag from the edge of the screen to reveal a hidden pane (when auto-hide is enabled).
- **Auto-Hide Size Restoration** - When a pane is auto-hidden and then shown again (via toggle or code), it now restores to its pre-hide size instead of the minimum size.
- **Real-time Size Updates** - `IdeLayout` now has an `onSizeChanged` callback for tracking pane size changes in real-time.

### Improvements

- **Resizer Visibility** - Resizers remain interactive during drag operations even if adjacent panes are hidden, enabling smooth drag-to-reveal workflows.
- **Resizer at Edge** - Resizers now stay visible at the container edge when a pane is hidden (if auto-hide is enabled), providing a visual cue and grab target for revealing.
- **Reliable State Serialization** - Improved `save()` and `load()` to ensure layout state is correctly preserved and restored without unintended mutations.

## 1.0.0

Initial release of the panes package.

### Features

- **MultiPane** - Flexible resizable split-view layouts (horizontal/vertical)
- **IdeLayout** - Pre-configured IDE-like layout with left, right, center, and bottom panels
- **TabbedPane** - Tabbed interface with icons and action buttons
- **PaneTheme** - Comprehensive theming via `ThemeExtension` or inherited widget
- **Serialization** - Save and restore layout state with `save()` / `load()`
- **Maximize/Restore** - Expand any pane to full area
- **Auto-hide** - Panels collapse when resized below threshold
- **Keyboard Accessibility** - Tab to focus resizers, arrow keys to resize
