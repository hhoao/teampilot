import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/config_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/layout_preferences.dart';
import '../theme/app_theme.dart';
import '../utils/app_keys.dart';
import '../widgets/settings/workspace_settings_toggle_strip.dart';
import '../widgets/settings/workspace_settings_widgets.dart';
import 'llm_config_workspace.dart';
import 'session_config_workspace.dart';

class ConfigWorkspace extends StatelessWidget {
  const ConfigWorkspace({this.section, super.key});

  final ConfigSection? section;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
      color: cs.surface,
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
                final navWidth = 220.0;
                final contentPadding = compact
                    ? const EdgeInsets.fromLTRB(16, 20, 16, 16)
                    : const EdgeInsets.fromLTRB(24, 28, 28, 24);
                final bodyPaneWidth = constraints.maxWidth - navWidth - 1;
                final configBodyMaxWidth =
                    (bodyPaneWidth - contentPadding.horizontal).clamp(
                      480.0,
                      3200.0,
                    );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: navWidth,
                      child: _ConfigNavPanel(
                        section: configCubit.state.section,
                        onSelectSection: (s) {
                          context.read<ConfigCubit>().selectSection(s);
                          context.go('/config/${s.name}');
                        },
                        l10n: l10n,
                      ),
                    ),
                    Container(
                      width: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                    Expanded(
                      child: Padding(
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
                              ConfigSection.llm => const LlmConfigWorkspace(),
                              ConfigSection.session =>
                                const SessionConfigWorkspace(),
                            },
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
                  selected: preferences.toolPlacement,
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
                  selected: preferences.toolsArrangement,
                  onChanged: controller.setToolsArrangement,
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
                  selected: normalizeThemeColorPreset(
                    preferences.themeColorPreset,
                  ),
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
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final id in kThemeColorPresetIds)
            _ThemeColorPresetChip(
              id: id,
              label: l10n.themeColorPresetName(id),
              selected: id == selected,
              onTap: () => onSelect(id),
            ),
        ],
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
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
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
      ),
    );
  }
}

class _SettingsTitleBar extends StatelessWidget {
  const _SettingsTitleBar({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 42, 40, 28),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
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
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: tt.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.25,
          ),
        ),
      ],
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(24, 28, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConfigNavItem(
            key: AppKeys.configLlmSectionButton,
            title: l10n.llmConfig,
            icon: Icons.memory_outlined,
            selected: section == ConfigSection.llm,
            onTap: () => onSelectSection(ConfigSection.llm),
          ),
          _ConfigNavItem(
            key: AppKeys.configLayoutSectionButton,
            title: l10n.layout,
            icon: Icons.dashboard_customize_outlined,
            selected: section == ConfigSection.layout,
            onTap: () => onSelectSection(ConfigSection.layout),
          ),
          _ConfigNavItem(
            key: AppKeys.configSessionSectionButton,
            title: l10n.session,
            icon: Icons.terminal_outlined,
            selected: section == ConfigSection.session,
            onTap: () => onSelectSection(ConfigSection.session),
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
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final muted = textBase.withValues(alpha: 0.64);
    final selectedColor = cs.primaryContainer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? selectedColor : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Icon(icon, color: selected ? textBase : muted, size: 18),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
