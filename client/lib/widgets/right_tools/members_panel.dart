import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/member_presence.dart';
import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import '../../models/workspace_topology.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/capabilities/provider_catalog_capability.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/ui/app_keys.dart';
import '../../utils/team/members_machine_groups.dart';
import 'package:shared_ui/shared_ui.dart';
import '../app_provider/provider_brand_icon.dart';
import '../cli/cli_brand_icon.dart';
import '../member_presence_indicator.dart';
import '../team/team_lead_badge.dart';
import '../workspace_folder_directory_row.dart';

/// Team roster list panel.
class MembersPanel extends StatelessWidget {
  const MembersPanel({
    required this.team,
    required this.members,
    required this.memberPresence,
    required this.providersByCli,
    required this.selectedMemberId,
    required this.onSelected,
    required this.onSwitchTo,
    required this.onOpen,
    required this.onLaunchAll,
    required this.canViewDetail,
    required this.onViewDetail,
    required this.onOpenConfigDir,
    this.memberTargets = const {},
    this.runtimeTargets = const [],
    this.groupByMachine = false,
    super.key,
  });

  final TeamProfile team;
  final List<TeamMemberConfig> members;
  final Map<String, MemberPresence> memberPresence;
  final Map<CliTool, List<AppProviderConfig>> providersByCli;
  final String selectedMemberId;
  final ValueChanged<String> onSelected;

  /// Select member without starting a PTY (context-menu action).
  final ValueChanged<String> onSwitchTo;
  final ValueChanged<String> onOpen;
  final VoidCallback onLaunchAll;

  /// Whether "view detail" is enabled (true when a session/tab is active).
  final bool canViewDetail;
  final ValueChanged<String> onViewDetail;
  final ValueChanged<String> onOpenConfigDir;

  /// Instance id → machine target id (session or remembered workspace pins).
  final MemberTargetAssignments memberTargets;

  /// Selectable home/runtime targets for label resolution.
  final List<RuntimeTarget> runtimeTargets;

  /// When true (mixed team), attempt machine section headers if ≥2 targets.
  final bool groupByMachine;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.maybeOf(context);
    final groups = groupByMachine
        ? groupMembersByMachine(members: members, memberTargets: memberTargets)
        : const <MembersMachineGroup>[];
    final useSections = groups.length >= 2;

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
                  style: TpTextStyles.of(
                    context,
                  ).xsBoldWideColored(cs.onSurfaceVariant),
                ),
              ),
              TpIconButton(
                icon: Icons.keyboard_double_arrow_right,
                tooltip: l10n.openTeam,
                color: cs.primary,
                size: TpIconButton.kCompactSize,
                onTap: onLaunchAll,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              children: [
                if (useSections)
                  for (final group in groups) ...[
                    _MachineSectionHeader(
                      targetId: group.targetId,
                      runtimeTargets: runtimeTargets,
                    ),
                    for (final member in group.members)
                      _memberTile(
                        context,
                        member: member,
                        cs: cs,
                        styles: styles,
                        l10n: l10n,
                        registry: registry,
                      ),
                  ]
                else
                  for (final member in members)
                    _memberTile(
                      context,
                      member: member,
                      cs: cs,
                      styles: styles,
                      l10n: l10n,
                      registry: registry,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberTile(
    BuildContext context, {
    required TeamMemberConfig member,
    required ColorScheme cs,
    required TpTextStyles styles,
    required AppLocalizations l10n,
    required CliToolRegistry? registry,
  }) {
    final selected = member.id == selectedMemberId;
    final presence =
        memberPresence[member.id] ?? const MemberPresence.offline();
    final statusLabel = memberPresenceStatusLabel(l10n, presence);
    final presets = context.watch<CliPresetsCubit>().state.presets;
    final launch = resolveMemberLaunch(
      team: team,
      member: member,
      globalPresets: presets,
    );
    final memberCli = launch.cli;
    final catalogCli = _catalogCli(registry, memberCli);
    final memberProvider = _memberProvider(
      providersByCli[catalogCli] ?? const [],
      launch.provider,
    );
    final brandLabel =
        memberProvider?.name ?? _cliDisplayLabel(registry, memberCli, l10n);
    final meta = [
      brandLabel,
      launch.model,
    ].where((v) => v.isNotEmpty).join(' / ');
    final subtitle = meta.isEmpty ? statusLabel : '$statusLabel · $meta';
    final titleColor = selected ? cs.onSecondaryContainer : cs.onSurface;
    final subtitleColor = selected
        ? cs.onSecondaryContainer.withValues(alpha: 0.74)
        : cs.onSurfaceVariant;
    return Container(
      key: AppKeys.memberRow(member.id),
      margin: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (d) => _showMemberMenu(context, l10n, member, d),
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
                : CliBrandIcon(cli: memberCli, size: 28, borderRadius: 7),
            title: MemberTitleRow(
              member: member,
              fallbackName: l10n.memberName,
              style: styles.md,
              textColor: titleColor,
              compactBadge: true,
            ),
            textColor: titleColor,
            iconColor: titleColor,
            subtitle: Text(subtitle, style: styles.smColored(subtitleColor)),
            trailing: MemberPresenceIndicator(presence: presence),
            onTap: () => onSelected(member.id),
          ),
        ),
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
    final action = await showTpActionMenuFromSpecsAtTap<_MemberMenuAction>(
      context: context,
      tapDetails: details,
      specs: [
        TpActionMenuSpec.item(
          value: _MemberMenuAction.viewDetail,
          icon: Icons.info_outline,
          label: l10n.memberDetailViewAction,
          enabled: canViewDetail,
          tooltip: canViewDetail ? null : l10n.memberDetailNeedsSession,
        ),
        TpActionMenuSpec.item(
          value: _MemberMenuAction.switchTo,
          icon: Icons.swap_horiz,
          label: l10n.switchToMember,
        ),
        TpActionMenuSpec.item(
          value: _MemberMenuAction.open,
          icon: Icons.open_in_new,
          label: l10n.openMember,
        ),
        TpActionMenuSpec.item(
          value: _MemberMenuAction.openConfigDir,
          icon: Icons.folder_open,
          label: l10n.memberDetailOpenConfigDir,
        ),
        const TpActionMenuSpec.divider(),
        TpActionMenuSpec.item(
          value: _MemberMenuAction.launchAll,
          icon: Icons.play_arrow,
          label: l10n.openTeam,
        ),
      ],
    );
    switch (action) {
      case _MemberMenuAction.viewDetail:
        onViewDetail(member.id);
      case _MemberMenuAction.switchTo:
        onSwitchTo(member.id);
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

class _MachineSectionHeader extends StatelessWidget {
  const _MachineSectionHeader({
    required this.targetId,
    required this.runtimeTargets,
  });

  final String targetId;
  final List<RuntimeTarget> runtimeTargets;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Row(
        children: [
          Icon(
            workspaceFolderTargetIcon(targetId),
            size: 16,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              workspaceFolderTargetLabel(runtimeTargets, targetId),
              style: styles.xsBoldWideColored(cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

enum _MemberMenuAction { viewDetail, switchTo, open, openConfigDir, launchAll }

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
