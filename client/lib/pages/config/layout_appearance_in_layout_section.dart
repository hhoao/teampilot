import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:tp_markdown/tp_markdown.dart' show ContentDisplayMode;

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography_scale.dart';
import '../../theme/font_catalog.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/settings/font_preference_setting.dart';
import '../../widgets/settings/theme_color_preset_picker.dart';
import '../../widgets/settings/typography_scale_setting.dart';

class LayoutAppearanceInLayoutSection extends StatelessWidget {
  const LayoutAppearanceInLayoutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<LayoutCubit>();

    return BlocSelector<
      LayoutCubit,
      LayoutState,
      (
        String,
        String,
        String,
        double,
        String,
        String,
        String,
        double,
        String,
        String,
      )
    >(
      selector: (state) {
        var themeMode = state.preferences.themeMode;
        if (themeMode != 'light' &&
            themeMode != 'dark' &&
            themeMode != 'system') {
          themeMode = 'system';
        }
        return (
          themeMode,
          normalizeThemeColorPreset(state.preferences.themeColorPreset),
          normalizeTypographyScale(state.preferences.typographyScale),
          state.preferences.typographyScaleCustomMultiplier,
          normalizeUiFontId(state.preferences.uiFontId),
          normalizeMonoFontId(state.preferences.monoFontId),
          normalizeTypographyScale(state.preferences.uiZoomScale),
          state.preferences.uiZoomCustomMultiplier,
          state.preferences.terminalThemeMode,
          languagePreferenceUiValue(state.preferences.locale),
        );
      },
      builder: (context, appearance) {
        final (
          themeMode,
          colorPreset,
          typographyScale,
          typographyCustomMultiplier,
          uiFontId,
          monoFontId,
          uiZoomScale,
          uiZoomCustomMultiplier,
          terminalThemeMode,
          langValue,
        ) = appearance;
        return BlocSelector<LayoutCubit, LayoutState, WorkspaceEntryMode>(
          selector: (state) => state.preferences.workspaceEntryMode,
          builder: (context, workspaceEntryMode) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TpSectionHeader(title: l10n.appearance),
                TpPreferenceRow(
                  title: l10n.workspace.entryModeTitle,
                  subtitle: l10n.workspace.entryModeDescription,
                  trailing: TpSegmentedPicker<WorkspaceEntryMode>(
                    segments: [
                      TpSegmentedOption<WorkspaceEntryMode>(
                        value: WorkspaceEntryMode.home,
                        label: l10n.workspace.entryModeHome,
                        icon: Icons.home_outlined,
                      ),
                      TpSegmentedOption<WorkspaceEntryMode>(
                        value: WorkspaceEntryMode.lastWorkspace,
                        label: l10n.workspace.entryModeLastWorkspace,
                        icon: Icons.history,
                      ),
                    ],
                    selected: workspaceEntryMode,
                    onChanged: controller.setWorkspaceEntryMode,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.theme.modeTitle,
                  subtitle: l10n.theme.modeDescription,
                  trailing: TpSegmentedPicker<String>(
                    segments: [
                      TpSegmentedOption<String>(
                        value: 'light',
                        label: l10n.theme.light,
                        icon: Icons.light_mode_outlined,
                      ),
                      TpSegmentedOption<String>(
                        value: 'dark',
                        label: l10n.theme.dark,
                        icon: Icons.dark_mode_outlined,
                      ),
                      TpSegmentedOption<String>(
                        value: 'system',
                        label: l10n.theme.system,
                        icon: Icons.desktop_windows_outlined,
                      ),
                    ],
                    selected: themeMode,
                    onChanged: controller.setThemeMode,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.theme.colorPresetTitle,
                  subtitle: l10n.theme.colorPresetDescription,
                  trailing: ThemeColorPresetPicker(
                    selected: colorPreset,
                    onSelect: controller.setThemeColorPreset,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.typography.scaleTitle,
                  subtitle: l10n.typography.scaleDescription,
                  trailing: TypographyScaleSetting(
                    scaleId: typographyScale,
                    customMultiplier: typographyCustomMultiplier,
                    onScaleIdChanged: controller.setTypographyScale,
                    onCustomMultiplierChanged:
                        controller.setTypographyScaleCustom,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.font.uiTitle,
                  subtitle: l10n.font.uiDescription,
                  trailing: FontPreferenceSetting(
                    role: FontRole.ui,
                    value: uiFontId,
                    onChanged: controller.setUiFontId,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.font.monoTitle,
                  subtitle: l10n.font.monoDescription,
                  trailing: FontPreferenceSetting(
                    role: FontRole.mono,
                    value: monoFontId,
                    onChanged: controller.setMonoFontId,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.uiZoomTitle,
                  subtitle: l10n.uiZoomDescription,
                  trailing: TypographyScaleSetting(
                    scaleId: uiZoomScale,
                    customMultiplier: uiZoomCustomMultiplier,
                    onScaleIdChanged: controller.setUiZoomScale,
                    onCustomMultiplierChanged: controller.setUiZoomCustom,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.markdownOpenModeTitle,
                  subtitle: l10n.markdownOpenModeDescription,
                  trailing: TpCompactSelect<MarkdownOpenMode>(
                    value: context.select<LayoutCubit, MarkdownOpenMode>(
                      (c) => c.state.preferences.markdownOpenMode,
                    ),
                    entries: [
                      (MarkdownOpenMode.preview, l10n.markdownOpenModePreview),
                      (MarkdownOpenMode.source, l10n.markdownOpenModeSource),
                      (
                        MarkdownOpenMode.remember,
                        l10n.markdownOpenModeRemember,
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) controller.setMarkdownOpenMode(v);
                    },
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.file.previewHostTitle,
                  subtitle: l10n.file.previewHostDescription,
                  trailing: TpSegmentedPicker<FilePreviewHost>(
                    segments: [
                      TpSegmentedOption<FilePreviewHost>(
                        value: FilePreviewHost.floating,
                        label: l10n.file.previewHostFloating,
                        icon: Icons.dashboard_customize_outlined,
                      ),
                      TpSegmentedOption<FilePreviewHost>(
                        value: FilePreviewHost.center,
                        label: l10n.file.previewHostCenter,
                        icon: Icons.vertical_split_outlined,
                      ),
                    ],
                    selected: context.select<LayoutCubit, FilePreviewHost>(
                      (c) => c.state.preferences.filePreviewHost,
                    ),
                    onChanged: (host) {
                      // Tab relocation on host switch was dropped with the
                      // migrate-file deletion: existing file/diff previews stay
                      // where they are (bar presence wins), new opens follow
                      // the new host. See workbench-tab-bar-unification report.
                      controller.setFilePreviewHost(host);
                    },
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.floating.previewTabsTitle,
                  subtitle: l10n.floating.previewTabsDescription,
                  trailing: Switch(
                    value: context.select<LayoutCubit, bool>(
                      (c) => c.state.preferences.floatingPreviewTabs,
                    ),
                    onChanged: controller.setFloatingPreviewTabs,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.floating.restoreTerminalSessionsTitle,
                  subtitle: l10n.floating.restoreTerminalSessionsDescription,
                  trailing: Switch(
                    value: context.select<LayoutCubit, bool>(
                      (c) => c.state.preferences.restoreTerminalSessions,
                    ),
                    onChanged: controller.setRestoreTerminalSessions,
                  ),
                  showDividerBelow: true,
                ),
                TpSectionHeader(title: l10n.thinkingProcessSectionTitle),
                TpPreferenceRow(
                  title: l10n.cotExpandLatestOnOpenTitle,
                  subtitle: l10n.cotExpandLatestOnOpenDescription,
                  trailing: Switch(
                    value: context.select<LayoutCubit, bool>(
                      (c) => c.state.preferences.cotExpandLatestOnOpen,
                    ),
                    onChanged: controller.setCotExpandLatestOnOpen,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.cotExpandReasoningOnOpenTitle,
                  subtitle: l10n.cotExpandReasoningOnOpenDescription,
                  trailing: Switch(
                    value: context.select<LayoutCubit, bool>(
                      (c) => c.state.preferences.cotExpandReasoningOnOpen,
                    ),
                    onChanged: controller.setCotExpandReasoningOnOpen,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.cotExpandToolsOnOpenTitle,
                  subtitle: l10n.cotExpandToolsOnOpenDescription,
                  trailing: Switch(
                    value: context.select<LayoutCubit, bool>(
                      (c) => c.state.preferences.cotExpandToolsOnOpen,
                    ),
                    onChanged: controller.setCotExpandToolsOnOpen,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.autoOpenSubagentPreviewTitle,
                  subtitle: l10n.autoOpenSubagentPreviewDescription,
                  trailing: Switch(
                    value: context.select<LayoutCubit, bool>(
                      (c) => c.state.preferences.autoOpenSubagentPreview,
                    ),
                    onChanged: controller.setAutoOpenSubagentPreview,
                  ),
                  showDividerBelow: true,
                ),
                TpSectionHeader(title: l10n.thinkingProcessFoldSectionTitle),
                for (final category in AiToolCallCategory.values) ...[
                  TpPreferenceRow(
                    title: _foldCategoryTitle(l10n, category),
                    trailing: Switch(
                      value: context.select<LayoutCubit, bool>(
                        (c) => c.state.preferences.foldToolCallCategories
                            .contains(category),
                      ),
                      onChanged: (value) => controller.setFoldToolCallCategory(
                        category,
                        fold: value,
                      ),
                    ),
                    showDividerBelow: true,
                  ),
                ],
                TpSectionHeader(title: l10n.contentDisplayModeSectionTitle),
                TpPreferenceRow(
                  title: l10n.chat.userMessageModeTitle,
                  subtitle: l10n.chat.userMessageModeDescription,
                  trailing: TpCompactSelect<ContentDisplayMode>(
                    value: context.select<LayoutCubit, ContentDisplayMode>(
                      (c) => c.state.preferences.chatUserMessageMode,
                    ),
                    entries: [
                      (
                        ContentDisplayMode.foldFixedHeight,
                        l10n.contentDisplayModeFoldFixedHeight,
                      ),
                      (
                        ContentDisplayMode.foldExpandFull,
                        l10n.contentDisplayModeFoldExpandFull,
                      ),
                      (
                        ContentDisplayMode.flatten,
                        l10n.contentDisplayModeFlatten,
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) controller.setChatUserMessageMode(v);
                    },
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.chat.codeBlockModeTitle,
                  subtitle: l10n.chat.codeBlockModeDescription,
                  trailing: TpCompactSelect<ContentDisplayMode>(
                    value: context.select<LayoutCubit, ContentDisplayMode>(
                      (c) => c.state.preferences.chatCodeBlockMode,
                    ),
                    entries: [
                      (
                        ContentDisplayMode.foldFixedHeight,
                        l10n.contentDisplayModeFoldFixedHeight,
                      ),
                      (
                        ContentDisplayMode.foldExpandFull,
                        l10n.contentDisplayModeFoldExpandFull,
                      ),
                      (
                        ContentDisplayMode.flatten,
                        l10n.contentDisplayModeFlatten,
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) controller.setChatCodeBlockMode(v);
                    },
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.file.codeBlockModeTitle,
                  subtitle: l10n.file.codeBlockModeDescription,
                  trailing: TpCompactSelect<ContentDisplayMode>(
                    value: context.select<LayoutCubit, ContentDisplayMode>(
                      (c) => c.state.preferences.fileCodeBlockMode,
                    ),
                    entries: [
                      (
                        ContentDisplayMode.foldFixedHeight,
                        l10n.contentDisplayModeFoldFixedHeight,
                      ),
                      (
                        ContentDisplayMode.foldExpandFull,
                        l10n.contentDisplayModeFoldExpandFull,
                      ),
                      (
                        ContentDisplayMode.flatten,
                        l10n.contentDisplayModeFlatten,
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) controller.setFileCodeBlockMode(v);
                    },
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.terminal.themeModeTitle,
                  subtitle: l10n.terminal.themeModeDescription,
                  trailing: TpCompactSelect<String>(
                    value: terminalThemeMode,
                    entries: [
                      ('adaptive', l10n.workspace.terminalThemeAdaptive),
                      ('classicDark', l10n.workspace.terminalThemeClassicDark),
                      (
                        'highContrast',
                        l10n.workspace.terminalThemeHighContrast,
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) controller.setTerminalThemeMode(v);
                    },
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.language,
                  subtitle: l10n.languageDescription,
                  trailing: TpCompactSelect<String>(
                    value: langValue,
                    entries: [
                      ('system', l10n.languageSystem),
                      ('en', l10n.languageEnglish),
                      ('zh', l10n.languageChinese),
                    ],
                    itemKeys: const {
                      'system': AppKeys.languageSystemButton,
                      'en': AppKeys.languageEnButton,
                      'zh': AppKeys.languageZhButton,
                    },
                    onChanged: (v) {
                      if (v != null) {
                        controller.setLocale(languagePreferenceStoredLocale(v));
                      }
                    },
                  ),
                  showDividerBelow: false,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

String _foldCategoryTitle(AppLocalizations l10n, AiToolCallCategory c) =>
    switch (c) {
      AiToolCallCategory.read => l10n.tool.categoryRead,
      AiToolCallCategory.write => l10n.tool.categoryWrite,
      AiToolCallCategory.edit => l10n.tool.categoryEdit,
      AiToolCallCategory.command => l10n.tool.categoryCommand,
      AiToolCallCategory.search => l10n.tool.categorySearch,
      AiToolCallCategory.browser => l10n.tool.categoryBrowser,
      AiToolCallCategory.subagent => l10n.tool.categorySubagent,
      AiToolCallCategory.askUser => l10n.tool.categoryAskUser,
      AiToolCallCategory.plan => l10n.tool.categoryPlan,
      AiToolCallCategory.task => l10n.tool.categoryTask,
      AiToolCallCategory.mcp => l10n.tool.categoryMcp,
      AiToolCallCategory.other => l10n.tool.categoryOther,
    };
