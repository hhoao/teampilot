import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/app_keys.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../../widgets/settings/workspace_section_host.dart';
import 'skill_discovery_section.dart';
import 'skill_installed_section.dart';
import 'skill_repos_section.dart';
import 'skill_section.dart';

export 'skill_section.dart';

class SkillManagementHubPage extends StatelessWidget {
  const SkillManagementHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WorkspaceHubPage(
      pageKey: AppKeys.skillsHub,
      title: l10n.skillsTitle,
      subtitle: l10n.skillsSubtitle,
      entries: [
        for (final section in SkillSection.values)
          WorkspaceHubEntry(
            title: section.title(l10n),
            icon: skillSectionIcon(section),
            onTap: throttledTap(
              'skill_hub_${section.name}',
              () => context.push(section.routePath('/skills')),
            ),
          ),
      ],
    );
  }
}

class SkillManagementPage extends StatelessWidget {
  const SkillManagementPage({
    required this.section,
    this.onSelectSection,
    super.key,
  });

  final SkillSection section;

  /// When set, section switches call this instead of route navigation — lets
  /// the page be embedded (e.g. in the workspace home) with local-state nav.
  final void Function(SkillSection target)? onSelectSection;

  @override
  Widget build(BuildContext context) {
    void select(SkillSection target) => onSelectSection != null
        ? onSelectSection!(target)
        : navigateSkillSection(context, target);
    return BlocConsumer<SkillCubit, SkillState>(
      listenWhen: (a, b) =>
          a.errorMessage != b.errorMessage && b.errorMessage != null,
      listener: (context, state) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.errorMessage!),
            duration: const Duration(seconds: 4),
          ),
        );
        context.read<SkillCubit>().clearError();
      },
      builder: (context, state) {
        final sectionBody = switch (section) {
          SkillSection.installed => SkillInstalledSection(
            state: state,
            onGoDiscovery: () => select(SkillSection.discovery),
          ),
          SkillSection.discovery => SkillDiscoverySection(
            state: state,
            onGoRepos: () => select(SkillSection.repos),
          ),
          SkillSection.repos => SkillReposSection(state: state),
        };

        return WorkspaceAdaptiveSectionPage(
          pageKey: AppKeys.skillsWorkspace,
          title: context.l10n.skillsTitle,
          subtitle: context.l10n.skillsSubtitle,
          bodyAnimationKey: ValueKey('skills-body-${section.name}'),
          nav: WorkspaceEnumNavPanel<SkillSection>(
            sections: SkillSection.values,
            current: section,
            basePath: '/skills',
            descriptor: (s) => s,
            onSelect: select,
          ),
          body: sectionBody,
        );
      },
    );
  }
}
