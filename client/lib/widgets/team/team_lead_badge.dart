import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../utils/team_member_naming.dart';
import '../../models/team_config.dart';

/// Compact pill shown beside team-lead members in lists and settings.
class TeamLeadBadge extends StatelessWidget {
  const TeamLeadBadge({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final horizontal = compact ? 6.0 : 8.0;
    final vertical = compact ? 2.0 : 3.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontal,
          vertical: vertical,
        ),
        child: Text(
          l10n.teamLeadBadge,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: cs.onSecondaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Member display name with an optional [TeamLeadBadge] when [member] is team-lead.
class MemberTitleRow extends StatelessWidget {
  const MemberTitleRow({
    required this.member,
    this.fallbackName,
    this.style,
    this.textColor,
    this.compactBadge = false,
    super.key,
  });

  final TeamMemberConfig member;
  final String? fallbackName;
  final TextStyle? style;
  final Color? textColor;
  final bool compactBadge;

  @override
  Widget build(BuildContext context) {
    final raw = member.name.trim();
    final label = raw.isEmpty ? (fallbackName ?? member.id) : raw;
    final textStyle =
        style?.copyWith(color: textColor) ?? TextStyle(color: textColor);

    return Row(
      children: [
        Flexible(
          child: Text(
            label,
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (TeamMemberNaming.isTeamLead(member)) ...[
          const SizedBox(width: 6),
          TeamLeadBadge(compact: compactBadge),
        ],
      ],
    );
  }
}
