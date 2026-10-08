import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// 条目超过 [TpActionMenuMetrics.searchThreshold] 时在顶部显示搜索框。
bool gitGraphActionMenuShowsSearchField(int searchableItemCount) =>
    searchableItemCount > TpActionMenuMetrics.searchThreshold;

/// Git 图相关 action menu：顶部固定搜索框，下方为可滚动的菜单条目。
class GitGraphFilterableActionMenuPanel extends StatelessWidget {
  const GitGraphFilterableActionMenuPanel({
    super.key,
    required this.minWidth,
    required this.showsSearchField,
    required this.searchFocus,
    required this.filterHint,
    required this.onFilterChanged,
    required this.menuChildren,
  });

  final double minWidth;
  final bool showsSearchField;
  final FocusNode searchFocus;
  final String filterHint;
  final ValueChanged<String> onFilterChanged;
  final List<Widget> menuChildren;

  @override
  Widget build(BuildContext context) {
    // Compare 菜单走 overlay（无 [TpPopover] 的透明 Material），TextField 需要祖先 Material。
    return Material(
      type: MaterialType.transparency,
      child: IntrinsicWidth(
        child: ConstrainedBox(
          constraints: TpActionMenuMetrics.panelConstraints(minWidth: minWidth),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: TpActionMenuMetrics.panelMaxHeight(context),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              if (showsSearchField) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                  child: TextField(
                    focusNode: searchFocus,
                    autofocus: true,
                    onChanged: onFilterChanged,
                    style: TpTextStyles.of(context).md,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: filterHint,
                      prefixIcon: Icon(
                        Icons.search,
                        size: TpActionMenuMetrics.iconSize(context),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const TpActionMenuDivider(),
              ],
              Flexible(
                child: TpActionMenuPanel(
                  minWidth: minWidth,
                  menuAnchorShell: true,
                  children: menuChildren,
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
