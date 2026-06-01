import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/plugin_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/app_keys.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../../widgets/settings/workspace_section_host.dart';
import 'plugin_discovery_section.dart';
import 'plugin_installed_section.dart';
import 'plugin_marketplaces_section.dart';
import 'plugin_section.dart';

export 'plugin_section.dart';

class PluginManagementHubPage extends StatelessWidget {
  const PluginManagementHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WorkspaceHubPage(
      pageKey: AppKeys.pluginsHub,
      title: l10n.pluginsTitle,
      subtitle: l10n.pluginsSubtitle,
      entries: [
        for (final section in PluginSection.values)
          WorkspaceHubEntry(
            title: section.title(l10n),
            icon: pluginSectionIcon(section),
            onTap: throttledTap(
              'plugin_hub_${section.name}',
              () => context.push(section.routePath('/plugins')),
            ),
          ),
      ],
    );
  }
}

class PluginManagementPage extends StatelessWidget {
  const PluginManagementPage({required this.section, super.key});

  final PluginSection section;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PluginCubit, PluginState>(
      listenWhen: (a, b) =>
          a.errorMessage != b.errorMessage && b.errorMessage != null,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.errorMessage!),
            duration: const Duration(seconds: 4),
          ),
        );
        context.read<PluginCubit>().clearError();
      },
      builder: (context, state) {
        final sectionBody = switch (section) {
          PluginSection.installed => PluginInstalledSection(
            state: state,
            onGoDiscovery: () =>
                navigatePluginSection(context, PluginSection.discovery),
          ),
          PluginSection.discovery => PluginDiscoverySection(
            state: state,
            onGoMarketplaces: () =>
                navigatePluginSection(context, PluginSection.marketplaces),
          ),
          PluginSection.marketplaces => PluginMarketplacesSection(state: state),
        };

        return WorkspaceAdaptiveSectionPage(
          pageKey: AppKeys.pluginsWorkspace,
          title: context.l10n.pluginsTitle,
          subtitle: context.l10n.pluginsSubtitle,
          bodyAnimationKey: ValueKey('plugins-body-${section.name}'),
          nav: WorkspaceEnumNavPanel<PluginSection>(
            sections: PluginSection.values,
            current: section,
            basePath: '/plugins',
            descriptor: (s) => s,
            onSelect: (target) => navigatePluginSection(context, target),
          ),
          body: sectionBody,
        );
      },
    );
  }
}
