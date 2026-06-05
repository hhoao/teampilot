import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/config_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/app_keys.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/settings/settings_dialog.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../../widgets/settings/workspace_section_host.dart';
import '../about_page.dart';
import '../system/log_config_workspace.dart';
import 'appearance_config_section.dart';
import 'layout_config_section.dart';
import 'session_config_section.dart';

/// Opens the workspace quick-settings modal from anywhere (e.g. the title bar).
///
/// Self-contained sections (layout/appearance, session) render inline; sections
/// that depend on the `/config/*` route tree (about) close the dialog and
/// navigate to the full settings route instead.
Future<void> showWorkspaceSettingsDialog(BuildContext context) {
  final l10n = context.l10n;

  void goToSection(ConfigSection section) {
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    context.read<ConfigCubit>().selectSection(section);
    navigator.pop();
    router.go('/config/${section.name}');
  }

  return showSettingsDialog(
    context,
    navTitle: l10n.settings,
    entries: [
      SettingsDialogEntry(
        icon: Icons.dashboard_customize_outlined,
        navLabel: l10n.layout,
        title: l10n.layout,
        subtitle: l10n.layoutPageSubtitle,
        body: const LayoutConfigWorkspace(showHeading: false),
      ),
      SettingsDialogEntry(
        icon: Icons.palette_outlined,
        navLabel: l10n.appearance,
        title: l10n.appearance,
        subtitle: l10n.appearancePageSubtitle,
        body: const AppearanceConfigWorkspace(showHeading: false),
      ),
      SettingsDialogEntry(
        icon: Icons.terminal_outlined,
        navLabel: l10n.session,
        title: l10n.session,
        subtitle: l10n.sessionPageSubtitle,
        body: const SessionConfigWorkspace(showHeading: false),
      ),
      SettingsDialogEntry(
        icon: Icons.info_outline,
        navLabel: l10n.aboutTitle,
        title: l10n.aboutTitle,
        subtitle: l10n.aboutPageSubtitle,
        body: AboutConfigWorkspace(
          showHeading: false,
          onViewLogs: () => goToSection(ConfigSection.logs),
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
    if (context.watch<TeamCubit>().state.selectedTeam == null) {
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
          key: AppKeys.configSshProfilesSectionButton,
          title: l10n.sshProfilesSettingsTitle,
          icon: Icons.dns_outlined,
          onTap: throttledTap(
            'config_hub_ssh_profiles',
            () => context.push('/config/ssh-profiles'),
          ),
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
  const ConfigWorkspace({
    required this.section,
    super.key,
  });

  final ConfigSection section;

  @override
  Widget build(BuildContext context) {
    final configCubit = context.watch<ConfigCubit>();
    final team = context.watch<TeamCubit>().state.selectedTeam;
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
      bodyAnimationKey: ValueKey('settings-body-${section.name}'),
      nav: ConfigNavPanel(
        section: currentSection,
        onSelectSection: (selected) {
          context.read<ConfigCubit>().selectSection(selected);
          context.go('/config/${selected.name}');
        },
        l10n: l10n,
      ),
      body: switch (currentSection) {
        ConfigSection.layout => LayoutConfigWorkspace(showHeading: showHeading),
        ConfigSection.session => SessionConfigWorkspace(
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
      animateEntries: true,
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
