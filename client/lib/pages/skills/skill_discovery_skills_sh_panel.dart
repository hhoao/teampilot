import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/github_source_url.dart';
import 'skill_discover_card.dart';
import 'skill_management_cards.dart';

class SkillDiscoverySkillsShSearchBar extends StatelessWidget {
  const SkillDiscoverySkillsShSearchBar({
    required this.controller,
    required this.onSearch,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: l10n.skillsSkillsShPlaceholder,
              prefixIcon: Icon(Icons.search, size: context.appIconSizes.md),
              floatingLabelBehavior: FloatingLabelBehavior.never,
            ),
            onSubmitted: (v) {
              if (v.trim().length >= 2) onSearch(v.trim());
            },
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: controller.text.trim().length < 2
              ? null
              : () => onSearch(controller.text.trim()),
          child: Text(l10n.skillsSkillsShSearch),
        ),
      ],
    );
  }
}

class SkillDiscoverySkillsShResults extends StatelessWidget {
  const SkillDiscoverySkillsShResults({
    required this.state,
    required this.installedKeys,
    super.key,
  });

  final SkillState state;
  final Set<String> installedKeys;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<SkillCubit>();
    final sh = state.skillsSh;
    if (sh.loading && sh.entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (sh.query.isEmpty) {
      return SkillManagementCard(
        child: SkillEmptyBlock(
          icon: Icons.search,
          title: l10n.skillsSkillsShPlaceholder,
          hint: '',
        ),
      );
    }
    if (sh.entries.isEmpty) {
      return SkillManagementCard(
        child: SkillEmptyBlock(
          icon: Icons.search_off,
          title: l10n.skillsDiscoveryEmpty,
          hint: l10n.skillsDiscoveryEmptyHint,
        ),
      );
    }

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 1100
                ? 3
                : (constraints.maxWidth >= 700 ? 2 : 1);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 168,
              ),
              itemCount: sh.entries.length,
              itemBuilder: (context, i) {
                final entry = sh.entries[i];
                final installKey =
                    '${entry.directory.toLowerCase()}:${entry.repoOwner.toLowerCase()}:${entry.repoName.toLowerCase()}';
                return SkillDiscoverCard(
                  name: entry.name,
                  description: l10n.skillsInstalls(entry.installs),
                  source: '${entry.repoOwner}/${entry.repoName}',
                  githubUrl: entry.githubBrowseUrl,
                  installed: installedKeys.contains(installKey),
                  busy: state.busyIds.contains(entry.key),
                  onInstall: () => cubit.installSkillsShEntry(entry),
                );
              },
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Column(
            children: [
              if (sh.entries.length < sh.totalCount)
                OutlinedButton.icon(
                  onPressed: sh.loading ? null : cubit.loadMoreSkillsSh,
                  icon: sh.loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.expand_more, size: context.appIconSizes.md),
                  label: Text(l10n.skillsSkillsShLoadMore),
                ),
              const SizedBox(height: 6),
              Text(
                l10n.skillsSkillsShPoweredBy,
                style: AppTextStyles.of(
                  context,
                ).caption.copyWith(color: Theme.of(context).hintColor),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
