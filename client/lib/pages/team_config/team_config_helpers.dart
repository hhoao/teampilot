import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../../services/app/flashskyai_agent_catalog_service.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';

AppProviderCli? catalogCliForTeam(BuildContext context, TeamCli cli) =>
    CliToolRegistryScope.maybeOf(
      context,
    )?.tryGet(cli.value)?.providerCatalogCli;

String teamCliDisplayLabel(
  BuildContext context,
  AppLocalizations l10n,
  TeamCli cli,
) {
  final def = CliToolRegistryScope.maybeOf(context)?.tryGet(cli.value);
  if (def != null) return cliDisplayName(def, l10n);
  return cli.value;
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
