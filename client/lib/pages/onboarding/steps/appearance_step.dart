import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/layout_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_keys.dart';
import '../../../widgets/settings/workspace_settings_toggle_strip.dart';
import '../../../widgets/settings/workspace_settings_widgets.dart';

class OnboardingAppearanceStep extends StatelessWidget {
  const OnboardingAppearanceStep({super.key});

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
            Text(l10n.onboardingAppearanceTitle, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              l10n.onboardingAppearanceSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            SettingsSurfaceCard(
              child: Column(
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
                    trailing: _OnboardingThemeColorPresetPicker(
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
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OnboardingThemeColorPresetPicker extends StatelessWidget {
  const _OnboardingThemeColorPresetPicker({
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
                child: ActionChip(
                  label: Text(l10n.themeColorPresetName(id)),
                  onPressed: () => onSelect(id),
                  backgroundColor: id == selected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
