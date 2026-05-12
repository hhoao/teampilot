import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/config_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/layout_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/app_workspace_settings_theme.dart';
import '../utils/app_keys.dart';
import '../widgets/settings/workspace_settings_widgets.dart';
import '../utils/perf.dart';
import 'llm_config_workspace.dart';

class ConfigWorkspace extends StatelessWidget {
  const ConfigWorkspace({this.section, super.key});

  final ConfigSection? section;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final configCubit = context.watch<ConfigCubit>();
    final teamCubit = context.watch<TeamCubit>();
    final team = teamCubit.state.selectedTeam;

    if (section != null && configCubit.state.section != section) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        configCubit.selectSection(section!);
      });
    }

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      key: AppKeys.configWorkspace,
      color: colors.workspaceBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsTitleBar(
            title: l10n.settings,
            subtitle: l10n.settingsPageSubtitle,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 820;
                final navWidth = compact ? 220.0 : 314.0;
                final contentPadding = compact
                    ? const EdgeInsets.fromLTRB(16, 20, 16, 16)
                    : const EdgeInsets.fromLTRB(24, 28, 28, 24);
                final bodyPaneWidth =
                    constraints.maxWidth - navWidth - 1;
                final configBodyMaxWidth =
                    (bodyPaneWidth - contentPadding.horizontal)
                        .clamp(480.0, 3200.0);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: navWidth,
                      child: _ConfigNavPanel(
                        section: configCubit.state.section,
                        compact: compact,
                        onSelectSection: (s) {
                          FramePerf.mark('nav config ${s.name}');
                          context.read<ConfigCubit>().selectSection(s);
                          context.go('/config/${s.name}');
                        },
                        l10n: l10n,
                      ),
                    ),
                    Container(width: 1, color: colors.subtleBorder),
                    Expanded(
                      child: PipelinePerf(
                        label: 'config body ${configCubit.state.section.name}',
                        child: BuildPerf(
                          label: 'config ${configCubit.state.section.name}',
                          builder: (_) => Padding(
                            padding: contentPadding,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: configBodyMaxWidth,
                                ),
                                child: switch (configCubit.state.section) {
                                  ConfigSection.layout =>
                                    const LayoutConfigWorkspace(),
                                  ConfigSection.llm =>
                                    const LlmConfigWorkspace(),
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}





class LayoutConfigWorkspace extends StatelessWidget {
  const LayoutConfigWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final layoutController = context.watch<LayoutCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WorkspaceHeading(
          title: l10n.layout,
          subtitle: l10n.layoutPageSubtitle,
        ),
        const SizedBox(height: 16),
        _LayoutControls(
          preferences: layoutController.state.preferences,
          controller: layoutController,
        ),
      ],
    );
  }
}

class _LayoutControls extends StatelessWidget {
  const _LayoutControls({required this.preferences, required this.controller});

  final LayoutPreferences preferences;
  final LayoutCubit controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = AppWorkspaceSettingsTokens.of(context);
    final segmentStyle = workspaceSettingsEmphasizedSegmentButtonStyle(context);
    final iconSize = tokens.segmentedIconSize;
    var themeMode = preferences.themeMode;
    if (themeMode != 'light' && themeMode != 'dark' && themeMode != 'system') {
      themeMode = 'system';
    }
    final systemLang = Localizations.localeOf(context).languageCode;
    final effectiveLang = preferences.locale.isNotEmpty
        ? preferences.locale
        : systemLang;
    final langValue = effectiveLang.startsWith('zh') ? 'zh' : 'en';

