import 'package:flutter/material.dart';
import 'package:teampilot/models/team_config.dart';

import '../../services/cli/registry/cli_tool_definition.dart';
import '../app_provider/provider_brand_icon.dart';
import '../app_provider/provider_icon_registry.dart';

/// Bundled provider icon id for a CLI, when not using the TeamPilot mark.
String? cliBrandIconKey(CliTool cli) => switch (cli) {
  CliTool.claude => 'claude',
  CliTool.codex => 'openai',
  CliTool.opencode => 'opencode',
  CliTool.cursor => 'cursor',
  CliTool.flashskyai => 'claude',
};

IconData cliToolIconData(CliTool cli) => switch (cli) {
  CliTool.flashskyai => Icons.bolt_outlined,
  CliTool.claude => Icons.terminal_outlined,
  CliTool.codex => Icons.integration_instructions_outlined,
  CliTool.opencode => Icons.code_outlined,
  CliTool.cursor => Icons.mouse_outlined,
};

/// Renders a CLI brand mark (TeamPilot logo, bundled vendor icon, or fallback).
class CliBrandIcon extends StatelessWidget {
  const CliBrandIcon({
    required this.cli,
    this.definition,
    this.label,
    this.size = 32,
    this.borderRadius = 8,
    this.showBorder = true,
    super.key,
  });

  final CliTool cli;
  final CliToolDefinition? definition;
  final String? label;
  final double size;
  final double borderRadius;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final iconKey = cliBrandIconKey(cli);
    final displayLabel = label ?? definition?.id.value ?? cli.value;

    if (iconKey != null && providerIconExists(iconKey)) {
      return ProviderBrandIcon(
        icon: iconKey,
        name: displayLabel,
        size: size,
        borderRadius: borderRadius,
        showBorder: showBorder,
      );
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: resolveProviderIconTileBackground(cs, isDark),
        borderRadius: BorderRadius.circular(borderRadius),
        border: showBorder
            ? Border.all(color: resolveProviderIconBorderColor(cs, isDark))
            : null,
      ),
      alignment: Alignment.center,
      child: Icon(
        cliToolIconData(cli),
        size: size * 0.5,
        color: resolveProviderIconForeground(cs, isDark),
      ),
    );
  }
}
