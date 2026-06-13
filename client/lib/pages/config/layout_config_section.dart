import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
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
        if (showHeading) ...[
          WorkspaceSectionHeading(
            title: l10n.layout,
            subtitle: l10n.layoutPageSubtitle,
          ),
          const SizedBox(height: 16),
        ],
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
          SettingsSurfaceCard(child: LayoutRegionVisibilitySection()),
          SizedBox(height: _cardGap),
          SettingsSurfaceCard(child: LayoutAppearanceInLayoutSection()),
        ],
      ),
    );
  }
}
