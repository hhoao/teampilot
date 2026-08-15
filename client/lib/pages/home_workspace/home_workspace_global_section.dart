import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../widgets/app_toast/app_toast.dart';

import '../../cubits/expert_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_member.dart';
import '../automations/automation_management_page.dart';
import '../expert_hub/expert_hub_page.dart';
import '../expert_hub/expert_team_picker_dialog.dart';
import '../expert_hub/expert_workspace_picker_dialog.dart';
import '../expert_hub/member_hub_add_feedback.dart';
import '../extensions/extension_management_page.dart';
import '../hooks/hook_management_page.dart';
import '../mcp/mcp_management_page.dart';
import '../plugins/plugin_management_page.dart';
import '../skills/skill_management_page.dart';
import '../llm_config/llm_config_workspace.dart';
import '../my_experts/my_experts_page.dart';
import '../my_teams/my_teams_page.dart';
import '../team_hub/team_hub_page.dart';

/// Which global management view is shown in the workspace-home right pane.
enum HomeGlobalView {
  skills,
  plugins,
  mcp,
  extensions,
  hooks,
  myTeams,
  myExperts,
  teamHub,
  expertHub,
  providers,
  automations;

  /// Query key on `/home-v2` for deep-linking a global management pane.
  static const globalQueryParam = 'global';

  String get routeSegment => name;

  /// `/home-v2?global=<segment>` — opens the main workspace with this sidebar
  /// shortcut selected. Hooks are the exception: they live on a dedicated
  /// route, so the location points there directly.
  String get homeLocation => switch (this) {
    HomeGlobalView.hooks => '/hooks',
    _ => Uri(
      path: '/home-v2',
      queryParameters: {globalQueryParam: routeSegment},
    ).toString(),
  };

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
  const HomeGlobalSection({
    required this.view,
    this.onOpenTeam,
    super.key,
  });

  final HomeGlobalView view;

  /// Selects a team and leaves the global view (My Teams open action).
  final ValueChanged<String>? onOpenTeam;

  @override
  State<HomeGlobalSection> createState() => _HomeGlobalSectionState();
}

class _HomeGlobalSectionState extends State<HomeGlobalSection> {
  SkillSection _skill = SkillSection.installed;
  PluginSection _plugin = PluginSection.installed;
  McpSection _mcp = McpSection.installed;
  ExtensionSection _extension = ExtensionSection.installed;

  @override
  Widget build(BuildContext context) {
    final content = switch (widget.view) {
      HomeGlobalView.skills => SkillManagementPage(
        section: _skill,
        onSelectSection: (s) => setState(() => _skill = s),
        embedded: true,
      ),
      HomeGlobalView.plugins => PluginManagementPage(
        section: _plugin,
        onSelectSection: (s) => setState(() => _plugin = s),
        embedded: true,
      ),
      HomeGlobalView.mcp => McpManagementPage(
        section: _mcp,
        onSelectSection: (s) => setState(() => _mcp = s),
        embedded: true,
      ),
      HomeGlobalView.extensions => ExtensionManagementPage(
        section: _extension,
        onSelectSection: (s) => setState(() => _extension = s),
        embedded: true,
      ),
      HomeGlobalView.hooks => const HookManagementPage(embedded: true),
      HomeGlobalView.myTeams => MyTeamsPage(onOpenTeam: widget.onOpenTeam),
      HomeGlobalView.myExperts => const MyExpertsPage(),
      HomeGlobalView.teamHub => const TeamHubPage(),
      HomeGlobalView.expertHub => ExpertHubPage(
        onAddToTeam: expertHubAddToTeam,
        onLaunchInWorkspace: expertHubLaunchInWorkspace,
      ),
      HomeGlobalView.providers => const LlmConfigWorkspace(embedded: true),
      HomeGlobalView.automations => const AutomationManagementPage(),
    };
    if (MediaQuery.disableAnimationsOf(context)) return content;
    return content
        .animate(key: ValueKey(widget.view))
        .fadeIn(duration: 180.ms, curve: Curves.easeOut)
        .slideX(
          begin: 0.025,
          end: 0,
          duration: 220.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

Future<void> expertHubAddToTeam(
  BuildContext context,
  ExpertHubCubit cubit,
  DiscoverableMember member,
) async {
  final teamId = await showExpertTeamPickerDialog(context);
  if (teamId == null || !context.mounted) return;

  final l10n = context.l10n;
  final result = await cubit.addToTeam(teamId: teamId, member: member);
  if (!context.mounted) return;
  AppToast.show(
    context,
    message: memberHubAddToastMessage(
      l10n,
      memberName: member.name,
      result: result,
    ),
    variant: memberHubAddToastIsWarning(result)
        ? TpToastVariant.warning
        : TpToastVariant.success,
  );
}

void expertHubLaunchInWorkspace(BuildContext context, DiscoverableMember member) {
  showExpertWorkspacePickerDialog(context).then((workspaceId) {
    if (workspaceId == null || !context.mounted) return;
    context.go(
      '/home-v2/workspace/$workspaceId?expert=${Uri.encodeComponent(member.key)}',
    );
  });
}
