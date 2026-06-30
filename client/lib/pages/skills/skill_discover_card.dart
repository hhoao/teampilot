import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/github_details_button.dart';

class SkillDiscoverCard extends StatelessWidget {
  const SkillDiscoverCard({
    super.key,
    required this.name,
    required this.description,
    required this.source,
    this.githubUrl,
    required this.installed,
    required this.busy,
    required this.onInstall,
  });

  final String name;
  final String description;
  final String source;
  final String? githubUrl;
  final bool installed;
  final bool busy;
  final VoidCallback onInstall;

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
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.of(context).bodyStrong.copyWith(
                    fontWeight: FontWeight.w800,
                    color: textBase,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            source,
            style: AppTextStyles.of(
              context,
            ).caption.copyWith(color: textBase.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.of(
                context,
              ).bodySmall.copyWith(color: textBase.withValues(alpha: 0.7)),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GithubDetailsButton(
                  url: githubUrl,
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
                      style: AppTextStyles.of(context).bodySmall.copyWith(
                        color: const Color(0xFF15803D),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  FilledButton(
                    onPressed: busy ? null : onInstall,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.skillsCardInstall),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
