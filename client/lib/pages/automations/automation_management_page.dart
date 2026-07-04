import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/app_keys.dart';
import 'automation_sort.dart';
import 'automations_management_tab.dart';

/// Global automations management page embedded in [HomeGlobalSection].
class AutomationManagementPage extends StatefulWidget {
  const AutomationManagementPage({super.key});

  @override
  State<AutomationManagementPage> createState() =>
      _AutomationManagementPageState();
}

class _AutomationManagementPageState extends State<AutomationManagementPage> {
  AutomationSort _sort = AutomationSort.nameAsc;
  var _filterPanelVisible = false;
  AutomationEnabledFilter _enabledFilter = AutomationEnabledFilter.all;
  AutomationActionFilter _actionFilter = AutomationActionFilter.all;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return ColoredBox(
      key: AppKeys.automationsWorkspace,
      color: cs.workspaceCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.automationsTitle,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: cs.onSurface),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Expanded(
            child: AutomationsManagementTab(
              sort: _sort,
              onSortChanged: (sort) => setState(() => _sort = sort),
              filterPanelVisible: _filterPanelVisible,
              onToggleFilterPanel: () => setState(
                () => _filterPanelVisible = !_filterPanelVisible,
              ),
              enabledFilter: _enabledFilter,
              onEnabledFilterChanged: (filter) =>
                  setState(() => _enabledFilter = filter),
              actionFilter: _actionFilter,
              onActionFilterChanged: (filter) =>
                  setState(() => _actionFilter = filter),
            )
                .animate(key: const ValueKey('home-all-automations'))
                .fadeIn(duration: 180.ms, curve: Curves.easeOut)
                .slideX(
                  begin: 0.025,
                  end: 0,
                  duration: 220.ms,
                  curve: Curves.easeOutCubic,
                ),
          ),
        ],
      ),
    );
  }
}
