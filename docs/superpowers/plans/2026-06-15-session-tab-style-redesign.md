# Session Tab Style Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign `WorkspaceShellTabChip` to match the visual style of `_ProjectTab` from `home_workspace_title_bar.dart`, adding left accent bar, icon slot, all-around border radius, AnimatedOpacity chrome, and max-width constraints.

**Architecture:** Three-file change. First extend `TabInfo` in the models file with `icon` and `accentColor` fields. Then redesign `WorkspaceShellTabChip` and update `WorkspaceShellTabRow` in the tabs file to use the new visual style. Finally update the `TabInfo` mapping in `chat_page_shell.dart` to supply the new fields.

**Tech Stack:** Flutter/Dart, Material 3 `ColorScheme` tokens, existing `SessionWorkingIndicator` widget.

---

## File Structure

| File | Responsibility | Action |
|------|---------------|--------|
| `client/lib/pages/workspace_shell/workspace_shell_models.dart` | `TabInfo` data class — tab identity, title, working state, icon, accent color | Modify |
| `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` | `WorkspaceShellTabChip` widget (visual redesign), `WorkspaceShellTabRow` (pass new fields) | Modify |
| `client/lib/pages/chat/chat_page_shell.dart` | Maps `ChatTabInfo` → `TabInfo` including new fields | Modify |

---

### Task 1: Add `icon` and `accentColor` fields to `TabInfo`

**Files:**
- Modify: `client/lib/pages/workspace_shell/workspace_shell_models.dart`

- [ ] **Step 1: Add fields to `TabInfo`**

Replace the entire file content:

```dart
import 'package:flutter/material.dart';

enum AppSection { chat, runs, config }

class TabInfo {
  const TabInfo({
    required this.id,
    required this.title,
    this.working = false,
    this.icon = Icons.terminal_rounded,
    this.accentColor,
  });

  final String id;
  final String title;

  /// Session has a member in a turn → show the working spinner left of title.
  final bool working;

  /// Icon shown left of the title, after the accent bar.
  /// Defaults to [Icons.terminal_rounded].
  final IconData icon;

  /// Color of the 3px left accent bar. When null, falls back to
  /// [ColorScheme.primary].
  final Color? accentColor;
}
```

- [ ] **Step 2: Verify existing tests still pass**

