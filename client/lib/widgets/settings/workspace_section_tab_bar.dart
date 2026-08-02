import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

class WorkspaceSectionTabBar extends StatelessWidget {
  const WorkspaceSectionTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            _WorkspaceSectionTabItem(
              label: tabs[i],
              selected: i == selectedIndex,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}

class _WorkspaceSectionTabItem extends StatefulWidget {
  const _WorkspaceSectionTabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_WorkspaceSectionTabItem> createState() =>
      _WorkspaceSectionTabItemState();
}

class _WorkspaceSectionTabItemState extends State<_WorkspaceSectionTabItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final selected = widget.selected;
    return TpHover(
      onTap: widget.onTap,
      onHoverChanged: (hovered) => setState(() => _hovered = hovered),
      borderRadius: BorderRadius.circular(6),
      hoverColor: selected
          ? Colors.transparent
          : cs.onSurface.withValues(alpha: 0.05),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? cs.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: selected
                ? styles.lgSemiboldColored(cs.primary)
                : styles.lgMediumColored(
                    _hovered ? cs.onSurface : cs.onSurfaceVariant,
                  ),
          ),
        ),
      ),
    );
  }
}
