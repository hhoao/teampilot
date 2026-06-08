import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../../services/app/flashskyai_agent_catalog_service.dart';
import '../../services/cli/registry/capabilities/cli_effort_capability.dart';
import '../../services/cli/registry/capabilities/provider_catalog_capability.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';

CliTool? catalogCliForTeam(BuildContext context, CliTool cli) {
  final registry = CliToolRegistryScope.maybeOf(context);
  if (registry == null) return null;
  return registry.capability<ProviderCatalogCapability>(cli) != null
      ? cli
      : null;
}

String teamCliDisplayLabel(
  BuildContext context,
  AppLocalizations l10n,
  CliTool cli,
) {
  final def = CliToolRegistryScope.maybeOf(context)?.tryGet(cli);
  if (def != null) {
    return cliDisplayName(def, l10n, registry: CliToolRegistryScope.maybeOf(context));
  }
  return cli.value;
}

bool teamShowsEffortPicker(
  BuildContext context, {
  required CliTool cli,
  required EffortPickerPlacement placement,
  String model = '',
}) {
  final registry = CliToolRegistryScope.maybeOf(context);
  if (registry == null) return false;
  final capability = registry.capability<CliEffortCapability>(cli);
  if (capability == null) return false;
  final target = switch (placement) {
    EffortPickerPlacement.team => capability.teamPickerPlacement(),
    EffortPickerPlacement.member => capability.memberPickerPlacement(),
    EffortPickerPlacement.provider => EffortPickerPlacement.hidden,
    EffortPickerPlacement.hidden => EffortPickerPlacement.hidden,
  };
  if (target != placement) return false;
  return capability.isApplicable(model: model);
}

String memberAgentDropdownItemLabel(
  BuildContext context,
  AppLocalizations l10n,
  String value, {
  List<String> userAgentIds = const [],
}) {
  if (value == FlashskyaiAgentCatalog.noneDropdownValue) {
    return l10n.agentBuiltInNone;
  }
  if (value == FlashskyaiAgentCatalog.customDropdownValue) {
    return l10n.agentBuiltInCustom;
  }
  final ent = FlashskyaiAgentCatalog.tryParseBuiltinId(value);
  if (ent != null) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final hint = zh ? ent.modelHintZh : ent.modelHintEn;
    return '${ent.id} · $hint';
  }
  if (userAgentIds.contains(value)) {
    return value;
  }
  return value;
}
