import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/extension_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/app_keys.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../../widgets/settings/workspace_section_host.dart';
import 'extension_installed_section.dart';
import 'extension_section.dart';

export 'extension_section.dart';

/// Android hub: a list entry per Extensions section.
class ExtensionManagementHubPage extends StatelessWidget {
  const ExtensionManagementHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WorkspaceHubPage(
      pageKey: AppKeys.extensionsHub,
      title: l10n.extensionsSettingsTitle,
      subtitle: l10n.extensionsSettingsDescription,
      entries: [
        for (final section in ExtensionSection.values)
          WorkspaceHubEntry(
            title: section.title(l10n),
            icon: extensionSectionIcon(section),
            onTap: throttledTap(
              'extension_hub_${section.name}',
              () => context.push(section.routePath('/extensions')),
            ),
          ),
      ],
    );
  }
}

class ExtensionManagementPage extends StatelessWidget {
  const ExtensionManagementPage({
    required this.section,
    this.onSelectSection,
    super.key,
  });

  final ExtensionSection section;

  /// When set, section switches call this instead of route navigation — lets
  /// the page be embedded (e.g. in the workspace home) with local-state nav.
  final void Function(ExtensionSection target)? onSelectSection;

  @override
  Widget build(BuildContext context) {
    void select(ExtensionSection target) => onSelectSection != null
        ? onSelectSection!(target)
        : navigateExtensionSection(context, target);
    return BlocConsumer<ExtensionCubit, ExtensionUiState>(
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
        context.read<ExtensionCubit>().clearError();
      },
      builder: (context, state) {
        return WorkspaceAdaptiveSectionPage(
          pageKey: AppKeys.extensionsWorkspace,
          title: context.l10n.extensionsSettingsTitle,
          subtitle: context.l10n.extensionsSettingsDescription,
          bodyAnimationKey: ValueKey('extensions-body-${section.name}'),
          nav: WorkspaceEnumNavPanel<ExtensionSection>(
            sections: ExtensionSection.values,
            current: section,
            basePath: '/extensions',
            descriptor: (s) => s,
            onSelect: select,
          ),
          body: ExtensionInstalledSection(state: state),
        );
      },
    );
  }
}
