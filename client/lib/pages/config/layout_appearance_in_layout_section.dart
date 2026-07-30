import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

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
                  title: l10n.workspaceEntryModeTitle,
                  subtitle: l10n.workspaceEntryModeDescription,
                  trailing: TpSegmentedPicker<WorkspaceEntryMode>(
                    segments: [
                      TpSegmentedOption<WorkspaceEntryMode>(
                        value: WorkspaceEntryMode.home,
                        label: l10n.workspaceEntryModeHome,
                        icon: Icons.home_outlined,
                      ),
                      TpSegmentedOption<WorkspaceEntryMode>(
                        value: WorkspaceEntryMode.lastWorkspace,
                        label: l10n.workspaceEntryModeLastWorkspace,
                        icon: Icons.history,
                      ),
                    ],
                    selected: workspaceEntryMode,
                    onChanged: controller.setWorkspaceEntryMode,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.themeModeTitle,
                  subtitle: l10n.themeModeDescription,
                  trailing: TpSegmentedPicker<String>(
                    segments: [
                      TpSegmentedOption<String>(
                        value: 'light',
                        label: l10n.themeLight,
                        icon: Icons.light_mode_outlined,
                      ),
                      TpSegmentedOption<String>(
                        value: 'dark',
                        label: l10n.themeDark,
                        icon: Icons.dark_mode_outlined,
                      ),
                      TpSegmentedOption<String>(
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
                TpPreferenceRow(
                  title: l10n.themeColorPresetTitle,
                  subtitle: l10n.themeColorPresetDescription,
                  trailing: ThemeColorPresetPicker(
                    selected: colorPreset,
                    onSelect: controller.setThemeColorPreset,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.typographyScaleTitle,
                  subtitle: l10n.typographyScaleDescription,
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
                  title: l10n.fontUiTitle,
                  subtitle: l10n.fontUiDescription,
                  trailing: FontPreferenceSetting(
                    role: FontRole.ui,
                    value: uiFontId,
                    onChanged: controller.setUiFontId,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.fontMonoTitle,
                  subtitle: l10n.fontMonoDescription,
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
                      (
                        MarkdownOpenMode.preview,
                        l10n.markdownOpenModePreview,
                      ),
                      (
                        MarkdownOpenMode.source,
                        l10n.markdownOpenModeSource,
                      ),
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
                  title: l10n.filePreviewHostTitle,
                  subtitle: l10n.filePreviewHostDescription,
                  trailing: TpSegmentedPicker<FilePreviewHost>(
                    segments: [
                      TpSegmentedOption<FilePreviewHost>(
                        value: FilePreviewHost.floating,
                        label: l10n.filePreviewHostFloating,
                        icon: Icons.dashboard_customize_outlined,
                      ),
                      TpSegmentedOption<FilePreviewHost>(
                        value: FilePreviewHost.center,
                        label: l10n.filePreviewHostCenter,
                        icon: Icons.vertical_split_outlined,
                      ),
                    ],
                    selected: context.select<LayoutCubit, FilePreviewHost>(
                      (c) => c.state.preferences.filePreviewHost,
                    ),
                    onChanged: controller.setFilePreviewHost,
                  ),
                  showDividerBelow: true,
                ),
                TpSectionHeader(title: l10n.thinkingProcessSectionTitle),
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
                  title: '终端主题',
                  subtitle: '跟随主题色或使用固定风格',
                  trailing: TpCompactSelect<String>(
                    value: terminalThemeMode,
                    entries: const [
                      ('adaptive', '跟随主题'),
                      ('classicDark', '经典暗色'),
                      ('highContrast', '高对比'),
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
