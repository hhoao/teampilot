import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';

/// Tabbed layout for tool panels (members / file tree / git).
class TabbedPanel extends StatelessWidget {
  const TabbedPanel({
    required this.panels,
    required this.preferences,
    super.key,
  });

  final List<Widget> panels;
  final LayoutPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tabs = <Tab>[
      if (preferences.membersVisible) Tab(text: l10n.members),
      if (preferences.fileTreeVisible) Tab(text: l10n.fileTree),
      if (preferences.gitVisible) Tab(text: l10n.sourceControl),
    ];
    return DefaultTabController(
      length: panels.length,
      child: Column(
        children: [
          TabBar(tabs: tabs, isScrollable: true),
          Expanded(child: TabBarView(children: panels)),
        ],
      ),
    );
  }
}
