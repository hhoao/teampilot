import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/app_provider_cubit.dart';
import '../../../cubits/cli_presets_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_provider_config.dart';
import '../../../models/cli_preset.dart';
import '../../../services/app/onboarding_service.dart';
import '../../../services/cli/registry/cli_display_name.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../widgets/app_provider/brand_dropdown_rows.dart';
import '../../../widgets/app_provider/cli_effort_picker_field.dart';
import '../../../widgets/app_provider/provider_model_picker_field.dart';
import '../../../widgets/cli/cli_brand_icon.dart';
import '../../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../../widgets/settings/workspace_settings_widgets.dart';
import '../../home_workspace/workspace/config/workspace_cli_config_helpers.dart';
import '../../home_workspace/workspace/config/workspace_cli_effort_helpers.dart';

class OnboardingDefaultPresetStep extends StatefulWidget {
  const OnboardingDefaultPresetStep({super.key});

  @override
  State<OnboardingDefaultPresetStep> createState() =>
      _OnboardingDefaultPresetStepState();
}

class _OnboardingDefaultPresetStepState
    extends State<OnboardingDefaultPresetStep> {
  String? _presetId;
  late CliTool _cli;
  late String _providerId;
  late String _modelId;
  late String _effortId;

  @override
  void initState() {
    super.initState();
    _cli = CliTool.claude;
    _providerId = '';
    _modelId = '';
    _effortId = '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFromState());
  }

  List<CliPreset> get _presets =>
      context.read<CliPresetsCubit>().state.presets;

  List<AppProviderConfig> _providersForCli(CliTool cli) =>
      context.read<AppProviderCubit>().state.providersFor(cli);

  AppProviderConfig? _selectedProvider() {
    for (final provider in _providersForCli(_cli)) {
      if (provider.id == _providerId) return provider;
    }
    return null;
  }

  void _loadFieldsFromPreset(CliPreset preset) {
    _presetId = preset.id;
    _cli = preset.cli;
    _providerId = preset.provider;
    _modelId = preset.model;
    _effortId = preset.effort;
  }

  void _syncFromState() {
    if (!mounted) return;
    final presets = _presets;
    final personal = context.read<LaunchProfileCubit>().activePersonal;
    final activePresetId = personal?.activePresetId?.trim();
    CliPreset? initialPreset;
    if (activePresetId != null && activePresetId.isNotEmpty) {
      for (final preset in presets) {
        if (preset.id == activePresetId) {
          initialPreset = preset;
          break;
        }
      }
    }
    initialPreset ??= presets.firstOrNull;

    if (initialPreset != null) {
      _loadFieldsFromPreset(initialPreset);
    } else {
      _presetId = null;
      _cli = CliTool.claude;
      final appProvider = context.read<AppProviderCubit>();
      final providerId =
          appProvider.state.selectedProviderIdByCli[CliTool.claude]?.trim() ??
          '';
      final providers = _providersForCli(CliTool.claude);
      final provider = providers
          .where((p) => p.id == providerId)
          .firstOrNull ??
          providers.firstOrNull;
      _providerId = provider?.id ?? '';
      _modelId = provider?.defaultModel.trim() ?? '';
      _effortId = '';
    }
    setState(() {});
    if (_providerId.isNotEmpty) {
      unawaited(_applySelection());
    }
  }

  Future<void> _applySelection() async {
    if (!mounted) return;
    if (_providerId.trim().isEmpty) return;

    final l10n = context.l10n;
    final name = l10n.onboardingDefaultPresetDefaultName;
    final presetsCubit = context.read<CliPresetsCubit>();
    final launchCubit = context.read<LaunchProfileCubit>();
    final appProviderCubit = context.read<AppProviderCubit>();

    String presetId = _presetId ?? '';
    if (presetId.isNotEmpty) {
      await presetsCubit.updatePreset(
        id: presetId,
        name: name,
        cli: _cli,
        provider: _providerId,
        model: _modelId,
        effort: _effortId,
      );
    } else {
      final before = presetsCubit.state.presets.map((p) => p.id).toSet();
      await presetsCubit.addPreset(
        name: name,
        cli: _cli,
        provider: _providerId,
        model: _modelId,
        effort: _effortId,
      );
      CliPreset? created;
      for (final preset in presetsCubit.state.presets) {
        if (!before.contains(preset.id)) {
          created = preset;
          break;
        }
      }
      created ??= presetsCubit.state.presets
          .where((p) => p.name == name && p.cli == _cli)
          .firstOrNull;
      if (created == null) return;
      presetId = created.id;
      _presetId = presetId;
    }

    await OnboardingService.applyDefaultPreset(
      presetId: presetId,
      cliPresetsCubit: presetsCubit,
      launchProfileCubit: launchCubit,
      appProviderCubit: appProviderCubit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final dropdownDeco = AppDropdownDecorations.themed(context);
    final providers = _providersForCli(_cli);
    final selectedProvider = _selectedProvider();
    final hideModelPicker = workspaceCliHidesModelPicker(
      registry,
      _cli,
      selectedProvider,
    );
    final showEffortPicker = workspaceCliShowsEffortPicker(
      registry: registry,
      cli: _cli,
      provider: selectedProvider,
      model: _modelId,
    );

    if (providers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.onboardingDefaultPresetTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.onboardingDefaultPresetEmpty,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.onboardingDefaultPresetTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.onboardingDefaultPresetSubtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        SettingsSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsLabeledRow(
                title: l10n.teamCliLabel,
                trailing: SettingsCompactDropdown<String>(
                  value: _cli.value,
                  entries: [
                    for (final def in registry.launchable)
                      (def.id.value, cliDisplayName(def, l10n)),
                  ],
                  itemBuilder: (context, value) {
                    final cli = CliTool.decode(value);
                    final def = registry.tryGet(cli);
                    return Row(
                      children: [
                        CliBrandIcon(
                          cli: cli,
                          label: def != null
                              ? cliDisplayName(def, l10n)
                              : cli.value,
                          size: 20,
                          borderRadius: 5,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            def != null
                                ? cliDisplayName(def, l10n)
                                : cli.value,
                          ),
                        ),
                      ],
                    );
                  },
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _cli = CliTool.decode(value);
                      _providerId = '';
                      _modelId = '';
                      _effortId = '';
                    });
                    unawaited(_applySelection());
                  },
                ),
                showDividerBelow: true,
              ),
              SettingsLabeledRow(
                title: l10n.provider,
                trailing: SettingsCompactDropdown<String>(
                  value: _providerId.isNotEmpty
                      ? _providerId
                      : providers.first.id,
                  entries: [
                    for (final provider in providers)
                      (provider.id, provider.name),
                  ],
                  itemBuilder: providerDropdownItemBuilder(
                    providers: providers,
                    labelFor: (id) =>
                        providers
                            .where((p) => p.id == id)
                            .map((p) => p.name)
                            .firstOrNull ??
                        id,
                  ),
                  onChanged: (value) {
                    if (value == null) return;
                    final provider = providers
                        .where((p) => p.id == value)
                        .firstOrNull;
                    setState(() {
                      _providerId = value;
                      _modelId = provider?.defaultModel.trim() ?? '';
                      _effortId = '';
                    });
                    unawaited(_applySelection());
                  },
                ),
                showDividerBelow: !hideModelPicker || showEffortPicker,
              ),
              if (!hideModelPicker)
                SettingsLabeledStackedRow(
                  title: l10n.defaultModel,
                  subtitle: l10n.onboardingDefaultPresetModelHint,
                  body: selectedProvider == null
                      ? Text(
                          l10n.selectModel,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        )
                      : ProviderModelPickerField(
                          cli: _cli,
                          providerId: selectedProvider.id,
                          provider: selectedProvider,
                          value: _modelId,
                          hintText: l10n.selectModel,
                          decoration: dropdownDeco,
                          onChanged: (value) {
                            setState(() => _modelId = value);
                            unawaited(_applySelection());
                          },
                        ),
                  showDividerBelow: showEffortPicker,
                ),
              if (showEffortPicker)
                SettingsLabeledRow(
                  title: l10n.workspaceCliEffortLevel,
                  subtitle: l10n.workspaceCliEffortLevelSubtitle,
                  trailing: CliEffortPickerField(
                    cli: _cli,
                    value: _effortId,
                    provider: selectedProvider,
                    model: _modelId,
                    allowInherit: true,
                    inheritLabel: l10n.workspaceCliEffortInheritHint,
                    decoration: dropdownDeco,
                    onChanged: (value) {
                      setState(() => _effortId = value.trim());
                      unawaited(_applySelection());
                    },
                  ),
                  showDividerBelow: false,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