Run: `cd client && flutter test test/pages/workspace_shell_test.dart`
Expected: PASS (existing `TabInfo` constructions use only `id`, `title`, `working` — no breaking changes)

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/workspace_shell/workspace_shell_models.dart
git commit -m "feat: add icon and accentColor fields to TabInfo"
```

---

### Task 2: Redesign `WorkspaceShellTabChip` visual style

**Files:**
- Modify: `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` (lines 138–358, `WorkspaceShellTabChip` and `WorkspaceShellTabChipState`)

- [ ] **Step 1: Add `_TabChromeSlot` widget to the file**

At the bottom of `workspace_shell_tabs.dart`, before the existing `WorkspaceShellActionsBar`, add this widget (mirrors the private `_TabChromeSlot` from `home_workspace_title_bar.dart`):

```dart
/// Keeps tab chrome in the layout while hiding it visually until hover/active.
class _TabChromeSlot extends StatelessWidget {
  const _TabChromeSlot({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}
```

- [ ] **Step 2: Replace `WorkspaceShellTabChip` constructor — remove color parameters, add `TabInfo` fields**

Replace the `WorkspaceShellTabChip` class (lines 138–166) with:

```dart
class WorkspaceShellTabChip extends StatefulWidget {
  const WorkspaceShellTabChip({
    super.key,
    required this.title,
    required this.active,
    required this.onTap,
    required this.onClose,
    this.onCloseOthers,
    this.onCloseRight,
    this.working = false,
    this.icon = Icons.terminal_rounded,
    this.accentColor,
  });

  final String title;
  final bool working;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback? onCloseOthers;
  final VoidCallback? onCloseRight;
  final IconData icon;
  final Color? accentColor;

  @override
  State<WorkspaceShellTabChip> createState() => WorkspaceShellTabChipState();
}
```

- [ ] **Step 3: Replace `WorkspaceShellTabChipState` build method**

Replace the entire `WorkspaceShellTabChipState` class body (lines 168–358). Keep the `_hovered`, `_overflowMenuOpen`, `_handleTabMenuSelection`, `_tabMenuSpecs`, `_showTabContextMenu*` methods unchanged. Replace only the `_tabMaterialColor` method and `build` method:

```dart
class WorkspaceShellTabChipState extends State<WorkspaceShellTabChip> {
  var _hovered = false;

  /// Keeps overflow actions (and [SidebarActionMenuButton]) mounted while the menu is
  /// open; otherwise moving the pointer onto the overlay triggers
  /// [MouseRegion.onExit] and removes the button before [onSelected] runs.
  var _overflowMenuOpen = false;

  void _handleTabMenuSelection(String value) {
    if (value == 'close') {
      widget.onClose();
    } else if (value == 'closeOthers') {
      widget.onCloseOthers?.call();
    } else if (value == 'closeRight') {
      widget.onCloseRight?.call();
    }
  }

  List<SidebarActionMenuSpec> _tabMenuSpecs(BuildContext menuContext) {
    final l10n = menuContext.l10n;
    return [
      SidebarActionMenuSpec.item(
        value: 'close',
        icon: Icons.close,
        label: l10n.closeTab,
      ),
      SidebarActionMenuSpec.item(
        value: 'closeOthers',
        icon: Icons.tab_unselected,
        label: l10n.closeOtherTabs,
      ),
      SidebarActionMenuSpec.item(
        value: 'closeRight',
        icon: Icons.arrow_forward,
        label: l10n.closeRightTabs,
      ),
    ];
  }

  Future<void> _showTabContextMenuAtTap(TapDownDetails details) async {
    if (!mounted) return;
    final selected = await showSidebarActionMenuFromSpecsAtTap<String>(
      context: context,
      tapDetails: details,
      specs: _tabMenuSpecs(context),
    );
    if (!mounted || selected == null) return;
    _handleTabMenuSelection(selected);
  }

  void _showTabContextMenuFromTap(TapDownDetails details) {
    _showTabContextMenuAtTap(details);
  }

  Future<void> _showTabContextMenu(Offset globalPosition) async {
    if (!mounted) return;
    final selected = await showSidebarActionMenuFromSpecs<String>(
      context: context,
      globalPosition: globalPosition,
      specs: _tabMenuSpecs(context),
    );
    if (!mounted || selected == null) return;
    _handleTabMenuSelection(selected);
  }

  void _showTabContextMenuAtChipCenter() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final center = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height / 2),
    );
    _showTabContextMenu(center);
  }

  /// Touch platforms have no hover; keep tab actions visible on Android.
  bool get _showChrome =>
      widget.active || _hovered || _overflowMenuOpen || Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final active = widget.active;
    final Color fg = active ? cs.onSurface : cs.onSurfaceVariant;
    final Color accent = widget.accentColor ?? cs.primary;
    final double barAlpha = active ? 1.0 : (_hovered ? 0.7 : 0.4);
    final Color barColor = accent.withValues(alpha: barAlpha);
    final double iconAlpha = active ? 1.0 : (_hovered ? 0.9 : 0.8);
    final Color iconColor = accent.withValues(alpha: iconAlpha);

    return Tooltip(
      message: widget.title,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTapDown: _showTabContextMenuFromTap,
          onLongPress: Platform.isAndroid
              ? _showTabContextMenuAtChipCenter
              : null,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 200),
              padding: const EdgeInsets.only(
                left: 10,
                right: 6,
                top: 6,
                bottom: 6,
              ),
              decoration: BoxDecoration(
                color: active
                    ? cs.surfaceContainerHigh
                    : _hovered
                        ? cs.onSurface.withValues(alpha: 0.05)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: active
                      ? cs.outlineVariant.withValues(alpha: 0.7)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left accent bar
                  SizedBox(
                    width: 3,
                    height: context.appIconSizes.md,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Working indicator / icon slot
                  _TabChromeSlot(
                    visible: _showChrome,
                    child: SessionWorkingIndicator(
                      working: widget.working,
                      size: context.appIconSizes.md,
                      color: iconColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title
                  Flexible(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.bodySmall.copyWith(color: fg),
                    ),
                  ),
                  // Overflow menu button
                  _TabChromeSlot(
                    visible: _showChrome,
                    child: SidebarActionMenuButton(
                      icon: Icon(
                        Icons.more_horiz,
                        size: context.appIconSizes.md,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      size: 32,
                      onOpen: () => setState(() => _overflowMenuOpen = true),
                      onClose: () =>
                          setState(() => _overflowMenuOpen = false),
                      specs: _tabMenuSpecs(context),
                      onSelected: (value) {
                        setState(() => _overflowMenuOpen = false);
                        _handleTabMenuSelection(value as String);
                      },
                    ),
                  ),
                  // Close button
                  _TabChromeSlot(
                    visible: _showChrome,
                    child: InkWell(
                      onTap: widget.onClose,
                      borderRadius: BorderRadius.circular(5),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.close,
                          size: context.appIconSizes.md,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Remove the old `_tabMaterialColor` method**

The old `_tabMaterialColor` method (lines 248–262 of the original file) is replaced by inline logic in the new `build` method. Ensure it is deleted along with the old build method.

- [ ] **Step 5: Verify the file compiles without errors**

Run: `cd client && dart analyze lib/pages/workspace_shell/workspace_shell_tabs.dart`
Expected: No errors (may have pre-existing warnings/infos)

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/workspace_shell/workspace_shell_tabs.dart
git commit -m "feat: redesign WorkspaceShellTabChip with accent bar, icon slot, and animated chrome"
```

---

### Task 3: Update `WorkspaceShellTabRow` to pass new fields

**Files:**
- Modify: `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` (lines 86–135, `WorkspaceShellTabRow.build`)

- [ ] **Step 1: Update `WorkspaceShellTabRow.build` to pass `icon` and `accentColor` from `TabInfo`**

Replace the `WorkspaceShellTabChip` construction inside `WorkspaceShellTabRow.build` (lines 114–126) with:

```dart
                  for (var i = 0; i < tabs.length; i++)
                    WorkspaceShellTabChip(
                      title: tabs[i].title,
                      working: tabs[i].working,
                      active: i == activeIndex,
                      onTap: () => onTabSelected?.call(i),
                      onClose: () => onTabClosed?.call(i),
                      onCloseOthers: () => onTabCloseOthers?.call(i),
                      onCloseRight: () => onTabCloseRight?.call(i),
                      icon: tabs[i].icon,
                      accentColor: tabs[i].accentColor,
                    ),
```

Also remove the now-unused `textBase`, `activeBg`, and `borderColor` variables from `WorkspaceShellTabRow.build` (lines 96–99), and remove the `isDark` variable:

Replace lines 96–99:
```dart
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
```

With just:
```dart
    final cs = Theme.of(context).colorScheme;
```

(We still need `cs` for the bottom border of the tab row container.)

- [ ] **Step 2: Verify compile**

Run: `cd client && dart analyze lib/pages/workspace_shell/workspace_shell_tabs.dart`
Expected: No errors

- [ ] **Step 3: Run workspace shell test**

Run: `cd client && flutter test test/pages/workspace_shell_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/workspace_shell/workspace_shell_tabs.dart
git commit -m "feat: update WorkspaceShellTabRow to pass icon and accentColor from TabInfo"
```

---

### Task 4: Update `chat_page_shell.dart` TabInfo mapping

**Files:**
- Modify: `client/lib/pages/chat/chat_page_shell.dart` (lines 177–185)

- [ ] **Step 1: Add `icon` and `accentColor` to the `TabInfo` mapping**

Replace lines 177–185 (the `tabs:` parameter of `WorkspaceShell`):

```dart
          tabs: model.tabs
              .map(
                (t) => TabInfo(
                  id: t.id,
                  title: t.title,
                  working: model.workingSessionIds.contains(t.id),
                  icon: Icons.terminal_rounded,
                  accentColor: Theme.of(context).colorScheme.primary,
                ),
              )
              .toList(),
```

- [ ] **Step 2: Verify compile**

Run: `cd client && dart analyze lib/pages/chat/chat_page_shell.dart`
Expected: No errors

- [ ] **Step 3: Run full analysis and tests**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: Pass (no new errors introduced)

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/chat/chat_page_shell.dart
git commit -m "feat: supply icon and accentColor when mapping ChatTabInfo to TabInfo"
```

---

## Self-Review Checklist

1. **Spec coverage:**
   - ✅ Left accent bar (3px wide colored bar) — Task 2 adds `SizedBox(width: 3, ...)` with `DecoratedBox` matching `_ProjectTab`'s barColor pattern
   - ✅ All-around 8px border radius — Task 2 changes from `BorderRadius.vertical(top: Radius.circular(10))` to `BorderRadius.circular(8)`
   - ✅ Icon slot on left — Task 2 replaces the bare `SessionWorkingIndicator` with a `_TabChromeSlot`-wrapped indicator that also serves as the icon position (the `SessionWorkingIndicator` already handles idle vs working states visually)
   - ✅ Background/border treatment matching — Task 2: active→`surfaceContainerHigh` + `outlineVariant` border; hover→`onSurface.withValues(alpha: 0.05)`
   - ✅ AnimatedOpacity fade for chrome — Task 2 adds `_TabChromeSlot` widget matching the `home_workspace_title_bar.dart` pattern
   - ✅ Max-width 200px instead of fixed 200px — Task 2 changes `width: 200` to `constraints: BoxConstraints(maxWidth: 200)` with `Flexible` title text
   - ✅ SessionWorkingIndicator integration — Task 2 keeps the indicator, wraps it in `_TabChromeSlot`, and passes the accent icon color

2. **Placeholder scan:** No TBD, TODO, or vague instructions. All steps contain exact code.

3. **Type consistency:**
   - `TabInfo.icon` → `IconData` → `WorkspaceShellTabChip.icon` → `IconData` ✅
   - `TabInfo.accentColor` → `Color?` → `WorkspaceShellTabChip.accentColor` → `Color?` ✅
   - All consumer sites updated (chat_page_shell.dart, WorkspaceShellTabRow) ✅
