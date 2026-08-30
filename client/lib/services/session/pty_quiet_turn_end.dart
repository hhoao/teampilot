import '../../models/team_config.dart';
import '../cli/registry/capabilities/team_behavior_capability.dart';
import '../cli/registry/cli_tool_registry.dart';

bool ptyQuietEndsTurn(CliTool cli, {CliToolRegistry? registry}) {
  final cap = (registry ?? CliToolRegistry.builtIn())
      .capability<TeamBehaviorCapability>(cli);
  return cap?.requiresPtyFallback ?? false;
}
