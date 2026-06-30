import 'package:flutter/material.dart';

import '../../theme/workspace_surface_layers.dart';
import 'home_workspace_content_header.dart';
import 'workspace_pane_animations.dart';

/// Shared chrome for home workspace identity panes (personal + team):
/// header, horizontal tab bar, divider, animated tab body.
class HomeIdentityContentShell extends StatelessWidget {
  const HomeIdentityContentShell({
    required this.header,
    required this.tabs,
    required this.selectedTabIndex,
    required this.onTabSelected,
    required this.tabBody,
    required this.bodyAnimationKey,
    super.key,
  });

  final Widget header;
  final List<String> tabs;
  final int selectedTabIndex;
  final ValueChanged<int> onTabSelected;
  final Widget tabBody;

  /// Drives tab-body entry motion (identity id + tab index), matching personal.
  final Key bodyAnimationKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.workspaceCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 14),
          HomeContentTabBar(
            tabs: tabs,
            selectedIndex: selectedTabIndex,
            onSelect: onTabSelected,
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Expanded(
            child: WorkspacePaneAnimations.data(tabBody, key: bodyAnimationKey),
          ),
        ],
      ),
    );
  }
}
