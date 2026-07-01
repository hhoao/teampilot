import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/capabilities/cli_effort_capability.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../pages/home_workspace/workspace/config/workspace_cli_config_helpers.dart';
import '../../pages/home_workspace/workspace/config/workspace_cli_effort_helpers.dart';
import '../../pages/team_config/team_config_helpers.dart';
import '../../widgets/app_provider/brand_dropdown_rows.dart';
import '../../widgets/app_provider/cli_effort_picker_field.dart';
import '../../widgets/app_provider/provider_model_picker_field.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'cli_launch_config_dropdown.dart';

/// How the effort picker resolves visibility and labels.
enum CliLaunchEffortContext { team, member, standalone }

/// CLI row variants for launch configure dialogs.
enum CliLaunchCliFieldKind { hidden, toolList, mixedTeam, mixedMember }

/// Provider / model / effort fields shared by launch configure dialogs.
class CliLaunchCustomFields extends StatelessWidget {
  const CliLaunchCustomFields({
    required this.catalogCli,
    required this.providers,
    required this.providerId,
    required this.modelId,
    required this.effortId,
    required this.registry,
    required this.onProviderChanged,
    required this.onModelChanged,
    required this.onEffortChanged,
    this.cliFieldKind = CliLaunchCliFieldKind.hidden,
    this.cliItems = const [],
    this.mixedMemberCliItems = const [],
    this.cliToken,
    this.onCliChanged,
    this.onMixedCliTokenChanged,
    this.cliSubtitle,
    this.team,
    this.member,
    this.effortContext = CliLaunchEffortContext.standalone,
    this.effortSubtitle,
    this.effortAllowInherit = false,
    this.effortInheritLabel,
    this.providerTitle,
    this.modelTitle,
    this.effortTitle,
    this.dropdownKeyPrefix = 'cli-launch',
    this.decoration,
    super.key,
  });

