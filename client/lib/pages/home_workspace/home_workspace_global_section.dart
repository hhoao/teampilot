import 'package:flutter/material.dart';

import '../extensions/extension_management_page.dart';
import '../mcp/mcp_management_page.dart';
import '../plugins/plugin_management_page.dart';
import '../skills/skill_management_page.dart';

/// Which global management view is shown in the workspace-home right pane.
enum HomeWorkspaceGlobalView { skills, plugins, mcp, extensions }

/// Embeds an existing global management page (Skills / Plugins / MCP) — or the
/// team Extensions section — inside the workspace-home right pane. Sub-section
/// navigation stays local (via [onSelectSection] overrides) so it never breaks
/// out of the home shell.
class HomeWorkspaceGlobalSection extends StatefulWidget {
  const HomeWorkspaceGlobalSection({required this.view, super.key});

  final HomeWorkspaceGlobalView view;

  @override
  State<HomeWorkspaceGlobalSection> createState() =>
      _HomeWorkspaceGlobalSectionState();
}

class _HomeWorkspaceGlobalSectionState
    extends State<HomeWorkspaceGlobalSection> {
  SkillSection _skill = SkillSection.installed;
  PluginSection _plugin = PluginSection.installed;
  McpSection _mcp = McpSection.installed;
  ExtensionSection _extension = ExtensionSection.installed;

  @override
  Widget build(BuildContext context) {
    return switch (widget.view) {
      HomeWorkspaceGlobalView.skills => SkillManagementPage(
          section: _skill,
          onSelectSection: (s) => setState(() => _skill = s),
        ),
      HomeWorkspaceGlobalView.plugins => PluginManagementPage(
          section: _plugin,
          onSelectSection: (s) => setState(() => _plugin = s),
        ),
      HomeWorkspaceGlobalView.mcp => McpManagementPage(
          section: _mcp,
          onSelectSection: (s) => setState(() => _mcp = s),
        ),
      HomeWorkspaceGlobalView.extensions => ExtensionManagementPage(
          section: _extension,
          onSelectSection: (s) => setState(() => _extension = s),
        ),
    };
  }
}
