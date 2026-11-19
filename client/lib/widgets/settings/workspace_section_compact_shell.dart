import 'package:flutter/material.dart';

import '../../services/app/platform_utils.dart';
import 'workspace_pane_header.dart';
import 'workspace_pane_insets.dart';
import 'workspace_section_nav_item.dart';
import 'workspace_section_tab_bar.dart';

/// Whether the compact section shell renders [WorkspacePaneHeader].
///
/// Android hub pages are pushed routes whose shell AppBar already carries the
/// back affordance, so they skip the pane header. An inline page (e.g. the
/// workspace manage overlay rendered inside the workspace route) has no AppBar;
/// when it supplies [hasBack] it must keep the header or the user loses the
/// only way out.
@visibleForTesting
bool workspaceSectionCompactShowHeader({
  required bool androidHub,
  required bool embedded,
  required bool hasBack,
}) => !(androidHub && !embedded) || hasBack;

class WorkspaceSectionCompactShell extends StatelessWidget {
  const WorkspaceSectionCompactShell({
    required this.pageKey,
    required this.title,
    this.subtitle,
    this.showSubtitle = false,
    required this.items,
    required this.body,
    this.onBack,
    this.embedded = false,
    super.key,
  });

  final Key pageKey;
  final String title;
  final String? subtitle;
  final bool showSubtitle;
  final List<WorkspaceSectionNavItem> items;
  final Widget body;
  final VoidCallback? onBack;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showHeader = workspaceSectionCompactShowHeader(
      androidHub: useAndroidHubNavigation(context),
      embedded: embedded,
      hasBack: onBack != null,
    );
    final showTabs = items.length > 1;
    final selectedIndex = _selectedIndex(items);

    Widget column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) ...[
          WorkspacePaneHeader(
            title: title,
            subtitle: subtitle,
            showSubtitle: showSubtitle,
            onBack: onBack,
          ),
          const SizedBox(height: 14),
        ],
        if (showTabs) ...[
          WorkspaceSectionTabBar(
            tabs: [for (final item in items) item.label],
            selectedIndex: selectedIndex,
            onSelect: (index) => items[index].onSelect(),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
        ],
        Expanded(child: body),
      ],
    );

    if (!embedded) {
      column = Padding(padding: WorkspacePaneInsets.page, child: column);
    }

    return Container(key: pageKey, child: column);
  }
}

int _selectedIndex(List<WorkspaceSectionNavItem> items) {
  for (var i = 0; i < items.length; i++) {
    if (items[i].selected) return i;
  }
  return 0;
}
