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
import '../../../theme/app_text_styles.dart';
import 'onboarding_step_scaffold.dart';

class OnboardingDefaultPresetStep extends StatefulWidget {
  const OnboardingDefaultPresetStep({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<OnboardingDefaultPresetStep> createState() =>
      OnboardingDefaultPresetStepState();
}

class OnboardingDefaultPresetStepState
    extends State<OnboardingDefaultPresetStep> {
  String? _presetId;
  late CliTool _cli;
  late String _providerId;
  late String _modelId;
  late String _effortId;
  var _hasSyncedFromState = false;

  @override
  void initState() {
    super.initState();
    _cli = CliTool.claude;
    _providerId = '';
    _modelId = '';
    _effortId = '';
    if (widget.isActive) {
      _scheduleSyncFromState();
    }
  }

  @override
  void didUpdateWidget(OnboardingDefaultPresetStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _scheduleSyncFromState();
    }
  }

  void _scheduleSyncFromState() {
    if (_hasSyncedFromState) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFromState());
  }

  List<CliPreset> get _presets => context.read<CliPresetsCubit>().state.presets;

  List<AppProviderConfig> _providersForCli(CliTool cli) =>
      context.read<AppProviderCubit>().state.providersFor(cli);

  AppProviderConfig? _selectedProvider() {
    final providers = _providersForCli(_cli);
    if (providers.isEmpty) return null;
    for (final provider in providers) {
      if (provider.id == _providerId) return provider;
    }
    return providers.first;
  }

  /// Keeps [_providerId]/[_modelId] aligned with an available provider for [cli].
  void _selectProviderForCli(
    CliTool cli, {
    String preferredProviderId = '',
    String preferredModelId = '',
  }) {
    final providers = _providersForCli(cli);
    final preferred = preferredProviderId.trim();
    final provider = preferred.isEmpty
        ? providers.firstOrNull
        : providers.where((p) => p.id == preferred).firstOrNull ??
              providers.firstOrNull;
    _providerId = provider?.id ?? '';
    final preferredModel = preferredModelId.trim();
    if (preferredModel.isNotEmpty && provider != null) {
      _modelId = preferredModel;
    } else {
      _modelId = provider?.defaultModel.trim() ?? '';
    }
  }

  void _loadFieldsFromPreset(CliPreset preset) {
    _presetId = preset.id;
    _cli = preset.cli;
    _effortId = preset.effort;
    _selectProviderForCli(
      preset.cli,
      preferredProviderId: preset.provider,
      preferredModelId: preset.model,
    );
  }

  void _syncFromState() {
    if (!mounted || _hasSyncedFromState) return;
    _hasSyncedFromState = true;
    final presets = _presets;
    CliPreset? initialPreset = presets.firstOrNull;

    if (initialPreset != null) {
      _loadFieldsFromPreset(initialPreset);
    } else {
      _presetId = null;
      _cli = CliTool.claude;
      _effortId = '';
      final appProvider = context.read<AppProviderCubit>();
      final preferred =
          appProvider.state.selectedProviderIdByCli[CliTool.claude]?.trim() ??
          '';
      _selectProviderForCli(CliTool.claude, preferredProviderId: preferred);
    }
    setState(() {});
  }

  Future<void> commitSelection() async {
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

    final cliPicker = SettingsLabeledRow(
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
                label: def != null ? cliDisplayName(def, l10n) : cli.value,
                size: 20,
                borderRadius: 5,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  def != null ? cliDisplayName(def, l10n) : cli.value,
                ),
              ),
            ],
          );
        },
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            _cli = CliTool.decode(value);
            _effortId = '';
            _selectProviderForCli(_cli);
          });
        },
      ),
      // Keep a divider when provider fields follow; omit when empty.
      showDividerBelow: providers.isNotEmpty,
    );

    return OnboardingStepScaffold(
      title: l10n.onboardingDefaultPresetTitle,
      subtitle: providers.isEmpty
          ? l10n.onboardingDefaultPresetEmpty
          : l10n.onboardingDefaultPresetSubtitle,
      body: SettingsSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cliPicker,
            if (providers.isNotEmpty) ...[
              SettingsLabeledRow(
                title: l10n.provider,
                trailing: SettingsCompactDropdown<String>(
                  value: selectedProvider?.id ?? providers.first.id,
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
                    setState(() {
                      _effortId = '';
                      _selectProviderForCli(
                        _cli,
                        preferredProviderId: value,
                      );
                    });
                  },
                ),
                showDividerBelow: !hideModelPicker || showEffortPicker,
              ),
              if (!hideModelPicker)
                SettingsLabeledRow(
                  title: l10n.defaultModel,
                  trailing: selectedProvider == null
                      ? Text(
                          l10n.selectModel,
                          style: AppTextStyles.of(context).md.copyWith(
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
                          },
                        ),
                  showDividerBelow: showEffortPicker,
                ),
              if (showEffortPicker)
                SettingsLabeledRow(
                  title: l10n.workspaceCliEffortLevel,
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
                    },
                  ),
                  showDividerBelow: false,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
