import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/config_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/layout_preferences.dart';
import '../services/platform_utils.dart';
import '../theme/app_theme.dart';
import '../utils/app_keys.dart';
import '../widgets/settings/workspace_hub_shell.dart';
import '../widgets/settings/workspace_settings_toggle_strip.dart';
import '../widgets/settings/workspace_settings_widgets.dart';
import 'llm_config_workspace.dart';
import 'session_config_workspace.dart';

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
          key: AppKeys.configLlmSectionButton,
          title: l10n.llmConfig,
          icon: Icons.memory_outlined,
          onTap: () {
            context.read<ConfigCubit>().selectSection(ConfigSection.llm);
            context.push('/config/llm');
          },
        ),
        WorkspaceHubEntry(
          key: AppKeys.configLayoutSectionButton,
          title: l10n.layout,
          icon: Icons.dashboard_customize_outlined,
          onTap: () {
            context.read<ConfigCubit>().selectSection(ConfigSection.layout);
            context.push('/config/layout');
          },
        ),
        WorkspaceHubEntry(
          key: AppKeys.configSessionSectionButton,
          title: l10n.session,
          icon: Icons.terminal_outlined,
          onTap: () {
            context.read<ConfigCubit>().selectSection(ConfigSection.session);
            context.push('/config/session');
          },
        ),
        WorkspaceHubEntry(
          key: AppKeys.configSshProfilesSectionButton,
          title: l10n.sshProfilesSettingsTitle,
          icon: Icons.dns_outlined,
          onTap: () => context.push('/config/ssh-profiles'),
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
    final team = context.watch<TeamCubit>().state.selectedTeam;

    if (configCubit.state.section != section) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        configCubit.selectSection(section);
      });
    }

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (useAndroidHubNavigation(context)) {
      return _AndroidConfigSectionPage(section: section);
    }

    return _DesktopConfigWorkspace(
      section: configCubit.state.section,
      onSelectSection: (selected) {
        context.read<ConfigCubit>().selectSection(selected);
        context.go('/config/${selected.name}');
      },
    );
  }
}

class _AndroidConfigSectionPage extends StatelessWidget {
  const _AndroidConfigSectionPage({required this.section});

  final ConfigSection section;

  @override
  Widget build(BuildContext context) {
    const showHeading = false;

    return WorkspaceSectionPage(
      pageKey: AppKeys.configWorkspace,
      child: switch (section) {
        ConfigSection.layout => LayoutConfigWorkspace(showHeading: showHeading),
        ConfigSection.llm => const LlmConfigWorkspace(),
        ConfigSection.session => SessionConfigWorkspace(
          showHeading: showHeading,
        ),
      },
    );
  }
}

class _DesktopConfigWorkspace extends StatelessWidget {
  const _DesktopConfigWorkspace({
    required this.section,
    required this.onSelectSection,
  });

  final ConfigSection section;
  final ValueChanged<ConfigSection> onSelectSection;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Container(
      key: AppKeys.configWorkspace,
      color: cs.workspacePage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceHubTitleBar(
            title: l10n.settings,
            subtitle: l10n.settingsPageSubtitle,
          ),
          Expanded(
            child: WorkspaceSplitShell(
              nav: _ConfigNavPanel(
                section: section,
                onSelectSection: onSelectSection,
                l10n: l10n,
              ),
              body: switch (section) {
                ConfigSection.layout => const LayoutConfigWorkspace(),
                ConfigSection.llm => const LlmConfigWorkspace(),
                ConfigSection.session => const SessionConfigWorkspace(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class LayoutConfigWorkspace extends StatelessWidget {
  const LayoutConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          WorkspaceSectionHeading(
            title: l10n.layout,
            subtitle: l10n.layoutPageSubtitle,
          ),
          const SizedBox(height: 16),
        ],
        const Expanded(child: _LayoutSettingsScroll()),
      ],
    );
  }
}

class _LayoutSettingsScroll extends StatelessWidget {
  const _LayoutSettingsScroll();

  @override
  Widget build(BuildContext context) {
    // return SizedBox(width: 360, height: 640);
    return SingleChildScrollView(
      child: SettingsSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            _ToolLayoutSettingsSection(),
            _RegionVisibilitySettingsSection(),
            _AppearanceSettingsSection(),
          ],
        ),
      ),
    );
  }
}

