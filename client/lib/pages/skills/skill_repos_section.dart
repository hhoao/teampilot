import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/skill.dart';
import '../../services/skill/skill_repo_disk_cache_service.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/skill_repo_parse.dart';
import 'skill_management_cards.dart';

class SkillReposSection extends StatefulWidget {
  const SkillReposSection({super.key, required this.state});
  final SkillState state;

  @override
  State<SkillReposSection> createState() => SkillReposSectionState();
}

class SkillReposSectionState extends State<SkillReposSection> {
  final _urlCtl = TextEditingController();
  final _branchCtl = TextEditingController(text: 'main');

  @override
  void dispose() {
    _urlCtl.dispose();
    _branchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<SkillCubit>();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkillManagementCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SkillCardHeader(title: l10n.skillsNavRepos),
                const SizedBox(height: 12),
                if (widget.state.repos.isEmpty)
                  SkillEmptyBlock(
                    icon: Icons.source_outlined,
                    title: l10n.skillsReposEmpty,
                    hint: l10n.skillsDiscoveryEmptyHint,
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final r in widget.state.repos)
                        SkillRepoRow(
                          repo: r,
                          syncing: widget.state.repoSyncingKeys.contains(
                            SkillRepoDiskCacheService.repoKey(r),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          SkillManagementCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SkillCardHeader(title: l10n.skillsRepoAdd),
                const SizedBox(height: 12),
                SkillFieldLabel(text: l10n.skillsRepoUrl),
                const SizedBox(height: 4),
                TextField(
                  controller: _urlCtl,
                  decoration: InputDecoration(
                    hintText: l10n.skillsRepoUrlHint,
                    hintMaxLines: 2,
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                  ),
                ),
                const SizedBox(height: 10),
                SkillFieldLabel(text: l10n.skillsRepoBranch),
                const SizedBox(height: 4),
                TextField(
                  controller: _branchCtl,
                  decoration: const InputDecoration(),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: throttledAsync('skill_add_repo', () async {
                      final url = _urlCtl.text.trim();
                      var branch = _branchCtl.text.trim();
                      if (url.isEmpty) return;
                      final parsed = parseGithubRepoUrl(url);
                      if (parsed == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.skillsRepoInvalidUrl)),
                        );
                        return;
                      }
                      if (branch.isEmpty) branch = 'main';
                      await cubit.addRepo(
                        SkillRepo(
                          owner: parsed.owner,
                          name: parsed.name,
                          branch: branch,
                        ),
                      );
                      _urlCtl.clear();
                      _branchCtl.text = 'main';
                    }),
                    icon: const Icon(Icons.add, size: AppIconSizes.md),
                    label: Text(l10n.skillsAdd),
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

class SkillRepoRow extends StatelessWidget {
  const SkillRepoRow({super.key, required this.repo, required this.syncing});
  final SkillRepo repo;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final cubit = context.read<SkillCubit>();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: workspaceInsetDecoration(cs, radius: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    repo.githubUrl,
                    style: AppTextStyles.of(
                      context,
                    ).body.copyWith(color: textBase),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${repo.branch}',
                    style: AppTextStyles.of(
                      context,
                    ).caption.copyWith(color: textBase.withValues(alpha: 0.55)),
                  ),
                ],
              ),
            ),
            if (syncing) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
            ],
            Switch(
              value: repo.enabled,
              onChanged: syncing
                  ? null
                  : (v) => cubit.toggleRepoEnabled(repo, v),
            ),
            IconButton(
              tooltip: l10n.skillsRemove,
              onPressed: () async {
                final ok = await skillConfirmDialog(
                  context,
                  title: l10n.skillsRepoRemove,
                  message: l10n.skillsRepoRemoveConfirm(repo.githubUrl),
                  confirmLabel: l10n.skillsRemove,
                  destructive: true,
                );
                if (ok) await cubit.removeRepo(repo.owner, repo.name);
              },
              icon: Icon(
                Icons.delete_outline,
                size: AppIconSizes.md,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
