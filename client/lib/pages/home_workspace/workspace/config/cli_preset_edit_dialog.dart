import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../cubits/app_provider_cubit.dart';
import '../../../../cubits/cli_presets_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/app_provider_config.dart';
import '../../../../models/cli_preset.dart';
import '../../../../services/cli/registry/cli_display_name.dart';
import '../../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../../widgets/app_dialog.dart';
import '../../../../widgets/app_provider/brand_dropdown_rows.dart';
import '../../../../widgets/app_provider/cli_effort_picker_field.dart';
import '../../../../widgets/app_provider/provider_model_picker_field.dart';
import '../../../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../../../widgets/dropdown/app_dropdown_field.dart';
import '../../../../widgets/settings/workspace_settings_widgets.dart';
import 'workspace_cli_config_helpers.dart';
import 'workspace_cli_effort_helpers.dart';

class CliPresetEditDialog extends StatefulWidget {
  const CliPresetEditDialog({this.existing, this.lockCli, super.key});

  /// If non-null, editing an existing preset.
  final CliPreset? existing;

  /// When non-null, the CLI dropdown is disabled and forced to this value.
  /// Used in native mode to lock presets to the team CLI.
  final CliTool? lockCli;

  bool get isEditing => existing != null;

  @override
  State<CliPresetEditDialog> createState() => _CliPresetEditDialogState();
}

class _CliPresetEditDialogState extends State<CliPresetEditDialog> {
  late final TextEditingController _nameCtl;
  late CliTool _cli;
  late String _providerId;
  late String _modelId;
  late String _effortId;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameCtl = TextEditingController(text: p?.name ?? '');
    _cli = widget.lockCli ?? p?.cli ?? CliTool.claude;
    _providerId = p?.provider ?? '';
    _modelId = p?.model ?? '';
    _effortId = p?.effort ?? '';
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  AppProviderConfig? _selectedProvider(Iterable<AppProviderConfig> providers) {
    for (final p in providers) {
      if (p.id == _providerId) return p;
    }
    return null;
  }

  Future<void> _save() async {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) return;
    if (_providerId.trim().isEmpty) return;

    final cubit = context.read<CliPresetsCubit>();
    if (widget.isEditing) {
      await cubit.updatePreset(
        id: widget.existing!.id,
        name: name,
        cli: _cli,
        provider: _providerId,
        model: _modelId,
        effort: _effortId,
      );
    } else {
      await cubit.addPreset(
        name: name,
        cli: _cli,
        provider: _providerId,
        model: _modelId,
        effort: _effortId,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final dropdownDeco = AppDropdownDecorations.themed(context);
    final providers = context
        .watch<AppProviderCubit>()
        .state
        .providersFor(_cli)
        .toList(growable: false);
    final selectedProvider = _selectedProvider(providers);
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

    return AppDialog(
      maxWidth: 640,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(
            title: widget.isEditing
                ? l10n.workspaceCliEditPresetTitle
                : l10n.workspaceCliAddPresetTitle,
          ),
          const SizedBox(height: 16),
          SettingsLabeledStackedRow(
            title: l10n.workspaceCliPresetNameLabel,
            body: TextField(
              controller: _nameCtl,
              decoration: const InputDecoration(),
              autofocus: !widget.isEditing,
            ),
            showDividerBelow: true,
          ),
          SettingsLabeledRow(
            title: l10n.teamCliLabel,
            trailing: AppDropdownField<String>(
              items: [for (final def in registry.launchable) def.id.value],
              initialItem: _cli.value,
              decoration: dropdownDeco,
              enabled: widget.lockCli == null,
              onChanged: (value) {
                if (value == null || widget.lockCli != null) return;
                setState(() {
                  _cli = CliTool.decode(value);
                  _providerId = '';
                  _modelId = '';
                  _effortId = '';
                });
              },
              itemBuilder: (context, value) => cliDropdownRow(
                context,
                cli: CliTool.decode(value),
                label: cliDisplayName(
                  registry.tryGet(CliTool.decode(value))!,
                  l10n,
                ),
                registry: registry,
              ),
            ),
            showDividerBelow: true,
          ),
          SettingsLabeledRow(
            title: l10n.provider,
            trailing: AppDropdownField<String>(
              key: ValueKey('preset-provider-$_cli-$_providerId'),
              items: providers.map((p) => p.id).toList()..sort(),
              initialItem: _providerId.isEmpty ? null : _providerId,
              hintText: l10n.selectProvider,
              decoration: dropdownDeco,
              onChanged: (value) {
                setState(() {
                  _providerId = value ?? '';
                  _modelId = '';
                  _effortId = '';
                });
              },
              itemBuilder: providerDropdownItemBuilder(
                providers: providers,
                labelFor: (value) {
                  for (final p in providers) {
                    if (p.id == value) return p.name;
                  }
                  return value;
                },
              ),
            ),
            showDividerBelow: hideModelPicker || showEffortPicker,
          ),
          if (!hideModelPicker)
            SettingsLabeledRow(
              title: l10n.model,
              trailing: ProviderModelPickerField(
                key: ValueKey('preset-model-$_providerId-$_modelId'),
                cli: _cli,
                providerId: _providerId,
                provider: selectedProvider,
                value: _modelId,
                hintText: l10n.selectModel,
                decoration: dropdownDeco,
                onChanged: (value) => setState(() {
                  _modelId = value.trim();
                  if (!workspaceCliShowsEffortPicker(
                    registry: registry,
                    cli: _cli,
                    provider: selectedProvider,
                    model: _modelId,
                  )) {
                    _effortId = '';
                  }
                }),
              ),
              showDividerBelow: showEffortPicker,
            ),
          if (showEffortPicker)
            SettingsLabeledRow(
              title: l10n.workspaceCliEffortLevel,
              subtitle: l10n.workspaceCliEffortLevelSubtitle,
              trailing: CliEffortPickerField(
                key: ValueKey(
                  'preset-effort-$_providerId-$_modelId-$_effortId',
                ),
                cli: _cli,
                value: _effortId,
                provider: selectedProvider,
                model: _modelId,
                allowInherit: true,
                inheritLabel: l10n.workspaceCliEffortInheritHint,
                decoration: dropdownDeco,
                onChanged: (value) => setState(() => _effortId = value.trim()),
              ),
              showDividerBelow: false,
            ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: _providerId.trim().isEmpty ? null : _save,
                child: Text(l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