    return Expanded(
      child: SingleChildScrollView(
        child: SettingsSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsLabeledRow(
                title: l10n.toolPlacement,
                subtitle: l10n.toolPlacementDescription,
                trailing: SegmentedButton<ToolPanelPlacement>(
                  style: segmentStyle,
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment<ToolPanelPlacement>(
                      value: ToolPanelPlacement.right,
                      label: Text(l10n.right),
                      icon: Icon(
                        Icons.vertical_split_outlined,
                        size: iconSize,
                      ),
                    ),
                    ButtonSegment<ToolPanelPlacement>(
                      value: ToolPanelPlacement.bottom,
                      label: Text(l10n.bottom),
                      icon: Icon(Icons.splitscreen_outlined, size: iconSize),
                    ),
                  ],
                  selected: {preferences.toolPlacement},
                  onSelectionChanged: (selection) =>
                      controller.setToolPlacement(selection.single),
                ),
                showDividerBelow: true,
              ),
              SettingsLabeledRow(
                title: l10n.membersAndFileTree,
                subtitle: l10n.membersAndFileTreeDescription,
                trailing: SegmentedButton<ToolsArrangement>(
                  style: segmentStyle,
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment<ToolsArrangement>(
                      value: ToolsArrangement.stacked,
                      label: Text(l10n.stacked),
                      icon: Icon(Icons.view_agenda_outlined, size: iconSize),
                    ),
                    ButtonSegment<ToolsArrangement>(
                      value: ToolsArrangement.tabs,
                      label: Text(l10n.tabs),
                      icon: Icon(Icons.tab_outlined, size: iconSize),
                    ),
                  ],
                  selected: {preferences.toolsArrangement},
                  onSelectionChanged: (selection) =>
                      controller.setToolsArrangement(selection.single),
                ),
                showDividerBelow: true,
              ),
              SettingsGroupHeader(title: l10n.regionVisibility),
              SettingsLabeledRow(
                title: l10n.teamSessions,
                subtitle: l10n.visibilityTeamSessionsHint,
                trailing: Switch(
                  key: AppKeys.contextSidebarVisibilitySwitch,
                  value: preferences.contextSidebarVisible,
                  onChanged: (value) =>
                      _setVisibility(contextSidebarVisible: value),
                ),
                showDividerBelow: true,
              ),
              SettingsLabeledRow(
                title: l10n.members,
                subtitle: l10n.visibilityMembersHint,
                trailing: Switch(
                  key: AppKeys.membersVisibilitySwitch,
                  value: preferences.membersVisible,
                  onChanged: (value) => _setVisibility(membersVisible: value),
                ),
                showDividerBelow: true,
              ),
              SettingsLabeledRow(
                title: l10n.fileTree,
                subtitle: l10n.visibilityFileTreeHint,
                trailing: Switch(
                  key: AppKeys.fileTreeVisibilitySwitch,
                  value: preferences.fileTreeVisible,
                  onChanged: (value) => _setVisibility(fileTreeVisible: value),
                ),
                showDividerBelow: true,
              ),
              SettingsGroupHeader(title: l10n.appearance),
              SettingsLabeledRow(
                title: l10n.themeModeTitle,
                subtitle: l10n.themeModeDescription,
                trailing: SegmentedButton<String>(
                  style: segmentStyle,
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment<String>(
                      value: 'light',
                      tooltip: l10n.themeLight,
                      icon: Icon(Icons.light_mode_outlined, size: iconSize),
                      label: Text(l10n.themeLight),
                    ),
                    ButtonSegment<String>(
                      value: 'dark',
                      tooltip: l10n.themeDark,
                      icon: Icon(Icons.dark_mode_outlined, size: iconSize),
                      label: Text(l10n.themeDark),
                    ),
                    ButtonSegment<String>(
                      value: 'system',
                      tooltip: l10n.themeSystem,
                      icon: Icon(
                        Icons.desktop_windows_outlined,
                        size: iconSize,
                      ),
                      label: Text(l10n.themeSystem),
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (selection) =>
                      controller.setThemeMode(selection.single),
                ),
                showDividerBelow: true,
              ),
              SettingsLabeledRow(
                title: l10n.language,
                subtitle: l10n.languageDescription,
                trailing: SettingsCompactDropdown<String>(
                  value: langValue,
                  items: [
                    DropdownMenuItem(
                      key: AppKeys.languageEnButton,
                      value: 'en',
                      child: Text(l10n.languageEnglish),
                    ),
                    DropdownMenuItem(
                      key: AppKeys.languageZhButton,
                      value: 'zh',
                      child: Text(l10n.languageChinese),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) controller.setLocale(v);
                  },
                ),
                showDividerBelow: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setVisibility({
    bool? contextSidebarVisible,
    bool? membersVisible,
    bool? fileTreeVisible,
  }) {
    controller.setRegionVisibility(
      appRailVisible: true,
      contextSidebarVisible:
          contextSidebarVisible ?? preferences.contextSidebarVisible,
      membersVisible: membersVisible ?? preferences.membersVisible,
      fileTreeVisible: fileTreeVisible ?? preferences.fileTreeVisible,
    );
  }
}

class _SettingsTitleBar extends StatelessWidget {
  const _SettingsTitleBar({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 42, 40, 28),
      decoration: BoxDecoration(
        color: colors.workspaceBackground,
        border: Border(bottom: BorderSide(color: colors.subtleBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textBase,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textBase.withValues(alpha: 0.66),
              fontSize: 14,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceHeading extends StatelessWidget {
  const _WorkspaceHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = AppWorkspaceSettingsTokens.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: tokens.workspaceHeadingTitleStyle(onSurface)),
        SizedBox(height: tokens.workspaceHeadingTitleSubtitleGap),
        Text(subtitle, style: tokens.workspaceHeadingSubtitleStyle(onSurface)),
      ],
    );
  }
}

class _ConfigNavPanel extends StatelessWidget {
  const _ConfigNavPanel({
    required this.section,
    required this.compact,
    required this.onSelectSection,
    required this.l10n,
  });

  final ConfigSection section;
  final bool compact;
  final ValueChanged<ConfigSection> onSelectSection;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      color: colors.workspaceBackground,
      padding: compact
          ? const EdgeInsets.fromLTRB(14, 22, 12, 20)
          : const EdgeInsets.fromLTRB(24, 28, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConfigNavItem(
            key: AppKeys.configLlmSectionButton,
            title: l10n.llmConfig,
            icon: Icons.memory_outlined,
            compact: compact,
            selected: section == ConfigSection.llm,
            onTap: () => onSelectSection(ConfigSection.llm),
          ),
          _ConfigNavItem(
            key: AppKeys.configLayoutSectionButton,
            title: l10n.layout,
            icon: Icons.dashboard_customize_outlined,
            compact: compact,
            selected: section == ConfigSection.layout,
            onTap: () => onSelectSection(ConfigSection.layout),
          ),
        ],
      ),
    );
  }
}

class _ConfigNavItem extends StatelessWidget {
  const _ConfigNavItem({
    super.key,
    required this.title,
    required this.icon,
    required this.compact,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final muted = textBase.withValues(alpha: 0.64);
    final selectedColor = colors.selectedBackground;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? selectedColor : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 54,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: selected ? textBase : muted,
                    size: compact ? 21 : 23,
                  ),
                  SizedBox(width: compact ? 12 : 16),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 14 : 15,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: selected ? textBase : muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
