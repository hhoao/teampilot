import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../widgets/settings/workspace_settings_toggle_strip.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';

class LayoutToolSettingsSection extends StatelessWidget {
  const LayoutToolSettingsSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<LayoutCubit>();

    return BlocSelector<
      LayoutCubit,
      LayoutState,
      (ToolPanelPlacement, ToolsArrangement)
    >(
      selector: (state) =>
          (state.preferences.toolPlacement, state.preferences.toolsArrangement),
      builder: (context, prefs) {
        final (toolPlacement, toolsArrangement) = prefs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsLabeledRow(
              title: l10n.toolPlacement,
              subtitle: l10n.toolPlacementDescription,
              trailing: WorkspaceSettingsToggleStrip<ToolPanelPlacement>(
                segments: [
                  WorkspaceToggleSegment<ToolPanelPlacement>(
                    value: ToolPanelPlacement.right,
                    label: l10n.right,
                    icon: Icons.vertical_split_outlined,
                  ),
                  WorkspaceToggleSegment<ToolPanelPlacement>(
                    value: ToolPanelPlacement.bottom,
                    label: l10n.bottom,
                    icon: Icons.splitscreen_outlined,
                  ),
                ],
                selected: toolPlacement,
                onChanged: controller.setToolPlacement,
              ),
              showDividerBelow: true,
            ),
            SettingsLabeledRow(
              title: l10n.membersAndFileTree,
              subtitle: l10n.membersAndFileTreeDescription,
              trailing: WorkspaceSettingsToggleStrip<ToolsArrangement>(
                segments: [
                  WorkspaceToggleSegment<ToolsArrangement>(
                    value: ToolsArrangement.stacked,
                    label: l10n.stacked,
                    icon: Icons.view_agenda_outlined,
                  ),
                  WorkspaceToggleSegment<ToolsArrangement>(
                    value: ToolsArrangement.tabs,
                    label: l10n.tabs,
                    icon: Icons.tab_outlined,
                  ),
                ],
                selected: toolsArrangement,
                onChanged: controller.setToolsArrangement,
              ),
              showDividerBelow: false,
            ),
          ],
        );
      },
    );
  }
}
