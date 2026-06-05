import '../../../l10n/app_localizations.dart';
import '../../../models/team_config.dart';
import 'capabilities/display_capability.dart';
import 'cli_tool_definition.dart';
import 'cli_tool_registry.dart';

/// UI display name via [DisplayCapability]; falls back to [CliTool.value].
String cliDisplayName(
  CliToolDefinition def,
  AppLocalizations l10n, {
  CliToolRegistry? registry,
}) {
  final cap = (registry ?? CliToolRegistry.builtIn())
      .capability<DisplayCapability>(def.id);
  if (cap != null) return cap.label(l10n);
  return def.id.value;
}
