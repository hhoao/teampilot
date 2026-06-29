import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/github_source_url.dart';
import 'skill_discover_card.dart';
import 'skill_discovery_helpers.dart';
import '../../widgets/empty_state_block.dart';
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

class SkillDiscoverySkillsShBody extends StatelessWidget {
  const SkillDiscoverySkillsShBody({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<SkillCubit, SkillState, Set<String>>(
      selector: (state) => skillInstalledKeys(state.installed),
      builder: (context, installedKeys) {
        return BlocSelector<SkillCubit, SkillState, SkillsShSearchState>(
          selector: (state) => state.skillsSh,
          builder: (context, sh) {
            final l10n = context.l10n;
            final cubit = context.read<SkillCubit>();

            if (sh.loading && sh.entries.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (sh.query.isEmpty) {
              return SingleChildScrollView(
                child: SkillManagementCard(
                  child: EmptyStateBlock(
                    icon: Icons.search,
                    title: l10n.skillsSkillsShPlaceholder,
                    hint: '',
                  ),
                ),
              );
            }
            if (sh.entries.isEmpty) {
              return SingleChildScrollView(
                child: SkillManagementCard(
                  child: EmptyStateBlock(
                    icon: Icons.search_off,
                    title: l10n.skillsDiscoveryEmpty,
                    hint: l10n.skillsDiscoveryEmptyHint,
                  ),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth >= 1100
                          ? 3
                          : (constraints.maxWidth >= 700 ? 2 : 1);
                      return BlocSelector<SkillCubit, SkillState, Set<String>>(
                        selector: (state) => state.busyIds,
                        builder: (context, busyIds) {
                          return GridView.builder(
                            padding: const EdgeInsets.only(top: 2),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              mainAxisExtent: 168,
                            ),
                            itemCount: sh.entries.length,
                            itemBuilder: (context, i) {
                              final entry = sh.entries[i];
                              return SkillDiscoverCard(
                                key: ValueKey(entry.key),
                                name: entry.name,
                                description: l10n.skillsInstalls(entry.installs),
                                source:
                                    '${entry.repoOwner}/${entry.repoName}',
                                githubUrl: entry.githubBrowseUrl,
                                installed: installedKeys.contains(
                                  skillsShInstallKey(entry),
                                ),
                                busy: busyIds.contains(entry.key),
                                onInstall: () =>
                                    cubit.installSkillsShEntry(entry),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  Icons.expand_more,
                                  size: context.appIconSizes.md,
                                ),
                          label: Text(l10n.skillsSkillsShLoadMore),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.skillsSkillsShPoweredBy,
                        style: AppTextStyles.of(context).caption.copyWith(
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