class _ToolLayoutSettingsSection extends StatelessWidget {
  const _ToolLayoutSettingsSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<LayoutCubit>();

    return BlocSelector<
      LayoutCubit,
      LayoutState,
      (ToolPanelPlacement, ToolsArrangement)
    >(
      selector: (state) =>
          (state.preferences.toolPlacement, state.preferences.toolsArrangement),
      builder: (context, prefs) {
        final (toolPlacement, toolsArrangement) = prefs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsLabeledRow(
              title: l10n.toolPlacement,
              subtitle: l10n.toolPlacementDescription,
              trailing: WorkspaceSettingsToggleStrip<ToolPanelPlacement>(
                segments: [
                  WorkspaceToggleSegment<ToolPanelPlacement>(
                    value: ToolPanelPlacement.right,
                    label: l10n.right,
                    icon: Icons.vertical_split_outlined,
                  ),
                  WorkspaceToggleSegment<ToolPanelPlacement>(
                    value: ToolPanelPlacement.bottom,
                    label: l10n.bottom,
                    icon: Icons.splitscreen_outlined,
                  ),
                ],
                selected: toolPlacement,
                onChanged: controller.setToolPlacement,
              ),
              showDividerBelow: true,
            ),
            SettingsLabeledRow(
              title: l10n.membersAndFileTree,
              subtitle: l10n.membersAndFileTreeDescription,
              trailing: WorkspaceSettingsToggleStrip<ToolsArrangement>(
                segments: [
                  WorkspaceToggleSegment<ToolsArrangement>(
                    value: ToolsArrangement.stacked,
                    label: l10n.stacked,
                    icon: Icons.view_agenda_outlined,
                  ),
                  WorkspaceToggleSegment<ToolsArrangement>(
                    value: ToolsArrangement.tabs,
                    label: l10n.tabs,
                    icon: Icons.tab_outlined,
                  ),
                ],
                selected: toolsArrangement,
                onChanged: controller.setToolsArrangement,
              ),
              showDividerBelow: true,
            ),
          ],
        );
      },
    );
  }
}

class _RegionVisibilitySettingsSection extends StatelessWidget {
  const _RegionVisibilitySettingsSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<LayoutCubit>();

    return BlocSelector<LayoutCubit, LayoutState, (bool, bool, bool)>(
      selector: (state) => (
        state.preferences.contextSidebarVisible,
        state.preferences.membersVisible,
        state.preferences.fileTreeVisible,
      ),
      builder: (context, visibility) {
        final (contextSidebarVisible, membersVisible, fileTreeVisible) =
            visibility;

        void setVisibility({
          bool? contextSidebarVisible,
          bool? membersVisible,
          bool? fileTreeVisible,
        }) {
          controller.setRegionVisibility(
            appRailVisible: true,
            contextSidebarVisible: contextSidebarVisible ?? visibility.$1,
            membersVisible: membersVisible ?? visibility.$2,
            fileTreeVisible: fileTreeVisible ?? visibility.$3,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsGroupHeader(title: l10n.regionVisibility),
            SettingsLabeledRow(
              title: l10n.teamSessions,
              subtitle: l10n.visibilityTeamSessionsHint,
              trailing: Switch(
                key: AppKeys.contextSidebarVisibilitySwitch,
                value: contextSidebarVisible,
                onChanged: (value) =>
                    setVisibility(contextSidebarVisible: value),
              ),
              showDividerBelow: true,
            ),
            SettingsLabeledRow(
              title: l10n.members,
              subtitle: l10n.visibilityMembersHint,
              trailing: Switch(
                key: AppKeys.membersVisibilitySwitch,
                value: membersVisible,
                onChanged: (value) => setVisibility(membersVisible: value),
              ),
              showDividerBelow: true,
            ),
            SettingsLabeledRow(
              title: l10n.fileTree,
              subtitle: l10n.visibilityFileTreeHint,
              trailing: Switch(
                key: AppKeys.fileTreeVisibilitySwitch,
                value: fileTreeVisible,
                onChanged: (value) => setVisibility(fileTreeVisible: value),
              ),
              showDividerBelow: true,
            ),
          ],
        );
      },
    );
  }
}

