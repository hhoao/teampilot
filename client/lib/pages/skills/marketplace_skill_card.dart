import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/skill/marketplace/skill_marketplace_source.dart';
import '../../widgets/github_details_button.dart';

class MarketplaceSkillCard extends StatelessWidget {
  const MarketplaceSkillCard({
    super.key,
    required this.skill,
    required this.installed,
    required this.busy,
    required this.onInstall,
  });

  final MarketplaceSkill skill;
  final bool installed;
  final bool busy;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final metrics = skill.metrics;

    return TpCatalogListCard(
      showTags: false,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
          child: Center(
            child: Icon(
              Icons.auto_awesome_outlined,
              size: 20,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
      title: skill.name,
      source: '${skill.repoOwner}/${skill.repoName}',
      description: skill.description,
      emptyDescription: l10n.skillsCatalogCardNoDescription,
      adoption: TpCatalogMetricView(
        icon: Icons.download_outlined,
        label: l10n.skillsCatalogAdoption,
        value: metrics.adoptionCount?.toString(),
        missingValueTooltip: l10n.catalogMetricMissingTooltip,
      ),
      rating: TpCatalogMetricView(
        icon: Icons.star_border,
        label: l10n.catalogMetricRating,
        value: metrics.rating?.toStringAsFixed(1),
        missingValueTooltip: l10n.catalogMetricMissingTooltip,
      ),
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GithubDetailsButton(
            url: skill.githubUrl,
            label: l10n.skillsCardDetails,
          ),
          if (installed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                l10n.skillsCardInstalled,
                style: styles.smSemiboldColored(const Color(0xFF15803D)),
              ),
            )
          else
            FilledButton.tonal(
              onPressed: busy ? null : onInstall,
              child: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      skill.isInstalledDirectly
                          ? l10n.skillsCardInstall
                          : l10n.skillsMarketplaceAddRepo,
                    ),
            ),
        ],
      ),
    );
  }
}
