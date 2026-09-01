import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';

class LayoutRegionVisibilitySection extends StatelessWidget {
  const LayoutRegionVisibilitySection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<LayoutCubit>();

    return BlocSelector<
      LayoutCubit,
      LayoutState,
      (bool, bool, bool, bool, bool, bool)
    >(
      selector: (state) => (
        state.preferences.rightToolsVisible,
        state.preferences.sessionTabBarVisible,
        state.preferences.membersVisible,
        state.preferences.fileTreeVisible,
        state.preferences.gitVisible,
        state.preferences.boardVisible,
      ),
      builder: (context, visibility) {
        final (
          rightToolsVisible,
          sessionTabBarVisible,
          membersVisible,
          fileTreeVisible,
          gitVisible,
          boardVisible,
        ) = visibility;

        void setVisibility({
          bool? membersVisible,
          bool? fileTreeVisible,
          bool? gitVisible,
          bool? boardVisible,
        }) {
          controller.setRegionVisibility(
            appRailVisible: true,
            membersVisible: membersVisible ?? visibility.$3,
            fileTreeVisible: fileTreeVisible ?? visibility.$4,
            gitVisible: gitVisible ?? visibility.$5,
            boardVisible: boardVisible ?? visibility.$6,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpSectionHeader(title: l10n.regionVisibility),
            TpPreferenceRow(
              title: l10n.rightTools,
              subtitle: l10n.visibilityRightToolsHint,
              trailing: Switch(
                key: AppKeys.rightToolsVisibilitySwitch,
                value: rightToolsVisible,
                onChanged: controller.setRightToolsVisible,
              ),
              showDividerBelow: true,
            ),
            TpPreferenceRow(
              title: l10n.sessionTabBarTitle,
              subtitle: l10n.sessionTabBarVisibilityHint,
              trailing: Switch(
                key: AppKeys.sessionTabBarVisibilitySwitch,
                value: sessionTabBarVisible,
                onChanged: controller.setSessionTabBarVisible,
              ),
              showDividerBelow: true,
            ),
            TpPreferenceRow(
              title: l10n.members,
              subtitle: l10n.visibilityMembersHint,
              trailing: Switch(
                key: AppKeys.membersVisibilitySwitch,
                value: membersVisible,
                onChanged: (value) => setVisibility(membersVisible: value),
              ),
              showDividerBelow: true,
            ),
            TpPreferenceRow(
              title: l10n.fileTree,
              subtitle: l10n.visibilityFileTreeHint,
              trailing: Switch(
                key: AppKeys.fileTreeVisibilitySwitch,
                value: fileTreeVisible,
                onChanged: (value) => setVisibility(fileTreeVisible: value),
              ),
              showDividerBelow: true,
            ),
            TpPreferenceRow(
              title: l10n.sourceControl,
              subtitle: l10n.visibilityGitHint,
              trailing: Switch(
                value: gitVisible,
                onChanged: (value) => setVisibility(gitVisible: value),
              ),
              showDividerBelow: true,
            ),
            TpPreferenceRow(
              title: l10n.board,
              subtitle: l10n.visibilityBoardHint,
              trailing: Switch(
                key: AppKeys.boardVisibilitySwitch,
                value: boardVisible,
                onChanged: (value) => setVisibility(boardVisible: value),
              ),
              showDividerBelow: false,
            ),
          ],
        );
      },
    );
  }
}
