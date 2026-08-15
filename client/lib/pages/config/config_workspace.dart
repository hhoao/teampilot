import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/config_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/app/platform_utils.dart';
import '../../utils/ui/app_keys.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/settings/settings_dialog.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../../widgets/settings/workspace_section_host.dart';
import '../about_page.dart';
import '../system/log_config_workspace.dart';
import 'ai_features_config_section.dart';
import 'cli_config_section.dart';
import 'github_config_section.dart';
import 'download_sources_config_section.dart';
import 'discovery_config_section.dart';
import 'layout_config_section.dart';
import 'session_config_section.dart';
import 'shortcuts_config_section.dart';
import 'ssh_profiles_config_section.dart';

int _configSectionDialogIndex(ConfigSection section) {
  return switch (section) {
    ConfigSection.layout => 0,
    ConfigSection.session => 1,
    ConfigSection.cli => 2,
    ConfigSection.aiFeatures => 3,
    ConfigSection.sshProfiles => 4,
    ConfigSection.github => 5,
    ConfigSection.downloadSources => 6,
    ConfigSection.discovery => 7,
    ConfigSection.shortcuts => 8,
    ConfigSection.about => 9,
    ConfigSection.logs => 9,
  };
}

/// Opens SSH profile management without leaving the active workspace.
void openSshProfilesManagement(BuildContext context) {
  if (useAndroidHubNavigation(context)) {
    context.read<ConfigCubit>().selectSection(ConfigSection.sshProfiles);
    context.push('/config/${ConfigSection.sshProfiles.routeSegment}');
    return;
  }
  showWorkspaceSettingsDialog(
    context,
    initialSection: ConfigSection.sshProfiles,
  );
}

/// Opens the workspace quick-settings modal from anywhere (e.g. the title bar).
Future<void> showWorkspaceSettingsDialog(
  BuildContext context, {
  ConfigSection? initialSection,
}) {
  final initialIndex = initialSection == null
      ? 0
      : _configSectionDialogIndex(initialSection);
  return showSettingsDialog(
    context,
    navTitle: (l10n) => l10n.settings,
    initialIndex: initialIndex,
    entries: [
      SettingsDialogEntry(
        icon: Icons.dashboard_customize_outlined,
        navLabel: (l10n) => l10n.layout,
        title: (l10n) => l10n.layout,
        subtitle: (l10n) => l10n.layoutPageSubtitle,
        bodyBuilder: (_) => const LayoutConfigWorkspace(showHeading: false),
      ),
      SettingsDialogEntry(
        icon: Icons.terminal_outlined,
        navLabel: (l10n) => l10n.session,
        title: (l10n) => l10n.session,
        subtitle: (l10n) => l10n.sessionPageSubtitle,
        bodyBuilder: (_) => const SessionConfigWorkspace(showHeading: false),
      ),
      SettingsDialogEntry(
        icon: Icons.code_outlined,
        navLabel: (l10n) => l10n.cliConfig,
        title: (l10n) => l10n.cliConfig,
        subtitle: (l10n) => l10n.cliConfigPageSubtitle,
        bodyBuilder: (_) => const CliConfigWorkspace(showHeading: false),
      ),
      SettingsDialogEntry(
        icon: Icons.auto_awesome_outlined,
        navLabel: (l10n) => l10n.aiFeatures,
        title: (l10n) => l10n.aiFeatures,
        subtitle: (l10n) => l10n.aiFeaturesPageSubtitle,
        bodyBuilder: (_) => const AiFeaturesConfigWorkspace(showHeading: false),
      ),
      SettingsDialogEntry(
        icon: Icons.dns_outlined,
        navLabel: (l10n) => l10n.sshProfilesSettingsTitle,
        title: (l10n) => l10n.sshProfilesPageTitle,
        subtitle: (l10n) => l10n.sshProfilesPageSubtitle,
        bodyBuilder: (_) =>
            const SshProfilesConfigWorkspace(showHeading: false),
      ),
      SettingsDialogEntry(
        icon: Icons.hub_outlined,
        navLabel: (l10n) => l10n.githubSettingsTitle,
        title: (l10n) => l10n.githubSettingsTitle,
        subtitle: (l10n) => l10n.githubSettingsSubtitle,
        bodyBuilder: (_) => const GithubConfigWorkspace(showHeading: false),
      ),
      SettingsDialogEntry(
        icon: Icons.cloud_download_outlined,
        navLabel: (l10n) => l10n.downloadSourcesSettingsTitle,
        title: (l10n) => l10n.downloadSourcesSettingsTitle,
        subtitle: (l10n) => l10n.downloadSourcesSettingsSubtitle,
        bodyBuilder: (_) =>
            const DownloadSourcesConfigWorkspace(showHeading: false),
      ),
      SettingsDialogEntry(
        icon: Icons.storefront_outlined,
        navLabel: (l10n) => l10n.discoverySettingsTitle,
        title: (l10n) => l10n.discoverySettingsTitle,
        subtitle: (l10n) => l10n.discoverySettingsSubtitle,
        bodyBuilder: (_) => const DiscoveryConfigWorkspace(showHeading: false),
      ),
      SettingsDialogEntry(
        icon: Icons.keyboard_outlined,
        navLabel: (l10n) => l10n.shortcutsSettingsTitle,
        title: (l10n) => l10n.shortcutsSettingsTitle,
        subtitle: (l10n) => l10n.shortcutsPageSubtitle,
        bodyBuilder: (_) => const ShortcutsConfigWorkspace(showHeading: false),
      ),
      SettingsDialogEntry(
        icon: Icons.info_outline,
        navLabel: (l10n) => l10n.aboutTitle,
        title: (l10n) => l10n.aboutTitle,
        subtitle: (l10n) => l10n.aboutPageSubtitle,
        bodyBuilder: (dialogContext) => AboutConfigWorkspace(
          showHeading: false,
          onViewLogs: () => showLogViewerDialog(dialogContext),
        ),
      ),
    ],
  );
}

