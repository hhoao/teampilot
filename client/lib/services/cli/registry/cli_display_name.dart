import '../../../l10n/app_localizations.dart';
import '../../../models/team_config.dart';
import 'capabilities/cli_executable_capability.dart';
import 'cli_tool_definition.dart';
import 'cli_tool_registry.dart';

/// UI display name via [CliExecutableCapability]; falls back to [CliTool.value].
String cliDisplayName(
  CliToolDefinition def,
  AppLocalizations l10n, {
  CliToolRegistry? registry,
}) {
  final cap = (registry ?? CliToolRegistry.builtIn())
      .capability<CliExecutableCapability>(def.id);
  if (cap != null) return cap.label(l10n);
  return def.id.value;
}
