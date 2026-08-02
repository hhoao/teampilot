import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import '../../theme/workspace_surface_layers.dart';
import '../home_workspace/home_workspace_route.dart';
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
    this.pickerMode = false,
    this.onConfirm,
    this.confirming = false,
    this.alreadyAdded = false,
    this.inset = 28,
  });

  final DiscoverableTeam team;

  /// True only while a hub clone is actually in flight (spinner + Cloning…).
  final bool cloning;

  /// Local ids already installed (skills/plugins/MCP) — drives the per-dep
  /// "installed ✓ / will install ⬇" badge.
  final Set<String> installedDepIds;
  final VoidCallback onBack;
  final VoidCallback onClone;

  /// When true, primary CTA is Confirm (not Clone). Sidebar Team Hub keeps
  /// the default (`false`).
  final bool pickerMode;
  final VoidCallback? onConfirm;

  /// Picker confirm in progress (reuse / non-clone). Disables Confirm without
  /// showing [teamHubCloning].
  final bool confirming;

  /// Shows an 「Already added」 chip when a local clone of this hub team exists.
  final bool alreadyAdded;

  /// Horizontal page inset (tighter on Android).
  final double inset;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
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
                leading: TpIconButton(
                  icon: Icons.arrow_back_rounded,
                  size: TpIconButton.chromeAlignedSize(context),
                  onTap: onBack,
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
                                  style: styles.mutedMd,
                                ),
                              ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (pickerMode && alreadyAdded)
                                  TeamStatChip(
                                    icon: Icons.check_rounded,
                                    label: l10n.teamHubAlreadyAdded,
                                  ),
                                TeamStatChip(
                                  icon: Icons.people_alt_outlined,
                                  label:
                                      '${team.roster.length} ${l10n.teamHubMembersLabel}',
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
                      if (pickerMode)
                        FilledButton(
                          onPressed: (cloning || confirming) ? null : onConfirm,
                          child: cloning
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(l10n.teamHubCloning),
                                  ],
                                )
                              : Text(l10n.teamHubConfirmSelection),
                        )
                      else
                        _CloneButton(cloning: cloning, onPressed: onClone),
                    ],
                  ),
                  if (team.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      team.description,
                      style: styles.mdRelaxed,
                    ),
                  ],
                  const SizedBox(height: 24),
                  _DepSection(
                    title: l10n.teamHubMembersLabel,
                    rows: [
                      for (final slot in team.roster)
                        _DepRow(label: slot.id, memberKey: slot.expertKey),
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
    final styles = TpTextStyles.of(context);
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
                  style: styles.mdSemiboldTightSnugColored(cs.onSurface),
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
                    style: styles.xsSemiboldColored(cs.onSurfaceVariant),
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
/// shows installed (✓) vs to-pull (⬇). When [memberKey] is set, a link opens
/// Expert Hub detail for that indexed member.
class _DepRow extends StatelessWidget {
  const _DepRow({required this.label, this.installed, this.memberKey});

  final String label;
  final bool? installed;
  final String? memberKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;
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
              style: styles.mdColored(cs.onSurface),
            ),
          ),
          if (memberKey != null)
            TextButton(
              onPressed: () {
                context.go(
                  HomeWorkspaceRoute.expertHubMemberLocation(memberKey!),
                );
              },
              child: Text(l10n.expertHubViewInHub),
            )
          else if (installed != null)
            _StatusBadge(installed: installed!),
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
    final styles = TpTextStyles.of(context);
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
            style: styles.xsSemiboldColored(fg),
          ),
        ],
      ),
    );
  }
}
