import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography_scale.dart';
import '../../utils/app_keys.dart';
import '../../widgets/settings/typography_scale_setting.dart';
import '../../widgets/settings/workspace_settings_toggle_strip.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';

class LayoutAppearanceInLayoutSection extends StatelessWidget {
  const LayoutAppearanceInLayoutSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<LayoutCubit>();

    return BlocSelector<
      LayoutCubit,
      LayoutState,
      (String, String, String, double, String, String)
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
          terminalThemeMode,
          langValue,
        ) = appearance;
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
              trailing: LayoutThemeColorPresetPicker(
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
  }
}

class LayoutThemeColorPresetPicker extends StatelessWidget {
  const LayoutThemeColorPresetPicker({
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
                child: LayoutThemeColorPresetChip(
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

class LayoutThemeColorPresetChip extends StatelessWidget {
  const LayoutThemeColorPresetChip({
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
                style: AppTextStyles.of(context).bodySmall.copyWith(
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
