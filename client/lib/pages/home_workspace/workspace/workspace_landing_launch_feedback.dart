import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../services/launch/workspace_landing_launch_gate.dart';

String landingLaunchBlockMessage(
  AppLocalizations l10n,
  WorkspaceLandingLaunchBlock block,
) {
  return switch (block) {
    TeamNotSelectedLaunchBlock() => l10n.selectTeam,
    MixedMemberPlacementUninitializedLaunchBlock() =>
      l10n.mixedWorkspaceMemberAssignmentIncomplete,
    LeadPlacementInvalidLaunchBlock() =>
      l10n.mixedWorkspaceLeadPlacementInvalid,
    TeamConfigIncompleteLaunchBlock() =>
      l10n.workspaceChatLandingTeamLaunchBlocked,
  };
}

/// Toast for submit attempts blocked by [block].
void showWorkspaceLandingLaunchBlock(
  BuildContext context,
  WorkspaceLandingLaunchBlock block,
) {
  AppToast.show(
    context,
    message: landingLaunchBlockMessage(context.l10n, block),
    variant: AppToastVariant.warning,
  );
}
