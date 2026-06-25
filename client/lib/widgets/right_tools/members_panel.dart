import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/member_presence.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/capabilities/provider_catalog_capability.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/app_keys.dart';
import '../app_icon_button.dart';
import '../app_provider/provider_brand_icon.dart';
import '../cli/cli_brand_icon.dart';
import '../member_presence_indicator.dart';
import '../menu/sidebar_action_menu.dart';
import '../team/team_lead_badge.dart';

/// Team roster list panel.
class MembersPanel extends StatelessWidget {
  const MembersPanel({
    required this.team,
    required this.members,
    required this.memberPresence,
    required this.selectedMemberId,
    required this.onSelected,
    required this.onOpen,
    required this.onLaunchAll,
    required this.canViewDetail,
    required this.onViewDetail,
    required this.onOpenConfigDir,
    super.key,
  });

  final TeamProfile team;
  final List<TeamMemberConfig> members;
  final Map<String, MemberPresence> memberPresence;
  final String selectedMemberId;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onOpen;
  final VoidCallback onLaunchAll;

  /// Whether "view detail" is enabled (true when a session/tab is active).
  final bool canViewDetail;
  final ValueChanged<String> onViewDetail;
  final ValueChanged<String> onOpenConfigDir;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.maybeOf(context);
    final providerState = context.watch<AppProviderCubit>().state;
    return Container(
      key: AppKeys.membersPanel,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.members,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              AppIconButton(
                icon: Icons.keyboard_double_arrow_right,
                tooltip: l10n.openTeam,
                color: cs.primary,
                size: AppIconButton.kCompactSize,
                onTap: onLaunchAll,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: members.length,
              itemBuilder: (context, index) {
                final member = members[index];
                final selected = member.id == selectedMemberId;
                final presence =
                    memberPresence[member.id] ?? const MemberPresence.offline();
                final statusLabel = memberPresenceStatusLabel(l10n, presence);
                final memberCli = member.cliWithin(team);
                final catalogCli = _catalogCli(registry, memberCli);
                final memberProvider = _memberProvider(
                  providerState.providersFor(catalogCli),
                  member.provider,
                );
                final brandLabel = memberProvider?.name ??
                    _cliDisplayLabel(registry, memberCli, l10n);
                final meta = [
                  brandLabel,
                  member.model,
                ].where((v) => v.isNotEmpty).join(' / ');
                final subtitle = meta.isEmpty
                    ? statusLabel
                    : '$statusLabel · $meta';
                final titleColor = selected
                    ? cs.onSecondaryContainer
                    : cs.onSurface;
                final subtitleColor = selected
                    ? cs.onSecondaryContainer.withValues(alpha: 0.74)
                    : cs.onSurfaceVariant;
                return Container(
                  key: AppKeys.memberRow(member.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onSecondaryTapDown: (d) =>
                        _showMemberMenu(context, l10n, member, d),
                    onLongPressStart: (d) => _showMemberMenu(
                      context,
                      l10n,
                      member,
                      TapDownDetails(globalPosition: d.globalPosition),
                    ),
                    child: Material(
                      color: selected ? cs.secondaryContainer : cs.workspaceInset,
                      borderRadius: BorderRadius.circular(8),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        leading: memberProvider != null
                            ? ProviderBrandIcon.fromConfig(
                                memberProvider,
                                size: 28,
                                borderRadius: 7,
                              )
                            : CliBrandIcon(
                                cli: memberCli,
                                size: 28,
                                borderRadius: 7,
                              ),
                        title: MemberTitleRow(
                          member: member,
                          fallbackName: l10n.memberName,
                          style: Theme.of(context).textTheme.bodyMedium,
                          textColor: titleColor,
                          compactBadge: true,
                        ),
                        textColor: titleColor,
                        iconColor: titleColor,
                        subtitle: Text(
                          subtitle,
                          style: TextStyle(color: subtitleColor),
                        ),
                        trailing: MemberPresenceIndicator(presence: presence),
                        onTap: () => onSelected(member.id),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMemberMenu(
    BuildContext context,
    AppLocalizations l10n,
    TeamMemberConfig member,
    TapDownDetails details,
  ) async {
    // Dispatch via the menu's return value (not inline `onAction`): actions that
    // push a route — e.g. the detail dialog — must run AFTER the menu route has
    // popped, otherwise the menu's own pop tears down the route we just pushed.
    final action = await showSidebarActionMenuFromSpecsAtTap<_MemberMenuAction>(
      context: context,
      tapDetails: details,
      specs: [
        SidebarActionMenuSpec.item(
          value: _MemberMenuAction.viewDetail,
          icon: Icons.info_outline,
          label: l10n.memberDetailViewAction,
          enabled: canViewDetail,
          tooltip: canViewDetail ? null : l10n.memberDetailNeedsSession,
        ),
        SidebarActionMenuSpec.item(
          value: _MemberMenuAction.open,
          icon: Icons.open_in_new,
          label: l10n.openMember,
        ),
        SidebarActionMenuSpec.item(
          value: _MemberMenuAction.openConfigDir,
          icon: Icons.folder_open,
          label: l10n.memberDetailOpenConfigDir,
        ),
        const SidebarActionMenuSpec.divider(),
        SidebarActionMenuSpec.item(
          value: _MemberMenuAction.launchAll,
          icon: Icons.play_arrow,
          label: l10n.openTeam,
        ),
      ],
    );
    switch (action) {
      case _MemberMenuAction.viewDetail:
        onViewDetail(member.id);
      case _MemberMenuAction.open:
        onOpen(member.id);
      case _MemberMenuAction.openConfigDir:
        onOpenConfigDir(member.id);
      case _MemberMenuAction.launchAll:
        onLaunchAll();
      case null:
        break;
    }
  }
}

enum _MemberMenuAction {
  viewDetail,
  open,
  openConfigDir,
  launchAll,
}

CliTool _catalogCli(CliToolRegistry? registry, CliTool memberCli) {
  if (registry != null &&
      registry.capability<ProviderCatalogCapability>(memberCli) != null) {
    return memberCli;
  }
  return CliTool.claude;
}

AppProviderConfig? _memberProvider(
  Iterable<AppProviderConfig> catalog,
  String provider,
) {
  final providerId = provider.trim();
  if (providerId.isEmpty) return null;
  for (final p in catalog) {
    if (p.id == providerId) return p;
  }
  return null;
}

String _cliDisplayLabel(
  CliToolRegistry? registry,
  CliTool cli,
  AppLocalizations l10n,
) {
  final def = registry?.tryGet(cli);
  if (def != null) {
    return cliDisplayName(def, l10n, registry: registry);
  }
  return cli.value;
}
