import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';

/// Embedded detail view for a public team, shown over the right pane.
class TeamHubDetailOverlay extends StatelessWidget {
  const TeamHubDetailOverlay({
    super.key,
    required this.team,
    required this.cloning,
    required this.installedDepIds,
    required this.onBack,
    required this.onClone,
  });

  final DiscoverableTeam team;
  final bool cloning;

  /// Local ids already installed (skills/plugins/MCP) — drives the per-dep
  /// "installed ✓ / will install ⬇" badge.
  final Set<String> installedDepIds;
  final VoidCallback onBack;
  final VoidCallback onClone;

  static const _touchTarget = 44.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final l10n = context.l10n;
    final subtitleParts = <String>[
      if (team.author != null && team.author!.isNotEmpty) team.author!,
      if (team.category.isNotEmpty) team.category,
    ];
    return ColoredBox(
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: _touchTarget,
                    minHeight: _touchTarget,
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: onBack,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    team.name,
                    style: styles.sectionTitle.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                if (subtitleParts.isNotEmpty)
                  Text(
                    subtitleParts.join(' · '),
                    style: styles.body.copyWith(color: cs.onSurfaceVariant),
                  ),
                if (team.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(team.description, style: styles.body),
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
                        installed: installedDepIds.contains(s.expectedLocalId),
                      ),
                  ],
                ),
                _DepSection(
                  title: l10n.teamHubPluginsLabel,
                  rows: [
                    for (final p in team.pluginDeps)
                      _DepRow(
                        label: p.name,
                        installed: installedDepIds.contains(p.expectedLocalId),
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: cloning ? null : onClone,
                child: cloning
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Text(l10n.teamHubCloning),
                        ],
                      )
                    : Text(l10n.teamHubClone),
              ),
            ),
          ),
        ],
      ),
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
    final styles = AppTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: styles.prominent.copyWith(fontWeight: FontWeight.w700),
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
      decoration: workspaceCardDecoration(cs, radius: 10),
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
    final Color fg = installed ? const Color(0xFF15803D) : cs.primary;
    final Color bg = installed
        ? const Color(0xFF15803D).withValues(alpha: 0.12)
        : cs.primary.withValues(alpha: 0.12);
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
            installed
                ? Icons.check_rounded
                : Icons.south_rounded,
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
