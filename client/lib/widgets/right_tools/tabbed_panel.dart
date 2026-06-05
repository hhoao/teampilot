import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../theme/app_icon_sizes.dart';

/// VSCode-style tool panel: a horizontal row of icon buttons at the top
/// switches the single visible view (members / file tree / git).
///
/// The icon entries are built from the same visibility flags, in the same
/// order, as the `panels` list supplied by [RightToolsPanel], so index `i`
/// always pairs with `panels[i]`.
class TabbedPanel extends StatefulWidget {
  const TabbedPanel({
    required this.panels,
    required this.preferences,
    super.key,
  });

  final List<Widget> panels;
  final LayoutPreferences preferences;

  @override
  State<TabbedPanel> createState() => _TabbedPanelState();
}

class _TabbedPanelState extends State<TabbedPanel> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    final entries = <_ViewEntry>[
      if (widget.preferences.membersVisible)
        _ViewEntry(Icons.groups_outlined, l10n.members),
      if (widget.preferences.fileTreeVisible)
        _ViewEntry(Icons.folder_outlined, l10n.fileTree),
      if (widget.preferences.gitVisible)
        _ViewEntry(Icons.account_tree_outlined, l10n.sourceControl),
    ];

    if (widget.panels.isEmpty) return const SizedBox.shrink();
    // A single view needs no switcher chrome.
    if (widget.panels.length == 1) return widget.panels.single;

    final selected = _selected.clamp(0, widget.panels.length - 1);

    return Column(
      children: [
        _ViewSwitcherBar(
          entries: entries,
          selected: selected,
          onSelected: (i) => setState(() => _selected = i),
        ),
        Divider(height: 1, thickness: 1, color: cs.outlineVariant),
        Expanded(
          child: IndexedStack(
            index: selected,
            sizing: StackFit.expand,
            children: widget.panels,
          ),
        ),
      ],
    );
  }
}

class _ViewEntry {
  const _ViewEntry(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// Horizontal activity-bar-style row of icon buttons.
class _ViewSwitcherBar extends StatelessWidget {
  const _ViewSwitcherBar({
    required this.entries,
    required this.selected,
    required this.onSelected,
  });

  final List<_ViewEntry> entries;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          for (var i = 0; i < entries.length; i++)
            _ViewSwitcherButton(
              entry: entries[i],
              active: i == selected,
              onTap: () => onSelected(i),
            ),
        ],
      ),
    );
  }
}

class _ViewSwitcherButton extends StatelessWidget {
  const _ViewSwitcherButton({
    required this.entry,
    required this.active,
    required this.onTap,
  });

  final _ViewEntry entry;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = active ? cs.primary : cs.onSurfaceVariant;
    return Tooltip(
      message: entry.label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? cs.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Icon(entry.icon, size: AppIconSizes.md, color: color),
        ),
      ),
    );
  }
}
