import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../../widgets/settings/workspace_settings_toggle_strip.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
class AppearanceConfigWorkspace extends StatelessWidget {
  const AppearanceConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<LayoutCubit>();

    return BlocSelector<LayoutCubit, LayoutState, WorkspaceEntryMode>(
      selector: (state) => state.preferences.workspaceEntryMode,
      builder: (context, mode) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeading) ...[
              WorkspaceSectionHeading(
                title: l10n.appearance,
                subtitle: l10n.appearancePageSubtitle,
              ),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: SingleChildScrollView(
                child: SettingsSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SettingsGroupHeader(title: l10n.appearance),
                      SettingsLabeledRow(
                        title: l10n.workspaceEntryModeTitle,
                        subtitle: l10n.workspaceEntryModeDescription,
                        trailing: WorkspaceSettingsToggleStrip<
                          WorkspaceEntryMode
                        >(
                          segments: [
                            WorkspaceToggleSegment<WorkspaceEntryMode>(
                              value: WorkspaceEntryMode.home,
                              label: l10n.workspaceEntryModeHome,
                              icon: Icons.home_outlined,
                            ),
                            WorkspaceToggleSegment<WorkspaceEntryMode>(
                              value: WorkspaceEntryMode.hub,
                              label: l10n.workspaceEntryModeHub,
                              icon: Icons.workspaces_outlined,
                            ),
                          ],
                          selected: mode,
                          onChanged:
                              controller.setWorkspaceEntryMode,
                        ),
                        showDividerBelow: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
