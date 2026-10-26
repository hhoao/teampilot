import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../widgets/app_toast/app_toast.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/cli_binary_kind.dart';
import '../../../services/cli/registry/cli_display_name.dart';
import '../../../services/cli/registry/cli_tool_registry.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../services/chat/launch/pre_send/local_binary_requirements.dart';
import '../../../services/remote/remote_cli_requirements.dart';
import '../../../services/chat/launch/pre_send/workspace_landing_launch_gate.dart';
import '../../config/config_workspace.dart';

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
    LocalCliMissingLaunchBlock(:final missing) =>
      landingLaunchLocalCliMissingMessage(l10n, missing, registry: registry),
  };
}

String landingLaunchLocalCliMissingMessage(
  AppLocalizations l10n,
  List<LocalBinaryRequirement> missing, {
  CliToolRegistry? registry,
}) {
  if (missing.isEmpty) return l10n.landingLaunchLocalCliMissing;
  final reg = registry ?? CliToolRegistry.builtIn();
  final details = missing
      .map((req) {
        final def = reg.tryGet(req.cli);
        final cliLabel = def != null
            ? cliDisplayName(def, l10n, registry: reg)
            : req.cli.value;
        return req.kind == CliBinaryKind.adapter
            ? l10n.landingLaunchLocalAdapterMissingDetail(cliLabel)
            : l10n.landingLaunchLocalCliMissingDetail(cliLabel);
      })
      .join('; ');
  return '${l10n.landingLaunchLocalCliMissing} $details';
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
        return l10n.landingLaunchRemoteCliMissingDetail(
          cliLabel,
          req.hostLabel,
        );
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
    action: block is LocalCliMissingLaunchBlock
        ? TpToastAction(
            label: context.l10n.landingLaunchLocalCliOpenSettings,
            onPressed: () => openCliConfigManagement(context),
          )
        : null,
  );
}
