import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../services/cli/registry/cli_display_name.dart';
import '../../../services/cli/registry/cli_tool_registry.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../services/remote/remote_cli_requirements.dart';
import '../../../services/launch/workspace_landing_launch_gate.dart';

String landingLaunchBlockMessage(
  AppLocalizations l10n,
  WorkspaceLandingLaunchBlock block, {
  CliToolRegistry? registry,
}) {
  return switch (block) {
    TeamNotSelectedLaunchBlock() => l10n.selectTeam,
    MixedMemberPlacementUninitializedLaunchBlock() =>
      l10n.mixedWorkspaceMemberAssignmentIncomplete,
    LeadPlacementInvalidLaunchBlock() =>
      l10n.mixedWorkspaceLeadPlacementInvalid,
    TeamConfigIncompleteLaunchBlock() =>
      l10n.workspaceChatLandingTeamLaunchBlocked,
    RemoteCliMissingLaunchBlock(:final missing) =>
      landingLaunchRemoteCliMissingMessage(l10n, missing, registry: registry),
  };
}

String landingLaunchRemoteCliMissingMessage(
  AppLocalizations l10n,
  List<RemoteCliRequirement> missing, {
  CliToolRegistry? registry,
}) {
  if (missing.isEmpty) return l10n.landingLaunchRemoteCliMissing;
  final reg = registry ?? CliToolRegistry.builtIn();
  final details = missing
      .map((req) {
        final def = reg.tryGet(req.cli);
        final cliLabel = def != null
            ? cliDisplayName(def, l10n, registry: reg)
            : req.cli.value;
        return l10n.landingLaunchRemoteCliMissingDetail(cliLabel, req.hostLabel);
      })
      .join('; ');
  return '${l10n.landingLaunchRemoteCliMissing} $details';
}

/// Toast for submit attempts blocked by [block].
void showWorkspaceLandingLaunchBlock(
  BuildContext context,
  WorkspaceLandingLaunchBlock block,
) {
  AppToast.show(
    context,
    message: landingLaunchBlockMessage(
      context.l10n,
      block,
      registry: CliToolRegistryScope.maybeOf(context),
    ),
    variant: TpToastVariant.warning,
  );
}
