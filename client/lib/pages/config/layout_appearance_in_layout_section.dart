import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography_scale.dart';
import '../../utils/app_keys.dart';
import '../../widgets/settings/theme_color_preset_picker.dart';
import '../../widgets/settings/typography_scale_setting.dart';
import '../../widgets/settings/workspace_settings_toggle_strip.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';

class LayoutAppearanceInLayoutSection extends StatelessWidget {
  const LayoutAppearanceInLayoutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<LayoutCubit>();

    return BlocSelector<
      LayoutCubit,
      LayoutState,
      (String, String, String, double, String, double, String, String)
    >(
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
          normalizeTypographyScale(state.preferences.typographyScale),
          state.preferences.typographyScaleCustomMultiplier,
          normalizeTypographyScale(state.preferences.uiZoomScale),
          state.preferences.uiZoomCustomMultiplier,
          state.preferences.terminalThemeMode,
          langValue,
        );
      },
      builder: (context, appearance) {
        final (
          themeMode,
          colorPreset,
          typographyScale,
          typographyCustomMultiplier,
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
                SettingsGroupHeader(title: l10n.appearance),
                SettingsLabeledRow(
                  title: l10n.workspaceEntryModeTitle,
                  subtitle: l10n.workspaceEntryModeDescription,
                  trailing: WorkspaceSettingsToggleStrip<WorkspaceEntryMode>(
                    segments: [
                      WorkspaceToggleSegment<WorkspaceEntryMode>(
                        value: WorkspaceEntryMode.home,
                        label: l10n.workspaceEntryModeHome,
                        icon: Icons.home_outlined,
                      ),
                      WorkspaceToggleSegment<WorkspaceEntryMode>(
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
              trailing: ThemeColorPresetPicker(
                selected: colorPreset,
                onSelect: controller.setThemeColorPreset,
              ),
              showDividerBelow: true,
            ),
            SettingsLabeledRow(
              title: l10n.typographyScaleTitle,
              subtitle: l10n.typographyScaleDescription,
              trailing: TypographyScaleSetting(
                scaleId: typographyScale,
                customMultiplier: typographyCustomMultiplier,
                onScaleIdChanged: controller.setTypographyScale,
                onCustomMultiplierChanged: controller.setTypographyScaleCustom,
              ),
              showDividerBelow: true,
            ),
            SettingsLabeledRow(
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
            SettingsLabeledRow(
              title: '终端主题',
              subtitle: '跟随主题色或使用固定风格',
              trailing: SettingsCompactDropdown<String>(
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
      },
    );
  }
}
