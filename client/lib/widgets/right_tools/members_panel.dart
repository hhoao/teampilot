import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/member_presence.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/app_keys.dart';
import '../app_icon_button.dart';
import '../member_presence_indicator.dart';
import '../team/team_lead_badge.dart';

/// Team roster list panel.
class MembersPanel extends StatelessWidget {
  const MembersPanel({
    required this.teamCli,
    required this.members,
    required this.memberPresence,
    required this.selectedMemberId,
    required this.onSelected,
    required this.onOpen,
    required this.onLaunchAll,
    super.key,
  });

  final TeamCli teamCli;
  final List<TeamMemberConfig> members;
  final Map<String, MemberPresence> memberPresence;
  final String selectedMemberId;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onOpen;
  final VoidCallback onLaunchAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final catalogCli =
        CliToolRegistryScope.maybeOf(
          context,
        )?.tryGet(teamCli.value)?.providerCatalogCli ??
        AppProviderCli.claude;
    final providerLabels = {
      for (final p in context.watch<AppProviderCubit>().state.providersFor(
        catalogCli,
      ))
        p.id: p.name,
    };
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
                final providerId = member.provider.trim();
                final providerLabel = providerId.isEmpty
                    ? ''
                    : (providerLabels[providerId] ?? providerId);
                final meta = [
                  providerLabel,
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
                  child: Material(
                    color: selected ? cs.secondaryContainer : cs.workspaceInset,
                    borderRadius: BorderRadius.circular(8),
                    child: Tooltip(
                      message: '$statusLabel · ${member.name}',
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
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
}
