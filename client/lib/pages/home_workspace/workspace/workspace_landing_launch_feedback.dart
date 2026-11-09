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
      l10n.mixed.workspaceMemberAssignmentIncomplete,
    LeadPlacementInvalidLaunchBlock() =>
      l10n.mixed.workspaceLeadPlacementInvalid,
    TeamConfigIncompleteLaunchBlock() =>
      l10n.workspace.chatLandingTeamLaunchBlocked,
    RemoteCliMissingLaunchBlock(:final missing) =>
      landingLaunchRemoteCliMissingMessage(l10n, missing, registry: registry),
    LocalCliMissingLaunchBlock(:final missing) =>
      landingLaunchLocalCliMissingMessage(l10n, missing, registry: registry),
    AcpUnsupportedTargetLaunchBlock() => landingLaunchAcpUnsupportedMessage(
      l10n,
      block,
    ),
  };
}

String landingLaunchAcpUnsupportedMessage(
  AppLocalizations l10n,
  AcpUnsupportedTargetLaunchBlock block,
) {
  final registry = CliToolRegistry.builtIn();
  final def = registry.tryGet(block.cli);
  final label = def != null
      ? cliDisplayName(def, l10n, registry: registry)
      : block.cli.value;
  return l10n.landing.launchAcpUnsupported(cli: label, target: block.targetId);
}

String landingLaunchLocalCliMissingMessage(
  AppLocalizations l10n,
  List<LocalBinaryRequirement> missing, {
  CliToolRegistry? registry,
}) {
  if (missing.isEmpty) return l10n.landing.launchLocalCliMissing;
  final reg = registry ?? CliToolRegistry.builtIn();
  final details = missing
      .map((req) {
        final def = reg.tryGet(req.cli);
        final cliLabel = def != null
            ? cliDisplayName(def, l10n, registry: reg)
            : req.cli.value;
        return req.kind == CliBinaryKind.adapter
            ? l10n.landing.launchLocalAdapterMissingDetail(cli: cliLabel)
            : l10n.landing.launchLocalCliMissingDetail(cli: cliLabel);
      })
      .join('; ');
  return '${l10n.landing.launchLocalCliMissing} $details';
}

String landingLaunchRemoteCliMissingMessage(
  AppLocalizations l10n,
  List<RemoteCliRequirement> missing, {
  CliToolRegistry? registry,
}) {
  if (missing.isEmpty) return l10n.landing.launchRemoteCliMissing;
  final reg = registry ?? CliToolRegistry.builtIn();
  final details = missing
      .map((req) {
        final def = reg.tryGet(req.cli);
        final cliLabel = def != null
            ? cliDisplayName(def, l10n, registry: reg)
            : req.cli.value;
        return l10n.landing.launchRemoteCliMissingDetail(
          cli: cliLabel,
          host: req.hostLabel,
        );
      })
      .join('; ');
  return '${l10n.landing.launchRemoteCliMissing} $details';
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
            label: context.l10n.landing.launchLocalCliOpenSettings,
            onPressed: () => openCliConfigManagement(context),
          )
        : null,
  );
}
