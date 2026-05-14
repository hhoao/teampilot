import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_keys.dart';
import '../models/layout_preferences.dart';
import '../widgets/resizable_split_view.dart';

enum AppSection { chat, runs, config }

class TabInfo {
  const TabInfo({required this.id, required this.title});

  final String id;
  final String title;
}

class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({
    required this.breadcrumb,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.child,
    this.showHeader = true,
    this.tabs = const [],
    this.activeTabIndex = 0,
    this.onTabSelected,
    this.onTabClosed,
    this.onTabCloseOthers,
    this.onTabCloseRight,
    this.layoutPreferences = const LayoutPreferences(),
    this.onRightToolsWidthChanged,
    this.rightTools,
    super.key,
  });

  final String breadcrumb;
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final Widget child;
  final bool showHeader;
  final List<TabInfo> tabs;
  final int activeTabIndex;
  final ValueChanged<int>? onTabSelected;
  final ValueChanged<int>? onTabClosed;
  final ValueChanged<int>? onTabCloseOthers;
  final ValueChanged<int>? onTabCloseRight;
  final LayoutPreferences layoutPreferences;
  final ValueChanged<double>? onRightToolsWidthChanged;
  final Widget? rightTools;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    return Column(
      children: [
        if (showHeader)
          Container(
            key: AppKeys.workspaceTopbar,
            height: 82.0 * textScale,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        breadcrumb,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textBase.withValues(alpha: 0.52),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: textBase,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textBase.withValues(alpha: 0.58),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  flex: 0,
                  child: Wrap(spacing: 8, runSpacing: 8, children: actions),
                ),
              ],
            ),
          ),
        if (tabs.isNotEmpty)
          _TabRow(
            tabs: tabs,
            activeIndex: activeTabIndex,
            onTabSelected: onTabSelected,
            onTabClosed: onTabClosed,
            onTabCloseOthers: onTabCloseOthers,
            onTabCloseRight: onTabCloseRight,
            trailing: actions.isNotEmpty && showHeader
                ? Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Wrap(spacing: 6, children: actions),
                  )
                : null,
          ),
        if (tabs.isEmpty && actions.isNotEmpty && showHeader)
          _ActionsBar(actions: actions),
        Expanded(
          child: _WorkspaceBody(
            preferences: layoutPreferences,
            rightTools: rightTools,
            onRightToolsWidthChanged: onRightToolsWidthChanged,
            child: child,
          ),
        ),
      ],
    );
  }
}

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({
    required this.preferences,
    required this.child,
    required this.rightTools,
    required this.onRightToolsWidthChanged,
  });

  final LayoutPreferences preferences;
  final Widget child;
  final Widget? rightTools;
  final ValueChanged<double>? onRightToolsWidthChanged;

  @override
  Widget build(BuildContext context) {
    if (rightTools == null) {
      return child;
    }
    if (preferences.toolPlacement == ToolPanelPlacement.bottom) {
      return Column(
        children: [
          Expanded(child: child),
          SizedBox(height: preferences.bottomToolsHeight, child: rightTools),
        ],
      );
    }
    final rightWidth = preferences.rightToolsWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        return ResizableSplitView(
          left: child,
          right: rightTools!,
          initialLeftWidth: (constraints.maxWidth - rightWidth)
              .clamp(150, constraints.maxWidth - 80),
          minLeftWidth: 150,
          maxLeftWidth: (constraints.maxWidth - 80).clamp(150, double.infinity),
          onWidthChanged: (leftWidth) {
            onRightToolsWidthChanged
                ?.call(constraints.maxWidth - leftWidth);
          },
        );
      },
    );
  }
}


class _TabRow extends StatelessWidget {
  const _TabRow({
    required this.tabs,
    required this.activeIndex,
    this.onTabSelected,
    this.onTabClosed,
    this.onTabCloseOthers,
    this.onTabCloseRight,
    this.trailing,
  });

