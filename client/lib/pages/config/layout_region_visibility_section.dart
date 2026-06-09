import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/app_keys.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';

class LayoutRegionVisibilitySection extends StatelessWidget {
  const LayoutRegionVisibilitySection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<LayoutCubit>();

    return BlocSelector<LayoutCubit, LayoutState, (bool, bool, bool)>(
      selector: (state) => (
        state.preferences.membersVisible,
        state.preferences.fileTreeVisible,
        state.preferences.gitVisible,
      ),
      builder: (context, visibility) {
        final (membersVisible, fileTreeVisible, gitVisible) = visibility;

        void setVisibility({
          bool? membersVisible,
          bool? fileTreeVisible,
          bool? gitVisible,
        }) {
          controller.setRegionVisibility(
            appRailVisible: true,
            membersVisible: membersVisible ?? visibility.$1,
            fileTreeVisible: fileTreeVisible ?? visibility.$2,
            gitVisible: gitVisible ?? visibility.$3,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsGroupHeader(title: l10n.regionVisibility),
            SettingsLabeledRow(
              title: l10n.members,
              subtitle: l10n.visibilityMembersHint,
              trailing: Switch(
                key: AppKeys.membersVisibilitySwitch,
                value: membersVisible,
                onChanged: (value) => setVisibility(membersVisible: value),
              ),
              showDividerBelow: true,
            ),
            SettingsLabeledRow(
              title: l10n.fileTree,
              subtitle: l10n.visibilityFileTreeHint,
              trailing: Switch(
                key: AppKeys.fileTreeVisibilitySwitch,
                value: fileTreeVisible,
                onChanged: (value) => setVisibility(fileTreeVisible: value),
              ),
              showDividerBelow: true,
            ),
            SettingsLabeledRow(
              title: l10n.sourceControl,
              subtitle: l10n.visibilityGitHint,
              trailing: Switch(
                value: gitVisible,
                onChanged: (value) => setVisibility(gitVisible: value),
              ),
              showDividerBelow: false,
            ),
          ],
        );
      },
    );
  }
}
