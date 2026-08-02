import 'dart:io';

import 'package:flutter/material.dart';

import 'workspace_pane_header.dart';
import 'workspace_pane_insets.dart';
import 'workspace_section_nav_item.dart';
import 'workspace_section_tab_bar.dart';

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
    final showHeader = !(Platform.isAndroid && !embedded);
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
