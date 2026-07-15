import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/menu/sidebar_action_menu.dart';
import '../home_workspace/workspaces_tab.dart';
import 'automation_sort.dart';
import 'automations_list_body.dart';

/// Toolbar + optional filter panel + list — mirrors [WorkspacesTab] layout.
class AutomationsManagementTab extends StatelessWidget {
  const AutomationsManagementTab({
    required this.sort,
    required this.onSortChanged,
    required this.filterPanelVisible,
    required this.onToggleFilterPanel,
    required this.enabledFilter,
    required this.onEnabledFilterChanged,
    required this.actionFilter,
    required this.onActionFilterChanged,
    super.key,
  });

  final AutomationSort sort;
  final ValueChanged<AutomationSort> onSortChanged;
  final bool filterPanelVisible;
  final VoidCallback onToggleFilterPanel;
  final AutomationEnabledFilter enabledFilter;
  final ValueChanged<AutomationEnabledFilter> onEnabledFilterChanged;
  final AutomationActionFilter actionFilter;
  final ValueChanged<AutomationActionFilter> onActionFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutomationsToolbar(
          sort: sort,
          onSortChanged: onSortChanged,
          filterPanelVisible: filterPanelVisible,
          onToggleFilterPanel: onToggleFilterPanel,
        ),
        if (filterPanelVisible) ...[
          const SizedBox(height: 12),
          AutomationsFilterPanel(
            enabledFilter: enabledFilter,
            onEnabledFilterChanged: onEnabledFilterChanged,
            actionFilter: actionFilter,
            onActionFilterChanged: onActionFilterChanged,
          ),
        ],
        const SizedBox(height: 16),
        Expanded(
          child: AutomationsListBody(
            sort: sort,
            enabledFilter: enabledFilter,
            actionFilter: actionFilter,
          ),
        ),
      ],
    );
  }
}

class AutomationsToolbar extends StatelessWidget {
  const AutomationsToolbar({
    required this.sort,
    required this.onSortChanged,
    required this.filterPanelVisible,
    required this.onToggleFilterPanel,
    super.key,
  });

  final AutomationSort sort;
  final ValueChanged<AutomationSort> onSortChanged;
  final bool filterPanelVisible;
  final VoidCallback onToggleFilterPanel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        AutomationsSortButton(sort: sort, onSortChanged: onSortChanged),
        const SizedBox(width: 8),
        WorkspacesIconChip(
          icon: filterPanelVisible ? Icons.filter_list_off : Icons.filter_list,
          tooltip: filterPanelVisible
              ? l10n.automationsHideFilter
              : l10n.automationsShowFilter,
          onTap: onToggleFilterPanel,
        ),
        const Spacer(),
      ],
    );
  }
}

class AutomationsSortButton extends StatelessWidget {
  const AutomationsSortButton({
    required this.sort,
    required this.onSortChanged,
    super.key,
  });

  final AutomationSort sort;
  final ValueChanged<AutomationSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SidebarActionMenuIconAnchor(
      minWidth: 220,
      triggerBuilder: (context, controller) {
        return WorkspacesIconChip(
          icon: Icons.sort_rounded,
          tooltip: l10n.automationsSort,
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
      buildMenuChildren: (context, controller) {
        return [
          for (final value in AutomationSort.values)
            SidebarActionMenuItem(
              icon: _iconForSort(value),
              label: value.label(l10n),
              trailing: sort == value
                  ? Icon(
                      Icons.check,
                      size: context.tpIconSizes.md,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    )
                  : null,
              menuController: controller,
              onTap: () => onSortChanged(value),
            ),
        ];
      },
    );
  }

  static IconData _iconForSort(AutomationSort sort) => switch (sort) {
    AutomationSort.nameAsc => Icons.sort_by_alpha_rounded,
    AutomationSort.nameDesc => Icons.sort_by_alpha_rounded,
    AutomationSort.nextRunAsc => Icons.schedule_rounded,
    AutomationSort.recentlyUpdated => Icons.update_rounded,
  };
}

class AutomationsFilterPanel extends StatelessWidget {
  const AutomationsFilterPanel({
    required this.enabledFilter,
    required this.onEnabledFilterChanged,
    required this.actionFilter,
    required this.onActionFilterChanged,
    super.key,
  });

  final AutomationEnabledFilter enabledFilter;
  final ValueChanged<AutomationEnabledFilter> onEnabledFilterChanged;
  final AutomationActionFilter actionFilter;
  final ValueChanged<AutomationActionFilter> onActionFilterChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.automationsFilterStatusLabel,
            style: TpTextStyles.of(context).smSemiboldColored(cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in AutomationEnabledFilter.values)
                _FilterPill(
                  label: _enabledFilterLabel(l10n, value),
                  selected: enabledFilter == value,
                  onTap: () => onEnabledFilterChanged(value),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            l10n.automationsFilterActionLabel,
            style: TpTextStyles.of(context).smSemiboldColored(cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in AutomationActionFilter.values)
                _FilterPill(
                  label: _actionFilterLabel(l10n, value),
                  selected: actionFilter == value,
                  onTap: () => onActionFilterChanged(value),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _enabledFilterLabel(
    AppLocalizations l10n,
    AutomationEnabledFilter filter,
  ) => switch (filter) {
    AutomationEnabledFilter.all => l10n.automationsFilterAll,
    AutomationEnabledFilter.enabledOnly => l10n.automationsFilterEnabled,
    AutomationEnabledFilter.disabledOnly => l10n.automationsFilterDisabled,
  };

  static String _actionFilterLabel(
    AppLocalizations l10n,
    AutomationActionFilter filter,
  ) => switch (filter) {
    AutomationActionFilter.all => l10n.automationsFilterActionAll,
    AutomationActionFilter.scheduledMessage =>
      l10n.automationsFilterScheduledMessage,
    AutomationActionFilter.launchPrompt => l10n.automationsFilterLaunchPrompt,
  };
}

class _FilterPill extends StatefulWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FilterPill> createState() => _FilterPillState();
}

class _FilterPillState extends State<_FilterPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final selected = widget.selected;
    final restingBg = selected
        ? cs.primary.withValues(alpha: 0.14)
        : cs.surfaceContainer;
    final hoverTint = cs.onSurface.withValues(alpha: 0.06);
    final background = _hovered
        ? Color.alphaBlend(hoverTint, restingBg)
        : restingBg;
    final borderColor = selected
        ? cs.primary.withValues(alpha: 0.45)
        : cs.outlineVariant.withValues(alpha: 0.65);
    final foreground = selected ? cs.primary : cs.onSurfaceVariant;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            widget.label,
            style: selected
                ? styles.smSemiboldColored(foreground)
                : styles.smMediumColored(foreground),
          ),
        ),
      ),
    );
  }
}
