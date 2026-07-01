import 'package:flutter/material.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../pages/team_config/team_config_helpers.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../theme/app_text_styles.dart';
import '../dropdown/app_dropdown_decoration.dart';
import '../dropdown/app_dropdown_field.dart';
import '../settings/workspace_settings_widgets.dart';
import 'cli_launch_config_dropdown.dart';
import 'member_launch_config_kind.dart';
import 'preset_launch_picker_field.dart';

/// Configuration type row: inherit team / preset / custom.
class MemberLaunchConfigTypeField extends StatelessWidget {
  const MemberLaunchConfigTypeField({
    required this.currentKind,
    required this.onChanged,
    this.decoration,
    this.showDividerBelow = false,
    super.key,
  });

  final MemberLaunchConfigKind currentKind;
  final ValueChanged<MemberLaunchConfigKind> onChanged;
  final AppDropdownDecoration? decoration;
  final bool showDividerBelow;

  static const _items = MemberLaunchConfigKind.values;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dropdownDeco = decoration ?? AppDropdownDecorations.themed(context);

    return SettingsLabeledRow(
      title: l10n.memberLaunchConfigTypeLabel,
      trailing: cliLaunchConfigDropdown(
        AppDropdownField<MemberLaunchConfigKind>(
          items: _items,
          initialItem: currentKind,
          hintText: l10n.memberLaunchConfigTypeLabel,
          decoration: dropdownDeco,
          itemLabel: (kind) => _kindLabel(l10n, kind),
          onChanged: (value) {
            if (value == null) return;
            onChanged(value);
          },
        ),
      ),
      showDividerBelow: showDividerBelow,
    );
  }

  static String _kindLabel(AppLocalizations l10n, MemberLaunchConfigKind kind) {
    return switch (kind) {
      MemberLaunchConfigKind.inheritTeam => l10n.memberPresetInheritTeam,
      MemberLaunchConfigKind.preset => l10n.memberLaunchConfigTypePreset,
      MemberLaunchConfigKind.custom => l10n.memberPresetCustom,
    };
  }
}

/// Read-only summary of what the team default resolves to when inheriting.
class MemberLaunchInheritSummary extends StatelessWidget {
  const MemberLaunchInheritSummary({
    required this.team,
    required this.presets,
    required this.registry,
    required this.providerState,
    super.key,
  });

  final TeamProfile team;
  final List<CliPreset> presets;
  final CliToolRegistry registry;
  final AppProviderState providerState;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final bundle = resolveTeamLaunchBundle(team: team, globalPresets: presets);
    final subtitle = bundle.isConfigured
        ? _bundleSummary(
            l10n: l10n,
            registry: registry,
            bundle: bundle,
            providerState: providerState,
          )
        : l10n.memberLaunchConfigInheritUnset;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: styles.bodySmall.copyWith(
              color: bundle.isConfigured ? cs.onSurface : cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  static String _bundleSummary({
    required AppLocalizations l10n,
    required CliToolRegistry registry,
    required TeamLaunchBundle bundle,
    required AppProviderState providerState,
  }) {
    if (bundle.sourcePreset != null) {
      final preset = bundle.sourcePreset!;
      final provider = providerConfigForPreset(
        providers: providerState.providersFor(preset.cli),
        preset: preset,
      );
      return presetPickerSubtitle(
        registry: registry,
        l10n: l10n,
        preset: preset,
        provider: provider,
      );
    }

    final def = registry.tryGet(bundle.cli);
    final cliName = def != null ? cliDisplayName(def, l10n) : bundle.cli.value;
    AppProviderConfig? provider;
    for (final p in providerState.providersFor(bundle.cli)) {
      if (p.id == bundle.provider.trim()) {
        provider = p;
        break;
      }
    }
    final providerName = provider?.name.trim().isNotEmpty == true
        ? provider!.name.trim()
        : bundle.provider.trim();
    final parts = <String>[
      if (providerName.isNotEmpty) providerName,
      if (bundle.model.trim().isNotEmpty) bundle.model.trim(),
      if (bundle.effort.trim().isNotEmpty) bundle.effort.trim(),
    ];
    if (parts.isEmpty) return cliName;
    return '$cliName · ${parts.join(' · ')}';
  }
}

/// Preset picker shown when configuration type is [MemberLaunchConfigKind.preset].
class MemberLaunchPresetField extends StatelessWidget {
  const MemberLaunchPresetField({
    required this.items,
    required this.currentToken,
    required this.eligiblePresets,
    required this.registry,
    required this.providerState,
    required this.onChanged,
    this.decoration,
    super.key,
  });

  final List<String> items;
  final String currentToken;
  final List<CliPreset> eligiblePresets;
  final CliToolRegistry registry;
  final AppProviderState providerState;
  final ValueChanged<String> onChanged;
  final AppDropdownDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    return PresetLaunchPickerField(
      mode: PresetLaunchPickerMode.presetOnly,
      items: items,
      currentToken: currentToken,
      eligiblePresets: eligiblePresets,
      registry: registry,
      providerState: providerState,
      decoration: decoration,
      onChanged: onChanged,
    );
  }
}

String memberLaunchPresetToken(TeamMemberConfig member) {
  if (member.hasExplicitPreset) return member.activePresetId!;
  return '';
}
