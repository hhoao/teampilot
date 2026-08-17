import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../widgets/app_toast/app_toast.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/settings/workspace_section_host.dart';
import '../../widgets/settings/workspace_section_nav_item.dart';
import 'skill_discovery_section.dart';
import 'skill_installed_section.dart';
import 'skill_registries_section.dart';
import 'skill_section.dart';

export 'skill_section.dart';

class SkillManagementPage extends StatelessWidget {
  const SkillManagementPage({
    required this.section,
    this.onSelectSection,
    this.embedded = false,
    super.key,
  });

  final SkillSection section;

  /// When set, section switches call this instead of route navigation — lets
  /// the page be embedded (e.g. in the workspace home) with local-state nav.
  final void Function(SkillSection target)? onSelectSection;

  /// When true, skip page inset — parent (home) already applied
  /// [WorkspacePaneInsets.page].
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    void select(SkillSection target) => onSelectSection != null
        ? onSelectSection!(target)
        : navigateSkillSection(context, target);
    return BlocListener<SkillCubit, SkillState>(
      listenWhen: (a, b) =>
          a.noticeMessage != b.noticeMessage && b.noticeMessage != null,
      listener: (context, state) {
        if (!context.mounted) return;
        AppToast.show(
          context,
          message:
              state.noticeMessage == SkillCubit.marketplaceRepoAddedNoticeKey
              ? context.l10n.skillsMarketplaceRepoAdded
              : state.noticeMessage!,
          variant: TpToastVariant.success,
          duration: const Duration(seconds: 4),
        );
        context.read<SkillCubit>().clearError();
      },
      child: BlocListener<SkillCubit, SkillState>(
        listenWhen: (a, b) =>
            a.errorMessage != b.errorMessage && b.errorMessage != null,
        listener: (context, state) {
          if (!context.mounted) return;
          AppToast.show(
            context,
            message: state.errorMessage!,
            variant: TpToastVariant.error,
            duration: const Duration(seconds: 4),
          );
          context.read<SkillCubit>().clearError();
        },
        child: WorkspaceAdaptiveSectionPage(
          pageKey: AppKeys.skillsWorkspace,
          title: context.l10n.skillsTitle,
          subtitle: context.l10n.skillsSubtitle,
          showSubtitle: false,
          embedded: embedded,
          compactSectionTabs: true,
          items: [
            for (final s in SkillSection.values)
              WorkspaceSectionNavItem(
                label: s.title(context.l10n),
                icon: skillSectionIcon(s),
                selected: s == section,
                onSelect: () => select(s),
              ),
          ],
          body: switch (section) {
            SkillSection.installed => BlocBuilder<SkillCubit, SkillState>(
              builder: (context, state) => SkillInstalledSection(
                state: state,
                onGoDiscovery: () => select(SkillSection.discovery),
              ),
            ),
            SkillSection.discovery => SkillDiscoverySection(
              onGoRegistries: () => select(SkillSection.registries),
            ),
            SkillSection.registries => const SkillRegistriesSection(),
          },
        ),
      ),
    );
  }
}
