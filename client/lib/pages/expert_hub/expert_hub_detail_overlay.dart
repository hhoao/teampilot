import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_member.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../home_workspace/home_workspace_route.dart';
import '../team_hub/team_hub_cards.dart';
import 'expert_hub_cards.dart';
import 'expert_hub_visuals.dart';

/// Embedded detail view for a public member persona, shown over the right pane.
class ExpertHubDetailOverlay extends StatelessWidget {
  const ExpertHubDetailOverlay({
    super.key,
    required this.member,
    required this.favorited,
    required this.adding,
    required this.installedDepIds,
    required this.onBack,
    required this.onToggleFavorite,
    required this.onAddToTeam,
    required this.onLaunchInWorkspace,
    this.inset = 28,
  });

  final DiscoverableMember member;
  final bool favorited;
  final bool adding;

  /// Local skill ids already installed — drives the per-dep badge.
  final Set<String> installedDepIds;
  final VoidCallback onBack;
  final VoidCallback onToggleFavorite;
  final VoidCallback onAddToTeam;
  final VoidCallback onLaunchInWorkspace;

  /// Horizontal page inset (tighter on Android).
  final double inset;

  static const _touchTarget = 44.0;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.of(context);
    final l10n = context.l10n;
    final teamMember = member.member;
    final subtitleParts = <String>[
      if (member.author != null && member.author!.isNotEmpty) member.author!,
      if (member.category.isNotEmpty) member.category,
    ];
    return Padding(
      padding: EdgeInsets.all(inset),
      child: ExpertHubWorkspaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 18, 0),
              child: ExpertHubCardHeader(
                title: member.name,
                leading: IconButton(
                  constraints: const BoxConstraints(
                    minWidth: _touchTarget,
                    minHeight: _touchTarget,
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: onBack,
                ),
                trailing: IconButton(
                  tooltip: l10n.expertHubFavorites,
                  icon: Icon(
                    favorited ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: favorited
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  onPressed: onToggleFavorite,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TeamMonogram(
                        seed: member.key,
                        label: member.name,
                        size: 52,
                        radius: 14,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (subtitleParts.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  subtitleParts.join(' · '),
                                  style: styles.mutedBody,
                                ),
                              ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                ExpertSourceBadge(
                                  source: member.source,
                                  accent: teamAccentColor(
                                    member.key,
                                    Theme.of(context).brightness,
                                  ),
                                ),
                                if (teamMember.capabilities.isNotEmpty)
                                  TeamStatChip(
                                    icon: Icons.psychology_outlined,
                                    label:
                                        '${teamMember.capabilities.length} ${l10n.expertHubCapabilities}',
                                  ),
                                if (member.skillDeps.isNotEmpty)
                                  TeamStatChip(
                                    icon: Icons.auto_awesome_outlined,
                                    label:
                                        '${member.skillDeps.length} ${l10n.teamHubSkillsLabel}',
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _AddToTeamButton(adding: adding, onPressed: onAddToTeam),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: adding ? null : onLaunchInWorkspace,
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                            child: Text(l10n.expertHubLaunchInWorkspace),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (member.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      member.description,
                      style: styles.body.copyWith(height: 1.45),
                    ),
                  ],
                  if (member.originTeamKey != null &&
                      member.originTeamKey!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          context.go(
                            HomeWorkspaceRoute.teamHubTeamLocation(
                              member.originTeamKey!.trim(),
                            ),
                          );
                        },
                        child: Text(l10n.expertHubViewOriginTeam),
                      ),
                    ),
                  ],
                  if (teamMember.prompt.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _ExpandableTextSection(
                      title: l10n.expertHubPrompt,
                      body: teamMember.prompt,
                    ),
                  ],
                  if (teamMember.playbook.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _ExpandableTextSection(
                      title: l10n.expertHubPlaybook,
                      body: teamMember.playbook,
                    ),
                  ],
                  if (teamMember.capabilities.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _CapabilitiesSection(
                      title: l10n.expertHubCapabilities,
                      capabilities: teamMember.capabilities,
                    ),
                  ],
                  if (member.skillDeps.isNotEmpty)
                    _DepSection(
                      title: l10n.teamHubSkillsLabel,
                      rows: [
                        for (final s in member.skillDeps)
                          _DepRow(
                            label: s.name,
                            installed: installedDepIds.contains(
                              s.expectedLocalId,
                            ),
                          ),
                      ],
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

class _AddToTeamButton extends StatelessWidget {
  const _AddToTeamButton({required this.adding, required this.onPressed});

  final bool adding;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FilledButton(
      onPressed: adding ? null : onPressed,
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      child: adding
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(l10n.expertHubAdding),
              ],
            )
          : Text(l10n.expertHubAddToTeam),
    );
  }
}

class _ExpandableTextSection extends StatelessWidget {
  const _ExpandableTextSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.of(context);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(title, style: styles.sectionTitle),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              body,
              style: styles.body.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilitiesSection extends StatelessWidget {
  const _CapabilitiesSection({
    required this.title,
    required this.capabilities,
  });

  final String title;
  final Set<String> capabilities;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: styles.sectionTitle.copyWith(color: cs.onSurface),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final cap in capabilities)
              TeamStatChip(label: cap, accent: cs.primary),
          ],
        ),
      ],
    );
  }
}

class _DepSection extends StatelessWidget {
  const _DepSection({required this.title, required this.rows});

  final String title;
  final List<_DepRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Text(
                  title,
                  style: styles.sectionTitle.copyWith(color: cs.onSurface),
                ),
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${rows.length}',
                    style: styles.caption.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...rows,
        ],
      ),
    );
  }
}

class _DepRow extends StatelessWidget {
  const _DepRow({required this.label, this.installed});

  final String label;
  final bool? installed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: workspaceInsetDecoration(cs, radius: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.body.copyWith(color: cs.onSurface),
            ),
          ),
          if (installed != null) _StatusBadge(installed: installed!),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.installed});

  final bool installed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color green = isDark
        ? const Color(0xFF4ADE80)
        : const Color(0xFF15803D);
    final Color fg = installed ? green : cs.primary;
    final Color bg = (installed ? green : cs.primary).withValues(alpha: 0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            installed ? Icons.check_rounded : Icons.south_rounded,
            size: 13,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            installed ? l10n.teamHubDepInstalled : l10n.teamHubDepToInstall,
            style: styles.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
