import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_member.dart';
import '../team_hub/team_hub_cards.dart';
import 'expert_hub_visuals.dart';

/// Bordered detail shell — reuses [TeamHubWorkspaceCard] styling.
class ExpertHubWorkspaceCard extends StatelessWidget {
  const ExpertHubWorkspaceCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TeamHubWorkspaceCard(child: child);
}

class ExpertHubCardHeader extends StatelessWidget {
  const ExpertHubCardHeader({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
  });

  final String title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) =>
      TeamHubCardHeader(title: title, leading: leading, trailing: trailing);
}

/// Fixed four-row discovery card for one public member persona.
///
/// 1. icon + name + favorite
/// 2. description (2 lines, or localized "无")
/// 3. tags
/// 4. metrics + source (source fixed max width, ellipsis)
class ExpertHubCard extends StatefulWidget {
  const ExpertHubCard({
    super.key,
    required this.member,
    required this.favorited,
    required this.busy,
    required this.onTap,
    required this.onToggleFavorite,
    this.selected = false,
  });

  final DiscoverableMember member;
  final bool favorited;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final bool selected;

  @override
  State<ExpertHubCard> createState() => _ExpertHubCardState();
}

class _ExpertHubCardState extends State<ExpertHubCard> {
  static const _touchTarget = 40.0;
  static const _radius = 14.0;
  static const _sourceMaxWidth = 120.0;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;
    final member = widget.member.forLocale(
      Localizations.localeOf(context).languageCode,
    );
    final accent = teamAccentColor(member.key, Theme.of(context).brightness);
    final interactive = !widget.busy;
    final borderColor = widget.selected
        ? cs.primary.withValues(alpha: 0.65)
        : _hovered
        ? accent.withValues(alpha: 0.55)
        : cs.outlineVariant;

    final description = member.description.trim();
    final descriptionText = description.isEmpty
        ? l10n.expertHubCardNoDescription
        : description;
    final sourceLabel = _sourceLabel(member, l10n);

    final tags = <Widget>[
      if (member.member.capabilities.isNotEmpty)
        TeamStatChip(
          icon: Icons.psychology_outlined,
          label: '${member.member.capabilities.length}',
          tooltip: l10n.expertHubCapabilities,
        ),
      if (member.skillDeps.isNotEmpty)
        TeamStatChip(
          icon: Icons.auto_awesome_outlined,
          label: '${member.skillDeps.length}',
          tooltip: l10n.teamHubSkillsLabel,
        ),
      if (member.pluginDeps.isNotEmpty)
        TeamStatChip(
          icon: Icons.extension_outlined,
          label: '${member.pluginDeps.length}',
          tooltip: l10n.teamHubPluginsLabel,
        ),
      if (member.mcpDeps.isNotEmpty)
        TeamStatChip(
          icon: Icons.cable_outlined,
          label: '${member.mcpDeps.length}',
          tooltip: l10n.teamHubMcpLabel,
        ),
      if (member.category.isNotEmpty)
        TeamStatChip(label: member.category, accent: accent),
    ];

    return MouseRegion(
      onEnter: (_) {
        if (widget.busy) return;
        setState(() => _hovered = true);
      },
      onExit: (_) => setState(() => _hovered = false),
      cursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: interactive ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(color: borderColor),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          padding: EdgeInsets.all(spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  TeamMonogram(seed: member.key, label: member.name),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Text(
                      member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.mdSemiboldColored(cs.onSurface),
                    ),
                  ),
                  _FavoriteButton(
                    favorited: widget.favorited,
                    touchTarget: _touchTarget,
                    onPressed: widget.onToggleFavorite,
                  ),
                ],
              ),
              SizedBox(height: spacing.sm),
              Text(
                descriptionText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: styles.smRelaxedColored(
                  description.isEmpty
                      ? cs.onSurface.withValues(alpha: 0.45)
                      : cs.onSurface.withValues(alpha: 0.78),
                ),
              ),
              SizedBox(height: spacing.sm),
              SizedBox(
                height: 28,
                child: tags.isEmpty
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          child: Row(
                            children: [
                              for (var i = 0; i < tags.length; i++) ...[
                                if (i > 0) SizedBox(width: spacing.xs),
                                tags[i],
                              ],
                            ],
                          ),
                        ),
                      ),
              ),
              SizedBox(height: spacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TpCatalogMetadataRow(
                      adoption: _metric(
                        icon: Icons.download_outlined,
                        label: l10n.expertsCatalogAdoption,
                        value: member.metrics.adoptionCount?.toString(),
                        missing: l10n.catalogMetricMissingTooltip,
                      ),
                      rating: _metric(
                        icon: Icons.star_outline_rounded,
                        label: l10n.catalogMetricRating,
                        value: member.metrics.rating?.toStringAsFixed(1),
                        missing: l10n.catalogMetricMissingTooltip,
                      ),
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _sourceMaxWidth,
                    ),
                    child: Text(
                      sourceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: styles.xsColored(
                        cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _sourceLabel(DiscoverableMember member, AppLocalizations l10n) {
  final author = member.author?.trim();
  if (author != null && author.isNotEmpty) return author;
  return switch (member.source) {
    ExpertMemberSource.builtin => l10n.expertHubSourceBuiltin,
    ExpertMemberSource.registry => l10n.expertHubSourceRegistry,
    ExpertMemberSource.local => l10n.expertHubSourceLocal,
    ExpertMemberSource.teamExtract => l10n.expertHubSourceTeamExtract,
    ExpertMemberSource.clone => l10n.expertHubSourceClone,
  };
}

TpCatalogMetricView _metric({
  required IconData icon,
  required String label,
  required String? value,
  required String missing,
}) => TpCatalogMetricView(
  icon: icon,
  label: label,
  value: value,
  missingValueTooltip: missing,
);

class ExpertSourceBadge extends StatelessWidget {
  const ExpertSourceBadge({super.key, required this.source, this.accent});

  final ExpertMemberSource source;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = switch (source) {
      ExpertMemberSource.builtin => l10n.expertHubSourceBuiltin,
      ExpertMemberSource.registry => l10n.expertHubSourceRegistry,
      ExpertMemberSource.local => l10n.expertHubSourceLocal,
      ExpertMemberSource.teamExtract => l10n.expertHubSourceTeamExtract,
      ExpertMemberSource.clone => l10n.expertHubSourceClone,
    };
    return TeamStatChip(label: label, accent: accent);
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({
    required this.favorited,
    required this.touchTarget,
    required this.onPressed,
  });

  final bool favorited;
  final double touchTarget;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      constraints: BoxConstraints(
        minWidth: touchTarget,
        minHeight: touchTarget,
      ),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        favorited ? Icons.star_rounded : Icons.star_outline_rounded,
        color: favorited ? cs.primary : cs.onSurfaceVariant,
        size: 20,
      ),
      onPressed: onPressed,
    );
  }
}
