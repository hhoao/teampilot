import 'package:flutter/material.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/cli_preset.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../pages/team_config/team_config_helpers.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'cli_launch_config_dropdown.dart';
import 'cli_launch_config_tokens.dart';

enum PresetLaunchPickerMode {
  /// Presets + custom (team default, AI features).
  customOnly,

  /// Inherit team + presets + custom (member).
  inheritAndCustom,
}

/// Preset row shared by team / member / AI-feature launch configure dialogs.
class PresetLaunchPickerField extends StatelessWidget {
  const PresetLaunchPickerField({
    required this.mode,
    required this.items,
    required this.currentToken,
    required this.eligiblePresets,
    required this.registry,
    required this.providerState,
    required this.onChanged,
    this.teamPresetName,
    this.decoration,
    super.key,
  });

  final PresetLaunchPickerMode mode;
  final List<String> items;
  final String currentToken;
  final List<CliPreset> eligiblePresets;
  final CliToolRegistry registry;
  final AppProviderState providerState;
  final ValueChanged<String> onChanged;
  final String? teamPresetName;
  final AppDropdownDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dropdownDeco =
        decoration ?? AppDropdownDecorations.themed(context);

    return SettingsLabeledRow(
      title: l10n.memberPresetLabel,
      trailing: cliLaunchConfigDropdown(
        AppDropdownField<String>(
          items: items,
          initialItem: currentToken,
          hintText: l10n.memberPresetSelectPreset,
          decoration: dropdownDeco,
          itemLabel: (value) => presetLaunchPickerLabel(
            value,
            l10n: l10n,
            eligiblePresets: eligiblePresets,
            mode: mode,
          ),
          listItemBuilder: (ctx, value) => presetLaunchPickerListItem(
            ctx,
            value: value,
            eligiblePresets: eligiblePresets,
            l10n: l10n,
            registry: registry,
            providerState: providerState,
            mode: mode,
            teamPresetName: teamPresetName,
          ),
          onChanged: (value) {
            if (value == null) return;
            onChanged(value);
          },
        ),
      ),
      showDividerBelow: true,
    );
  }
}

String presetLaunchPickerLabel(
  String value, {
  required AppLocalizations l10n,
  required List<CliPreset> eligiblePresets,
  required PresetLaunchPickerMode mode,
}) {
  if (mode == PresetLaunchPickerMode.inheritAndCustom &&
      value == CliLaunchConfigTokens.presetInherit) {
    return l10n.memberPresetInheritTeam;
  }
  if (value == CliLaunchConfigTokens.presetCustom) {
    return l10n.memberPresetCustom;
  }
  for (final preset in eligiblePresets) {
    if (preset.id == value) return preset.name;
  }
  return value;
}

Widget presetLaunchPickerListItem(
  BuildContext context, {
  required String value,
  required List<CliPreset> eligiblePresets,
  required AppLocalizations l10n,
  required CliToolRegistry registry,
  required AppProviderState providerState,
  required PresetLaunchPickerMode mode,
  String? teamPresetName,
}) {
  if (mode == PresetLaunchPickerMode.inheritAndCustom &&
      value == CliLaunchConfigTokens.presetInherit) {
    return _PresetDropdownOption(
      title: l10n.memberPresetInheritTeam,
      subtitle: teamPresetName ?? l10n.memberPresetInheritTeamNone,
      enabled: teamPresetName != null,
    );
  }
  if (value == CliLaunchConfigTokens.presetCustom) {
    return _PresetDropdownOption(
      title: l10n.memberPresetCustom,
      enabled: true,
    );
  }
  for (final preset in eligiblePresets) {
    if (preset.id == value) {
      final provider = providerConfigForPreset(
        providers: providerState.providersFor(preset.cli),
        preset: preset,
      );
      final subtitle = presetPickerSubtitle(
        registry: registry,
        l10n: l10n,
        preset: preset,
        provider: provider,
      );
      return _PresetDropdownOption(
        title: preset.name,
        subtitle: subtitle,
        enabled: true,
      );
    }
  }
  return Text(value);
}

class _PresetDropdownOption extends StatelessWidget {
  const _PresetDropdownOption({
    required this.title,
    this.subtitle,
    required this.enabled,
  });

  final String title;
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final alpha = enabled ? 1.0 : 0.38;
    return Opacity(
      opacity: alpha,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(color: cs.onSurface)),
          if (subtitle != null)
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// All global presets sorted by display name (AI features, unscoped pickers).
List<CliPreset> globalPresetPickerItems(List<CliPreset> allPresets) {
  final items = List<CliPreset>.from(allPresets);
  items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return items;
}

List<String> presetLaunchDropdownItems({
  required PresetLaunchPickerMode mode,
  required List<CliPreset> eligiblePresets,
}) {
  return switch (mode) {
    PresetLaunchPickerMode.customOnly => [
      ...eligiblePresets.map((p) => p.id),
      CliLaunchConfigTokens.presetCustom,
    ],
    PresetLaunchPickerMode.inheritAndCustom => [
      CliLaunchConfigTokens.presetInherit,
      ...eligiblePresets.map((p) => p.id),
      CliLaunchConfigTokens.presetCustom,
    ],
  };
}

String? teamPresetDisplayName(String? teamPresetId, List<CliPreset> presets) {
  if (teamPresetId == null) return null;
  for (final preset in presets) {
    if (preset.id == teamPresetId) return preset.name;
  }
  return null;
}
