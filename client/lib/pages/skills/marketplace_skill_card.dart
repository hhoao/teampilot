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

  static String formatUpdatedAt(int unixSeconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final metrics = skill.metrics;
    return TpCatalogCardShell(
      title: skill.name,
      source: '${skill.repoOwner}/${skill.repoName}',
      description: skill.description,
      body: skill.contentLanguage == null
          ? null
          : Align(
              alignment: AlignmentDirectional.centerStart,
              child: _LanguageBadge(code: skill.contentLanguage!),
            ),
      metadata: TpCatalogMetadataRow(
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
      ),
      action: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          GithubDetailsButton(
            url: skill.githubUrl,
            label: l10n.skillsCardDetails,
          ),
          if (installed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                l10n.skillsCardInstalled,
                style: TpTextStyles.of(context)
                    .smBoldColored(const Color(0xFF15803D)),
              ),
            )
          else
            FilledButton(
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

class _LanguageBadge extends StatelessWidget {
  const _LanguageBadge({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        code.toUpperCase(),
        style: TpTextStyles.of(context).xsBoldColored(cs.onSecondaryContainer),
      ),
    );
  }
}
