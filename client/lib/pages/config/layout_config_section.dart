import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import 'layout_appearance_in_layout_section.dart';
import 'layout_region_visibility_section.dart';

class LayoutConfigWorkspace extends StatelessWidget {
  const LayoutConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) WorkspacePaneHeader(title: l10n.layout),
        const Expanded(child: _LayoutSettingsScroll()),
      ],
    );
  }
}

class _LayoutSettingsScroll extends StatelessWidget {
  const _LayoutSettingsScroll();

  static const _cardGap = 12.0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          TpCard.outlined(child: LayoutRegionVisibilitySection()),
          SizedBox(height: _cardGap),
          TpCard.outlined(child: LayoutAppearanceInLayoutSection()),
        ],
      ),
    );
  }
}
