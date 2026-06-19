import '../../models/plugin.dart';
import '../../models/team_config.dart';
import '../cli/registry/capabilities/plugin_provisioner_capability.dart';
import '../cli/registry/cli_tool_registry.dart';

enum PluginCliSupportLevel {
  fullySupported,
  partiallySupported,
  notApplicable,
}

class PluginCliSupportStatus {
  const PluginCliSupportStatus({
    required this.tool,
    required this.level,
    this.dropped = const {},
  });

  final CliTool tool;
  final PluginCliSupportLevel level;
  final Set<PluginComponentKind> dropped;
}

Set<PluginComponentKind> presentPluginComponentKinds(PluginCapabilities caps) {
  final present = <PluginComponentKind>{};
  if (caps.skills.isNotEmpty) present.add(PluginComponentKind.skills);
  if (caps.agents.isNotEmpty) present.add(PluginComponentKind.agents);
  if (caps.commands.isNotEmpty) present.add(PluginComponentKind.commands);
  if (caps.hooks.isNotEmpty) present.add(PluginComponentKind.hooks);
  if (caps.mcpServers.isNotEmpty) present.add(PluginComponentKind.mcp);
  return present;
}

PluginCliSupportStatus analyzePluginCliSupport({
  required PluginCapabilities capabilities,
  required CliTool tool,
  CliToolRegistry? registry,
}) {
  final present = presentPluginComponentKinds(capabilities);
  if (present.isEmpty) {
    return PluginCliSupportStatus(
      tool: tool,
      level: PluginCliSupportLevel.notApplicable,
    );
  }

  final provisioner = pluginProvisionerForTool(tool, registry: registry);
  if (provisioner == null) {
    return PluginCliSupportStatus(
      tool: tool,
      level: PluginCliSupportLevel.notApplicable,
      dropped: present,
    );
  }

  final supported = provisioner.supported;
  final dropped = present.difference(supported);
  final carried = present.intersection(supported);
  if (carried.isEmpty) {
    return PluginCliSupportStatus(
      tool: tool,
      level: PluginCliSupportLevel.notApplicable,
      dropped: dropped,
    );
  }
  if (dropped.isEmpty) {
    return PluginCliSupportStatus(
      tool: tool,
      level: PluginCliSupportLevel.fullySupported,
    );
  }
  return PluginCliSupportStatus(
    tool: tool,
    level: PluginCliSupportLevel.partiallySupported,
    dropped: dropped,
  );
}

List<PluginCliSupportStatus> analyzePluginCliSupportForLaunchClis(
  PluginCapabilities capabilities, {
  CliToolRegistry? registry,
}) {
  final reg = registry ?? CliToolRegistry.builtIn();
  return [
    for (final def in reg.launchable)
      analyzePluginCliSupport(
        capabilities: capabilities,
        tool: def.id,
        registry: reg,
      ),
  ];
}

bool pluginCapabilitiesDisclosable(PluginCapabilities capabilities) =>
    presentPluginComponentKinds(capabilities).isNotEmpty;