  final List<TabInfo> tabs;
  final int activeIndex;
  final ValueChanged<int>? onTabSelected;
  final ValueChanged<int>? onTabClosed;
  final ValueChanged<int>? onTabCloseOthers;
  final ValueChanged<int>? onTabCloseRight;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    _TabChip(
                      title: tabs[i].title,
                      active: i == activeIndex,
                      onTap: () => onTabSelected?.call(i),
                      onClose: () => onTabClosed?.call(i),
                      onCloseOthers: () => onTabCloseOthers?.call(i),
                      onCloseRight: () => onTabCloseRight?.call(i),
                      textColor: textBase,
                      activeBg: cs.primaryContainer,
                      borderColor: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                ],
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _TabChip extends StatefulWidget {
  const _TabChip({
    required this.title,
    required this.active,
    required this.onTap,
    required this.onClose,
    this.onCloseOthers,
    this.onCloseRight,
    required this.textColor,
    required this.activeBg,
    required this.borderColor,
  });

  final String title;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback? onCloseOthers;
  final VoidCallback? onCloseRight;
  final Color textColor;
  final Color activeBg;
  final Color borderColor;

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  var _hovered = false;
  /// Keeps overflow actions (and [PopupMenuButton]) mounted while the menu is
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

  List<PopupMenuEntry<String>> _tabMenuEntries(BuildContext menuContext) {
    final l10n = menuContext.l10n;
    return [
      PopupMenuItem(value: 'close', child: Text(l10n.closeTab)),
      PopupMenuItem(value: 'closeOthers', child: Text(l10n.closeOtherTabs)),
      PopupMenuItem(value: 'closeRight', child: Text(l10n.closeRightTabs)),
    ];
  }

  Future<void> _showTabContextMenu(Offset globalPosition) async {
    if (!mounted) return;
    final overlayObject =
        Overlay.maybeOf(context)?.context.findRenderObject();
    if (overlayObject is! RenderBox) return;

    final anchor = overlayObject.globalToLocal(globalPosition);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(anchor, anchor),
        Offset.zero & overlayObject.size,
      ),
      items: _tabMenuEntries(context),
    );
    if (!mounted || selected == null) return;
    _handleTabMenuSelection(selected);
  }

  /// Whole-tab hover from [MouseRegion]. Avoids [InkWell] + nested
  /// [PopupMenuButton] ink fighting (hover patch only behind title text).
  Color _tabMaterialColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hoverTint =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.10);
    if (widget.active) {
      return _hovered
          ? Color.alphaBlend(hoverTint, widget.activeBg)
          : widget.activeBg;
    }
    if (_hovered) {
      return Color.alphaBlend(hoverTint, cs.surfaceContainer);
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Tooltip(
        message: widget.title,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: _tabMaterialColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              onSecondaryTapUp: (details) =>
                  _showTabContextMenu(details.globalPosition),
              child: Container(
                width: 200,
                padding: const EdgeInsets.only(left: 12, top: 6, right: 12),
                height: 42,
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: widget.active
                          ? widget.borderColor
                          : Colors.transparent,
                    ),
                    right: BorderSide(
                      color: widget.active
                          ? widget.borderColor
                          : Colors.transparent,
                    ),
                    top: BorderSide(
                      color: widget.active
                          ? widget.borderColor
                          : Colors.transparent,
                    ),
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: widget.textColor,
                          ),
                        ),
                      ),
                    ),
                    if (_hovered || _overflowMenuOpen) ...[
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        tooltip: '',
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.more_horiz,
                          size: 12,
                          color: widget.textColor.withValues(alpha: 0.6),
                        ),
                        onOpened: () =>
                            setState(() => _overflowMenuOpen = true),
                        onCanceled: () =>
                            setState(() => _overflowMenuOpen = false),
                        onSelected: (value) {
                          setState(() => _overflowMenuOpen = false);
                          _handleTabMenuSelection(value);
                        },
                        itemBuilder: _tabMenuEntries,
                      ),
                      GestureDetector(
                        onTap: widget.onClose,
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: widget.textColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionsBar extends StatelessWidget {
  const _ActionsBar({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          const Spacer(),
          Wrap(spacing: 6, children: actions),
        ],
      ),
    );
  }
}