/// Android settings landing: title + section list (each section is a full page).
class ConfigSettingsHubPage extends StatelessWidget {
  const ConfigSettingsHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (context.watch<LaunchProfileCubit>().state.selectedTeam == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return WorkspaceHubPage(
      pageKey: AppKeys.configSettingsHub,
      title: l10n.settings,
      subtitle: l10n.settingsPageSubtitle,
      entries: [
        WorkspaceHubEntry(
          key: AppKeys.configLayoutSectionButton,
          title: l10n.layout,
          icon: Icons.dashboard_customize_outlined,
          onTap: throttledTap('config_hub_layout', () {
            context.read<ConfigCubit>().selectSection(ConfigSection.layout);
            context.push('/config/layout');
          }),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configSessionSectionButton,
          title: l10n.session,
          icon: Icons.terminal_outlined,
          onTap: throttledTap('config_hub_session', () {
            context.read<ConfigCubit>().selectSection(ConfigSection.session);
            context.push('/config/session');
          }),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configCliSectionButton,
          title: l10n.cliConfig,
          icon: Icons.code_outlined,
          onTap: throttledTap('config_hub_cli', () {
            context.read<ConfigCubit>().selectSection(ConfigSection.cli);
            context.push('/config/cli');
          }),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configAiFeaturesSectionButton,
          title: l10n.aiFeatures,
          icon: Icons.auto_awesome_outlined,
          onTap: throttledTap('config_hub_ai_features', () {
            context.read<ConfigCubit>().selectSection(ConfigSection.aiFeatures);
            context.push('/config/${ConfigSection.aiFeatures.routeSegment}');
          }),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configSshProfilesSectionButton,
          title: l10n.sshProfilesSettingsTitle,
          icon: Icons.dns_outlined,
          onTap: throttledTap('config_hub_ssh_profiles', () {
            context.read<ConfigCubit>().selectSection(
              ConfigSection.sshProfiles,
            );
            context.push('/config/${ConfigSection.sshProfiles.routeSegment}');
          }),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configGithubSectionButton,
          title: l10n.githubSettingsTitle,
          icon: Icons.hub_outlined,
          onTap: throttledTap('config_hub_github', () {
            context.read<ConfigCubit>().selectSection(ConfigSection.github);
            context.push('/config/${ConfigSection.github.routeSegment}');
          }),
        ),
        WorkspaceHubEntry(
          title: l10n.downloadSourcesSettingsTitle,
          icon: Icons.cloud_download_outlined,
          onTap: throttledTap('config_hub_download_sources', () {
            context.read<ConfigCubit>().selectSection(
              ConfigSection.downloadSources,
            );
            context.push(
              '/config/${ConfigSection.downloadSources.routeSegment}',
            );
          }),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configDiscoverySectionButton,
          title: l10n.discoverySettingsTitle,
          icon: Icons.storefront_outlined,
          onTap: throttledTap('config_hub_discovery', () {
            context.read<ConfigCubit>().selectSection(ConfigSection.discovery);
            context.push('/config/${ConfigSection.discovery.routeSegment}');
          }),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configShortcutsSectionButton,
          title: l10n.shortcutsSettingsTitle,
          icon: Icons.keyboard_outlined,
          onTap: throttledTap('config_hub_shortcuts', () {
            context.read<ConfigCubit>().selectSection(
              ConfigSection.shortcuts,
            );
            context.push('/config/${ConfigSection.shortcuts.routeSegment}');
          }),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configAboutSectionButton,
          title: l10n.aboutTitle,
          icon: Icons.info_outline,
          onTap: throttledTap('config_hub_about', () {
            context.read<ConfigCubit>().selectSection(ConfigSection.about);
            context.push('/config/about');
          }),
        ),
      ],
    );
  }
}

class ConfigWorkspace extends StatelessWidget {
  const ConfigWorkspace({required this.section, super.key});

  final ConfigSection section;

