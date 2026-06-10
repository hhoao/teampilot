import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import 'team_hub_cards.dart';
import 'team_hub_visuals.dart';

/// Embedded detail view for a public team, shown over the right pane.
class TeamHubDetailOverlay extends StatelessWidget {
  const TeamHubDetailOverlay({
    super.key,
    required this.team,
    required this.cloning,
    required this.installedDepIds,
    required this.onBack,
    required this.onClone,
    this.inset = 28,
  });

  final DiscoverableTeam team;
  final bool cloning;

  /// Local ids already installed (skills/plugins/MCP) — drives the per-dep
  /// "installed ✓ / will install ⬇" badge.
  final Set<String> installedDepIds;
  final VoidCallback onBack;
  final VoidCallback onClone;

  /// Horizontal page inset (tighter on Android).
  final double inset;

  static const _touchTarget = 44.0;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.of(context);
    final l10n = context.l10n;
    final subtitleParts = <String>[
      if (team.author != null && team.author!.isNotEmpty) team.author!,
      if (team.category.isNotEmpty) team.category,
    ];
    return Padding(
      padding: EdgeInsets.all(inset),
      child: TeamHubWorkspaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 18, 0),
              child: TeamHubCardHeader(
                title: team.name,
                leading: IconButton(
                  constraints: const BoxConstraints(
                    minWidth: _touchTarget,
                    minHeight: _touchTarget,
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: onBack,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      TeamMonogram(
                        seed: team.key,
                        label: team.name,
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
                                TeamStatChip(
                                  icon: Icons.people_alt_outlined,
                                  label:
                                      '${team.members.length} ${l10n.teamHubMembersLabel}',
                                ),
                                if (team.skillDeps.isNotEmpty)
                                  TeamStatChip(
                                    icon: Icons.auto_awesome_outlined,
                                    label:
                                        '${team.skillDeps.length} ${l10n.teamHubSkillsLabel}',
                                  ),
                                if (team.pluginDeps.isNotEmpty)
                                  TeamStatChip(
                                    icon: Icons.extension_outlined,
                                    label:
                                        '${team.pluginDeps.length} ${l10n.teamHubPluginsLabel}',
                                  ),
                                if (team.mcpDeps.isNotEmpty)
                                  TeamStatChip(
                                    icon: Icons.cable_outlined,
                                    label:
                                        '${team.mcpDeps.length} ${l10n.teamHubMcpLabel}',
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _CloneButton(cloning: cloning, onPressed: onClone),
                    ],
                  ),
                  if (team.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      team.description,
                      style: styles.body.copyWith(height: 1.45),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _DepSection(
                    title: l10n.teamHubMembersLabel,
                    rows: [
                      for (final m in team.members)
                        _DepRow(
                          label: m.model.isEmpty
                              ? m.name
                              : '${m.name} · ${m.provider} ${m.model}'.trim(),
                        ),
                    ],
                  ),
                  _DepSection(
                    title: l10n.teamHubSkillsLabel,
                    rows: [
                      for (final s in team.skillDeps)
                        _DepRow(
                          label: s.name,
                          installed: installedDepIds.contains(
                            s.expectedLocalId,
                          ),
                        ),
                    ],
                  ),
                  _DepSection(
                    title: l10n.teamHubPluginsLabel,
                    rows: [
                      for (final p in team.pluginDeps)
                        _DepRow(
                          label: p.name,
                          installed: installedDepIds.contains(
                            p.expectedLocalId,
                          ),
                        ),
                    ],
                  ),
                  _DepSection(
                    title: l10n.teamHubMcpLabel,
                    rows: [
                      for (final m in team.mcpDeps)
                        _DepRow(
                          label: m.name,
                          installed: installedDepIds.contains(m.id),
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

class _CloneButton extends StatelessWidget {
  const _CloneButton({required this.cloning, required this.onPressed});

  final bool cloning;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FilledButton(
      onPressed: cloning ? null : onPressed,
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      child: cloning
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(l10n.teamHubCloning),
              ],
            )
          : Text(l10n.teamHubClone),
    );
  }
}

/// A titled group of dependency rows; renders nothing when [rows] is empty.
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
      padding: const EdgeInsets.only(bottom: 20),
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

/// One dependency line. When [installed] is non-null, a trailing status badge
/// shows installed (✓) vs to-pull (⬇).
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
    // Brightness-aware green so the installed badge stays legible in dark mode.
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
