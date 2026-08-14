import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/skill/marketplace/skill_marketplace_source.dart';
import '../../theme/workspace_surface_layers.dart';
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
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final textBase = cs.onSurface;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: workspaceCardDecoration(cs, radius: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  skill.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TpTextStyles.of(context).mdBoldColored(textBase),
                ),
              ),
              if (skill.contentLanguage != null) ...[
                const SizedBox(width: 6),
                _LanguageBadge(code: skill.contentLanguage!),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${skill.repoOwner}/${skill.repoName}',
            style: TpTextStyles.of(
              context,
            ).xsColored(textBase.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              skill.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TpTextStyles.of(
                context,
              ).smColored(textBase.withValues(alpha: 0.7)),
            ),
          ),
          _MetaRow(skill: skill, l10n: l10n),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      l10n.skillsCardInstalled,
                      style: TpTextStyles.of(
                        context,
                      ).smBoldColored(const Color(0xFF15803D)),
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

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.skill, required this.l10n});
  final MarketplaceSkill skill;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final textBase = Theme.of(context).colorScheme.onSurface;
    final dim = TpTextStyles.of(
      context,
    ).xsColored(textBase.withValues(alpha: 0.55));
    final chips = <String>[
      if (skill.stars != null) l10n.skillsCardStars(skill.stars!),
      if (skill.installs != null) l10n.skillsInstalls(skill.installs!),
      if (skill.updatedAt != null)
        l10n.skillsCardUpdatedAt(
          MarketplaceSkillCard.formatUpdatedAt(skill.updatedAt!),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [for (final c in chips) Text(c, style: dim)],
    );
  }
}