  @override
  Widget build(BuildContext context) {
    final configCubit = context.watch<ConfigCubit>();
    final team = context.watch<LaunchProfileCubit>().state.selectedTeam;
    final l10n = context.l10n;

    if (configCubit.state.section != section) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        configCubit.selectSection(section);
      });
    }

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }

    const showHeading = false;
    final currentSection = configCubit.state.section;

    return WorkspaceAdaptiveSectionPage(
      pageKey: AppKeys.configWorkspace,
      title: l10n.settings,
      subtitle: l10n.settingsPageSubtitle,
      showSubtitle: false,
      nav: ConfigNavPanel(
        section: currentSection,
        onSelectSection: (selected) {
          context.read<ConfigCubit>().selectSection(selected);
          context.go('/config/${selected.routeSegment}');
        },
        l10n: l10n,
      ),
      body: switch (currentSection) {
        ConfigSection.layout => LayoutConfigWorkspace(showHeading: showHeading),
        ConfigSection.session => SessionConfigWorkspace(
          showHeading: showHeading,
        ),
        ConfigSection.cli => CliConfigWorkspace(showHeading: showHeading),
        ConfigSection.aiFeatures => AiFeaturesConfigWorkspace(
          showHeading: showHeading,
        ),
        ConfigSection.sshProfiles => SshProfilesConfigWorkspace(
          showHeading: showHeading,
        ),
        ConfigSection.github => GithubConfigWorkspace(showHeading: showHeading),
        ConfigSection.downloadSources => DownloadSourcesConfigWorkspace(
          showHeading: showHeading,
        ),
        ConfigSection.discovery => DiscoveryConfigWorkspace(
          showHeading: showHeading,
        ),
        ConfigSection.shortcuts => ShortcutsConfigWorkspace(
          showHeading: showHeading,
        ),
        ConfigSection.about => AboutConfigWorkspace(showHeading: showHeading),
        ConfigSection.logs => LogConfigWorkspace(showHeading: showHeading),
      },
    );
  }
}

class ConfigNavPanel extends StatelessWidget {
  const ConfigNavPanel({
    required this.section,
    required this.onSelectSection,
    required this.l10n,
    super.key,
  });

  final ConfigSection section;
  final ValueChanged<ConfigSection> onSelectSection;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return WorkspaceHubNavList(
      sidebarStyle: true,
      entries: [
        WorkspaceHubEntry(
          key: AppKeys.configLayoutSectionButton,
          title: l10n.layout,
          icon: Icons.dashboard_customize_outlined,
          selected: section == ConfigSection.layout,
          onTap: throttledTap(
            'config_nav_layout',
            () => onSelectSection(ConfigSection.layout),
          ),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configSessionSectionButton,
          title: l10n.session,
          icon: Icons.terminal_outlined,
          selected: section == ConfigSection.session,
          onTap: throttledTap(
            'config_nav_session',
            () => onSelectSection(ConfigSection.session),
          ),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configCliSectionButton,
          title: l10n.cliConfig,
          icon: Icons.code_outlined,
          selected: section == ConfigSection.cli,
          onTap: throttledTap(
            'config_nav_cli',
            () => onSelectSection(ConfigSection.cli),
          ),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configAiFeaturesSectionButton,
          title: l10n.aiFeatures,
          icon: Icons.auto_awesome_outlined,
          selected: section == ConfigSection.aiFeatures,
          onTap: throttledTap(
            'config_nav_ai_features',
            () => onSelectSection(ConfigSection.aiFeatures),
          ),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configSshProfilesSectionButton,
          title: l10n.sshProfilesSettingsTitle,
          icon: Icons.dns_outlined,
          selected: section == ConfigSection.sshProfiles,
          onTap: throttledTap(
            'config_nav_ssh_profiles',
            () => onSelectSection(ConfigSection.sshProfiles),
          ),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configGithubSectionButton,
          title: l10n.githubSettingsTitle,
          icon: Icons.hub_outlined,
          selected: section == ConfigSection.github,
          onTap: throttledTap(
            'config_nav_github',
            () => onSelectSection(ConfigSection.github),
          ),
        ),
        WorkspaceHubEntry(
          title: l10n.downloadSourcesSettingsTitle,
          icon: Icons.cloud_download_outlined,
          selected: section == ConfigSection.downloadSources,
          onTap: throttledTap(
            'config_nav_download_sources',
            () => onSelectSection(ConfigSection.downloadSources),
          ),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configDiscoverySectionButton,
          title: l10n.discoverySettingsTitle,
          icon: Icons.storefront_outlined,
          selected: section == ConfigSection.discovery,
          onTap: throttledTap(
            'config_nav_discovery',
            () => onSelectSection(ConfigSection.discovery),
          ),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configShortcutsSectionButton,
          title: l10n.shortcutsSettingsTitle,
          icon: Icons.keyboard_outlined,
          selected: section == ConfigSection.shortcuts,
          onTap: throttledTap(
            'config_nav_shortcuts',
            () => onSelectSection(ConfigSection.shortcuts),
          ),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configAboutSectionButton,
          title: l10n.aboutTitle,
          icon: Icons.info_outline,
          selected: section == ConfigSection.about,
          onTap: throttledTap(
            'config_nav_about',
            () => onSelectSection(ConfigSection.about),
          ),
        ),
      ],
    );
  }
}
