import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/team/team_config_launch_validator.dart';
import '../../widgets/app_dialog.dart';
import '../team_config/team_config_section.dart';

/// Shows the "team configuration incomplete" warning for [validation] and, when
/// the user opts in, navigates to the team-config screen (deep-linked to the
/// first affected member when one is known). Launch is never blocked by this.
///
Future<void> showTeamConfigIncompleteDialog(
  BuildContext context,
  TeamConfigValidation validation,
) async {
  if (!validation.hasIssues) return;
  final groups = _groupIssues(context.l10n, validation);

  final goConfigure = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _TeamConfigIncompleteDialog(
      teamName: validation.teamName,
      groups: groups,
    ),
  );

  if (goConfigure != true || !context.mounted) return;
  _openTeamConfig(context, validation.firstMemberId);
}

/// Routes to team config under `/home-v2`; deep-link via query params so the
/// right tab (and member) opens.
void _openTeamConfig(BuildContext context, String? memberId) {
  final hasMember = memberId != null && memberId.isNotEmpty;
  final query = <String, String>{
    'section': hasMember
        ? TeamConfigSection.members.routeSegment
        : TeamConfigSection.team.routeSegment,
    if (hasMember) 'member': memberId,
  };
  context.go(Uri(path: '/home-v2', queryParameters: query).toString());
}

class _TeamConfigIncompleteDialog extends StatelessWidget {
  const _TeamConfigIncompleteDialog({
    required this.teamName,
    required this.groups,
  });

  final String teamName;
  final List<_IssueGroup> groups;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return AppDialog(
      maxWidth: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.tune_rounded,
                color: colors.onErrorContainer,
                size: 26,
              ),
            ),
          ),
          const SizedBox(height: 12),
          AppDialogHeader(
            title: l10n.teamConfigIncompleteTitle,
            onClose: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.teamConfigIncompleteBody(teamName),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (var i = 0; i < groups.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 48,
                      color: colors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  _IssueRow(group: groups[i]),
                ],
              ],
            ),
          ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.teamConfigIncompleteDismiss),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(l10n.teamConfigIncompleteGoConfigure),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.group});

  final _IssueGroup group;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final aspects = group.aspects.join(l10n.teamConfigAspectSeparator);

    return Semantics(
      label: l10n.teamConfigIssueSemanticLabel(group.title, aspects),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(group.icon, size: 20, color: colors.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    aspects,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One subject (a member, or the team default) and the config aspects missing
/// for it — collapses repeated per-aspect issues into a single row.
class _IssueGroup {
  _IssueGroup({required this.icon, required this.title});

  final IconData icon;
  final String title;
  final List<String> aspects = [];
}

List<_IssueGroup> _groupIssues(
  AppLocalizations l10n,
  TeamConfigValidation validation,
) {
  const teamKey = '__team__';
  final byKey = <String, _IssueGroup>{};
  final order = <String>[];

  _IssueGroup groupFor(String key, IconData icon, String title) =>
      byKey.putIfAbsent(key, () {
        order.add(key);
        return _IssueGroup(icon: icon, title: title);
      });

  for (final issue in validation.issues) {
    switch (issue.kind) {
      case TeamConfigIssueKind.teamDefaultProviderMissing:
        groupFor(
          teamKey,
          Icons.groups_2_outlined,
          l10n.teamConfigGroupTeamDefault,
        ).aspects.add(l10n.teamConfigAspectDefaultProvider);
      case TeamConfigIssueKind.memberProviderMissing:
        groupFor(
          issue.memberId ?? '',
          Icons.person_outline,
          issue.memberName ?? issue.memberId ?? '',
        ).aspects.add(l10n.teamConfigAspectProvider);
      case TeamConfigIssueKind.memberModelMissing:
        groupFor(
          issue.memberId ?? '',
          Icons.person_outline,
          issue.memberName ?? issue.memberId ?? '',
        ).aspects.add(l10n.teamConfigAspectModel);
      case TeamConfigIssueKind.memberCliMissing:
        groupFor(
          issue.memberId ?? '',
          Icons.person_outline,
          issue.memberName ?? issue.memberId ?? '',
        ).aspects.add(l10n.teamConfigAspectCli);
    }
  }

  return [for (final key in order) byKey[key]!];
}