  final CliTool catalogCli;
  final List<AppProviderConfig> providers;
  final String providerId;
  final String modelId;
  final String effortId;
  final CliToolRegistry registry;
  final ValueChanged<String> onProviderChanged;
  final ValueChanged<String> onModelChanged;
  final ValueChanged<String> onEffortChanged;
  final CliLaunchCliFieldKind cliFieldKind;
  final List<CliTool> cliItems;
  final List<String> mixedMemberCliItems;
  final String? cliToken;
  final ValueChanged<CliTool>? onCliChanged;
  final ValueChanged<String>? onMixedCliTokenChanged;
  final String? cliSubtitle;
  final TeamProfile? team;
  final TeamMemberConfig? member;
  final CliLaunchEffortContext effortContext;
  final String? effortSubtitle;
  final bool effortAllowInherit;
  final String? effortInheritLabel;
  final String? providerTitle;
  final String? modelTitle;
  final String? effortTitle;
  final String dropdownKeyPrefix;
  final AppDropdownDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dropdownDeco = decoration ?? AppDropdownDecorations.themed(context);
    final providerIds = providers.map((p) => p.id).toList()..sort();
    if (providerId.isNotEmpty && !providerIds.contains(providerId)) {
      providerIds.add(providerId);
    }
    final providerLabels = {
      for (final provider in providers) provider.id: provider.name,
      if (providerId.isNotEmpty && !providers.any((p) => p.id == providerId))
        providerId: providerId,
    };
    final selectedProvider = _selectedProvider(providers, providerId);
    final hideModelPicker = workspaceCliHidesModelPicker(
      registry,
      catalogCli,
      selectedProvider,
    );
    final showEffortPicker = _showsEffortPicker(context, selectedProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cliFieldKind != CliLaunchCliFieldKind.hidden)
          _buildCliRow(context, l10n, dropdownDeco),
        if (providers.isEmpty)
          SettingsLabeledRow(
            title: providerTitle ?? l10n.provider,
            trailing: Text(
              l10n.onboardingDefaultPresetEmpty,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            showDividerBelow: false,
          )
        else ...[
          SettingsLabeledRow(
            title: providerTitle ?? l10n.provider,
            trailing: cliLaunchConfigDropdown(
              AppDropdownField<String>(
                key: ValueKey(
                  '$dropdownKeyPrefix-provider-$catalogCli-$providerId',
                ),
                items: providerIds,
                initialItem: providerId.isEmpty ? null : providerId,
                hintText: l10n.selectProvider,
                decoration: dropdownDeco,
                onChanged: (value) {
                  if (value == null || value.isEmpty) return;
                  onProviderChanged(value);
                },
                itemBuilder: providerDropdownItemBuilder(
                  providers: providers,
                  labelFor: (value) => providerLabels[value] ?? value,
                ),
              ),
            ),
            showDividerBelow: !hideModelPicker || showEffortPicker,
          ),
          if (!hideModelPicker)
            SettingsLabeledRow(
              title: modelTitle ?? l10n.model,
              trailing: cliLaunchConfigDropdown(
                ProviderModelPickerField(
                  key: ValueKey(
                    '$dropdownKeyPrefix-model-$providerId-$modelId',
                  ),
                  cli: catalogCli,
                  providerId: providerId,
                  provider: selectedProvider,
                  value: modelId,
                  hintText: l10n.selectModel,
                  decoration: dropdownDeco,
                  onChanged: onModelChanged,
                ),
              ),
              showDividerBelow: showEffortPicker,
            ),
          if (showEffortPicker)
            SettingsLabeledRow(
              title: effortTitle ?? l10n.teamEffortLevel,
              subtitle: effortSubtitle,
              trailing: cliLaunchConfigDropdown(
                CliEffortPickerField(
                  key: ValueKey(
                    '$dropdownKeyPrefix-effort-$providerId-$modelId-$effortId',
                  ),
                  cli: catalogCli,
                  value: effortId,
                  team: team,
                  member: member,
                  provider: selectedProvider,
                  model: modelId,
                  allowInherit: effortAllowInherit,
                  inheritLabel: effortInheritLabel,
                  decoration: dropdownDeco,
                  onChanged: onEffortChanged,
                ),
              ),
              showDividerBelow: false,
            ),
        ],
      ],
    );
  }

  Widget _buildCliRow(
    BuildContext context,
    AppLocalizations l10n,
    AppDropdownDecoration dropdownDeco,
  ) {
    return switch (cliFieldKind) {
      CliLaunchCliFieldKind.toolList => SettingsLabeledRow(
        title: l10n.aiFeatureCliLabel,
        trailing: cliLaunchConfigDropdown(
          AppDropdownField<CliTool>(
            items: cliItems,
            initialItem: catalogCli,
            decoration: dropdownDeco,
            itemLabel: (cli) {
              final def = registry.tryGet(cli);
              return def == null ? cli.value : cliDisplayName(def, l10n);
            },
            onChanged: (cli) {
              if (cli == null || cli == catalogCli) return;
              onCliChanged?.call(cli);
            },
          ),
        ),
        showDividerBelow: providers.isNotEmpty,
      ),
      CliLaunchCliFieldKind.mixedTeam => SettingsLabeledRow(
        title: l10n.teamCliLabel,
        subtitle: cliSubtitle,
        trailing: cliLaunchConfigDropdown(
          AppDropdownField<CliTool>(
            items: cliItems,
            initialItem: catalogCli,
            decoration: dropdownDeco,
            itemLabel: (cli) {
              final def = registry.tryGet(cli);
              return def == null ? cli.value : cliDisplayName(def, l10n);
            },
            onChanged: (value) {
              if (value == null || value == catalogCli) return;
              onCliChanged?.call(value);
            },
            itemBuilder: (ctx, cli) {
              final def = registry.tryGet(cli);
              return cliDropdownRow(
                ctx,
                cli: cli,
                label: def == null ? cli.value : cliDisplayName(def, l10n),
                registry: registry,
              );
            },
          ),
        ),
        showDividerBelow: true,
      ),
      CliLaunchCliFieldKind.mixedMember => SettingsLabeledRow(
        title: l10n.teamCliLabel,
        trailing: cliLaunchConfigDropdown(
          AppDropdownField<String>(
            items: mixedMemberCliItems,
            initialItem: cliToken,
            decoration: dropdownDeco,
            itemLabel: (value) {
              final def = registry.tryGet(CliTool.decode(value));
              return def == null ? value : cliDisplayName(def, l10n);
            },
            onChanged: (value) {
              if (value == null || value == cliToken) return;
              onMixedCliTokenChanged?.call(value);
            },
            itemBuilder: (ctx, value) {
              final cli = CliTool.decode(value);
              final def = registry.tryGet(cli);
              return cliDropdownRow(
                ctx,
                cli: cli,
                label: def == null ? value : cliDisplayName(def, l10n),
                registry: registry,
              );
            },
          ),
        ),
        showDividerBelow: true,
      ),
      CliLaunchCliFieldKind.hidden => const SizedBox.shrink(),
    };
  }

  bool _showsEffortPicker(BuildContext context, AppProviderConfig? provider) {
    return switch (effortContext) {
      CliLaunchEffortContext.team => teamShowsEffortPicker(
        context,
        cli: catalogCli,
        placement: EffortPickerPlacement.team,
        model: modelId,
      ),
      CliLaunchEffortContext.member => teamShowsEffortPicker(
        context,
        cli: catalogCli,
        placement: EffortPickerPlacement.member,
        model: modelId,
      ),
      CliLaunchEffortContext.standalone => workspaceCliShowsEffortPicker(
        registry: registry,
        cli: catalogCli,
        provider: provider,
        model: modelId,
      ),
    };
  }

  AppProviderConfig? _selectedProvider(
    Iterable<AppProviderConfig> providers,
    String id,
  ) {
    for (final provider in providers) {
      if (provider.id == id) return provider;
    }
    return null;
  }
}
