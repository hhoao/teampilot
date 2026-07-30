import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/floating_workspace_tab.dart';
import '../../theme/workspace_surface_layers.dart';

/// Horizontal tab strip for floating workspace tabs with per-tab close.
class FloatingWorkspaceTabBar extends StatelessWidget {
  const FloatingWorkspaceTabBar({
    required this.tabs,
    required this.activeTabId,
    required this.onSelect,
    required this.onClose,
    super.key,
  });

  final List<FloatingTab> tabs;
  final String? activeTabId;
  final ValueChanged<String> onSelect;
  final ValueChanged<FloatingTab> onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final selected = tab.id == activeTabId;
          return Material(
            color: selected ? cs.workspaceSubtleSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: () => onSelect(tab.id),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        tab.title,
                        overflow: TextOverflow.ellipsis,
                        style: selected
                            ? styles.smMediumColored(cs.onSurface)
                            : styles.smColored(cs.onSurfaceVariant),
                      ),
                    ),
                    TpIconButton(
                      icon: Icons.close,
                      compact: true,
                      size: 22,
                      iconSize: 14,
                      tooltip: l10n.floatingWorkspaceCloseTab,
                      onTap: () => onClose(tab),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
