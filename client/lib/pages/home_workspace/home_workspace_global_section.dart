import 'package:flutter/material.dart';

import '../extensions/extension_management_page.dart';
import '../mcp/mcp_management_page.dart';
import '../plugins/plugin_management_page.dart';
import '../skills/skill_management_page.dart';
import '../llm_config/llm_config_workspace.dart';
import '../team_hub/team_hub_page.dart';

/// Which global management view is shown in the workspace-home right pane.
enum HomeGlobalView {
  skills,
  plugins,
  mcp,
  extensions,
  teamHub,
  providers;

  /// Query key on `/home-v2` for deep-linking a global management pane.
  static const globalQueryParam = 'global';

  String get routeSegment => name;

  /// `/home-v2?global=<segment>` — opens the main workspace with this sidebar
  /// shortcut selected.
  String get homeLocation => Uri(
        path: '/home-v2',
        queryParameters: {globalQueryParam: routeSegment},
      ).toString();

  /// Resolves [globalQueryParam] (e.g. `skills`, `mcp`) back to a view.
  static HomeGlobalView? fromSegment(String? segment) {
    final value = segment?.trim();
    if (value == null || value.isEmpty) return null;
    for (final view in values) {
      if (view.routeSegment == value) return view;
    }
    return null;
  }
}

/// Embeds an existing global management page (Skills / Plugins / MCP) — or the
/// team Extensions section — inside the workspace-home right pane. Sub-section
/// navigation stays local (via [onSelectSection] overrides) so it never breaks
/// out of the home shell.
class HomeGlobalSection extends StatefulWidget {
  const HomeGlobalSection({required this.view, super.key});

  final HomeGlobalView view;

  @override
  State<HomeGlobalSection> createState() =>
      _HomeGlobalSectionState();
}

class _HomeGlobalSectionState
    extends State<HomeGlobalSection> {
  SkillSection _skill = SkillSection.installed;
  PluginSection _plugin = PluginSection.installed;
  McpSection _mcp = McpSection.installed;
  ExtensionSection _extension = ExtensionSection.installed;

  @override
  Widget build(BuildContext context) {
    return switch (widget.view) {
      HomeGlobalView.skills => SkillManagementPage(
          section: _skill,
          onSelectSection: (s) => setState(() => _skill = s),
        ),
      HomeGlobalView.plugins => PluginManagementPage(
          section: _plugin,
          onSelectSection: (s) => setState(() => _plugin = s),
        ),
      HomeGlobalView.mcp => McpManagementPage(
          section: _mcp,
          onSelectSection: (s) => setState(() => _mcp = s),
        ),
      HomeGlobalView.extensions => ExtensionManagementPage(
          section: _extension,
          onSelectSection: (s) => setState(() => _extension = s),
        ),
      HomeGlobalView.teamHub => const TeamHubPage(),
      HomeGlobalView.providers => const LlmConfigWorkspace(),
    };
  }
}