class _AppearanceSettingsSection extends StatelessWidget {
  const _AppearanceSettingsSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<LayoutCubit>();

    return BlocSelector<LayoutCubit, LayoutState, (String, String, String)>(
      selector: (state) {
        var themeMode = state.preferences.themeMode;
        if (themeMode != 'light' &&
            themeMode != 'dark' &&
            themeMode != 'system') {
          themeMode = 'system';
        }
        final systemLang =
            WidgetsBinding.instance.platformDispatcher.locale.languageCode;
        final effectiveLang = state.preferences.locale.isNotEmpty
            ? state.preferences.locale
            : systemLang;
        final langValue = effectiveLang.startsWith('zh') ? 'zh' : 'en';
        return (
          themeMode,
          normalizeThemeColorPreset(state.preferences.themeColorPreset),
          langValue,
        );
      },
      builder: (context, appearance) {
        final (themeMode, colorPreset, langValue) = appearance;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsGroupHeader(title: l10n.appearance),
            SettingsLabeledRow(
              title: l10n.themeModeTitle,
              subtitle: l10n.themeModeDescription,
              trailing: WorkspaceSettingsToggleStrip<String>(
                segments: [
                  WorkspaceToggleSegment<String>(
                    value: 'light',
                    label: l10n.themeLight,
                    icon: Icons.light_mode_outlined,
                  ),
                  WorkspaceToggleSegment<String>(
                    value: 'dark',
                    label: l10n.themeDark,
                    icon: Icons.dark_mode_outlined,
                  ),
                  WorkspaceToggleSegment<String>(
                    value: 'system',
                    label: l10n.themeSystem,
                    icon: Icons.desktop_windows_outlined,
                  ),
                ],
                selected: themeMode,
                onChanged: controller.setThemeMode,
              ),
              showDividerBelow: true,
            ),
            SettingsLabeledRow(
              title: l10n.themeColorPresetTitle,
              subtitle: l10n.themeColorPresetDescription,
              trailing: _ThemeColorPresetPicker(
                selected: colorPreset,
                onSelect: controller.setThemeColorPreset,
              ),
              showDividerBelow: true,
            ),
            SettingsLabeledRow(
              title: l10n.language,
              subtitle: l10n.languageDescription,
              trailing: SettingsCompactDropdown<String>(
                value: langValue,
                entries: [
                  ('en', l10n.languageEnglish),
                  ('zh', l10n.languageChinese),
                ],
                itemKeys: const {
                  'en': AppKeys.languageEnButton,
                  'zh': AppKeys.languageZhButton,
                },
                onChanged: (v) {
                  if (v != null) controller.setLocale(v);
                },
              ),
              showDividerBelow: false,
            ),
          ],
        );
      },
    );
  }
}

class _ThemeColorPresetPicker extends StatelessWidget {
  const _ThemeColorPresetPicker({
    required this.selected,
    required this.onSelect,
  });

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Align(
      alignment: Alignment.centerRight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final id in kThemeColorPresetIds)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _ThemeColorPresetChip(
                  id: id,
                  label: l10n.themeColorPresetName(id),
                  selected: id == selected,
                  onTap: () => onSelect(id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemeColorPresetChip extends StatelessWidget {
  const _ThemeColorPresetChip({
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final primary = themePresetSwatchPrimary(id);
    final secondary = themePresetSwatchSecondary(id);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.workspaceInset,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: secondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: textBase.withValues(alpha: selected ? 1 : 0.78),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigNavPanel extends StatelessWidget {
  const _ConfigNavPanel({
    required this.section,
    required this.onSelectSection,
    required this.l10n,
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
          onTap: () => onSelectSection(ConfigSection.layout),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configLlmSectionButton,
          title: l10n.llmConfig,
          icon: Icons.memory_outlined,
          selected: section == ConfigSection.llm,
          onTap: () => onSelectSection(ConfigSection.llm),
        ),
        WorkspaceHubEntry(
          key: AppKeys.configSessionSectionButton,
          title: l10n.session,
          icon: Icons.terminal_outlined,
          selected: section == ConfigSection.session,
          onTap: () => onSelectSection(ConfigSection.session),
        ),
      ],
    );
  }
}
